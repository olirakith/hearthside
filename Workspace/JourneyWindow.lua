local MS = _G.MS

-- Journey as a normal movable window on the single game screen, for players without the Companion.
-- The multi-screen engine is not involved: WorldFrame and UIParent are never moved and the
-- Runtime stays DISABLED. The spanned path always wins (Runtime:Enable closes the window).
MS.JourneyWindow = { open = false }
local Window = MS.JourneyWindow

local MAX_WIDTH, MAX_HEIGHT = 1280, 820
local DEFAULT_INSET = 28 -- Journey.BOTTOM_SAFE_INSET outside window mode
local ESCAPE_FRAME = "HearthsideWindowEscape"
local FADE_SECONDS = .25 -- a full fade, from opaque to fully clear

local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function Say(key)
    MS.Diagnostics:Print(MS.L[key])
end

local function Saved()
    local database = MS.Database and MS.Database:Get()
    return database and database.workspace
end

-- Returns true, or false and the localization key of the reason.
function Window:Available()
    local runtime = MS.Runtime
    if not runtime or runtime.state ~= "DISABLED" then return false, "JOURNEY_WINDOW_SPANNED" end
    if runtime.closing or runtime.restoring or (MS.Recovery and MS.Recovery.pending) then
        return false, "JOURNEY_WINDOW_BUSY"
    end
    if MS.UIParentViewport and MS.UIParentViewport:IsApplied() then return false, "JOURNEY_WINDOW_SPANNED" end
    if InCombatLockdown() then return false, "JOURNEY_WINDOW_COMBAT" end
    return true
end

function Window:IsOpen()
    return self.open == true
end

-- UI units from UIParent, bottom-left origin: centred, or where the player last left it.
function Window:Rect()
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if not Finite(screenWidth) or not Finite(screenHeight) or screenWidth <= 0 or screenHeight <= 0 then return nil end
    local width, height = math.min(screenWidth * .82, MAX_WIDTH), math.min(screenHeight * .86, MAX_HEIGHT)
    local x, y = (screenWidth - width) / 2, (screenHeight - height) / 2
    local saved = Saved()
    saved = saved and saved.window
    if type(saved) == "table" and Finite(saved.x) and Finite(saved.y) then
        -- A smaller screen than last time must not push the window out of reach.
        x = math.max(0, math.min(saved.x, screenWidth - width))
        y = math.max(0, math.min(saved.y, screenHeight - height))
    end
    return { x = x, y = y, width = width, height = height }
end

