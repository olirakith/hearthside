local MS = _G.MS
-- Setup assistant. States: NEVER_STARTED -> DISPLAY_REQUIRED -> LAYOUT_MIGRATION
-- (VIEWPORT with the previous Journey Edit Mode profile active) -> READY.
-- Journey never prepares, imports, selects or edits Edit Mode layouts.
MS.JourneyOnboarding = { schemaVersion = 1, hooks = {} }
local O = MS.JourneyOnboarding
local function Finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function Signal(code)
    if MS.DiagnosticSnapshots then MS.DiagnosticSnapshots:Signal("onboarding", code) end
end
-- Non-reversible token for diagnostics (never the character key itself).
local function Token(text)
    local hash = 2166136261
    for index = 1, #text do hash = (hash * 16777619 + text:byte(index)) % 4294967296 end
    return string.format("%08x", hash)
end

-- Capture character history before JourneySession creates this login's records.
-- Account preferences or the new onboarding record alone do not prove prior use.
function O:CapturePriorUsers(db)
    if self.priorUsers then return end
    self.priorUsers = {}
    local journey = type(db) == "table" and db.journey
    if type(journey) ~= "table" then return end
    local session = journey.session
    if type(session) == "table" and type(session.character) == "string" then
        self.priorUsers[session.character] = true
    end
    local characters = type(journey.memory) == "table" and journey.memory.characters
    for character, record in pairs(type(characters) == "table" and characters or {}) do
        if type(record) == "table" and (type(record.character) == "table" and Finite(record.character.firstSeenAt)
            or type(record.sessions) == "table" and next(record.sessions) ~= nil) then
            self.priorUsers[character] = true
        end
    end
    local identity = MS.JourneyCharacterIdentity:Resolve()
    if identity.key and (self.priorUsers[identity.legacyKey] or self.priorUsers[identity.fallbackKey]) then
        self.priorUsers[identity.key] = true
    end
end
function O.ClassifyUser(saved, state)
    if saved.origin ~= "MIGRATED_EXISTING_USER" then return "NEW_USER" end
    return state == "READY" and "READY_EXISTING_USER" or "INCOMPLETE_EXISTING_USER"
end

-- Failed readiness predicates are not terminal display decisions: a loaded
-- Companion layout can precede the physical span and all derived frames.
local function DisplayActionReason(layout, status, layoutError, runtime, spanMatches)
    if not layout then
        if status == "MISSING" or status == "INVALID" then return layoutError or status end
        return nil
    end
    if runtime.enabling or runtime.restoring or runtime.closing or runtime.autoEnableScheduled
        or runtime.state == "ENABLING" or runtime.state == "RESTORING"
        or MS.Recovery and MS.Recovery.pending then return nil end
    if runtime.state == "FAILED" then return runtime.lastEnableError or "RUNTIME_FAILED" end
    if runtime.state == "DISABLED" then
        if runtime.lastEnableError then return runtime.lastEnableError end
        if type(runtime.AutoEnableAllowed) == "function" and not runtime:AutoEnableAllowed() then return "AUTO_ENABLE_DISABLED" end
        if spanMatches and runtime.invalidatedReason then return "RUNTIME_INVALIDATED" end
    end
end

-- READY requires every predicate, in this order. Shared with diagnostics.
function O.ReadyPredicates(e)
    return { { name = "displayReady", value = e.displayReady and true or false },
        { name = "layoutCompatible", value = not e.layoutMigration } }
end

-- Pure transition policy: saved progress is intent, never readiness evidence.
function O.Evaluate(saved, e)
    local ready = true
    for _, predicate in ipairs(O.ReadyPredicates(e)) do ready = ready and predicate.value end
    if ready then return "READY" end
    if not saved.started and saved.origin ~= "MIGRATED_EXISTING_USER" and not e.displayReady then return "NEVER_STARTED" end
    if not e.displayReady then return "DISPLAY_REQUIRED" end
    return "LAYOUT_MIGRATION"
end

