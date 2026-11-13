local MS = _G.MS
local Schema = MS.ChroniclesContentSchema

MS.ChroniclesContentValidator = {}
local Validator = MS.ChroniclesContentValidator
local KINDS = Schema.KINDS
local WORD_RANGES = { NOTE = { 80, 150 }, CHRONICLE = { 200, 400 }, DOSSIER = { 600, 1200 } }

local FIELDS = {
    regions = { id = true, contentVersion = true, names = true, mapID = true, parent = true },
    chronicles = { id = true, contentVersion = true, status = true, format = true, type = true,
        region = true, locales = true, trigger = true, spoiler = true, sources = true,
        credits = true, storyId = true, tags = true },
    rumors = { id = true, contentVersion = true, status = true, targetRegion = true,
        trigger = true, locales = true, revealRegionName = true, sources = true, credits = true },
    collections = { id = true, contentVersion = true, status = true, kind = true,
        region = true, ordering = true, reveal = true, showExactTotal = true, entries = true, seal = true, locales = true },
    seals = { id = true, contentVersion = true, status = true, region = true,
        collection = true, locales = true, conditions = true },
}

local function Diagnostic(report, severity, code, path, message)
    local list = severity == "error" and report.errors or report.warnings
    list[#list + 1] = { code = code, path = path, message = message }
end

local function Result()
    return { ok = true, errors = {}, warnings = {} }
end

local function Finish(report)
    report.ok = #report.errors == 0
    return report
end

local function NonEmpty(value)
    return type(value) == "string" and value:find("%S") ~= nil
end

local function PositiveInteger(value)
    return type(value) == "number" and value == value and value >= 1
        and value < math.huge and value == math.floor(value)
end

local function ID(value)
    if not NonEmpty(value) or not value:match("^[a-z0-9][a-z0-9._-]*$") then return false end
    if value:find("..", 1, true) or value:sub(-1) == "." then return false end
    return true
end

local function Keys(value)
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        if type(a) == "string" or type(a) == "number" then return a < b end
        if type(a) == "boolean" then return a == false and b == true end
        return false
    end)
    return keys
end

local function KeyLabel(key)
    local kind = type(key)
    if kind == "string" or kind == "number" or kind == "boolean" then return tostring(key) end
    return "<" .. kind .. ">"
end

local function Declarative(value, path, report, seen)
    local kind = type(value)
    if kind == "function" or kind == "userdata" or kind == "thread" then
        Diagnostic(report, "error", "NON_DECLARATIVE_VALUE", path, "Content cannot contain executable or opaque values")
        return
    end
    if kind == "number" and (value ~= value or value == math.huge or value == -math.huge) then
        Diagnostic(report, "error", "NON_DECLARATIVE_VALUE", path, "Content numbers must be finite")
        return
    end
    if kind ~= "table" then return end
    if getmetatable(value) ~= nil then
        Diagnostic(report, "error", "NON_DECLARATIVE_VALUE", path, "Content tables cannot have metatables")
        return
    end
    if seen[value] then
        Diagnostic(report, "error", "CYCLIC_DATA", path, "Content tables cannot contain cycles")
        return
    end
    seen[value] = true
    for _, key in ipairs(Keys(value)) do
        Declarative(key, path .. ".<key>", report, seen)
        Declarative(value[key], path .. "." .. KeyLabel(key), report, seen)
    end
    seen[value] = nil
end

local function Fields(value, allowed, path, report)
    if type(value) ~= "table" then
        Diagnostic(report, "error", "INVALID_STRUCTURE", path, "Expected a table")
        return false
    end
    for _, key in ipairs(Keys(value)) do
        if not allowed[key] then
            Diagnostic(report, "error", "UNKNOWN_FIELD", path .. "." .. KeyLabel(key), "Field is not in Content Schema V1")
        end
    end
    return true
end

local function Array(value, path, report, nonempty)
    if type(value) ~= "table" then
        Diagnostic(report, "error", "INVALID_STRUCTURE", path, "Expected an array")
        return false, 0
    end
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            Diagnostic(report, "error", "INVALID_ARRAY", path, "Array keys must be positive integers")
            return false, 0
        end
        count = count + 1
        if key > maximum then maximum = key end
    end
    if count ~= maximum then
        Diagnostic(report, "error", "INVALID_ARRAY", path, "Array cannot be sparse")
        return false, 0
    end
    if nonempty and count == 0 then
        Diagnostic(report, "error", "EMPTY_ARRAY", path, "Array cannot be empty")
    end
    return true, count
