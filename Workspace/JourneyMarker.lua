local MS = _G.MS
MS.JourneyMarker = { VERSION = 1, listeners = {} }
local Marker = MS.JourneyMarker

local function Num(value)
    if type(value) == "number" and value == value then return value end
end
local function Sanitize(raw)
    if type(raw) ~= "table" then return nil end
    local mapID, x, y, placed = Num(raw.mapID), Num(raw.x), Num(raw.y), Num(raw.placed)
    if not mapID or mapID < 1 or mapID % 1 ~= 0 then return nil end
    if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    if placed and placed < 0 then placed = nil end
    return { mapID = mapID, x = x, y = y, placed = placed or 0 }
end

local function Store(create)
    local db = MS.Database and MS.Database.Get and MS.Database:Get()
    if type(db) ~= "table" then return nil end
    if type(db.journey) ~= "table" then
        if not create then return nil end
        db.journey = {}
    end
    local store = db.journey.marker
    if type(store) ~= "table" or type(store.characters) ~= "table" then
        if not create then return nil end
        store = { version = Marker.VERSION, characters = {} }
        db.journey.marker = store
    end
    return store
end
local function Key()
    local identity = MS.JourneyCharacterIdentity and MS.JourneyCharacterIdentity:Resolve()
    return type(identity) == "table" and type(identity.key) == "string" and identity.key or nil
end

local function Notify()
    for index = 1, #Marker.listeners do
        pcall(Marker.listeners[index])
    end
end

function Marker:Set(mapID, x, y, now)
    local clean = Sanitize({ mapID = mapID, x = x, y = y, placed = type(now) == "number" and now or 0 })
    local key = Key()
    local store = clean and key and Store(true)
    if not store then return false end
    store.characters[key] = clean
    Notify()
    return true
end

function Marker:Get()
    local key, store = Key(), Store(false)
    local clean = key and store and Sanitize(store.characters[key])
    return clean or nil
end

function Marker:Clear()
    local key, store = Key(), Store(false)
    if not key or not store or store.characters[key] == nil then return false end
    store.characters[key] = nil
    Notify()
    return true
end

function Marker:IsOn(mapID)
    local marker = self:Get()
    return marker ~= nil and marker.mapID == mapID
end

function Marker:Listen(callback)
    if type(callback) ~= "function" then return false end
    self.listeners[#self.listeners + 1] = callback
    return true
end
