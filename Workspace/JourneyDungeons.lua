local MS = _G.MS

-- Which dungeon or raid the player is in, and what Journey knows of it. The client has no map for
-- them, but still carries the art of most plans: 12 tiles a floor, loaded by path. No art is shipped.
MS.JourneyDungeons = {}
local D = MS.JourneyDungeons

-- By instance ID. areas: its area IDs, the one quests are filed under included. zone: the map its entrance is on. folder/base: the art, base defaulting to folder.
-- names: locale keys of the floors when they are wings rather than storeys.
D.list = {
    [33] = { areas = { 209 }, zone = 1421, folder = "ShadowfangKeep", floors = 7 },
    [34] = { areas = { 717 }, zone = 1453, folder = "TheStockade", floors = 1 },
    [36] = { areas = { 1581 }, zone = 1436, folder = "TheDeadmines", floors = 2 },
    [43] = { areas = { 718 }, zone = 1413, folder = "WailingCaverns", floors = 1 },
    [47] = { areas = { 491, 1717 }, zone = 1413, folder = "RazorfenKraul", floors = 1 },
    [48] = { areas = { 719 }, zone = 1440, folder = "BlackfathomDeeps", floors = 3 },
    [70] = { areas = { 1337, 1517 }, zone = 1418, folder = "Uldaman", floors = 2 },
    [90] = { areas = { 721, 133 }, zone = 1426, folder = "Gnomeregan", floors = 4 },
    [109] = { areas = { 1477, 1417 }, zone = 1435, folder = "TheTempleOfAtalHakkar", floors = 1 },
    [129] = { areas = { 722 }, zone = 1413, folder = "RazorfenDowns", floors = 1 },
    [189] = { areas = { 796 }, zone = 1420, folder = "ScarletMonastery", floors = 4, names = { "JOURNEY_DUNGEON_SM_GRAVEYARD",
        "JOURNEY_DUNGEON_SM_LIBRARY", "JOURNEY_DUNGEON_SM_ARMORY", "JOURNEY_DUNGEON_SM_CATHEDRAL" } },
    [209] = { areas = { 1176, 978 }, zone = 1446 }, -- Zul'Farrak: the client has no plan of it
    [229] = { areas = { 1583, 17804 }, zone = 1428, folder = "BlackrockSpire", floors = 7 },
    [230] = { areas = { 1584, 1585, 17803 }, zone = 1428, folder = "BlackrockDepths", floors = 2 },
    [249] = { areas = { 2159 }, zone = 1445, folder = "OnyxiasLair", floors = 1 },
    [289] = { areas = { 2057 }, zone = 1422, folder = "ScholomanceOld", floors = 4 },
    [309] = { areas = { 1977 }, zone = 1434 }, -- Zul'Gurub
    [329] = { areas = { 2017 }, zone = 1423, folder = "Stratholme", floors = 2 },
    [349] = { areas = { 2100 }, zone = 1443, folder = "Maraudon", floors = 2 },
    [389] = { areas = { 2437 }, zone = 1454, folder = "Ragefire", floors = 1 },
    [409] = { areas = { 2717 }, zone = 1428, folder = "MoltenCore", floors = 1 },
    [429] = { areas = { 2557 }, zone = 1444, folder = "DireMaul", floors = 6 },
    [469] = { areas = { 2677 }, zone = 1428, folder = "BlackwingLair", floors = 4 },
    [509] = { areas = { 3429 }, zone = 1451 }, -- Ruins of Ahn'Qiraj
    [531] = { areas = { 3428, 16076 }, zone = 1451, folder = "AhnQiraj", floors = 3 },
    [533] = { areas = { 3456 }, zone = 1423, folder = "Naxxramas", floors = 6 },
    -- Forever's own: no plan in the client.
    [2959] = { areas = { 16544, 16560 }, zone = 1416 }, -- City of Dalaran
    [2994] = { areas = { 16620 }, zone = 1445 }, -- Alcaz Prison
    [2998] = { areas = { 16732 }, zone = 1437 }, -- Excavation Site
    [2999] = { areas = { 16611 }, zone = 1458 }, -- Ruins of Lordaeron
    [3065] = { areas = { 16919 }, zone = 1455 }, -- Hall of Thanes
    [2970] = { areas = { 16550 } }, -- The Drowned City
    [2974] = { areas = { 16554 } }, -- Blackmaw Hold
    [3001] = { areas = { 16667 } }, -- The Shaper's Terrace
    [3039] = { areas = { 16842 } }, -- Krol'dok Stronghold
}

