local MS = _G.MS
local Schema = MS.ChroniclesContentSchema
local Validator = MS.ChroniclesContentValidator

MS.ChroniclesRegistry = {}
local Registry = MS.ChroniclesRegistry
Registry.__index = Registry

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[Copy(key)] = Copy(item) end
    return result
end

local function MapCopy(map)
    local result = {}
    for key, value in pairs(map) do result[key] = value end
    return result
end

function Registry:New()
    local instance = { packs = {}, ids = {}, collectionIDsByChronicle = {}, publishedByTrigger = {},
        publishedRumorsByTrigger = {}, regionsByMapID = {} }
    for _, kind in ipairs(Schema.KINDS) do instance[kind] = {} end
    return setmetatable(instance, self)
end

function Registry:RegisterPack(pack)
    if type(pack) == "table" and type(pack.pack) == "table"
        and type(pack.pack.id) == "string" and self.packs[pack.pack.id] then
        return { ok = false, errors = { { code = "DUPLICATE_PACK_ID", path = "pack.id",
            message = "Pack ID is already registered" } }, warnings = {} }
    end
    local report = Validator:ValidatePack(pack, self)
    if not report.ok then return report end

    -- Build every new index before publishing any of them.
    local saved = Copy(pack)
    local nextPacks, nextIDs = MapCopy(self.packs), MapCopy(self.ids)
    local nextKinds, nextInverse = {}, MapCopy(self.collectionIDsByChronicle)
    local nextTriggers, nextMaps = MapCopy(self.publishedByTrigger), MapCopy(self.regionsByMapID)
    local nextRumorTriggers = MapCopy(self.publishedRumorsByTrigger)
    for _, kind in ipairs(Schema.KINDS) do nextKinds[kind] = MapCopy(self[kind]) end
    for _, kind in ipairs(Schema.KINDS) do
        for _, definition in ipairs(saved[kind]) do
            nextKinds[kind][definition.id] = definition
            nextIDs[definition.id] = kind
        end
    end
    for _, region in ipairs(saved.regions) do nextMaps[region.mapID] = region.id end
    for _, chronicle in ipairs(saved.chronicles) do
        if chronicle.status == "PUBLISHED" then
            local kind = chronicle.trigger.type
            local previous = nextTriggers[kind] or {}
            local ids = {}
            for index, id in ipairs(previous) do ids[index] = id end
            ids[#ids + 1] = chronicle.id
            nextTriggers[kind] = ids
        end
    end
    for _, rumor in ipairs(saved.rumors) do
        if rumor.status == "PUBLISHED" then
            local kind = rumor.trigger.type
            local previous = nextRumorTriggers[kind] or {}
            local ids = {}
            for index, id in ipairs(previous) do ids[index] = id end
            ids[#ids + 1] = rumor.id
            nextRumorTriggers[kind] = ids
        end
    end
    for _, collection in ipairs(saved.collections) do
        for _, chronicleID in ipairs(collection.entries) do
            local previous = nextInverse[chronicleID] or {}
            local ids = {}
            for index, id in ipairs(previous) do ids[index] = id end
            ids[#ids + 1] = collection.id
            nextInverse[chronicleID] = ids
        end
    end
    nextPacks[saved.pack.id] = saved
    self.packs, self.ids, self.collectionIDsByChronicle = nextPacks, nextIDs, nextInverse
    self.publishedByTrigger, self.regionsByMapID = nextTriggers, nextMaps
    self.publishedRumorsByTrigger = nextRumorTriggers
    for _, kind in ipairs(Schema.KINDS) do self[kind] = nextKinds[kind] end
    return report
end

function Registry:GetPack(id) return self.packs[id] end
function Registry:GetRegion(id) return self.regions[id] end
function Registry:GetChronicle(id) return self.chronicles[id] end
function Registry:GetRumor(id) return self.rumors[id] end
function Registry:GetCollection(id) return self.collections[id] end
function Registry:GetSeal(id) return self.seals[id] end

function Registry:GetRegionByMapID(mapID)
    return self.regionsByMapID[mapID]
end

function Registry:GetPublishedChroniclesForTrigger(kind)
    local result = {}
    for _, id in ipairs(self.publishedByTrigger[kind] or {}) do
        result[#result + 1] = self.chronicles[id]
    end
    return result
end

function Registry:GetPublishedRumorsForTrigger(kind)
    local result = {}
    for _, id in ipairs(self.publishedRumorsByTrigger[kind] or {}) do
        result[#result + 1] = self.rumors[id]
    end
    return result
end

function Registry:GetCollectionsForChronicle(id)
    local result = {}
    for index, collectionID in ipairs(self.collectionIDsByChronicle[id] or {}) do result[index] = collectionID end
    return result
end
