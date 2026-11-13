local MS = _G.MS

MS.JourneySession = { active = false }
local Session = MS.JourneySession
local RESUME_SECONDS = 300
local MAX_EVENTS = 150

local function Now()
    return type(time) == "function" and time() or 0
end

local function Read(functionName, ...)
    local fn = _G[functionName]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

local function CharacterKey()
    return MS.JourneyCharacterIdentity:Resolve().key
end

local function Zone()
    return Read("GetZoneText") or Read("GetSubZoneText") or ""
end

local EVENT_KEYS = {
    SESSION_STARTED = "JOURNEY_EVENT_SESSION_STARTED", ZONE_ENTERED = "JOURNEY_EVENT_ZONE_ENTERED",
    LEVEL_UP = "JOURNEY_EVENT_LEVEL_UP", QUEST_ACCEPTED = "JOURNEY_EVENT_QUEST_ACCEPTED",
    QUEST_COMPLETED = "JOURNEY_EVENT_QUEST_COMPLETED", QUEST_TURNED_IN = "JOURNEY_EVENT_QUEST_TURNED_IN",
    DEATH = "JOURNEY_EVENT_DEATH",
}
local OLD_TYPES = { SESSION_START = "SESSION_STARTED", ZONE_CHANGED = "ZONE_ENTERED", PLAYER_DEAD = "DEATH" }

local function PlayerMap()
    if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and type(id) == "number" and id > 0 then return id end
    end
end

local function EventTitle(kind, detail)
    local format = MS.L[EVENT_KEYS[kind]]
    if kind == "SESSION_STARTED" or kind == "DEATH" then return format end
    if not detail or detail == "" then detail = MS.L.JOURNEY_QUEST_DETAILS end
    return string.format(format, detail)
end

local function Trim(events)
    while #events > MAX_EVENTS do
        local index = events[1].type == "SESSION_STARTED" and 2 or 1
        table.remove(events, index)
    end
end

function Session:AddEvent(kind, detail, metadata)
    local data = self.data
    kind = OLD_TYPES[kind] or kind
    if not data or not EVENT_KEYS[kind] then return end
    metadata = metadata or {}
    data.events[#data.events + 1] = { timestamp = Now(), type = kind, title = EventTitle(kind, detail),
        detail = detail, mapID = metadata.mapID, questID = metadata.questID }
    Trim(data.events)
    if MS.JourneyMemory then MS.JourneyMemory:OnSessionEvent(kind, detail, metadata, Now()) end
    if MS.SessionFeed then MS.SessionFeed:Refresh() end
end

function Session:MigrateEvents()
    local events = {}
    for _, raw in ipairs(self.data.events) do
        if type(raw) == "table" then
            local kind = OLD_TYPES[raw.kind] or raw.type or raw.kind
            local stamp = raw.timestamp or raw.at
            if EVENT_KEYS[kind] and type(stamp) == "number" and stamp == stamp and stamp >= 0 and stamp < math.huge then
                local detail = type(raw.detail) == "string" and raw.detail or nil
                events[#events + 1] = { timestamp = stamp, type = kind, title = EventTitle(kind, detail),
                    detail = detail, mapID = raw.mapID, questID = raw.questID }
            end
        end
    end
    Trim(events); self.data.events = events
    for _, key in ipairs({ "questTurnIns", "zonesVisited" }) do
        local value = self.data[key]
        if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then self.data[key] = nil end
    end
    -- Old, truncated sessions cannot supply exact historical totals.
    if self.data.metricsVersion ~= 2 then
        self.data.questTurnIns, self.data.zonesVisited, self.data.visitedMaps = nil, nil, nil
    elseif type(self.data.visitedMaps) ~= "table" then
        self.data.zonesVisited, self.data.visitedMaps = nil, nil
    end
end

function Session:VisitZone()
    local id = PlayerMap()
    if id and self.data.zonesVisited and self.data.visitedMaps and not self.data.visitedMaps[id] then
        self.data.visitedMaps[id] = true
        self.data.zonesVisited = (self.data.zonesVisited or 0) + 1
    end
    return id
end

