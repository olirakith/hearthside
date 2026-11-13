local MS = _G.MS
MS.ChroniclesCollectionSealEngine = {}
local Engine = MS.ChroniclesCollectionSealEngine
Engine.__index = Engine

function Engine:New(registry, store, characterKey)
    return setmetatable({ registry = registry, store = store, characterKey = characterKey }, self)
end

local function ConditionsMet(definition, state, completed)
    local conditions = definition.conditions or {
        { type = "COLLECTION_COMPLETED", collection = definition.collection } }
    for _, condition in ipairs(conditions) do
        local matched = false
        if condition.type == "COLLECTION_COMPLETED" then
            local record = state.collections[condition.collection]
            matched = completed[condition.collection] or type(record) == "table" and record.completedAt ~= nil
        elseif condition.type == "CHRONICLE_DISCOVERED" then
            local record = state.chronicles[condition.chronicle]
            matched = type(record) == "table" and record.discoveredAt ~= nil
        elseif condition.type == "REGION_EXPLORED" then
            local record = state.regions[condition.region]
            matched = type(record) == "table" and record.state == "EXPLORED"
        end
        if not matched then return false end
    end
    return #conditions > 0
end

-- Reconciliation also handles reloads and newly registered volumes. All writes
-- are permanent facts; notification availability never participates.
function Engine:Reconcile(now)
    local ok, result = pcall(function()
        local state = self.store:GetCharacterState(self.characterKey)
        if not state then return nil end
        local completed, unlocked, completions = {}, {}, {}
        for id, definition in pairs(self.registry.collections) do
            if definition.status == "PUBLISHED"
                and MS.ChroniclesCollectionState:Derive(definition, state).state == "COMPLETED"
                and state.collections[id] == nil then
                completions[id] = true
                completed[#completed + 1] = id
            end
        end
        for id, definition in pairs(self.registry.seals) do
            if definition.status == "PUBLISHED" and state.seals[id] == nil
                and ConditionsMet(definition, state, completions) then unlocked[#unlocked + 1] = id end
        end
        table.sort(completed)
        table.sort(unlocked)
        if not self.store:CommitCollectionSeals(self.characterKey, completed, unlocked, now) then return nil end
        return { status = "READY", completed = completed, unlocked = unlocked }
    end)
    return ok and result or { status = "UNAVAILABLE", completed = {}, unlocked = {} }
end
