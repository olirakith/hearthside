local MS = _G.MS
MS.Community = MS.Community or {}
-- Reads what the game itself says about the player's own quests: "designed for several".
-- Never guesses an intention, never reads another player's quests.
local Q = { groupTags = { [1] = "TAG_GROUP", [81] = "TAG_DUNGEON", [62] = "TAG_RAID", [85] = "TAG_HEROIC" } }
MS.Community.QuestFacts = Q

-- pcall + secret-value filtering (GetQuestLogTitle needs ten returns; the filter keeps eight
-- through Community.Call, so the ninth, the quest ID, is filtered here as well).
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j = pcall(fn, ...)
    if not ok then return nil end
    local R = MS.Community.Readable
    return R(a), R(b), R(c), R(d), R(e), R(f), R(g), R(h), R(i), R(j)
end

local function Number(value) return type(value) == "number" and value == value and value or nil end

-- Title, suggested group size and log index of a quest in the player's own log, or nil.
function Q:LogEntry(questID)
    if not Number(questID) or questID <= 0 then return nil end
    local log = _G.C_QuestLog
    local title, suggested, logIndex
    if type(log) == "table" and type(log.GetLogIndexForQuestID) == "function" then
        local index = Call(log.GetLogIndexForQuestID, questID)
        local info = index and Call(log.GetInfo, index)
        if type(info) == "table" and info.questID == questID then
            title, suggested, logIndex = info.title, Number(info.suggestedGroup), Number(index)
        end
    end
    if not title and type(_G.GetNumQuestLogEntries) == "function" and type(_G.GetQuestLogTitle) == "function" then
        local count = Number(Call(_G.GetNumQuestLogEntries)) or 0
        for index = 1, math.min(count, 200) do
            local name, _, _, size, isHeader, _, _, _, id = Call(_G.GetQuestLogTitle, index)
            if id == questID and not isHeader then title, suggested, logIndex = name, Number(size), index; break end
        end
    end
    if type(title) ~= "string" or title == "" then return nil end
    return title, suggested, logIndex
end

-- Returns title, fact ("SUGGESTED_GROUP" / "TAG_*") and the suggested size, or nil when the
-- game states nothing about playing together.
function Q:GroupFact(questID)
    local title, suggested = self:LogEntry(questID)
    if not title then return nil end
    local log = _G.C_QuestLog
    local tagID
    if type(log) == "table" and type(log.GetQuestTagInfo) == "function" then
        local info = Call(log.GetQuestTagInfo, questID)
        tagID = type(info) == "table" and Number(info.tagID) or nil
    elseif type(_G.GetQuestTagInfo) == "function" then
        tagID = Number((Call(_G.GetQuestTagInfo, questID)))
    end
    if tagID and self.groupTags[tagID] then return title, self.groupTags[tagID], suggested end
    if suggested and suggested > 1 then return title, "SUGGESTED_GROUP", suggested end
    return nil
end

-- The client's own hyperlink for a quest, never built by Journey. Accepted only when it is a
-- single quest link naming this exact questID (some clients take a log index instead).
local function QuestLinkFor(link, questID)
    if type(link) ~= "string" or #link > 200 then return nil end
    local core = link:gsub("^|c%x%x%x%x%x%x%x%x", ""):gsub("|r$", "")
    local id = core:match("^|Hquest:(%d+)[%d:%-]*|h%[[^|%]]+%]|h$")
    return id and tonumber(id) == questID and link or nil
end
Q.QuestLinkFor = QuestLinkFor

function Q:NativeLink(questID)
    local fn = _G.GetQuestLink
    if type(fn) ~= "function" then return nil, "UNAVAILABLE" end
    local link = QuestLinkFor(Call(fn, questID), questID)
    if link then return link end
    local _, _, logIndex = self:LogEntry(questID)
    link = logIndex and QuestLinkFor(Call(fn, logIndex), questID)
    if link then return link end
    return nil, "NO_LINK"
end

-- First quest of the player's log that the game marks as a group activity (PLAYER_GROUP_QUEST_ACTIVE).
function Q:ActiveGroupQuest()
    local log = _G.C_QuestLog
    if type(log) ~= "table" or type(log.GetNumQuestLogEntries) ~= "function" or type(log.GetInfo) ~= "function" then return nil end
    local count = Number(Call(log.GetNumQuestLogEntries)) or 0
    for index = 1, math.min(count, 200) do
        local info = Call(log.GetInfo, index)
        if type(info) == "table" and not info.isHeader and Number(info.questID) then
            local title, fact = self:GroupFact(info.questID)
            if title then return { questID = info.questID, title = title, fact = fact } end
        end
    end
end
