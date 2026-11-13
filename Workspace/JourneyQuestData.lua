local MS = _G.MS
local MapData = MS.JourneyMapData

MS.JourneyQuestData = { mapNames = {}, mapNamesKey = nil, indexDirty = true }
local QuestData = MS.JourneyQuestData

local function ValidID(value)
	return type(value) == "number" and value > 0
end

local function Normal(x, y)
	return MapData.Normal(x, y)
end

local function XY(item)
	if type(item) ~= "table" and type(item) ~= "userdata" then
		return nil
	end
	local ok, x, y = pcall(function()
		if type(item.GetXY) == "function" then
			return item:GetXY()
		end
		return item.x, item.y
	end)
	if ok and Normal(x, y) then
		return x, y
	end
end

local function Position(item)
	if type(item) ~= "table" then
		return nil
	end
	if Normal(item.x, item.y) then
		return item.x, item.y
	end
	return XY(item.position or item.pos)
end

local function Shape(a, b, c)
	if type(a) ~= "table" then
		return type(a) .. "," .. type(b) .. "," .. type(c)
	end
	local keys, visited = {}, 0
	for key, value in pairs(a) do
		visited = visited + 1
		if visited > 16 then
			break
		end
		keys[#keys + 1] = tostring(key) .. ":" .. type(value)
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

local function EntryShape(entry)
	if type(entry) ~= "table" then
		return type(entry) .. ":" .. string.sub(tostring(entry), 1, 32)
	end
	local values = {}
	for key, value in pairs(entry) do
		if #values >= 16 then
			break
		end
		local primitive = type(value) == "number" or type(value) == "string" or type(value) == "boolean"
		values[#values + 1] = tostring(key) .. "=" .. (primitive and string.sub(tostring(value), 1, 24) or type(value))
	end
	table.sort(values)
	return "table:" .. table.concat(values, ",")
end

local function Call(diagnostic, namespace, method, ...)
	local object = _G[namespace]
	local fn = type(object) == "table" and object[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		if #diagnostic.errors < 8 then
			diagnostic.errors[#diagnostic.errors + 1] = namespace
				.. "."
				.. method
				.. ":"
				.. string.sub(tostring(a), 1, 100)
		end
		return nil
	end
	if diagnostic.shapes[method] == nil or (a ~= nil and string.sub(diagnostic.shapes[method], 1, 4) == "nil,") then
		local shapeOK, shape = pcall(Shape, a, b, c)
		diagnostic.shapes[method] = shapeOK and shape or "SHAPE_ERROR"
	end
	return a, b, c
end

local function Normalize(value)
	if type(value) ~= "string" then
		return nil
	end
	local text = value
	for from, to in pairs({
		["à"] = "a",
		["â"] = "a",
		["ä"] = "a",
		["À"] = "a",
		["Â"] = "a",
		["é"] = "e",
		["è"] = "e",
		["ê"] = "e",
		["ë"] = "e",
		["É"] = "e",
		["È"] = "e",
		["Ê"] = "e",
		["î"] = "i",
		["ï"] = "i",
		["Î"] = "i",
		["ô"] = "o",
		["ö"] = "o",
		["Ô"] = "o",
		["ù"] = "u",
		["û"] = "u",
		["ü"] = "u",
		["Ù"] = "u",
		["ç"] = "c",
		["Ç"] = "c",
	}) do
		text = string.gsub(text, from, to)
	end
	text = string.lower(text):gsub("[^%w]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return text ~= "" and text or nil
end

function QuestData:MapNameIndex(displayMapID)
	local candidates, key = self:Candidates(displayMapID)
	if self.mapNamesKey == key then
		return self.mapNames
	end
	local names = {}
	for _, info in ipairs(candidates) do
		local label = Normalize(info.name)
		if label then
			if names[label] and names[label] ~= info.mapID then
				names[label] = false
			elseif names[label] ~= false then
				names[label] = info.mapID
			end
		end
	end
	self.mapNames, self.mapNamesKey = names, key
	return names
end

local function Progress(objectives, taskPercent)
	local result = { completedObjectives = 0, totalObjectives = 0, objectives = {} }
	if type(objectives) == "table" then
		for index = 1, math.min(#objectives, 16) do
			local raw = objectives[index]
			if type(raw) == "table" then
				local text = type(raw.text) == "string" and raw.text or ""
				local current = type(raw.numFulfilled) == "number" and raw.numFulfilled
					or type(raw.current) == "number" and raw.current
					or nil
				local required = type(raw.numRequired) == "number" and raw.numRequired
					or type(raw.required) == "number" and raw.required
					or nil
				if not current or not required then
					local a, b = string.match(text, "(%d+)%s*/%s*(%d+)")
					if a and b then
						current, required = tonumber(a), tonumber(b)
					end
				end
				local finished = raw.finished == true
					or raw.finished == 1
					or (
						type(current) == "number"
						and type(required) == "number"
						and required > 0
						and current >= required
					)
				local objective = {
					text = text,
					type = raw.type,
					current = current,
					required = required,
					finished = finished == true,
				}
				if type(current) == "number" and type(required) == "number" and required > 0 then
					objective.percent = math.max(0, math.min(100, current / required * 100))
				else
					local supplied = type(raw.progressBarPercent) == "number" and raw.progressBarPercent
						or type(raw.progress) == "number" and raw.progress
						or nil
					if type(supplied) == "number" and supplied >= 0 and supplied <= 100 then
						objective.percent = supplied
					end
				end
				result.objectives[#result.objectives + 1] = objective
				if objective.finished then
					result.completedObjectives = result.completedObjectives + 1
				end
			end
		end
	end
	result.totalObjectives = #result.objectives
	if type(taskPercent) == "number" and taskPercent >= 0 and taskPercent <= 100 then
		result.percent, result.percentSource = taskPercent, "C_TaskQuest.GetQuestProgressBarInfo"
	elseif result.totalObjectives == 1 and type(result.objectives[1].percent) == "number" then
		result.percent, result.percentSource = result.objectives[1].percent, "OBJECTIVE_VALUE"
	elseif result.totalObjectives > 0 then
		local sameType, allNumeric, currentTotal, requiredTotal = true, true, 0, 0
		local firstType = result.objectives[1].type
		for _, objective in ipairs(result.objectives) do
			if objective.type ~= firstType then
				sameType = false
			end
			if
				type(objective.current) ~= "number"
				or type(objective.required) ~= "number"
				or objective.required <= 0
			then
				allNumeric = false
			else
				currentTotal = currentTotal + math.min(objective.current, objective.required)
				requiredTotal = requiredTotal + objective.required
			end
		end
		if allNumeric and (result.totalObjectives == 1 or (sameType and firstType ~= nil)) then
			result.currentTotal, result.requiredTotal = currentTotal, requiredTotal
			result.percent = currentTotal / requiredTotal * 100
			result.percentSource = "OBJECTIVE_COUNTS"
		end
	end
	return result
end

local function IsTurnIn(item)
	if type(item) ~= "table" then
		return false
	end
	if item.isTurnIn == true or item.turnIn == true then
		return true
	end
	local kind = type(item.poiType) == "string" and item.poiType or type(item.type) == "string" and item.type or ""
	return string.find(string.lower(kind), "turn", 1, true) ~= nil
end

local function IsGiver(item)
	if type(item) ~= "table" then
		return false
	end
	if item.isGiver == true or item.giver == true or item.isQuestStart == true then
		return true
	end
	local kind = type(item.poiType) == "string" and item.poiType or type(item.type) == "string" and item.type or ""
	return string.find(string.lower(kind), "giver", 1, true) ~= nil
end

function QuestData:Invalidate(reason)
	self.indexDirty = true
	self.invalidateReason = reason or "QUEST_LOG_UPDATE"
end

-- One pending callback shared by Journal and Map event listeners. Navigation
-- consumes dirty data synchronously; the callback then skips already fresh views.
function QuestData:ScheduleRefresh(reason)
    local journey = MS.JourneyWorkspace
    if self.indexing or not journey or not journey.active then return end
    self:Invalidate(reason)
    MS.QuestJournal:Invalidate()
    MS.MapView.dirty = true
    if self.refreshTicket then
        self.coalescedCount = (self.coalescedCount or 0) + 1
        return
    end
    local ticket = {}
    self.refreshTicket = ticket
    local function Flush()
        if self.refreshTicket ~= ticket then return end
        self.refreshTicket = nil
        if not journey.active then return end
        local journal, map = MS.QuestJournal, MS.MapView
        -- This snapshot lives only for the semantic batch. Explicit navigation
        -- outside the callback still reads immediately, without a stale cache.
        self.flushSnapshot = { description = journal.visible == true or map.active == true }
        local ok, err = pcall(function()
            if map.active and map.dirty then map:RefreshQuests() end
            if not self.flushSnapshot.quests and MS.JourneySession and MS.JourneySession.active and MS.JourneySession.ObserveQuests then
                -- Session completion uses objectives even with both pages hidden.
                self:ReadLog({ errors = {}, shapes = {} }, { description = false })
            end
            if journal.active and journal.dirty then
                if journal.visible then journal:Refresh() else journal:RefreshCounts() end
            end
        end)
        self.flushSnapshot = nil
        if not ok then error(err) end
    end
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, Flush)
    else Flush() end
end

function QuestData:Candidates(displayMapID)
	local playerMapID = MapData:PlayerMapID()
	local key = tostring(playerMapID) .. ":" .. tostring(displayMapID)
	if self.candidateKey == key then
		return self.candidates, key
	end
	local candidates, seen = {}, {}
	local function Add(mapID)
		if not ValidID(mapID) or seen[mapID] or #candidates >= 128 then
			return
		end
		local info = MapData:Info(mapID)
		if not info then
			return
		end
		seen[mapID] = true
		candidates[#candidates + 1] = info
	end
	Add(displayMapID) -- The visible map must also get the bounded legacy complement.
	local playerChain = MapData:Hierarchy(playerMapID)
	local displayChain = MapData:Hierarchy(displayMapID)
	for _, info in ipairs(playerChain) do
		Add(info.mapID)
	end
	for _, info in ipairs(displayChain) do
		Add(info.mapID)
	end
	local zoneType = _G.Enum and Enum.UIMapType and Enum.UIMapType.Zone
	local function Children(parentID)
		local raw = MapData:Children(parentID)
		for _, child in ipairs(raw) do
			Add(child.mapID)
		end
	end
	-- The player's continent is first; the rest of the hierarchy is only sampled within the cap.
	for index = #playerChain, 1, -1 do
		Children(playerChain[index].mapID)
	end
	for index = #displayChain, 1, -1 do
		Children(displayChain[index].mapID)
	end
	local cursor = 1
	while cursor <= #candidates and #candidates < 128 do
		local info = candidates[cursor]
		cursor = cursor + 1
		if not zoneType or info.mapType ~= zoneType then
			Children(info.mapID)
		end
	end
	self.candidates, self.candidateKey = candidates, key
	return candidates, key
end

function QuestData:BuildIndex(byID, displayMapID, diagnostic, visibleEntries)
	local candidates, key = self:Candidates(displayMapID)
	if not self.indexDirty and self.index and self.index.candidateKey == key then
		return self.index
	end
	local index = {
		candidateKey = key,
		byQuest = {},
		byMap = {},
		mapsScanned = 0,
		questMatches = 0,
		coordinateMatches = 0,
		status = "READY",
		lastBuildReason = self.invalidateReason or "MAP_CHANGED",
		poiStateRestored = true,
		originalPoiMap = nil,
		restoredPoiMap = nil,
		lastError = "none",
		legacyMapsScanned = 0,
		iconCalls = 0,
		legacyShape = "UNAVAILABLE",
		iconShape = "UNAVAILABLE",
		mapListShape = "UNAVAILABLE",
		legacyEntryShape = "UNAVAILABLE",
		legacyEntries = {},
		iconReturnShape = "UNAVAILABLE",
	}
	local function Match(questID, mapID, x, y, source, role)
		if not ValidID(mapID) or not ValidID(questID) then
			return
		end
		if not byID[questID] then
			return
		end
		local list = index.byQuest[questID]
		if not list then
			list = {}
			index.byQuest[questID] = list
		end
		if #list >= 16 then
			return
		end
		for _, old in ipairs(list) do
			if
				old.mapID == mapID
				and old.source == source
				and old.role == role
				and (not Normal(x, y) or (old.x == x and old.y == y))
			then
				if not old.x and Normal(x, y) then
					old.x, old.y = x, y
					index.coordinateMatches = index.coordinateMatches + 1
				end
				return
			end
		end
		list[#list + 1] = {
			mapID = mapID,
			x = Normal(x, y) and x or nil,
			y = Normal(x, y) and y or nil,
			source = source,
			role = role,
		}
		index.questMatches = index.questMatches + 1
		if Normal(x, y) then
			index.coordinateMatches = index.coordinateMatches + 1
		end
		index.byMap[mapID] = index.byMap[mapID] or {}
		index.byMap[mapID][questID] = true
	end
	local function Role(item)
		if IsTurnIn(item) then
			return "TURN_IN"
		end
		if IsGiver(item) then
			return "GIVER"
		end
		return "UNCLASSIFIED"
	end
	local poiAPI = type(_G.C_QuestLog) == "table" and C_QuestLog or nil
	local getPoiMap = poiAPI and poiAPI.GetMapForQuestPOIs
	local setPoiMap = poiAPI and poiAPI.SetMapForQuestPOIs
	local original = type(getPoiMap) == "function" and Call(diagnostic, "C_QuestLog", "GetMapForQuestPOIs") or nil
	index.originalPoiMap = original
	local inCombat = type(_G.InCombatLockdown) == "function" and InCombatLockdown()
	local maySet = ValidID(original) and type(setPoiMap) == "function" and not inCombat
	if inCombat then
		index.status = "LIMITED_COMBAT"
	end
	if not maySet and not inCombat then
		index.status = "POI_READ_ONLY_NO_RESTORABLE_ORIGINAL"
	end
	local updateIcons = _G.QuestPOIUpdateIcons
	index.legacyUpdateAvailable = type(updateIcons) == "function"
	local function UpdateIcons()
		if not index.legacyUpdateAvailable then
			return true
		end
		local ok, err = pcall(updateIcons)
		if not ok or err == false then
			index.lastError = "QuestPOIUpdateIcons:" .. string.sub(tostring(err), 1, 100)
			return false
		end
		return true
	end
	local function SnapshotIcon(questID)
		local ok, completed, x, y, objective = pcall(_G.QuestPOIGetIconInfo, questID)
		if not Normal(x, y) then
			if Normal(completed, x) then
				x, y = completed, x
			else
				x, y = nil, nil
			end
		end
		return { ok = ok, completed = completed, x = x, y = y, objective = objective }
	end
	local function SelectPoiMap(mapID, probeQuestID)
		local ok, err = pcall(setPoiMap, mapID)
		local probe
		if ok and err ~= false and probeQuestID then
			-- The sole deliberate pre-update read: one quest on one diagnostic rebuild.
			probe = { mapID = mapID, questID = probeQuestID, before = SnapshotIcon(probeQuestID) }
		end
		local updated = UpdateIcons()
		local selectedMap = Call(diagnostic, "C_QuestLog", "GetMapForQuestPOIs")
		if probe then
			probe.after = SnapshotIcon(probeQuestID)
			probe.status = updated and selectedMap == mapID and probe.before.ok and probe.after.ok and "OBSERVED"
				or "ERROR"
			if probe.status == "OBSERVED" then
				if Normal(probe.before.x, probe.before.y) or Normal(probe.after.x, probe.after.y) then
					probe.changed = probe.before.x ~= probe.after.x or probe.before.y ~= probe.after.y
				else
					probe.status = "NO_COORDINATES"
				end
			end
			self.legacyUpdateProbe = probe
		end
		if not ok or err == false then
			index.lastError = "SetMapForQuestPOIs:" .. string.sub(tostring(err), 1, 100)
		end
		if selectedMap ~= mapID then
			index.lastError = "POI_MAP_SELECTION_MISMATCH"
		end
		return ok and err ~= false and updated and selectedMap == mapID
	end
	local probeQuestID
	if not self.legacyUpdateProbe and index.legacyUpdateAvailable and type(_G.QuestPOIGetIconInfo) == "function" then
		for _, entry in ipairs(visibleEntries or {}) do
			if type(entry) == "table" and byID[entry.questID] then
				probeQuestID = entry.questID
				break
			end
		end
	end
	local byLogIndex = {}
	for questID, quest in pairs(byID) do
		byLogIndex[quest.index] = questID
	end
	self.indexing = true
	local function ScanLegacy(mapID)
		if type(_G.GetQuestPOIs) ~= "function" then
			return
		end
		local scanMapInfo = MapData:Info(mapID)
		local okLegacy, legacy = pcall(GetQuestPOIs)
		if not okLegacy then
			index.lastError = "GetQuestPOIs:" .. string.sub(tostring(legacy), 1, 100)
			return
		end
		if type(legacy) ~= "table" then
			index.legacyShape = type(legacy)
			return
		end
		if index.legacyShape == "UNAVAILABLE" or (index.legacyShape == "TABLE:0" and #legacy > 0) then
			index.legacyShape = "TABLE:" .. #legacy
			index.legacyEntryShape = EntryShape(legacy[1])
			for i = 1, math.min(8, #legacy) do
				index.legacyEntries[i] = EntryShape(legacy[i])
			end
		end
		for i = 1, math.min(#legacy, 64) do
			local entry = legacy[i]
			local entryType = type(entry)
			local questID, x, y, role
			local explicitMapID
			if entryType == "table" then
				questID = entry.questID or byLogIndex[entry.questLogIndex]
				x, y = Position(entry)
				role = Role(entry)
				explicitMapID = entry.mapID or entry.uiMapID
			elseif entryType == "number" then
				local byIDMatch, byIndexMatch = byID[entry], byID[byLogIndex[entry]]
				if byIDMatch and byIndexMatch and entry ~= byLogIndex[entry] then
					questID = nil -- The returned number is ambiguous; never assign it to a different quest.
				else
					questID = byIDMatch and entry or byLogIndex[entry]
				end
			end
			local quest = ValidID(questID) and byID[questID] or nil
			local headerEvidence = quest
				and quest.headerVerified
				and scanMapInfo
				and Normalize(quest.headerName) == Normalize(scanMapInfo.name)
			local mapEvidence = ValidID(explicitMapID)
				or (index.byMap[mapID] and index.byMap[mapID][questID])
				or headerEvidence
			if
				quest
				and mapEvidence
				and (not ValidID(explicitMapID) or explicitMapID == mapID)
				and type(_G.QuestPOIGetIconInfo) == "function"
				and index.iconCalls < 128
			then
				index.iconCalls = index.iconCalls + 1
				local iconOK, completed, ix, iy, objective = pcall(QuestPOIGetIconInfo, questID)
				if iconOK then
					if
						index.iconReturnShape == "UNAVAILABLE" or (Normal(ix, iy) and not index.iconCoordinateObserved)
					then
						index.iconReturnShape = table.concat({
							EntryShape(completed),
							EntryShape(ix),
							EntryShape(iy),
							EntryShape(objective),
						}, ",")
						if Normal(ix, iy) then
							index.iconCoordinateObserved = true
						end
					end
					if index.iconShape == "UNAVAILABLE" or Normal(ix, iy) then
						index.iconShape = Shape(completed, ix, iy)
					end
					if type(completed) == "boolean" and Normal(ix, iy) then
						x, y = ix, iy
						role = completed and "TURN_IN" or "ACTIVE_OBJECTIVE"
					elseif Normal(completed, ix) then
						x, y = completed, ix
					end
				else
					index.lastError = "QuestPOIGetIconInfo:" .. string.sub(tostring(completed), 1, 100)
				end
			end
			if
				quest
				and mapEvidence
				and (not ValidID(explicitMapID) or explicitMapID == mapID)
				and (Normal(x, y) or ValidID(explicitMapID))
			then
				Match(questID, explicitMapID or mapID, x, y, "LEGACY_QUEST_POI", role or "UNCLASSIFIED")
			end
			if index.legacyEntryShape == "UNAVAILABLE" and entry ~= nil then
				index.legacyEntryShape = EntryShape(entry)
			end
		end
	end
	local function Scan()
		for _, info in ipairs(candidates) do
			index.mapsScanned = index.mapsScanned + 1
			local list = info.mapID == displayMapID and visibleEntries
				or Call(diagnostic, "C_QuestLog", "GetQuestsOnMap", info.mapID)
			if type(list) == "table" then
				if #list == 0 and index.mapListShape == "UNAVAILABLE" then
					index.mapListShape = "EMPTY_TABLE"
				end
				if
					type(list[1]) == "table"
					and (index.mapListShape == "UNAVAILABLE" or index.mapListShape == "EMPTY_TABLE")
				then
					index.mapListShape = Shape(list[1])
				end
				for i = 1, math.min(#list, 128) do
					local item = list[i]
					if type(item) == "table" then
						-- This scan establishes quest -> map membership, never visible coordinates.
						Match(item.questID, info.mapID, nil, nil, "NATIVE_MAP_QUEST", Role(item))
					end
				end
			end
			if maySet and index.legacyMapsScanned < 32 then
				index.legacyMapsScanned = index.legacyMapsScanned + 1
				if SelectPoiMap(info.mapID, info.mapID == displayMapID and probeQuestID or nil) then
					ScanLegacy(info.mapID)
				end
			end
		end
	end
	local ok, err = pcall(Scan)
	if not ok then
		index.lastError = "SCAN:" .. string.sub(tostring(err), 1, 120)
	end
	if maySet then
		local restored = SelectPoiMap(original)
		index.restoredPoiMap = Call(diagnostic, "C_QuestLog", "GetMapForQuestPOIs")
		if not restored or index.restoredPoiMap ~= original then
			restored = SelectPoiMap(original)
			index.restoredPoiMap = Call(diagnostic, "C_QuestLog", "GetMapForQuestPOIs")
		end
		index.poiStateRestored = restored and index.restoredPoiMap == original
		if not index.poiStateRestored then
			index.status = "POI_RESTORE_FAILED"
			if index.lastError == "none" then
				index.lastError = "POI_MAP_MISMATCH"
			end
		end
	else
		-- No legacy state mutation when restoration cannot be guaranteed (or in combat).
		index.restoredPoiMap = original
	end
	index.legacyUpdate = self.legacyUpdateProbe
	if not ok and index.poiStateRestored ~= false then
		index.status = "SCAN_ERROR"
	end
	if index.lastError ~= "none" and index.status == "READY" then
		index.status = "SCAN_PARTIAL"
	end
	self.indexing = false
	self.index, self.indexDirty = index, inCombat or index.poiStateRestored == false
	return index
end

function QuestData:ResolveQuestLocation(quest, index, diagnostic, names)
	local id = quest.questID
	local function Assign(mapID, x, y, source, confidence, role)
		if not ValidID(mapID) or not MapData:Info(mapID) then
			return false
		end
		quest.mapID, quest.questMapID = mapID, mapID
		quest.positionX, quest.positionY = nil, nil
		quest.mapIndicatorX, quest.mapIndicatorY = nil, nil
		if Normal(x, y) then
			if role == "TURN_IN" or role == "ACTIVE_OBJECTIVE" then
				quest.positionX, quest.positionY = x, y
			else
				quest.mapIndicatorX, quest.mapIndicatorY = x, y
			end
		end
		quest.locationSource, quest.locationConfidence = source, confidence
		quest.turnInVerified = role == "TURN_IN" and Normal(x, y) or false
		return true
	end
	if not ValidID(id) then
		quest.locationSource, quest.locationConfidence = "UNKNOWN", "UNKNOWN"
		quest.mapName = MS.L.JOURNEY_MAP_UNKNOWN_ZONE
		return
	end
	local headerMapID = quest.headerVerified and names[Normalize(quest.headerName)] or nil
	local ready = quest.state == "READY_TO_TURN_IN"
	local poi = Call(diagnostic, "C_QuestLog", "GetQuestPOIInfo", id)
	if type(poi) == "table" and (not ready or IsTurnIn(poi)) then
		local mapID = poi.mapID or poi.uiMapID
		local x, y = Position(poi)
		if
			Assign(
				mapID,
				x,
				y,
				IsTurnIn(poi) and Normal(x, y) and "QUEST_POI_COORDINATE" or "QUEST_POI_MAP",
				"HIGH",
				IsTurnIn(poi) and "TURN_IN"
			)
		then
			quest.mapName = MapData:Info(quest.mapID).name
			return
		end
	end
	local matches = index.byQuest[id] or {}
	local best, bestScore, ambiguous = nil, -1, false
	local preferredZone = ValidID(headerMapID) and MapData:LocalZone(headerMapID)
		or (MS.JourneyQuestieOffers and MapData:LocalZone(MS.JourneyQuestieOffers:QuestZone(id)))
	local zoneType = _G.Enum and Enum.UIMapType and Enum.UIMapType.Zone
	for _, match in ipairs(matches) do
		local info = MapData:Info(match.mapID)
		if info then
			local depth = #MapData:Hierarchy(match.mapID)
			local score = (zoneType and info.mapType == zoneType and 32 or 0)
				+ depth
				+ (Normal(match.x, match.y) and 2 or 0)
				+ (match.role == "ACTIVE_OBJECTIVE" and 64 or 0)
				+ (quest.state == "READY_TO_TURN_IN" and match.role == "TURN_IN" and 128 or 0)
				+ (preferredZone and MapData:LocalZone(match.mapID) == preferredZone and 16 or 0)
			if score > bestScore then
				best, bestScore, ambiguous = match, score, false
			elseif score == bestScore and best and best.mapID ~= match.mapID then
				ambiguous = true
			end
		end
	end
	if ambiguous then
		quest.locationSource, quest.locationConfidence = "AMBIGUOUS", "UNKNOWN"
		quest.mapName = MS.L.JOURNEY_MAP_UNKNOWN_ZONE
		return
	end
	if
		best
		and not (ready and best.role ~= "TURN_IN" and best.mapID == headerMapID)
		and Assign(
			best.mapID,
			best.x,
			best.y,
			best.source == "LEGACY_QUEST_POI" and Normal(best.x, best.y) and "QUEST_POI_COORDINATE" or "QUEST_POI_MAP",
			"HIGH",
			best.role
		)
	then
		quest.mapName = MapData:Info(quest.mapID).name
		return
	end
	local directMapID = Call(diagnostic, "C_QuestLog", "GetQuestUiMapID", id)
	if not (ready and directMapID == headerMapID) and Assign(directMapID, nil, nil, "DIRECT_MAP_API", "HIGH") then
		quest.mapName = MapData:Info(quest.mapID).name
		return
	end
	local waypointMapID, wx, wy = Call(diagnostic, "C_QuestLog", "GetNextWaypoint", id)
	if type(waypointMapID) == "table" then
		local value = waypointMapID
		waypointMapID, wx, wy = value.mapID or value.uiMapID, Position(value)
	end
	if ValidID(waypointMapID) and not Normal(wx, wy) then
		local fx, fy = Call(diagnostic, "C_QuestLog", "GetNextWaypointForMap", id, waypointMapID)
		if type(fx) == "table" then
			fx, fy = Position(fx)
		end
		wx, wy = fx, fy
	end
	if Assign(waypointMapID, wx, wy, "WAYPOINT_API", "MEDIUM") then
		quest.mapName = MapData:Info(quest.mapID).name
		return
	end
	local taskMapID = Call(diagnostic, "C_TaskQuest", "GetQuestZoneID", id)
	if ValidID(taskMapID) then
		local tx, ty = Call(diagnostic, "C_TaskQuest", "GetQuestLocation", id, taskMapID)
		if type(tx) == "table" then
			tx, ty = Position(tx)
		end
		if Assign(taskMapID, tx, ty, "TASK_QUEST_API", "MEDIUM") then
			quest.mapName = MapData:Info(quest.mapID).name
			return
		end
	end
	-- A verified Quest Log header identifies the region, never a turn-in coordinate.
	if Assign(headerMapID, nil, nil, "QUEST_LOG_HEADER", "MEDIUM") then
		quest.mapName = MapData:Info(quest.mapID).name
		return
	end
	quest.locationSource, quest.locationConfidence = "UNKNOWN", "UNKNOWN"
	quest.mapName = MS.L.JOURNEY_MAP_UNKNOWN_ZONE
end

-- Zone confidence is separate from position confidence: a quest without a reliable
-- position can still have a trusted canonical zone. A raw mapID alone is never trusted.
function QuestData:ResolveQuestZone(quest, index, names)
	quest.zoneMapID, quest.zoneSource, quest.zoneName = nil, "UNKNOWN", nil
	local function Set(zoneID, source)
		local info = zoneID and MapData:Info(zoneID)
		if not info then return false end
		quest.zoneMapID, quest.zoneSource, quest.zoneName = zoneID, source, info.name
		return true
	end
	-- A/B: the same HIGH/MEDIUM location the map action already trusts.
	if quest.locationConfidence == "HIGH" or quest.locationConfidence == "MEDIUM" then
		if Set(MapData:LocalZone(quest.questMapID or quest.mapID), "LOCATION") then return end
	end
	-- Map membership evidence for this quest, reduced to canonical zones.
	local zones, count = {}, 0
	for _, match in ipairs(index and index.byQuest and index.byQuest[quest.questID] or {}) do
		local zone = MapData:Info(match.mapID) and MapData:LocalZone(match.mapID)
		if zone and not zones[zone] then zones[zone], count = true, count + 1 end
	end
	-- The verified Quest Log header names the zone, unless map evidence contradicts it.
	local header = quest.headerVerified and names and names[Normalize(quest.headerName)] or nil
	local headerZone = ValidID(header) and MapData:LocalZone(header) or nil
	if headerZone and (count == 0 or zones[headerZone]) and Set(headerZone, "QUEST_LOG_HEADER") then return end
	-- QuestieDB, when installed, files the quest under one zone: it decides among the candidates.
	local filed = MS.JourneyQuestieOffers and MS.JourneyQuestieOffers:QuestZone(quest.questID)
	local filedZone = ValidID(filed) and MapData:LocalZone(filed) or nil
	if filedZone and (count == 0 or zones[filedZone]) and Set(filedZone, "QUESTIEDB") then return end
	-- Several candidate maps that all belong to one zone still identify that zone.
	if count == 1 then Set(next(zones), "MAP_MEMBERSHIP") end
end

-- The trusted canonical zone is the only zone-level truth; raw mapID/mapName never count.
-- Records that never went through ResolveQuestZone are evaluated by that same rule on a
-- scratch copy: nothing is cached on the record, so later evidence changes cannot go stale.
function QuestData:TrustedZone(quest, index, names)
	if type(quest) ~= "table" then return nil end
	if quest.zoneSource == nil and quest.zoneMapID == nil then
		local probe = { questID = quest.questID, locationConfidence = quest.locationConfidence,
			questMapID = quest.questMapID, mapID = quest.mapID,
			headerVerified = quest.headerVerified, headerName = quest.headerName }
		self:ResolveQuestZone(probe, index, names)
		quest = probe
	end
	if quest.zoneSource == "UNKNOWN" then return nil end
	return ValidID(quest.zoneMapID) and quest.zoneMapID or nil
end

-- Player-facing place: the trusted zone name, or a trusted location's own map inside that
-- zone (e.g. a micro map). Without a trusted zone: the localized unknown-region label.
function QuestData:PlaceName(quest)
	local zone = self:TrustedZone(quest)
	if not zone then
		if quest.headerVerified and type(quest.headerName) == "string" and quest.headerName ~= "" then
			return quest.headerName
		end
		return MS.L.JOURNEY_MAP_UNKNOWN_ZONE
	end
	local located = (quest.locationConfidence == "HIGH" or quest.locationConfidence == "MEDIUM")
		and (quest.questMapID or quest.mapID)
	if ValidID(located) and MapData:LocalZone(located) == zone then
		local info = MapData:Info(located)
		if info and info.name then return info.name end
	end
	local info = MapData:Info(zone)
	return info and info.name or quest.zoneName or MS.L.JOURNEY_MAP_UNKNOWN_ZONE
end

-- Shared CARTE / QUÊTES label: the relation's display name when resolved, else PlaceName.
function QuestData:DisplayPlaceName(quest)
	if type(quest) ~= "table" then return MS.L.JOURNEY_MAP_UNKNOWN_ZONE end
	return quest.displayMapName or self:PlaceName(quest)
end

function QuestData:ReadSnapshot(diagnostic)
	local batch = self.flushSnapshot
	if batch and batch.entries then return batch end
	local entries, headers = {}, {}
	local modern = type(_G.C_QuestLog) == "table"
		and type(C_QuestLog.GetNumQuestLogEntries) == "function"
		and type(C_QuestLog.GetInfo) == "function"
	local count
	if modern then
		count = Call(diagnostic, "C_QuestLog", "GetNumQuestLogEntries")
	elseif type(_G.GetNumQuestLogEntries) == "function" then
		local ok, result = pcall(GetNumQuestLogEntries)
		if ok then
			count = result
		end
	end
	count = type(count) == "number" and math.min(count, 200) or 0
	for index = 1, count do
		local info
		if modern then
			info = Call(diagnostic, "C_QuestLog", "GetInfo", index)
		elseif type(_G.GetQuestLogTitle) == "function" then
			local ok, title, level, _, _, isHeader, _, complete, _, questID = pcall(GetQuestLogTitle, index)
			if ok and title then
				info = { title = title, level = level, isHeader = isHeader, isComplete = complete, questID = questID }
			end
		end
		if type(info) == "table" then
			entries[index] = info
			if info.isHeader == true or info.isHeader == 1 then
				headers[#headers + 1] = { index = index, name = info.title }
			end
		end
	end
	local snapshot = batch or {}
	snapshot.entries, snapshot.headers, snapshot.count, snapshot.modern = entries, headers, count, modern
	snapshot.logDiagnostic = diagnostic
	return snapshot
end

function QuestData:ReadLog(diagnostic, options)
	local snapshot = self:ReadSnapshot(diagnostic)
	diagnostic.errors, diagnostic.shapes = snapshot.logDiagnostic.errors, snapshot.logDiagnostic.shapes
	if snapshot.quests then
		for key, value in pairs(snapshot.diagnostic) do diagnostic[key] = value end
		return snapshot.quests, snapshot.byID, snapshot
	end
	local quests, byID = {}, {}
	local entries, headers, count, modern = snapshot.entries, snapshot.headers, snapshot.count, snapshot.modern
	options = self.flushSnapshot or options or {}
	self.descriptionSupport = "UNAVAILABLE_SAFE_API"
	local headerCursor, header = 1, nil
	for index = 1, count do
		local info = entries[index]
		while headerCursor <= #headers and headers[headerCursor].index < index do
			header = headers[headerCursor]
			headerCursor = headerCursor + 1
		end
		if type(info) == "table" then
			if info.isHeader ~= true and info.isHeader ~= 1 then
				local nextHeader = headers[headerCursor]
				local verified = header and header.index < index and (not nextHeader or index < nextHeader.index)
				local quest = {
					questID = info.questID,
					title = info.title or tostring(info.questID or index),
					level = info.level,
					index = index,
					questLogIndex = index,
					headerIndex = verified and header.index or nil,
					headerName = verified and header.name or nil,
					nextHeaderIndex = nextHeader and nextHeader.index or nil,
					headerVerified = verified == true,
					active = true,
					isComplete = info.isComplete == true or info.isComplete == 1,
				}
				if ValidID(quest.questID) then
					local ready = Call(diagnostic, "C_QuestLog", "ReadyForTurnIn", quest.questID)
					local complete = Call(diagnostic, "C_QuestLog", "IsComplete", quest.questID)
					quest.readyForTurnIn = ready == true or ready == 1
					if complete ~= nil then
						quest.isComplete = complete == true or complete == 1
					end
					if quest.readyForTurnIn then
						quest.state, quest.stateSource = "READY_TO_TURN_IN", "C_QuestLog.ReadyForTurnIn"
					elseif ready == nil and quest.isComplete then
						quest.state = "READY_TO_TURN_IN"
						quest.stateSource = (complete == true or complete == 1) and "C_QuestLog.IsComplete_FALLBACK"
							or "C_QuestLog.GetInfo.isComplete_FALLBACK"
					else
						quest.state, quest.stateSource = "IN_PROGRESS", "QUEST_LOG_ACTIVE"
					end
					local objectives = Call(diagnostic, "C_QuestLog", "GetQuestObjectives", quest.questID)
					if
						type(objectives) == "table"
						and type(objectives[1]) == "table"
						and diagnostic.objectiveShape == nil
					then
						local shapeOK, shape = pcall(Shape, objectives[1])
						diagnostic.objectiveShape = shapeOK and shape or "SHAPE_ERROR"
					end
					local taskPercent = Call(diagnostic, "C_TaskQuest", "GetQuestProgressBarInfo", quest.questID)
					quest.progress = Progress(objectives, taskPercent)
					if options.description ~= false and type(_G.GetQuestLogQuestText) == "function" then
						local textOK, description = pcall(GetQuestLogQuestText, index)
						if textOK and type(description) == "string" and description ~= "" then
							quest.description = description
							self.descriptionSupport = "SUPPORTED"
						end
					end
					byID[quest.questID] = quest
				else
					quest.state, quest.stateSource = "UNKNOWN", "QUEST_LOG_NO_ID"
					quest.progress = Progress(nil)
					quest.mapName = MS.L.JOURNEY_MAP_UNKNOWN_ZONE
					quest.locationSource, quest.locationConfidence = "UNKNOWN", "UNKNOWN"
				end
				quests[#quests + 1] = quest
			end
		end
	end
	diagnostic.logSource = modern and "C_QuestLog.GetInfo" or "GetQuestLogTitle"
	diagnostic.questProgressSupported = type(_G.C_QuestLog) == "table"
			and type(C_QuestLog.GetQuestObjectives) == "function"
			and "API_PRESENT"
		or "UNAVAILABLE"
	self.latestByID = byID
	snapshot.quests, snapshot.byID, snapshot.diagnostic = quests, byID, diagnostic
	if MS.JourneySession and MS.JourneySession.ObserveQuests then MS.JourneySession:ObserveQuests(quests) end
	return quests, byID, snapshot
end

function QuestData:DescendsFrom(mapID, ancestorID)
	if not ValidID(mapID) or not ValidID(ancestorID) then
		return false
	end
	if mapID == ancestorID then
		return true
	end
	local seen = {}
	for _ = 1, 8 do
		if seen[mapID] then
			break
		end
		seen[mapID] = true
		local info = MapData:Info(mapID)
		mapID = info and info.parentMapID
		if mapID == ancestorID then
			return true
		end
		if not ValidID(mapID) then
			break
		end
	end
	return false
end


function QuestData:IsLocalQuest(quest, contextMapID)
    local zone = MapData:LocalZone(contextMapID)
    if not zone or type(quest) ~= "table" then return false end
    return MapData:LocalZone(quest.questMapID or quest.mapID) == zone
end

function QuestData:Pins(displayMapID, byID, index, nativeEntries, diagnostic)
	local pins, seen, sources, nativeCoordinates, selected = {}, {}, {}, {}, {}
	local legacyByQuest = {}
	local selection = { nativeCount = 0, legacyCount = 0, headerCount = 0 }
	diagnostic.sourceSelection = selection
	diagnostic.visibleMapQuestEntries = #nativeEntries
	diagnostic.sourceComparison, diagnostic.nativeExclusions = {}, {}
	for questID, quest in pairs(byID) do
		quest.pinSource, quest.objectivePOIs, quest.turnInPOI = nil, {}, nil
		for _, match in ipairs(index.byQuest[questID] or {}) do
			if match.source == "LEGACY_QUEST_POI" and match.mapID == displayMapID and Normal(match.x, match.y) then
				legacyByQuest[questID] = legacyByQuest[questID] or match
				if
					(quest.state == "READY_TO_TURN_IN" and match.role == "TURN_IN")
					or (quest.state == "IN_PROGRESS" and match.role == "ACTIVE_OBJECTIVE")
				then
					legacyByQuest[questID] = match
				end
			end
		end
	end
	local function Add(questID, x, y, source, state, entry)
		local key = tostring(questID) .. string.format(":%.17g:%.17g", x, y)
		if seen[key] then
			return nil, "DUPLICATE_QUEST_COORDINATE"
		end
		seen[key], sources[source] = true, true
		local quest = byID[questID]
		if not quest then
			local info = MapData:Info(displayMapID)
			quest = {
				questID = questID,
				title = entry and entry.title or string.format(MS.L.JOURNEY_MAP_QUEST_FALLBACK, questID),
				state = state,
				active = false,
				mapID = displayMapID,
				questMapID = displayMapID,
				mapName = info and info.name,
				locationSource = source,
				locationConfidence = "HIGH",
			}
		end
		local role = state == "READY_TO_TURN_IN" and "READY_TURNIN"
			or state == "IN_PROGRESS" and "ACTIVE_OBJECTIVE"
			or state == "AVAILABLE" and "AVAILABLE_START"
			or "NATIVE_MAP_PIN"
		local pin = {
			questID = questID,
			quest = quest,
			mapID = displayMapID,
			x = x,
			y = y,
			source = source,
			apiSource = source,
			state = state,
			role = role,
			confidence = "HIGH",
			coordinateKind = source == "NATIVE_MAP_QUEST" and "NATIVE_MAP_PIN_COORDINATE" or "QUEST_POI_COORDINATE",
			nativeEntry = entry,
			turnInVerified = state == "READY_TO_TURN_IN",
			pinType = state == "READY_TO_TURN_IN" and "UI-QuestPoi-QuestBangTurnIn"
				or state == "AVAILABLE" and "QuestNormal"
				or state == "IN_PROGRESS" and "Quest-In-Progress-Icon-yellow"
				or "UNKNOWN",
		}
		quest.pinSource = source
		local poi = { mapID = displayMapID, x = x, y = y, source = source, role = role, confidence = "HIGH" }
		if state == "READY_TO_TURN_IN" then
			quest.turnInPOI = poi
		elseif state == "IN_PROGRESS" then
			quest.objectivePOIs = quest.objectivePOIs or {}
			quest.objectivePOIs[#quest.objectivePOIs + 1] = poi
		elseif state == "AVAILABLE" then
			quest.availablePOI = poi
		end
		pins[#pins + 1], selected[questID] = pin, pin
		local count = source == "NATIVE_MAP_QUEST" and "nativeCount" or "legacyCount"
		selection[count] = selection[count] + 1
		return pin
	end
	local compared = {}
	local function Compare(questID, state, native, pin, exclusion)
		if #diagnostic.sourceComparison >= 12 then
			return
		end
		local legacy = legacyByQuest[questID]
		diagnostic.sourceComparison[#diagnostic.sourceComparison + 1] = {
			questID = questID,
			state = state,
			mapID = displayMapID,
			nativeMap = native,
			legacy = legacy,
			legacyAvailable = legacy ~= nil,
			selected = pin,
			exclusion = exclusion,
		}
		if questID then
			compared[questID] = true
		end
	end
	-- This list is the direct response for the visible map. Header/index location
	-- and legacy coordinates cannot overrule it, including for ready quests.
	for entryIndex, entry in ipairs(nativeEntries) do
		local questID = type(entry) == "table" and entry.questID or nil
		local quest = ValidID(questID) and byID[questID] or nil
		local state = quest and quest.state or "UNKNOWN"
		local pin, exclusion
		if not ValidID(questID) then
			exclusion = "INVALID_QUEST_ID"
		elseif not Normal(entry.x, entry.y) then
			exclusion = "MISSING_OR_INVALID_NATIVE_XY"
		else
			nativeCoordinates[questID] = true
			if not quest then
				local onQuest = Call(diagnostic, "C_QuestLog", "IsOnQuest", questID)
				local ready = Call(diagnostic, "C_QuestLog", "ReadyForTurnIn", questID)
				if ready == true or ready == 1 then
					state = "READY_TO_TURN_IN"
				elseif onQuest == true or onQuest == 1 or entry.inProgress == true or entry.inProgress == 1 then
					state = "IN_PROGRESS"
				elseif entry.isQuestStart == true or entry.isQuestStart == 1 then
					state = "AVAILABLE"
				end
			end
			-- isMapIndicatorQuest is retained, not used to hide native coordinates.
			pin, exclusion = Add(questID, entry.x, entry.y, "NATIVE_MAP_QUEST", state, entry)
		end
		if exclusion then
			diagnostic.nativeExclusions[#diagnostic.nativeExclusions + 1] = "entry="
				.. entryIndex
				.. ",questID="
				.. tostring(questID)
				.. ",reason="
				.. exclusion
		end
		Compare(questID, state, entry, pin or selected[questID], exclusion)
	end
	-- Legacy is only a complement on this exact map, with state/role agreement.
	local questIDs = {}
	for questID in pairs(byID) do
		questIDs[#questIDs + 1] = questID
	end
	table.sort(questIDs)
	for _, questID in ipairs(questIDs) do
		local quest, legacy = byID[questID], legacyByQuest[questID]
		if not nativeCoordinates[questID] and legacy then
			if
				(quest.state == "READY_TO_TURN_IN" and legacy.role == "TURN_IN")
				or (quest.state == "IN_PROGRESS" and legacy.role == "ACTIVE_OBJECTIVE")
			then
				Add(questID, legacy.x, legacy.y, "LEGACY_QUEST_POI", quest.state)
			end
		end
		local headerOnly = not selected[questID]
			and quest.mapID == displayMapID
			and quest.locationSource == "QUEST_LOG_HEADER"
		if headerOnly then
			selection.headerCount = selection.headerCount + 1 -- Region records, never rendered pins.
		end
		if not compared[questID] and (legacy or headerOnly or selected[questID]) then
			Compare(
				questID,
				quest.state,
				nil,
				selected[questID]
					or (headerOnly and { source = "QUEST_LOG_HEADER", pinType = "NONE_REGION_ONLY" } or nil)
			)
		end
	end
	for _, example in ipairs(diagnostic.sourceComparison) do
		example.selected = selected[example.questID] or example.selected
	end
	diagnostic.visibleJourneyPins = #pins
	local names = {}
	for source in pairs(sources) do
		names[#names + 1] = source
	end
	table.sort(names)
	return pins, #names > 0 and table.concat(names, ",") or "NONE"
end

-- UI relation is local to this display. It never changes index evidence or pins.
function QuestData:ResolveDisplayRelation(quest, displayMapID, present, index)
	quest.globalLocation = tostring(quest.locationSource) .. ":" .. tostring(quest.mapID or "none")
	quest.displayedMapMatch = present == true
	-- Precedence: live native presence on this displayed map (local, never sticky), then the
	-- trusted canonical zone. Raw mapID/mapName and candidate maps never decide the relation.
	local zone = self:TrustedZone(quest, index)
	local relation, mapID
	if present then
		relation, mapID = "HERE", displayMapID
	elseif zone then
		local displayZone = MapData:LocalZone(displayMapID)
		relation = (displayZone and displayZone == zone or self:DescendsFrom(zone, displayMapID))
			and "HERE" or "OFF_REGION"
		mapID = zone
	else
		local candidates = index and index.byQuest and index.byQuest[quest.questID]
		relation = quest.locationSource == "AMBIGUOUS" and type(candidates) == "table" and #candidates > 0
			and "AMBIGUOUS" or "UNKNOWN"
	end
	local info = present and MapData:Info(displayMapID)
	quest.displayRelation, quest.displayMapID = relation, mapID
	quest.displayMapName = info and info.name or self:PlaceName(quest)
	return relation
end

function QuestData:Collect(displayMapID)
	local diagnostic = { errors = {}, shapes = {} }
	local quests, byID, snapshot = self:ReadLog(diagnostic)
	-- Always read the displayed map directly, even when QuestMapIndex is cached.
	local nativeEntries = Call(diagnostic, "C_QuestLog", "GetQuestsOnMap", displayMapID)
	diagnostic.visibleQuestSource = "C_QuestLog.GetQuestsOnMap"
	diagnostic.visibleMapQuestStatus = type(nativeEntries) == "table" and "OBSERVED" or "UNAVAILABLE"
	nativeEntries = type(nativeEntries) == "table" and nativeEntries or {}
	local index = self:BuildIndex(byID, displayMapID, diagnostic, nativeEntries)
	local names = self:MapNameIndex(displayMapID)
	index.locations = index.locations or {}
	for _, quest in ipairs(quests) do
		if ValidID(quest.questID) then
			local cached = index.locations[quest.questID]
			if cached and cached.state == quest.state then
				for _, field in ipairs({
					"mapID",
					"questMapID",
					"mapName",
					"positionX",
					"positionY",
					"mapIndicatorX",
					"mapIndicatorY",
					"locationSource",
					"locationConfidence",
					"turnInVerified",
				}) do
					quest[field] = cached[field]
				end
			else
				self:ResolveQuestLocation(quest, index, diagnostic, names)
				cached = { state = quest.state }
				for _, field in ipairs({
					"mapID",
					"questMapID",
					"mapName",
					"positionX",
					"positionY",
					"mapIndicatorX",
					"mapIndicatorY",
					"locationSource",
					"locationConfidence",
					"turnInVerified",
				}) do
					cached[field] = quest[field]
				end
				index.locations[quest.questID] = cached
			end
			self:ResolveQuestZone(quest, index, names)
		end
	end
	local pins, pinSource = self:Pins(displayMapID, byID, index, nativeEntries, diagnostic)
	local here, elsewhere, unlocated, ambiguous = {}, {}, {}, {}
	local stateCounts, locationCounts, examples = {}, {}, {}
	-- "Ici" is a zone: a displayed micro map is judged exactly like its containing zone, so
	-- CARTE and QUÊTES can never disagree. Pins above still use the displayed map itself.
	local relationMapID = MapData:RelationZone(displayMapID)
	local relationEntries = nativeEntries
	if relationMapID ~= displayMapID then
		relationEntries = Call(diagnostic, "C_QuestLog", "GetQuestsOnMap", relationMapID)
		relationEntries = type(relationEntries) == "table" and relationEntries or {}
	end
	local displayedMatches = {}
	for _, entry in ipairs(relationEntries) do
		if type(entry) == "table" and ValidID(entry.questID) then
			displayedMatches[entry.questID] = true
		end
	end
	local relations = { HERE = 0, OFF_REGION = 0, AMBIGUOUS = 0, UNKNOWN = 0 }
	diagnostic.questDisplayRelation = relations
	local withProgress = 0
	for _, quest in ipairs(quests) do
		stateCounts[quest.state] = (stateCounts[quest.state] or 0) + 1
		locationCounts[quest.locationSource] = (locationCounts[quest.locationSource] or 0) + 1
		if quest.progress and quest.progress.totalObjectives > 0 then
			withProgress = withProgress + 1
		end
		local relation = self:ResolveDisplayRelation(quest, relationMapID, displayedMatches[quest.questID], index)
		relations[relation] = relations[relation] + 1
		if relation == "HERE" then
			here[#here + 1] = quest
		elseif relation == "OFF_REGION" then
			elsewhere[#elsewhere + 1] = quest
		elseif relation == "AMBIGUOUS" then
			ambiguous[#ambiguous + 1] = quest
		else
			unlocated[#unlocated + 1] = quest
		end
		if #examples < 8 then
			examples[#examples + 1] = quest
		end
	end
	local additionalStates = {}
	for index, pin in ipairs(pins) do
		if not pin.quest or not pin.quest.active then
			local key = pin.questID or ("pin:" .. index)
			if not additionalStates[key] then
				additionalStates[key] = true
				stateCounts[pin.state] = (stateCounts[pin.state] or 0) + 1
			end
		end
	end
	diagnostic.questsWithProgress = withProgress
	if withProgress > 0 then
		diagnostic.questProgressSupported = "OBSERVED"
	end
	diagnostic.questProgressExample = nil
	for _, quest in ipairs(examples) do
		if quest.progress and quest.progress.totalObjectives > 0 then
			diagnostic.questProgressExample = tostring(quest.questID or "?")
				.. ":"
				.. quest.progress.completedObjectives
				.. "/"
				.. quest.progress.totalObjectives
				.. ":"
				.. tostring(quest.progress.percent or "none")
			break
		end
	end
	local stateSources = {}
	for _, quest in ipairs(quests) do
		stateSources[quest.stateSource] = true
	end
	for _, pin in ipairs(pins) do
		if not pin.quest or not pin.quest.active then
			stateSources[pin.state == "AVAILABLE" and "NATIVE_MAP_POI_GIVER" or "NATIVE_MAP_POI_UNCLASSIFIED"] = true
		end
	end
	local sourceNames = {}
	for source in pairs(stateSources) do
		sourceNames[#sourceNames + 1] = source
	end
	table.sort(sourceNames)
	diagnostic.stateSources = table.concat(sourceNames, ",")
	local locationNames = {}
	for source in pairs(locationCounts) do
		locationNames[#locationNames + 1] = source
	end
	table.sort(locationNames)
	diagnostic.locationSources = table.concat(locationNames, ",")
	local confidenceCounts = { HIGH = 0, MEDIUM = 0, UNKNOWN = 0, AMBIGUOUS = locationCounts.AMBIGUOUS or 0 }
	local headerMatches = 0
	for _, quest in ipairs(quests) do
		if quest.locationSource ~= "AMBIGUOUS" then
			local confidence = quest.locationConfidence or "UNKNOWN"
			confidenceCounts[confidence] = (confidenceCounts[confidence] or 0) + 1
		end
		if quest.locationSource == "QUEST_LOG_HEADER" then
			headerMatches = headerMatches + 1
		end
	end
	index.headerMatches = headerMatches
	index.ambiguous = locationCounts.AMBIGUOUS or 0
	index.unknown = #unlocated
	diagnostic.confidenceCounts = confidenceCounts
	return {
		active = quests,
		snapshot = snapshot,
		byID = byID,
		pins = pins,
		nativeMapEntries = nativeEntries,
		here = here,
		elsewhere = elsewhere,
		unlocated = unlocated,
		ambiguous = ambiguous,
		examples = examples,
		relationMapID = relationMapID,
		stateCounts = stateCounts,
		source = diagnostic.logSource .. "+" .. pinSource,
		diagnostic = diagnostic,
		index = index,
	}
end

-- Presentation priority shared by CARTE and QUÊTES: ready to turn in first, otherwise the
-- incoming order (quest log order) is kept. Orientation only, never a recommendation.
function QuestData:ReadyFirst(list, stateOf)
	stateOf = stateOf or function(quest) return quest.state end
	local ranked = {}
	for position, item in ipairs(list or {}) do
		ranked[position] = { item = item, position = position, ready = stateOf(item) == "READY_TO_TURN_IN" }
	end
	table.sort(ranked, function(a, b)
		if a.ready ~= b.ready then return a.ready end
		return a.position < b.position
	end)
	local ordered = {}
	for position, entry in ipairs(ranked) do ordered[position] = entry.item end
	return ordered
end

-- The first objective still open, as one short line for a quest row ("Collier clouté : 0/5").
-- The quest log text already carries the counts most of the time; they are added otherwise.
function QuestData:ObjectiveLine(quest)
    for _, objective in ipairs(quest and quest.progress and quest.progress.objectives or {}) do
        local text = objective.text
        if not objective.finished and type(text) == "string" and text ~= "" then
            if objective.type ~= "event" and type(objective.current) == "number" and type(objective.required) == "number"
                and objective.required > 1 and not text:find("%d+%s*/%s*%d+") then
                text = string.format(MS.L.JOURNEY_MAP_ROW_OBJECTIVE, text, objective.current, objective.required)
            end
            return text
        end
    end
end

-- Event/dialogue objectives are not numeric grinding progress, even if the API supplies 0/1.
function QuestData:HasCountedObjectives(quest)
    for _, objective in ipairs(quest and quest.progress and quest.progress.objectives or {}) do
        if objective.type ~= "event" and type(objective.required) == "number" and objective.required > 1 then return true end
    end
    return false
end
