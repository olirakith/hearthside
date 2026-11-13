local MS = _G.MS

MS.ChroniclesTriggerEngine = {}
local Engine = MS.ChroniclesTriggerEngine

local FACT_FOR_TRIGGER = {
    FIRST_ENTER_ZONE = "ENTER_ZONE",
    FIRST_ENTER_SUBZONE = "ENTER_SUBZONE",
    QUEST_COMPLETED = "QUEST_COMPLETED",
    QUEST_SET_COMPLETED = "QUEST_COMPLETED",
    LEVEL_REACHED = "LEVEL_REACHED",
}

local function Result(matched, supported, reason)
    return { matched = matched, supported = supported, reason = reason }
end

function Engine:Evaluate(trigger, fact, context)
    if type(trigger) ~= "table" or type(fact) ~= "table" then
        return Result(false, false, "INVALID_INPUT")
    end
    local kind = trigger.type
    if kind == "MAP_FULLY_EXPLORED" then return Result(false, false, "UNSUPPORTED_RUNTIME") end
    if not FACT_FOR_TRIGGER[kind] then return Result(false, false, "UNKNOWN_TRIGGER") end
    if fact.type ~= FACT_FOR_TRIGGER[kind] then return Result(false, true, "WRONG_FACT") end
    if kind == "FIRST_ENTER_ZONE" then
        return Result(trigger.region == fact.region, true, "EVALUATED")
    elseif kind == "FIRST_ENTER_SUBZONE" then
        return Result(trigger.region == fact.region and trigger.subzone == fact.subzone, true, "EVALUATED")
    elseif kind == "QUEST_COMPLETED" then
        return Result(trigger.questID == fact.questID, true, "EVALUATED")
    elseif kind == "LEVEL_REACHED" then
        return Result(type(fact.level) == "number" and fact.level >= trigger.level, true, "EVALUATED")
    end
    local completed = type(context) == "table" and context.completedQuestIDs
    if type(completed) ~= "table" then return Result(false, false, "QUEST_HISTORY_UNAVAILABLE") end
    local containsFact = false
    for _, questID in ipairs(trigger.quests or {}) do
        if questID == fact.questID then containsFact = true end
        if completed[questID] ~= true then return Result(false, true, "QUEST_MISSING") end
    end
    return Result(containsFact, true, "EVALUATED")
end
