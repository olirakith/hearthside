local MS = _G.MS

MS.ChroniclesRegionState = {}
local RegionState = MS.ChroniclesRegionState

local RANK = { UNKNOWN = 0, RUMORED = 1, VISITED = 2, EXPLORED = 3 }

local function ValidTime(now)
    return type(now) == "number" and now > 0 and now < math.huge and now == math.floor(now)
end

local function Copy(record)
    local result = {}
    if record then for key, value in pairs(record) do result[key] = value end end
    return result
end

function RegionState:GetState(record)
    if record == nil then return "UNKNOWN" end
    if type(record) ~= "table" then return nil end
    if RANK[record.state] then return record.state end
    -- Older saves could contain a timestamp instead of an explicit state.
    if record.state ~= nil then return nil end
    if record.exploredAt ~= nil then return "EXPLORED" end
    if record.firstVisitedAt ~= nil then return "VISITED" end
    if record.firstRumorAt ~= nil then return "RUMORED" end
    return "UNKNOWN"
end

local function Prepare(self, current, now)
    if not ValidTime(now) then return nil end
    local state = self:GetState(current)
    if not state then return nil end
    return Copy(current), state
end

function RegionState:MarkRumored(current, now)
    local nextRecord, state = Prepare(self, current, now)
    if not nextRecord then return nil, false end
    if nextRecord.firstRumorAt == nil then nextRecord.firstRumorAt = now end
    if state == "UNKNOWN" then nextRecord.state = "RUMORED"
    else nextRecord.state = state end
    local changed = not current or nextRecord.firstRumorAt ~= current.firstRumorAt
        or nextRecord.state ~= current.state
    return nextRecord, changed
end

function RegionState:MarkVisited(current, now)
    local nextRecord, state = Prepare(self, current, now)
    if not nextRecord then return nil, false end
    if state == "UNKNOWN" or state == "RUMORED" then
        nextRecord.state = "VISITED"
        if nextRecord.firstVisitedAt == nil then nextRecord.firstVisitedAt = now end
    else
        nextRecord.state = state
    end
    local changed = not current or nextRecord.state ~= current.state
        or nextRecord.firstVisitedAt ~= current.firstVisitedAt
    return nextRecord, changed
end

function RegionState:MarkExplored(current, now)
    local nextRecord, state = Prepare(self, current, now)
    if not nextRecord then return nil, false end
    if state ~= "VISITED" and state ~= "EXPLORED" then return current, false end
    nextRecord.state = "EXPLORED"
    if nextRecord.exploredAt == nil then nextRecord.exploredAt = now end
    local changed = nextRecord.state ~= current.state or nextRecord.exploredAt ~= current.exploredAt
    return nextRecord, changed
end
