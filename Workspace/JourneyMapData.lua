local MS = _G.MS

-- Data only. No Blizzard map frame, canvas, or provider is acquired here.
MS.JourneyMapData = {}
local Data = MS.JourneyMapData

local function Call(object, method, ...)
	local fn = type(object) == "table" and object[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if ok then
		return a, b, c
	end
end

local function XY(value)
	if type(value) ~= "table" and type(value) ~= "userdata" then
		return nil
	end
	local ok, x, y = pcall(function()
		if type(value.GetXY) == "function" then
			return value:GetXY()
		end
		return value.x, value.y
	end)
	if ok and type(x) == "number" and type(y) == "number" then
		return x, y
	end
end

local function Normal(x, y)
	return type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

Data.Normal = Normal

function Data:EnsureMapAPI()
	if
		type(_G.C_Map) == "table"
		and type(C_Map.GetMapInfo) == "function"
		and type(C_Map.GetMapArtLayers) == "function"
	then
		return "READY"
	end
	if type(_G.InCombatLockdown) == "function" and InCombatLockdown() then
		return "LOAD_DEFERRED_COMBAT"
	end
	if self.moduleAttempted then
		return self.moduleResult
	end
	self.moduleAttempted = true
	local addon, name = _G.C_AddOns, "Blizzard_WorldMap"
	local verified = Call(addon, "GetAddOnInfo", name)
	if verified == nil and type(_G.GetAddOnInfo) == "function" then
		local ok, result = pcall(GetAddOnInfo, name)
		if ok then
			verified = result
		end
	end
	if verified ~= name then
		self.moduleResult = "OFFICIAL_MODULE_NOT_VERIFIED"
		return self.moduleResult
	end
	local loaded = Call(addon, "IsAddOnLoaded", name)
	if loaded == nil and type(_G.IsAddOnLoaded) == "function" then
		local ok, result = pcall(IsAddOnLoaded, name)
		if ok then
			loaded = result
		end
	end
	if loaded ~= true then
		local success = Call(addon, "LoadAddOn", name)
		if success == nil and type(_G.LoadAddOn) == "function" then
			local ok, result = pcall(LoadAddOn, name)
			success = ok and result
		end
		if success ~= true then
			self.moduleResult = "LOAD_FAILED"
			return self.moduleResult
		end
	end
	self.moduleResult = "OFFICIAL_MODULE_IN_MEMORY"
	return self.moduleResult
end

function Data:PlayerMapID()
	local id = Call(_G.C_Map, "GetBestMapForUnit", "player")
	if type(id) ~= "number" then
		id = Call(_G.C_Map, "GetMapForUnit", "player")
	end
	if type(id) ~= "number" and type(_G.GetCurrentMapAreaID) == "function" then
		local ok, legacyID = pcall(GetCurrentMapAreaID)
		if ok then
			id = legacyID
		end
	end
	return type(id) == "number" and id or nil
end

function Data:Info(mapID)
	if type(mapID) ~= "number" then
		return nil
	end
	local info = Call(_G.C_Map, "GetMapInfo", mapID)
	if type(info) ~= "table" then
		return nil
	end
	return {
		mapID = mapID,
		name = type(info.name) == "string" and info.name or tostring(mapID),
		mapType = info.mapType,
		parentMapID = info.parentMapID,
	}
end

function Data:Hierarchy(mapID)
	local chain, seen = {}, {}
	for _ = 1, 8 do
		local info = self:Info(mapID)
		if not info or seen[mapID] then
			break
		end
		seen[mapID] = true
		table.insert(chain, 1, info)
		mapID = info.parentMapID
		if type(mapID) ~= "number" or mapID == 0 then
			break
		end
	end
	return chain
end

function Data:Children(mapID)
	local raw = Call(_G.C_Map, "GetMapChildrenInfo", mapID)
	local children = {}
	if type(raw) ~= "table" then
		return children
	end
	for index = 1, math.min(#raw, 128) do
		local item = raw[index]
		if type(item) == "table" and type(item.mapID) == "number" then
			children[#children + 1] = {
				mapID = item.mapID,
				name = type(item.name) == "string" and item.name or tostring(item.mapID),
				mapType = item.mapType,
			}
		end
	end
	table.sort(children, function(a, b)
		return a.name < b.name
	end)
	return children
end

function Data:PlayerPosition(mapID)
	local value = Call(_G.C_Map, "GetPlayerMapPosition", mapID, "player")
	local x, y = XY(value)
	if Normal(x, y) then
		return x, y
	end
end

function Data:BackgroundAtlas(mapID)
	local atlas = Call(_G.C_Map, "GetMapArtBackgroundAtlas", mapID)
	return type(atlas) == "string" and atlas ~= "" and atlas or nil
end

function Data:Art(mapID)
	if type(mapID) ~= "number" then
		return nil
	end
	local artID = Call(_G.C_Map, "GetMapArtID", mapID)
	local inputs = { mapID }
	if type(artID) == "number" and artID ~= mapID then
		inputs[2] = artID
	end
	for _, input in ipairs(inputs) do
		local layers = Call(_G.C_Map, "GetMapArtLayers", input)
		if type(layers) == "table" then
			local layerCount = #layers > 0 and math.min(#layers, 8) or 1
			for layerIndex = 1, layerCount do
				local layer = #layers > 0 and layers[layerIndex] or layers
				if
					type(layer) == "table"
					and type(layer.layerWidth) == "number"
					and type(layer.layerHeight) == "number"
					and layer.layerWidth > 0
					and layer.layerHeight > 0
					and type(layer.tileWidth) == "number"
					and type(layer.tileHeight) == "number"
					and layer.tileWidth > 0
					and layer.tileHeight > 0
				then
					local columns = math.ceil(layer.layerWidth / layer.tileWidth)
					local rows = math.ceil(layer.layerHeight / layer.tileHeight)
					if columns * rows <= 128 then
						local indices = { layerIndex, 0 }
						if type(layer.layerIndex) == "number" then
							indices[3] = layer.layerIndex
						end
						for _, textureInput in ipairs(inputs) do
							for _, textureIndex in ipairs(indices) do
								local textures = Call(_G.C_Map, "GetMapArtLayerTextures", textureInput, textureIndex)
								if type(textures) == "table" and #textures >= columns * rows then
									return {
										layer = layer,
										textures = textures,
										columns = columns,
										rows = rows,
										artID = artID,
										source = "C_Map.GetMapArtLayerTextures",
									}
								end
							end
						end
					end
				end
			end
		end
	end
end

-- Resolve IDs and usable art only; translated map names are display labels.
function Data:ResolvePlayerJourneyMap()
	local rawID = self:PlayerMapID()
	local rawInfo = self:Info(rawID)
	local result = { rawPlayerMapID = rawID, rawPlayerMapName = rawInfo and rawInfo.name }
	local mapID, seen = rawID, {}
	local types = _G.Enum and Enum.UIMapType or {}
	local allowed = {}
	for _, name in ipairs({ "World", "Continent", "Zone", "Dungeon", "Micro", "Orphan" }) do
		if type(types[name]) == "number" then
			allowed[types[name]] = true
		end
	end
	for _ = 1, 16 do
		if type(mapID) ~= "number" or mapID <= 0 or seen[mapID] then
			break
		end
		seen[mapID] = true
		local info = self:Info(mapID)
		if not info then
			break
		end
		local relevant = allowed[info.mapType]
		if next(allowed) == nil then
			relevant = type(info.mapType) == "number" and info.mapType >= 1 and info.mapType <= 6
		end
		local art = relevant and self:Art(mapID)
		local usable = art ~= nil and art ~= false
		if usable then
			for i = 1, art.columns * art.rows do
				local texture = art.textures[i]
				if
					not ((type(texture) == "number" and texture > 0) or (type(texture) == "string" and texture ~= ""))
				then
					usable = false
					break
				end
			end
		end
		if usable then
			result.canonicalJourneyMapID, result.canonicalJourneyMapName = mapID, info.name
			return result
		end
		mapID = info.parentMapID
	end
	return result
end

-- Quest semantics and POI resolution are owned by JourneyQuestData.lua.

-- Reading context is a containing playable zone, independent of artwork choice.
function Data:LocalZone(mapID)
    local zoneType = type(Enum) == "table" and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local seen = {}
    for _ = 1, 16 do
        if type(mapID) ~= "number" or mapID <= 0 or seen[mapID] then return nil end
        seen[mapID] = true
        local info = self:Info(mapID)
        if not info then return nil end
        if info.mapType == zoneType then return mapID end
        mapID = info.parentMapID
    end
end

function Data:PlayerLocalZone()
    local mapID
    if type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function" then
        local ok, value = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then mapID = value end
    end
    return self:LocalZone(mapID)
end

-- The single meaning of "ici" shared by CARTE, QUÊTES and the zone card: the player's
-- containing playable zone, never a browsed map nor a micro/sub-zone map. Places without a
-- containing zone (an orphan instance, for example) fall back to the canonical Journey map.
function Data:PlayerZone()
    local zone = self:LocalZone(self:PlayerMapID())
    if zone then return zone end
    return self:ResolvePlayerJourneyMap().canonicalJourneyMapID
end

-- Read-only: the zone a displayed map belongs to for "ici" purposes.
function Data:RelationZone(mapID)
    return self:LocalZone(mapID) or mapID
end
