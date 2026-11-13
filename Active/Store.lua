local MS = _G.MS
MS.Active = MS.Active or {}
-- AzerothJourneyActiveDB: versioned, bounded, separate from the engine and Community stores.
-- Pure: the caller passes the raw SavedVariable and assigns the returned root back.
--   seals       account-wide Sur mes pas records (a seal can be for another character of the account)
--   characters  per character: the running Contrat and a short history of finished ones
--   arbiter     the card arbiter's per-session quota (survives /reload, reset at login)
--   evidence    capabilities seen working on one client build
--   diagnostics bounded journal (Active.Diagnostics)
local Store = { schema = 1, characterLimit = 50 }
MS.Active.Store = Store

local function Table(value) return type(value) == "table" and value or nil end

-- A sub-table rebuilt from its known fields only (their owners validate the values).
local function Pick(raw, keys)
    local out = {}
    if type(raw) == "table" then for _, key in ipairs(keys) do out[key] = raw[key] end end
    return out
end

function Store:Initialize(raw, currentKey, now)
    self.readOnly, self.status, self.dropped = false, "READY", 0
    local root = Table(raw)
    if root and type(root.schemaVersion) == "number" and root.schemaVersion > self.schema then
        -- Written by a newer Journey: never rewrite it. Active features stay off for this load.
        self.readOnly, self.status, self.root = true, "SCHEMA_NEWER", root
        return root
    end
    if root and root.schemaVersion ~= self.schema then
        -- No older schema exists yet: a root without a valid version is repaired in place, every
        -- table below going through its validator (valid records survive, nothing else does).
        root.schemaVersion = self.schema
        self.status = "REPAIRED"
    elseif not root then
        root = { schemaVersion = self.schema }
        self.status = "CREATED"
    end
    root.diagnostics = Pick(root.diagnostics, { "schema", "entries", "counters", "dropped", "seq" })
    root.arbiter = Pick(root.arbiter, { "counts", "lastAt" })
    root.evidence = MS.Active.Capabilities:SanitizeEvidence(root.evidence)
    root.seals = MS.Active.SealBook:Sanitize(Table(root.seals) or {}, now)
    root.muted = root.muted == true or nil
    root.noCredits = root.noCredits == true or nil
    -- Deterministic bound: the current character first, then most recently seen, then key order.
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
    for index = 1, math.min(#keys, self.characterLimit) do
        characters[keys[index]] = self:SanitizeBucket(source[keys[index]])
    end
    self.dropped = math.max(0, #keys - self.characterLimit)
    -- Only known keys survive: stray or malformed top-level data never grows the file.
    root = { schemaVersion = self.schema, diagnostics = root.diagnostics, arbiter = root.arbiter,
        evidence = root.evidence, seals = root.seals, muted = root.muted, noCredits = root.noCredits,
        characters = characters }
    self.root = root
    return root
end

function Store:SanitizeBucket(raw)
    local Engine = MS.Active.ContractEngine
    local bucket = { lastSeenAt = type(raw.lastSeenAt) == "number" and raw.lastSeenAt or nil }
    bucket.contract = Engine:SanitizeContract(raw.contract)
    bucket.history = Engine:SanitizeHistory(raw.history)
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
