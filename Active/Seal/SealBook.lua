local MS = _G.MS
MS.Active = MS.Active or {}
-- Sur mes pas domain. Pure: no WoW API; the adapters hand it identities, samples and clocks.
--
-- A seal is one place (zone uiMapID + normalized x,y), one short line and one recipient:
--   NEXT  my next character: any other character of this account (local, no code)
--   CHAR  one exact character, by name-realm (shared by code)
--   ANY   anyone holding the code (shared by code)
-- States: ARMED (waiting here to be found), SENT (the author's copy of a shared code),
-- OPENED (found; the words stay readable), ARCHIVED (expired or dropped: no words, no place).
local Book = {
    radius = 20,          -- yards, on the seal's own map (UNVERIFIED until runtime P1)
    nearRadius = 70,      -- yards: "the seal feels close", said without saying where
    hintBytes = 64,
    streak = 3,           -- consecutive in-radius samples before opening
    expireSeconds = 365 * 86400,
    limits = { ARMED = 30, SENT = 30, OPENED = 50, ARCHIVED = 100 },
}
MS.Active.SealBook = Book
Book.kinds = { NEXT = true, CHAR = true, ANY = true }
Book.states = { ARMED = true, SENT = true, OPENED = true, ARCHIVED = true }

local function Num(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function Unit(value) return Num(value) and value >= 0 and value <= 1 end
local function Id(value) return type(value) == "string" and value:find("^%x%x%x%x%x%x%x%x$") ~= nil end

local function Archived(seal, reason, now)
    return { id = seal.id, kind = seal.kind, state = "ARCHIVED", reason = reason, archivedAt = now or seal.archivedAt }
end

-- One stored record, validated field by field. nil when it cannot be trusted at all.
function Book:SanitizeRecord(raw, now)
    local Text = MS.Active.Text
    if type(raw) ~= "table" or not Id(raw.id) or not self.kinds[raw.kind] or not self.states[raw.state] then return nil end
    if raw.state == "ARCHIVED" then
        return { id = raw.id, kind = raw.kind, state = "ARCHIVED", reason = type(raw.reason) == "string" and raw.reason:sub(1, 16) or "UNKNOWN",
            archivedAt = Num(raw.archivedAt) and raw.archivedAt or nil }
    end
    local seal = { id = raw.id, kind = raw.kind, state = raw.state, origin = raw.origin == "IMPORTED" and "IMPORTED" or "SELF",
        createdAt = Num(raw.createdAt) and raw.createdAt or nil, mapID = Num(raw.mapID) and raw.mapID or nil,
        author = Text.CleanLine(raw.author, MS.Active.SealCodec.authorBytes), text = Text.CleanLine(raw.text, MS.Active.SealCodec.textBytes) }
    if not seal.createdAt or not seal.mapID or not seal.author or not seal.text then return nil end
    if raw.kind == "NEXT" then
        if not MS.JourneyCharacterIdentity:IsKey(raw.authorKey) or seal.origin ~= "SELF" then return nil end
        seal.authorKey = raw.authorKey
        if raw.state == "ARMED" then seal.hint = Text.CleanLine(raw.hint, self.hintBytes) end
    end
    if raw.kind == "CHAR" then
        if not Num(raw.recipientHash) or raw.recipientHash <= 0 then return nil end
        seal.recipientHash = raw.recipientHash
        seal.recipient = Text.CleanLine(raw.recipient, 80)
    end
    if raw.state == "ARMED" then
        if not Unit(raw.x) or not Unit(raw.y) then return nil end
        seal.x, seal.y = raw.x, raw.y
        if seal.kind ~= "NEXT" and seal.origin ~= "IMPORTED" then return nil end
        if Num(now) and now - seal.createdAt > self.expireSeconds then return Archived(seal, "EXPIRED", now) end
    elseif raw.state == "SENT" then
        -- The stored code must decode to this very seal; only its canonical form is kept (no
        -- surrounding text, no escape sequence ever reaches a copy box or the chat line).
        local Codec = MS.Active.SealCodec
        if seal.origin ~= "SELF" or seal.kind == "NEXT" or type(raw.code) ~= "string" or #raw.code > 400 then return nil end
        local decoded = Codec.Decode(raw.code)
        if not decoded or decoded.id ~= seal.id or decoded.kind ~= seal.kind or decoded.mapID ~= seal.mapID
            or decoded.text ~= seal.text or decoded.author ~= seal.author
            or decoded.createdAt ~= math.floor(seal.createdAt)
            or decoded.recipientHash ~= (seal.kind == "CHAR" and seal.recipientHash or 0) then return nil end
        seal.code = Codec.Encode(decoded)
        if not seal.code then return nil end
    elseif raw.state == "OPENED" then
        seal.openedAt = Num(raw.openedAt) and raw.openedAt or seal.createdAt
        seal.openedBy = MS.JourneyCharacterIdentity:IsKey(raw.openedBy) and raw.openedBy or nil
        seal.seen = raw.seen == true
    end
    return seal
end

local function Newest(a, b)
    local ta = a.openedAt or a.archivedAt or a.createdAt or 0
    local tb = b.openedAt or b.archivedAt or b.createdAt or 0
    if ta ~= tb then return ta > tb end
    return a.id < b.id
end

-- Applies the per-state limits, newest first. Opened seals beyond their limit are archived
-- (their words leave); everything else beyond its limit is dropped.
function Book:Bound(seals, now)
    local byState = { ARMED = {}, SENT = {}, OPENED = {}, ARCHIVED = {} }
    for _, seal in pairs(seals) do byState[seal.state][#byState[seal.state] + 1] = seal end
    local result, archivedCount = {}, 0
    for _, state in ipairs({ "ARMED", "SENT", "OPENED" }) do
        table.sort(byState[state], Newest)
        for index, seal in ipairs(byState[state]) do
            if index <= self.limits[state] then result[seal.id] = seal
            elseif state == "OPENED" then
                local archived = Archived(seal, "ROTATED", now)
                byState.ARCHIVED[#byState.ARCHIVED + 1] = archived
                archivedCount = archivedCount + 1
            end
        end
    end
    table.sort(byState.ARCHIVED, Newest)
    for index, seal in ipairs(byState.ARCHIVED) do
        if index <= self.limits.ARCHIVED and not result[seal.id] then result[seal.id] = seal end
    end
    return result, archivedCount
end

function Book:Sanitize(raw, now)
    local seals = {}
    for key, value in pairs(type(raw) == "table" and raw or {}) do
        local seal = self:SanitizeRecord(value, now)
        if seal and seal.id == key then seals[key] = seal end
    end
    return (self:Bound(seals, now))
end

function Book:Count(seals, state)
    local count = 0
    for _, seal in pairs(seals) do if seal.state == state then count = count + 1 end end
    return count
end

-- A seal this character may find. NEXT: any character of the account but its author.
-- CHAR: only the character the code names. ANY: whoever imported the code.
function Book:IsFor(seal, identity)
    if seal.state ~= "ARMED" or type(identity) ~= "table" or not identity.key then return false end
    if seal.kind == "NEXT" then return seal.authorKey ~= identity.key end
    if seal.kind == "CHAR" then return self:IsRecipient(seal.recipientHash, identity) end
    return seal.kind == "ANY"
end

-- A Forever surname. Elsewhere the game's second name is the realm, which is no surname.
function Book:Surname(identity)
    local Text = MS.Active.Text
    local surname = type(identity) == "table" and Text.NormalizeRealm(identity.surname) or nil
    if surname and surname ~= Text.NormalizeRealm(identity.realm) then return surname end
end

-- The name other players reach this character by: "First-Surname", else "Name-Realm".
function Book:IdentityName(identity)
    local name = type(identity) == "table" and identity.firstName
    local suffix = self:Surname(identity) or (type(identity) == "table" and MS.Active.Text.NormalizeRealm(identity.realm))
    if not name or not suffix then return nil end
    return name .. "-" .. suffix
end

-- Before surnames were read, a character was "First-Realm": codes of that form stay valid.
local function LegacyName(identity)
    local Text = MS.Active.Text
    local realm = type(identity) == "table" and Text.NormalizeRealm(identity.realm)
    if not realm or not identity.firstName then return nil end
    return identity.firstName .. "-" .. realm
end

function Book:IdentityHash(identity)
    local name = self:IdentityName(identity)
    return name and MS.Active.SealCodec.RecipientHash(MS.Active.Text.NameKey(name)) or nil
end

function Book:IsRecipient(hash, identity)
    if hash == self:IdentityHash(identity) then return true end
    local legacy = LegacyName(identity)
    return legacy ~= nil and hash == MS.Active.SealCodec.RecipientHash(MS.Active.Text.NameKey(legacy))
end

function Book:ArmedFor(seals, identity)
    local list = {}
    for _, seal in pairs(seals) do if self:IsFor(seal, identity) then list[#list + 1] = seal end end
    table.sort(list, function(a, b) if a.createdAt ~= b.createdAt then return a.createdAt < b.createdAt end return a.id < b.id end)
    return list
end

-- Sealing needs a place Journey can find again: a settled, readable, outdoor zone map with a
-- position and a world size, out of combat, alive, not on a flight, not in an instance.
-- Returns true or false, reason.
function Book:CanSealHere(sample)
    if type(sample) ~= "table" then return false, "NO_POSITION" end
    if sample.combat ~= false then return false, "COMBAT" end
    if sample.settled ~= true then return false, "UNSETTLED" end
    if sample.instance ~= false then return false, "INSTANCE" end
    if sample.dead ~= false then return false, "DEAD" end
    if sample.taxi == true then return false, "TAXI" end
    if sample.indoors ~= false then return false, "INDOORS" end
    if not Num(sample.mapID) or sample.mapType ~= 3 then return false, "MAP_LEVEL" end
    if not Unit(sample.x) or not Unit(sample.y) then return false, "NO_POSITION" end
    if not Num(sample.width) or not Num(sample.height) or sample.width <= 0 or sample.height <= 0 then return false, "NO_DISTANCE" end
    return true
end

-- One sample against one seal: NEAR | FAR | OTHER_MAP | MAP_LEVEL | UNSETTLED | INSTANCE |
-- INDOORS | NO_POSITION | NO_DISTANCE | COMBAT | DEAD | TAXI. Only NEAR counts towards opening.
function Book:Classify(seal, sample)
    if type(sample) ~= "table" or sample.settled ~= true then return "UNSETTLED" end
    if sample.instance ~= false then return "INSTANCE" end
    if sample.mapID ~= seal.mapID then return "OTHER_MAP" end
    -- The same readable zone map as at sealing time, or nothing.
    if sample.mapType ~= 3 then return "MAP_LEVEL" end
    if sample.indoors ~= false then return "INDOORS" end
    if not Unit(sample.x) or not Unit(sample.y) then return "NO_POSITION" end
    if not Num(sample.width) or not Num(sample.height) or sample.width <= 0 or sample.height <= 0 then return "NO_DISTANCE" end
    local dx, dy = (sample.x - seal.x) * sample.width, (sample.y - seal.y) * sample.height
    if math.sqrt(dx * dx + dy * dy) > self.radius then return "FAR" end
    if sample.combat ~= false then return "COMBAT" end
    if sample.dead ~= false then return "DEAD" end
    if sample.taxi ~= false then return "TAXI" end
    return "NEAR"
end

-- Close enough to say so, too far to open, and free to read it: a fight, a ghost or a flight
-- passing over stays silent.
function Book:Vicinity(seal, sample)
    if self:Classify(seal, sample) ~= "FAR" then return false end
    if sample.combat ~= false or sample.dead ~= false or sample.taxi ~= false then return false end
    local dx, dy = (sample.x - seal.x) * sample.width, (sample.y - seal.y) * sample.height
    return math.sqrt(dx * dx + dy * dy) <= self.nearRadius
end

local function NewId(seals, random)
    for _ = 1, 16 do
        local id = string.format("%04x%04x", random(0, 65535), random(0, 65535))
        if not seals[id] then return id end
    end
end

-- input: { kind, text, recipient (CHAR: canonical "Name-Realm"), identity, sample, now, random,
-- hint (optional subzone name; NEXT only, the AJ1 code has no room for it) }
-- Returns the record (already stored) or nil, reason.
function Book:Create(seals, input)
    local Text, Codec = MS.Active.Text, MS.Active.SealCodec
    if not self.kinds[input.kind] then return nil, "KIND" end
    local ok, reason = self:CanSealHere(input.sample)
    if not ok then return nil, reason end
    local words = Text.CleanLine(input.text, Codec.textBytes)
    if not words then return nil, "EMPTY" end
    local identity = input.identity
    if type(identity) ~= "table" or not identity.key or not identity.firstName or not identity.realm then return nil, "IDENTITY" end
    local author = Text.CleanLine(self:IdentityName(identity), Codec.authorBytes)
    local recipientKey = input.kind == "CHAR" and Text.NameKey(input.recipient) or nil
    if input.kind == "CHAR" and (not recipientKey or recipientKey == Text.NameKey(author)) then return nil, "RECIPIENT" end
    local state = input.kind == "NEXT" and "ARMED" or "SENT"
    if self:Count(seals, state) >= self.limits[state] and state == "ARMED" then return nil, "FULL" end
    local id = NewId(seals, input.random)
    if not id then return nil, "ID" end
    local seal = { id = id, kind = input.kind, state = state, origin = "SELF", createdAt = input.now, mapID = input.sample.mapID,
        author = author, text = words }
    if input.kind == "NEXT" then
        seal.authorKey, seal.x, seal.y = identity.key, input.sample.x, input.sample.y
        seal.hint = Text.CleanLine(input.hint, self.hintBytes)
    else
        seal.recipientHash = recipientKey and Codec.RecipientHash(recipientKey) or nil
        seal.recipient = input.kind == "CHAR" and input.recipient or nil
        seal.code = Codec.Encode({ kind = input.kind, id = id, createdAt = input.now, mapID = input.sample.mapID,
            x = input.sample.x, y = input.sample.y, recipientHash = seal.recipientHash, author = author, text = words })
        if not seal.code then return nil, "ENCODE" end
    end
    seals[id] = seal
    local bounded = self:Bound(seals, input.now)
    for key in pairs(seals) do seals[key] = bounded[key] end
    return seal
end

-- May this character import a decoded code? Returns true, or false and
-- DUPLICATE | ALREADY_OPENED | OWN_SEAL | WRONG_RECIPIENT | EXPIRED | FULL.
function Book:CanImport(seals, decoded, identity, now)
    local Text = MS.Active.Text
    local existing = seals[decoded.id]
    if existing and existing.state == "OPENED" then return false, "ALREADY_OPENED" end
    if existing and existing.state ~= "SENT" then return false, "DUPLICATE" end
    local authorKey = decoded.author and Text.NameKey(decoded.author)
    if authorKey and (authorKey == Text.NameKey(self:IdentityName(identity)) or authorKey == Text.NameKey(LegacyName(identity))) then
        return false, "OWN_SEAL"
    end
    if decoded.kind == "CHAR" and not self:IsRecipient(decoded.recipientHash, identity) then return false, "WRONG_RECIPIENT" end
    -- The author's copy (SENT) lives in the same account-wide store when the code was meant for
    -- another character of the same player: the seal now waits for that character instead.
    if Num(now) and now - decoded.createdAt > self.expireSeconds then return false, "EXPIRED" end
    if self:Count(seals, "ARMED") >= self.limits.ARMED then return false, "FULL" end
    if existing and existing.kind ~= decoded.kind then return false, "DUPLICATE" end
    return true
end

-- Imports a decoded code for this character. Returns the armed record, or nil and a CanImport reason.
function Book:Import(seals, decoded, identity, now)
    local ok, reason = self:CanImport(seals, decoded, identity, now)
    if not ok then return nil, reason end
    local seal = { id = decoded.id, kind = decoded.kind, state = "ARMED", origin = "IMPORTED", createdAt = decoded.createdAt,
        mapID = decoded.mapID, x = decoded.x, y = decoded.y, author = decoded.author, text = decoded.text,
        recipientHash = decoded.kind == "CHAR" and decoded.recipientHash or nil }
    seals[seal.id] = seal
    return seal
end

-- Opening keeps the words, the author and the dates; the exact place is no longer needed.
function Book:Open(seals, id, identity, now)
    local seal = seals[id]
    if not seal or not self:IsFor(seal, identity) then return nil end
    seal.state, seal.openedAt, seal.openedBy, seal.seen = "OPENED", now, identity.key, false
    seal.x, seal.y, seal.hint = nil, nil, nil
    local bounded = self:Bound(seals, now)
    for key in pairs(seals) do seals[key] = bounded[key] end
    return seal
end

function Book:Abandon(seals, id, now)
    local seal = seals[id]
    if not seal or (seal.state ~= "ARMED" and seal.state ~= "SENT") then return false end
    seals[id] = Archived(seal, "ABANDONED", now)
    return true
end

-- Whole days between two timestamps (for "sealed 3 days ago").
function Book.Days(from, to)
    if not Num(from) or not Num(to) or to < from then return 0 end
    return math.floor((to - from) / 86400)
end
