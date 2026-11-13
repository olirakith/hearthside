local MS = _G.MS
MS.Community = MS.Community or {}
-- Exact character identity, or nothing. Same rule across the domain:
-- a runtime identifier on either side forbids any name fallback.
local Identity = {}
MS.Community.Identity = Identity

local function Text(value, limit)
    if type(value) ~= "string" then return nil end
    -- Explicit ASCII classes only: %s/%c depend on the C locale and can split UTF-8 names.
    value = value:match("^[ \t]*(.-)[ \t]*$")
    if value == "" or #value > (limit or 64) or value:find("[%z\1-\31\127|]") then return nil end
    return value
end

function Identity.IsGUID(value)
    return MS.JourneyCharacterIdentity:IsGUID(value)
end

-- realm stays nil unless it was given explicitly; the local realm is never assumed.
function Identity.Make(guid, name, realm)
    local id = { guid = Identity.IsGUID(guid) and guid or nil, name = Text(name), realm = Text(realm) }
    if not id.guid and not (id.name and id.realm) then return nil end
    return id
end

function Identity.Key(id)
    if type(id) ~= "table" then return nil end
    if id.guid then return "g:" .. id.guid end
    if id.name and id.realm then return "n:" .. id.name .. "-" .. id.realm end
end

-- Returns "MATCH" or a rejection code; only MATCH may ever drive a player-facing echo.
function Identity.Compare(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return "INVALID" end
    if a.guid or b.guid then
        if not (a.guid and b.guid) then return "GUID_ONE_SIDED" end
        if a.guid == b.guid then return "MATCH" end
        -- Same visible name, different GUID: the measurement COM-01 needs. Never a match.
        if a.name and a.name == b.name then return "GUID_MISMATCH" end
        return "DIFFERENT"
    end
    if not (a.realm and b.realm) then return "REALM_UNKNOWN" end
    if a.name == b.name and a.realm == b.realm then return "MATCH" end
    return "DIFFERENT"
end

function Identity.Same(a, b) return Identity.Compare(a, b) == "MATCH" end

function Identity.Copy(id)
    return id and { guid = id.guid, name = id.name, realm = id.realm } or nil
end

-- Parses a native "Name-Realm" sender. No realm part means no realm, not the local one.
function Identity.FromAddress(address, guid)
    if type(address) ~= "string" then return Identity.Make(guid) end
    local name, realm = address:match("^([^%-]+)%-(.+)$")
    return Identity.Make(guid, name or address, realm)
end