function O:Initialize()
    local db = MS.Database and MS.Database.data
    local character = MS.JourneySession and MS.JourneySession.data and MS.JourneySession.data.character
    if not db or type(character) ~= "string" or character == "" or character:find("?", 1, true) then return end
    db.journey = type(db.journey) == "table" and db.journey or {}
    local store = db.journey.onboarding
    if type(store) ~= "table" then store = {}; db.journey.onboarding = store end
    -- Unknown future schemas are not downgraded or used to assert readiness.
    if store.schemaVersion ~= nil and store.schemaVersion ~= self.schemaVersion then return end
    store.schemaVersion = self.schemaVersion
    store.characters = type(store.characters) == "table" and store.characters or {}
    self.identity = MS.JourneyCharacterIdentity:Resolve()
    self.identityMigration = MS.JourneyCharacterIdentity:MigrateCharacters(store.characters, self.identity)
    MS.JourneyCharacterIdentity:WarnConflict("ONBOARDING", self.identityMigration)
    if self.identityMigration.status == "CONFLICT" then self.saved, self.character = nil, nil; return end
    local saved = store.characters[character]
    if type(saved) ~= "table" then saved = {}; store.characters[character] = saved end
    for _, key in ipairs({ "started", "acknowledged", "completed" }) do saved[key] = saved[key] == true end
    if saved.origin ~= "NEW_USER" and saved.origin ~= "MIGRATED_EXISTING_USER" then
        saved.origin = self.priorUsers and self.priorUsers[character] and "MIGRATED_EXISTING_USER" or "NEW_USER"
    end
    -- The state is output only (recomputed by Refresh). Values and fields of
    -- earlier versions stay untouched until then, so downgrades keep working.
    if type(saved.state) ~= "string" then saved.state = "NEVER_STARTED" end
    self.saved, self.character = saved, character
    return saved
end

function O:ReadEvidence()
    -- Classifier inputs recorded as they are decided, for read-only diagnostics.
    local d = { complete = false }
    self.diagnosticPredicates = d
    local runtime, workspace, journey = MS.Runtime or {}, MS.Workspace or {}, MS.JourneyWorkspace or {}
    local layout, layoutStatus, layoutError
    if MS.Config then layout, layoutStatus, layoutError = MS.Config:GetLayout() end
    local ok, width, height = false, nil, nil
    if type(GetPhysicalScreenSize) == "function" then ok, width, height = pcall(GetPhysicalScreenSize) end
    local spanMatches = layout and ok and width == layout.span.width and height == layout.span.height or false
    local workspaceReady = workspace.frame and workspace.frame:IsShown() and journey.active == true or false
    local displayReady = layout ~= nil and spanMatches and runtime.state == "ACTIVE" and runtime.enabled == true
        and not runtime.restoring and not runtime.closing and not runtime.invalidatedReason and workspaceReady or false
    local watch = MS.EditModeWatch or {}
    local editing = type(watch.IsEditModeShown) == "function" and watch:IsEditModeShown() or false
    local layoutMigration = watch.state == "NEEDED"
    local displayActionReason = not displayReady and DisplayActionReason(layout, layoutStatus, layoutError, runtime, spanMatches) or nil
    d.layoutReady, d.spanMatches = layout ~= nil, spanMatches == true
    d.runtimeActive, d.runtimeEnabled = runtime.state == "ACTIVE", runtime.enabled == true
    d.runtimeSettled = not runtime.restoring and not runtime.closing and not runtime.invalidatedReason
    d.workspaceShown = workspace.frame and workspace.frame:IsShown() and true or false
    d.journeyActive, d.workspaceReady, d.displayReady = journey.active == true, workspaceReady, displayReady
    d.layoutStatus, d.displayActionReason = layoutStatus, displayActionReason
    d.displayActionRequired = displayActionReason ~= nil
    d.layoutMigration, d.editing = layoutMigration, editing
    d.complete = true
    local combat = type(InCombatLockdown) == "function" and InCombatLockdown() or false
    return { layoutReady = layout ~= nil, spanMatches = spanMatches, displayReady = displayReady,
        displayActionRequired = displayActionReason ~= nil, gameReady = displayReady, workspaceReady = displayReady,
        editing = editing, combat = combat, layoutMigration = layoutMigration,
        layoutName = watch.active and watch.active.name or nil,
        canEnable = spanMatches and not combat and not editing
            and (runtime.state == "DISABLED" or runtime.state == "FAILED") and not runtime.closing
            and not runtime.restoring and not (MS.Recovery and MS.Recovery.pending),
        canReload = not combat and not editing and runtime.state ~= "ENABLING" and runtime.state ~= "RESTORING"
            and not runtime.restoring and not (MS.Recovery and MS.Recovery.pending) }
