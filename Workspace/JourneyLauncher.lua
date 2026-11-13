local MS = _G.MS

-- How a one-screen player opens the Journey window without typing: a button on the minimap edge
-- and an entry in Blizzard's AddOns menu (declared in the TOC). Both only call
-- JourneyWindow:Toggle(), which keeps every refusal (spanned, busy, combat). The button is shown
-- only while Journey is not on a second screen, and the player can turn it off in the settings.
MS.JourneyLauncher = {}
local Launcher = MS.JourneyLauncher

local ICON = "Interface\\Icons\\INV_Misc_Map_01"
Launcher.ICON = ICON

local function Setting(key)
    return MS.JourneySettings and MS.JourneySettings:Get(key)
end

-- The multi-screen engine owns Journey: nothing to open on this screen.
function Launcher:Spanned()
    local runtime = MS.Runtime
    if runtime and runtime.state ~= "DISABLED" then return true end
    return MS.UIParentViewport ~= nil and MS.UIParentViewport:IsApplied() == true
end

function Launcher:ShouldShow()
    return Setting("showMinimapButton") == true and not self:Spanned()
end

-- Position on the minimap edge from an angle in degrees; a square minimap keeps its corners.
function Launcher:Offset(angle, width, height)
    local radians = math.rad(angle)
    local x, y = math.cos(radians), math.sin(radians)
    local square = type(_G.GetMinimapShape) == "function" and _G.GetMinimapShape() == "SQUARE"
    if square then
        local scale = 1 / math.max(math.abs(x), math.abs(y))
        x, y = x * scale, y * scale
    end
    return x * (width / 2 + 5), y * (height / 2 + 5)
end

function Launcher:Place()
    local button, minimap = self.button, _G.Minimap
    if not button or not minimap then return end
    local x, y = self:Offset(Setting("minimapAngle") or 210, minimap:GetWidth(), minimap:GetHeight())
    button:ClearAllPoints()
    button:SetPoint("CENTER", minimap, "CENTER", x, y)
end

-- Cursor angle around the minimap centre, in whole degrees [0, 360).
function Launcher:CursorAngle()
    local minimap = _G.Minimap
    local cx, cy = minimap:GetCenter()
    local x, y = GetCursorPosition()
    local scale = minimap:GetEffectiveScale()
    local angle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
    return math.floor(angle + .5) % 360
end

local function Tooltip(owner)
    if not GameTooltip or not GameTooltip.SetOwner then return end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine(MS.L.JOURNEY_LAUNCHER_TITLE)
    if Launcher:Spanned() then
        GameTooltip:AddLine(MS.L.JOURNEY_LAUNCHER_SPANNED, 1, 1, 1, true)
    else
        GameTooltip:AddLine(MS.L.JOURNEY_LAUNCHER_TOGGLE, 1, 1, 1, true)
        if owner == Launcher.button then GameTooltip:AddLine(MS.L.JOURNEY_LAUNCHER_DRAG, 1, 1, 1, true) end
    end
    GameTooltip:Show()
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

function Launcher:Create()
    if self.button or not _G.Minimap then return self.button end
    local button = CreateFrame("Button", "HearthsideMinimapButton", _G.Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", button, "TOPLEFT")
    button:SetScript("OnClick", function() Launcher:Activate() end)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", HideTooltip)
    button:SetScript("OnDragStart", function(self)
        HideTooltip()
        self:SetScript("OnUpdate", function()
            MS.JourneySettings:Set("minimapAngle", Launcher:CursorAngle())
            Launcher:Place()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    self.button = button
    self:Place()
    return button
end

function Launcher:Refresh()
    local show = self:ShouldShow()
    if not self.button then
        if not show then return end
        self:Create()
        if not self.button then return end
    end
    if self.button:IsShown() ~= show then self.button:SetShown(show) end
end

function Launcher:Activate()
    if MS.JourneyWindow then MS.JourneyWindow:Toggle() end
end

-- The engine is only read, never hooked: a span or a restore changes the screen size, a queued
-- one finishes after combat, and a light one-second look catches anything else.
function Launcher:Start()
    if self.started then return end
    self.started = true
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(events.RegisterEvent, events, "DISPLAY_SIZE_CHANGED")
    pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function()
        Launcher:Refresh()
        -- The runtime settles on the next frame after a size change.
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(0, function() Launcher:Refresh() end)
        end
    end)
    if type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        self.ticker = C_Timer.NewTicker(1, function() Launcher:Refresh() end)
    end
    if MS.JourneySettings then
        MS.JourneySettings:Listen(function(key)
            if key == "showMinimapButton" then Launcher:Refresh() end
        end)
    end
end

-- Runtime and Recovery load after the Workspace files: hook them once everything is loaded.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Launcher:Start()
end)

-- Blizzard's AddOns menu (TOC: AddonCompartmentFunc*): called as (addonName, mouseButton).
function _G.Hearthside_OnAddonCompartmentClick()
    Launcher:Activate()
end

function _G.Hearthside_OnAddonCompartmentEnter(_, menuButton)
    if menuButton then Tooltip(menuButton) end
end

function _G.Hearthside_OnAddonCompartmentLeave()
    HideTooltip()
end
