local MS = _G.MS
MS.JourneyDayLog = {}
local Log = MS.JourneyDayLog
local listeners = {}

local function Hidden(v) return type(_G.issecretvalue) == "function" and issecretvalue(v) end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end
local function Num(v)
    if Hidden(v) then return nil end
    return type(v) == "number" and v == v and v >= 0 and v < math.huge and v or nil
end
local function Text(v)
    if Hidden(v) then return nil end
    return type(v) == "string" and #v > 0 and #v <= 256 and v or nil
end
local function Tab(v) return not Hidden(v) and type(v) == "table" and v or {} end
local function Yes(v) return not Hidden(v) and v == true end
local function Now() return Num(Call(_G.time)) or 0 end
local function Key(t) return Text(Call(_G.date, "%Y-%m-%d", t)) end
local function Map() return Num(Call(_G.C_Map and C_Map.GetBestMapForUnit, "player")) end
local function Level() return Num(Call(_G.UnitLevel, "player")) end
local function Notify(kind, entry, day)
    for _, fn in ipairs(listeners) do pcall(fn, kind, entry, day) end
end
local function TrimEntries(entries)
    while #entries > 400 do
        local remove = 1
        for i, e in ipairs(entries) do if e.kind ~= "LOGIN" then remove = i; break end end
        table.remove(entries, remove)
    end
end
local function SortEntries(entries)
    local order = {}
    for i, e in ipairs(entries) do order[e] = i end
    table.sort(entries, function(a, b)
        if a.at == b.at then return order[a] < order[b] end
        return a.at < b.at
    end)
end
local function NewDay(key, at)
    return { key = key, firstAt = at, lastAt = at, playSeconds = 0, sessions = 0,
        startLevel = Level(), endLevel = Level(), xpGained = 0, quests = 0, bosses = 0,
        deaths = 0, kills = Log.killBase ~= nil and 0 or nil, entries = {}, companions = {} }
end
local kinds = { LOGIN = true, ZONE = true, QUEST = true, LEVEL = true, DEATH = true,
    KILLS = true, GROUP = true, DUNGEON = true }
