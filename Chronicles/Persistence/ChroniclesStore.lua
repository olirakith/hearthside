local MS = _G.MS

MS.ChroniclesStore = { CURRENT_SCHEMA_VERSION = 1, status = "UNINITIALIZED" }
local Store = MS.ChroniclesStore
local STATE_KEYS = { "regions", "chronicles", "rumors", "collections", "seals", "notifications" }

-- Add one explicit function per version transition when a new schema ships.
-- Each function can then be exercised independently by the Store tests.
local MIGRATIONS = {}

local function ValidCharacterKey(key)
    return MS.JourneyCharacterIdentity:IsKey(key)
end

local function ValidCharacterState(state)
    if type(state) ~= "table" then return false end
    for _, field in ipairs(STATE_KEYS) do
        -- Presentation data is disposable. Preserve malformed notifications for
        -- diagnosis, while allowing the progression fields to remain available.
        -- NotificationQueue validates its own field and fails closed.
        if field ~= "notifications" and state[field] ~= nil
            and type(state[field]) ~= "table" then return false end
    end
    return true
end

local function ValidCharacters(characters)
    if type(characters) ~= "table" then return false end
    for key, state in pairs(characters) do
        if not ValidCharacterKey(key) or not ValidCharacterState(state) then return false end
    end
    return true
end

function Store:ResolveCharacterKey()
    return MS.JourneyCharacterIdentity:Resolve().key
end

function Store:Initialize(db)
    self.identity = MS.JourneyCharacterIdentity:Resolve()
    self.identityMigration = { status = "UNAVAILABLE", canonicalKey = self.identity.key }
    if db == nil then db = _G.MultiScreenForeverChroniclesDB end
    if db == nil then
        db = { schemaVersion = self.CURRENT_SCHEMA_VERSION, characters = {} }
        _G.MultiScreenForeverChroniclesDB = db
        self.db, self.status = db, "FIRST_RUN"
        self.identityMigration = MS.JourneyCharacterIdentity:MigrateCharacters(db.characters, self.identity)
        return self.status
    end
    if type(db) ~= "table" then
        self.db, self.status = nil, "INVALID"
        return self.status
    end
    local version = db.schemaVersion
    if type(version) ~= "number" or version ~= math.floor(version) or version < 1 then
        self.db, self.status = nil, "INVALID"
        return self.status
    end
    if version > self.CURRENT_SCHEMA_VERSION then
        self.db, self.status = nil, "NEWER_SCHEMA"
        return self.status
    end
    if not ValidCharacters(db.characters) then
        self.db, self.status = nil, "INVALID"
        return self.status
    end
    while version < self.CURRENT_SCHEMA_VERSION do
        local migrate = MIGRATIONS[version]
        if type(migrate) ~= "function" or not migrate(db) then
            self.db, self.status = nil, "INVALID"
            return self.status
        end
        version = version + 1
        db.schemaVersion = version
    end
    self.db, self.status = db, self.status == "FIRST_RUN" and self.db == db and "FIRST_RUN" or "READY"
    self.identityMigration = MS.JourneyCharacterIdentity:MigrateCharacters(db.characters, self.identity)
    MS.JourneyCharacterIdentity:WarnConflict("CHRONICLES", self.identityMigration)
    return self.status
end

function Store:GetStatus()
    return self.status
end

function Store:GetSchemaVersion()
    return self.db and self.db.schemaVersion or nil
end

function Store:GetCharacterState(characterKey)
    if not self.db or not ValidCharacterKey(characterKey) then return nil end
    return self.db.characters[characterKey]
end

function Store:EnsureCharacterState(characterKey)
    if not self.db or not ValidCharacterKey(characterKey) then return nil end
    local characters = self.db.characters
    local state = characters[characterKey]
    if state == nil then
        state = {}
        characters[characterKey] = state
    elseif not ValidCharacterState(state) then
        self.db, self.status = nil, "INVALID"
        return nil
    end
    for _, field in ipairs(STATE_KEYS) do
        if state[field] == nil then state[field] = {} end
    end
    return state
end

