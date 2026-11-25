local MS = _G.MS

-- Dungeon entrances to draw on zone maps, read from QuestieDB when the player has installed it.
-- Journey ships none of its data. Source: ZoneDB's `dungeons`, shaped
-- [dungeonAreaID] = { name, aliases, parentAreaID, { { zoneAreaID, x, y }, ... } } with x, y in
-- percent of the zone, already in the client's frame: they are only divided by 100.
local E = { stats = {} }
MS.JourneyMapEntrances = E

-- The table is published either as a table or as Lua source: run the source as pure data.
local function Parse(source)
    if type(source) == "table" then return source end
    if type(source) ~= "string" then return nil end
    local chunk = loadstring(source)
    if not chunk then return nil end
    local env = {}
    setfenv(chunk, env)
    local done, result = pcall(chunk)
    if not done then return nil end
    if type(result) ~= "table" then
        for _, value in pairs(env) do if type(value) == "table" then result = value; break end end
    end
    return type(result) == "table" and result or nil
end

local function ByName(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.areaID < b.areaID
end

-- Rows of the shared table that are no dungeon door: transit, PvP halls, brawler pubs, the faire
-- island, an open quest zone and the battlegrounds (joined from a battlemaster).
E.NOT_DUNGEONS = {
    [2257] = true, -- Deeprun Tram
    [2917] = true, -- Hall of Legends
    [2918] = true, -- Champions' Hall
    [5733] = true, -- Molten Front
    [5861] = true, -- Darkmoon Faire Island
    [6298] = true, -- Brawl'gar Arena
    [6618] = true, -- Bizmo's Brawlpub
    [2597] = true, -- Alterac Valley
    [3277] = true, -- Warsong Gulch
    [3358] = true, -- Arathi Basin
}

-- Doors of raids; a spot shared with a dungeon (Blackrock Mountain) stays a dungeon's.
E.RAIDS = {
    [1977] = true, -- Zul'Gurub
    [2159] = true, -- Onyxia's Lair
    [2677] = true, -- Blackwing Lair
    [2717] = true, -- Molten Core
    [3428] = true, -- Temple of Ahn'Qiraj
    [3429] = true, -- Ruins of Ahn'Qiraj
    [3456] = true, -- Naxxramas
    [3457] = true, -- Karazhan
}

-- The client's own area table, when it answers: it drops areas this client does not have and
-- gives the localized name. QuestieDB keys from 10000 up are its own, not client areas.
local CLIENT_AREA_LIMIT = 10000
local function AreaNames()
    local map = _G.C_Map
    if type(map) ~= "table" or type(map.GetAreaInfo) ~= "function" then return nil end
    -- Trust it only if it knows a dungeon every client has (The Deadmines).
    local ok, probe = pcall(map.GetAreaInfo, 1581)
    if not ok or type(probe) ~= "string" or probe == "" then return nil end
    return function(areaID)
        if areaID >= CLIENT_AREA_LIMIT then return true, nil end
        local found, name = pcall(map.GetAreaInfo, areaID)
        if not found or type(name) ~= "string" or name == "" then return false end
        return true, name
    end
end

-- Several instances share one door (Blackrock Mountain, Dire Maul): one entry per spot.
local function Spot(list, areaID, name, x, y)
    for _, entry in ipairs(list) do
        if math.abs(entry.x - x) < .006 and math.abs(entry.y - y) < .006 then
            for _, known in ipairs(entry.names) do
                if known == name then return false end
            end
            entry.names[#entry.names + 1] = name
            entry.raid = entry.raid and E.RAIDS[areaID] == true
            return false
        end
    end
    list[#list + 1] = { areaID = areaID, name = name, names = { name }, x = x, y = y, raid = E.RAIDS[areaID] == true }
    return true
end

-- Index every entrance by the map it sits on, once; nothing is kept while the library is absent.
function E:Build()
    if self.byMap then return self.byMap end
    local Offers = MS.JourneyQuestieOffers
    local lib = Offers and Offers:Library()
    if not lib then self.stats.library = false; return nil end
    self.stats.library = true
    local byMap, entrances = {}, 0
    local ok, zone = pcall(lib.Support.Get, "ZoneDB")
    local dungeons = ok and type(zone) == "table" and type(zone.private) == "table" and Parse(zone.private.dungeons)
    local areaToUi = dungeons and Offers:AreaToUiMap(lib)
    local skipped = 0
    if areaToUi then
        local client = AreaNames()
        -- Fixed order, so a shared door is always titled by the same instance.
        local ids = {}
        for areaID in pairs(dungeons) do
            if type(areaID) == "number" then ids[#ids + 1] = areaID end
        end
        table.sort(ids)
        for _, areaID in ipairs(ids) do
            local row = dungeons[areaID]
            local places = type(row) == "table" and type(row[4]) == "table" and row[4]
            local known, localName = true, nil
            if client and places then known, localName = client(areaID) end
            if self.NOT_DUNGEONS[areaID] or not known then
                skipped = skipped + 1
            elseif type(row[1]) == "string" and places then
                for _, place in ipairs(places) do
                    local uiMapID = type(place) == "table" and areaToUi[place[1]]
                    if uiMapID and type(place[2]) == "number" and type(place[3]) == "number" then
                        local list = byMap[uiMapID] or {}
                        byMap[uiMapID] = list
                        if Spot(list, areaID, localName or row[1], place[2] / 100, place[3] / 100) then
                            entrances = entrances + 1
                        end
                    end
                end
            end
        end
    end
    self.stats.skipped = skipped
    for _, list in pairs(byMap) do table.sort(list, ByName) end
    self.byMap, self.cache, self.stats.entrances = byMap, {}, entrances
    local maps = 0
    for _ in pairs(byMap) do maps = maps + 1 end
    self.stats.maps = maps
    return byMap
end

-- Entrances on this map as { areaID, name, names, x, y, raid } (x, y in 0-1), sorted by name; empty without QuestieDB.
function E:ForMap(uiMapID)
    local byMap = self:Build()
    if not byMap or type(uiMapID) ~= "number" then return {} end
    local cached = self.cache[uiMapID]
    if not cached then
        cached = byMap[uiMapID] or {}
        self.cache[uiMapID] = cached
    end
    return cached
end

-- Level range of each zone (uiMapID), as published for the original game: warcraft.wiki.gg,
-- "Zones by level (Classic)". Forever does not answer C_Map.GetMapLevels, and quest levels made
-- poor ranges (Redridge read 15-60). Cities and Forever's own zones are left out.
E.ZONE_LEVELS = {
    [1426] = { 1, 10 },  -- Dun Morogh
    [1411] = { 1, 10 },  -- Durotar
    [1429] = { 1, 10 },  -- Elwynn Forest
    [1412] = { 1, 10 },  -- Mulgore
    [1438] = { 1, 10 },  -- Teldrassil
    [1420] = { 1, 10 },  -- Tirisfal Glades
    [1439] = { 10, 20 }, -- Darkshore
    [1432] = { 10, 20 }, -- Loch Modan
    [1421] = { 10, 20 }, -- Silverpine Forest
    [1436] = { 10, 20 }, -- Westfall
    [1413] = { 10, 25 }, -- The Barrens
    [1433] = { 15, 25 }, -- Redridge Mountains
    [1442] = { 15, 27 }, -- Stonetalon Mountains
    [1440] = { 18, 30 }, -- Ashenvale
    [1431] = { 18, 30 }, -- Duskwood
    [1437] = { 20, 30 }, -- Wetlands
    [1424] = { 20, 35 }, -- Hillsbrad Foothills
    [1441] = { 25, 35 }, -- Thousand Needles
    [1416] = { 30, 40 }, -- Alterac Mountains
    [1417] = { 30, 40 }, -- Arathi Highlands
    [1443] = { 30, 40 }, -- Desolace
    [1434] = { 30, 45 }, -- Stranglethorn Vale
    [1445] = { 35, 45 }, -- Dustwallow Marsh
    [1418] = { 35, 45 }, -- Badlands
    [1435] = { 35, 45 }, -- Swamp of Sorrows
    [1444] = { 40, 50 }, -- Feralas
    [1425] = { 40, 50 }, -- The Hinterlands
    [1446] = { 40, 50 }, -- Tanaris
    [1427] = { 45, 50 }, -- Searing Gorge
    [1447] = { 45, 55 }, -- Azshara
    [1419] = { 45, 55 }, -- Blasted Lands
    [1449] = { 48, 55 }, -- Un'Goro Crater
    [1448] = { 48, 55 }, -- Felwood
    [1428] = { 50, 58 }, -- Burning Steppes
    [1422] = { 51, 58 }, -- Western Plaguelands
    [1423] = { 53, 60 }, -- Eastern Plaguelands
    [1452] = { 53, 60 }, -- Winterspring
    [1430] = { 55, 60 }, -- Deadwind Pass
    [1450] = { 55, 60 }, -- Moonglade
    [1451] = { 55, 60 }, -- Silithus
}

-- Level range of the zone: the client's when it tells, else the published range.
function E.ZoneLevels(uiMapID)
    local map = _G.C_Map
    if type(map) == "table" and type(map.GetMapLevels) == "function" then
        local ok, min, max = pcall(map.GetMapLevels, uiMapID)
        if ok and type(min) == "number" and type(max) == "number" and max > 0 then return min, max end
    end
    local range = E.ZONE_LEVELS[uiMapID]
    if range then return range[1], range[2] end
    return nil
end

function E:Report()
    self:Build()
    return {
        "library=" .. tostring(self.stats.library == true),
        "entrances=" .. tostring(self.stats.entrances or 0),
        "maps=" .. tostring(self.stats.maps or 0),
        "skipped=" .. tostring(self.stats.skipped or 0),
    }
end
