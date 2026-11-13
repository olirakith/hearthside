local MS = _G.MS
MS.Community = MS.Community or {}
-- Encounter sessions from observed group facts. Pure and RAM-only: nothing here is persisted.
-- Evidence keeps its exact nature: being grouped is not being together, and the player's own
-- zone is not the companion's zone unless a same-zone reading says so.
local E = {}
MS.Community.Encounter = E
local Identity = MS.Community.Identity

E.policy = {
    sampleCap = 60,            -- seconds credited per observation gap at most (AFK, loading, sleep)
    minPresenceSeconds = 120,  -- below this a member is ignored ("very short group")
    minGroupedSeconds = 600,   -- heuristic: worth proposing a memory without stronger evidence
    routeSeconds = 300, routeSamples = 3,   -- same-zone time needed for "part of your road together"
    instanceSeconds = 180,     -- same-instance time needed for an instance claim
    leaveGrace = 60,           -- a member back within this window continues the same encounter
    endGrace = 60,             -- group reformed within this window continues the same session
}

-- Claims a candidate may NEVER support, whatever its evidence. Nothing observed proves them.
E.memberLimit = 80   -- active members tracked at once (a 40-man raid plus pending departures)

E.FORBIDDEN = { "QUEST_COMPLETED_TOGETHER", "DUNGEON_CLEARED", "KILLED_TOGETHER", "FIRST_MEETING", "FRIENDSHIP",
    "COPRESENCE_AT_PLACE" }

local Engine = {}
Engine.__index = Engine

function E.New(policy, sink)
    return setmetatable({ policy = policy or E.policy, sink = sink, serial = 0 }, Engine)
end