end

local function CheckID(value, path, report)
    if not ID(value) then Diagnostic(report, "error", "INVALID_ID", path, "Expected a dotted or slugged ID") end
end

local function CheckEnum(value, enum, path, report)
    if not enum[value] then Diagnostic(report, "error", "INVALID_ENUM", path, "Value is not supported") end
end

local function CheckText(value, path, report)
    if not NonEmpty(value) then Diagnostic(report, "error", "INVALID_TEXT", path, "Expected non-empty text") end
end

local function CheckVersion(definition, path, report)
    if not PositiveInteger(definition.contentVersion) then
        Diagnostic(report, "error", "INVALID_CONTENT_VERSION", path .. ".contentVersion", "Expected a positive integer")
    end
end

local function CheckStatus(definition, path, report)
    CheckEnum(definition.status, Schema.CONTENT_STATUSES, path .. ".status", report)
end

local function CheckStrings(value, path, report)
    local valid, count = Array(value, path, report)
    if not valid then return end
    for index = 1, count do CheckText(value[index], path .. "." .. index, report) end
end

local function CheckLocales(locales, kind, status, path, report)
    if type(locales) ~= "table" then
        Diagnostic(report, "error", "INVALID_STRUCTURE", path, "Expected locale table")
        return
    end
    local usable = 0
    for _, locale in ipairs({ "enUS", "frFR" }) do
        local entry = locales[locale]
        if entry == nil or type(entry) == "table" and entry.status == "MISSING" then
            Diagnostic(report, "warning", "MISSING_TRANSLATION", path .. "." .. locale, "Translation is missing")
        end
        if entry ~= nil then
            local entryPath = path .. "." .. locale
            local allowed = kind == "chronicles" and { status = true, title = true, body = true, landmarks = true }
                or kind == "rumors" and { status = true, text = true }
                or { status = true, name = true, description = true }
            if Fields(entry, allowed, entryPath, report) then
                CheckEnum(entry.status, Schema.LOCALE_STATUSES, entryPath .. ".status", report)
                for _, field in ipairs(kind == "chronicles" and { "title", "body" }
                    or kind == "rumors" and { "text" } or { "name", "description" }) do
                    if entry[field] ~= nil and type(entry[field]) ~= "string" then
                        Diagnostic(report, "error", "INVALID_TEXT", entryPath .. "." .. field, "Expected text")
                    end
                end
                if entry.status == "PUBLISHED" then
                    usable = usable + 1
                    if kind == "chronicles" then
                        CheckText(entry.title, entryPath .. ".title", report)
                        CheckText(entry.body, entryPath .. ".body", report)
                    elseif kind == "rumors" then
                        CheckText(entry.text, entryPath .. ".text", report)
                    else
                        CheckText(entry.name, entryPath .. ".name", report)
                    end
                end
                if entry.landmarks ~= nil then CheckStrings(entry.landmarks, entryPath .. ".landmarks", report) end
                if kind == "chronicles" and NonEmpty(entry.body) and WORD_RANGES[status.format] then
                    local words = 0
                    for _ in entry.body:gmatch("%S+") do words = words + 1 end
                    local range = WORD_RANGES[status.format]
                    if words < range[1] or words > range[2] then
                        Diagnostic(report, "warning", "EDITORIAL_LENGTH", entryPath .. ".body", "Body is outside the recommended word range")
                    end
                end
            end
        end
    end
    for _, key in ipairs(Keys(locales)) do
        if not Schema.LOCALES[key] then
            Diagnostic(report, "error", "UNKNOWN_LOCALE", path .. "." .. KeyLabel(key), "Locale is not supported")
        end
    end
    if status.status == "PUBLISHED" and usable == 0 then
        Diagnostic(report, "error", "NO_PUBLISHED_LOCALE", path, "Published content needs a published locale")
    end
end

