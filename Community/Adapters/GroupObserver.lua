local MS = _G.MS
MS.Community = MS.Community or {}
-- Translates WoW group facts into Encounter snapshots. Reads only: roster identity, connection,
-- zone-level comparisons and the player's own place. Nothing about other players is persisted;
-- only booleans (same zone / same instance) leave this file, never a location.
local C = MS.Community
local O = { feature = "encounterMemories", interval = 15, settleSeconds = 5 }
C.GroupObserver = O

local Call = MS.Community.Call  -- pcall + secret-value filtering

local function Uptime() return Call(_G.GetTime) or 0 end

local function BestMap(unit)
    local map = _G.C_Map
    local id = type(map) == "table" and Call(map.GetBestMapForUnit, unit) or nil
    return type(id) == "number" and id > 0 and id or nil
end

local function LocalZone(mapID)
    if not mapID then return nil end
    local data = MS.JourneyMapData
    if data and data.LocalZone then return Call(data.LocalZone, data, mapID) end
    return mapID
end

local function PlaceName(mapID)
    local data = MS.JourneyMapData
    local info = data and data.Info and Call(data.Info, data, mapID)
    if not info and type(_G.C_Map) == "table" then info = Call(_G.C_Map.GetMapInfo, mapID) end
    return type(info) == "table" and type(info.name) == "string" and info.name or nil
end

function O:PlayerPlace()
    local data = MS.JourneyMapData
    local mapID = data and data.PlayerZone and Call(data.PlayerZone, data) or LocalZone(BestMap("player")) or BestMap("player")
    local inInstance = Call(_G.IsInInstance) == true
    local name = PlaceName(mapID)
    if inInstance then name = Call(_G.GetInstanceInfo) or name end
    -- Location is transient after login and transitions: a place is settled only when the same
    -- reading holds after the settle delay.
    local stable = mapID ~= nil and mapID == self.lastMapID and Uptime() - (self.zoneChangedAt or 0) >= self.settleSeconds
    self.lastMapID = mapID
    return { mapID = mapID, name = name, instance = inInstance, settled = stable and type(name) == "string" }
end

local function MemberIdentity(unit)
    local guid = Call(_G.UnitGUID, unit)
    local name = Call(_G.UnitName, unit)
    local realm
    if guid and type(_G.GetPlayerInfoByGUID) == "function" then
        local _, _, _, _, _, _, guidRealm = Call(_G.GetPlayerInfoByGUID, guid)
        if type(guidRealm) == "string" and guidRealm ~= "" then realm = guidRealm end
    end
    return C.Identity.Make(guid, name, realm)
end

function O:Snapshot()
    local snap = { inGroup = false, members = {}, mono = Uptime() }
    local count = Call(_G.GetNumGroupMembers) or 0
    if type(count) ~= "number" or count <= 1 then return snap end
    snap.inGroup, snap.raid = true, Call(_G.IsInRaid) == true
    snap.place = self:PlayerPlace()
    local playerGUID = Call(_G.UnitGUID, "player")
    local playerMap = BestMap("player")
    local playerZone = LocalZone(playerMap)
    local prefix, total = snap.raid and "raid" or "party", snap.raid and math.min(count, 40) or math.min(count - 1, 4)
    for index = 1, total do
        local unit = prefix .. index
        if Call(_G.UnitExists, unit) then
            local identity = MemberIdentity(unit)
            local key = identity and C.Identity.Key(identity)
            if key and identity.guid ~= playerGUID then
                local member = { identity = identity, connected = Call(_G.UnitIsConnected, unit) ~= false }
                local memberMap = member.connected and BestMap(unit) or nil
                if memberMap and playerZone and not snap.place.instance then member.sameZone = LocalZone(memberMap) == playerZone end
                -- Same map is not the same instance copy: only visibility proves it. Unknown stays nil.
                if snap.place.instance and member.connected then
                    if Call(_G.UnitIsVisible, unit) then member.sameInstance = true
                    elseif memberMap and playerMap and memberMap ~= playerMap then member.sameInstance = false end
                end
                snap.members[key] = member
            end
        end
    end
    if C.caps and C.Capabilities.Usable(C.caps.QuestGroupFacts) and C.QuestFacts then
        snap.groupQuest = C.QuestFacts:ActiveGroupQuest()
    end
    return snap
end

function O:Sample()
    if not self.engine then return end
    local ok, snap = pcall(self.Snapshot, self)
    if not ok then C:Log("COMPONENT_ERROR", { component = "GroupObserver", phase = "SAMPLE", reason = tostring(snap) }); return end
    self.engine:Observe(C.Now(), snap)
    if C.OnEncounterSample then C:OnEncounterSample(self.engine and self.engine.session ~= nil) end
end

function O:OnEngineEvent(event)
    local kind = event.type
    if kind == "SESSION_START" then
        C:Log("GROUP_SESSION_START", { session = event.session, raid = event.raid, members = event.members,
            presentAtStart = event.presentAtStart })
    elseif kind == "MEMBER_JOIN" then
        C:Log("GROUP_MEMBER_JOIN", { session = event.session, subject = event.identity, guid = event.identity.guid ~= nil,
            realm = event.identity.realm ~= nil, presentAtStart = event.presentAtStart })
    elseif kind == "EVIDENCE" then
        C:Log("ENCOUNTER_EVIDENCE", { session = event.session, kind = event.kind, place = event.place })
    elseif kind == "MEMBER_LEAVE" then
        local candidate = event.candidate
        C:Log("GROUP_MEMBER_LEAVE", { session = event.session, subject = event.identity, grouped = math.floor(event.grouped) })
        local claims = {}
        for claim in pairs(candidate.claims) do claims[#claims + 1] = claim end
        table.sort(claims)
        C:Log("MEMORY_CANDIDATE", { session = event.session, subject = event.identity, confidence = candidate.confidence,
            reasons = table.concat(candidate.reasons, ","), claims = table.concat(claims, ","), rejected = candidate.rejected })
        if candidate.propose and C.OnCandidate then C:OnCandidate(candidate) end
    elseif kind == "SESSION_END" then
        C:Log("GROUP_SESSION_END", { session = event.session, duration = event.duration, members = event.members,
            candidates = event.candidates, reason = event.reason })
    end
end

function O:Start()
    self.engine = C.Encounter.New(nil, function(event) O:OnEngineEvent(event) end)
    self.lastMapID, self.zoneChangedAt = nil, Uptime()
    if not self.frame then
        self.frame = CreateFrame("Frame")
        self.frame:SetScript("OnEvent", function(_, event) O:OnEvent(event) end)
    end
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
        "ZONE_CHANGED_INDOORS" }) do pcall(self.frame.RegisterEvent, self.frame, event) end
    self.ticker = C_Timer.NewTicker(self.interval, function() O:Sample() end)
    self:Sample()
end

function O:OnEvent(event)
    if event ~= "GROUP_ROSTER_UPDATE" then self.zoneChangedAt = Uptime() end
    -- Coalesce bursts of roster/zone events into one sample shortly after.
    if self.pending then return end
    self.pending = true
    C_Timer.After(event == "GROUP_ROSTER_UPDATE" and 1 or self.settleSeconds + 1, function()
        O.pending = false
        O:Sample()
    end)
end

-- Evidence is RAM-only: stopping (flag off, logout, reload) drops it without proposing anything.
function O:Stop()
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if self.frame then self.frame:UnregisterAllEvents() end
    if self.engine then self.engine:Reset() end
    self.engine, self.pending = nil, false
end

C:Register("GroupObserver", O)
