local MS = _G.MS

MS.Viewport = {
    original = nil,
}

function MS.Viewport:CaptureOriginal()
    if self.original then
        return
    end
    local original = { points = {} }
    local count = WorldFrame:GetNumPoints()
    if type(count) ~= "number" or count < 1 then
        error("WorldFrame has no restorable anchors")
    end
    for index = 1, count do
        local point, relativeTo, relativePoint, x, y = WorldFrame:GetPoint(index)
        if not point then error("WorldFrame anchor capture failed") end
        table.insert(original.points, { point, relativeTo, relativePoint, x, y })
    end
    self.original = original
end

function MS.Viewport:Apply(rect)
    self:CaptureOriginal()
    local offsets = MS.Transform:RectToFrameOffsets(rect, UIParent, WorldFrame)
    if not offsets then
        error("WorldFrame effective scale is unavailable")
    end
    WorldFrame:ClearAllPoints()
    WorldFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", offsets.x, offsets.y)
    WorldFrame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", offsets.x + offsets.width, offsets.y + offsets.height)
end

function MS.Viewport:Restore()
    if not self.original then
        return true
    end
    local ok = pcall(function()
        WorldFrame:ClearAllPoints()
        for _, point in ipairs(self.original.points) do
            WorldFrame:SetPoint(point[1], point[2], point[3], point[4], point[5])
        end
    end)
    if not ok then return nil, "ERROR_VIEWPORT_RESTORE" end
    self.original = nil
    return true
end

-- Re-evaluate the existing viewport lease only at completed native lifecycle
-- boundaries. Blizzard's intro cinematic restores WorldFrame to the full span;
-- Edit Mode exit is the semantic boundary after profile saving/activation.
local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function CurrentRect()
    local ok, x, y, width, height = pcall(WorldFrame.GetRect, WorldFrame)
    if not ok or not Finite(x) or not Finite(y) or not Finite(width) or not Finite(height) then return end
    return MS.Transform:FrameRectToUI({x=x,y=y,width=width,height=height}, WorldFrame, UIParent)
end
local function SameRect(a, b)
    if not a or not b then return false end
    for _, key in ipairs({"x", "y", "width", "height"}) do
        if not Finite(a[key]) or math.abs(a[key]-b[key]) > 1 then return false end
    end
    return true
end
function MS.Viewport:Reevaluate(signal)
    local runtime = MS.Runtime
    if not self.original or not runtime or runtime.state ~= "ACTIVE" or not runtime.enabled
        or runtime.closing or runtime.restoring or runtime.invalidatedReason then return end
    if _G.EditModeManagerFrame and EditModeManagerFrame.editModeActive == true then return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        self.pendingLifecycle = signal
        self.lastLifecycle = {signal=signal,state="COMBAT_DEFERRED"}
        return
    end
    self.pendingLifecycle = nil
    local layout, reason = MS.LayoutEngine:Build()
    if not layout then self.lastLifecycle = {signal=signal,state="REFUSED",reason=reason}; return end
    local before = CurrentRect()
    local contract = MS.GameSurfaceContract and MS.GameSurfaceContract:Get()
    local evidence = {signal=signal,expected=layout.game,before=before,
        contractGeneration=contract and contract.generation,state="MATCHED",span=layout.metrics}
    self.lastLifecycle = evidence
    if not before then evidence.state="UNREADABLE"; return end
    if SameRect(before, layout.game) then return true end
    -- The validated owner applies its ordinary configured GAME rect, preserving
    -- the original restore capture. No new geometry writer or profile mutation.
    local ok, error = pcall(self.Apply, self, layout.game)
    evidence.after = CurrentRect()
    evidence.state = ok and SameRect(evidence.after, layout.game) and "REAPPLIED" or "NOT_CONFIRMED"
    evidence.error = not ok and tostring(error) or nil
    return evidence.state == "REAPPLIED"
end
function MS.Viewport:InstallLifecycle()
    local registry = _G.EventRegistry
    if not registry or type(registry.RegisterCallback) ~= "function" then return end
    self.lifecycleSignals = self.lifecycleSignals or {}
    for _, signal in ipairs({"EditMode.Exit", "CinematicFrame.CinematicStopped"}) do
        if not self.lifecycleSignals[signal] then
            local name = signal
            local ok = pcall(registry.RegisterCallback, registry, name, function()
                pcall(MS.Viewport.Reevaluate, MS.Viewport, name)
            end, self)
            if ok then self.lifecycleSignals[signal] = true end
        end
    end
end
if type(CreateFrame) == "function" then
    local events = CreateFrame("Frame")
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event)
        MS.Viewport:InstallLifecycle()
        if event == "PLAYER_REGEN_ENABLED" and MS.Viewport.pendingLifecycle then
            pcall(MS.Viewport.Reevaluate, MS.Viewport, MS.Viewport.pendingLifecycle)
        end
    end)
    MS.Viewport.lifecycleEvents = events
end
MS.Viewport:InstallLifecycle()
