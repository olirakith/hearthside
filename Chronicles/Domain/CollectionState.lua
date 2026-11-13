local MS = _G.MS

MS.ChroniclesCollectionState = {}
local Collections = MS.ChroniclesCollectionState

function Collections:Derive(definition, state)
    local discovered, total = 0, #definition.entries
    for _, id in ipairs(definition.entries) do
        local record = state and state.chronicles and state.chronicles[id]
        if type(record) == "table" and record.discoveredAt then discovered = discovered + 1 end
    end
    local record = state and state.collections and state.collections[definition.id]
    local completedAt = type(record) == "table" and record.completedAt or nil
    local complete = completedAt ~= nil or total > 0 and discovered == total
    -- HIDDEN collections enter the Grimoire only after a real discovery.
    local revealed = complete or discovered > 0 or definition.reveal == "ALWAYS"
    local region = state and state.regions and state.regions[definition.region]
    local policy = definition.showExactTotal
    local exact = policy == "ALWAYS" or policy == "AFTER_FIRST_ENTRY" and discovered > 0
        or policy == "AFTER_REGION_EXPLORED" and type(region) == "table" and region.state == "EXPLORED"
    return { state = complete and "COMPLETED" or revealed and "REVEALED" or "HIDDEN",
        discovered = discovered, total = total, showExactTotal = exact == true,
        completedAt = completedAt }
end
