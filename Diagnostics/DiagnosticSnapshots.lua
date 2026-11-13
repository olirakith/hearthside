local MS = _G.MS

-- Read-only snapshots for the optional developer console (AzerothJourney_Dev).
-- Getters copy cached production state into plain values. They never refresh,
-- measure, acquire, apply layouts, change frames or write SavedVariables.
MS.DiagnosticSnapshots = { schema = 1, signal = "AzerothJourney.Diagnostics",
    EditMode = {}, Display = {}, Surfaces = {}, Pixel = {}, Lifecycle = {} }
local S = MS.DiagnosticSnapshots

-- Listener-free change notice. Without a subscriber this is a table lookup.
function S:Signal(domain, code)
    local registry = _G.EventRegistry
    if type(registry) == "table" and type(registry.TriggerEvent) == "function" then
        pcall(registry.TriggerEvent, registry, self.signal, domain, code)
    end
end

local function Number(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge and value or nil
end
local function Rect(r)
    if type(r) ~= "table" then return nil end
    return { x = Number(r.x), y = Number(r.y), width = Number(r.width), height = Number(r.height) }
end
-- Native values keep their exact shape: nil and failures are explicit markers.
local function Raw(ok, value)
    if not ok then return "ERROR" end
    if value == nil then return "NIL" end
    if type(value) == "boolean" or Number(value) then return value end
    return "TYPE_" .. string.upper(type(value))
end
local function Query(object, method)
    if type(object) ~= "table" or type(object[method]) ~= "function" then return "UNAVAILABLE" end
    return Raw(pcall(object[method], object))
end
local function Code(value)
    -- Whole upper-case codes only; exception text may contain paths or names.
    if value == nil then return nil end
    local code = type(value) == "string" and string.match(value, "^[A-Z][A-Z0-9_]+") or nil
    local rest = code and string.sub(value, #code + 1, #code + 1)
    return code and (rest == "" or rest == ":" or rest == " ") and code or "DETAIL_OMITTED"
end
local function LayoutKind(layoutType)
    local types = type(_G.Enum) == "table" and _G.Enum.EditModeLayoutType or {}
    if layoutType == nil then return nil end
    if layoutType == types.Preset then return "PRESET" end
    if layoutType == types.Account then return "ACCOUNT" end
    if layoutType == types.Character then return "CHARACTER" end
    return "UNKNOWN"
end
local function PlayerData()
    local diagnostic = MS.PlayerDiagnostic
    if not diagnostic or type(diagnostic.Read) ~= "function" then return nil end
    local ok, data = pcall(diagnostic.Read, diagnostic)
    return ok and type(data) == "table" and data or nil
end

function S.EditMode:GetDiagnosticSnapshot()
    local watch, mode, onboarding = MS.EditModeWatch or {}, MS.UIParentMode or {}, MS.JourneyOnboarding or {}
    local predicates = type(onboarding.diagnosticPredicates) == "table" and onboarding.diagnosticPredicates or {}
    local active = type(watch.active) == "table" and watch.active or nil
    -- Layout names stay out of snapshots: only the layout kind is reported.
    return { schema = 2,
        mode = { mode = mode.mode, reason = Code(mode.reason) },
        watch = { state = watch.state, journeyProfile = watch.journeyProfileActive == true, editing = watch.editing == true,
            refreshCount = Number(watch.refreshCount),
            lastSignal = type(watch.lastSignal) == "string" and #watch.lastSignal <= 64 and watch.lastSignal or nil },
        active = active and { kind = LayoutKind(active.layoutType), custom = active.custom == true } or nil,
        onboarding = { layoutMigration = predicates.layoutMigration == true, editing = predicates.editing == true },
        uiParentHeight = Number(Query(_G.UIParent, "GetHeight")), uiParentScale = Number(Query(_G.UIParent, "GetEffectiveScale")) }
end

function S.Display:GetDiagnosticSnapshot()
    local runtime, workspace, journey = MS.Runtime or {}, MS.Workspace or {}, MS.JourneyWorkspace or {}
    local contracts = MS.GameSurfaceContract or {}
    local contract = type(contracts.Get) == "function" and contracts:Get() or nil
    local layout, status, layoutError
    if MS.Config and type(MS.Config.GetLayout) == "function" then layout, status, layoutError = MS.Config:GetLayout() end
    local ok, width, height = false, nil, nil
    if type(GetPhysicalScreenSize) == "function" then ok, width, height = pcall(GetPhysicalScreenSize) end
    local world = {}
    if _G.WorldFrame and type(_G.WorldFrame.GetRect) == "function" then
        local read, x, y, w, h = pcall(_G.WorldFrame.GetRect, _G.WorldFrame)
        if read then world = { x = Number(x), y = Number(y), width = Number(w), height = Number(h) } end
    end
    local function Measure(frame, method)
        if not frame or type(frame[method]) ~= "function" then return nil end
        local read, value = pcall(frame[method], frame)
        return read and Number(value) or nil
    end
    local shown = workspace.frame and Raw(pcall(workspace.frame.IsShown, workspace.frame)) or false
    local safety = contract and contract.safety
    local viewport = MS.Viewport or {}
    local last = type(viewport.lastLifecycle) == "table" and viewport.lastLifecycle or nil
    return { schema = 2,
        layout = { status = layout and status or layoutError or status or "UNAVAILABLE",
            span = layout and { width = Number(layout.span.width), height = Number(layout.span.height) } or nil,
            game = layout and Rect(layout.game) or nil, workspace = layout and Rect(layout.workspace) or nil },
        physical = { width = ok and Number(width) or nil, height = ok and Number(height) or nil,
            spanMatches = layout ~= nil and ok and width == layout.span.width and height == layout.span.height or false },
        contract = { version = contracts.version, generation = Number(contracts.generation), ready = contract ~= nil,
            uiRect = contract and Rect(contract.uiRect), physicalRect = contract and Rect(contract.physicalRect),
            workspaceRect = contract and Rect(contract.workspaceRect), screenRect = contract and Rect(contract.screenRect),
            uiScale = contract and Number(contract.uiScale),
            effectiveScale = contract and Number(contract.effectiveScale), runtimeToken = contract and contract.runtimeToken,
            validTopology = safety and safety.validTopology == true or false,
            anchorMatches = safety and safety.anchorMatches == true or false },
        runtime = { state = runtime.state, enabled = runtime.enabled == true, enabling = runtime.enabling == true,
            restoring = runtime.restoring == true, closing = runtime.closing == true,
            invalidatedReason = Code(runtime.invalidatedReason), lastEnableStage = runtime.lastEnableStage,
            lastClosureError = Code(runtime.lastClosureError), enableGeneration = Number(runtime.enableGeneration),
            autoEnableTriggered = runtime.autoEnableTriggered == true, autoEnableScheduled = runtime.autoEnableScheduled == true,
            failSafeRequested = runtime.failSafeRequested == true, recoveryPending = MS.Recovery and MS.Recovery.pending == true or false },
        workspace = { created = workspace.frame ~= nil, shown = shown, uiRect = Rect(workspace.uiRect),
            physicalRect = Rect(workspace.physicalRect), journeyActive = journey.active == true,
            view = journey.view, error = Code(journey.lastError) },
        viewport = { originalCaptured = viewport.original ~= nil, pendingLifecycle = viewport.pendingLifecycle,
            lastLifecycle = last and { signal = last.signal, state = last.state, reason = Code(last.reason),
                contractGeneration = Number(last.contractGeneration) } or nil },
        frames = { worldFrame = world, uiParentWidth = Measure(_G.UIParent, "GetWidth"),
            uiParentHeight = Measure(_G.UIParent, "GetHeight"), uiParentScale = Measure(_G.UIParent, "GetEffectiveScale") } }
end

function S.Surfaces:GetDiagnosticSnapshot()
    local player, viewport = PlayerData(), MS.UIParentViewport or {}
    local diagnostic = MS.PlayerDiagnostic or {}
    local health, reason
    if player and type(diagnostic.Health) == "function" then
        local ok, value, detail = pcall(diagnostic.Health, diagnostic, player)
        if ok then health, reason = value, detail end
    end
    local accepted = {}
    for id, value in pairs(type(diagnostic.acceptedLimitations) == "table" and diagnostic.acceptedLimitations or {}) do accepted[id] = value end
    return { schema = 2, available = player ~= nil, acceptedLimitations = accepted,
        limitationsVersion = Number(diagnostic.limitationsVersion), health = health or "UNAVAILABLE", healthReason = reason,
        viewport = { state = viewport.state, applies = Number(viewport.applyCount), restores = Number(viewport.restoreCount) },
        mode = player and player.mode or nil }
end

function S.Pixel:GetDiagnosticSnapshot()
    local diagnostic, ph = MS.PlayerDiagnostic, MS.PixelHandshake or {}
    local read = diagnostic and type(diagnostic.ReadPixelTransport) == "function"
        and select(2, pcall(diagnostic.ReadPixelTransport, diagnostic)) or nil
    if type(read) ~= "table" then return { schema = 1, available = false } end
    local reasons = {}
    for name, value in pairs(type(ph.REASON) == "table" and ph.REASON or {}) do reasons[value] = name end
    read.schema, read.available = 1, true
    read.started, read.heartbeat, read.cellSize = ph.started == true, Number(ph.HEARTBEAT), Number(ph.CELL_SIZE)
    read.leavingReason = ph.message == ph.TYPE_LEAVING and reasons[ph.reason] or nil
    read.intentPending = ph.intentDeadline ~= nil
    return read
end

-- Correlation context only: existing engine and onboarding lifecycle flags.
function S.Lifecycle:GetDiagnosticSnapshot()
    local runtime, onboarding, ph = MS.Runtime or {}, MS.JourneyOnboarding or {}, MS.PixelHandshake or {}
    local reasons = {}
    for name, value in pairs(type(ph.REASON) == "table" and ph.REASON or {}) do reasons[value] = name end
    return { schema = 1, productionLoaded = true, addon = MS.addonName,
        runtime = { state = runtime.state, enabled = runtime.enabled == true, enableGeneration = Number(runtime.enableGeneration),
            autoEnableTriggered = runtime.autoEnableTriggered == true },
        startup = { worldEntered = onboarding.worldEntered, loadingScreen = onboarding.loadingScreen,
            cinematicActive = onboarding.cinematicActive == true, runtimeObserved = onboarding.startupRuntimeObserved == true,
            settled = onboarding.startupSettled == true },
        exit = { message = ph.message == ph.TYPE_LEAVING and "LEAVING" or ph.message == ph.TYPE_READY and "READY" or "NONE",
            reason = ph.message == ph.TYPE_LEAVING and reasons[ph.reason] or nil },
        combat = type(InCombatLockdown) == "function" and Raw(pcall(InCombatLockdown)) or "UNAVAILABLE",
        editing = MS.EditModeWatch and MS.EditModeWatch.editing == true or false }
end