function Session:QuestTitle(id)
    local quest = MS.JourneyQuestData and MS.JourneyQuestData.latestByID and MS.JourneyQuestData.latestByID[id]
    if quest then return quest.title end
    if C_QuestLog and type(C_QuestLog.GetTitleForQuestID) == "function" then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok and type(title) == "string" then return title end
    end
end

function Session:ObserveQuests(quests)
    if not self.active then return end
    local previous, current = self.observedQuests or {}, {}
    for _, quest in ipairs(quests) do
        local progress = quest.progress or {}
        local completed = quest.state == "READY_TO_TURN_IN" or ((progress.totalObjectives or 0) > 0
            and progress.completedObjectives == progress.totalObjectives)
        if quest.questID then
            current[quest.questID] = completed
            if previous[quest.questID] == false and completed then
                self:AddEvent("QUEST_COMPLETED", quest.title, { questID = quest.questID, mapID = quest.mapID })
            end
        end
    end
    self.observedQuests = current
end

function Session:New()
    local now = Now()
    if not CharacterKey() then self.data, self.active = nil, false; return end
    if MS.JourneyMemory then MS.JourneyMemory:CloseSession(self.data, now, false) end
    local level = Read("UnitLevel", "player") or 0
    local xp = Read("UnitXP", "player") or 0
    self.data = { active = true, character = CharacterKey(), startedAt = now,
        lastSeenAt = now, startLevel = level, level = level,
        startXP = xp, lastXP = xp, lastXPMax = Read("UnitXPMax", "player") or 0,
        xpGained = 0, deaths = 0, zone = Zone(), events = {}, metricsVersion = 2,
        questTurnIns = 0, zonesVisited = 0, visitedMaps = {} }
    MS.Database:Get().journey.session = self.data
    self.active, self.observedQuests = true, nil
    if MS.JourneyInventoryData then MS.JourneyInventoryData:ResetSession() end
    if MS.JourneyMemory then MS.JourneyMemory:BeginSession(self.data, now) end
    local mapID = self:VisitZone()
    self:AddEvent("SESSION_STARTED", self.data.zone, { mapID = mapID })
    self:RefreshHeader()
end

function Session:Initialize()
    local journey = MS.Database:Get().journey
    local saved = journey.session
    self.identity = MS.JourneyCharacterIdentity:Resolve()
    local key = self.identity.key
    local memory = MS.JourneyMemory
    self.identityMigration = memory and memory.identityMigration
    if memory and memory.identityMigration and memory.identityMigration.status == "CONFLICT" then
        self.data, self.active = nil, false
        memory:Bind(nil)
        self.identityMigration = memory.identityMigration
        return nil, "CHARACTER_IDENTITY_CONFLICT"
    end
    if type(saved) == "table" and key and saved.character ~= key and
        (saved.character == self.identity.legacyKey or saved.character == self.identity.fallbackKey) then
        saved.character = key
    end
    if self.active and self.data == saved and saved.character == key and
        (not memory or memory.data == (memory.root and memory.root.characters[key])) then
        if memory then memory:Bind(key) end
        self:RefreshHeader()
        return true
    end
    local now = Now()
    if memory then memory:PrepareStartup(saved, key, now) end
    if type(saved) == "table" and saved.active == true
        and saved.character == CharacterKey()
        and type(saved.startedAt) == "number"
        and type(saved.lastSeenAt) == "number"
        and now >= saved.lastSeenAt and now - saved.lastSeenAt <= RESUME_SECONDS
        and type(saved.level) == "number" and type(saved.lastXP) == "number"
        and type(saved.lastXPMax) == "number" and type(saved.deaths) == "number"
        and type(saved.events) == "table" and type(saved.xpGained) == "number" then
        self.data, self.active = saved, true
        self:MigrateEvents()
        self.observedQuests = nil
        self:UpdateXP()
        if MS.JourneyMemory then MS.JourneyMemory:BeginSession(self.data, now) end
    else
        self:New()
    end
    if not self.eventFrame then
        local frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", function(_, event, ...)
            Session:OnEvent(event, ...)
        end)
        for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_LEVEL_UP",
            "PLAYER_DEAD", "PLAYER_XP_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN" }) do
            local ok = pcall(frame.RegisterEvent, frame, event)
            if event == "QUEST_TURNED_IN" then self.questTurnedInSupported = ok end
        end
        self.eventFrame = frame
    end
    self:RefreshHeader()
