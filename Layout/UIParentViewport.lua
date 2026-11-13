local MS = _G.MS

-- UIParent = GAME controller (VIEWPORT mode).
-- Owns exactly one UIParent anchor: BOTTOMRIGHT. Blizzard owns TOPLEFT
-- (UpdateUIParentPosition rewrites it for notch/debug bars), so the controller never
-- calls ClearAllPoints/SetSize/SetScale on UIParent. Target offsets are always
-- derived from the native capture, never from the current anchor.
MS.UIParentViewport = { state = "NATIVE", applyCount = 0, restoreCount = 0, history = {} }
local V = MS.UIParentViewport
V.TOLERANCE_UI = 0.5
V.OWNED_POINT = "BOTTOMRIGHT"

local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function Near(a, b) return Finite(a) and Finite(b) and math.abs(a - b) <= V.TOLERANCE_UI end
local function SameScale(a, b) return Finite(a) and Finite(b) and math.abs(a - b) <= 1e-4 end
local function InCombat() return type(InCombatLockdown) == "function" and InCombatLockdown() == true end

local function Read(frame, method, ...)
    if not frame or type(frame[method]) ~= "function" then return end
    local ok, a, b, c, d, e = pcall(frame[method], frame, ...)
    if ok then return a, b, c, d, e end
end

-- Pure: the GAME viewport as a right-edge inset of the native UIParent.
-- Supported topology: GAME flush with the window's left, bottom and top edges,
-- WORKSPACE strictly to its right. Anything else would need TOPLEFT, which
-- Blizzard rewrites; the controller refuses it instead of fighting that writer.
function V.Plan(game, workspace, spanWidth, spanHeight)
    if not MS.Rect:IsValid(game) or not MS.Rect:IsValid(workspace)
        or not Finite(spanWidth) or not Finite(spanHeight) or spanWidth <= 0 or spanHeight <= 0 then
        return nil, "PLAN_INPUT_INVALID"
    end
    local gameRight = game.x + game.width
    if not Near(game.x, 0) or not Near(game.y, 0) or not Near(game.height, spanHeight) then
        return nil, "PLAN_GAME_NOT_LEFT_FULL_HEIGHT"
    end
    if workspace.x < gameRight - V.TOLERANCE_UI then return nil, "PLAN_WORKSPACE_NOT_RIGHT" end
    local delta = spanWidth - gameRight
    if delta <= V.TOLERANCE_UI or gameRight <= 0 then return nil, "PLAN_NO_INSET" end
    return { delta = delta, gameRight = gameRight, gameWidth = game.width,
        spanWidth = spanWidth, spanHeight = spanHeight }
end

