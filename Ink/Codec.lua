local MS = _G.MS
MS.Ink = MS.Ink or {}
-- Seals of L'Encre des Royaumes: "HSI1:" + base64 of a binary tale. Pure.
-- Not encryption. Everything after the id is scrambled with a keystream anyone can rebuild, so
-- that pasting a seal does not spoil the tale at a glance; answers are only fingerprints (Tale).
-- Line breaks and spaces inside the seal are ignored: chat and Discord wrap long codes. A final
-- "." ends it, so words pasted right after it are not read as part of it.
--
-- Layout (big-endian):
--   1 format (1 = plain, 2 = packed, 3 = plain extended, 4 = packed extended) | 4 id
--   ---- scrambled from here (formats 2 and 4: packed with Ink.Pack first, then scrambled) ----
--   2 tale version | 1 mode | 1 order | 4 createdAt
--   s8 author | s8 title | s16 intro | s16 ending | 1 page count
--   per page: 2 key | s8 title | s16 hint | s16 text | 1 trigger kind | trigger
--     PLACE  2 mapID | 2 x | 2 y | 1 radius
--     ANSWER 1 n | n * 4 hash
--     ITEM   4 itemID | 1 count
--   extended formats only (used when a page needs them; older versions refuse them whole):
--     NPC    4 npcID | s8 name
--     EMOTE  s8 token | 1 flags (1 = creature, 2 = place) | [NPC fields] | [PLACE fields]
--     KILL   4 npcID | s8 name | 1 count
--     then, per page: 1 flags (1 = hours, 2 = level) | [1 from | 1 to] | [1 level]
--   4 CRC32 of everything before
-- s8 / s16: a 1- or 2-byte length, then that many bytes of UTF-8.
local Codec = { plain = 1, packed = 2, extended = 2, prefix = "HSI1:", maxInput = 40000, maxBody = 32000 }
MS.Ink.Codec = Codec

local MODES, MODE_NAMES = { NOTES = 1, HUNT = 2, QUEST = 3 }, { "NOTES", "HUNT", "QUEST" }
local ORDERS, ORDER_NAMES = { FREE = 1, SEQUENCE = 2 }, { "FREE", "SEQUENCE" }
local TRIGGERS, TRIGGER_NAMES = { PLACE = 1, ANSWER = 2, ITEM = 3, NPC = 4, EMOTE = 5, KILL = 6 },
    { "PLACE", "ANSWER", "ITEM", "NPC", "EMOTE", "KILL" }

local floor, byte, char = math.floor, string.byte, string.char

local function Bytes() return MS.Community.Bytes end
local function Tale() return MS.Ink.Tale end

local function U(value, size)
    local out = {}
    for index = size, 1, -1 do
        out[index] = char(value % 256)
        value = floor(value / 256)
    end
    return table.concat(out)
end

