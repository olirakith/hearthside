local MS = _G.MS
MS.Ink = MS.Ink or {}
-- L'Encre des Royaumes: a tale written by a player, as stored and as decoded from a seal. Pure.
-- Everything here may come from someone else's bytes: every field is rebuilt from known keys,
-- cleaned and bounded, and a tale that cannot be made whole is refused.
--
-- tale = { id (8 hex), version (1-65535), createdAt, author, title, mode, order, intro, ending,
--          pages = { { key (4 hex), title, hint, text, trigger, when? } } }
-- trigger = { kind = "PLACE", mapID, x, y, radius } | { kind = "ANSWER", hashes = { 8 hex... } }
--         | { kind = "ITEM", itemID, count } | { kind = "NPC", npcID, name }
--         | { kind = "EMOTE", token, npcID?, name?, mapID?, x?, y?, radius? }
--         | { kind = "KILL", npcID, name, count }
-- when = { from?, to? (hours of the realm, from included, to excluded), level? }: what else it takes.
-- name is the creature's, in the language of the author's game.
local Tale = {
    maxPages = 30,
    titleBytes = 64, authorBytes = 64, hintBytes = 300, textBytes = 600, introBytes = 400,
    maxLines = 8, maxAnswers = 4, answerBytes = 40,
    minRadius = 3, maxRadius = 200, defaultRadius = 8, maxItemCount = 200,
    nameBytes = 60, maxKills = 100, defaultKills = 5, maxLevel = 80,
}
MS.Ink.Tale = Tale
Tale.modes = { NOTES = true, HUNT = true, QUEST = true }
Tale.orders = { FREE = true, SEQUENCE = true }
Tale.kinds = { "PLACE", "ANSWER", "ITEM", "NPC", "EMOTE", "KILL" }
Tale.triggers = {}
for _, kind in ipairs(Tale.kinds) do Tale.triggers[kind] = true end