-- Commit a complete discovery batch only after all inputs and the target state
-- have been checked. Existing discoveries keep their original timestamp.
function Store:DiscoverChronicles(characterKey, ids, discoveredAt)
    local state = self:GetCharacterState(characterKey)
    if not state or type(state.chronicles) ~= "table" or type(ids) ~= "table"
        or type(discoveredAt) ~= "number" or discoveredAt ~= math.floor(discoveredAt)
        or discoveredAt <= 0 or discoveredAt == math.huge then return nil end
    local seen, pending = {}, {}
    for index, id in ipairs(ids) do
        if type(id) ~= "string" or id == "" or seen[id] then return nil end
        seen[id] = true
        local existing = state.chronicles[id]
        if existing ~= nil and type(existing) ~= "table" then return nil end
        if existing == nil then pending[#pending + 1] = id end
    end
    for key in pairs(ids) do
        if type(key) ~= "number" or key < 1 or key > #ids or key ~= math.floor(key) then return nil end
    end
    if #pending > 0 then
        local nextChronicles = {}
        for id, record in pairs(state.chronicles) do nextChronicles[id] = record end
        for _, id in ipairs(pending) do nextChronicles[id] = { discoveredAt = discoveredAt } end
        state.chronicles = nextChronicles
    end
    return pending
end

-- Reading is a domain transition. Acknowledging presentation events never
-- calls this operation, and the original discovery date is retained.
local function ValidTime(value)
    return value == nil or type(value) == "number" and value > 0
        and value < math.huge and value == math.floor(value)
end

function Store:MarkChronicleRead(characterKey, chronicleID, now)
    local state = self:GetCharacterState(characterKey)
    if not state or type(state.chronicles) ~= "table"
        or type(chronicleID) ~= "string" or chronicleID == ""
        or type(now) ~= "number" or now <= 0 or now >= math.huge
        or now ~= math.floor(now) then return nil end
    local record = state.chronicles[chronicleID]
    if type(record) ~= "table" or not ValidTime(record.discoveredAt)
        or record.discoveredAt == nil or not ValidTime(record.readAt) then return nil end
    if record.readAt ~= nil then return false end
    local nextRecord = {}
    for key, value in pairs(record) do nextRecord[key] = value end
    nextRecord.readAt = now
    local nextChronicles = {}
    for id, value in pairs(state.chronicles) do nextChronicles[id] = value end
    nextChronicles[chronicleID] = nextRecord
    state.chronicles = nextChronicles
    return true
end

function Store:CommitCollectionSeals(characterKey, completed, unlocked, now)
    local state = self:GetCharacterState(characterKey)
    if not state or type(state.collections) ~= "table" or type(state.seals) ~= "table"
        or not ValidTime(now) or now == nil then return false end
    local function Prepare(records, ids, field)
        if type(ids) ~= "table" then return nil end
        local nextRecords, seen = {}, {}
        for id, record in pairs(records) do
            if type(record) ~= "table" or not ValidTime(record[field])
                or record[field] == nil then return nil end
            nextRecords[id] = record
        end
        for _, id in ipairs(ids) do
            if type(id) ~= "string" or id == "" or seen[id] then return nil end
            seen[id] = true
            if nextRecords[id] == nil then nextRecords[id] = { [field] = now } end
        end
        for index in pairs(ids) do
            if type(index) ~= "number" or index < 1 or index > #ids
                or index ~= math.floor(index) then return nil end
        end
        return nextRecords
    end
    local collections = Prepare(state.collections, completed, "completedAt")
    local seals = Prepare(state.seals, unlocked, "unlockedAt")
    if not collections or not seals then return false end
    state.collections, state.seals = collections, seals
    return true
end

local function ValidRegionRecord(record)
    return type(record) == "table"
        and (record.state == "RUMORED" or record.state == "VISITED" or record.state == "EXPLORED")
        and ValidTime(record.firstRumorAt) and ValidTime(record.firstVisitedAt)
        and ValidTime(record.exploredAt)
end

local function ValidRegionUpdates(updates)
    if type(updates) ~= "table" then return false end
    for id, record in pairs(updates) do
        if type(id) ~= "string" or id == "" or not ValidRegionRecord(record) then return false end
    end
    return true
end

function Store:CommitRegionStates(characterKey, updates)
    local state = self:GetCharacterState(characterKey)
    if not state or type(state.regions) ~= "table" or not ValidRegionUpdates(updates) then return false end
    local nextRegions = {}
    for id, record in pairs(state.regions) do nextRegions[id] = record end
    for id, record in pairs(updates) do nextRegions[id] = record end
    state.regions = nextRegions
    return true
end

function Store:DiscoverRumors(characterKey, ids, regionUpdates, discoveredAt)
    local state = self:GetCharacterState(characterKey)
    if not state or type(state.rumors) ~= "table" or type(state.regions) ~= "table"
        or type(ids) ~= "table" or not ValidRegionUpdates(regionUpdates)
        or not ValidTime(discoveredAt) or discoveredAt == nil then return nil end
    local pending, seen = {}, {}
    for _, id in ipairs(ids) do
        if type(id) ~= "string" or id == "" or seen[id] then return nil end
        seen[id] = true
        local existing = state.rumors[id]
        if existing ~= nil and type(existing) ~= "table" then return nil end
        if existing == nil then pending[#pending + 1] = id end
    end
    for key in pairs(ids) do
        if type(key) ~= "number" or key < 1 or key > #ids or key ~= math.floor(key) then return nil end
    end
    if #pending == 0 then return pending end
    local nextRumors, nextRegions = {}, {}
    for id, record in pairs(state.rumors) do nextRumors[id] = record end
    for id, record in pairs(state.regions) do nextRegions[id] = record end
    for _, id in ipairs(pending) do nextRumors[id] = { discoveredAt = discoveredAt } end
    for id, record in pairs(regionUpdates) do nextRegions[id] = record end
    state.rumors, state.regions = nextRumors, nextRegions
    return pending
end
