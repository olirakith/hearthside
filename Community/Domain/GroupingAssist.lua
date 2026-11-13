local MS = _G.MS
MS.Community = MS.Community or {}
-- Quest social actions: Journey prepares one question about the PLAYER and their quest (quest,
-- class, level, where they are), phrased the way a player would type it. Never about another
-- player, never a criterion, never sent automatically, no state kept.
local GA = { chatLimit = 255, placeLimit = 40 }
MS.Community.GroupingAssist = GA

GA.FACT_KEYS = { SUGGESTED_GROUP = "COMMUNITY_ASK_FACT_GROUP", TAG_GROUP = "COMMUNITY_ASK_FACT_GROUP",
    TAG_DUNGEON = "COMMUNITY_ASK_FACT_DUNGEON", TAG_RAID = "COMMUNITY_ASK_FACT_RAID", TAG_HEROIC = "COMMUNITY_ASK_FACT_DUNGEON" }

local function Clean(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("[%z\1-\31|]", ""):match("^[ \t]*(.-)[ \t]*$")
    return value ~= "" and value or nil
end

-- Where the player is, for the sentence. The locales introduce it with a word that never
-- agrees with the name ("vers", "near"), so no article is ever guessed. The sub-zone first, then
-- the zone; a name too long or without a letter would read badly and is left out.
function GA.Place(subzone, zone)
    for _, value in ipairs({ Clean(subzone) or false, Clean(zone) or false }) do
        if value and #value <= GA.placeLimit and value:find("[A-Za-z\192-\255]") then return value end
    end
    return nil
end

-- Most natural first: "Hunter 10, I'm near X.", then "Hunter 10 here.", then the bare question.
local function Format(L, quest, class, level, place)
    if class and level and place then return string.format(L.COMMUNITY_SOCIAL_FIND_TEXT, quest, class, level, place) end
    if class and level then return string.format(L.COMMUNITY_SOCIAL_FIND_TEXT_NOPLACE, quest, class, level) end
    return string.format(L.COMMUNITY_SOCIAL_FIND_TEXT_MINIMAL, quest)
end

-- facts: { title, link, className, level, place, zone }. link is the client's own quest
-- hyperlink (already validated by the adapter); without it the plain title is used.
-- Returns the text and "NATIVE" or "TITLE", or nil.
function GA.Compose(L, facts)
    local title = Clean(facts.title)
    if not title then return nil end
    local class, place = Clean(facts.className), GA.Place(facts.place, facts.zone)
    local level = type(facts.level) == "number" and facts.level >= 1 and math.floor(facts.level) or nil
    for _, quest in ipairs(type(facts.link) == "string" and { facts.link, title } or { title }) do
        -- A sentence too long for the chat line first drops the place, never the quest.
        local text = Format(L, quest, class, level, place)
        if #text > GA.chatLimit and place then text = Format(L, quest, class, level, nil) end
        if #text <= GA.chatLimit then return text, quest == title and "TITLE" or "NATIVE" end
    end
    -- Never cut inside a UTF-8 character: drop the last, possibly partial, one.
    local text = string.format(L.COMMUNITY_SOCIAL_FIND_TEXT_MINIMAL, title):sub(1, GA.chatLimit):gsub("[\192-\255][\128-\191]*$", "")
    return text, "TITLE"
end

function GA.FactLine(L, fact, size)
    local key = GA.FACT_KEYS[fact]
    if not key then return nil end
    if fact == "SUGGESTED_GROUP" and type(size) == "number" and size > 1 then
        return string.format(L.COMMUNITY_ASK_FACT_SIZE, math.floor(size))
    end
    return L[key]
end