local function CheckSources(definition, path, report)
    local valid, count = Array(definition.sources, path .. ".sources", report)
    if valid then
        for index = 1, count do
            local entry = definition.sources[index]
            local entryPath = path .. ".sources." .. index
            if Fields(entry, { type = true, reference = true }, entryPath, report) then
                CheckEnum(entry.type, Schema.SOURCE_TYPES, entryPath .. ".type", report)
                CheckText(entry.reference, entryPath .. ".reference", report)
            end
        end
        if count == 0 then
            Diagnostic(report, definition.status == "PUBLISHED" and "error" or "warning",
                "MISSING_SOURCE", path .. ".sources", "Published content needs a source")
        end
    end
    local credits = definition.credits
    if Fields(credits, { author = true, contributors = true }, path .. ".credits", report) then
        CheckText(credits.author, path .. ".credits.author", report)
        CheckStrings(credits.contributors, path .. ".credits.contributors", report)
    end
end

local function CheckTrigger(trigger, path, report)
    if type(trigger) ~= "table" then
        Diagnostic(report, "error", "INVALID_STRUCTURE", path, "Expected declarative trigger")
        return
    end
    local kind = trigger.type
    if not Schema.TRIGGERS[kind] then
        Diagnostic(report, "error", "UNKNOWN_TRIGGER", path .. ".type", "Trigger type is not supported")
        return
    end
    local allowed = { type = true }
    if kind == "FIRST_ENTER_ZONE" or kind == "MAP_FULLY_EXPLORED" then
        allowed.region = true
        CheckID(trigger.region, path .. ".region", report)
    elseif kind == "FIRST_ENTER_SUBZONE" then
        allowed.region, allowed.subzone = true, true
        CheckID(trigger.region, path .. ".region", report)
        CheckText(trigger.subzone, path .. ".subzone", report)
    elseif kind == "QUEST_COMPLETED" then
        allowed.questID = true
        if not PositiveInteger(trigger.questID) then Diagnostic(report, "error", "INVALID_QUEST_ID", path .. ".questID", "Expected a positive integer") end
    elseif kind == "QUEST_SET_COMPLETED" then
        allowed.quests = true
        local valid, count = Array(trigger.quests, path .. ".quests", report, true)
        if valid then
            local seen = {}
            for index = 1, count do
                local questID = trigger.quests[index]
                if not PositiveInteger(questID) then
                    Diagnostic(report, "error", "INVALID_QUEST_ID", path .. ".quests." .. index, "Expected a positive integer")
                elseif seen[questID] then
                    Diagnostic(report, "error", "DUPLICATE_QUEST_ID", path .. ".quests." .. index, "Quest is repeated")
                end
                seen[questID] = true
            end
        end
    else
        allowed.level = true
        if not PositiveInteger(trigger.level) then Diagnostic(report, "error", "INVALID_LEVEL", path .. ".level", "Expected a positive integer") end
    end
    Fields(trigger, allowed, path, report)
end

local function CheckSpoiler(spoiler, path, report)
    if not Fields(spoiler, { policy = true, unlockAfterQuestID = true, unlockAfterChronicle = true }, path, report) then return end
    CheckEnum(spoiler.policy, Schema.SPOILERS, path .. ".policy", report)
    if spoiler.unlockAfterQuestID ~= nil and not PositiveInteger(spoiler.unlockAfterQuestID) then
        Diagnostic(report, "error", "INVALID_QUEST_ID", path .. ".unlockAfterQuestID", "Expected a positive integer")
    end
    if spoiler.unlockAfterChronicle ~= nil then CheckID(spoiler.unlockAfterChronicle, path .. ".unlockAfterChronicle", report) end
end