-- Everything that only exists in window mode: border, close button, drag handle, Escape.
function Window:Decorate(on)
    local Journey, frame, Style = MS.JourneyWorkspace, MS.Workspace.frame, MS.JourneyUIStyle
    if on and not self.border then
        local border = CreateFrame("Frame", nil, frame)
        border:SetAllPoints(frame)
        border:SetFrameLevel(frame:GetFrameLevel() + 100)
        local function Edge(first, second, horizontal)
            local texture = border:CreateTexture(nil, "OVERLAY")
            Style:Color(texture, "borderActive")
            texture:SetPoint(first, border, first)
            texture:SetPoint(second, border, second)
            if horizontal then texture:SetHeight(1) else texture:SetWidth(1) end
        end
        Edge("TOPLEFT", "TOPRIGHT", true)
        Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
        Edge("TOPLEFT", "BOTTOMLEFT", false)
        Edge("TOPRIGHT", "BOTTOMRIGHT", false)
        self.border = border
    end
    if on and not self.closeButton then
        local button = Style:CloseButton(Journey.header, function() Window:Close() end)
        button:SetSize(18, 18)
        button:SetPoint("TOPRIGHT", Journey.header, "TOPRIGHT", -4, -4)
        button:SetScript("OnEnter", function()
            if GameTooltip and GameTooltip.SetOwner then
                GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(MS.L.JOURNEY_WINDOW_CLOSE); GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        self.closeButton = button
    end
    if on and not self.escape then
        -- Escape hides every shown frame named in UISpecialFrames; hiding this child closes the window.
        local escape = CreateFrame("Frame", ESCAPE_FRAME, frame)
        -- Alt+Z hides UIParent, and this child with it: that is not a request to close.
        escape:SetScript("OnHide", function() if Window.open and UIParent:IsShown() then Window:Close() end end)
        if type(_G.UISpecialFrames) == "table" then table.insert(_G.UISpecialFrames, ESCAPE_FRAME) end
        self.escape = escape
    end
    if self.border then self.border:SetShown(on) end
    if self.closeButton then self.closeButton:SetShown(on) end
    if self.escape then self.escape:SetShown(on) end
    if Journey.header then Journey.header:EnableMouse(on) end
    -- On one screen the world is under the window: a click on an empty area must stop here.
    frame:EnableMouse(on)
end

function Window:Open()
    if self.open then return true end
    local available, key = self:Available()
    if not available then Say(key); return nil, key end
    local rect = self:Rect()
    if not rect then Say("JOURNEY_WINDOW_FAILED"); return nil, "JOURNEY_WINDOW_FAILED" end

    local Journey = MS.JourneyWorkspace
    self.previousInset = Journey.BOTTOM_SAFE_INSET
    Journey.BOTTOM_SAFE_INSET = 0
    local called, shown, showError = pcall(MS.Workspace.Show, MS.Workspace, { workspace = rect, window = true })
    if not called or not shown then
        Journey.BOTTOM_SAFE_INSET = self.previousInset or DEFAULT_INSET
        pcall(MS.Workspace.Hide, MS.Workspace)
        Say("JOURNEY_WINDOW_FAILED")
        return nil, showError
    end
    self.open = true
    local started, ready = pcall(Journey.Start, Journey)
    local decorated = started and ready and pcall(self.Decorate, self, true)
    if not decorated then
        self:Close()
        Say("JOURNEY_WINDOW_FAILED")
        return nil, "JOURNEY_WINDOW_FAILED"
    end
    self:StartFade()
    return true
end

-- Always possible. In combat the frame goes at once and the Stop waits for the end of the fight.
function Window:Close()
    if not self.open then return true end
    self.open, self.dragging = false, false
    self:StopFade()
    local Journey, Workspace = MS.JourneyWorkspace, MS.Workspace
    Journey.BOTTOM_SAFE_INSET = self.previousInset or DEFAULT_INSET
    pcall(self.Decorate, self, false)
    local function Finish()
        pcall(Journey.Stop, Journey)
        if MS.TooltipBridge.tooltip then pcall(MS.TooltipBridge.tooltip.Hide, MS.TooltipBridge.tooltip) end
        pcall(Workspace.Hide, Workspace)
    end
    if InCombatLockdown() then
        if Workspace.frame then pcall(Workspace.frame.Hide, Workspace.frame) end
        -- Recovery keeps one pending action: whatever already waits runs right after this one.
        local waiting = MS.Recovery.pending
        MS.Recovery:RunOrQueue(function()
            Finish()
            if waiting then waiting() end
        end)
    else
        Finish()
    end
    return true
end

function Window:Toggle()
    if self.open then return self:Close() end
    return self:Open()
end

function Window:StartDrag()
    local frame = MS.Workspace.frame
    if not self.open or not frame then return end
    self.dragging = true
    pcall(frame.StartMoving, frame)
    self:WakeFade()
end

function Window:StopDrag()
    local frame = MS.Workspace.frame
    if not self.dragging or not frame then return end
    self.dragging = false
    self:WakeFade()
    pcall(frame.StopMovingOrSizing, frame)
    local x, y = frame:GetLeft(), frame:GetBottom()
    local saved = Saved()
    if saved and Finite(x) and Finite(y) then
        saved.window = { x = math.floor(x + .5), y = math.floor(y + .5) }
    end
end

-- While the character moves, the window lets the world show through. Stopping, pointing at it or
-- dragging it brings it back. Only the window fades: the spanned workspace is never touched.
local function PlayerMoving()
    if type(_G.IsPlayerMoving) == "function" then return _G.IsPlayerMoving() == true end
    return type(_G.GetUnitSpeed) == "function" and (_G.GetUnitSpeed("player") or 0) > 0
end

function Window:TargetAlpha()
    local Settings = MS.JourneySettings
    if not self.open or not self.moving or self.dragging then return 1 end
    if not Settings or Settings:Get("fadeWhenMoving") ~= true then return 1 end
    local frame = MS.Workspace.frame
    if frame and frame.IsMouseOver and frame:IsMouseOver() then return 1 end
    return Settings:Get("movingOpacity") or 1
end

-- One frame of the fade; true while it must keep running (the pointer can come over while moving).
function Window:StepFade(elapsed)
    local frame = MS.Workspace.frame
    if not frame then return false end
    local target, current = self:TargetAlpha(), frame:GetAlpha()
    local step = math.max(0, elapsed or 0) / FADE_SECONDS
    local alpha = current < target and math.min(target, current + step) or math.max(target, current - step)
    frame:SetAlpha(alpha)
    return alpha ~= target or self.moving == true
end

function Window:WakeFade()
    local fader = self.fader
    if not fader or not self.open then return end
    fader:SetScript("OnUpdate", function(_, elapsed)
        if not Window:StepFade(elapsed) then fader:SetScript("OnUpdate", nil) end
    end)
end

function Window:StartFade()
    if not self.fader then
        self.fader = CreateFrame("Frame")
        self.fader:SetScript("OnEvent", function(_, event)
            Window.moving = event == "PLAYER_STARTED_MOVING"
            Window:WakeFade()
        end)
    end
    pcall(self.fader.RegisterEvent, self.fader, "PLAYER_STARTED_MOVING")
    pcall(self.fader.RegisterEvent, self.fader, "PLAYER_STOPPED_MOVING")
    self.moving = PlayerMoving()
    self:WakeFade()
end

function Window:StopFade()
    if self.fader then
        self.fader:UnregisterAllEvents()
        self.fader:SetScript("OnUpdate", nil)
    end
    self.moving = false
    local frame = MS.Workspace and MS.Workspace.frame
    if frame and frame.SetAlpha then frame:SetAlpha(1) end
end

if MS.JourneySettings then
    MS.JourneySettings:Listen(function(key)
        if key == "fadeWhenMoving" or key == "movingOpacity" then Window:WakeFade() end
    end)
end

function _G.Hearthside_ToggleWindow()
    Window:Toggle()
end

_G.BINDING_HEADER_HEARTHSIDE = MS.L.BINDING_HEADER_HEARTHSIDE
_G.BINDING_NAME_HEARTHSIDE_TOGGLE_WINDOW = MS.L.BINDING_NAME_HEARTHSIDE_TOGGLE_WINDOW
