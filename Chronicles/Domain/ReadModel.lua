local MS = _G.MS

MS.ChroniclesReadModel = {}
local Queries = MS.ChroniclesReadModel

local function Unread(record)
    return type(record) == "table" and record.discoveredAt ~= nil and record.readAt == nil
end

local function Display(definition, locale)
    if not definition or type(definition.locales) ~= "table" then return nil end
    local localized = definition.locales[locale]
    if not localized or localized.status ~= "PUBLISHED" then
        localized = definition.locales.enUS and definition.locales.enUS.status == "PUBLISHED"
            and definition.locales.enUS or definition.locales.frFR
    end
    return localized and localized.status == "PUBLISHED" and localized or nil
end

function Queries:GetUnreadCount(characterState)
    local count = 0
    for _, record in pairs(characterState and characterState.chronicles or {}) do
        if Unread(record) then count = count + 1 end
    end
    return count
end

function Queries:GetCollections(state, registry, regionID, locale)
    local result = {}
    for id, definition in pairs(registry and registry.collections or {}) do
        if definition.status == "PUBLISHED" and (regionID == nil or definition.region == regionID) then
            local derived = MS.ChroniclesCollectionState:Derive(definition, state)
            if derived.state ~= "HIDDEN" then
                local localized = Display(definition, locale)
                local entries = {}
                for _, entryID in ipairs(definition.entries) do
                    local entry = self:GetChronicle(state, registry, entryID, locale)
                    if entry then entries[#entries + 1] = entry end
                end
                result[#result + 1] = { id = id, region = definition.region, kind = definition.kind,
                    name = localized and localized.name or MS.L["CHRONICLES_COLLECTION_" .. definition.kind],
                    state = derived.state, discovered = derived.discovered,
                    total = derived.showExactTotal and derived.total or nil,
                    completedAt = derived.completedAt, entries = entries }
            end
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

function Queries:GetSeals(state, registry, regionID, locale)
    local result = {}
    for id, record in pairs(state and state.seals or {}) do
        local definition = registry and registry:GetSeal(id)
        local localized = Display(definition, locale)
        if type(record) == "table" and record.unlockedAt
            and (regionID == nil or definition and (definition.region == regionID
                or not definition.region and registry:GetCollection(definition.collection)
                    and registry:GetCollection(definition.collection).region == regionID)) then
            result[#result + 1] = { id = id, unlockedAt = record.unlockedAt,
                name = localized and localized.name or MS.L.CHRONICLES_UNAVAILABLE_SEAL,
                description = localized and localized.description }
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

function Queries:GetUnreadChronicles(characterState, registry, locale)
    local result = {}
    for id, record in pairs(characterState and characterState.chronicles or {}) do
        if Unread(record) then
            local definition = registry and registry:GetChronicle(id)
            local localized = Display(definition, locale)
            result[#result + 1] = { id = id, discoveredAt = record.discoveredAt,
                title = localized and localized.title or MS.L.CHRONICLES_UNAVAILABLE_ENTRY,
                region = definition and definition.region,
                type = definition and definition.type }
        end
    end
    table.sort(result, function(a, b)
        if a.discoveredAt ~= b.discoveredAt then return a.discoveredAt > b.discoveredAt end
        return a.id < b.id
    end)
    return result
end

function Queries:GetChroniclesForRegion(characterState, registry, regionID, locale)
    local result = {}
    for id, record in pairs(characterState and characterState.chronicles or {}) do
        local definition = registry and registry:GetChronicle(id)
        if definition and definition.region == regionID and record.discoveredAt then
            local localized = Display(definition, locale)
            result[#result + 1] = { id = id, discoveredAt = record.discoveredAt,
                readAt = record.readAt,
                title = localized and localized.title or MS.L.CHRONICLES_UNAVAILABLE_ENTRY,
                region = regionID, type = definition.type }
        end
    end
    table.sort(result, function(a, b)
        if a.discoveredAt ~= b.discoveredAt then return a.discoveredAt > b.discoveredAt end
        return a.id < b.id
    end)
    return result
end

function Queries:GetRegionSummary(characterState, registry, regionID)
    local region = registry and registry:GetRegion(regionID)
    if not region then return nil end
    local state = characterState and characterState.regions and characterState.regions[regionID]
    local stateName = MS.ChroniclesRegionState
        and MS.ChroniclesRegionState:GetState(state) or state and state.state or "UNKNOWN"
    if stateName ~= "UNKNOWN" and stateName ~= "RUMORED"
        and stateName ~= "VISITED" and stateName ~= "EXPLORED" then stateName = "UNKNOWN" end
    local summary = { id = regionID, parent = region.parent, state = stateName,
        discovered = 0, unread = 0, revealName = stateName == "VISITED" or stateName == "EXPLORED" }
    if summary.state == "RUMORED" then
        for rumorID, record in pairs(characterState and characterState.rumors or {}) do
            local rumor = registry:GetRumor(rumorID)
            if record.discoveredAt and rumor and rumor.targetRegion == regionID
                and rumor.revealRegionName then summary.revealName = true; break end
        end
    end
    for id, record in pairs(characterState and characterState.chronicles or {}) do
        local definition = registry:GetChronicle(id)
        if definition and definition.region == regionID and record.discoveredAt then
            summary.discovered = summary.discovered + 1
            if Unread(record) then summary.unread = summary.unread + 1 end
        end
    end
    return summary
end

function Queries:GetChronicle(characterState, registry, id, locale)
    local record = characterState and characterState.chronicles and characterState.chronicles[id]
    if type(record) ~= "table" or not record.discoveredAt then return nil end
    local definition = registry and registry:GetChronicle(id)
    local localized = Display(definition, locale)
    if not definition or not localized then return nil end
    return { id = id, title = localized.title, body = localized.body,
        type = definition.type, format = definition.format, region = definition.region,
        discoveredAt = record.discoveredAt, readAt = record.readAt }
end

function Queries:GetRegions(characterState, registry, locale)
    local result, known = {}, {}
    for id, definition in pairs(registry and registry.regions or {}) do
        local summary = self:GetRegionSummary(characterState, registry, id)
        if summary.state ~= "UNKNOWN" or summary.discovered > 0 then
            summary.name = summary.revealName and (definition.names[locale]
                or definition.names.enUS or definition.names.frFR or id) or nil
            result[#result + 1] = summary
            known[id] = summary
        end
    end
    for _, summary in ipairs(result) do
        local depth, path, parent = 0, summary.name or summary.id, known[summary.parent]
        while parent and depth < 8 do
            depth = depth + 1
            path = (parent.name or parent.id) .. "/" .. path
            parent = known[parent.parent]
        end
        summary.depth, summary.path = depth, path
    end
    table.sort(result, function(a, b) return a.path < b.path end)
    return result
end