end

function O:Refresh()
    if not self:Initialize() then return end
    local ok, e = pcall(self.ReadEvidence, self)
    if not ok then e = { displayReady = false } end
    local state = self.Evaluate(self.saved, e)
    self.saved.state, self.evidence = state, e
    self.saved.userKind = self.ClassifyUser(self.saved, state)
    e.existingUser = self.saved.origin == "MIGRATED_EXISTING_USER"
    if state == "READY" or e.displayReady or e.existingUser then self.saved.started = true end
    if state == "READY" then self.saved.completed = true end
    self:TrySettleStartup()
    -- Completion prompts may recur after an actual readiness regression.
    if self.startupSettled and not e.editing and state ~= "READY" then
        self.saved.acknowledged, self.saved.completed = false, false
    end
    if MS.JourneyOnboardingView then MS.JourneyOnboardingView:Refresh() end
    Signal("REFRESH")
    return state, e
end
function O:Begin()
    if not self:Initialize() then return end
    self.saved.started = true
    return self:Refresh()
end
function O:Finish()
    local state = self:Refresh()
    if state ~= "READY" then return false end
    self.saved.acknowledged = true
    return true
end
function O:RetryDisplay()
    local _, e = self:Refresh()
    if not e then return end
    if e.canEnable then MS.Runtime:Enable() end
    if MS.EditModeWatch then MS.EditModeWatch:Refresh("ONBOARDING_RECHECK") end
    return self:Refresh()
end
function O:ReloadInterface()
    local _, e = self:Refresh()
    if e and not e.displayReady and e.canReload and type(ReloadUI) == "function" then
        ReloadUI()
        return true
    end
    return false
end
function O:OpenDiagnostic()
    if MS.JourneyOnboardingView then MS.JourneyOnboardingView:Close() end
    if MS.JourneyWorkspace and MS.JourneyWorkspace.active then MS.JourneyWorkspace:SelectView("SETTINGS") end
    if MS.PlayerDiagnostic then MS.PlayerDiagnostic:Open() end
end
function O:Open()
    if self:Refresh() and MS.JourneyOnboardingView then MS.JourneyOnboardingView:Open() end
end

-- A playable world is not proof that Journey has finished initializing: latch
-- once the runtime has reached a decision outside any transition.
function O:TrySettleStartup()
    if self.startupSettled or not self.startupRuntimeObserved then return end
    local runtime = MS.Runtime or {}
    if runtime.enabling or runtime.restoring or runtime.closing or runtime.autoEnableScheduled
        or runtime.state == "ENABLING" or runtime.state == "RESTORING"
        or MS.Recovery and MS.Recovery.pending then return end
    if runtime.state ~= "ACTIVE" and runtime.state ~= "DISABLED" and runtime.state ~= "FAILED" then return end
    self.startupSettled = true
end
function O:ScheduleRefresh()
    if self.refreshScheduled then return end
    local function Refresh()
        self.refreshScheduled = false
        self:Refresh()
        self:MaybeOpen()
    end
    if C_Timer and type(C_Timer.After) == "function" then
        self.refreshScheduled = true
        C_Timer.After(0, Refresh)
    else Refresh() end
