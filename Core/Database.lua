local MS = _G.MS

MS.Database = {}

function MS.Database:Initialize()
    if type(MultiScreenForeverDB) ~= "table" then MultiScreenForeverDB = {} end
    local db = MultiScreenForeverDB
    if type(db.schemaVersion) ~= "number" or db.schemaVersion < 1 then
        -- Contains product preferences/session only; no geometry is migrated.
        db.schemaVersion = 1
        db.workspace = type(db.workspace) == "table" and db.workspace or {}
        db.journey = type(db.journey) == "table" and db.journey or {}
    end
    if db.schemaVersion < 2 then
        db.journeyMap = type(db.journeyMap) == "table" and db.journeyMap or {}
        db.schemaVersion = 2
    end
    db.workspace = type(db.workspace) == "table" and db.workspace or {}
    db.journey = type(db.journey) == "table" and db.journey or {}
    db.journeyMap = type(db.journeyMap) == "table" and db.journeyMap or {}
    -- Journey seed knowledge only. Existing named Blizzard profiles are never
    -- adopted or migrated into a seed baseline by database initialization.
    db.editModeProfiles = type(db.editModeProfiles) == "table" and db.editModeProfiles
        or { schemaVersion = 1 }
    self.data = db
    if MS.JourneySettings then MS.JourneySettings:Initialize(db) end
    if MS.JourneyMemory then MS.JourneyMemory:Initialize(db) end
    if MS.JourneyInventoryData then MS.JourneyInventoryData:Bind(db) end
    return db
end

function MS.Database:Get()
    return self.data or self:Initialize()
end
