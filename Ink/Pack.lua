local MS = _G.MS
MS.Ink = MS.Ink or {}
-- A small LZSS packer for seals: written prose repeats itself enough to save a third or more.
-- Pure and bounded: unpacking someone else's bytes never reads outside them, never writes more
-- than the caller allows, and fails with nil on anything that does not hold together.
--
-- Stream: groups of up to 8 tokens, each group led by one flag byte (bit k set = token k is a
-- copy). A literal is one byte. A copy is two bytes: 12-bit distance back (1-4095), 4-bit length
-- (3-18).
local Pack = { window = 4095, minMatch = 3, maxMatch = 18, chain = 24 }
MS.Ink.Pack = Pack

local byte, char, floor, sub = string.byte, string.char, math.floor, string.sub

function Pack.Compress(data)
    local n, out, heads = #data, {}, {}
    local flagsAt, flags, bit = nil, 0, 8
    local function Token(isCopy, ...)
        if bit == 8 then
            if flagsAt then out[flagsAt] = char(flags) end
            out[#out + 1] = ""
            flagsAt, flags, bit = #out, 0, 0
        end
        if isCopy then flags = flags + 2 ^ bit end
        bit = bit + 1
        for _, value in ipairs({ ... }) do out[#out + 1] = value end
    end
    local function Remember(at)
        if at + 2 > n then return end
        local key = sub(data, at, at + 2)
        local list = heads[key]
        if not list then list = {}; heads[key] = list end
        list[#list + 1] = at
        if #list > Pack.chain * 2 then
            -- Keep the most recent positions only.
            local kept = {}
            for index = #list - Pack.chain + 1, #list do kept[#kept + 1] = list[index] end
            heads[key] = kept
        end
    end
    local at = 1
    while at <= n do
        local bestLength, bestDistance = 0, 0
        local list = at + 2 <= n and heads[sub(data, at, at + 2)] or nil
        if list then
            for index = #list, math.max(1, #list - Pack.chain + 1), -1 do
                local from = list[index]
                local distance = at - from
                if distance > Pack.window then break end
                local length = 0
                while length < Pack.maxMatch and at + length <= n and byte(data, from + length) == byte(data, at + length) do
                    length = length + 1
                end
                if length > bestLength then bestLength, bestDistance = length, distance end
                if bestLength == Pack.maxMatch then break end
            end
        end
        if bestLength >= Pack.minMatch then
            Token(true, char(floor(bestDistance / 16)), char((bestDistance % 16) * 16 + bestLength - Pack.minMatch))
            for step = 0, bestLength - 1 do Remember(at + step) end
            at = at + bestLength
        else
            Token(false, sub(data, at, at))
            Remember(at)
            at = at + 1
        end
    end
    if flagsAt then out[flagsAt] = char(flags) end
    return table.concat(out)
end

-- Returns the unpacked bytes, or nil when the stream is broken or would exceed maxOut.
function Pack.Decompress(data, maxOut)
    if type(data) ~= "string" then return nil end
    local out, size, at, n = {}, 0, 1, #data
    while at <= n do
        local flags = byte(data, at)
        at = at + 1
        for bit = 0, 7 do
            if at > n then break end
            local isCopy = floor(flags / 2 ^ bit) % 2 == 1
            if isCopy then
                if at + 1 > n then return nil end
                local high, low = byte(data, at), byte(data, at + 1)
                at = at + 2
                local distance, length = high * 16 + floor(low / 16), low % 16 + Pack.minMatch
                if distance < 1 or distance > size or size + length > maxOut then return nil end
                for _ = 1, length do
                    size = size + 1
                    out[size] = out[size - distance]
                end
            else
                if size + 1 > maxOut then return nil end
                size = size + 1
                out[size] = sub(data, at, at)
                at = at + 1
            end
        end
    end
    return table.concat(out)
end
