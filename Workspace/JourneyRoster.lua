local MS = _G.MS
MS.JourneyRoster = { VERSION = 1, dirty = false }
local Roster = MS.JourneyRoster

local SAVE_DELAY = 5
local EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA",
    "UPDATE_PENDING_MAIL", "PLAYER_UPDATE_RESTING", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED" }

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end
local function Str(value, max)
    if type(value) == "string" and #value <= max then return value end
end
local function Int(value, min, max)
    if type(value) == "number" and value % 1 == 0 and value >= min and (not max or value <= max) then
        return value
    end
end
local function Bool(value)
    if type(value) == "boolean" then return value end
end

local function SanitizeProfessions(list)
    if type(list) ~= "table" then return nil end
    local result = {}
    for index = 1, #list do
        local entry = list[index]
        if #result >= 6 then break end
        if type(entry) == "table" and Str(entry.name, 64) then
            local clean = { name = entry.name, rank = Int(entry.rank, 0), max = Int(entry.max, 0), cooldowns = {} }
            if type(entry.cooldowns) == "table" then
                for slot = 1, #entry.cooldowns do
                    local cd = entry.cooldowns[slot]
                    if #clean.cooldowns >= 20 then break end
                    if type(cd) == "table" and Str(cd.name, 64) then
                        clean.cooldowns[#clean.cooldowns + 1] = { name = cd.name, readyAt = Int(cd.readyAt, 0) }
                    end
                end
            end
            result[#result + 1] = clean
        end
    end
    return result
end

function Roster.Sanitize(record)
    if type(record) ~= "table" then return nil end
    local name, level, seen = Str(record.name, 64), Int(record.level, 1, 80), Int(record.seen, 0)
    if not name or not level or not seen then return nil end
    return { name = name, realm = Str(record.realm, 64), class = Str(record.class, 64), level = level,
        faction = Str(record.faction, 64), zone = Str(record.zone, 80), subzone = Str(record.subzone, 80),
        money = Int(record.money, 0), rested = Int(record.rested, 0), xpMax = Int(record.xpMax, 0),
        resting = Bool(record.resting), bagFree = Int(record.bagFree, 0), bagTotal = Int(record.bagTotal, 0),
        mail = Bool(record.mail), professions = SanitizeProfessions(record.professions), seen = seen }
end

local function Store(create)
    local db = MS.Database and MS.Database.Get and MS.Database:Get()
    if type(db) ~= "table" then return nil end
    db.journey = type(db.journey) == "table" and db.journey or {}
    local store = db.journey.roster
    if type(store) ~= "table" or type(store.characters) ~= "table" then
        if not create then return nil end
        store = { version = Roster.VERSION, characters = {} }
        db.journey.roster = store
    end
    return store
end
local function Key()
    local identity = MS.JourneyCharacterIdentity and MS.JourneyCharacterIdentity:Resolve()
    return type(identity) == "table" and identity.key or nil
end

local function ReadBags(api)
    local container = api.C_Container
    if type(container) ~= "table" then return nil, nil end
    local total, free = 0, 0
    for bag = 0, 4 do
        local slots = Call(container.GetContainerNumSlots, bag)
        local empty = Call(container.GetContainerNumFreeSlots, bag)
        if type(slots) ~= "number" or type(empty) ~= "number" then return nil, nil end
        total, free = total + slots, free + empty
    end
    return free, total
end

function Roster:Capture(api, now)
    api = api or _G
    -- The class token ("MAGE"), not the localized name: it survives a change of game language.
    local okClass, _, class = pcall(api.UnitClass, "player")
    if not okClass then class = nil end
    local free, total = ReadBags(api)
    local professions = type(api.Professions) == "function" and Call(api.Professions) or nil
    return { name = Call(api.UnitName, "player"), realm = Call(api.GetRealmName), class = class,
        level = Call(api.UnitLevel, "player"), faction = Call(api.UnitFactionGroup, "player"),
        zone = Call(api.GetRealZoneText), subzone = Call(api.GetSubZoneText),
        money = Call(api.GetMoney), rested = Call(api.GetXPExhaustion),
        xpMax = Call(api.UnitXPMax, "player"), resting = Call(api.IsResting),
        bagFree = free, bagTotal = total, mail = Call(api.HasNewMail),
        professions = professions, seen = now }
end

function Roster:Save(now)
    local key = Key()
    if not key or Call(_G.InCombatLockdown) == true then self.dirty = true; return false end
    now = now or (type(time) == "function" and time() or 0)
    local record = Roster.Sanitize(self:Capture(_G, now))
    local store = record and Store(true)
    if not store then self.dirty = true; return false end
    store.characters[key] = record
    self.dirty = false
    return true
end

function Roster:List()
    local store, list, current = Store(false), {}, Key()
    for key, raw in pairs(store and store.characters or {}) do
        local record = Roster.Sanitize(raw)
        if record then record.key, record.current = key, key == current; list[#list + 1] = record end
    end
    table.sort(list, function(a, b)
        if a.current ~= b.current then return a.current end
        if a.seen ~= b.seen then return a.seen > b.seen end
        return a.key < b.key
    end)
    return list
end

function Roster:Total()
    local sum = 0
    for _, record in ipairs(self:List()) do sum = sum + (record.money or 0) end
    return sum
end

function Roster:Forget(key)
    local store = Store(false)
    if not store or key == Key() or store.characters[key] == nil then return false end
    store.characters[key] = nil
    return true
end

function Roster:MarkDirty()
    self.dirty = true
    if self.pending then return end
    local timer = _G.C_Timer
    if type(timer) == "table" and type(timer.After) == "function" then
        self.pending = true
        timer.After(SAVE_DELAY, function()
            Roster.pending = false
            if Roster.dirty then Roster:Save() end
        end)
    else
        self:Save()
    end
end

-- To be called once from the Journey startup, after MS.Database is ready.
function Roster:Start()
    if self.eventFrame then return end
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGOUT" then Roster:Save() else Roster:MarkDirty() end
    end)
    for _, event in ipairs(EVENTS) do pcall(self.eventFrame.RegisterEvent, self.eventFrame, event) end
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "PLAYER_LOGOUT")
end