end
-- Presentation-only lifecycle gate. It neither classifies users nor asserts readiness.
-- Returns the first blocking condition, or nil when presentation is allowed.
function O:AutoPresentBlocker()
    if not self.worldEntered then return "WORLD_NOT_ENTERED" end
    if self.loadingScreen ~= false then return "LOADING_SCREEN" end
    if self.cinematicActive then return "CINEMATIC_ACTIVE" end
    for _, name in ipairs({ "InCinematic", "IsPlayerInWorld" }) do
        local query = _G[name]
        if type(query) == "function" then
            local ok, value = pcall(query)
            if not ok then return "QUERY_FAILED_" .. string.upper(name) end
            if name == "InCinematic" and value then return "IN_CINEMATIC" end
            if name == "IsPlayerInWorld" and not value then return "NOT_IN_WORLD" end
        end
    end
    for _, name in ipairs({ "CinematicFrame", "MovieFrame" }) do
        local frame = _G[name]
        if frame and frame:IsShown() then return string.upper(name) .. "_SHOWN" end
    end
end
function O:CanAutoPresent() return self:AutoPresentBlocker() == nil end
-- Decision gates in evaluation order; the code is kept as diagnostic evidence.
function O:PresentationBlocker()
    if not self.startupSettled then return "STARTUP_NOT_SETTLED" end
    if self.autoPresented then return "ALREADY_PRESENTED" end
    if self.sessionClosed then return "SESSION_CLOSED" end
    if not self.saved or not self.evidence then return "NOT_CLASSIFIED" end
    local lifecycle = self:AutoPresentBlocker()
    if lifecycle then return lifecycle end
    if self.evidence.combat then return "COMBAT" end
    if self.evidence.editing then return "EDITING" end
    if not self.evidence.displayReady and not self.evidence.displayActionRequired then return "WAITING_DISPLAY_TRANSIENT" end
    if self.saved.completed and self.saved.state == "READY" then return "COMPLETED" end
    if self.saved.acknowledged and self.saved.state == "READY" then return "ACKNOWLEDGED" end
end
function O:MaybeOpen()
    local blocker = self:PresentationBlocker()
    self.presentationDecision = blocker or "PRESENTED"
    if not blocker then
        self.autoPresented = true
        if MS.JourneyOnboardingView then MS.JourneyOnboardingView:Open() end
    end
    Signal("PRESENTATION")
end

