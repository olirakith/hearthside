local MS = _G.MS
MS.Active = MS.Active or {}
-- The player's place, read fresh each time and never stored passively. Every value goes through
-- the secret-value filter; anything unreadable stays nil ("unknown"), never a default.
local A = MS.Active
local P = { settleSeconds = 8 }
A.Position = P

local function XY(position)
    if type(position) ~= "table" then return nil end
    if type(position.GetXY) == "function" then return A.Call(position.GetXY, position) end
    return A.Readable(position.x), A.Readable(position.y)
end

local function Finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end

-- Login and loading screens can report a stale or continent map for several seconds (observed
-- on 70450): nothing is sealed or opened until the window has passed.
function P:OnEnteringWorld()
    self.settleUntil = A.Uptime() + self.settleSeconds
end

function P:Settled()
    return A.Uptime() >= (self.settleUntil or 0)
end

-- Best map only (cheap): used to know whether a full sample is worth taking.
function P:MapID()
    local map = _G.C_Map
    if type(map) ~= "table" then return nil end
    local mapID = A.Call(map.GetBestMapForUnit, "player")
    return Finite(mapID) and mapID or nil
end

-- { mapID, mapType, x, y, width, height, indoors, instance, combat, dead, taxi, settled }
function P:Sample()
    local map = type(_G.C_Map) == "table" and _G.C_Map or {}
    local sample = { settled = self:Settled() }
    sample.mapID = self:MapID()
    if sample.mapID then
        local info = A.Call(map.GetMapInfo, sample.mapID)
        sample.mapType = type(info) == "table" and A.Readable(info.mapType) or nil
        local x, y = XY(A.Call(map.GetPlayerMapPosition, sample.mapID, "player"))
        if Finite(x) and Finite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 and not (x == 0 and y == 0) then
            sample.x, sample.y = x, y
        end
        local width, height = A.Call(map.GetMapWorldSize, sample.mapID)
        if Finite(width) and Finite(height) and width > 0 and height > 0 then sample.width, sample.height = width, height end
    end
    sample.indoors = A.Bool(A.Call(_G.IsIndoors))
    sample.instance = A.Bool(A.Call(_G.IsInInstance))
    sample.combat = A.Bool(A.Call(_G.InCombatLockdown))
    sample.dead = A.Bool(A.Call(_G.UnitIsDeadOrGhost, "player"))
    sample.taxi = A.Bool(A.Call(_G.UnitOnTaxi, "player"))
    -- Evidence: a readable position and world size on a zone map prove these on this build.
    if sample.x and sample.mapType == 3 then A:Prove("MapPosition", "POSITION_READ") end
    if sample.width then A:Prove("MapDistance", "WORLD_SIZE_READ") end
    return sample
end

-- The zone's display name, in the reader's own language (nil when the game does not say).
function P:MapName(mapID)
    local map = _G.C_Map
    if type(map) ~= "table" or not Finite(mapID) then return nil end
    local info = A.Call(map.GetMapInfo, mapID)
    local name = type(info) == "table" and A.Readable(info.name) or nil
    return type(name) == "string" and name ~= "" and MS.Active.Text.CleanLine(name, 64) or nil
end

A:Register("Position", P)

-- /aj sonde: one copyable live report of every capability the active experiences depend on. Measures, never
-- stores: no names, no coordinates beyond this screen.
local Probe = {}
A.Probe = Probe

local function Show(value)
    if value == nil then return "nil" end
    return tostring(value)
end

-- Passive session watcher: created by the first Probe:Lines() only, never persisted.
local LIST_CAP = 40
local watch = { casts = {}, auras = {}, castSeen = {}, auraSeen = {}, castUnreadable = 0, auraUnreadable = 0 }

