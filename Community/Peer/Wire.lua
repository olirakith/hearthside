local MS = _G.MS
MS.Community = MS.Community or {}
-- Peer protocol wire format. Same envelope, limits, codes
-- and error names. ASCII envelope + base64 payload. CRC32 detects accidents, not a malicious peer.
local W = {}
MS.Community.Wire = W
local Bytes = MS.Community.Bytes

W.LIMITS = { wire = 200, fragment = 96, fragments = 64, logical = 6144 }
W.TYPES = { HELLO = "H", HELLO_ACK = "A", MEMORY_PROPOSE = "P", MEMORY_ACCEPT = "Y", MEMORY_DECLINE = "N",
    MEMORY_FRAGMENT = "F", MEMORY_COMPLETE = "C", MEMORY_ACK = "K", SNAPSHOT_REQUEST = "Q", SNAPSHOT_RESPONSE = "S",
    ERROR = "E", REFUSE = "R" }
W.NAMES = {}
for name, code in pairs(W.TYPES) do W.NAMES[code] = name end
-- JSON null inside decoded arrays (Lua tables cannot hold nil in a sequence).
W.NULL = setmetatable({}, { __tostring = function() return "null" end })

local function Fail(code) error({ code = code }, 0) end
local function Check(condition, code) if not condition then Fail(code) end end
W.Check = Check
function W.Code(err) return type(err) == "table" and err.code or tostring(err) end

W.checksum = Bytes.Crc32
function W.token(value, length) return Bytes.IsHex(value, length) end
local function Integer(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value) and value >= minimum and value <= maximum
end
W.Integer = Integer

-- ---------- strict JSON (arrays, strings, safe integers, null, booleans; output = JSON.stringify) ----------
local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function EncodeString(value)
    return '"' .. value:gsub('[%z\1-\31"\\]', function(c)
        return ESCAPES[c] or (c:byte() < 32 and string.format("\\u%04x", c:byte())) or c
    end) .. '"'
end
local function Length(value) return type(value.n) == "number" and value.n or #value end
local function Encode(value, depth)
    Check(depth < 8, "JSON_DEPTH")
    if value == W.NULL then return "null" end
    local kind = type(value)
    if kind == "string" then Check(Bytes.ValidUtf8(value), "JSON_UTF8"); return EncodeString(value) end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then Check(Integer(value, -9007199254740991, 9007199254740991), "JSON_NUMBER"); return string.format("%.0f", value) end
    Check(kind == "table", "JSON_TYPE")
    local parts = {}
    for index = 1, Length(value) do
        local item = value[index]
        Check(item ~= nil, "JSON_HOLE")
        parts[index] = Encode(item, depth + 1)
    end
    return "[" .. table.concat(parts, ",") .. "]"
end
function W.json(value) return Encode(value, 0) end

