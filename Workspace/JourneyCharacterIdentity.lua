local MS = _G.MS
MS.JourneyCharacterIdentity = {}
local Identity = MS.JourneyCharacterIdentity

local function Text(value)
    if type(value) ~= "string" or #value > 256 then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value == "" or value:find("[@?%c]") then return nil end
    return value
end

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, first, second = pcall(fn, ...)
    if ok then return first, second end
end

function Identity:IsGUID(value)
    if type(value) ~= "string" or #value > 256 then return false end
    local realm, id = value:match("^Player%-(%d+)%-(%x+)$")
    return realm ~= nil and tonumber(realm) > 0 and tonumber(realm) < math.huge
        and #id >= 8 and #id <= 16 and tonumber(id, 16) > 0
end

function Identity:IsKey(value)
    return self:IsGUID(value) or type(value) == "string"
        and #value <= 256 and value:match("^[^?@%c]+@[^?@%c]+$") ~= nil
end

function Identity:Resolve()
    local first, surname = Read(_G.UnitName, "player")
    local fullFirst, fullSecond = Read(_G.UnitFullName, "player")
    first = Text(first) or Text(fullFirst)
    surname = Text(surname) or (first == Text(fullFirst) and Text(fullSecond) or nil)
    local realm = Text(Read(_G.GetRealmName))
    local fullName = first and (surname and first .. " " .. surname or first)
    local guid = Read(_G.UnitGUID, "player")
    guid = self:IsGUID(guid) and guid or nil
    local fallback = fullName and realm and fullName .. "@" .. realm
    local legacy = first and realm and first .. "@" .. realm
    return { key = guid or fallback, guid = guid, firstName = first, surname = surname,
        fullName = fullName, realm = realm, legacyKey = legacy, fallbackKey = fallback }
end

local function Meaningful(value)
    if type(value) == "table" then
        for _, child in pairs(value) do if Meaningful(child) then return true end end
        return false
    end
    return value ~= nil and value ~= false and value ~= 0 and value ~= ""
end

-- Only exact keys emitted by the old algorithm and the full-name fallback are
-- eligible. Never search for another character sharing the first name.
function Identity:MigrateCharacters(characters, identity)
    local result = { status = "UNCHANGED", canonicalKey = identity.key, legacyKeys = {} }
    if type(characters) ~= "table" or not identity.key then result.status = "UNAVAILABLE"; return result end
    local candidates, seen = {}, {}
    for _, key in ipairs({ identity.legacyKey or false, identity.fallbackKey or false }) do
        if key and key ~= identity.key and not seen[key] and characters[key] ~= nil then
            seen[key] = true
            result.legacyKeys[#result.legacyKeys + 1] = key
            candidates[#candidates + 1] = key
        end
    end
    if #candidates == 0 then return result end
    if #candidates > 1 then result.status = "CONFLICT"; result.reason = "MULTIPLE_LEGACY_RECORDS"; return result end
    local key = candidates[1]
    if type(characters[key]) ~= "table" then result.status = "CONFLICT"; result.reason = "INVALID_LEGACY_RECORD"; return result end
    if Meaningful(characters[identity.key]) and Meaningful(characters[key]) then
        result.status, result.reason = "CONFLICT", "CANONICAL_AND_LEGACY_DATA"
        return result
    end
    if not Meaningful(characters[identity.key]) then
        characters[identity.key] = characters[key]
    end
    characters[key] = nil
    result.status, result.migratedFrom = "MIGRATED", key
    return result
end

function Identity:WarnConflict(scope, migration)
    if migration.status ~= "CONFLICT" then return end
    self.warned = self.warned or {}
    local key = scope .. ":" .. tostring(migration.canonicalKey)
    if not self.warned[key] and MS.Diagnostics and MS.L and MS.L.JOURNEY_IDENTITY_CONFLICT then
        self.warned[key] = true
        pcall(MS.Diagnostics.Print, MS.Diagnostics, MS.L.JOURNEY_IDENTITY_CONFLICT)
    end
end
