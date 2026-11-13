local MS = _G.MS
MS.Active = MS.Active or {}
-- Words for Contrat cards, states and the announce lines. The data stays locale-neutral (ids,
-- verdicts, seconds); only this module turns it into text, in the reader's language.
local T = {}
MS.Active.ContractText = T

local function L() return MS.L end

function T:Duration(seconds)
    if type(seconds) ~= "number" or seconds < 0 then return L().CONTRACT_DURATION_UNKNOWN end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return string.format(L().CONTRACT_DURATION_M, minutes) end
    return string.format(L().CONTRACT_DURATION_HM, math.floor(minutes / 60), minutes % 60)
end

-- Short limit for a card title: "1 h 30", "45 min".
function T:Limit(seconds)
    local minutes = math.floor((seconds or 0) / 60)
    if minutes < 60 then return string.format(L().CONTRACT_DURATION_M, minutes) end
    if minutes % 60 == 0 then return string.format(L().CONTRACT_DURATION_H, minutes / 60) end
    return string.format(L().CONTRACT_DURATION_HM, math.floor(minutes / 60), minutes % 60)
end

function T:Title(id, param)
    if id == "TIME_LIMIT" then return string.format(L().CONTRACT_CARD_TIME_LIMIT_TITLE, self:Limit(param)) end
    return L()["CONTRACT_CARD_" .. id .. "_TITLE"] or id
end

function T:Description(id, mode)
    if mode == "GROUP" and L()["CONTRACT_CARD_" .. id .. "_DESC_GROUP"] then return L()["CONTRACT_CARD_" .. id .. "_DESC_GROUP"] end
    return L()["CONTRACT_CARD_" .. id .. "_DESC"] or ""
end

-- "OBSERVÉ", "À L'ESSAI" (observed, never seen working on this build yet) or "SUR L'HONNEUR".
function T:ModeTag(id, mode, caps)
    local card = MS.Active.ContractCatalog.Get(id)
    if not card then return "" end
    if card.mode == "HONOR" then return L().CONTRACT_TAG_HONOR end
    if MS.Active.ContractEngine:OnTrial(id, mode, caps) then return L().CONTRACT_TAG_TRIAL end
    return L().CONTRACT_TAG_OBSERVED
end

-- Live state of a running rule. trial: its card is on trial, so it can only end ROMPU or NON
-- VÉRIFIABLE: it never reads "holding".
function T:LiveState(rule, trial)
    if rule.status == "BROKEN" then return L().CONTRACT_VERDICT_BROKEN, "critical" end
    if rule.status == "HONOR" then return L().CONTRACT_VERDICT_HONOR, "textSecondary" end
    if rule.uncertain then return L().CONTRACT_VERDICT_UNVERIFIABLE, "warning" end
    if trial then return L().CONTRACT_STATE_TRIAL, "warning" end
    return L().CONTRACT_STATE_WATCHING, "success"
end

T.verdictColors = { KEPT = "success", KEPT_HONOR = "success", BROKEN = "critical", DECLARED_BROKEN = "critical", UNVERIFIABLE = "warning",
    HONOR = "textSecondary", ABANDONED = "muted" }

function T:Verdict(verdict)
    return L()["CONTRACT_VERDICT_" .. tostring(verdict)] or tostring(verdict), self.verdictColors[verdict] or "textPrimary"
end

-- Why: "Kesh est mort", "jamais observé sur cette version du jeu"...
function T:Reason(reason, who)
    if not reason then return nil end
    local text = L()["CONTRACT_REASON_" .. reason]
    if not text then return nil end
    if text:find("%%s") then
        -- Streamer mode: who broke a rule stays out of sight.
        local mode = _G.MS and _G.MS.BroadcastMode
        if not who or (mode and mode:IsOn()) then return L()["CONTRACT_REASON_" .. reason .. "_ANON"] end
        return string.format(text, who)
    end
    return text
end

function T:ContractTitle(goal)
    if goal.goal == "LEVEL" or goal.kind == "LEVEL" then return string.format(L().CONTRACT_TITLE_LEVEL, goal.target or 0) end
    return goal.instance and string.format(L().CONTRACT_TITLE_DUNGEON_NAMED, goal.instance) or L().CONTRACT_TITLE_DUNGEON
end

local function Join(parts) return table.concat(parts, L().CONTRACT_LINE_SEPARATOR) end

local function Titles(cards, mode, level)
    local titles = {}
    for _, card in ipairs(cards) do
        local id = type(card) == "table" and card.id or card
        local param = type(card) == "table" and card.param or nil
        if id == "TIME_LIMIT" and not param then param = MS.Active.ContractCatalog.TimeLimit(mode, level) end
        titles[#titles + 1] = T:Title(id, param)
    end
    return Join(titles)
end

function T:StartLine(contract)
    return string.format(L().CONTRACT_ANNOUNCE_START, Titles(contract.cards, contract.mode))
end

-- Before the signature: the rules put to the group.
function T:ProposalLine(cards, mode, level)
    return string.format(L().CONTRACT_ANNOUNCE_PROPOSAL, Titles(cards, mode, level))
end

-- "Zéro mort · En moins de 1 h · Pas de potion": what the player is about to sign.
function T:Summary(cards, mode, level) return Titles(cards, mode, level) end

-- Twitch counts characters, not bytes: cut a UTF-8 string to that many characters.
function T.Cut(text, limit)
    local count, stop = 0, #text
    for position in text:gmatch("()[^\128-\191]") do
        count = count + 1
        if count > limit then stop = position - 1; break end
    end
    return (text:sub(1, stop):gsub(" +$", ""))
end

T.pollLetters = { "A", "B", "C", "D", "E" }
T.pollTitleLimit, T.pollChoiceLimit = 60, 25

-- The vote, as the streamer retypes it in a Twitch poll: a title, then one short choice per
-- Contrat, each named after a card no other choice uses when there is one.
function T:PollChoices(options)
    local choices, named = {}, {}
    for index, cards in ipairs(options) do
        local pick = cards[1]
        for _, card in ipairs(cards) do
            if not named[card.id] then pick = card; break end
        end
        if pick then named[pick.id] = true end
        local title = pick and self:Title(pick.id, pick.param) or ""
        choices[index] = T.Cut(string.format(L().CONTRACT_LIVE_POLL_CHOICE, T.pollLetters[index], title), T.pollChoiceLimit)
    end
    return choices
end

function T:PollText(options)
    local lines = { T.Cut(L().CONTRACT_LIVE_POLL_TITLE, T.pollTitleLimit) }
    for _, choice in ipairs(self:PollChoices(options)) do lines[#lines + 1] = choice end
    return table.concat(lines, "\n")
end

-- The result line, shortened to fit the chat box: details first, then the bare verdict.
function T:ResultLine(result, limit)
    local verdict = self:Verdict(result.verdict)
    local duration = self:Duration(result.duration)
    local details = {}
    for _, rule in ipairs(result.rules) do
        details[#details + 1] = string.format(L().CONTRACT_ANNOUNCE_RULE, self:Title(rule.card, rule.param), (self:Verdict(rule.verdict)))
    end
    local full = string.format(L().CONTRACT_ANNOUNCE_RESULT, verdict, duration, Join(details))
    if #full <= (limit or 255) then return full end
    return string.format(L().CONTRACT_ANNOUNCE_RESULT_SHORT, verdict, duration)
end