end

function Session:UpdateXP()
    local data = self.data
    if not data then return end
    local level = Read("UnitLevel", "player") or data.level
    local xp = Read("UnitXP", "player") or data.lastXP
    local maximum = Read("UnitXPMax", "player") or data.lastXPMax
    local delta = 0
    if level > data.level then
        delta = math.max(0, data.lastXPMax - data.lastXP) + math.max(0, xp)
    elseif level == data.level then
        delta = math.max(0, xp - data.lastXP)
    end
    data.xpGained = data.xpGained + delta
    data.level, data.lastXP, data.lastXPMax = level, xp, maximum
    data.lastSeenAt = Now()
    self:RefreshHeader()
end

function Session:OnEvent(event, ...)
    if not self.active then return end
    if event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
        local zone = Zone()
        if zone ~= "" and zone ~= self.data.zone then
            self.data.zone = zone
            self:AddEvent("ZONE_ENTERED", zone, { mapID = self:VisitZone() })
        end
    elseif event == "PLAYER_LEVEL_UP" then
        local level = ...
        self:AddEvent("LEVEL_UP", tostring(level or ""))
        self:UpdateXP()
    elseif event == "PLAYER_DEAD" then
        self.data.deaths = self.data.deaths + 1
        self:AddEvent("PLAYER_DEAD")
    elseif event == "PLAYER_XP_UPDATE" then
        self:UpdateXP()
    elseif event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" then
        local first, second = ...
        local questID = event == "QUEST_ACCEPTED" and (second or first) or first
        if type(questID) == "number" and questID > 0 then
            if event == "QUEST_TURNED_IN" and type(self.data.questTurnIns) == "number" then
                self.data.questTurnIns = self.data.questTurnIns + 1
            elseif event == "QUEST_ACCEPTED" then
                self.observedQuests = self.observedQuests or {}
                self.observedQuests[questID] = false
            end
            self:AddEvent(event, self:QuestTitle(questID), { questID = questID, mapID = PlayerMap() })
        end
    end
    self.data.lastSeenAt = Now()
    if MS.JourneyMemory then
        if event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
            MS.JourneyMemory:ObservePlayerZone(self.data.level, self.data.lastSeenAt)
        end
        MS.JourneyMemory:Checkpoint(self.data)
    end
    self:RefreshHeader()
end

function Session:GetSummary()
    local data = self.data
    if not data then return nil end
    local duration = math.max(0, Now() - data.startedAt)
    local perHour = duration > 0 and data.xpGained * 3600 / duration or 0
    local remaining = math.max(0, (data.lastXPMax or 0) - (data.lastXP or 0))
    return { duration = duration, xpGained = data.xpGained, xpPerHour = perHour,
        etaNextLevel = perHour > 0 and math.floor(remaining * 3600 / perHour) or nil,
        level = data.level, xp = data.lastXP, xpMax = data.lastXPMax,
        zone = data.zone, character = data.character, events = #data.events,
        deaths = data.deaths, questTurnIns = data.questTurnIns, zonesVisited = data.zonesVisited }
end

function Session:StartClock()
    if self.ticker or not self.active then return end
    if type(C_Timer) ~= "table" or type(C_Timer.NewTicker) ~= "function" then return end
    self.ticker = C_Timer.NewTicker(1, function()
        if self.data then self.data.lastSeenAt = Now() end
        self:RefreshHeader()
    end)
end

function Session:StopClock()
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if self.data then self.data.lastSeenAt = Now() end
    if MS.JourneyMemory then MS.JourneyMemory:Checkpoint(self.data) end
end

function Session:RefreshHeader()
    if MS.JourneyWorkspace then MS.JourneyWorkspace:RefreshHeader() end
    if MS.JourneySessionJournal then MS.JourneySessionJournal:RefreshSummary() end
end