local function CheckDefinition(kind, definition, path, report)
    if not FIELDS[kind] then
        Diagnostic(report, "error", "UNKNOWN_KIND", path, "Definition kind is not supported")
        return
    end
    if not Fields(definition, FIELDS[kind], path, report) then return end
    CheckID(definition.id, path .. ".id", report)
    CheckVersion(definition, path, report)
    if kind == "regions" then
        if not PositiveInteger(definition.mapID) then Diagnostic(report, "error", "INVALID_MAP_ID", path .. ".mapID", "Expected a positive integer") end
        if definition.parent ~= nil then CheckID(definition.parent, path .. ".parent", report) end
        if type(definition.names) ~= "table" then
            Diagnostic(report, "error", "INVALID_STRUCTURE", path .. ".names", "Expected region names")
        else
            local count = 0
            for _, locale in ipairs({ "enUS", "frFR" }) do
                if definition.names[locale] ~= nil then
                    count = count + 1
                    CheckText(definition.names[locale], path .. ".names." .. locale, report)
                end
            end
            if count == 0 then Diagnostic(report, "error", "MISSING_LOCALE", path .. ".names", "Region needs a name") end
            Fields(definition.names, Schema.LOCALES, path .. ".names", report)
        end
        return
    end
    CheckStatus(definition, path, report)
    if kind == "chronicles" then
        CheckEnum(definition.format, Schema.FORMATS, path .. ".format", report)
        CheckEnum(definition.type, Schema.CHRONICLE_TYPES, path .. ".type", report)
        CheckID(definition.region, path .. ".region", report)
        CheckLocales(definition.locales, kind, definition, path .. ".locales", report)
        CheckTrigger(definition.trigger, path .. ".trigger", report)
        CheckSpoiler(definition.spoiler, path .. ".spoiler", report)
        CheckSources(definition, path, report)
        if definition.storyId ~= nil then CheckID(definition.storyId, path .. ".storyId", report) end
        if definition.tags ~= nil then CheckStrings(definition.tags, path .. ".tags", report) end
    elseif kind == "rumors" then
        CheckID(definition.targetRegion, path .. ".targetRegion", report)
        CheckTrigger(definition.trigger, path .. ".trigger", report)
        CheckLocales(definition.locales, kind, definition, path .. ".locales", report)
        if type(definition.revealRegionName) ~= "boolean" then
            Diagnostic(report, "error", "INVALID_BOOLEAN", path .. ".revealRegionName", "Expected a boolean")
        end
        CheckSources(definition, path, report)
    elseif kind == "collections" then
        CheckEnum(definition.kind, Schema.COLLECTION_KINDS, path .. ".kind", report)
        CheckID(definition.region, path .. ".region", report)
        CheckEnum(definition.ordering, Schema.ORDERINGS, path .. ".ordering", report)
        CheckEnum(definition.reveal, Schema.REVEALS, path .. ".reveal", report)
        CheckEnum(definition.showExactTotal, Schema.EXACT_TOTALS, path .. ".showExactTotal", report)
        local valid, count = Array(definition.entries, path .. ".entries", report, definition.status == "PUBLISHED")
        if valid then
            local seen = {}
            for index = 1, count do
                local entry = definition.entries[index]
                CheckID(entry, path .. ".entries." .. index, report)
                if seen[entry] then Diagnostic(report, "error", "DUPLICATE_ENTRY", path .. ".entries." .. index, "Entry is repeated") end
                seen[entry] = true
            end
        end
        if definition.seal ~= nil then CheckID(definition.seal, path .. ".seal", report) end
        if definition.locales ~= nil then
            CheckLocales(definition.locales, kind, definition, path .. ".locales", report)
        end
    elseif kind == "seals" then
        if definition.region ~= nil then CheckID(definition.region, path .. ".region", report) end
        if definition.collection ~= nil then CheckID(definition.collection, path .. ".collection", report) end
        if definition.conditions == nil then
            if definition.collection == nil then
                Diagnostic(report, "error", "MISSING_SEAL_CONDITIONS", path, "Seal needs conditions or a collection")
            end
        else
            local valid, count = Array(definition.conditions, path .. ".conditions", report, true)
            if valid then
                for index = 1, count do
                    local condition = definition.conditions[index]
                    local conditionPath = path .. ".conditions." .. index
                    local field = type(condition) == "table" and ({ COLLECTION_COMPLETED = "collection",
                        CHRONICLE_DISCOVERED = "chronicle", REGION_EXPLORED = "region" })[condition.type]
                    if not field then
                        Diagnostic(report, "error", "INVALID_SEAL_CONDITION", conditionPath, "Unsupported condition")
                    else
                        Fields(condition, { type = true, [field] = true }, conditionPath, report)
                        CheckID(condition[field], conditionPath .. "." .. field, report)
                    end
                end
            end
        end
        CheckLocales(definition.locales, kind, definition, path .. ".locales", report)
    end
end

function Validator:ValidateDefinition(kind, definition)
    local report = Result()
    local path = type(kind) == "string" and kind or "definition"
    Declarative(definition, path, report, {})
    if #report.errors == 0 then
        CheckDefinition(kind, definition, path .. "." .. tostring(type(definition) == "table" and definition.id or "?"), report)
    end
    return Finish(report)
end

