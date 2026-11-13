local MS = _G.MS
MS.Active = MS.Active or {}
-- Pure text helpers for player-written lines and share codes. Byte-level only: Lua strings are
-- bytes, and WoW's string.lower/upper do not understand UTF-8.
local Text = {}
MS.Active.Text = Text

local byte = string.byte

-- Strict UTF-8 check (same rules as Community.Bytes.ValidUtf8, kept local so Active stands alone).
function Text.ValidUtf8(data)
    if type(data) ~= "string" then return false end
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

-- Number of characters (code points) in valid UTF-8.
function Text.Length(data)
    local count = 0
    for i = 1, #data do
        local c = byte(data, i)
        if c < 0x80 or c >= 0xC0 then count = count + 1 end
    end
    return count
end

-- Longest prefix of at most maxBytes that never cuts a character in half.
function Text.Truncate(data, maxBytes)
    if #data <= maxBytes then return data end
    local cut = maxBytes
    -- Step back over continuation bytes to the start of the character that would be cut.
    while cut > 0 do
        local c = byte(data, cut + 1)
        if not c or c < 0x80 or c >= 0xC0 then break end
        cut = cut - 1
    end
    return data:sub(1, cut)
end

-- A line written by a player, or decoded from someone else's code: one line, no WoW escape
-- sequences (|c, |T, |H...), no control bytes, collapsed spaces, at most maxBytes, valid UTF-8.
-- Returns nil when nothing readable is left.
function Text.CleanLine(value, maxBytes)
    if type(value) ~= "string" then return nil end
    -- Explicit ASCII ranges: %c depends on the C locale and can match UTF-8 bytes.
    value = value:gsub("[%z\1-\31\127]", " "):gsub("|", "")
    value = value:gsub("  +", " "):match("^ *(.-) *$")
    if not Text.ValidUtf8(value) then return nil end
    value = Text.Truncate(value, maxBytes)
    value = value:match("^(.-) *$")
    if value == "" then return nil end
    return value
end

-- ASCII-only case folding: enough for comparing realm/character names the game capitalizes
-- itself, without pretending to fold accented letters.
function Text.FoldAscii(value)
    return (value:gsub("[A-Z]", string.lower))
end

-- "Name-Realm" as the game normalizes it: no spaces or apostrophes in the realm.
function Text.NormalizeRealm(realm)
    if type(realm) ~= "string" then return nil end
    realm = realm:gsub("[ \t']", "")
    if realm == "" then return nil end
    return realm
end

-- Parses what a player typed for a precise recipient. Exact name, the realm defaulting to the
-- author's; returns the canonical "Name-Realm" or nil. No fuzzy matching of any kind.
-- Forever characters have a first name and a surname, and "First-Surname" is what /w takes: there
-- defaultRealm is nil, a lone first name reaches nobody and "First Surname" is read as that form.
function Text.RecipientName(typed, defaultRealm)
    local clean = Text.CleanLine(typed, 80)
    if not clean then return nil end
    if not defaultRealm then clean = (clean:gsub("^([^%- ]+) ([^%- ]+)$", "%1-%2")) end
    local name, realm = clean:match("^([^%- ]+)%-(.+)$")
    if not name then name, realm = clean:match("^([^%- ]+)$"), defaultRealm end
    realm = Text.NormalizeRealm(realm)
    if not name or not realm or Text.Length(name) < 2 or Text.Length(name) > 12 or name:find("[%z\1-\64\91-\96\123-\127]") then return nil end
    -- Character names start with a capital: "aldric" is written "Aldric" (ASCII first letter only).
    return (name:gsub("^[a-z]", string.upper)) .. "-" .. realm
end

-- Comparison key for a canonical name: ASCII case folded, realm normalized.
function Text.NameKey(canonical)
    if type(canonical) ~= "string" then return nil end
    local name, realm = canonical:match("^(.-)%-(.+)$")
    realm = Text.NormalizeRealm(realm)
    if not name or name == "" or not realm then return nil end
    return Text.FoldAscii(name) .. "-" .. Text.FoldAscii(realm)
end
