local MS = _G.MS
MS.Community = MS.Community or {}
-- Pure byte helpers shared by diagnostics and the peer protocol. Lua strings are byte
-- arrays. Arithmetic only: WoW's bit library returns signed values, Lua 5.1 tests have none.
local Bytes = {}
MS.Community.Bytes = Bytes

local floor, byte, char = math.floor, string.byte, string.char

local XOR4 = {}
for a = 0, 15 do
    XOR4[a] = {}
    for b = 0, 15 do
        local r, bit, x, y = 0, 1, a, b
        for _ = 1, 4 do
            if x % 2 ~= y % 2 then r = r + bit end
            x, y, bit = floor(x / 2), floor(y / 2), bit * 2
        end
        XOR4[a][b] = r
    end
end
local function Xor8(a, b)
    return XOR4[floor(a / 16)][floor(b / 16)] * 16 + XOR4[a % 16][b % 16]
end
local function Xor32(a, b)
    local result, scale = 0, 1
    for _ = 1, 4 do
        result = result + Xor8(a % 256, b % 256) * scale
        a, b, scale = floor(a / 256), floor(b / 256), scale * 256
    end
    return result
end
Bytes.Xor32 = Xor32

local CRC = {}
for n = 0, 255 do
    local c = n
    for _ = 1, 8 do
        if c % 2 == 1 then c = Xor32(floor(c / 2), 0xEDB88320) else c = floor(c / 2) end
    end
    CRC[n] = c
end

-- CRC32 (IEEE, as wire.cjs): eight lowercase hex digits. Detects accidents, authenticates nothing.
function Bytes.Crc32(data)
    local crc = 0xFFFFFFFF
    for i = 1, #data do
        crc = Xor32(CRC[Xor8(crc % 256, byte(data, i))], floor(crc / 256))
    end
    return string.format("%08x", Xor32(crc, 0xFFFFFFFF))
end

function Bytes.IsHex(value, length)
    return type(value) == "string" and #value == length and value:find("^[0-9a-f]+$") ~= nil
end

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE = {}
for i = 1, 64 do DECODE[byte(ALPHABET, i)] = i - 1 end

function Bytes.Base64Encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = byte(data, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local s1, s2 = floor(n / 262144) % 64, floor(n / 4096) % 64
        local s3, s4 = floor(n / 64) % 64, n % 64
        out[#out + 1] = ALPHABET:sub(s1 + 1, s1 + 1) .. ALPHABET:sub(s2 + 1, s2 + 1)
            .. (b and ALPHABET:sub(s3 + 1, s3 + 1) or "=") .. (c and ALPHABET:sub(s4 + 1, s4 + 1) or "=")
    end
    return table.concat(out)
end

-- Canonical only: re-encoding must reproduce the input exactly (as wire.cjs).
function Bytes.Base64Decode(text)
    if type(text) ~= "string" or #text % 4 ~= 0 or not text:find("^[A-Za-z0-9+/]*=?=?$") then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local q = { byte(text, i, i + 3) }
        local pad = (q[3] == 61 and 1 or 0) + (q[4] == 61 and 1 or 0)
        if pad > 0 and i + 3 ~= #text then return nil end
        local n = 0
        for k = 1, 4 do n = n * 64 + (q[k] == 61 and 0 or DECODE[q[k]]) end
        local chunk = char(floor(n / 65536), floor(n / 256) % 256, n % 256)
        out[#out + 1] = chunk:sub(1, 3 - pad)
    end
    local data = table.concat(out)
    if Bytes.Base64Encode(data) ~= text then return nil end
    return data
end

-- Strict UTF-8: no overlong forms, surrogates, code points above U+10FFFF or truncation.
function Bytes.ValidUtf8(data)
    local i, n = 1, #data
    while i <= n do
        local c = byte(data, i)
        local length, minimum, code
        if c < 0x80 then length = 1
        elseif c >= 0xC2 and c <= 0xDF then length, code, minimum = 2, c - 0xC0, 0x80
        elseif c >= 0xE0 and c <= 0xEF then length, code, minimum = 3, c - 0xE0, 0x800
        elseif c >= 0xF0 and c <= 0xF4 then length, code, minimum = 4, c - 0xF0, 0x10000
        else return false end
        if length > 1 then
            if i + length - 1 > n then return false end
            for k = 1, length - 1 do
                local continuation = byte(data, i + k)
                if continuation < 0x80 or continuation > 0xBF then return false end
                code = code * 64 + (continuation - 0x80)
            end
            if code < minimum or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF) then return false end
        end
        i = i + length
    end
    return true
end

-- JavaScript string length (UTF-16 code units) of valid UTF-8, so limits match the lab.
function Bytes.Utf16Length(data)
    local count = 0
    for i = 1, #data do
        local c = byte(data, i)
        if c < 0x80 or c >= 0xC0 then count = count + (c >= 0xF0 and 2 or 1) end
    end
    return count
end

function Bytes.RandomHex(length, random)
    local out = {}
    for i = 1, length do
        local v = random(0, 15)
        out[i] = string.format("%x", v)
    end
    return table.concat(out)
end