local function CrossReferences(pack, maps, known, report)
    local function Exists(kind, id)
        return maps[kind][id] ~= nil or known and known[kind] and known[kind][id] ~= nil
    end
    local function Reference(kind, id, path, code)
        if ID(id) and not Exists(kind, id) then Diagnostic(report, "error", code, path, "Referenced definition does not exist") end
    end
    local function Trigger(trigger, path)
        if type(trigger) == "table" and (trigger.type == "FIRST_ENTER_ZONE" or trigger.type == "FIRST_ENTER_SUBZONE"
            or trigger.type == "MAP_FULLY_EXPLORED") then
            Reference("regions", trigger.region, path .. ".region", "UNKNOWN_REGION")
        end
    end
    for _, region in ipairs(pack.regions) do
        if region.parent ~= nil then Reference("regions", region.parent, "regions." .. region.id .. ".parent", "UNKNOWN_REGION") end
    end
    for _, chronicle in ipairs(pack.chronicles) do
        local path = "chronicles." .. chronicle.id
        Reference("regions", chronicle.region, path .. ".region", "UNKNOWN_REGION")
        Trigger(chronicle.trigger, path .. ".trigger")
        if chronicle.spoiler.unlockAfterChronicle ~= nil then
            Reference("chronicles", chronicle.spoiler.unlockAfterChronicle, path .. ".spoiler.unlockAfterChronicle", "UNKNOWN_CHRONICLE")
            if chronicle.spoiler.unlockAfterChronicle == chronicle.id then
                Diagnostic(report, "error", "SELF_DEPENDENCY", path .. ".spoiler.unlockAfterChronicle", "Chronicle cannot unlock itself")
            end
        end
    end
    for _, rumor in ipairs(pack.rumors) do
        local path = "rumors." .. rumor.id
        Reference("regions", rumor.targetRegion, path .. ".targetRegion", "UNKNOWN_REGION")
        Trigger(rumor.trigger, path .. ".trigger")
    end
    for _, collection in ipairs(pack.collections) do
        local path = "collections." .. collection.id
        Reference("regions", collection.region, path .. ".region", "UNKNOWN_REGION")
        for index, id in ipairs(collection.entries) do
            Reference("chronicles", id, path .. ".entries." .. index, "UNKNOWN_CHRONICLE")
        end
        if collection.seal ~= nil then
            Reference("seals", collection.seal, path .. ".seal", "UNKNOWN_SEAL")
            local seal = maps.seals[collection.seal] or known and known.seals and known.seals[collection.seal]
            if seal and seal.collection ~= collection.id then
                Diagnostic(report, "error", "SEAL_COLLECTION_MISMATCH", path .. ".seal", "Seal references another collection")
            end
        end
    end
    for _, seal in ipairs(pack.seals) do
        local path = "seals." .. seal.id
        if seal.collection then Reference("collections", seal.collection, path .. ".collection", "UNKNOWN_COLLECTION") end
        for index, condition in ipairs(seal.conditions or {}) do
            local target = ({ COLLECTION_COMPLETED = { "collections", "collection" },
                CHRONICLE_DISCOVERED = { "chronicles", "chronicle" }, REGION_EXPLORED = { "regions", "region" } })[condition.type]
            Reference(target[1], condition[target[2]], path .. ".conditions." .. index, "UNKNOWN_SEAL_CONDITION_TARGET")
        end
        if seal.region ~= nil then Reference("regions", seal.region, path .. ".region", "UNKNOWN_REGION") end
    end
    local function CheckCycles(kind, dependency, field, code)
        local visiting, visited = {}, {}
        local function Visit(id)
            if visited[id] then return end
            if visiting[id] then
                Diagnostic(report, "error", code, kind .. "." .. id .. "." .. field, "Dependency cycle is not allowed")
                return
            end
            visiting[id] = true
            local entry = maps[kind][id]
            local nextID = entry and dependency(entry)
            if nextID and maps[kind][nextID] then Visit(nextID) end
            visiting[id], visited[id] = nil, true
        end
        for _, entry in ipairs(pack[kind]) do Visit(entry.id) end
    end
    CheckCycles("regions", function(region) return region.parent end, "parent", "CIRCULAR_REGION_PARENT")
    CheckCycles("chronicles", function(chronicle) return chronicle.spoiler.unlockAfterChronicle end,
        "spoiler.unlockAfterChronicle", "CIRCULAR_DEPENDENCY")
end