local function AddId(list, seen, id)
    if seen[id] or #list >= LIST_CAP then return end
    seen[id] = true
    list[#list + 1] = id
end

local function ScanAuras()
    local auras = type(_G.C_UnitAuras) == "table" and _G.C_UnitAuras or nil
    if not auras or type(auras.GetAuraDataByIndex) ~= "function" then return end
    local now = A.Uptime()
    if watch.lastScan and now - watch.lastScan < 1 then return end
    watch.lastScan = now
    for index = 1, 40 do
        -- Not A.Call: a refused or secret read must count as unreadable, not as the end of the list.
        local ok, data = pcall(auras.GetAuraDataByIndex, "player", index, "HELPFUL")
        if not ok then
            watch.auraUnreadable = watch.auraUnreadable + 1
            break
        end
        if data == nil then break end
        data = A.Readable(data)
        local id = type(data) == "table" and A.Readable(data.spellId) or nil
        if type(id) == "number" then
            AddId(watch.auras, watch.auraSeen, id)
            A:Prove("AuraRead", "PROBE_AURA")
        else
            watch.auraUnreadable = watch.auraUnreadable + 1
        end
    end
end

local function OnWatchEvent(_, event, unit, _, spellID)
    if A.Readable(unit) ~= "player" then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local id = A.Readable(spellID)
        if type(id) == "number" then
            AddId(watch.casts, watch.castSeen, id)
            A:Prove("SpellCast", "PROBE_SPELLCAST")
        else
            watch.castUnreadable = watch.castUnreadable + 1
        end
    elseif event == "UNIT_AURA" then
        ScanAuras()
    end
end

local function StartWatch()
    if watch.frame or type(_G.CreateFrame) ~= "function" then return end
    local ok, frame = pcall(_G.CreateFrame, "Frame")
    if not ok or type(frame) ~= "table" then return end
    watch.frame = frame
    frame:SetScript("OnEvent", OnWatchEvent)
    for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_AURA" }) do
        local registered = type(frame.RegisterUnitEvent) == "function" and pcall(frame.RegisterUnitEvent, frame, event, "player")
        if not registered then pcall(frame.RegisterEvent, frame, event) end
    end
end

local function IdList(list) return #list > 0 and table.concat(list, ",") or "-" end

function Probe:Lines()
    StartWatch()
    local lines = {}
    for _, line in ipairs(A:ExportHeader()) do lines[#lines + 1] = line end
    local sample = P:Sample()
    lines[#lines + 1] = string.format("sample settled=%s map=%s mapType=%s position=%s worldSize=%s indoors=%s instance=%s",
        Show(sample.settled), Show(sample.mapID), Show(sample.mapType), Show(sample.x ~= nil), Show(sample.width ~= nil),
        Show(sample.indoors), Show(sample.instance))
    if sample.width then lines[#lines + 1] = string.format("worldSize %.0fx%.0f yd", sample.width, sample.height) end
    lines[#lines + 1] = string.format("player combat=%s dead=%s taxi=%s mounted=%s inGroup=%s level=%s xp=%s",
        Show(sample.combat), Show(sample.dead), Show(sample.taxi), Show(A.Bool(A.Call(_G.IsMounted))),
        Show(A.Bool(A.Call(_G.IsInGroup))), Show(A.Call(_G.UnitLevel, "player")), Show(A.Call(_G.UnitXP, "player")))
    local instanceName, instanceType = A.Call(_G.GetInstanceInfo)
    lines[#lines + 1] = string.format("instanceInfo type=%s named=%s", Show(instanceType), Show(type(instanceName) == "string"))
    lines[#lines + 1] = string.format("time server=%s uptime=%s secretApi=%s", Show(A.Call(_G.GetServerTime)), Show(A.Uptime() > 0),
        Show(type(_G.canaccessvalue) == "function"))
    -- Calibration: a state the player is really in (dead, on a flight, mounted, grouped), read back
    -- positively by the game, proves that capability on this build. Nothing is proven by a "no".
    local proven = {}
    local function Prove(name, code) if A:Prove(name, code) then proven[#proven + 1] = name end end
    if sample.dead == true then Prove("PlayerDeath", "PROBE_DEAD") end
    if sample.taxi == true then Prove("Taxi", "PROBE_TAXI") end
    if A.Bool(A.Call(_G.IsMounted)) == true then Prove("Mount", "PROBE_MOUNTED") end
    if sample.x and sample.mapType == 3 then Prove("MapPosition", "PROBE_POSITION") end
    local members = A.Call(_G.GetNumSubgroupMembers) or 0
    for index = 1, math.min(type(members) == "number" and members or 0, 4) do
        local unit = "party" .. index
        local guid, dead = A.Call(_G.UnitGUID, unit), A.Bool(A.Call(_G.UnitIsDeadOrGhost, unit))
        local feign
        if type(_G.UnitIsFeignDeath) == "function" then feign = A.Bool(A.Call(_G.UnitIsFeignDeath, unit)) end
        lines[#lines + 1] = string.format("%s exists=%s connected=%s guid=%s dead=%s feign=%s", unit,
            Show(A.Bool(A.Call(_G.UnitExists, unit))), Show(A.Bool(A.Call(_G.UnitIsConnected, unit))),
            Show(guid ~= nil), Show(dead), Show(feign))
        if guid ~= nil and A.Bool(A.Call(_G.IsInGroup)) == true then Prove("GroupRoster", "PROBE_ROSTER") end
        if dead == true and feign == false then Prove("PartyDeath", "PROBE_PARTY_DEAD") end
    end
    lines[#lines + 1] = string.format("casts ids=%s unreadable=%d", IdList(watch.casts), watch.castUnreadable)
    lines[#lines + 1] = string.format("auras ids=%s unreadable=%d", IdList(watch.auras), watch.auraUnreadable)
    lines[#lines + 1] = "proven now " .. (#proven > 0 and table.concat(proven, ",") or "-")
    lines[#lines + 1] = "caps " .. A.Capabilities:Text(A.caps)
    lines[#lines + 1] = "END"
    return lines
end