local function Text() return MS.Active.Text end
local function Num(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function Hex(value, length) return type(value) == "string" and #value == length and value:find("^%x+$") ~= nil end

function Tale.Line(value, maxBytes) return Text().CleanLine(value, maxBytes) end

-- Several lines: each one cleaned, at most maxLines, blank runs collapsed to one blank line.
-- Returns nil when nothing readable is left.
function Tale.Block(value, maxBytes)
    if type(value) ~= "string" then return nil end
    maxBytes = maxBytes or Tale.textBytes
    local lines, blank = {}, false
    for raw in (value:gsub("\r\n?", "\n") .. "\n"):gmatch("([^\n]*)\n") do
        local line = Text().CleanLine(raw, maxBytes)
        if line then
            if blank and #lines > 0 then lines[#lines + 1] = "" end
            lines[#lines + 1], blank = line, false
        else
            blank = true
        end
        if #lines >= Tale.maxLines then break end
    end
    if #lines == 0 then return nil end
    return Text().Truncate(table.concat(lines, "\n"), maxBytes)
end

-- Answers compare without case, accents, punctuation or extra spaces: "L'Épée " = "lepee".
local FOLD = {
    ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a", ["Á"] = "a",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["î"] = "i", ["ï"] = "i", ["í"] = "i", ["Î"] = "i", ["Ï"] = "i", ["Í"] = "i",
    ["ô"] = "o", ["ö"] = "o", ["ó"] = "o", ["Ô"] = "o", ["Ö"] = "o", ["Ó"] = "o",
    ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u", ["Ú"] = "u",
    ["ç"] = "c", ["Ç"] = "c", ["ñ"] = "n", ["Ñ"] = "n", ["ÿ"] = "y", ["œ"] = "oe", ["Œ"] = "oe", ["æ"] = "ae", ["Æ"] = "ae",
    ["ß"] = "ss",
}

function Tale.NormalizeAnswer(value)
    local line = Text().CleanLine(value, Tale.answerBytes * 2)
    if not line then return nil end
    line = line:gsub("[\195\197][\128-\191]", function(pair) return FOLD[pair] end)
    line = line:gsub("[A-Z]", string.lower)
    -- Apostrophes and hyphens join words ("l'epee" = "lepee"); other punctuation becomes a space.
    line = line:gsub("['%-]", ""):gsub("[^a-z0-9\128-\255]", " ")
    line = line:gsub("  +", " "):match("^ *(.-) *$")
    if line == "" then return nil end
    return line
end

-- The fingerprint of one accepted answer, salted by its tale and page so the same word gives
-- different fingerprints elsewhere. Anti-spoil only: a short answer can still be guessed.
function Tale.AnswerHash(taleId, pageKey, value)
    local normalized = Tale.NormalizeAnswer(value)
    if not normalized then return nil end
    return MS.Community.Bytes.Crc32(taleId .. ":" .. pageKey .. ":" .. normalized)
end

local function Integer(value, minimum, maximum)
    return Num(value) and value % 1 == 0 and value >= minimum and value <= maximum
end

local function Creature(raw)
    local name = Integer(raw.npcID, 1, 4294967295) and Tale.Line(raw.name, Tale.nameBytes)
    if name then return raw.npcID, name end
end

-- The other conditions of a page, or nil when there is none.
function Tale.SanitizeWhen(raw)
    if type(raw) ~= "table" then return nil end
    local when = {}
    if Integer(raw.from, 0, 23) and Integer(raw.to, 0, 23) and raw.from ~= raw.to then when.from, when.to = raw.from, raw.to end
    if Integer(raw.level, 2, Tale.maxLevel) then when.level = raw.level end
    return next(when) and when or nil
end

-- Whether an hour is in a range that may cross midnight.
function Tale.InHours(hour, from, to)
    if from < to then return hour >= from and hour < to end
    return hour >= from or hour < to
end

-- HOUR | LEVEL: what a condition still asks, or nil when it is met. An unread value is not met.
function Tale.Waiting(when, hour, level)
    if not when then return nil end
    if when.level and not (Num(level) and level >= when.level) then return "LEVEL" end
    if when.from and not (Num(hour) and Tale.InHours(hour, when.from, when.to)) then return "HOUR" end
end

-- What older versions of Hearthside cannot read.
function Tale.Extended(tale)
    for _, page in ipairs(tale.pages) do
        local kind = page.trigger.kind
        if page.when or kind == "NPC" or kind == "EMOTE" or kind == "KILL" then return true end
    end
    return false
end

function Tale.SanitizeTrigger(raw)
    if type(raw) ~= "table" or not Tale.triggers[raw.kind] then return nil end
    if raw.kind == "PLACE" then
        if not Num(raw.mapID) or raw.mapID < 1 or raw.mapID > 65535 or raw.mapID % 1 ~= 0 then return nil end
        if not Num(raw.x) or not Num(raw.y) or raw.x < 0 or raw.x > 1 or raw.y < 0 or raw.y > 1 then return nil end
        local radius = Num(raw.radius) and math.floor(raw.radius) or Tale.defaultRadius
        radius = math.max(Tale.minRadius, math.min(Tale.maxRadius, radius))
        return { kind = "PLACE", mapID = raw.mapID, x = raw.x, y = raw.y, radius = radius }
    elseif raw.kind == "ANSWER" then
        local hashes, seen = {}, {}
        for _, hash in ipairs(type(raw.hashes) == "table" and raw.hashes or {}) do
            if Hex(hash, 8) and not seen[hash:lower()] and #hashes < Tale.maxAnswers then
                seen[hash:lower()] = true
                hashes[#hashes + 1] = hash:lower()
            end
        end
        if #hashes == 0 then return nil end
        return { kind = "ANSWER", hashes = hashes }
    elseif raw.kind == "NPC" or raw.kind == "KILL" then
        local npcID, name = Creature(raw)
        if not npcID then return nil end
        local trigger = { kind = raw.kind, npcID = npcID, name = name }
        if raw.kind == "KILL" then
            local count = Num(raw.count) and math.floor(raw.count) or Tale.defaultKills
            trigger.count = math.max(1, math.min(Tale.maxKills, count))
        end
        return trigger
    elseif raw.kind == "EMOTE" then
        if type(raw.token) ~= "string" or #raw.token > 24 or not raw.token:find("^%u[%u%d_]*$") then return nil end
        local trigger = { kind = "EMOTE", token = raw.token }
        trigger.npcID, trigger.name = Creature(raw)
        local place = raw.mapID and Tale.SanitizeTrigger({ kind = "PLACE", mapID = raw.mapID, x = raw.x, y = raw.y, radius = raw.radius })
        -- A target or a place that cannot be read whole makes another page: the trigger is refused.
        if (raw.npcID and not trigger.npcID) or (raw.mapID and not place) then return nil end
        if place then trigger.mapID, trigger.x, trigger.y, trigger.radius = place.mapID, place.x, place.y, place.radius end
        return trigger
    else
        if not Num(raw.itemID) or raw.itemID < 1 or raw.itemID > 4294967295 or raw.itemID % 1 ~= 0 then return nil end
        local count = Num(raw.count) and math.floor(raw.count) or 1
        return { kind = "ITEM", itemID = raw.itemID, count = math.max(1, math.min(Tale.maxItemCount, count)) }
    end
end

-- A page needs a key, a title and a trigger; its hint and text may be empty.
function Tale.SanitizePage(raw)
    if type(raw) ~= "table" or not Hex(raw.key, 4) then return nil end
    local trigger = Tale.SanitizeTrigger(raw.trigger)
    local title = Tale.Line(raw.title, Tale.titleBytes)
    if not trigger or not title then return nil end
    return { key = raw.key:lower(), title = title, hint = Tale.Block(raw.hint, Tale.hintBytes),
        text = Tale.Block(raw.text, Tale.textBytes), trigger = trigger, when = Tale.SanitizeWhen(raw.when) }
end

-- Returns a clean copy, or nil and a reason. strict refuses a tale with any dropped page (decoded
-- seals); stored tales are already whole.
function Tale.Sanitize(raw, strict)
    if type(raw) ~= "table" then return nil, "INVALID" end
    if not Hex(raw.id, 8) then return nil, "INVALID" end
    if not Num(raw.version) or raw.version < 1 or raw.version > 65535 or raw.version % 1 ~= 0 then return nil, "INVALID" end
    if not Tale.modes[raw.mode] or not Tale.orders[raw.order] then return nil, "INVALID" end
    local tale = {
        id = raw.id:lower(), version = raw.version, mode = raw.mode, order = raw.order,
        createdAt = Num(raw.createdAt) and math.floor(raw.createdAt) or nil,
        author = Tale.Line(raw.author, Tale.authorBytes), title = Tale.Line(raw.title, Tale.titleBytes),
        intro = Tale.Block(raw.intro, Tale.introBytes), ending = Tale.Block(raw.ending, Tale.introBytes),
        pages = {},
    }
    if not tale.author or not tale.title then return nil, "INVALID" end
    local source, keys = type(raw.pages) == "table" and raw.pages or {}, {}
    for index = 1, math.min(#source, Tale.maxPages) do
        local page = Tale.SanitizePage(source[index])
        if page and not keys[page.key] then
            keys[page.key] = true
            tale.pages[#tale.pages + 1] = page
        elseif strict then
            return nil, "INVALID"
        end
    end
    if strict and #source > Tale.maxPages then return nil, "INVALID" end
    if #tale.pages == 0 then return nil, "EMPTY" end
    return tale
end

function Tale.Page(tale, key)
    for index, page in ipairs(tale.pages) do if page.key == key then return page, index end end
end
