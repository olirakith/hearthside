local MS = _G.MS

MS.ChroniclesRumorEngine = {}
local Engine = MS.ChroniclesRumorEngine
Engine.__index = Engine

local TRIGGERS_BY_FACT = {
    ENTER_ZONE = { "FIRST_ENTER_ZONE" },
    ENTER_SUBZONE = { "FIRST_ENTER_SUBZONE" },
    QUEST_COMPLETED = { "QUEST_COMPLETED", "QUEST_SET_COMPLETED" },
    LEVEL_REACHED = { "LEVEL_REACHED" },
}

function Engine:New(registry, store, triggerEngine, regionState, characterKey)
    return setmetatable({ registry = registry, store = store, triggerEngine = triggerEngine,
        regionState = regionState, characterKey = characterKey }, self)
end

function Engine:ProcessFact(fact, context, now)
    local unavailable = { rumors = {}, status = "UNAVAILABLE" }
    if type(fact) ~= "table" or type(fact.type) ~= "string"
        or type(now) ~= "number" or now <= 0 or now >= math.huge or now ~= math.floor(now) then
        return { rumors = {}, status = "INVALID_FACT" }
    end
    local kinds = TRIGGERS_BY_FACT[fact.type]
    if not kinds then return { rumors = {}, status = "UNSUPPORTED_FACT" } end
    local ok, result = pcall(function()
        local registry, store = self.registry, self.store
        if type(registry) ~= "table" or type(registry.GetPublishedRumorsForTrigger) ~= "function"
            or type(store) ~= "table" or type(store.GetCharacterState) ~= "function"
            or type(store.DiscoverRumors) ~= "function" or type(self.triggerEngine) ~= "table"
            or type(self.triggerEngine.Evaluate) ~= "function" or type(self.regionState) ~= "table"
            or type(self.regionState.MarkRumored) ~= "function" then return nil end
        local state = store:GetCharacterState(self.characterKey)
        if type(state) ~= "table" or type(state.rumors) ~= "table"
            or type(state.regions) ~= "table" then return nil end
        local pending, regionUpdates = {}, {}
        for _, kind in ipairs(kinds) do
            local candidates = registry:GetPublishedRumorsForTrigger(kind)
            if type(candidates) ~= "table" then return nil end
            for _, rumor in ipairs(candidates) do
                if type(rumor) ~= "table" or type(rumor.id) ~= "string" then return nil end
                if rumor.status == "PUBLISHED" and state.rumors[rumor.id] == nil then
                    local evaluation = self.triggerEngine:Evaluate(rumor.trigger, fact, context)
                    if evaluation.supported and evaluation.matched then
                        if not registry:GetRegion(rumor.targetRegion) then return nil end
                        local current = regionUpdates[rumor.targetRegion] or state.regions[rumor.targetRegion]
                        local nextRecord, changed = self.regionState:MarkRumored(current, now)
                        if not nextRecord then return nil end
                        if changed then regionUpdates[rumor.targetRegion] = nextRecord end
                        pending[#pending + 1] = rumor.id
                    end
                end
            end
        end
        local discovered = store:DiscoverRumors(self.characterKey, pending, regionUpdates, now)
        if not discovered then return nil end
        return { rumors = discovered, status = "READY" }
    end)
    return ok and result or unavailable
end