local textFields = { "zone", "subzone", "title", "killer", "name", "class" }
local numberFields = { "mapID", "questID", "level", "seconds", "killerLevel", "since", "count", "id", "kills", "total" }
local function CleanEntry(raw)
    raw = Tab(raw)
    local kind, at = Text(raw.kind), Num(raw.at)
    if not kind or not kinds[kind] or not at then return nil end
    local e = { kind = kind, at = at }
    for _, k in ipairs(textFields) do e[k] = Text(raw[k]) end
    for _, k in ipairs(numberFields) do e[k] = Num(raw[k]) end
    for _, k in ipairs({ "first", "guessed", "killerElite", "done" }) do e[k] = Yes(raw[k]) or nil end
    if kind == "DUNGEON" then
        if not e.id then return nil end
        e.since, e.kills, e.bosses, e.companions = e.since or at, e.kills or 0, {}, {}
        for _, boss in pairs(Tab(raw.bosses)) do
            boss = Tab(boss)
            local id, stamp = Num(boss.encounterID), Num(boss.at)
            if id and stamp then e.bosses[#e.bosses + 1] = { encounterID = id, at = stamp,
                name = Text(boss.name), npcID = Num(boss.npcID) } end
        end
        table.sort(e.bosses, function(a, b) return a.at < b.at end)
        for _, name in pairs(Tab(raw.companions)) do
            name = Text(name)
            if name then e.companions[#e.companions + 1] = name end
        end
    elseif kind == "KILLS" and not e.count then return nil end
    return e
end
local function Sanitize(raw)
    local data = { version = 1, days = {} }
    for key, day in pairs(Tab(Tab(raw).days)) do
        key = Text(key)
        if key and key:match("^%d%d%d%d%-%d%d%-%d%d$") and type(day) == "table" and not Hidden(day) then
            local first = Num(day.firstAt)
            if first and Key(first) == key then
                local clean = NewDay(key, first)
                clean.startLevel, clean.endLevel = Num(day.startLevel), Num(day.endLevel)
                clean.lastAt = math.max(first, Num(day.lastAt) or first)
                for _, k in ipairs({ "playSeconds", "sessions", "xpGained", "quests", "kills", "bosses", "deaths" }) do
                    clean[k] = Num(day[k]) or (k ~= "kills" and 0 or nil)
                end
                for _, rawEntry in pairs(Tab(day.entries)) do
                    local e = CleanEntry(rawEntry)
                    if e then clean.entries[#clean.entries + 1] = e end
                end
                SortEntries(clean.entries); TrimEntries(clean.entries)
                for name, mate in pairs(Tab(day.companions)) do
                    name, mate = Text(name), Tab(mate)
                    if name and Num(mate.seconds) then clean.companions[name] = {
                        seconds = Num(mate.seconds), class = Text(mate.class), level = Num(mate.level) } end
                end
                data.days[key] = clean
            end
        end
    end
    return data
end
local function TrimDays()
    local keys = {}
    for key in pairs(Log.data.days) do keys[#keys + 1] = key end
    table.sort(keys)
    for i = 1, #keys - 14 do Log.data.days[keys[i]] = nil end
end
local function DayAt(at)
    if not Log.data then return nil end
    local key = Key(at)
    if not key then return nil end
    local day = Log.data.days[key]
    if not day then day = NewDay(key, at); Log.data.days[key] = day; TrimDays() end
    day.firstAt, day.lastAt = math.min(day.firstAt, at), math.max(day.lastAt, at)
    return day
end
local function Add(e)
    local day = DayAt(e.at)
    if not day then return end
    day.entries[#day.entries + 1] = e
    SortEntries(day.entries); TrimEntries(day.entries)
    Notify("ADD", e, day)
    return day
end
local function Location(e)
    local current = Log.current or {}
    e.zone, e.mapID = current.zone, current.mapID
    return e
end
-- Just after someone joins, the game may not know them yet: "Unknown", level 0. Not a name.
local function Known(name) return name and name ~= _G.UNKNOWNOBJECT and name ~= _G.UNKNOWN and name or nil end
local function FullName(unit)
    local first, second = Call(_G.UnitName, unit)
    first, second = Known(Text(first)), Text(second)
    return first and (second and first .. " " .. second or first) or nil
end
local function UnitLevelOf(unit)
    local level = Num(Call(_G.UnitLevel, unit))
    return level and level >= 1 and level or nil
end
local function NPC(unit)
    local guid = Text(Call(_G.UnitGUID, unit))
    if not guid then return nil end
    local kind, id = guid:match("^(%a+)%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-")
    return (kind == "Creature" or kind == "Vehicle") and Num(tonumber(id)) or nil
end
local function Hostile(unit, attacking)
    if not Yes(Call(_G.UnitCanAttack, "player", unit)) then return nil end
    if attacking and not Yes(Call(_G.UnitIsUnit, unit .. "target", "player")) then return nil end
    local name = Text(Call(_G.UnitName, unit))
    if not name then return nil end
    local class = Text(Call(_G.UnitClassification, unit))
    return { killer = name, killerLevel = Num(Call(_G.UnitLevel, unit)),
        killerElite = class == "elite" or class == "rareelite" or class == "worldboss" or nil }
end
local function Killer(at)
    local found = Hostile("target", true)
    if found then return found end
    for i = 1, 40 do found = Hostile("nameplate" .. i, true); if found then return found end end
    if Log.lastHostile and at >= Log.lastHostile.at and at - Log.lastHostile.at <= 10 then
        found = Log.lastHostile; found.guessed = true; return found
    end
    return {}
end
local function Stat(id)
    local value = Call(_G.GetStatistic, id)
    local number = Num(value)
    if number then return number end
    value = Text(value)
    if value and value:match("%d") and not value:find("[^%d%s,%.\194\160\226\128\175]") then
        return Num(tonumber((value:gsub("%D", ""))))
    end
end
local function KillStat()
    if Log.statID then return Stat(Log.statID) end
    for _, id in ipairs({ 1197, 107 }) do
        local n = Stat(id)
        if n then Log.statID = id; return n end
    end
end
local function PollKills(at)
    local value = KillStat()
    if not value then Log.killBase = nil; return end
    local base, since = Log.killBase, Log.killAt or at
    Log.killBase, Log.killAt = value, at
    local day = DayAt(at)
    if not day then return end
    day.kills = day.kills or 0
    if not base or value <= base then return end
    local count = value - base
    day.kills = day.kills + count
    if Log.dungeon then
        local e = Log.dungeon
        e.kills, e.at = e.kills + count, at
        SortEntries(Log.dungeonDay.entries); Notify("UPDATE", e, Log.dungeonDay)
        Notify("STATS", nil, day)
    else
        local last, current = day.entries[#day.entries], Log.current or {}
        if last and last.kind == "KILLS" and last.zone == current.zone and last.mapID == current.mapID
            and at >= last.at and at - last.at < 900 then
            last.count, last.at = last.count + count, at; Notify("UPDATE", last, day)
        else Add(Location({ kind = "KILLS", at = at, since = since, count = count })) end
    end
end
-- silent: on load, the group already there is not news (a reload would log everyone again).
-- Someone the game does not know yet is looked at again a little later; a join logged
-- before their level or class arrived is completed then.
local Group
local function GroupLater(silent)
    local timer = _G.C_Timer
    if Log.groupRetry or (Log.groupTries or 0) >= 15 or type(timer) ~= "table" or type(timer.After) ~= "function" then return end
    Log.groupRetry, Log.groupTries = true, (Log.groupTries or 0) + 1
    Call(timer.After, 2, function() Log.groupRetry = nil; Group(Now(), silent) end)
end
Group = function(at, silent)
    local roster, waiting = {}, false
    local raid = Yes(Call(_G.IsInRaid))
    local count = Num(Call(raid and _G.GetNumGroupMembers or _G.GetNumSubgroupMembers)) or 0
    Log.joined = Log.joined or {}
    for i = 1, math.min(count, 40) do
        local unit = (raid and "raid" or "party") .. i
        if not Yes(Call(_G.UnitIsUnit, unit, "player")) then
            local name = FullName(unit)
            if not name then waiting = true end
            if name then
                local _, class = Call(_G.UnitClass, unit)
                local mate = { class = Text(class), level = UnitLevelOf(unit) }
                if not mate.level or not mate.class then waiting = true end
                roster[name] = mate
                local joined = Log.joined[name]
                if not silent and not Log.roster[name] then
                    local entry = { kind = "GROUP", at = at, name = name, class = mate.class, level = mate.level }
                    Log.joined[name] = { entry = entry, day = Add(entry) }
                elseif joined and ((not joined.entry.level and mate.level) or (not joined.entry.class and mate.class)) then
                    joined.entry.level = joined.entry.level or mate.level
                    joined.entry.class = joined.entry.class or mate.class
                    if joined.day then Notify("UPDATE", joined.entry, joined.day) end
                end
                if Log.dungeon then
                    local found = false
                    for _, companion in ipairs(Log.dungeon.companions) do if companion == name then found = true end end
                    if not found then
                        Log.dungeon.companions[#Log.dungeon.companions + 1] = name
                        Notify("UPDATE", Log.dungeon, Log.dungeonDay)
                    end
                end
            end
        end
    end
    Log.roster = roster
    for name in pairs(Log.joined) do if not roster[name] then Log.joined[name] = nil end end
    if waiting then GroupLater(silent) else Log.groupTries = 0 end
end
local function Dungeon(at)
    local d = Call(MS.JourneyDungeons and MS.JourneyDungeons.Current, MS.JourneyDungeons)
    d = Tab(d)
    local id = Num(d.id)
    if Log.dungeon and Log.dungeon.id == id then return end
    if Log.dungeon then
        Log.dungeon.done, Log.dungeon.at = true, at
        SortEntries(Log.dungeonDay.entries); Notify("UPDATE", Log.dungeon, Log.dungeonDay)
        Log.dungeon, Log.dungeonDay, Log.encounter = nil, nil, nil
    end
    if not id then return end
    local day = DayAt(at)
    if not day then return end
    for _, summary in ipairs(Log:Days()) do
        local saved = Log.data.days[summary.key]
        for i = #saved.entries, 1, -1 do
            local e = saved.entries[i]
            if e.kind == "DUNGEON" and not e.done then
                if not Log.dungeon and e.id == id and at >= e.at and at - e.at < 1800 then
                    Log.dungeon, Log.dungeonDay = e, saved
                    e.at, saved.lastAt = at, math.max(saved.lastAt, at)
                    SortEntries(saved.entries); Notify("UPDATE", e, saved)
                else
                    e.done = true; Notify("UPDATE", e, saved)
                end
            end
        end
    end
    if Log.dungeon then return end
    local names = {}
    for name in pairs(Log.roster) do names[#names + 1] = name end
    table.sort(names)
    local bosses = MS.JourneyDungeonBosses and MS.JourneyDungeonBosses[id]
    local e = { kind = "DUNGEON", at = at, since = at, id = id, name = Text(d.name), mapID = Map(),
        companions = names, kills = 0, bosses = {}, total = type(bosses) == "table" and #bosses or nil }
    Log.dungeon, Log.dungeonDay = e, Add(e)
end
-- The player's map, unless it is a whole continent or the world (the client's answer early at login).
local function PlaceMap()
    local id = Map()
    local info = id and Call(_G.C_Map and C_Map.GetMapInfo, id)
    local types = _G.Enum and Enum.UIMapType or {}
    local kind = type(info) == "table" and info.mapType
    if kind == (types.Continent or 2) or kind == (types.World or 1) or kind == (types.Cosmic or 0) then return nil end
    return id
end
local function RefreshZone(at, detail, metadata)
    Log.current = { zone = Text(detail) or Text(Call(_G.GetZoneText)),
        subzone = Text(Call(_G.GetSubZoneText)), mapID = PlaceMap() or (metadata.mapID ~= Map() and Num(metadata.mapID)) or nil, since = at }
    Log.lastHostile = nil
end
-- At login the client may not know the zone yet, or give a whole continent: ask again later.
local function FillZone()
    local current = Log.current
    if not current then return end
    current.zone = current.zone or Text(Call(_G.GetZoneText))
    current.mapID = PlaceMap() or current.mapID
end
local function XP(at)
    local xp, level, maximum = Num(Call(_G.UnitXP, "player")), Level(), Num(Call(_G.UnitXPMax, "player"))
    if xp and level and Log.xp and Log.level then
        local delta = level == Log.level and math.max(0, xp - Log.xp) or
            (level > Log.level and Log.xpMax and math.max(0, Log.xpMax - Log.xp) + xp or 0)
        local day = DayAt(at)
        if day then day.xpGained, day.endLevel = day.xpGained + delta, level; Notify("STATS", nil, day) end
    end
    Log.xp, Log.level, Log.xpMax = xp, level, maximum
end
local function OnTaxi()
    local flying = Call(_G.UnitOnTaxi, "player")
    return not Hidden(flying) and flying == true
end
-- Whether the zone just reached is a first visit (the memory may have noted it since `since`).
local function FirstVisit(at, since)
    local memory = MS.JourneyMemory and MS.JourneyMemory.data
    local id, first = Log.current and Log.current.mapID, nil
    if id and memory and not Log.seenZones[id] then
        local zone = Tab(memory.zones)[id]
        local visited = zone and Num(Tab(zone).firstVisitedAt)
        first = not zone or visited == at or (since and visited and visited >= since) or false
    end
    if id then Log.seenZones[id] = true end
    return first or nil
end
-- A flight logs no zone on the way: one arrival when the player lands, unless back where they left.
local function Land(at)
    local flight = Log.flight
    if not flight or OnTaxi() then return end
    Log.flight = nil
    local current = Log.current
    if not current then return end
    current.since = at
    if current.zone and current.zone ~= flight.from then
        local first = FirstVisit(at, flight.at)
        Add(Location({ kind = "ZONE", at = at, first = first, from = flight.from }))
    end
end
local function Tick()
    local at = Now()
    local cursor = math.max(Log.tickAt or at, at - 60)
    Log.tickAt = at
    while cursor < at do
        local parts = Call(_G.date, "*t", cursor)
        local boundary
        if type(parts) == "table" then
            parts.hour, parts.min, parts.sec, parts.day, parts.isdst = 0, 0, 0, parts.day + 1, nil
            boundary = Num(Call(_G.time, parts))
        end
        local finish = boundary and boundary > cursor and math.min(at, boundary) or at
        local day = DayAt(cursor)
        if day then
            local seconds = finish - cursor
            day.playSeconds, day.lastAt = day.playSeconds + seconds, finish
            for name, mate in pairs(Log.roster) do
                local saved = day.companions[name] or { seconds = 0 }
                saved.seconds, saved.class, saved.level = saved.seconds + seconds, mate.class, mate.level
                day.companions[name] = saved
            end
            Notify("STATS", nil, day)
            if Log.playedLevel then Log.playedLevel = Log.playedLevel + seconds end
        end
        cursor = finish
    end
    XP(at)
    Land(at)
end

function Log:OnSessionEvent(kind, detail, metadata, now)
    if Hidden(kind) then return end
    -- Session starts before the integrator initializes this module.
    if not self.data then
        if kind == "SESSION_STARTED" then self.pending = { detail = Text(detail), metadata = metadata, at = Num(now) } end
        return
    end
    metadata = Tab(metadata)
    local at = Num(now) or Now()
    local day = DayAt(at)
    if not day then return end
    if kind == "SESSION_STARTED" then
        RefreshZone(at, detail, metadata)
        day.sessions = day.sessions + 1
        Add(Location({ kind = "LOGIN", at = at }))
    elseif kind == "ZONE_ENTERED" then
        local from = self.current and self.current.zone
        PollKills(at); RefreshZone(at, detail, metadata); Dungeon(at)
        if OnTaxi() then
            self.flight = self.flight or { from = from, at = at }
        else
            Add(Location({ kind = "ZONE", at = at, first = FirstVisit(at) }))
        end
    elseif kind == "QUEST_TURNED_IN" then
        day.quests = day.quests + 1
        local e = Location({ kind = "QUEST", at = at, title = Text(detail), questID = Num(metadata.questID) })
        e.mapID = Num(metadata.mapID) or e.mapID; Add(e)
    elseif kind == "LEVEL_UP" then
        local level = Num(detail) or (Text(detail) and Num(tonumber(detail)))
        day.endLevel = level or day.endLevel
        Add(Location({ kind = "LEVEL", at = at, level = level, seconds = Num(metadata.seconds) or self.playedLevel }))
        self.playedLevel = nil
    elseif kind == "DEATH" then
        local e = Location({ kind = "DEATH", at = at, subzone = self.current and self.current.subzone })
        for k, v in pairs(Killer(at)) do if k ~= "at" then e[k] = v end end
        day.deaths = day.deaths + 1; Add(e)
    end
end
local function CaptureBoss()
    local encounter = Log.encounter
    if not encounter then return end
    local fallback = NPC("boss1")
    for _, unit in ipairs({ "boss1", "boss2", "boss3", "boss4", "boss5", "target" }) do
        local name = Text(Call(_G.UnitName, unit))
        if name and name == encounter.name then
            local id = NPC(unit)
            if id then encounter.npcID = id; encounter.matched = true; return end
        end
    end
    if not encounter.npcID then encounter.npcID = fallback end
end
local function Event(_, event, a, b, c, d, success)
    local at = Now()
    if event == "PLAYER_TARGET_CHANGED" then
        local hostile = Hostile("target")
        if hostile then hostile.at = at; Log.lastHostile = hostile end
        CaptureBoss()
    elseif event == "ENCOUNTER_START" then
        local id, name = Num(a), Text(b)
        if id and name then Log.encounter = { id = id, name = name }; CaptureBoss() end
    elseif event == "ENCOUNTER_END" then
        local id, name, result = Num(a), Text(b), Num(success)
        if result == 1 and id and Log.dungeon then
            local e, duplicate = Log.dungeon, false
            for _, boss in ipairs(e.bosses) do if boss.encounterID == id then duplicate = true end end
            if not duplicate then
                local encounter = Log.encounter
                e.bosses[#e.bosses + 1] = { encounterID = id, name = name, at = at,
                    npcID = encounter and encounter.id == id and encounter.npcID or nil }
                e.at = at
                local day = DayAt(at)
                if day then day.bosses = day.bosses + 1; Notify("STATS", nil, day) end
                SortEntries(Log.dungeonDay.entries); Notify("UPDATE", e, Log.dungeonDay)
            end
        end
        Log.encounter = nil
    elseif event == "GROUP_ROSTER_UPDATE" then Tick(); Log.groupTries = 0; Group(at)
    elseif event == "PLAYER_REGEN_ENABLED" then PollKills(at)
    elseif event == "PLAYER_XP_UPDATE" then
        if Hidden(a) or (a ~= nil and a ~= "player") then return end
        XP(at)
        if not Log.pollPending then
            Log.pollPending = true
            local timer = _G.C_Timer
            if type(timer) == "table" and type(timer.After) == "function" then
                Call(timer.After, 1, function() Log.pollPending = nil; PollKills(Now()) end)
            else Log.pollPending = nil; PollKills(at) end
        end
    elseif event == "PLAYER_CONTROL_GAINED" then Land(at)
    elseif event == "TIME_PLAYED_MSG" then Log.playedLevel = Num(b)
    elseif event == "PLAYER_LOGOUT" then Tick(); PollKills(at)
    else
        PollKills(at); Dungeon(at); FillZone()
        if Log.current then Log.current.subzone = Text(Call(_G.GetSubZoneText)) end
    end
end
function Log:Initialize()
    if self.initialized then return true end
    local identity = Call(MS.JourneyCharacterIdentity.Resolve, MS.JourneyCharacterIdentity)
    local key = Text(Tab(identity).key)
    local db = MS.Database:Get()
    if not key or type(db) ~= "table" then return nil end
    db.journey = Tab(db.journey); db.journey.dayLog = Tab(db.journey.dayLog)
    self.key, self.data = key, Sanitize(db.journey.dayLog[key])
    db.journey.dayLog[key] = self.data
    TrimDays()
    self.roster, self.seenZones, self.tickAt = {}, {}, Now()
    RefreshZone(self.tickAt, nil, {})
    self.killBase, self.killAt = KillStat(), self.tickAt
    XP(self.tickAt)
    local pending = self.pending
    self.pending = nil
    local session = Tab(MS.JourneySession and MS.JourneySession.data)
    local started = pending and pending.at or self.tickAt
    local today = self.data.days[Key(self.tickAt)]
    local reload = not pending and today and today.lastAt and self.tickAt - today.lastAt <= 60
    if not reload then
        self:OnSessionEvent("SESSION_STARTED", pending and pending.detail or Text(session.zone),
            pending and pending.metadata, started)
        -- An older resumed session does not change the current zone's arrival time.
        RefreshZone(self.tickAt, nil, {})
    end
    day = DayAt(self.tickAt)
    if day and self.killBase ~= nil then day.kills = day.kills or 0 end
    Group(self.tickAt, true); Dungeon(self.tickAt)
    self.events = Call(_G.CreateFrame, "Frame")
    if self.events then
        Call(self.events.SetScript, self.events, "OnEvent", Event)
        for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "ENCOUNTER_START", "ENCOUNTER_END", "GROUP_ROSTER_UPDATE",
            "PLAYER_REGEN_ENABLED", "PLAYER_XP_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
            "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "TIME_PLAYED_MSG", "PLAYER_LOGOUT", "PLAYER_CONTROL_GAINED" }) do
            Call(self.events.RegisterEvent, self.events, event)
        end
    end
    local timer = _G.C_Timer
    if type(timer) == "table" then
        self.clock = Call(timer.NewTicker, 10, Tick)
        self.killClock = Call(timer.NewTicker, 15, function() PollKills(Now()) end)
    end
    self.initialized = true
    return true
end
function Log:Days()
    local days = {}
    for key, day in pairs(self.data and self.data.days or {}) do
        days[#days + 1] = { key = key, firstAt = day.firstAt, lastAt = day.lastAt,
            playSeconds = day.playSeconds, startLevel = day.startLevel, endLevel = day.endLevel }
    end
    table.sort(days, function(a, b) return a.key > b.key end)
    return days
end
function Log:Day(key)
    key = Text(key)
    return key and self.data and self.data.days[key] or nil
end
function Log:TodayKey() return Key(Now()) end
function Log:Current()
    local c = self.current or {}
    return { zone = c.zone, subzone = c.subzone, mapID = c.mapID, since = c.since }
end
function Log:Listen(fn) if type(fn) == "function" then listeners[#listeners + 1] = fn end end
function Log:GetStatus()
    return { initialized = self.initialized == true, characterKey = self.key, version = 1,
        days = #self:Days(), statisticID = self.statID, killsAvailable = self.killBase ~= nil,
        dungeonID = self.dungeon and self.dungeon.id }
end
