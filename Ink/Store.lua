local MS = _G.MS
MS.Ink = MS.Ink or {}
-- HearthsideInkDB: versioned and bounded, separate from every other Hearthside store. Pure: the
-- caller passes the raw SavedVariable and assigns the returned root back.
--   tales       account-wide, by id: tales written here or kept from a seal
--   characters  per character: progress in each tale
--   drafts      account-wide, by id: tales being written (schema 2)
-- Schema 3: people, emotes, kills and conditions. An older Hearthside must not rewrite (and drop) those pages.
local Store = { schema = 3, taleLimit = 50, characterLimit = 50, draftLimit = 20 }
MS.Ink.Store = Store

local function Table(value) return type(value) == "table" and value or nil end
local function Num(value) return type(value) == "number" and value == value and value >= 0 end

-- The character who gave a tale in the game, or nil.
local function From(value)
    return type(value) == "string" and MS.Ink.Tale.Line(value, MS.Ink.Tale.authorBytes) or nil
end

-- origin: WRITTEN (by a character of this account) or KEPT (imported). keptAt orders the bound.
local function SanitizeEntry(raw)
    if not Table(raw) then return nil end
    local tale = MS.Ink.Tale.Sanitize(raw.tale)
    if not tale then return nil end
    return { tale = tale, origin = raw.origin == "WRITTEN" and "WRITTEN" or "KEPT",
        keptAt = Num(raw.keptAt) and raw.keptAt or 0, from = From(raw.from) }
end

function Store:Initialize(raw, currentKey)
    self.readOnly, self.status = false, "READY"
    local root = Table(raw)
    if root and type(root.schemaVersion) == "number" and root.schemaVersion > self.schema then
        -- Written by a newer Hearthside: never rewrite it.
        self.readOnly, self.status, self.root = true, "SCHEMA_NEWER", root
        return root
    end
    if not root then
        root, self.status = {}, "CREATED"
    elseif root.schemaVersion == 1 or root.schemaVersion == 2 then
        -- Schema 1 had no drafts: everything else reads the same.
        self.status = "MIGRATED"
    elseif root.schemaVersion ~= self.schema then
        self.status = "REPAIRED"
    end
    -- Tales: valid entries only, most recently kept first, within the bound.
    local entries = {}
    for id, entry in pairs(Table(root.tales) or {}) do
        local clean = SanitizeEntry(entry)
        if clean and clean.tale.id == id then entries[#entries + 1] = clean end
    end
    table.sort(entries, function(a, b)
        if a.keptAt ~= b.keptAt then return a.keptAt > b.keptAt end
        return a.tale.id < b.tale.id
    end)
    local tales = {}
    for index = 1, math.min(#entries, self.taleLimit) do tales[entries[index].tale.id] = entries[index] end
    -- Characters: the current one first, then most recently seen.
    local source, keys = Table(root.characters) or {}, {}
    for key, bucket in pairs(source) do
        if MS.JourneyCharacterIdentity:IsKey(key) and Table(bucket) then keys[#keys + 1] = key end
    end
    local function seen(key) return Num(source[key].lastSeenAt) and source[key].lastSeenAt or 0 end
    table.sort(keys, function(a, b)
        if (a == currentKey) ~= (b == currentKey) then return a == currentKey end
        if seen(a) ~= seen(b) then return seen(a) > seen(b) end
        return a < b
    end)
    local characters = {}
    for index = 1, math.min(#keys, self.characterLimit) do
        characters[keys[index]] = self:SanitizeBucket(source[keys[index]], tales)
    end
    -- Drafts: valid ones only, most recently edited first, within the bound.
    local drafts, list = {}, {}
    for id, raw in pairs(Table(root.drafts) or {}) do
        local draft = MS.Ink.Draft.Sanitize(raw)
        if draft and draft.id == id then list[#list + 1] = draft end
    end
    table.sort(list, function(a, b)
        if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
        return a.id < b.id
    end)
    for index = 1, math.min(#list, self.draftLimit) do drafts[list[index].id] = list[index] end
    root = { schemaVersion = self.schema, tales = tales, characters = characters, drafts = drafts }
    self.root = root
    return root
end

function Store:SanitizeBucket(raw, tales)
    local bucket = { lastSeenAt = Num(raw.lastSeenAt) and raw.lastSeenAt or nil, progress = {} }
    for id, progress in pairs(Table(raw.progress) or {}) do
        local entry = tales[id]
        local clean = entry and MS.Ink.Progress.Sanitize(progress, entry.tale)
        if clean then bucket.progress[id] = clean end
    end
    return bucket
end

function Store:Character(key, now)
    if self.readOnly or not self.root or not MS.JourneyCharacterIdentity:IsKey(key) then return nil end
    local characters = self.root.characters
    if not characters[key] then
        local count = 0
        for _ in pairs(characters) do count = count + 1 end
        if count >= self.characterLimit then return nil end
        characters[key] = { progress = {} }
    end
    if type(now) == "number" then characters[key].lastSeenAt = now end
    return characters[key]
end

function Store:Count()
    local count = 0
    for _ in pairs(self.root and self.root.tales or {}) do count = count + 1 end
    return count
end

-- Keeps a tale: a new one, or a newer version of one already kept (same id, same author).
-- Returns the entry and NEW | UPDATED, or nil and SAME | OLDER | CONFLICT | FULL | LOCKED.
function Store:Keep(tale, origin, now, from)
    if self.readOnly or not self.root then return nil, "LOCKED" end
    local tales, current = self.root.tales, self.root.tales[tale.id]
    if current then
        if current.tale.author ~= tale.author then return nil, "CONFLICT" end
        if tale.version == current.tale.version then return nil, "SAME" end
        if tale.version < current.tale.version then return nil, "OLDER" end
        current.tale, current.keptAt = tale, now or current.keptAt
        if origin == "WRITTEN" then current.origin = "WRITTEN" end
        current.from = From(from) or current.from
        -- Every character keeps the pages it found that still exist in the new version.
        for _, bucket in pairs(self.root.characters) do
            if bucket.progress[tale.id] then bucket.progress[tale.id] = MS.Ink.Progress.Sanitize(bucket.progress[tale.id], tale) end
        end
        return current, "UPDATED"
    end
    if self:Count() >= self.taleLimit then return nil, "FULL" end
    tales[tale.id] = { tale = tale, origin = origin == "WRITTEN" and "WRITTEN" or "KEPT", keptAt = now or 0, from = From(from) }
    return tales[tale.id], "NEW"
end

-- Removes a tale and every character's progress in it.
function Store:Forget(id)
    if self.readOnly or not self.root or not self.root.tales[id] then return false end
    self.root.tales[id] = nil
    for _, bucket in pairs(self.root.characters) do bucket.progress[id] = nil end
    return true
end

-- Drafts ---------------------------------------------------------------------------------------
function Store:DraftCount()
    local count = 0
    for _ in pairs(self.root and self.root.drafts or {}) do count = count + 1 end
    return count
end

-- Keeps a new draft. Returns it, or nil and FULL | LOCKED.
function Store:AddDraft(draft)
    if self.readOnly or not self.root then return nil, "LOCKED" end
    if not self.root.drafts[draft.id] and self:DraftCount() >= self.draftLimit then return nil, "FULL" end
    self.root.drafts[draft.id] = draft
    return draft
end

function Store:RemoveDraft(id)
    if self.readOnly or not self.root or not self.root.drafts[id] then return false end
    self.root.drafts[id] = nil
    return true
end
