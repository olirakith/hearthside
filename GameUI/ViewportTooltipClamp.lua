local MS = _G.MS

-- VIEWPORT-mode GameTooltip clamp. Clamping is to the screen (the full span),
-- not to UIParent, so with UIParent = GAME a tooltip can still overflow into
-- WORKSPACE. One persistent property only: SetClampRectInsets. Blizzard writes
-- these insets once (SharedTooltip_OnLoad), so a refresh at the viewport's own
-- apply/restore boundaries holds without wrapping SetOwner or any other method.
-- Same rule as the certified LEGACY lease (TooltipClampStrategy): RIGHT is the
-- larger of the native inset and the WORKSPACE width, in UIParent units.
MS.ViewportTooltipClamp = { state = "NATIVE", writes = 0 }
local C = MS.ViewportTooltipClamp
local SCALE_TOLERANCE = 0.000001

local function Read(frame, method)
    if not frame or type(frame[method]) ~= "function" then return end
    local ok, a, b, c, d = pcall(frame[method], frame)
    if ok then return a, b, c, d end
end
local function Finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end

-- Never write through a foreign wrapper or onto a protected/forbidden tooltip.
local function Eligible(tooltip)
    if not tooltip or Read(tooltip, "IsForbidden") ~= false or Read(tooltip, "IsProtected") ~= false then
        return nil, "TOOLTIP_SECURITY_UNKNOWN"
    end
    if type(issecurevariable) == "function" then
        local ok, secure = pcall(issecurevariable, tooltip, "SetClampRectInsets")
        if not ok or secure ~= true then return nil, "TOOLTIP_WRITER_NOT_SECURE" end
    end
    local tooltipScale, uiScale = Read(tooltip, "GetEffectiveScale"), Read(UIParent, "GetEffectiveScale")
    if not Finite(tooltipScale) or not Finite(uiScale) or math.abs(tooltipScale - uiScale) > SCALE_TOLERANCE then
        return nil, "CLAMP_UNITS_UNKNOWN"
    end
    return true
end

-- The only VIEWPORT GameTooltip writer (approved port in the surface authority manifest).
function C:Write(tooltip, insets)
    local ok = pcall(tooltip.SetClampRectInsets, tooltip, insets.LEFT, insets.RIGHT, insets.TOP, insets.BOTTOM)
    if ok then self.writes = self.writes + 1 end
    return ok
end

-- Follows the UIParent controller: APPLIED -> GAME clamp, otherwise native.
function C:Sync()
    local tooltip, viewport = _G.GameTooltip, MS.UIParentViewport
    local plan = viewport and viewport.state == "APPLIED" and viewport.plan
    if not plan then return self:Restore() end
    local eligible, reason = Eligible(tooltip)
    if not eligible then self.lastError = reason; return nil, reason end
    if not self.original then
        local left, right, top, bottom = Read(tooltip, "GetClampRectInsets")
        if not (Finite(left) and Finite(right) and Finite(top) and Finite(bottom)) then
            self.lastError = "CLAMP_UNAVAILABLE"; return nil, self.lastError
        end
        self.original = { LEFT = left, RIGHT = right, TOP = top, BOTTOM = bottom }
    end
    local o = self.original
    local target = { LEFT = o.LEFT, RIGHT = math.max(o.RIGHT, plan.delta), TOP = o.TOP, BOTTOM = o.BOTTOM }
    if not self:Write(tooltip, self.lifted and o or target) then
        self.lastError = "CLAMP_WRITE_FAILED"; return nil, self.lastError
    end
    self.state, self.applied, self.lastError = "APPLIED", target, nil
    return true
end

-- Over the Journey map, tooltips belong next to their pin on WORKSPACE: the native insets hold while
-- the cursor is there. The map lifts on entry and drops on exit or when it hides.
function C:SetLifted(lifted)
    if self.lifted == lifted then return end
    self.lifted = lifted
    if self.state == "APPLIED" and self.original then
        self:Write(_G.GameTooltip, lifted and self.original or self.applied)
    end
end

function C:Restore()
    local o, tooltip = self.original, _G.GameTooltip
    if not o then self.state = "NATIVE"; return true end
    if not tooltip or Read(tooltip, "IsForbidden") ~= false then self.lastError = "TOOLTIP_UNAVAILABLE"; return nil, self.lastError end
    if not self:Write(tooltip, o) then self.lastError = "CLAMP_RESTORE_FAILED"; return nil, self.lastError end
    self.original, self.applied, self.state, self.lastError = nil, nil, "NATIVE", nil
    return true
end

function C:GetStatus()
    local insets = self.applied
    return { state = self.state, writes = self.writes, lastError = self.lastError, lifted = self.lifted == true,
        right = insets and insets.RIGHT, nativeRight = self.original and self.original.RIGHT }
end