local function Utf8(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then return string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64) end
    if code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
    end
    return string.char(0xF0 + math.floor(code / 262144), 0x80 + math.floor(code / 4096) % 64,
        0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
end

-- Same grammar as JSON.parse in the lab (whitespace, fractions, exponents, objects, every
-- escape). Objects decode to { __object = true } tables, which every schema check refuses,
-- exactly where the lab's validation refuses them. Business validation decides, not the parser.
W.OBJECT = "__object"
function W.parse(payload)
    Check(type(payload) == "string" and Bytes.ValidUtf8(payload), "UTF8")
    local position = 1
    local Value
    local function Peek() return payload:sub(position, position) end
    local function Space() position = (payload:find("[^ \t\n\r]", position) or #payload + 1) end
    local function String()
        position = position + 1
        local out = {}
        while true do
            local c = Peek()
            Check(c ~= "", "JSON")
            if c == '"' then position = position + 1; return table.concat(out) end
            if c == "\\" then
                local e = payload:sub(position + 1, position + 1)
                local simple = ({ ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" })[e]
                if simple then out[#out + 1] = simple; position = position + 2
                elseif e == "u" then
                    local hex = payload:sub(position + 2, position + 5)
                    Check(hex:find("^%x%x%x%x$"), "JSON")
                    local code = tonumber(hex, 16)
                    position = position + 6
                    if code >= 0xD800 and code <= 0xDBFF then
                        local low = payload:sub(position, position + 5)
                        -- A lone surrogate is valid JSON but not valid UTF-8 text: refused like TextDecoder.
                        Check(low:find("^\\u[dD][c-fC-F]%x%x$"), "JSON_SURROGATE")
                        code = 0x10000 + (code - 0xD800) * 1024 + (tonumber(low:sub(3), 16) - 0xDC00)
                        position = position + 6
                    else
                        Check(code < 0xDC00 or code > 0xDFFF, "JSON_SURROGATE")
                    end
                    out[#out + 1] = Utf8(code)
                else Fail("JSON") end
            else
                Check(c:byte() >= 32, "JSON")
                out[#out + 1] = c
                position = position + 1
            end
        end
    end
    function Value(depth)
        Check(depth < 16, "JSON_DEPTH")
        Space()
        local c = Peek()
        local result
        if c == "[" then
            position = position + 1
            result = { n = 0 }
            Space()
            if Peek() == "]" then position = position + 1
            else
                while true do
                    result.n = result.n + 1
                    result[result.n] = Value(depth + 1)
                    Space()
                    local d = Peek()
                    position = position + 1
                    if d == "]" then break end
                    Check(d == ",", "JSON")
                end
            end
        elseif c == "{" then
            position = position + 1
            result = { [W.OBJECT] = true }
            Space()
            if Peek() == "}" then position = position + 1
            else
                while true do
                    Space()
                    Check(Peek() == '"', "JSON")
                    local key = String()
                    Space()
                    Check(Peek() == ":", "JSON")
                    position = position + 1
                    result[key] = Value(depth + 1)
                    Space()
                    local d = Peek()
                    position = position + 1
                    if d == "}" then break end
                    Check(d == ",", "JSON")
                end
            end
        elseif c == '"' then result = String()
        elseif payload:sub(position, position + 3) == "null" then position = position + 4; result = W.NULL
        elseif payload:sub(position, position + 3) == "true" then position = position + 4; result = true
        elseif payload:sub(position, position + 4) == "false" then position = position + 5; result = false
        else
            -- JSON number: -?(0|[1-9][0-9]*)(.[0-9]+)?([eE][+-]?[0-9]+)?
            local p = position
            if payload:sub(p, p) == "-" then p = p + 1 end
            local int = payload:match("^%d+", p)
            Check(int ~= nil and (int == "0" or int:sub(1, 1) ~= "0"), "JSON")
            p = p + #int
            if payload:sub(p, p) == "." then
                local fraction = payload:match("^%d+", p + 1)
                Check(fraction ~= nil, "JSON")
                p = p + 1 + #fraction
            end
            local e = payload:sub(p, p)
            if e == "e" or e == "E" then
                p = p + 1
                local sign = payload:sub(p, p)
                if sign == "+" or sign == "-" then p = p + 1 end
                local exponent = payload:match("^%d+", p)
                Check(exponent ~= nil, "JSON")
                p = p + #exponent
            end
            result = tonumber(payload:sub(position, p - 1))
            Check(result ~= nil and result == result and result ~= math.huge and result ~= -math.huge, "JSON_NUMBER")
            position = p
        end
        return result
    end
    local value = Value(0)
    Space()
    Check(position == #payload + 1, "JSON")
    return value
end

function W.IsArray(value) return type(value) == "table" and value ~= W.NULL and value.n ~= nil and not value[W.OBJECT] end

function W.equal(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" or a == W.NULL or b == W.NULL or a[W.OBJECT] or b[W.OBJECT] then return false end
    if Length(a) ~= Length(b) then return false end
    for index = 1, Length(a) do if not W.equal(a[index], b[index]) then return false end end
    return true
end

-- ---------- envelope ----------
-- J1|type|senderReference|messageId|index/count|payloadLength|payloadCRC|fragmentLength|fragmentCRC|base64
function W.encode(f)
    Check(W.TYPES[f.type], "TYPE")
    Check(W.token(f.senderReference, 12) and W.token(f.messageId, 16), "IDENTIFIER")
    local data = f.payload
    local index, count = f.index or 1, f.count or 1
    Check(type(data) == "string", "PAYLOAD")
    Check(Integer(count, 1, W.LIMITS.fragments) and Integer(index, 1, count), "FRAGMENT_RANGE")
    Check(Integer(f.totalLength, 0, W.LIMITS.logical) and W.token(f.hash, 8), "LOGICAL_METADATA")
    Check(#data <= W.LIMITS.fragment, "FRAGMENT_SIZE")
    if f.type ~= "MEMORY_FRAGMENT" then
        Check(index == 1 and count == 1 and f.totalLength == #data and f.hash == W.checksum(data), "CONTROL_METADATA")
    end
    local packet = table.concat({ "J1", W.TYPES[f.type], f.senderReference, f.messageId, index .. "/" .. count,
        tostring(f.totalLength), f.hash, tostring(#data), W.checksum(data), Bytes.Base64Encode(data) }, "|")
    Check(#packet <= W.LIMITS.wire, "WIRE_SIZE")
    return packet
end

local function Fields(packet)
    local parts = {}
    for part in (packet .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = part end
    return parts
end

function W.decode(packet)
    Check(type(packet) == "string" and #packet <= W.LIMITS.wire and not packet:find("[^\32-\126]"), "WIRE_SIZE_OR_ENCODING")
    local parts = Fields(packet)
    Check(#parts == 10, "ENVELOPE")
    Check(parts[1] == "J1", "PROTOCOL_VERSION")
    local kind = W.NAMES[parts[2]]
    Check(kind and #parts[2] == 1, "TYPE")
    Check(W.token(parts[3], 12) and W.token(parts[4], 16), "IDENTIFIER")
    local index, count = parts[5]:match("^([1-9]%d?)/([1-9]%d?)$")
    Check(index ~= nil, "FRAGMENT_RANGE")
    Check(parts[6]:find("^0$") or parts[6]:find("^[1-9]%d?%d?%d?$"), "LENGTH")
    Check(parts[8]:find("^0$") or parts[8]:find("^[1-9]%d?$"), "LENGTH")
    Check(W.token(parts[7], 8) and W.token(parts[9], 8), "CHECKSUM_FORMAT")
    Check(parts[10]:find("^[A-Za-z0-9+/]*=?=?$") and #parts[10] % 4 == 0, "BASE64")
    local payload = Bytes.Base64Decode(parts[10])
    Check(payload ~= nil, "BASE64_CANONICAL")
    index, count = tonumber(index), tonumber(count)
    local totalLength = tonumber(parts[6])
    Check(Integer(count, 1, W.LIMITS.fragments) and Integer(index, 1, count) and Integer(totalLength, 0, W.LIMITS.logical), "FRAGMENT_RANGE")
    Check(#payload == tonumber(parts[8]) and #payload <= W.LIMITS.fragment, "FRAGMENT_LENGTH")
    Check(W.checksum(payload) == parts[9], "FRAGMENT_CHECKSUM")
    if kind ~= "MEMORY_FRAGMENT" then
        Check(count == 1 and index == 1 and totalLength == #payload and parts[7] == W.checksum(payload), "CONTROL_METADATA")
    end
    return { type = kind, senderReference = parts[3], messageId = parts[4], index = index, count = count,
        totalLength = totalLength, hash = parts[7], payload = payload }
end

function W.fragments(bytes)
    Check(type(bytes) == "string" and #bytes > 0 and #bytes <= W.LIMITS.logical, "LOGICAL_SIZE")
    local output = {}
    for offset = 1, #bytes, W.LIMITS.fragment do output[#output + 1] = bytes:sub(offset, offset + W.LIMITS.fragment - 1) end
    return output
end
