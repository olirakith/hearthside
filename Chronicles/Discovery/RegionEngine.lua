local MS = _G.MS

MS.ChroniclesRegionEngine = {}
local Engine = MS.ChroniclesRegionEngine
Engine.__index = Engine

function Engine:New(registry, store, regionState, characterKey)
    return setmetatable({ registry = registry, store = store,
        regionState = regionState, characterKey = characterKey }, self)
end

local function Mark(self, method, regionID, now)
    local unavailable = { changed = false, status = "UNAVAILABLE" }
    local ok, result = pcall(function()
        if type(regionID) ~= "string" or not self.registry:GetRegion(regionID) then
            return { changed = false, status = "UNKNOWN_REGION" }
        end
        local state = self.store:GetCharacterState(self.characterKey)
        if not state or type(state.regions) ~= "table" then return nil end
        local nextRecord, changed = self.regionState[method](self.regionState, state.regions[regionID], now)
        if not nextRecord then return { changed = false, status = "INVALID_STATE" } end
        if changed and not self.store:CommitRegionStates(self.characterKey,
            { [regionID] = nextRecord }) then return nil end
        return { changed = changed, status = "READY", state = nextRecord.state }
    end)
    return ok and result or unavailable
end

function Engine:MarkRumored(regionID, now) return Mark(self, "MarkRumored", regionID, now) end
function Engine:MarkVisited(regionID, now) return Mark(self, "MarkVisited", regionID, now) end
function Engine:MarkExplored(regionID, now) return Mark(self, "MarkExplored", regionID, now) end