function V:ReadPoints()
    local points = {}
    local count = Read(UIParent, "GetNumPoints")
    for index = 1, Finite(count) and count or 0 do
        local point, relative, relativePoint, x, y = Read(UIParent, "GetPoint", index)
        points[#points + 1] = { point, relative, relativePoint, x, y }
    end
    return points
end

local function Owned(points)
    for _, point in ipairs(points) do
        if point[1] == V.OWNED_POINT then return point end
    end
end

-- Capture only a native UIParent: full span width, left edge at 0. A
-- non-native UIParent (another writer, or a leaked lease) is refused so
-- offsets can never accumulate across enable cycles.
function V:Capture(spanWidth)
    if self.original then return true end
    local points = self:ReadPoints()
    local owned = Owned(points)
    if not owned or not Finite(owned[4]) or not Finite(owned[5]) then
        return nil, "UIPARENT_ANCHOR_SHAPE"
    end
    if not Near(Read(UIParent, "GetLeft"), 0) or not Near(Read(UIParent, "GetWidth"), spanWidth) then
        return nil, "UIPARENT_NOT_NATIVE_AT_CAPTURE"
    end
    self.original = { point = owned[1], relative = owned[2], relativePoint = owned[3], x = owned[4], y = owned[5],
        pointCount = #points, width = Read(UIParent, "GetWidth"), height = Read(UIParent, "GetHeight"),
        scale = Read(UIParent, "GetScale"), effectiveScale = Read(UIParent, "GetEffectiveScale") }
    return true
end

-- Bootstrap readiness. Every UI-unit quantity of a plan (SPAN_ROOT size, GAME
-- rect, delta, the BOTTOMRIGHT offset itself) derives from UIParent's
-- effective scale, and that scale is not authoritative during addon loading:
-- the client applies the session UI scale during login, after ADDON_LOADED,
-- and addons may apply their own up to PLAYER_LOGIN. Runtime finding (cab896f,
-- /reload while spanned): at load time UIParent was still at its pre-login
-- scale 1.0, so GAME measured 1365.3 instead of the session's 2133.3. The mode
-- declares the scale authoritative once PLAYER_ENTERING_WORLD is fully
-- dispatched; no UIParent write happens before that.
function V:SettleScale(signal)
    if not self.scaleAuthority then self.scaleAuthority = signal or "UNKNOWN" end
end

-- Coherence of a built layout with the geometry in force at write time: the
-- GAME rect (from Build) and the span (read now) must share one UIParent scale.
function V:Readiness(layout)
    if not self.scaleAuthority then return nil, "UI_SCALE_NOT_SETTLED" end
    local metrics = type(layout) == "table" and layout.metrics
    if type(metrics) ~= "table" then return nil, "PLAN_INPUT_INVALID" end
    local spanWidth, spanHeight = MS.ViewportRoots:GetSpanSize()
    if not SameScale(metrics.effectiveScale, Read(UIParent, "GetEffectiveScale"))
        or not Near(metrics.uiWidth, spanWidth) or not Near(metrics.uiHeight, spanHeight) then
        return nil, "PLAN_SCALE_INCOHERENT"
    end
    return true
end

function V:Target()
    local o, plan = self.original, self.plan
    if not o or not plan then return end
    return o.point, o.relative, o.relativePoint, o.x - plan.delta, o.y
end

function V:Verify()
    local plan = self.plan
    if not plan then return "NOT_APPLIED" end
    -- The offset is in UIParent units: any scale change invalidates the plan.
    if not SameScale(Read(UIParent, "GetEffectiveScale"), plan.uiScale) then return "DRIFT_SCALE" end
    local owned = Owned(self:ReadPoints())
    local _, relative, relativePoint, x, y = self:Target()
    if not owned or owned[2] ~= relative or owned[3] ~= relativePoint
        or not Near(owned[4], x) or not Near(owned[5], y) then return "DRIFT_ANCHOR" end
    -- Height is Blizzard's (TOPLEFT notch/debug-bar offset); only the edges we own are checked.
    if not Near(Read(UIParent, "GetLeft"), 0) or not Near(Read(UIParent, "GetRight"), plan.gameRight) then
        return "DRIFT_RECT"
    end
    return "MATCHED"
end

local function Fail(self, reason)
    self.lastError = reason
    return nil, reason
end

-- Every apply/restore outcome with the geometry read at that moment (diagnostics).
function V:Record(operation, source, result)
    local history = self.history
    history[#history + 1] = string.format("%s:%s:%s r=%.1f w=%.1f s=%.3f", operation, tostring(source or "RUNTIME"),
        tostring(result), tonumber(Read(UIParent, "GetRight")) or -1, tonumber(Read(UIParent, "GetWidth")) or -1,
        tonumber(Read(UIParent, "GetEffectiveScale")) or -1)
    if #history > 8 then table.remove(history, 1) end
end

-- layout: MS.LayoutEngine:Build() result (UIParent UI units).
function V:Apply(layout, source)
    local applied, reason = self:ApplyInner(layout)
    self:Record("APPLY", source, applied and "OK" or reason)
    return applied, reason
end

function V:ApplyInner(layout)
    if InCombat() then return Fail(self, "COMBAT") end
    if type(layout) ~= "table" then return Fail(self, "PLAN_INPUT_INVALID") end
    local ready, notReady = self:Readiness(layout)
    if not ready then return Fail(self, notReady) end
    local spanWidth, spanHeight = MS.ViewportRoots:GetSpanSize()
    local plan, planError = V.Plan(layout.game, layout.workspace, spanWidth, spanHeight)
    if not plan then return Fail(self, planError) end
    plan.uiScale = Read(UIParent, "GetEffectiveScale")
    if self.plan and self.state == "APPLIED" then
        if Near(self.plan.delta, plan.delta) and self:Verify() == "MATCHED" then return true end
    end
    local captured, captureError = self:Capture(spanWidth)
    if not captured then return Fail(self, captureError) end
    self.plan = plan
    local written = pcall(UIParent.SetPoint, UIParent, self:Target())
    local verdict = written and self:Verify() or "WRITE_FAILED"
    if verdict ~= "MATCHED" then
        -- Fail closed: never leave a half-applied UIParent behind.
        self:RestoreInner()
        return Fail(self, "APPLY_" .. verdict)
    end
    self.state, self.lastError = "APPLIED", nil
    self.applyCount = self.applyCount + 1
    self.appliedAt = type(GetTime) == "function" and GetTime() or nil
    if MS.ViewportTooltipClamp then MS.ViewportTooltipClamp:Sync() end
    return true
end

function V:IsApplied() return self.original ~= nil end

function V:Restore(source)
    local owned = self.original ~= nil
    local restored, reason = self:RestoreInner()
    if owned then self:Record("RESTORE", source, restored and "OK" or reason) end
    return restored, reason
end

function V:RestoreInner()
    local o = self.original
    if not o then self.state = "NATIVE"; return true end
    if InCombat() then return Fail(self, "COMBAT") end
    -- Judge the resulting anchor, not the write: a write that never landed
    -- (failed apply) still leaves the exact native tuple in place.
    pcall(UIParent.SetPoint, UIParent, o.point, o.relative, o.relativePoint, o.x, o.y)
    local owned = Owned(self:ReadPoints())
    local exact = owned and owned[2] == o.relative and owned[3] == o.relativePoint
        and owned[4] == o.x and owned[5] == o.y
    local spanWidth = MS.ViewportRoots:GetSpanSize()
    if not exact or not Near(Read(UIParent, "GetWidth"), spanWidth) then
        self.state = "RESTORE_FAILED"
        return Fail(self, "RESTORE_NOT_EXACT")
    end
    self.original, self.plan = nil, nil
    self.state = "NATIVE"
    self.restoreCount = self.restoreCount + 1
    if MS.ViewportTooltipClamp then MS.ViewportTooltipClamp:Sync() end
    return true
end

function V:GetStatus()
    local o, plan = self.original, self.plan
    return { state = self.state, lastError = self.lastError, verify = plan and self:Verify() or "NOT_APPLIED",
        applyCount = self.applyCount, restoreCount = self.restoreCount, history = self.history,
        delta = plan and plan.delta, gameRight = plan and plan.gameRight, spanWidth = plan and plan.spanWidth,
        planScale = plan and plan.uiScale, scaleAuthority = self.scaleAuthority,
        original = o and { point = o.point, relativePoint = o.relativePoint, x = o.x, y = o.y,
            relative = o.relative == nil and "nil" or (Read(o.relative, "GetName") or "<anonymous>"),
            pointCount = o.pointCount, width = o.width, scale = o.scale } or nil,
        uiParent = { left = Read(UIParent, "GetLeft"), right = Read(UIParent, "GetRight"),
            width = Read(UIParent, "GetWidth"), height = Read(UIParent, "GetHeight"),
            scale = Read(UIParent, "GetScale"), points = #self:ReadPoints(),
            protected = Read(UIParent, "IsProtected") },
        screenWidth = type(GetScreenWidth) == "function" and GetScreenWidth() or nil,
        screenHeight = type(GetScreenHeight) == "function" and GetScreenHeight() or nil }
end
