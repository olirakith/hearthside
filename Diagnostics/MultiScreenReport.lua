local MS = _G.MS

local function Value(value)
    if value == nil then return "unavailable" end
    if type(value) == "table" then return "<table>" end
    local text = tostring(value):gsub("\r", "\\r"):gsub("\n", "\\n")
    return text
end

local function Number(value, precision)
    if type(value) ~= "number" then return "unavailable" end
    return string.format("%." .. (precision or 2) .. "f", value)
end

local function Pair(width, height)
    if type(width) ~= "number" or type(height) ~= "number" then return "unavailable" end
    return string.format("%.2fx%.2f", width, height)
end

local function Rect(rect)
    if type(rect) ~= "table" or type(rect.x) ~= "number" or type(rect.y) ~= "number"
        or type(rect.width) ~= "number" or type(rect.height) ~= "number" then
        return "unavailable"
    end
    return string.format("%.2f,%.2f,%.2f,%.2f", rect.x, rect.y, rect.width, rect.height)
end

local function Read(object, method, ...)
    if not object then return nil end
    local ok, fn = pcall(function() return object[method] end)
    if not ok or type(fn) ~= "function" then return nil end
    local success, a, b, c, d, e = pcall(fn, object, ...)
    if success then return a, b, c, d, e end
end

local function PhysicalSize()
    if type(GetPhysicalScreenSize) ~= "function" then return nil end
    local ok, width, height = pcall(GetPhysicalScreenSize)
    if ok then return width, height end
end