-- Doors QuestieDB numbers apart: Stratholme's gauntlet, Dire Maul's wings.
D.doors = { [10001] = 329, [10022] = 429, [10023] = 429, [10024] = 429, [10025] = 429, [10026] = 429, [10027] = 429 }

D.ART = "Interface\\WorldMap\\%s\\%s%d_%d"
D.TILES, D.COLUMNS, D.ROWS, D.TILE, D.WIDTH, D.HEIGHT = 12, 4, 3, 256, 1002, 668
local KINDS = { party = true, raid = true }

local function NativeMap()
    local types = _G.Enum and Enum.UIMapType
    local info = MS.JourneyMapData:Info(MS.JourneyMapData:PlayerMapID())
    return info ~= nil and types ~= nil and info.mapType == types.Dungeon
end

-- { id, name, raid, areas, zone, folder, base, floors, names } inside a dungeon or a raid, else nil. Nil too
-- if the client ever gives the player a map of it: that one is better than a plan.
function D:Current()
    if type(_G.GetInstanceInfo) ~= "function" then return nil end
    local ok, name, kind, _, _, _, _, _, id = pcall(GetInstanceInfo)
    if not ok or not KINDS[kind] or type(id) ~= "number" or NativeMap() then return nil end
    local dungeon = self:Describe(id, type(name) == "string" and name or "")
    dungeon.raid = kind == "raid"
    return dungeon
end

function D:Describe(id, name)
    local known = self.list[id] or {}
    return { id = id, name = name, areas = known.areas, zone = known.zone, folder = known.folder,
        base = known.base or known.folder, floors = known.floors or 0, names = known.names }
end

-- The dungeon behind a door of the map, by the area of its entrance; nil for an unknown place.
function D:ByArea(areaID, name)
    if not self.byArea then
        self.byArea = {}
        for id, known in pairs(self.list) do
            for _, area in ipairs(known.areas) do self.byArea[area] = id end
        end
        for area, id in pairs(self.doors) do self.byArea[area] = id end
    end
    local id = self.byArea[areaID]
    if not id then return nil end
    local map, ok, own = _G.C_Map, false, nil
    if type(map) == "table" and type(map.GetAreaInfo) == "function" then ok, own = pcall(map.GetAreaInfo, self.list[id].areas[1]) end
    return self:Describe(id, ok and type(own) == "string" and own ~= "" and own or name or "")
end

-- The dungeons behind an entrance of JourneyMapEntrances, each once.
function D:Behind(entry)
    local list, seen, areas = {}, {}, entry.areas or { entry.areaID }
    local paired = entry.names and #entry.names == #areas -- two wings may share one name
    for index, areaID in ipairs(areas) do
        local dungeon = self:ByArea(areaID, paired and entry.names[index] or entry.name)
        if dungeon and not seen[dungeon.id] then
            seen[dungeon.id] = true
            list[#list + 1] = dungeon
        end
    end
    return list
end

function D:Tile(dungeon, floor, index)
    return self.ART:format(dungeon.folder, dungeon.base, floor, index)
end

function D:FloorName(dungeon, floor)
    local key = dungeon.names and dungeon.names[floor]
    return key and MS.L[key] or MS.L.JOURNEY_DUNGEON_FLOOR:format(floor)
end

-- Whether the client really has this plan: a missing file has no file ID.
function D:HasArt(dungeon, probe)
    if not dungeon.folder or dungeon.floors < 1 then return false end
    probe:SetTexture(self:Tile(dungeon, 1, 1))
    if type(probe.GetTextureFileID) ~= "function" then return true end
    local id = probe:GetTextureFileID()
    return type(id) == "number" and id > 0
end