local function S(value, size)
    value = value or ""
    return U(#value, size) .. value
end

-- MINSTD keystream seeded by the id, as in the Sur mes pas codes.
local function Scramble(data, from, seed)
    local Xor, state, out = Bytes().Xor32, seed % 2147483646 + 1, { data:sub(1, from - 1) }
    for index = from, #data do
        state = (state * 48271) % 2147483647
        out[#out + 1] = char(Xor(byte(data, index), floor(state / 128) % 256))
    end
    return table.concat(out)
end

local function EncodePlace(trigger)
    return U(trigger.mapID, 2) .. U(floor(trigger.x * 65535 + .5), 2) .. U(floor(trigger.y * 65535 + .5), 2) .. char(trigger.radius)
end

local function EncodeCreature(trigger) return U(trigger.npcID, 4) .. S(trigger.name, 1) end

local function EncodeWhen(when)
    when = when or {}
    local flags = (when.from and 1 or 0) + (when.level and 2 or 0)
    return char(flags) .. (when.from and char(when.from, when.to) or "") .. (when.level and char(when.level) or "")
end

local function EncodeTrigger(trigger)
    local parts = { char(TRIGGERS[trigger.kind]) }
    if trigger.kind == "PLACE" then
        parts[2] = EncodePlace(trigger)
    elseif trigger.kind == "ANSWER" then
        parts[2] = char(#trigger.hashes)
        for _, hash in ipairs(trigger.hashes) do parts[#parts + 1] = U(tonumber(hash, 16), 4) end
    elseif trigger.kind == "NPC" then
        parts[2] = EncodeCreature(trigger)
    elseif trigger.kind == "KILL" then
        parts[2] = EncodeCreature(trigger) .. char(trigger.count)
    elseif trigger.kind == "EMOTE" then
        parts[2] = S(trigger.token, 1) .. char((trigger.npcID and 1 or 0) + (trigger.mapID and 2 or 0))
            .. (trigger.npcID and EncodeCreature(trigger) or "") .. (trigger.mapID and EncodePlace(trigger) or "")
    else
        parts[2] = U(trigger.itemID, 4) .. char(trigger.count)
    end
    return table.concat(parts)
end

-- Encodes a tale (cleaned first). Returns the seal or nil.
function Codec.Encode(raw)
    local tale = Tale().Sanitize(raw, true)
    if not tale or not tale.createdAt or tale.createdAt < 0 or tale.createdAt > 4294967295 then return nil end
    local idNumber = tonumber(tale.id, 16)
    local extended = Tale().Extended(tale)
    local shift = extended and Codec.extended or 0
    local parts = {
        char(Codec.plain + shift), U(idNumber, 4),
        U(tale.version, 2), char(MODES[tale.mode]), char(ORDERS[tale.order]), U(tale.createdAt, 4),
        S(tale.author, 1), S(tale.title, 1), S(tale.intro, 2), S(tale.ending, 2), char(#tale.pages),
    }
    for _, page in ipairs(tale.pages) do
        parts[#parts + 1] = U(tonumber(page.key, 16), 2) .. S(page.title, 1) .. S(page.hint, 2) .. S(page.text, 2)
            .. EncodeTrigger(page.trigger) .. (extended and EncodeWhen(page.when) or "")
    end
    local body = table.concat(parts)
    body = body .. U(tonumber(Bytes().Crc32(body), 16), 4)
    -- Packed when it is shorter (almost always); the checksum covers the plain bytes.
    local packed = MS.Ink.Pack.Compress(body:sub(6))
    if #packed < #body - 5 then body = char(Codec.packed + shift) .. body:sub(2, 5) .. packed end
    return Codec.prefix .. Bytes().Base64Encode(Scramble(body, 6, idNumber)) .. "."
end

-- The seal inside anything pasted (a message, a forum post): first one only, spaces removed.
function Codec.Find(text)
    if type(text) ~= "string" or #text > Codec.maxInput then return nil end
    local packed = text:gsub("%s+", "")
    -- A seal that lost its final dot is still tried (its checksum refuses anything glued to it).
    return packed:match("HSI1:([A-Za-z0-9+/]+=?=?)%.") or packed:match("HSI1:([A-Za-z0-9+/]+=?=?)")
end

-- A cursor over decoded bytes; every read past the end returns nil.
local function Reader(data)
    local at = 1
    local reader = {}
    function reader.U(size)
        if at + size - 1 > #data then return nil end
        local value = 0
        for index = at, at + size - 1 do value = value * 256 + byte(data, index) end
        at = at + size
        return value
    end
    function reader.S(size)
        local length = reader.U(size)
        if not length or at + length - 1 > #data then return nil end
        local value = data:sub(at, at + length - 1)
        at = at + length
        return value
    end
    function reader.Done() return at == #data + 1 end
    return reader
end

local function DecodePlace(read, into)
    local mapID, x, y, radius = read.U(2), read.U(2), read.U(2), read.U(1)
    if not radius then return nil end
    into.mapID, into.x, into.y, into.radius = mapID, x / 65535, y / 65535, radius
    return into
end

local function DecodeCreature(read, into)
    into.npcID, into.name = read.U(4), read.S(1)
    return into.name and into or nil
end

-- Returns the conditions (an empty table when there is none), or nil when the bytes stop.
local function DecodeWhen(read)
    local flags = read.U(1)
    if not flags or flags > 3 then return nil end
    local when = {}
    if flags % 2 == 1 then
        when.from, when.to = read.U(1), read.U(1)
        if not when.to then return nil end
    end
    if flags >= 2 then
        when.level = read.U(1)
        if not when.level then return nil end
    end
    return when
end

-- Conditions are refused rather than dropped: the page would open too early.
local function KeptWhen(when)
    local clean = Tale().SanitizeWhen(when) or {}
    return clean.from == when.from and clean.to == when.to and clean.level == when.level
end

local function DecodeTrigger(read, extended)
    local code = read.U(1) or 0
    local kind = (extended or code <= 3) and TRIGGER_NAMES[code]
    if kind == "PLACE" then
        return DecodePlace(read, { kind = kind })
    elseif kind == "NPC" then
        return DecodeCreature(read, { kind = kind })
    elseif kind == "KILL" then
        local trigger = DecodeCreature(read, { kind = kind })
        if trigger then trigger.count = read.U(1) end
        return trigger and trigger.count and trigger or nil
    elseif kind == "EMOTE" then
        local trigger = { kind = kind, token = read.S(1) }
        local flags = read.U(1)
        if not flags or flags > 3 then return nil end
        if flags % 2 == 1 and not DecodeCreature(read, trigger) then return nil end
        if flags >= 2 and not DecodePlace(read, trigger) then return nil end
        return trigger
    elseif kind == "ANSWER" then
        local count = read.U(1)
        if not count then return nil end
        local hashes = {}
        for index = 1, count do
            local value = read.U(4)
            if not value then return nil end
            hashes[index] = string.format("%08x", value)
        end
        return { kind = kind, hashes = hashes }
    elseif kind == "ITEM" then
        local itemID, count = read.U(4), read.U(1)
        if not count then return nil end
        return { kind = kind, itemID = itemID, count = count }
    end
end

-- Returns the tale, or nil and MALFORMED | UNSUPPORTED | CORRUPT | INVALID | EMPTY.
function Codec.Decode(text, now)
    local encoded = Codec.Find(text)
    if not encoded then return nil, "MALFORMED" end
    local data = Bytes().Base64Decode(encoded)
    -- A seal was pasted but its bytes do not hold together: most often it was cut short.
    if not data or #data < 24 then return nil, "CORRUPT" end
    local format = byte(data, 1)
    if format < Codec.plain or format > Codec.packed + Codec.extended then return nil, "UNSUPPORTED" end
    local extended = format > Codec.extended
    local shift = extended and Codec.extended or 0
    local idNumber = (byte(data, 2) * 16777216) + (byte(data, 3) * 65536) + (byte(data, 4) * 256) + byte(data, 5)
    data = Scramble(data, 6, idNumber)
    if format == Codec.packed + shift then
        local unpacked = MS.Ink.Pack.Decompress(data:sub(6), Codec.maxBody)
        if not unpacked or #unpacked < 19 then return nil, "CORRUPT" end
        data = char(Codec.plain + shift) .. data:sub(2, 5) .. unpacked
    end
    local body = data:sub(1, -5)
    local crcRead = Reader(data:sub(-4))
    if tonumber(Bytes().Crc32(body), 16) ~= crcRead.U(4) then return nil, "CORRUPT" end
    local read = Reader(body)
    read.U(5)
    local raw = { id = string.format("%08x", idNumber), version = read.U(2), mode = MODE_NAMES[read.U(1) or 0],
        order = ORDER_NAMES[read.U(1) or 0], createdAt = read.U(4) }
    raw.author, raw.title, raw.intro, raw.ending = read.S(1), read.S(1), read.S(2), read.S(2)
    local count = read.U(1)
    if not count or count < 1 then return nil, "INVALID" end
    raw.pages = {}
    for index = 1, count do
        local key = read.U(2)
        local title, hint, pageText = read.S(1), read.S(2), read.S(2)
        local trigger = key and pageText and DecodeTrigger(read, extended)
        local when = trigger and extended and DecodeWhen(read) or nil
        if not trigger or (extended and not (when and KeptWhen(when))) then return nil, "INVALID" end
        raw.pages[index] = { key = string.format("%04x", key), title = title, hint = hint, text = pageText, trigger = trigger, when = when }
    end
    if not read.Done() then return nil, "INVALID" end
    local tale, reason = Tale().Sanitize(raw, true)
    if not tale then return nil, reason end
    -- Someone else's bytes: text a player could not have written is refused, not repaired.
    if tale.author ~= raw.author or tale.title ~= raw.title then return nil, "INVALID" end
    if tale.createdAt < 1700000000 or (type(now) == "number" and tale.createdAt > now + 86400) then return nil, "INVALID" end
    return tale
end