-- Read-only developer snapshot of cached classifier output; never re-reads evidence.
function O:GetDiagnosticSnapshot()
    local saved, e, view = self.saved, self.evidence, MS.JourneyOnboardingView or {}
    local session = MS.JourneySession and MS.JourneySession.data and MS.JourneySession.data.character
    local db = MS.Database and MS.Database.data
    local store = type(db) == "table" and type(db.journey) == "table" and db.journey.onboarding
    local characters = 0
    for _ in pairs(type(store) == "table" and type(store.characters) == "table" and store.characters or {}) do characters = characters + 1 end
    local result = { schema = 2, initialized = saved ~= nil,
        character = { token = type(self.character) == "string" and Token(self.character) or nil,
            matchesSession = self.character ~= nil and self.character == session,
            priorUser = self.priorUsers and self.character and self.priorUsers[self.character] == true or false,
            recordsInStore = characters },
        startup = { worldEntered = self.worldEntered, loadingScreen = self.loadingScreen, cinematicActive = self.cinematicActive == true,
            runtimeObserved = self.startupRuntimeObserved == true, refreshScheduled = self.refreshScheduled == true,
            settled = self.startupSettled == true },
        presentation = { decision = self.presentationDecision or "NOT_EVALUATED", autoPresented = self.autoPresented == true,
            displayReason = e and (e.displayReady and "DISPLAY_READY" or e.displayActionRequired and "DISPLAY_ACTION_REQUIRED"
                or "WAITING_DISPLAY_TRANSIENT") or "NOT_CLASSIFIED",
            sessionClosed = self.sessionClosed == true, lifecycleBlocker = self:AutoPresentBlocker() or "NONE" },
        view = { shown = view.frame and view.frame:IsShown() and true or false,
            renderedState = view.renderedState, renderedStage = view.renderedStage } }
    if saved then
        result.persisted = { started = saved.started, completed = saved.completed, acknowledged = saved.acknowledged,
            state = saved.state, origin = saved.origin, userKind = saved.userKind }
    end
    if e then
        local ready, failed = {}, {}
        for _, predicate in ipairs(O.ReadyPredicates(e)) do
            ready[#ready + 1] = { name = predicate.name, value = predicate.value }
            if not predicate.value then failed[#failed + 1] = predicate.name end
        end
        local evidence = {}
        for key, value in pairs(e) do if type(value) == "boolean" then evidence[key] = value end end
        result.classifier = { state = saved and saved.state, ready = ready, failed = failed, evidence = evidence }
    end
    local predicates = {}
    for key, value in pairs(type(self.diagnosticPredicates) == "table" and self.diagnosticPredicates or {}) do predicates[key] = value end
    result.predicates = predicates
    return result
end
function O:InstallPresentationHooks()
    -- Natural movie completion does not necessarily emit STOP_MOVIE. OnHide runs
    -- for completion, confirmed skipping and failed playback, after Blizzard restores UI.
    local movie = _G.MovieFrame
    if movie and type(movie.HookScript) == "function" and self.movieFrameHook ~= movie then
        local ok = pcall(movie.HookScript, movie, "OnHide", function() self:ScheduleRefresh() end)
        if ok then self.movieFrameHook = movie end
    end
end
-- Posthooks on Journey's own tables only (and MovieFrame's OnHide above).
function O:Install()
    self:InstallPresentationHooks()
    if type(hooksecurefunc) ~= "function" then return end
    local function Hook(object, method, after)
        if not object or type(object[method]) ~= "function" then return end
        self.hooks[object] = self.hooks[object] or {}
        if self.hooks[object][method] then return end
        self.hooks[object][method] = pcall(hooksecurefunc, object, method, function()
            if after then after() end
            pcall(self.ScheduleRefresh, self)
        end)
    end
    local database = MS.Database
    if database and not self.databaseHook and type(database.Initialize) == "function" then
        self.databaseHook = pcall(hooksecurefunc, database, "Initialize", function()
            O:CapturePriorUsers(database.data)
        end)
    end
    local function RuntimeObserved() self.startupRuntimeObserved = true end
    -- ConsiderAutoEnable also completes the no-configuration/disabled path:
    -- genuine new installs must still reach Welcome or display support.
    for _, method in ipairs({ "ConsiderAutoEnable", "CompleteEnable", "FailEnable" }) do
        Hook(MS.Runtime, method, RuntimeObserved)
    end
    for _, method in ipairs({ "QueueRestore", "RequestFailSafeDisable" }) do Hook(MS.Runtime, method) end
    Hook(MS.Recovery, "Restore")
    Hook(MS.Workspace, "Show")
    Hook(MS.JourneyWorkspace, "Start")
    Hook(MS.EditModeWatch, "Refresh")
end
if type(CreateFrame) == "function" then
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
        "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "ADDON_LOADED",
        "CINEMATIC_START", "CINEMATIC_STOP", "PLAY_MOVIE", "STOP_MOVIE",
        "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "PLAYER_LEAVING_WORLD", "PLAYER_CONTROL_GAINED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event)
        O:Install()
        if event == "PLAYER_ENTERING_WORLD" then O.worldEntered = true
        elseif event == "PLAYER_LEAVING_WORLD" then O.worldEntered = false
        elseif event == "LOADING_SCREEN_ENABLED" then O.loadingScreen = true
        elseif event == "LOADING_SCREEN_DISABLED" then O.loadingScreen = false
        elseif event == "CINEMATIC_START" then O.cinematicActive = true
        elseif event == "CINEMATIC_STOP" then O.cinematicActive = false end
        if event == "PLAYER_LOGIN" then
            O.worldEntered, O.loadingScreen = false, true
            if MS.JourneyOnboardingView then MS.JourneyOnboardingView:RegisterSettings() end
            O:ScheduleRefresh()
        elseif event == "ADDON_LOADED" then
            if MS.JourneyOnboardingView then MS.JourneyOnboardingView:RegisterSettings() end
        else O:ScheduleRefresh() end
    end)
    O.frame = frame
end
if MS.Database and MS.Database.data then O:CapturePriorUsers(MS.Database.data) end
O:Install()