local function Emit(self, events, event)
    events[#events + 1] = event
    if self.sink then self.sink(event) end
end

local function Add(map, key, value) map[key] = (map[key] or 0) + value end

local function Best(map)
    local bestKey, bestValue
    for key, value in pairs(map) do
        if not bestValue or value > bestValue or (value == bestValue and tostring(key) < tostring(bestKey)) then
            bestKey, bestValue = key, value
        end
    end
    return bestKey, bestValue or 0
end

local function SettledZone(place)
    return place and place.settled == true and type(place.mapID) == "number" and place.mapID or nil
end

function Engine:Start(now, snap, presentAtStart)
    self.serial = self.serial + 1
    local session = { id = string.format("s%.0f.%d", now, self.serial), startedAt = now, raid = snap.raid == true,
        members = {}, active = 0, memberCount = 0, places = {}, presentAtStart = presentAtStart, candidates = 0, serial = 0 }
    self.session = session
    return session
end

-- Credits the interval that just ended using the state observed at its start.
function Engine:Account(snap, delta)
    local session = self.session
    if delta <= 0 or not snap.inGroup then return end
    local place = snap.place or {}
    local zone = SettledZone(place)
    if zone then session.places[zone] = { mapID = zone, name = place.name, instance = place.instance == true } end
    for key, observed in pairs(snap.members or {}) do
        local member = session.members[key]
        if member and not member.leftAt then
            member.grouped = member.grouped + delta
            -- The player's group quest counts only for the companions present while it was active.
            if snap.groupQuest then member.questContext = { questID = snap.groupQuest.questID, title = snap.groupQuest.title } end
            if zone then Add(member.playerZones, zone, delta) end
            if zone and not place.instance and observed.sameZone == true then
                Add(member.sameZone, zone, delta); Add(member.sameZoneSamples, zone, 1)
            end
            if zone and place.instance and observed.sameInstance == true then
                Add(member.instance, zone, delta); Add(member.instanceSamples, zone, 1)
            end
        end
    end
end

local function NewMember(session, key, observed, now, clock)
    session.memberCount = session.memberCount + 1
    session.active = session.active + 1
    session.serial = session.serial + 1
    -- The episode id is opaque (session serial), never derived from the member's identity.
    return { key = key, episode = "e" .. session.serial, identity = Identity.Copy(observed.identity), joinedAt = now,
        presentAtStart = session.presentAtStart and clock == session.startClock, grouped = 0, rejoins = 0, transitions = 0,
        playerZones = {}, sameZone = {}, sameZoneSamples = {}, instance = {}, instanceSamples = {} }
end

-- now: civil time for the memory's dates. snap.mono (when given): monotonic seconds used for
-- every duration and grace window, so a civil clock change never inflates evidence.
function Engine:Observe(now, snap)
    local events, policy = {}, self.policy
    snap = snap or {}
    local clock = snap.mono or now
    local previous = self.last
    -- Out-of-order or replayed observation: ignored without touching any state.
    if previous and clock < previous.clock then return events end
    self.last = { now = now, clock = clock, snap = snap }
    local session = self.session
    if session and previous then
        self:Account(previous.snap, math.max(0, math.min(clock - previous.clock, policy.sampleCap)))
    end
    -- Deadlines that expired before this observation are settled first: a return after the
    -- grace window is a new encounter, not a rejoin.
    if session then
        self:Settle(now, clock, events, false)
        session = self.session
    end
    local members = snap.members or {}
    if snap.inGroup and next(members) then
        if not session then
            session = self:Start(now, snap, previous == nil)
            session.startClock = clock
            local count = 0
            for _ in pairs(members) do count = count + 1 end
            Emit(self, events, { type = "SESSION_START", session = session.id, raid = session.raid,
                members = count, presentAtStart = session.presentAtStart })
        end
        session.notInGroupSince = nil
        session.raid = session.raid or snap.raid == true
        local zone, previousZone = SettledZone(snap.place), previous and SettledZone(previous.snap.place)
        local keys = {}
        for key in pairs(members) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local observed = members[key]
            local member = session.members[key]
            if not member then
                if session.active < E.memberLimit then
                    member = NewMember(session, key, observed, now, clock)
                    session.members[key] = member
                    Emit(self, events, { type = "MEMBER_JOIN", session = session.id, key = key, identity = member.identity,
                        presentAtStart = member.presentAtStart })
                end
            elseif member.leftAt then
                member.leftAt, member.leftAtCivil, member.rejoins = nil, nil, member.rejoins + 1
                Emit(self, events, { type = "MEMBER_REJOIN", session = session.id, key = key })
            end
            if member and observed.identity and observed.identity.guid and not member.identity.guid then
                member.identity.guid = observed.identity.guid
            end
            -- Zone change while grouped, with the member observed in the new zone as well.
            if member and zone and previousZone and zone ~= previousZone and observed.sameZone == true
                and previous.snap.members and previous.snap.members[key] then
                member.transitions = member.transitions + 1
                Emit(self, events, { type = "EVIDENCE", session = session.id, key = key,
                    kind = "ZONE_TRANSITION_WHILE_GROUPED", place = zone })
            end
        end
        for key, member in pairs(session.members) do
            if not members[key] and not member.leftAt then member.leftAt, member.leftAtCivil = clock, now end
        end
    elseif session then
        session.notInGroupSince = session.notInGroupSince or clock
        for _, member in pairs(session.members) do
            if not member.leftAt then member.leftAt, member.leftAtCivil = clock, now end
        end
    end
    return events
end

-- Finalizes members gone for longer than the grace window, then the session itself.
-- Finalized members are removed from RAM: a raid that keeps renewing stays bounded.
function Engine:Settle(now, clock, events, force)
    local session, policy = self.session, self.policy
    local keys = {}
    for key in pairs(session.members) do keys[#keys + 1] = key end
    table.sort(keys)
    local ending = force or (session.notInGroupSince and clock - session.notInGroupSince >= policy.endGrace)
    for _, key in ipairs(keys) do
        local member = session.members[key]
        if ending or (member.leftAt and clock - member.leftAt >= policy.leaveGrace) then
            member.endedAt = member.leftAtCivil or now
            local candidate = E.Evaluate(member, session, policy)
            if candidate.propose then session.candidates = session.candidates + 1 end
            session.members[key] = nil
            session.active = session.active - 1
            Emit(self, events, { type = "MEMBER_LEAVE", session = session.id, key = key, identity = member.identity,
                grouped = member.grouped, candidate = candidate })
        end
    end
    if ending then
        Emit(self, events, { type = "SESSION_END", session = session.id, duration = now - session.startedAt,
            members = session.memberCount, candidates = session.candidates, reason = force and "FORCED" or "GROUP_LEFT" })
        self.session = nil
    end
end

-- Logout, reload or Community switched off: evidence is dropped, never written down.
function Engine:Reset()
    self.session, self.last = nil, nil
end

-- Flushes the open session (used when Community stops while grouped).
function Engine:Close(now)
    local events = {}
    if self.session then self:Settle(now, self.last and self.last.clock or now, events, true) end
    self.last = nil
    return events
end

function E.Evaluate(member, session, policy)
    policy = policy or E.policy
    local candidate = { id = session.id .. ":" .. member.episode, session = session.id, key = member.key,
        identity = Identity.Copy(member.identity), startedAt = member.joinedAt, endedAt = member.endedAt,
        grouped = member.grouped, presentAtStart = member.presentAtStart == true, rejoins = member.rejoins,
        claims = {}, forbidden = {}, reasons = {}, propose = false }
    for _, claim in ipairs(E.FORBIDDEN) do candidate.forbidden[claim] = true end
    local reasons = candidate.reasons
    reasons[#reasons + 1] = "GROUP_MEMBER"
    reasons[#reasons + 1] = "GROUP_DURATION:" .. math.floor(member.grouped)
    if member.presentAtStart then reasons[#reasons + 1] = "PRESENT_AT_START" end
    if member.grouped < policy.minPresenceSeconds then
        candidate.rejected = "TOO_SHORT"
        return candidate
    end
    candidate.claims.GROUP_MEMBER = true
    local instanceZone, instanceSeconds = Best(member.instance)
    local routeZone, routeSeconds = Best(member.sameZone)
    local playerZone = Best(member.playerZones)
    if instanceZone and instanceSeconds >= policy.instanceSeconds then
        candidate.claims.SAME_INSTANCE = true
        reasons[#reasons + 1] = "INSTANCE_PRESENCE:" .. math.floor(instanceSeconds)
    end
    if routeZone and routeSeconds >= policy.routeSeconds and (member.sameZoneSamples[routeZone] or 0) >= policy.routeSamples then
        candidate.claims.SHARED_ROUTE = true
        reasons[#reasons + 1] = "SAME_ZONE_OBSERVED:" .. math.floor(routeSeconds)
    end
    if member.transitions > 0 then reasons[#reasons + 1] = "ZONE_TRANSITION_WHILE_GROUPED:" .. member.transitions end
    if member.questContext then
        candidate.claims.PLAYER_QUEST_CONTEXT = true
        candidate.context = { questID = member.questContext.questID, title = member.questContext.title }
        reasons[#reasons + 1] = "PLAYER_GROUP_QUEST_ACTIVE"
    end
    -- The memory's place: shared evidence first, otherwise the player's own place (a fact about
    -- the player, never presented as the companion's location).
    local placeZone = candidate.claims.SAME_INSTANCE and instanceZone or candidate.claims.SHARED_ROUTE and routeZone or playerZone
    local place = placeZone and session.places[placeZone]
    if not place then
        candidate.rejected = "PLACE_UNSETTLED"
        return candidate
    end
    candidate.place = { mapID = place.mapID, name = place.name, instance = place.instance }
    candidate.placeShared = candidate.claims.SAME_INSTANCE or candidate.claims.SHARED_ROUTE or false
    candidate.propose = member.grouped >= policy.minGroupedSeconds or candidate.claims.SAME_INSTANCE == true
        or candidate.claims.SHARED_ROUTE == true
    if not candidate.propose then candidate.rejected = "BELOW_THRESHOLD" end
    candidate.confidence = candidate.claims.SAME_INSTANCE and "HIGH"
        or candidate.claims.SHARED_ROUTE and (routeSeconds >= 1200 and "HIGH" or "MEDIUM") or "LOW"
    return candidate
end
