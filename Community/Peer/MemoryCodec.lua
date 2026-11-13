local MS = _G.MS
MS.Community = MS.Community or {}
-- Peer memory codec on the MemoryBook model. Same compact,
-- versioned projection (schema 1). Not a second set of truth rules: MemoryBook.Validate decides.
-- Nothing local-only leaves the sender: no GUID, no quest context, no kept date, no evidence time.
local M = {}
MS.Community.MemoryCodec = M
local W, MB = MS.Community.Wire, MS.Community.MemoryBook
local NULL, Check = W.NULL, W.Check

M.KINDS = { "MOMENT", "ZONE_ENTRY", "INSTANCE_VISIT" }
M.SOURCES = { "MANUAL", "OBSERVED" }
M.EVIDENCE = { "MANUAL", "GROUP_MEMBER", "COPRESENCE_CONFIRMED", "INSTANCE_PRESENCE", "PEER_CONFIRMED" }
-- Wire evidence never claims more than the local basis: a shared road is not copresence.
M.BASIS_EVIDENCE = { MANUAL = 0, GROUP_MEMBER = 1, SHARED_ROUTE = 1, SAME_INSTANCE = 3 }

local function Opt(value) if value == nil then return NULL end return value end
local function Empty(value)
    return value == NULL or value == "" or value == 0 or (type(value) == "table" and value ~= NULL and (value.n or #value) == 0)
end

function M.pack(memory)
    local clean = MB.Validate(memory)
    Check(clean ~= nil, "MEMORY_SCHEMA")
    Check(clean.source == "OBSERVED" or clean.source == "MANUAL", "NOT_OWN_PRIVATE_MEMORY")
    local mentions = { n = 0 }
    for _, companion in ipairs(clean.companions) do
        mentions.n = mentions.n + 1
        mentions[mentions.n] = { n = 3, companion.name, Opt(companion.realm), M.BASIS_EVIDENCE[companion.basis] }
    end
    local place = clean.place
    local result = { n = 10, 1, clean.id, place.instance and 2 or 0,
        { n = 4, place.mapID and ("map:" .. place.mapID) or "place", NULL, place.name, Opt(place.mapID) },
        { n = 2, clean.at * 1000, clean["until"] and clean["until"] * 1000 or NULL },
        clean.title or "", clean.note or "", clean.source == "OBSERVED" and 1 or 0, mentions, NULL }
    while result.n > 5 and Empty(result[result.n]) do result[result.n] = nil; result.n = result.n - 1 end
    return W.json(result)
end

local function Array(value, minimum, maximum)
    Check(W.IsArray(value) and value.n >= minimum and value.n <= maximum, "MEMORY_SCHEMA")
end
-- Defaults apply to ABSENT trailing fields only (JavaScript destructuring), never to false.
local function Field(value, index, default)
    if index > value.n then return default end
    return value[index]
end
local function OptText(value) return value == NULL or type(value) == "string" end

-- Returns a RECEIVED memory (raw table for MemoryBook.Validate) and the sender's origin id.
function M.unpack(bytes, senderReference, transferId, now)
    local value = W.parse(bytes)
    Array(value, 5, 10)
    local version, originId, kind, place, time = value[1], value[2], value[3], value[4], value[5]
    local title, note = Field(value, 6, ""), Field(value, 7, "")
    local source, mentions, related = Field(value, 8, 0), Field(value, 9, { n = 0 }), Field(value, 10, NULL)
    Check(version == 1 and W.Integer(kind, 0, 2) and W.Integer(source, 0, 1), "MEMORY_SCHEMA")
    Array(place, 4, 4); Array(time, 2, 2); Array(mentions, 0, MB.companionLimit)
    Check(type(originId) == "string" and originId:find("[^ \t\r\n]") and MS.Community.Bytes.Utf16Length(originId) <= 120, "MEMORY_SCHEMA")
    Check(type(place[1]) == "string" and OptText(place[2]) and OptText(place[3]), "MEMORY_SCHEMA")
    -- Exactly one name source, as the domain requires.
    Check((place[2] == NULL) ~= (place[3] == NULL), "MEMORY_SCHEMA")
    Check(place[4] == NULL or W.Integer(place[4], 1, 2147483647), "MEMORY_SCHEMA")
    Check(W.Integer(time[1], 1000, 4102444800000) and (time[2] == NULL or W.Integer(time[2], time[1], 4102444800000)), "MEMORY_SCHEMA")
    Check(type(title) == "string" and type(note) == "string", "MEMORY_SCHEMA")
    -- Documented adaptation: V1 production carries no `related` (the sender's personal fact).
    Check(related == NULL, "MEMORY_SCHEMA")
    local name = place[3] ~= NULL and place[3] or place[2]
    local reference = senderReference .. ":" .. transferId
    local memory = { v = MB.schema, id = "r:" .. reference, source = "RECEIVED", at = math.floor(time[1] / 1000),
        ["until"] = time[2] ~= NULL and math.floor(time[2] / 1000) or nil,
        place = { mapID = place[4] ~= NULL and place[4] or nil, name = name, instance = kind == 2, reference = place[1] },
        kind = M.KINDS[kind + 1],
        companions = {}, keptAt = now, provenance = { reference = reference },
        title = title ~= "" and title or nil, note = note ~= "" and note or nil }
    for index = 1, mentions.n do
        local mention = mentions[index]
        Array(mention, 3, 3)
        local displayName, realm, evidence = mention[1], mention[2], mention[3]
        Check(type(displayName) == "string" and OptText(realm) and W.Integer(evidence, 0, #M.EVIDENCE - 1), "MEMORY_SCHEMA")
        -- A player-authored memory stays player-authored: every mention must be MANUAL.
        Check(source == 1 or evidence == 0, "MEMORY_SCHEMA")
        memory.companions[#memory.companions + 1] = { name = displayName, realm = realm ~= NULL and realm or nil, basis = "RECEIVED" }
    end
    local clean, reason = MB.Validate(memory)
    Check(clean ~= nil, "MEMORY_SCHEMA_" .. tostring(reason))
    return clean, originId
end
