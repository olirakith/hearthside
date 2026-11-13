local MS = _G.MS

-- UIParent = GAME session layer. The mode is resolved once per UI load, at
-- this addon's ADDON_LOADED (SavedVariables present):
--   VIEWPORT: eligible Companion topology and not disabled by the player.
--             UIParent is the GAME viewport.
--   LEGACY:   LEGACY_MINIMAL fallback (unsupported topologies, missing layout
--             or the kill switch): native full-span UIParent, WorldFrame =
--             GAME, Journey WORKSPACE, and no HUD containment at all.
-- Runtime evidence (VIEWPORT validation, Forever 70338): hooks on native frame
-- built-in methods (GameTooltip:SetOwner, BottomManagedFrameContainer:SetPoint)
-- turn into hard failures once the client session is in a poisoned state
-- (taintLog); neither mode installs any of them.
MS.UIParentMode = { mode = "UNRESOLVED", schemaVersion = 1, events = {}, signals = {},
    driftCount = 0, reapplyCount = 0 }
local Mode = MS.UIParentMode

local function Say(key, ...)
    local text = MS.L and MS.L[key]
    if text and MS.Diagnostics then MS.Diagnostics:Print(string.format(text, ...)) end
end
local function InCombat() return type(InCombatLockdown) == "function" and InCombatLockdown() == true end
local function Now() return type(GetTime) == "function" and GetTime() or 0 end
local function Note(self, name, detail)
    local events = self.events
    events[#events + 1] = string.format("%.1f %s %s", Now(), name, tostring(detail or ""))
    if #events > 12 then table.remove(events, 1) end
end

-- Lifecycle signals actually received, in order (diagnostics only).
function Mode:Signal(name)
    local signals = self.signals
    signals[#signals + 1] = string.format("%s@%.1f", name, Now())
    if #signals > 12 then table.remove(signals, 1) end
end

-- Persisted only by an explicit enable/disable; absent means "default".
function Mode:Store()
    if type(MultiScreenForeverDB) ~= "table" then MultiScreenForeverDB = {} end
    local db = MultiScreenForeverDB
    if type(db.uiParentViewport) ~= "table" or db.uiParentViewport.schemaVersion ~= self.schemaVersion then
        db.uiParentViewport = { schemaVersion = self.schemaVersion }
    end
    return db.uiParentViewport
end

-- Supported topology: GAME at the window origin with full height, WORKSPACE
-- strictly to its right. Edit Mode converts saved offsets with absolute screen
-- coordinates (EditModeSystemMixin:BreakFrameSnap), and Blizzard owns
-- UIParent's TOPLEFT, so any other topology stays LEGACY.
function Mode.TopologyEligible(layout)
    if type(layout) ~= "table" then return false, "NO_GENERATED_LAYOUT" end
    local game, workspace, span = layout.game, layout.workspace, layout.span
    if game.x ~= 0 or game.y ~= 0 or game.height ~= span.height then
        return false, "TOPOLOGY_GAME_NOT_ORIGIN_FULL_HEIGHT"
    end
    if workspace.x < game.x + game.width then return false, "TOPOLOGY_WORKSPACE_NOT_RIGHT" end
    return true
end

-- Never resolves before SavedVariables exist: an early query is not a choice.
function Mode:ResolveMode(source)
    if self.mode ~= "UNRESOLVED" then return self.mode end
    if not self.savedVariablesReady then return self.mode end
    self.resolvedBy = source or "UNKNOWN"
    local db = rawget(_G, "MultiScreenForeverDB")
    local stored = type(db) == "table" and type(db.uiParentViewport) == "table" and db.uiParentViewport or nil
    local layout, source, layoutError
    if MS.Config then layout, source, layoutError = MS.Config:GetLayout() end
    self.layoutSource = source
    local eligible, topologyReason = Mode.TopologyEligible(layout)
    if stored and stored.enabled == false then
        self.mode, self.reason = "LEGACY", "PLAYER_DISABLED"
    elseif not eligible then
        self.mode, self.reason = "LEGACY", layout and topologyReason or (layoutError or "NO_GENERATED_LAYOUT")
    else
        self.mode, self.reason = "VIEWPORT", "ELIGIBLE_TOPOLOGY"
    end
    Note(self, "RESOLVED", self.mode .. ":" .. self.reason .. ":" .. self.resolvedBy)
    return self.mode
end

function Mode:IsViewport()
    if self.mode == "UNRESOLVED" then self:ResolveMode("LAZY_QUERY") end
    return self.mode == "VIEWPORT"
end

-- LEGACY_MINIMAL entered because of an unsupported topology (never for the
-- kill switch): one non-modal notice per session once Journey is active.
function Mode:OnRuntimeActive()
    if self.mode ~= "LEGACY" or self.compatibilityNoticeShown then return end
    if type(self.reason) ~= "string" or not self.reason:find("^TOPOLOGY_") then return end
    self.compatibilityNoticeShown = true
    Note(self, "COMPATIBILITY_NOTICE", self.reason)
    Say("UIPARENT_MODE_COMPATIBILITY")
end

-- HUD containment is retired: Journey wraps no native HUD method. Wrappers
-- found here belong to another addon (compatibility evidence only).
function Mode:HookAudit()
    local tooltip, bottom = _G.GameTooltip, _G.BottomManagedFrameContainer
    return { foreign = {
        setOwner = tooltip and rawget(tooltip, "SetOwner") ~= nil or false,
        setPoint = bottom and rawget(bottom, "SetPoint") ~= nil or false,
    } }
end

-- Entry point at this addon's ADDON_LOADED; PLAYER_LOGIN is an idempotent fallback.
function Mode:OnAddonLoaded(source)
    self:Signal(source)
    self.savedVariablesReady = true
    self:ResolveMode(source)
    self:Arm(source)
end

-- The client window must equal the Companion span (same predicate as the automatic activation
-- auto-enable and LayoutEngine). Never shrink UIParent on an unspanned window.
function Mode:SpanReady()
    local layout = MS.Config and MS.Config:GetLayout()
    if not layout or type(GetPhysicalScreenSize) ~= "function" then return false, "NO_GENERATED_LAYOUT" end
    local ok, width, height = pcall(GetPhysicalScreenSize)
    if not ok or width ~= layout.span.width or height ~= layout.span.height then return false, "SPAN_NOT_ACTIVE" end
    return true
end

-- Bootstrap readiness invariant: span active AND UI scale settled
-- (UIParentViewport:SettleScale at PLAYER_ENTERING_WORLD+0).
function Mode:BootstrapReady()
    local ready, reason = self:SpanReady()
    if not ready then return false, reason end
    if not MS.UIParentViewport.scaleAuthority then return false, "UI_SCALE_NOT_SETTLED" end
    return true
end

-- Establishes at the first coherent point: PLAYER_ENTERING_WORLD+0 on a
-- /reload while spanned, DISPLAY_SIZE_CHANGED on a fresh launch. A released
-- session never re-arms by itself.
function Mode:Arm(signal)
    if not self:IsViewport() or MS.UIParentViewport:IsApplied() or self.establishedAt then return end
    if InCombat() then self.pendingArm = signal; Note(self, "ARM_COMBAT_DEFERRED", signal); return end
    local ready, reason = self:BootstrapReady()
    if not ready then self.lastArmRefusal = reason; Note(self, "ARM_REFUSED", reason); return end
    local layout, layoutError = MS.LayoutEngine:Build()
    if not layout then self.lastArmRefusal = layoutError; Note(self, "ARM_REFUSED", layoutError); return end
    local applied, applyError = MS.UIParentViewport:Apply(layout, signal)
    if not applied then
        self.lastArmRefusal = applyError
        Note(self, "ARM_FAILED", applyError)
        Say("UIPARENT_MODE_REFUSED", tostring(applyError))
        return
    end
    self:MarkEstablished(signal)
end

function Mode:MarkEstablished(source)
    self.establishedAt = self.establishedAt or source
    self.lastArmRefusal = nil
    Note(self, "ESTABLISHED", source)
end

-- The span arrives after login on a fresh launch; same settle delay as the
-- runtime's display check.
function Mode:OnDisplaySizeChanged()
    self:Signal("DISPLAY_SIZE_CHANGED")
    local function Settled()
        if not self:IsViewport() then return end
        self:Arm("DISPLAY_SIZE_CHANGED")
        self:EstablishSession("DISPLAY_SIZE_CHANGED")
        self:Verify("DISPLAY_SIZE_CHANGED")
    end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(0, Settled) else Settled() end
end

-- The GAME viewport is only coherent with an ACTIVE runtime: start it, or
-- release UIParent (fail closed).
function Mode:EstablishSession(signal)
    if not self:IsViewport() or not MS.UIParentViewport:IsApplied() then return end
    local runtime = MS.Runtime
    local allowed = type(runtime.AutoEnableAllowed) ~= "function" or runtime:AutoEnableAllowed()
    if runtime.state == "DISABLED" and not runtime.enabling and not (MS.Recovery and MS.Recovery.pending) then
        if allowed then
            Note(self, "SESSION_ENABLE", signal)
            runtime:Enable()
        else
            -- /msautoenable off is respected: no runtime, so no GAME viewport either.
            runtime.lastEnableError = runtime.lastEnableError or "AUTO_ENABLE_DISABLED"
        end
    end
    if runtime.state == "DISABLED" and not (MS.Recovery and MS.Recovery.pending) and MS.UIParentViewport:IsApplied() then
        local restored = MS.UIParentViewport:Restore("SESSION_FAIL_CLOSED")
        Note(self, "SESSION_FAIL_CLOSED", runtime.lastEnableError or "ENABLE_REFUSED")
        Say("UIPARENT_MODE_FAILED", tostring(runtime.lastEnableError or "ENABLE_REFUSED") .. (restored and "" or " (RESTORE_FAILED)"))
    end
end

-- Read-only check at lifecycle boundaries; corrects only our own anchor, out
-- of combat, always from the native capture.
function Mode:Verify(signal)
    local viewport = MS.UIParentViewport
    if not self:IsViewport() or viewport.state ~= "APPLIED" then return end
    local verdict = viewport:Verify()
    self.lastVerify = { signal = signal, verdict = verdict, at = Now() }
    if verdict == "MATCHED" then return end
    self.driftCount = self.driftCount + 1
    if InCombat() then self.pendingVerify = signal; Note(self, "DRIFT_COMBAT", verdict); return end
    local layout = MS.LayoutEngine:Build()
    local reapplied = layout and viewport:Apply(layout, "DRIFT:" .. tostring(signal))
    if reapplied then self.reapplyCount = self.reapplyCount + 1 end
    Note(self, "DRIFT", verdict .. (reapplied and ":REAPPLIED" or ":FAILED"))
    Say("UIPARENT_MODE_DRIFT", verdict, tostring(signal), tostring(reapplied and true or false))
    if not reapplied and MS.Runtime.state ~= "DISABLED" then MS.Runtime:QueueRestore("uiparent-viewport-drift") end
end

-- Kill switch: Journey off, UIParent restored, LEGACY persisted. The current
-- session continues as LEGACY_MINIMAL (an explicit /ms enable runs it).
function Mode:Kill()
    self:Store().enabled = false
    self.mode, self.reason = "LEGACY", "PLAYER_DISABLED"
    Note(self, "KILL_SWITCH")
    if InCombat() then
        MS.Recovery:RunOrQueue(function() MS.Recovery:Restore("uiparent-kill-switch") end)
        Say("UIPARENT_MODE_QUEUED")
        return
    end
    if MS.Runtime.state ~= "DISABLED" or MS.UIParentViewport:IsApplied() then
        MS.Recovery:Restore("uiparent-kill-switch")
    end
    if MS.UIParentViewport:IsApplied() then MS.UIParentViewport:Restore("KILL_SWITCH") end
    Say("UIPARENT_MODE_KILLED", MS.UIParentViewport.state)
end

function Mode:StatusLines()
    local v, r = MS.UIParentViewport:GetStatus(), MS.ViewportRoots:GetStatus()
    local runtime, ui, o = MS.Runtime or {}, v.uiParent, v.original or {}
    local audit = self:HookAudit()
    local clamp = MS.ViewportTooltipClamp and MS.ViewportTooltipClamp:GetStatus() or {}
    local edit = MS.EditModeWatch and MS.EditModeWatch:GetStatus() or {}
    local function N(n) return type(n) == "number" and string.format("%.2f", n) or tostring(n) end
    local function Flags(t)
        local parts = {}
        for key, value in pairs(t) do parts[#parts + 1] = key .. "=" .. tostring(value) end
        table.sort(parts)
        return table.concat(parts, ",")
    end
    local physicalWidth, physicalHeight
    if type(GetPhysicalScreenSize) == "function" then physicalWidth, physicalHeight = GetPhysicalScreenSize() end
    return {
        string.format("UIParent mode=%s reason=%s resolvedBy=%s runtime=%s established=%s waitingForScale=%s",
            self.mode, tostring(self.reason), tostring(self.resolvedBy), tostring(runtime.state),
            tostring(self.establishedAt), tostring(runtime.waitingForScale == true)),
        string.format("UIParent state=%s verify=%s left=%s right=%s width=%s height=%s scale=%s points=%s err=%s",
            v.state, v.verify, N(ui.left), N(ui.right), N(ui.width), N(ui.height), N(ui.scale),
            tostring(ui.points), tostring(v.lastError)),
        string.format("native %s:%s(%s,%s) points=%s width=%s | delta=%s gameRight=%s span=%s planScale=%s scaleAuthority=%s",
            tostring(o.point), tostring(o.relativePoint), N(o.x), N(o.y), tostring(o.pointCount), N(o.width),
            N(v.delta), N(v.gameRight), N(v.spanWidth), N(v.planScale), tostring(v.scaleAuthority)),
        string.format("SPAN_ROOT=%sx%s screen=%sx%s physical=%sx%s WORKSPACE_ROOT shown=%s parent=%s",
            N(r.spanWidth), N(r.spanHeight), N(v.screenWidth), N(v.screenHeight), tostring(physicalWidth),
            tostring(physicalHeight), tostring(r.workspaceShown), tostring(r.workspaceParent)),
        string.format("hooks foreign{%s}", Flags(audit.foreign)),
        string.format("tooltipClamp state=%s right=%s nativeRight=%s writes=%s err=%s", tostring(clamp.state),
            N(clamp.right), N(clamp.nativeRight), tostring(clamp.writes), tostring(clamp.lastError)),
        string.format("editMode active=%s journeyProfile=%s migration=%s", tostring(edit.active),
            tostring(edit.journeyProfile), tostring(edit.state)),
        string.format("applies=%d restores=%d drift=%d reapply=%d armRefusal=%s events: %s", v.applyCount,
            v.restoreCount, self.driftCount, self.reapplyCount, tostring(self.lastArmRefusal),
            table.concat(self.events, " | ")),
        "history: " .. table.concat(v.history or {}, " | "),
        "signals: " .. table.concat(self.signals, " "),
    }
end

function Mode:Command(message)
    local command = string.lower(string.match(message or "", "^%s*(%S*)") or "")
    if command == "enable" then
        self:Store().enabled = true
        Say("UIPARENT_MODE_ENABLED")
    elseif command == "disable" then
        self:Kill()
    elseif command == "status" then
        for _, line in ipairs(self:StatusLines()) do MS.Diagnostics:Print(line) end
    else
        Say("UIPARENT_MODE_USAGE")
    end
end

SLASH_AJVIEWPORT1 = "/ajviewport"
SlashCmdList.AJVIEWPORT = function(message) Mode:Command(message) end

if type(CreateFrame) == "function" then
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
        frame:RegisterEvent(event)
    end
    pcall(frame.RegisterEvent, frame, "DISPLAY_SIZE_CHANGED")
    frame:SetScript("OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" then
            if name ~= MS.addonName then return end
            Mode:OnAddonLoaded("ADDON_LOADED")
        elseif event == "PLAYER_LOGIN" then
            Mode:OnAddonLoaded("PLAYER_LOGIN")
        elseif event == "PLAYER_ENTERING_WORLD" then
            Mode:Signal("PLAYER_ENTERING_WORLD")
            -- After every PEW handler (Blizzard's UpdateUIParentPosition, addon
            -- scale writers): the session UI scale is authoritative from here.
            if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
                C_Timer.After(0, function()
                    if Mode:IsViewport() then MS.UIParentViewport:SettleScale("PLAYER_ENTERING_WORLD") end
                    Mode:Arm("PLAYER_ENTERING_WORLD")
                    Mode:EstablishSession("PLAYER_ENTERING_WORLD")
                    Mode:Verify("PLAYER_ENTERING_WORLD")
                end)
            end
        elseif event == "DISPLAY_SIZE_CHANGED" then
            Mode:OnDisplaySizeChanged()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if Mode.pendingArm then local signal = Mode.pendingArm; Mode.pendingArm = nil; Mode:Arm(signal .. "+COMBAT_END") end
            if Mode.pendingVerify then local signal = Mode.pendingVerify; Mode.pendingVerify = nil; Mode:Verify(signal .. "+COMBAT_END") end
        end
    end)
    Mode.eventFrame = frame
    local registry = _G.EventRegistry
    if registry and type(registry.RegisterCallback) == "function" then
        pcall(registry.RegisterCallback, registry, "EditMode.Exit", function() Mode:Verify("EditMode.Exit") end, Mode)
    end
end
-- Create SPAN_ROOT at load so its screen rect is resolved before the first arm.
MS.ViewportRoots:EnsureSpanRoot()
Mode:Signal("FILE_END")
