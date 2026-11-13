local MS = _G.MS

MS.ChroniclesDiscoveryEngine = {}
local Engine = MS.ChroniclesDiscoveryEngine
Engine.__index = Engine

local TRIGGERS_BY_FACT = {
    ENTER_ZONE = { "FIRST_ENTER_ZONE" },
    ENTER_SUBZONE = { "FIRST_ENTER_SUBZONE" },
    QUEST_COMPLETED = { "QUEST_COMPLETED", "QUEST_SET_COMPLETED" },
    LEVEL_REACHED = { "LEVEL_REACHED" },
}

function Engine:New(registry, store, triggerEngine, characterKey)
    return setmetatable({ registry = registry, store = store, triggerEngine = triggerEngine,
        characterKey = characterKey }, self)
end

function Engine:ProcessFact(fact, context, now)
    local empty = { discovered = {}, status = "UNAVAILABLE" }
    if type(fact) ~= "table" or type(fact.type) ~= "string"
        or type(now) ~= "number" or now <= 0 or now == math.huge or now ~= math.floor(now) then
        return { discovered = {}, status = "INVALID_FACT" }
    end
    local kinds = TRIGGERS_BY_FACT[fact.type]
    if not kinds then return { discovered = {}, status = "UNSUPPORTED_FACT" } end
    local ok, result = pcall(function()
        local registry, store = self.registry, self.store
        if type(registry) ~= "table" or type(registry.GetPublishedChroniclesForTrigger) ~= "function"
            or type(store) ~= "table" or type(store.GetCharacterState) ~= "function"
            or type(store.DiscoverChronicles) ~= "function" or type(self.triggerEngine) ~= "table"
            or type(self.triggerEngine.Evaluate) ~= "function" then return nil end
        local state = store:GetCharacterState(self.characterKey)
        if type(state) ~= "table" or type(state.chronicles) ~= "table" then return nil end
        local pending = {}
        for _, kind in ipairs(kinds) do
            local candidates = registry:GetPublishedChroniclesForTrigger(kind)
            if type(candidates) ~= "table" then return nil end
            for _, definition in ipairs(candidates) do
                if type(definition) ~= "table" or type(definition.id) ~= "string" then return nil end
                if definition.status == "PUBLISHED" and state.chronicles[definition.id] == nil then
                    local evaluation = self.triggerEngine:Evaluate(definition.trigger, fact, context)
                    if evaluation.supported and evaluation.matched then pending[#pending + 1] = definition.id end
                end
            end
        end
        local discovered = store:DiscoverChronicles(self.characterKey, pending, now)
        if not discovered then return nil end
        return { discovered = discovered, status = "READY" }
    end)
    return ok and result or empty
end
