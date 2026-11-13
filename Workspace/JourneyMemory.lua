local MS = _G.MS
-- Persistent facts only. JourneySession owns all event registration and clocks.
MS.JourneyMemory = { schema = 1, sessionLimit = 30, milestoneLimit = 250 }
local Memory = MS.JourneyMemory

local function Number(value, minimum, maximum)
    return type(value) == "number" and value == value and value >= (minimum or 0)
        and value <= (maximum or 9007199254740991) and value == math.floor(value)
end
local function ID(value) return Number(value, 1, 2147483647) end
local function Stamp(value) return Number(value, 1, 4102444800) end
local function Text(value)
    return type(value) == "string" and #value > 0 and #value <= 256 and value or nil
end
local function CharacterKey(key)
    return MS.JourneyCharacterIdentity:IsKey(key) and key or nil
end
local function Table(value) return type(value) == "table" and value or {} end
local function VisitMapType(mapID)
    local info = MS.JourneyMapData and MS.JourneyMapData:Info(mapID)
    local mapType = info and info.mapType
    local types = _G.Enum and Enum.UIMapType or {}
    local zone, dungeon = types.Zone or 3, types.Dungeon or 4
    return mapType == zone or mapType == dungeon, mapType, info ~= nil
end
local function CopyNumbers(source, keys)
    local result = {}
    for _, key in ipairs(keys) do if Number(source[key]) then result[key] = source[key] end end
    return result
end
local SUMMARY_KEYS = { "startedAt", "endedAt", "lastObservedAt", "duration", "startLevel", "endLevel",
    "xpGained", "questTurnIns", "deaths", "zonesVisitedCount", "sourceStartedAt",
    "baseXP", "baseTurnIns", "baseDeaths", "baseZones" }
local function Summary(raw, open)
    if type(raw) ~= "table" or not Stamp(raw.startedAt) then return nil end
    local result = CopyNumbers(raw, SUMMARY_KEYS)
    for _, key in ipairs({ "startLevel", "endLevel" }) do
        if not Number(result[key], 1, 1000) then result[key] = nil end
    end
    if not Stamp(result.lastObservedAt) or result.lastObservedAt < result.startedAt then result.lastObservedAt = nil end
    if not Stamp(result.endedAt) or result.endedAt < result.startedAt then result.endedAt = nil end
    result.interrupted = raw.interrupted == true or nil
    if result.interrupted then result.endedAt = nil end
    local last = result.endedAt or result.lastObservedAt
    result.duration = last and last - result.startedAt or nil
    if open then
        result.zoneIDs = {}
        result.zonesVisitedCount = 0
        for id, present in pairs(Table(raw.zoneIDs)) do
            local visitable, _, known = VisitMapType(id)
            if ID(id) and present == true and (not known or visitable) then
                result.zoneIDs[id] = true; result.zonesVisitedCount = result.zonesVisitedCount + 1
            end
        end
    end
    if not open then
        for _, key in ipairs({ "sourceStartedAt", "baseXP", "baseTurnIns", "baseDeaths", "baseZones" }) do result[key] = nil end
    end
    return result
end
local function TrimMilestones(data)
    while #data.milestones > Memory.milestoneLimit do
        local remove = 1
        for index, milestone in ipairs(data.milestones) do
            -- Preserve the current level record in the timeline; all facts remain in their tables.
            if milestone.type ~= "LEVEL_REACHED" or milestone.level ~= data.character.maxLevel then remove = index; break end
        end
        table.remove(data.milestones, remove)
    end
end

