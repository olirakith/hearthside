local MS = _G.MS

MS.ChroniclesPresentationEvents = {}
local Events = MS.ChroniclesPresentationEvents

local function Add(events, kind, prefix, priority, id, now, batchID)
    events[#events + 1] = { eventID = prefix .. id, type = kind,
        contentID = id, priority = priority, createdAt = now, batchID = batchID }
end

-- Only newly committed domain results become presentation events. This module
-- never reads or writes player progression.
function Events:FromFactResult(fact, result, now)
    local events = {}
    local firstID = result.regionVisited and fact.region
        or result.rumors and result.rumors[1]
        or result.discovered and result.discovered[1]
    if not firstID then return events end
    local batchID = "fact:" .. tostring(now) .. ":" .. firstID
    if result.regionVisited then
        Add(events, "REGION_VISITED", "region-visited:", "IMPORTANT",
            fact.region, now, batchID)
    end
    for _, id in ipairs(result.rumors or {}) do
        Add(events, "RUMOR_DISCOVERED", "rumor:", "LOW", id, now, batchID)
    end
    for _, id in ipairs(result.discovered or {}) do
        Add(events, "CHRONICLE_DISCOVERED", "chronicle:", "NORMAL", id, now, batchID)
    end
    return events
end