function Validator:ValidatePack(pack, known)
    local report = Result()
    Declarative(pack, "pack", report, {})
    if #report.errors > 0 then return Finish(report) end
    if not Fields(pack, { contentSchemaVersion = true, pack = true, regions = true,
        chronicles = true, rumors = true, collections = true, seals = true }, "pack", report) then return Finish(report) end
    if pack.contentSchemaVersion ~= Schema.CONTENT_SCHEMA_VERSION then
        Diagnostic(report, "error", "UNKNOWN_CONTENT_SCHEMA", "contentSchemaVersion", "Content Schema V1 is required")
    end
    if Fields(pack.pack, { id = true, version = true, source = true, timeline = true }, "pack.pack", report) then
        CheckID(pack.pack.id, "pack.id", report)
        if not PositiveInteger(pack.pack.version) then Diagnostic(report, "error", "INVALID_PACK_VERSION", "pack.version", "Expected a positive integer") end
        CheckEnum(pack.pack.source, Schema.PACK_SOURCES, "pack.source", report)
        CheckEnum(pack.pack.timeline, Schema.TIMELINES, "pack.timeline", report)
    end
    local maps, ids = {}, {}
    local arraysValid = true
    for _, kind in ipairs(KINDS) do
        maps[kind] = {}
        local valid, count = Array(pack[kind], kind, report)
        if not valid then arraysValid = false end
        if valid then
            for index = 1, count do
                local definition = pack[kind][index]
                local path = kind .. "." .. index
                CheckDefinition(kind, definition, path, report)
                if type(definition) == "table" and ID(definition.id) then
                    if ids[definition.id] or known and known.ids and known.ids[definition.id] then
                        Diagnostic(report, "error", "DUPLICATE_ID", path .. ".id", "Definition ID is already registered")
                    else
                        ids[definition.id] = kind
                        maps[kind][definition.id] = definition
                    end
                end
            end
        end
    end
    if arraysValid and #report.errors == 0 then CrossReferences(pack, maps, known, report) end
    return Finish(report)
end

function Validator:ValidateEvolution(previousPack, nextPack)
    local report = Result()
    local previous = self:ValidatePack(previousPack)
    local nextReport = self:ValidatePack(nextPack)
    for _, source in ipairs({ previous, nextReport }) do
        for _, item in ipairs(source.errors) do report.errors[#report.errors + 1] = item end
        for _, item in ipairs(source.warnings) do report.warnings[#report.warnings + 1] = item end
    end
    -- A removal may make nextPack invalid for other reasons; still report the
    -- completion contract violation explicitly.
    if previous.ok and type(nextPack) == "table" and type(nextPack.collections) == "table" then
        local nextCollections = {}
        for _, collection in ipairs(nextPack.collections) do
            if type(collection) == "table" and type(collection.id) == "string" then
                nextCollections[collection.id] = collection
            end
        end
        for _, old in ipairs(previousPack.collections) do
            if old.status == "PUBLISHED" then
                local updated = nextCollections[old.id]
                local changed = not updated or type(updated.entries) ~= "table"
                    or old.ordering ~= updated.ordering or #old.entries ~= #updated.entries
                if not changed and old.ordering == "ORDERED" then
                    for index, id in ipairs(old.entries) do if updated.entries[index] ~= id then changed = true; break end end
                elseif not changed then
                    local set = {}
                    for _, id in ipairs(old.entries) do set[id] = true end
                    for _, id in ipairs(updated.entries) do if not set[id] then changed = true; break end end
                end
                if changed then
                    Diagnostic(report, "error", "IMMUTABLE_COMPLETION_SET_CHANGED", "collections." .. old.id .. ".entries", "Published collection completion set is immutable")
                end
            end
        end
    end
    if #report.errors > 0 then return Finish(report) end
    if previousPack.pack.id ~= nextPack.pack.id then
        Diagnostic(report, "error", "PACK_ID_CHANGED", "pack.id", "Evolution must keep the same pack ID")
        return Finish(report)
    end
    local nextByKind = {}
    for _, kind in ipairs(KINDS) do
        nextByKind[kind] = {}
        for _, definition in ipairs(nextPack[kind]) do nextByKind[kind][definition.id] = definition end
    end
    for _, kind in ipairs(KINDS) do
        for _, old in ipairs(previousPack[kind]) do
            local updated = nextByKind[kind][old.id]
            if updated and updated.contentVersion < old.contentVersion then
                Diagnostic(report, "error", "VERSION_REGRESSION", kind .. "." .. old.id .. ".contentVersion", "Content version cannot decrease")
            end
        end
    end
    return Finish(report)
end