function Memory:Sanitize(raw)
    raw = Table(raw)
    local character = Table(raw.character)
    local data = { character = {}, zones = {}, quests = {}, sessions = {}, milestones = {} }
    for _, key in ipairs({ "firstSeenAt", "maxLevel", "lastLevel", "lastMapID" }) do
        local valid = key == "firstSeenAt" and Stamp(character[key])
            or key == "lastMapID" and ID(character[key])
            or (key == "maxLevel" or key == "lastLevel") and Number(character[key], 1, 1000)
        if valid then data.character[key] = character[key] end
    end
    if data.character.lastLevel then data.character.maxLevel = math.max(data.character.maxLevel or 0, data.character.lastLevel) end
    local cleaned = 0
    for id, zone in pairs(Table(raw.zones)) do
        local visitable, _, known = VisitMapType(id)
        if ID(id) and type(zone) == "table" and Stamp(zone.firstVisitedAt) and Stamp(zone.lastVisitedAt)
            and zone.lastVisitedAt >= zone.firstVisitedAt and Number(zone.visits, 1) and (not known or visitable) then
            data.zones[id] = { firstVisitedAt = zone.firstVisitedAt, lastVisitedAt = zone.lastVisitedAt,
                visits = zone.visits, firstVisitedLevel = Number(zone.firstVisitedLevel, 1, 1000) and zone.firstVisitedLevel or nil,
                nameSnapshot = Text(zone.nameSnapshot) }
        elseif known and not visitable then
            cleaned = cleaned + 1
        end
    end
    if not data.zones[data.character.lastMapID] then data.character.lastMapID = nil end
    for id, quest in pairs(Table(raw.quests)) do
        if ID(id) and type(quest) == "table" and Stamp(quest.firstTurnedInAt) and Stamp(quest.lastTurnedInAt)
            and quest.lastTurnedInAt >= quest.firstTurnedInAt and Number(quest.turnInCount, 1) then
            data.quests[id] = { firstTurnedInAt = quest.firstTurnedInAt, lastTurnedInAt = quest.lastTurnedInAt,
                turnInCount = quest.turnInCount, titleSnapshot = Text(quest.titleSnapshot), mapID = ID(quest.mapID) and quest.mapID or nil }
        end
    end
    for _, rawSession in ipairs(Table(raw.sessions)) do
        local session = Summary(rawSession)
        if session then data.sessions[#data.sessions + 1] = session end
    end
    while #data.sessions > self.sessionLimit do table.remove(data.sessions, 1) end
    local seen = {}
    for _, milestone in ipairs(Table(raw.milestones)) do
        if type(milestone) == "table" and Stamp(milestone.timestamp) then
            local kind, value = milestone.type
            if kind == "LEVEL_REACHED" and Number(milestone.level, 1, data.character.maxLevel or 0) then value = milestone.level
            elseif kind == "FIRST_ZONE_VISIT" and ID(milestone.mapID) and data.zones[milestone.mapID] then value = milestone.mapID
            elseif kind == "FIRST_QUEST_TURNIN" and ID(milestone.questID) and data.quests[milestone.questID] then value = milestone.questID end
            if value and not seen[kind .. value] then
                seen[kind .. value] = true
                local entry = { timestamp = milestone.timestamp, type = kind }
                entry[kind == "LEVEL_REACHED" and "level" or kind == "FIRST_ZONE_VISIT" and "mapID" or "questID"] = value
                data.milestones[#data.milestones + 1] = entry
            elseif kind == "FIRST_ZONE_VISIT" and ID(milestone.mapID) and not data.zones[milestone.mapID] then
                cleaned = cleaned + 1
            end
        end
    end
    TrimMilestones(data)
    data.openSession = Summary(raw.openSession, true)
    return data, cleaned
end

function Memory:Initialize(db)
    local memory = Table(db.journey.memory)
    self.identity = MS.JourneyCharacterIdentity:Resolve()
    self.identityMigration = MS.JourneyCharacterIdentity:MigrateCharacters(memory.characters, self.identity)
    MS.JourneyCharacterIdentity:WarnConflict("MEMORY", self.identityMigration)
    local characters = {}
    self.invalidEntriesCleaned = 0
    for key, data in pairs(Table(memory.characters)) do
        if CharacterKey(key) then
            -- Conflict records stay byte-for-byte intact and remain unbound.
            local preserve = self.identityMigration.status == "CONFLICT" and
                (key == self.identity.key or key == self.identity.legacyKey or key == self.identity.fallbackKey)
            local clean, count = data, 0
            if not preserve then clean, count = self:Sanitize(data) end
            characters[key] = clean
            self.invalidEntriesCleaned = self.invalidEntriesCleaned + count
        end
    end
    db.journey.memory = { schema = self.schema, characters = characters }
    self.root = db.journey.memory
    if self.identityMigration.status == "CONFLICT" then self:Bind(nil) end
    if not Number(db.schemaVersion, 4) then db.schemaVersion = 4 end
end

function Memory:Bind(key)
    self.data, self.key = nil, CharacterKey(key)
    self.lastVisitMapID, self.lastVisitMapType = nil, nil
    self.zoneCount, self.questCount, self.totalQuestTurnIns = 0, 0, 0
    if not self.root or not self.key then return end
    self.root.characters[key] = self.root.characters[key] or self:Sanitize({})
    self.data = self.root.characters[key]
    self.currentMapID = self.data.character.lastMapID
    self.zoneCount, self.questCount, self.totalQuestTurnIns = 0, 0, 0
    for _ in pairs(self.data.zones) do self.zoneCount = self.zoneCount + 1 end
    for _, quest in pairs(self.data.quests) do
        self.questCount = self.questCount + 1; self.totalQuestTurnIns = self.totalQuestTurnIns + quest.turnInCount
    end
end

function Memory:Notify()
    if MS.JourneyProgressionView then MS.JourneyProgressionView:Invalidate() end
    if MS.JourneyContextPanel and MS.JourneyContextPanel.RefreshMemory then MS.JourneyContextPanel:RefreshMemory() end
end
function Memory:AddMilestone(kind, stamp, key, value)
    local entry = { timestamp = stamp, type = kind }; entry[key] = value
    self.data.milestones[#self.data.milestones + 1] = entry
    TrimMilestones(self.data)
end
function Memory:ObserveLevel(level, stamp)
    if not self.data or not Number(level, 1, 1000) or not Stamp(stamp) then return end
    local character = self.data.character
    character.firstSeenAt = character.firstSeenAt or stamp
    character.lastLevel = level
    if level > (character.maxLevel or 0) then
        character.maxLevel = level
        self:AddMilestone("LEVEL_REACHED", stamp, "level", level)
        self:Notify()
    end
end
function Memory:ObserveZone(mapID, name, level, stamp)
    if not self.data or not ID(mapID) or not Stamp(stamp) then return end
    local visitable, mapType = VisitMapType(mapID)
    if not visitable then
        self.filteredNonVisitMaps = (self.filteredNonVisitMaps or 0) + 1
        return
    end
    self.lastVisitMapID, self.lastVisitMapType = mapID, mapType
    local open = self.data.openSession
    if open and not open.zoneIDs[mapID] then
        open.zoneIDs[mapID] = true; open.zonesVisitedCount = open.zonesVisitedCount + 1
    end
    if self.currentMapID == mapID then return end
    self.currentMapID, self.data.character.lastMapID = mapID, mapID
    if name == tostring(mapID) then name = nil end
    local zone = self.data.zones[mapID]
    if zone then
        zone.lastVisitedAt = math.max(zone.lastVisitedAt, stamp); zone.visits = zone.visits + 1
        zone.nameSnapshot = Text(name) or zone.nameSnapshot
    else
        self.data.zones[mapID] = { firstVisitedAt = stamp, lastVisitedAt = stamp, visits = 1,
            firstVisitedLevel = Number(level, 1, 1000) and level or nil, nameSnapshot = Text(name) }
        self.zoneCount = self.zoneCount + 1
        self:AddMilestone("FIRST_ZONE_VISIT", stamp, "mapID", mapID)
    end
    self:Notify()
end
function Memory:ObservePlayerZone(level, stamp)
    if not self.data or not MS.JourneyMapData then return end
    local resolved = MS.JourneyMapData:ResolvePlayerJourneyMap()
    if resolved then self:ObserveZone(resolved.canonicalJourneyMapID, resolved.canonicalJourneyMapName, level, stamp) end
end
function Memory:TurnIn(questID, title, mapID, stamp)
    if not self.data or not ID(questID) or not Stamp(stamp) then return end
    local quest = self.data.quests[questID]
    if quest then
        quest.turnInCount = quest.turnInCount + 1
        quest.lastTurnedInAt = math.max(quest.lastTurnedInAt, stamp)
        quest.titleSnapshot = Text(title) or quest.titleSnapshot
        quest.mapID = ID(mapID) and mapID or quest.mapID
    else
        self.data.quests[questID] = { firstTurnedInAt = stamp, lastTurnedInAt = stamp, turnInCount = 1,
            titleSnapshot = Text(title), mapID = ID(mapID) and mapID or nil }
        self.questCount = self.questCount + 1
        self:AddMilestone("FIRST_QUEST_TURNIN", stamp, "questID", questID)
    end
    self.totalQuestTurnIns = self.totalQuestTurnIns + 1
    self:Notify()
end

function Memory:Checkpoint(session)
    local open = self.data and self.data.openSession
    if not open or not session or session.character ~= self.key or session.startedAt ~= open.sourceStartedAt then return end
    local stamp = session.lastSeenAt
    if Stamp(stamp) and stamp >= open.startedAt then open.lastObservedAt = stamp; open.duration = stamp - open.startedAt end
    if Number(session.level, 1, 1000) then open.endLevel = session.level end
    for _, spec in ipairs({ {"xpGained","baseXP","xpGained"}, {"questTurnIns","baseTurnIns","questTurnIns"},
        {"deaths","baseDeaths","deaths"} }) do
        local value, base = session[spec[1]], open[spec[2]]
        if Number(value) and Number(base) and value >= base then open[spec[3]] = value - base end
    end
end
function Memory:CloseSession(session, endedAt, interrupted)
    if not self.data or not self.data.openSession then return end
    self:Checkpoint(session)
    local open = self.data.openSession
    open.interrupted = interrupted == true or nil
    open.endedAt = not interrupted and Stamp(endedAt) and endedAt >= open.startedAt and endedAt or nil
    self.data.sessions[#self.data.sessions + 1] = Summary(open)
    self.data.openSession = nil
    while #self.data.sessions > self.sessionLimit do table.remove(self.data.sessions, 1) end
    self:Notify()
end
function Memory:PrepareStartup(previous, key, now)
    local checkpoint = previous
    if type(previous) == "table" and Stamp(now) and type(previous.lastSeenAt) == "number"
        and previous.lastSeenAt > now then checkpoint = nil end
    -- Close the previous character's open record as well when switching characters.
    if type(previous) == "table" and CharacterKey(previous.character) and previous.character ~= key then
        self:Bind(previous.character); self:CloseSession(checkpoint, nil, true)
    end
    self:Bind(key)
    self:CloseSession(checkpoint, nil, true)
end
function Memory:BeginSession(session, stamp)
    if not self.data or not Stamp(stamp) or session.character ~= self.key then return end
    local existing = self.data.openSession
    if existing and existing.sourceStartedAt == session.startedAt then
        self:Checkpoint(session)
        return
    end
    if existing then self:CloseSession(nil, nil, true) end
    self.data.character.firstSeenAt = self.data.character.firstSeenAt or stamp
    local open = { startedAt = stamp, lastObservedAt = stamp, duration = 0,
        sourceStartedAt = session.startedAt, startLevel = session.level, endLevel = session.level,
        baseXP = session.xpGained, baseTurnIns = session.questTurnIns, baseDeaths = session.deaths }
    self.data.openSession = Summary(open, true)
    self:ObserveLevel(session.level, stamp)
    self:ObservePlayerZone(session.level, stamp)
    self:Checkpoint(session)
    self:Notify()
end
function Memory:OnSessionEvent(event, detail, metadata, stamp)
    if event == "LEVEL_UP" then self:ObserveLevel(tonumber(detail), stamp)
    elseif event == "QUEST_TURNED_IN" then
        local resolved = MS.JourneyMapData and MS.JourneyMapData:ResolvePlayerJourneyMap()
        self:TurnIn(metadata.questID, detail, resolved and resolved.canonicalJourneyMapID, stamp)
    end
end
function Memory:GetZone(mapID) return self.data and self.data.zones[mapID] end
function Memory:GetQuest(questID) return self.data and self.data.quests[questID] end
-- Read-only: unique remembered quests turned in within a zone (a recorded sub-map counts for
-- its containing zone). nil when no character memory is bound, so callers never invent zero.
function Memory:CompletedQuestCount(zoneID)
    if not self.data or not ID(zoneID) then return nil end
    local zones, count = {}, 0
    for _, quest in pairs(self.data.quests) do
        local mapID = quest.mapID
        if mapID and zones[mapID] == nil then
            zones[mapID] = mapID == zoneID or (MS.JourneyMapData and MS.JourneyMapData:LocalZone(mapID) == zoneID) or false
        end
        if mapID and zones[mapID] then count = count + 1 end
    end
    return count
end
function Memory:GetStatus()
    local data = self.data
    local last = data and data.milestones[#data.milestones]
    return { schema = self.schema, identity = self.identity, identityMigration = self.identityMigration,
        maxLevel = data and data.character.maxLevel, zoneCount = self.zoneCount or 0,
        questCount = self.questCount or 0, totalQuestTurnIns = self.totalQuestTurnIns or 0,
        sessionCount = data and #data.sessions or 0, milestoneCount = data and #data.milestones or 0,
        openSession = data and data.openSession ~= nil or false, lastMilestoneType = last and last.type,
        lastVisitMapID = self.lastVisitMapID, lastVisitMapType = self.lastVisitMapType,
        filteredNonVisitMaps = self.filteredNonVisitMaps or 0, invalidEntriesCleaned = self.invalidEntriesCleaned or 0,
        chainCompletion = "UNSUPPORTED_BY_DESIGN" }
end
