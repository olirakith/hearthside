local MS = _G.MS
MS.Active = MS.Active or {}
-- Poster codes: what the Companion needs to draw a finished Contrat or a found seal, written in the
-- player's language. "AJP1:" + base64. The player copies it by hand, so the Companion never reads
-- SavedVariables. Layout documented in the Companion: src/poster/mod.rs.
local A = MS.Active
local Code = { prefix = "AJP1:", version = 1, lineBytes = 120, maxNames = 8, maxRules = 3 }
A.PosterCode = Code

local KINDS = { CONTRACT = 1, SEAL = 2 }
local STATES = { KEPT = 1, KEPT_HONOR = 1, BROKEN = 2, DECLARED_BROKEN = 2, HONOR = 3, UNVERIFIABLE = 4 }

local char, floor = string.char, math.floor

local function Bytes() return MS.Community.Bytes end

local function U32(value)
    return char(floor(value / 16777216) % 256, floor(value / 65536) % 256, floor(value / 256) % 256, value % 256)
end

local function Line(value)
    local line = A.Text.CleanLine(value, Code.lineBytes) or ""
    return char(#line) .. line
end

local function Seed(id) return tonumber(Bytes().Crc32(tostring(id)), 16) end

-- poster: { kind, seed, title, date, detail, markTop, markMain, quote, names = {}, rules = { { state, title, stamp } } }
function Code.Encode(poster)
    local parts = { char(Code.version), char(KINDS[poster.kind]), U32(poster.seed) }
    for _, field in ipairs({ "title", "date", "detail", "markTop", "markMain", "quote" }) do
        parts[#parts + 1] = Line(poster[field])
    end
    local names, rules = poster.names or {}, poster.rules or {}
    local nameCount, ruleCount = math.min(#names, Code.maxNames), math.min(#rules, Code.maxRules)
    parts[#parts + 1] = char(nameCount)
    for index = 1, nameCount do parts[#parts + 1] = Line(names[index]) end
    parts[#parts + 1] = char(ruleCount)
    for index = 1, ruleCount do
        local rule = rules[index]
        parts[#parts + 1] = char(rule.state) .. Line(rule.title) .. Line(rule.stamp)
    end
    local body = table.concat(parts)
    return Code.prefix .. Bytes().Base64Encode(body .. U32(tonumber(Bytes().Crc32(body), 16)))
end

-- A rule that was not broken counts, honor included: its stamp still says what it is.
function Code.ForContract(result)
    local L, T = MS.L, A.ContractText
    local lines = A.Credits:ForContract(result)
    local kept, rules, names = 0, {}, {}
    for index, rule in ipairs(result.rules) do
        local state = STATES[rule.verdict] or STATES.UNVERIFIABLE
        if state ~= STATES.BROKEN then kept = kept + 1 end
        rules[index] = { state = state, title = lines.rules[index].title, stamp = lines.rules[index].stamp }
    end
    local seen = {}
    local function Add(name)
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    Add(result.character and result.character.name)
    for _, name in ipairs(result.group and result.group.names or {}) do Add(name) end
    local duration = T:Duration(result.duration)
    return {
        kind = "CONTRACT", seed = Seed(result.id), title = lines.title,
        date = A.Kit.Date(result.endedAt) .. " " .. date("%Y", result.endedAt),
        detail = #names > 1 and string.format(L.POSTER_TOGETHER, duration) or duration,
        markTop = L.POSTER_MARK_CONTRACT, markMain = kept .. "/" .. #result.rules,
        names = names, rules = rules,
    }
end

-- The reader comes first: "Masquer les autres joueurs" keeps only the first name.
function Code.ForSeal(seal)
    local L = MS.L
    local lines = A.Credits:ForSeal(seal)
    local names = {}
    local reader = A.identity and A.identity.firstName
    if reader then names[1] = string.format(L.POSTER_SEAL_FOR, reader) end
    names[#names + 1] = string.format(L.CREDITS_SEAL_FROM, seal.author:match("^[^%-]+") or seal.author)
    return {
        kind = "SEAL", seed = Seed(seal.id), title = lines.title, detail = lines.sub,
        markTop = L.POSTER_MARK_SEAL, markMain = L.POSTER_MARK_FOUND, quote = lines.quote, names = names,
    }
end
