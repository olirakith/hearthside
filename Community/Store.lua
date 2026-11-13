local MS = _G.MS
MS.Community = MS.Community or {}
-- AzerothJourneyCommunityDB: versioned, bounded, separate from MultiScreenForeverDB.
-- Pure: the caller passes the raw SavedVariable and assigns the returned root back.
local Store = { schema = 1, characterLimit = 50 }
MS.Community.Store = Store

local function Table(value) return type(value) == "table" and value or nil end

function Store:Initialize(raw, currentKey)
    self.readOnly, self.status, self.dropped = false, "READY", 0
    local root = Table(raw)
    if root and type(root.schemaVersion) == "number" and root.schemaVersion > self.schema then
        -- Written by a newer Journey: never rewrite it. Community stays off for this load.
        self.readOnly, self.status, self.root = true, "SCHEMA_NEWER", root
        return root
    end
    if not root or root.schemaVersion ~= self.schema then
        root = { schemaVersion = self.schema, previousSchema = root and root.schemaVersion or nil }
        if Table(raw) then root.flags, root.characters, root.diagnostics = raw.flags, raw.characters, raw.diagnostics end
        self.status = Table(raw) and "MIGRATED" or "CREATED"
    end
    root.flags = MS.Community.Flags:Sanitize(root.flags)
    root.diagnostics = Table(root.diagnostics) or {}
    -- Optional, account-wide; an absent or malformed table is simply no evidence (no migration).
    root.evidence = MS.Community.Capabilities:SanitizeEvidence(root.evidence)
    -- Deterministic bound: the current character first, then most recently used, then key order.
    local source, keys = Table(root.characters) or {}, {}
    for key, bucket in pairs(source) do
        if MS.JourneyCharacterIdentity:IsKey(key) and Table(bucket) then keys[#keys + 1] = key end
    end
    local function seen(key) local value = source[key].lastSeenAt; return type(value) == "number" and value or 0 end
    table.sort(keys, function(a, b)
        if (a == currentKey) ~= (b == currentKey) then return a == currentKey end
        if seen(a) ~= seen(b) then return seen(a) > seen(b) end
        return a < b
    end)
    local characters = {}
    for index = 1, math.min(#keys, self.characterLimit) do characters[keys[index]] = self:SanitizeBucket(source[keys[index]]) end
    self.dropped = math.max(0, #keys - self.characterLimit)
    root.characters = characters
    self.root = root
    return root
end

-- Social tables are kept only through their owners' validators; without one they are dropped,
-- never carried over unvalidated.
function Store:SanitizeBucket(raw)
    local C = MS.Community
    local bucket = { lastSeenAt = type(raw.lastSeenAt) == "number" and raw.lastSeenAt or nil, memories = {}, order = {}, peer = {} }
    if C.MemoryBook then
        bucket.memories = Table(raw.memories) or {}
        C.MemoryBook:SanitizeBucket(bucket)
    end
    if C.Peer and C.Peer.SanitizeDurable then bucket.peer = C.Peer.SanitizeDurable(Table(raw.peer) or {}) end
    return bucket
end

function Store:Character(key, now)
    if self.readOnly or not self.root or not MS.JourneyCharacterIdentity:IsKey(key) then return nil end
    local characters = self.root.characters
    if not characters[key] then
        local count = 0
        for _ in pairs(characters) do count = count + 1 end
        if count >= self.characterLimit then return nil end
        characters[key] = self:SanitizeBucket({})
    end
    if type(now) == "number" then characters[key].lastSeenAt = now end
    return characters[key]
end

-- Forget this character's Community data only; flags and other characters are untouched.
function Store:Forget(key)
    if self.readOnly or not self.root or not self.root.characters[key] then return false end
    self.root.characters[key] = self:SanitizeBucket({})
    return true
end