local function Field(lines, name, value)
    lines[#lines + 1] = name .. "=" .. Value(value)
end

local function Section(lines, title)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[" .. title .. "]"
end

-- UIParent = GAME session (VIEWPORT or LEGACY_MINIMAL), from its own status lines.
function MS.Diagnostics:AppendViewportReport(lines)
    Section(lines, "UIPARENT VIEWPORT")
    local mode = MS.UIParentMode
    local ok, status = pcall(function() return mode and mode:StatusLines() end)
    if not ok or type(status) ~= "table" then Field(lines, "status", ok and "UNAVAILABLE" or tostring(status)); return end
    for _, line in ipairs(status) do lines[#lines + 1] = line end
end

local function SafeStatus(lines, label, owner, method, ...)
    if not owner or type(owner[method]) ~= "function" then return nil end
    local ok, value = pcall(owner[method], owner, ...)
    if ok then return value end
    Field(lines, label .. ".diagnosticError", value)
end

local function Span(layout, source)
    if source == "COMPANION_GENERATED" and type(MS.GeneratedLayout) == "table" then
        return type(MS.GeneratedLayout.span) == "table" and MS.GeneratedLayout.span or nil
    end
    local game, workspace = layout and layout.game, layout and layout.workspace
    if not MS.Rect:IsValid(game) or not MS.Rect:IsValid(workspace) then return nil end
    local left = math.min(game.x, workspace.x)
    local bottom = math.min(game.y, workspace.y)
    return {
        width = math.max(game.x + game.width, workspace.x + workspace.width) - left,
        height = math.max(game.y + game.height, workspace.y + workspace.height) - bottom,
    }
end

local function WorldFramePhysical(metrics)
    local x, y, width, height = Read(WorldFrame, "GetRect")
    if not metrics or not x or not y or not width or not height then return nil end
    local ok, result = pcall(function()
        local ui = MS.Transform:FrameRectToUI(
            { x = x, y = y, width = width, height = height }, WorldFrame, UIParent)
        return ui and MS.Transform:UIRectToPhysical(ui, metrics)
    end)
    if ok then return result end
end

local function RectMatch(first, second)
    if not first or not second then return "unavailable" end
    local tolerance = 1
    local matches = math.abs(first.x - second.x) <= tolerance
        and math.abs(first.y - second.y) <= tolerance
        and math.abs(first.width - second.width) <= tolerance
        and math.abs(first.height - second.height) <= tolerance
    return matches and "YES" or "NO"
end

function MS.Diagnostics:BuildMultiScreenReport()
    local lines = { "=== " .. MS.L.PRODUCT_NAME .. " ===" }
    Field(lines, "Addon", MS.Product and MS.Product.addonVersion)
    Field(lines, "Companion", "UNKNOWN") -- Not carried by protocol V1.
    Field(lines, "Protocol", MS.PixelHandshake and MS.PixelHandshake.VERSION)
    local version, build
    if type(GetBuildInfo) == "function" then version, build = GetBuildInfo() end
    Field(lines, "WoW", tostring(version) .. " / " .. tostring(build))
    Field(lines, "Addon installation", MS.addonName == "MultiScreen_Forever"
        and "LEGACY_FOLDER MultiScreen_Forever" or MS.addonName)
    Section(lines, "RUNTIME")
    local runtime = MS.Runtime or {}
    for _, name in ipairs({ "state", "restoreInProgress", "restoreCount",
        "restoreTransactions", "restoreAttempts", "lastRestoreReason",
        "lastRestoreResult", "lastRestoreError", "lastEnableStage",
        "lastEnableError", "lastEnableDetail", "failSafeDisableCount" }) do
        if name == "restoreInProgress" then Field(lines, name, runtime.restoring)
        else Field(lines, name, runtime[name]) end
    end
    Field(lines, "appliedSteps", runtime.appliedSteps and table.concat(runtime.appliedSteps, ",") or "none")
    Section(lines, "RECOVERY")
    local recovery = MS.Recovery or {}
    for _, name in ipairs({ "viewportRestoreResult", "uiParentRestoreResult",
        "workspaceRestoreResult", "deferredResult", "deferredError" }) do Field(lines, name, recovery[name]) end
    Field(lines, "restoreTransactions", runtime.restoreTransactions)
    Field(lines, "restoreAttempts", runtime.restoreAttempts)
    Field(lines, "restoreHistory", runtime.restoreHistory and table.concat(runtime.restoreHistory, ",") or "none")
    Field(lines, "ROLLBACK_FIRST_FAILURE", runtime.lastRestoreResult == "FAILED"
        and type(runtime.lastRestoreError) == "string"
        and runtime.lastRestoreError:match("^[^;]+") or "none")
    local layoutOk, layout, source, layoutError = pcall(MS.Config.GetLayout, MS.Config)
    if not layoutOk then
        Field(lines, "Layout.diagnosticError", layout)
        layout, source, layoutError = nil, "UNAVAILABLE", "DIAGNOSTIC_ERROR"
    end
    local generated = MS.GeneratedLayout
    local metrics = SafeStatus(lines, "Transform", MS.Transform, "GetMetrics")
    local actualWidth, actualHeight = PhysicalSize()
    local spanOk, span = pcall(Span, layout, source)
    if not spanOk then Field(lines, "Span.diagnosticError", span); span = nil end

    Section(lines, "LAYOUT")
    Field(lines, "runtime.invalidatedReason", MS.Runtime and MS.Runtime.invalidatedReason or "none")
    Field(lines, "runtime.lastClosureError", MS.Runtime and MS.Runtime.lastClosureError or "none")
    Field(lines, "source", source)
    Field(lines, "schemaVersion", type(generated) == "table" and generated.schemaVersion or nil)
    Field(lines, "layoutError", layoutError or "none")
    Field(lines, "expectedSpan", span and Pair(span.width, span.height) or nil)
    Field(lines, "actualPhysical", Pair(actualWidth, actualHeight))
    local layoutMatch = source == "COMPANION_GENERATED" and layout and span
        and actualWidth == span.width and actualHeight == span.height
    Field(lines, "layoutMatch", source == "COMPANION_GENERATED" and (layoutMatch and "YES" or "NO") or "N/A")
    Field(lines, "game", Rect(layout and layout.game))
    Field(lines, "workspace", Rect(layout and layout.workspace))

    Section(lines, "UI")
    Field(lines, "GetPhysicalScreenSize", Pair(actualWidth, actualHeight))
    Field(lines, "UIParentSize", Pair(Read(UIParent, "GetWidth"), Read(UIParent, "GetHeight")))
    Field(lines, "UIParentScale", Number(Read(UIParent, "GetScale"), 6))
    Field(lines, "UIParentEffectiveScale", Number(Read(UIParent, "GetEffectiveScale"), 6))

    Section(lines, "VIEWPORT")
    local actualWorld = WorldFramePhysical(metrics)
    Field(lines, "expectedWorldFramePhysical", Rect(layout and layout.game))
    Field(lines, "actualWorldFramePhysical", Rect(actualWorld))
    Field(lines, "match", RectMatch(layout and layout.game, actualWorld))

    Section(lines, "WORKSPACE")
    local workspace = MS.Workspace
    local workspaceShown = Read(workspace and workspace.frame, "IsShown") == true
    local workspaceUI = layout and metrics and MS.Rect:IsValid(layout.workspace)
        and MS.Transform:RectToUI(layout.workspace, metrics) or nil
    local workspaceLayout = workspaceShown and workspace and workspace:GetLayoutInfo() or nil
    if not workspaceLayout and workspaceUI then
        workspaceLayout = MS.WorkspaceLayout:Calculate(workspaceUI)
    end
    Field(lines, "shown", workspaceShown)
    Field(lines, "physicalRect", Rect(layout and layout.workspace))
    Field(lines, "uiRect", Rect(workspaceUI))
    Field(lines, "responsiveClass", workspaceLayout and workspaceLayout.class)
    for _, name in ipairs({ "header", "main", "side", "bottom" }) do
        Field(lines, name, Rect(workspaceLayout and workspaceLayout[name]))
    end

    Section(lines, "GAME REGION")
    local gameUI = MS.GameUI
    local gameShown = Read(gameUI and gameUI.frame, "IsShown") == true
    local gameUIRect = gameUI and gameUI:GetRegion()
    if not gameUIRect and layout and metrics and MS.Rect:IsValid(layout.game) then
        gameUIRect = MS.Transform:RectToUI(layout.game, metrics)
    end
    Field(lines, "shown", gameShown)
    Field(lines, "physicalRect", Rect(layout and layout.game))
    Field(lines, "uiRect", Rect(gameUIRect))

    Section(lines, "EDIT MODE")
    local watch = SafeStatus(lines, "EditMode", MS.EditModeWatch, "GetStatus")
    Field(lines, "activeLayout", watch and watch.active)
    Field(lines, "journeyProfileActive", watch and watch.journeyProfile)
    Field(lines, "migration", watch and watch.state)
    Field(lines, "editing", watch and watch.editing)

    local journeyMap = SafeStatus(lines, "JourneyMap", MS.MapView, "GetStatus")

    Section(lines, "JOURNEY MAP")
    Field(lines, "JourneyMap.support", journeyMap and journeyMap.support)
    Field(lines, "JourneyMap.supported", journeyMap and journeyMap.supported)
    Field(lines, "JourneyMap.engine", journeyMap and journeyMap.engine)
    Field(lines, "JourneyMap.blizzardModule", journeyMap and journeyMap.blizzardModule)
    Field(lines, "JourneyMap.independent", journeyMap and journeyMap.independent)
    Field(lines, "JourneyMap.nativeWorldMapShownAtOpen", journeyMap and journeyMap.nativeWorldMapShownAtOpen)
    Field(lines, "JourneyMap.frame", journeyMap and journeyMap.frame)
    Field(lines, "JourneyMap.view", journeyMap and journeyMap.view)
    Field(lines, "JourneyMap.mapID", journeyMap and journeyMap.mapID)
    Field(lines, "JourneyMap.mapName", journeyMap and journeyMap.mapName)
    Field(lines, "JourneyMap.mapType", journeyMap and journeyMap.mapType)
    Field(lines, "JourneyMap.mode", journeyMap and journeyMap.mode)
    for _, name in ipairs({ "rawPlayerMapID", "rawPlayerMapName", "canonicalPlayerMapID",
        "canonicalPlayerMapName", "displayedMapID", "followPlayer", "lastAutoMapChangeReason",
        "autoMapChanges", "manualMapChanges" }) do
        Field(lines, "JourneyMap." .. name, journeyMap and journeyMap[name])
    end
    for _, name in ipairs({ "HERE", "OFF_REGION", "AMBIGUOUS", "UNKNOWN" }) do
        Field(lines, "questDisplayRelation." .. name, journeyMap and journeyMap["questDisplayRelation." .. name])
    end
    Field(lines, "playerTargetAngle", journeyMap and journeyMap.playerTargetAngle)
    Field(lines, "JourneyMap.navigation", journeyMap and journeyMap.navigation)
    Field(lines, "JourneyMap.breadcrumbDepth", journeyMap and journeyMap.breadcrumbDepth)
    Field(lines, "JourneyMap.childCount", journeyMap and journeyMap.childCount)
    Field(lines, "JourneyMap.artSource", journeyMap and journeyMap.artSource)
    Field(lines, "JourneyMap.backgroundAtlas", journeyMap and journeyMap.backgroundAtlas)
    Field(lines, "JourneyMap.artTiles", journeyMap and journeyMap.artTiles)
    Field(lines, "JourneyMap.missingTiles", journeyMap and journeyMap.missingTiles)
    Field(lines, "JourneyMap.artFallback", journeyMap and journeyMap.artFallback)
    Field(lines, "JourneyMap.renderRect", journeyMap and journeyMap.renderRect)
    Field(lines, "JourneyMap.selectedPinGlow", journeyMap and journeyMap.selectedPinGlow)
    Field(lines, "JourneyMap.mapPanelRect", journeyMap and journeyMap.mapPanelRect)
    Field(lines, "JourneyMap.canvasMargin", journeyMap and journeyMap.canvasMargin)
    Field(lines, "JourneyMap.playerPin", journeyMap and journeyMap.playerPin)
    Field(lines, "JourneyMap.playerPinCount", journeyMap and journeyMap.playerPinCount)
    Field(lines, "JourneyMap.playerPosition", journeyMap and journeyMap.playerPosition)
    for _, name in ipairs({ "playerFacingSupported", "playerFacing", "playerDisplayAngle",
        "playerArrowRotationOffset", "playerFallbackVisible", "playerPinBackgroundVisible" }) do
        Field(lines, name, journeyMap and journeyMap[name])
    end
    for _, name in ipairs({ "supported", "textureCount", "source", "error", "shape" }) do
        Field(lines, "exploration." .. name, journeyMap and journeyMap["exploration." .. name])
    end
    for _, name in ipairs({ "source", "nativeCount", "activeObjectiveCount", "turnInCount", "genericCount" }) do
        Field(lines, "questPOI." .. name, journeyMap and journeyMap["questPOI." .. name])
    end
    Field(lines, "GetQuestPOIs.entryShape", journeyMap and journeyMap["GetQuestPOIs.entryShape"])
    for index = 1, math.min(8, #(journeyMap and journeyMap["GetQuestPOIs.entries"] or {})) do
        Field(lines, "GetQuestPOIs.entry." .. index, journeyMap["GetQuestPOIs.entries"][index])
    end
    Field(lines, "QuestPOIGetIconInfo.shape", journeyMap and journeyMap["QuestPOIGetIconInfo.shape"])
    for _, name in ipairs({ "available", "pinCount", "matches", "scanned", "error" }) do
        Field(lines, "nativeCalibration." .. name, journeyMap and journeyMap["nativeCalibration." .. name])
    end
    for index = 1, math.min(8, #(journeyMap and journeyMap["nativeCalibration.examples"] or {})) do
        Field(lines, "nativeCalibration.pin." .. index, journeyMap["nativeCalibration.examples"][index])
    end
    for _, name in ipairs({ "visibleQuestSource", "visibleMapQuestStatus", "visibleMapQuestEntries",
        "visibleJourneyPins", "nativeMapQuestEntries", "journeyRenderedQuestPins", "poiStateRestored",
        "sourceSelection.nativeCount", "sourceSelection.legacyCount", "sourceSelection.headerCount",
        "legacyUpdate.available", "legacyUpdate.status", "legacyUpdate.changed", "legacyUpdate.questID",
        "legacyUpdate.mapID", "legacyUpdate.before", "legacyUpdate.after",
        "legacyBeforeUpdate", "legacyAfterUpdate", "legacyUpdateChanged", "nativeCalibration.mapID" }) do
        Field(lines, name, journeyMap and journeyMap[name])
    end
    for index, example in ipairs(journeyMap and journeyMap.sourceComparison or {}) do
        if index > 12 then break end
        Field(lines, "sourceComparison." .. index, example)
    end
    Field(lines, "nativeExclusions.count", #(journeyMap and journeyMap.nativeExclusions or {}))
    for index, exclusion in ipairs(journeyMap and journeyMap.nativeExclusions or {}) do
        Field(lines, "nativeExclusion." .. index, exclusion)
    end
    Field(lines, "JourneyMap.questSource", journeyMap and journeyMap.questSource)
    Field(lines, "JourneyMap.questPins", journeyMap and journeyMap.questPins)
    Field(lines, "JourneyMap.availablePins", journeyMap and journeyMap.availablePins)
    Field(lines, "JourneyMap.progressPins", journeyMap and journeyMap.progressPins)
    Field(lines, "JourneyMap.turnInPins", journeyMap and journeyMap.turnInPins)
    Field(lines, "JourneyMap.unknownPins", journeyMap and journeyMap.unknownPins)
    Field(lines, "JourneyMap.questPinStates", journeyMap and journeyMap.questPinStates)
    Field(lines, "JourneyMap.availableQuests", journeyMap and journeyMap.availableQuests)
    Field(lines, "JourneyMap.inProgressQuests", journeyMap and journeyMap.inProgressQuests)
    Field(lines, "JourneyMap.readyToTurnInQuests", journeyMap and journeyMap.readyToTurnInQuests)
    Field(lines, "JourneyMap.unknownStateQuests", journeyMap and journeyMap.unknownStateQuests)
    Field(lines, "JourneyMap.hereQuests", journeyMap and journeyMap.hereQuests)
    Field(lines, "JourneyMap.offRegionQuests", journeyMap and journeyMap.offRegionQuests)
    Field(lines, "JourneyMap.unlocatedQuests", journeyMap and journeyMap.unlocatedQuests)
    Field(lines, "JourneyMap.ambiguousQuests", journeyMap and journeyMap.ambiguousQuests)
    Field(lines, "JourneyMap.questLocationConfidence", journeyMap and journeyMap.questLocationConfidence)
    Field(lines, "JourneyMap.questLocationSources", journeyMap and journeyMap.questLocationSources)
    Field(lines, "JourneyMap.questStateSources", journeyMap and journeyMap.questStateSources)
    Field(lines, "JourneyMap.questProgressSupported", journeyMap and journeyMap.questProgressSupported)
    Field(lines, "JourneyMap.questsWithProgress", journeyMap and journeyMap.questsWithProgress)
    Field(lines, "JourneyMap.questProgressExample", journeyMap and journeyMap.questProgressExample)
    Field(lines, "JourneyMap.waypointShape", journeyMap and journeyMap.waypointShape)
    Field(lines, "JourneyMap.waypointForMapShape", journeyMap and journeyMap.waypointForMapShape)
    Field(lines, "JourneyMap.taskLocationShape", journeyMap and journeyMap.taskLocationShape)
    Field(lines, "JourneyMap.taskZoneShape", journeyMap and journeyMap.taskZoneShape)
    Field(lines, "JourneyMap.readyForTurnInShape", journeyMap and journeyMap.readyForTurnInShape)
    Field(lines, "JourneyMap.isCompleteShape", journeyMap and journeyMap.isCompleteShape)
    Field(lines, "JourneyMap.questUiMapShape", journeyMap and journeyMap.questUiMapShape)
    Field(lines, "JourneyMap.questPOIMapID", journeyMap and journeyMap.questPOIMapID)
    Field(lines, "JourneyMap.objectiveShape", journeyMap and journeyMap.objectiveShape)
    Field(lines, "JourneyMap.questDataErrors", journeyMap and journeyMap.questDataErrors)
    for _, name in ipairs({ "status", "mapsScanned", "legacyMapsScanned", "iconCalls", "questMatches", "coordinateMatches",
        "headerMatches", "ambiguous", "unknown", "originalPoiMap", "restoredPoiMap",
        "poiStateRestored", "lastBuildReason", "lastError", "legacyShape", "legacyEntryShape",
        "iconShape", "iconReturnShape",
        "mapListShape" }) do
        Field(lines, "questMapIndex." .. name, journeyMap and journeyMap["questMapIndex." .. name])
    end
    Field(lines, "pinRenderer", journeyMap and journeyMap.pinRenderer)
    for _, kind in ipairs({ "available", "inProgress", "inProgressBase", "ready", "player" }) do
        for _, field in ipairs({ "type", "value", "source", "validated" }) do
            local key = "pinAssets." .. kind .. "." .. field
            Field(lines, key, journeyMap and journeyMap[key])
        end
    end
    Field(lines, "unicodePinGlyphs", journeyMap and journeyMap.unicodePinGlyphs)
    Field(lines, "playerPinRenderer", journeyMap and journeyMap.playerPinRenderer)
    Field(lines, "questPinRenderer", journeyMap and journeyMap.questPinRenderer)
    Field(lines, "progressOverlay", journeyMap and journeyMap.progressOverlay)
    Field(lines, "JourneyMap.uiTextScale", journeyMap and journeyMap.uiTextScale)
    Field(lines, "JourneyMap.sessionJournalWidth", journeyMap and journeyMap.sessionJournalWidth)
    for index = 1, math.min(8, #(journeyMap and journeyMap.questExamples or {})) do
        Field(lines, "JourneyMap.questExample." .. index, journeyMap.questExamples[index])
    end
    Field(lines, "JourneyMap.questFallback", journeyMap and journeyMap.questFallback)
    Field(lines, "JourneyMap.playerTicker", journeyMap and journeyMap.playerTicker)
    Field(lines, "JourneyMap.error", journeyMap and journeyMap.error or "none")

    Section(lines, "JOURNEY WORKSPACE")
    local journey = SafeStatus(lines, "Journey", MS.JourneyWorkspace, "GetStatus")
    Field(lines, "JourneyUI.themeVersion", MS.JourneyUIStyle and MS.JourneyUIStyle.version)
    Field(lines, "JourneyUI.layoutVariant", journey and journey.responsiveMode)
    Field(lines, "JourneyUI.textScale", journey and journey.uiTextScale)
    Field(lines, "JourneyUI.contextVisible", MS.JourneyContextPanel and MS.JourneyContextPanel.visible)
    Field(lines, "JourneyUI.sessionJournalExpanded", MS.JourneySessionJournal and MS.JourneySessionJournal.expanded)
    for _, name in ipairs({ "active", "view", "error", "sessionActive", "sessionDuration",
        "sessionEvents", "xpGained", "xpPerHour", "etaNextLevel",
        "questCount", "completedQuestCount", "bagFree", "bagTotal",
        "mapSupported", "inventorySupported", "responsiveMode", "uiTextScale",
        "sessionJournalWidth", "mapMainWidth" }) do
        Field(lines, name, journey and journey[name])
    end
    for _, spec in ipairs({ { "QuestView", "questView" }, { "InventoryView", "inventoryView" }, { "MapView", "mapView" } }) do
        local state = journey and journey[spec[2]] or {}
        for _, key in ipairs({ "visible", "dirty", "refreshCount", "deferredRefreshCount",
            "questModelRefreshCount", "questModelCoalescedCount" }) do
            if state[key] ~= nil then Field(lines, spec[1] .. "." .. key, state[key]) end
        end
    end
    for _, spec in ipairs({
        { "Inventory", "inventory", { "active", "visible", "dirty", "refreshCount",
            "category", "renderedRowCount", "layoutMode", "usedSlots",
            "totalSlots", "freeSlots", "itemCount", "questItemCount", "trackedCount",
            "sessionFindCount", "pendingItemDataCount", "bagListenerRegistered",
            "bagUpdateDelayedCount", "lastBagEvent", "snapshotCount", "lastScanState",
            "lastOwnedDelta", "lastFindingItemID", "merchantDeferred",
            "lastDiffItemCount", "lastPositiveDeltaCount", "lastNegativeDeltaCount",
            "lastCandidateItemID", "lastCandidateBagsBefore", "lastCandidateBagsAfter",
            "lastCandidateOwnedBefore", "lastCandidateOwnedAfter",
            "lastCandidateDecision", "lastCandidateReason" } },
        { "JourneyMemory", "memory", { "schema", "maxLevel", "zoneCount", "questCount", "totalQuestTurnIns",
            "sessionCount", "milestoneCount", "openSession", "lastMilestoneType", "lastVisitMapID",
            "lastVisitMapType", "filteredNonVisitMaps", "invalidEntriesCleaned", "chainCompletion" } },
        { "ProgressionView", "progressionView", { "visible", "dirty", "refreshCount",
            "milestoneCount", "zoneCount", "sessionCount", "questCount" } },
        { "ContextPanel", "contextPanel", { "type", "questID", "refreshCount", "descriptionSupport" } },
        { "SessionJournal", "sessionJournal", { "eventCount", "sessionQuestTurnIns", "zonesVisited", "expanded", "compact" } },
        { "Settings", "settings", { "textScale", "sessionJournalWidth", "showQuestProgressBars", "followPlayerOnStart" } },
    }) do
        local state = journey and journey[spec[2]] or {}
        for _, key in ipairs(spec[3]) do Field(lines, spec[1] .. "." .. key, state[key]) end
    end
    Field(lines, "mapDestination", journeyMap and journeyMap.destination)

    Section(lines, "PERFORMANCE")
    local perf = SafeStatus(lines, "Performance", MS.PerformanceAudit, "GetSummary")
    Field(lines, "samplerActive", perf and perf.active)
    Field(lines, "activeLabel", perf and perf.activeLabel or "none")
    Field(lines, "completedRuns", perf and perf.completedRuns)
    Field(lines, "lastRun", perf and perf.lastLabel or "none")
    Field(lines, "lastFpsAvg", perf and Number(perf.lastFpsAvg) or "unavailable")
    self:AppendViewportReport(lines)
    return table.concat(lines, "\n")
end

function MS.Diagnostics:ShowMultiScreenReport()
    local ok, report = pcall(self.BuildMultiScreenReport, self)
    if not ok then report = "=== MULTISCREEN REPORT ===\nreport.diagnosticError=" .. tostring(report) end
    local shown, failure = pcall(self.ShowCopyableReport, self, MS.L.REPORT_TITLE, report, "multiscreen")
    if not shown then self:Print(string.format(MS.L.REPORT_ERROR, tostring(failure))) end
end
