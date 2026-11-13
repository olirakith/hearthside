local MS = _G.MS
MS.Active = MS.Active or {}
-- Sur mes pas share codes: "AJ1:" + base64 of a small binary payload. Pure.
-- Not encryption. The words and the place are scrambled with a keystream anyone can rebuild
-- from the code itself, so that pasting a code does not spoil it at a glance. The promise is
-- "Journey does not reveal the place before you find it", never "this place is secret".
--
-- Payload (big-endian):
--   1 version (1) | 1 kind (2 = one character, 3 = anyone with the code) | 4 id
--   ---- scrambled from here ----
--   4 createdAt | 2 uiMapID | 2 x | 2 y | 4 recipient hash (0 for anyone)
--   1 + n author "Name-Realm" | 1 + n text | 4 CRC32 of everything before
local Codec = { version = 1, prefix = "AJ1:", textBytes = 80, authorBytes = 64 }
MS.Active.SealCodec = Codec
Codec.kinds = { CHAR = 2, ANY = 3 }
Codec.kindNames = { [2] = "CHAR", [3] = "ANY" }

local floor, byte, char = math.floor, string.byte, string.char

local function Bytes() return MS.Community.Bytes end

local function U(value, size)
    local out = {}
    for index = size, 1, -1 do
        out[index] = char(value % 256)
        value = floor(value / 256)
    end
    return table.concat(out)
end

local function ReadU(data, at, size)
    local value = 0
    for index = at, at + size - 1 do value = value * 256 + byte(data, index) end
    return value
end

-- MINSTD keystream seeded by the id: products stay below 2^53, exact in Lua doubles.
local function Scramble(data, from, seed)
    local Xor, state, out = Bytes().Xor32, seed % 2147483646 + 1, { data:sub(1, from - 1) }
    for index = from, #data do
        state = (state * 48271) % 2147483647
        out[#out + 1] = char(Xor(byte(data, index), floor(state / 128) % 256))
    end
    return table.concat(out)
end

local function HexToNumber(hex) return tonumber(hex, 16) end

-- Recipient hash: CRC32 of the folded "name-realm" key. Detects the wrong character, proves nothing.
function Codec.RecipientHash(nameKey)
    if type(nameKey) ~= "string" or nameKey == "" then return 0 end
    return HexToNumber(Bytes().Crc32(nameKey))
end

-- seal: { kind = "CHAR"|"ANY", id = 8 hex, createdAt, mapID, x, y, recipientHash, author, text }
function Codec.Encode(seal)
    local kind = Codec.kinds[seal.kind]
    local Text = MS.Active.Text
    local author = Text.CleanLine(seal.author, Codec.authorBytes)
    local words = Text.CleanLine(seal.text, Codec.textBytes)
    if not kind or not author or not words or type(seal.id) ~= "string" or not seal.id:find("^%x%x%x%x%x%x%x%x$") then return nil end
    if type(seal.mapID) ~= "number" or seal.mapID < 1 or seal.mapID > 65535 or type(seal.createdAt) ~= "number" then return nil end
    if type(seal.x) ~= "number" or type(seal.y) ~= "number" or seal.x < 0 or seal.x > 1 or seal.y < 0 or seal.y > 1 then return nil end
    local idNumber = HexToNumber(seal.id)
    local body = table.concat({
        char(Codec.version), char(kind), U(idNumber, 4),
        U(floor(seal.createdAt), 4), U(floor(seal.mapID), 2),
        U(floor(seal.x * 65535 + .5), 2), U(floor(seal.y * 65535 + .5), 2),
        U(kind == Codec.kinds.CHAR and (seal.recipientHash or 0) or 0, 4),
        char(#author), author, char(#words), words,
    })
    body = body .. U(HexToNumber(Bytes().Crc32(body)), 4)
    return Codec.prefix .. Bytes().Base64Encode(Scramble(body, 7, idNumber))
end

-- The code inside anything pasted (a whisper, a Discord message): first match only.
function Codec.Find(text)
    if type(text) ~= "string" or #text > 4096 then return nil end
    return text:match("AJ1:([A-Za-z0-9+/]+=?=?)")
end

-- Returns the decoded seal, or nil and MALFORMED | UNSUPPORTED | CORRUPT | INVALID.
function Codec.Decode(text, now)
    local encoded = Codec.Find(text)
    if not encoded then return nil, "MALFORMED" end
    local data = Bytes().Base64Decode(encoded)
    if not data or #data < 26 then return nil, "MALFORMED" end
    if byte(data, 1) ~= Codec.version then return nil, "UNSUPPORTED" end
    local kind = Codec.kindNames[byte(data, 2)]
    if not kind then return nil, "UNSUPPORTED" end
    local idNumber = ReadU(data, 3, 4)
    data = Scramble(data, 7, idNumber)
    local body, crc = data:sub(1, -5), ReadU(data, #data - 3, 4)
    if HexToNumber(Bytes().Crc32(body)) ~= crc then return nil, "CORRUPT" end
    local at = 21
    local authorLength = byte(body, at)
    if not authorLength or at + authorLength >= #body then return nil, "INVALID" end
    local author = body:sub(at + 1, at + authorLength)
    at = at + authorLength + 1
    local textLength = byte(body, at)
    if not textLength or at + textLength ~= #body then return nil, "INVALID" end
    local words = body:sub(at + 1, at + textLength)
    local Text = MS.Active.Text
    local seal = {
        kind = kind, id = string.format("%08x", idNumber),
        createdAt = ReadU(body, 7, 4), mapID = ReadU(body, 11, 2),
        x = ReadU(body, 13, 2) / 65535, y = ReadU(body, 15, 2) / 65535,
        recipientHash = ReadU(body, 17, 4),
        author = Text.CleanLine(author, Codec.authorBytes), text = Text.CleanLine(words, Codec.textBytes),
    }
    -- Someone else's bytes: anything a player could not have typed, or any impossible field, is refused.
    if not seal.author or seal.author ~= author or not seal.text or seal.text ~= words or seal.mapID < 1 then return nil, "INVALID" end
    if (kind == "CHAR") ~= (seal.recipientHash ~= 0) then return nil, "INVALID" end
    if seal.createdAt < 1700000000 or (type(now) == "number" and seal.createdAt > now + 86400) then return nil, "INVALID" end
    return seal
end
