local MS = _G.MS

MS.Runtime = { enabled = false, enabling = false, enableGeneration = 0,
    invalidatedReason = nil, state = "DISABLED", restoring = false,
    restoreCount = 0, restoreTransactions = 0, restoreAttempts = 0,
    failSafeDisableCount = 0 }

function MS.Runtime:RecordStep(name)
    self.appliedSteps = self.appliedSteps or {}
    self.appliedSteps[#self.appliedSteps + 1] = name
    self.lastEnableStage = name
end

function MS.Runtime:QueueRestore(reason)
    if self.state == "RESTORING" then return true, true end
    if self.closing and MS.Recovery and MS.Recovery.pending then return false, nil end
    self.closing, self.enabled, self.enabling = true, false, false
    self.enableGeneration = self.enableGeneration + 1
    local success
    local ran = MS.Recovery:RunOrQueue(function() success = MS.Recovery:Restore(reason) end)
    return ran, success
end

function MS.Runtime:FailEnable(reason)
    if self.state ~= "ENABLING" then return end
    self.enabling = false
    self.enabled = false
    self.lastEnableError = reason
    if InCombatLockdown() then
        self.state = "FAILED"
        self:QueueRestore("enable-failed:" .. tostring(reason))
    else
        MS.Recovery:Restore("enable-failed:" .. tostring(reason))
    end
    MS.Diagnostics:Print(string.format(MS.L.ENABLE_FAILED, MS.L[reason] or MS.L.ERROR_CONFIG))
end

function MS.Runtime:RequestFailSafeDisable(reason)
    if self.state ~= "ACTIVE" and self.state ~= "ENABLING" then return end
    if self.failSafeRequested then return end
    self.failSafeRequested = true
    self.failSafeDisableCount = self.failSafeDisableCount + 1
    self.invalidatedReason = reason
    -- The window left the span: once restored, the exact span size may
    -- auto-enable again. A manual /ms disable never re-arms it.
    if reason == "DISPLAY_SIZE_CHANGED" then self.autoEnableTriggered = false end
    if self.state == "ENABLING" and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        self.closing = true
        local generation = self.enableGeneration
        local scheduled = pcall(C_Timer.After, 0, function()
            if generation ~= self.enableGeneration then return end
            if self.state == "ENABLING" or self.state == "ACTIVE" then
                self:QueueRestore("fail-safe:" .. reason)
                MS.Diagnostics:Print(MS.L.DISPLAY_INVALIDATED)
            end
        end)
        if scheduled then return end
    end
    self:QueueRestore("fail-safe:" .. reason)
    MS.Diagnostics:Print(MS.L.DISPLAY_INVALIDATED)
end

function MS.Runtime:OnDisplayMetricsChanged(reason)
    if self.state == "DISABLED" and reason == "DISPLAY_SIZE_CHANGED" then
        self:ScheduleAutoEnable()
        return
    end
    if self.state ~= "ACTIVE" and self.state ~= "ENABLING" then return end
    if reason == "UI_SCALE_CHANGED" then self:RequestFailSafeDisable(reason); return end
    local generated = MS.GeneratedLayout and MS.GeneratedLayout.span
    local ok, width, height = false, nil, nil
    if type(GetPhysicalScreenSize) == "function" then ok, width, height = pcall(GetPhysicalScreenSize) end
    if generated and ok and width == generated.width and height == generated.height then
        if not self.displayCheckScheduled and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            self.displayCheckScheduled = true
            local generation = self.enableGeneration
            local scheduled = pcall(C_Timer.After, 0, function()
                if generation ~= self.enableGeneration then return end
                self.displayCheckScheduled = false
                if self.state ~= "ACTIVE" and self.state ~= "ENABLING" then return end
                local measured, laterWidth, laterHeight = pcall(GetPhysicalScreenSize)
                if not measured or laterWidth ~= generated.width or laterHeight ~= generated.height then
                    self:RequestFailSafeDisable(reason)
                end
            end)
            if not scheduled then self.displayCheckScheduled = false end
        end
        return
    end
    self:RequestFailSafeDisable(reason)
end

function MS.Runtime:CompleteEnable(layout)
    if self.state ~= "ENABLING" or self.restoring or self.closing then return end
    -- No HUD containment in either mode: VIEWPORT makes UIParent the GAME
    -- viewport; LEGACY_MINIMAL leaves the HUD to the player's Edit Mode layout.

    self:RecordStep("workspace")
    local workspaceCalled, shown, showError = pcall(MS.Workspace.Show, MS.Workspace, layout)
    if self.state ~= "ENABLING" or self.closing then return end
    if not workspaceCalled or not shown then
        self:FailEnable(showError or "ERROR_CONFIG")
        return
    end

    self:RecordStep("journey")
    local journeyCalled, journeyReady, journeyError = pcall(MS.JourneyWorkspace.Start, MS.JourneyWorkspace)
    if self.state ~= "ENABLING" or self.closing then return end
    if not journeyCalled or not journeyReady then
        self:FailEnable(journeyError or "ERROR_JOURNEY_CREATE")
        return
    end

    self.enabled = true
    local closureReady, closureError = pcall(function()
        -- Only the dedicated WORKSPACE tooltip; native tooltips stay native.
        self:RecordStep("tooltip")
        MS.TooltipBridge:Enable()
    end)
    if self.state ~= "ENABLING" or self.closing then return end
    if not closureReady then
        self.lastClosureError = tostring(closureError)
        self:FailEnable("ERROR_GAMEUI_CLOSURE")
        return
    end
    self.lastClosureError = nil
    self.invalidatedReason = nil
    self.failSafeRequested = false
    self.enabling = false
    self.state = "ACTIVE"
    if MS.GameSurfaceContract then pcall(MS.GameSurfaceContract.Refresh, MS.GameSurfaceContract) end
    MS.Diagnostics:RefreshCopyableReportPlacement()
    MS.Diagnostics:Print(MS.L.ENABLED)
    if MS.UIParentMode then MS.UIParentMode:OnRuntimeActive() end
end

function MS.Runtime:Enable()
    if self.state == "ENABLING" or self.state == "RESTORING" then return end
    if self.closing or (MS.Recovery and MS.Recovery.pending) then return end
    if self.state == "FAILED" then MS.Recovery:Restore("retry-before-enable") end
    if self.state == "FAILED" then return end
    if self.enabled then
        MS.Diagnostics:Print(MS.L.ENABLED)
        return
    end
    if MS.Recovery and MS.Recovery.pending then
        MS.Diagnostics:Print(MS.L.RESET_QUEUED)
        return
    end
    self.enableGeneration = self.enableGeneration + 1
    self.state, self.enabling, self.appliedSteps = "ENABLING", true, {}
    self.lastEnableError, self.lastEnableDetail, self.lastEnableStage = nil, nil, "PRECHECK"
    self.failSafeRequested, self.displayCheckScheduled = false, false
    if not MS.Config or type(MS.Config.GetLayout) ~= "function" or not MS.LayoutEngine or not MS.Recovery
        or not MS.Viewport or not MS.Workspace or not MS.GameUI or not MS.EditModeWatch
        or not MS.Diagnostics
        or not MS.JourneyWorkspace or not MS.JourneySession
        or not MS.TooltipBridge or not MS.MapView then
        self.enabled = false
        self.state, self.enabling, self.appliedSteps = "DISABLED", false, nil
        if MS.Diagnostics then
            MS.Diagnostics:Print(string.format(MS.L.INVALID_LAYOUT, MS.L.ERROR_CONFIG))
        end
        return
    end

    if InCombatLockdown() then
        self.state, self.enabling, self.appliedSteps = "DISABLED", false, nil
        MS.Recovery:RunOrQueue(function() MS.Runtime:Enable() end)
        MS.Diagnostics:Print(MS.L.ENABLE_QUEUED)
        return
    end

    if MS.EditModeWatch:IsEditModeShown() then
        self.state, self.enabling, self.appliedSteps = "DISABLED", false, nil
        MS.Diagnostics:Print(MS.L.ERROR_EDITMODE_OPEN)
        return
    end

    local layout, errorMessage = MS.LayoutEngine:Build()
    if not layout then
        self.state, self.enabling, self.appliedSteps = "DISABLED", false, nil
        MS.Diagnostics:Print(string.format(MS.L.INVALID_LAYOUT, MS.L[errorMessage] or MS.L.ERROR_CONFIG))
        return
    end

    local viewport = MS.UIParentMode and MS.UIParentMode:IsViewport()
    if viewport then
        -- Transient bootstrap state, not a failure: UIParent's scale is not
        -- authoritative before PLAYER_ENTERING_WORLD+0, where the session
        -- layer establishes the viewport and enables the runtime. Nothing has
        -- been mutated yet, so there is nothing to recover.
        local _, notReady = MS.UIParentViewport:Readiness(layout)
        if notReady == "UI_SCALE_NOT_SETTLED" then
            self.state, self.enabling, self.appliedSteps = "DISABLED", false, nil
            self.waitingForScale = true
            return
        end
    end
    self.waitingForScale = nil

    local created, workspaceError = MS.Workspace:Create()
    if not created then
        self.state, self.enabling, self.appliedSteps = "DISABLED", false, nil
        MS.Diagnostics:Print(string.format(MS.L.ENABLE_FAILED, MS.L[workspaceError] or MS.L.ERROR_CONFIG))
        return
    end

    if MS.JourneyWindow and MS.JourneyWindow:IsOpen() then MS.JourneyWindow:Close() end -- the spanned path always wins
    self:RecordStep("viewport")
    local applied = pcall(MS.Viewport.Apply, MS.Viewport, layout.game)
    if self.state ~= "ENABLING" or self.closing then return end
    if not applied then
        self:FailEnable("ERROR_VIEWPORT_APPLY")
        return
    end

    if viewport then
        self:RecordStep("uiParent")
        local uiCalled, uiApplied, uiError = pcall(MS.UIParentViewport.Apply, MS.UIParentViewport, layout)
        if self.state ~= "ENABLING" or self.closing then return end
        if not uiCalled or not uiApplied then
            self.lastEnableDetail = tostring(uiCalled and uiError or uiApplied)
            self:FailEnable("ERROR_UIPARENT_VIEWPORT")
            return
        end
        MS.UIParentMode:MarkEstablished("RUNTIME_ENABLE")
    end

    self:RecordStep("gameRegion")
    local gameCalled, prepared, gameUIError = pcall(MS.GameUI.Prepare, MS.GameUI, layout)
    if self.state ~= "ENABLING" or self.closing then return end
    if not gameCalled or not prepared then
        self:FailEnable(gameUIError or "ERROR_CONFIG")
        return
    end

    self:CompleteEnable(layout)
end

function MS.Runtime:Disable()
    local ran, success = self:QueueRestore("manual-disable")
    if not ran then
        MS.Diagnostics:Print(MS.L.RESET_QUEUED)
    elseif success then
        MS.Diagnostics:Print(MS.L.DISABLED)
    end
end

function MS.Runtime:Reset()
    local ran, success = self:QueueRestore("reset")
    if not ran then
        MS.Diagnostics:Print(MS.L.RESET_QUEUED)
    elseif success then
        MS.Diagnostics:Print(MS.L.RESET)
    end
end

function MS.Runtime:OnLogout()
    if not InCombatLockdown() then
        MS.Recovery:Restore("logout")
    end
end

function MS.Runtime:Recover()
    local ran, success = self:QueueRestore("recover")
    if not ran then MS.Diagnostics:Print(MS.L.RESET_QUEUED)
    elseif success then MS.Diagnostics:Print(MS.L.RECOVERED) end
end

-- Automatic activation once the Companion's span is applied.
-- The span itself is the signal: the physical screen size becomes the size
-- of the layout already loaded from Generated/Layout.lua. Nothing is read or
-- received at runtime; the existing Enable() path does all the work (layout
-- build, combat queue, fail-safe). At most once per UI load, or again after a
-- fail-safe for a size change (the window left the span); never a disable.
local AUTO_ENABLE_TEXT = {
    frFR = {
        on = "Activation automatique sur span : ACTIVÉE.",
        off = "Activation automatique sur span : DÉSACTIVÉE.",
        usage = "Usage : /msautoenable on | off | status",
        triggered = "Span détecté : activation automatique du moteur multi-écran.",
    },
    enUS = {
        on = "Auto-enable on span: ON.",
        off = "Auto-enable on span: OFF.",
        usage = "Usage: /msautoenable on | off | status",
        triggered = "Span detected: enabling the multi-screen engine automatically.",
    },
}

local function AutoEnableText(key)
    local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
    return (AUTO_ENABLE_TEXT[locale] or AUTO_ENABLE_TEXT.enUS)[key]
end

-- An absent SavedVariables choice defaults to ON; explicit OFF persists.
function MS.Runtime:AutoEnableAllowed()
    return type(MultiScreenForeverDB) ~= "table" or MultiScreenForeverDB.autoEnableOnSpan ~= false
end

-- Same deferral as the fail-safe check: UIParent metrics settle after the
-- resize. Repeated events while a check is pending schedule nothing more.
function MS.Runtime:ScheduleAutoEnable()
    if self.autoEnableTriggered or self.autoEnableScheduled then return end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        self.autoEnableScheduled = true
        local scheduled = pcall(C_Timer.After, 0, function()
            self.autoEnableScheduled = false
            self:ConsiderAutoEnable()
        end)
        if scheduled then return end
        self.autoEnableScheduled = false
    end
    self:ConsiderAutoEnable()
end

function MS.Runtime:ConsiderAutoEnable()
    if self.autoEnableTriggered then return false end
    if self.state ~= "DISABLED" or self.enabling or self.restoring or self.closing then return false end
    if MS.Recovery and MS.Recovery.pending then return false end
    if not self:AutoEnableAllowed() then return false end
    if not MS.Config or type(MS.Config.GetLayout) ~= "function" then return false end
    local layout = MS.Config:GetLayout()
    if not layout then return false end
    if type(GetPhysicalScreenSize) ~= "function" then return false end
    local ok, width, height = pcall(GetPhysicalScreenSize)
    if not ok or width ~= layout.span.width or height ~= layout.span.height then return false end
    self.autoEnableTriggered = true
    if MS.Diagnostics then MS.Diagnostics:Print(AutoEnableText("triggered")) end
    self:Enable()
    return true
end

SLASH_MULTISCREENAUTOENABLE1 = "/msautoenable"
SlashCmdList.MULTISCREENAUTOENABLE = function(message)
    local command = string.lower(string.match(message or "", "^%s*(%S*)") or "")
    if type(MultiScreenForeverDB) ~= "table" then MultiScreenForeverDB = {} end
    if command == "on" then
        MultiScreenForeverDB.autoEnableOnSpan = true
    elseif command == "off" then
        MultiScreenForeverDB.autoEnableOnSpan = false
    elseif command ~= "status" then
        MS.Diagnostics:Print(AutoEnableText("usage"))
        return
    end
    MS.Diagnostics:Print(AutoEnableText(MS.Runtime:AutoEnableAllowed() and "on" or "off"))
end
