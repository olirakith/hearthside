local MS = _G.MS
MS.Active = MS.Active or {}
-- Where Journey's active views appear, and the few widgets they share. Plain, non-secure frames
-- and colour textures only (no Blizzard template, no protected call): safe on the game screen.
--   WORKSPACE  the Journey second screen, when it is shown
--   SCREEN     otherwise: centred on the game screen, only while there is something to show
local A = MS.Active
local Kit = {}
A.Kit = Kit

function Kit:Host()
    local workspace, journey = MS.Workspace, MS.JourneyWorkspace
    if workspace and workspace.frame and workspace.frame:IsShown() and journey and journey.active ~= false then
        return workspace.frame, "WORKSPACE"
    end
    return _G.UIParent, "SCREEN"
end

local function Style() return MS.JourneyUIStyle end

-- The active views are drawn for the default text size. Their fonts stay at that size and the
-- whole frame scales with the setting: text, boxes and gaps grow together and wrap the same.
Kit.baseScale = 1.1
local zoomed = {}

local function Zoom()
    local settings = MS.JourneySettings
    return (settings and settings:Get("textScale") or Kit.baseScale) / Kit.baseScale
end

function Kit.Zoom(frame)
    zoomed[frame] = true
    frame:SetScale(Zoom())
end

function Kit.Label(parent, token, color, justify)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local style = Style()
    if style then
        if style.ApplyAt then style:ApplyAt(label, token or "BODY", Kit.baseScale) end
        if style.Text then style:Text(label, color or "textPrimary") end
    end
    if type(label.SetShadowOffset) == "function" then label:SetShadowOffset(1, -1) end
    if type(label.SetShadowColor) == "function" then label:SetShadowColor(0, 0, 0, .9) end
    label:SetJustifyH(justify or "LEFT")
    if type(label.SetWordWrap) == "function" then label:SetWordWrap(true) end
    return label
end

function Kit.Paint(label, color)
    local style = Style()
    if style and style.Text then style:Text(label, color) end
end

function Kit.Fill(texture, token, alpha)
    local style = Style()
    if style and style.Color then style:Color(texture, token) end
    if alpha then texture:SetAlpha(alpha) end
end

-- A framed action button whose text is its label.
function Kit.Size(label, token)
    local style = Style()
    if style and style.ApplyAt then style:ApplyAt(label, token, Kit.baseScale) end
end

function Kit.Button(parent, width, height, onClick, paper)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height or 26)
    button.label = Kit.Label(button, "BODY", "textPrimary", "CENTER")
    button.label:SetPoint("LEFT", button, "LEFT", 6, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    local style = Style()
    if style and style.Action then style:Action(button, button.label, paper) end
    button:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
    function button:SetLabel(text) self.label:SetText(text or "") end
    -- Selected toggles keep a gold edge.
    function button:SetSelected(selected)
        self.selected = selected == true
        if self.actionBorder then Kit.Fill(self.actionBorder, self.selected and "gold" or "borderActive") end
    end
    return button
end

-- The shared reaction of custom surfaces: tracks hovered and pressed, then asks the surface to
-- repaint. OnHide clears them, since a clicked surface can vanish under the mouse.
function Kit.Reactive(frame, paint)
    local function Set(hovered, pressed)
        frame.hovered, frame.pressed = hovered, pressed
        paint(frame)
    end
    frame:SetScript("OnEnter", function() Set(true, false) end)
    frame:SetScript("OnLeave", function() Set(false, false) end)
    frame:SetScript("OnMouseDown", function() Set(frame.hovered == true, true) end)
    frame:SetScript("OnMouseUp", function() Set(frame.hovered == true, false) end)
    frame:SetScript("OnHide", function() Set(false, false) end)
end

local function InCombat() return A.Bool(A.Call(_G.InCombatLockdown)) ~= false end

-- Four sounds of the game itself, nothing shipped. Never in a fight, never when the player
-- turned them off, and a sound this client does not know simply stays silent.
Kit.sounds = { CARD = "IG_MAINMENU_OPTION_CHECKBOX_ON", SIGN = "IG_SPELLBOOK_OPEN", CRACK = "U_CHAT_SCROLL_BUTTON",
    TAB = "IG_CHARACTER_INFO_TAB" }

function Kit.Play(name)
    local root = A.Store and A.Store.root
    if (root and root.muted) or InCombat() then return end
    local id = type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT[Kit.sounds[name]] or nil
    if type(id) == "number" and type(_G.PlaySound) == "function" then pcall(_G.PlaySound, id, "SFX") end
end

-- One driver for every short fade; it sleeps when nothing moves. In a fight, frames just appear.
local fades, driver = {}, nil

local function StepFades(_, elapsed)
    for frame, fade in pairs(fades) do
        fade.time = fade.time + (elapsed or 0)
        local progress = math.min(1, fade.time / fade.duration)
        if progress >= 1 or not frame:IsShown() then
            frame:SetAlpha(1)
            fades[frame] = nil
        else
            frame:SetAlpha(1 - (1 - progress) ^ 2)
        end
    end
    if next(fades) == nil then driver:Hide() end
end

function Kit.FadeIn(frame, seconds)
    if InCombat() then
        fades[frame] = nil
        frame:SetAlpha(1)
        return
    end
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", StepFades)
    end
    frame:SetAlpha(0)
    fades[frame] = { time = 0, duration = seconds or .18 }
    driver:Show()
end

-- A single-line text field on a dark inset.
function Kit.Input(parent, width, maxLetters)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 26)
    box:SetAutoFocus(false)
    if type(box.SetFontObject) == "function" then box:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlight) end
    if type(box.SetTextInsets) == "function" then box:SetTextInsets(8, 8, 0, 0) end
    if maxLetters and type(box.SetMaxLetters) == "function" then box:SetMaxLetters(maxLetters) end
    box.back = box:CreateTexture(nil, "BACKGROUND")
    box.back:SetAllPoints(box)
    Kit.Fill(box.back, "backgroundDeep")
    box.edge = box:CreateTexture(nil, "BORDER")
    box.edge:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
    box.edge:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    box.edge:SetHeight(1)
    Kit.Fill(box.edge, "borderActive")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

function Kit.Rule(parent, color)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    Kit.Fill(rule, color or "borderMuted")
    return rule
end

-- Hides every child frame of a view's region list (views reuse their widgets).
function Kit.ShowOnly(items, visible)
    for _, item in ipairs(items) do item:SetShown(visible) end
end

-- A date as "12 octobre" (localized month names; no time of day).
function Kit.Date(timestamp)
    if type(timestamp) ~= "number" then return MS.L.ACTIVE_DATE_UNKNOWN end
    local ok, parts = pcall(_G.date, "*t", timestamp)
    if not ok or type(parts) ~= "table" then return MS.L.ACTIVE_DATE_UNKNOWN end
    local month, index = nil, 0
    for name in string.gmatch(MS.L.ACTIVE_MONTHS or "", "[^,]+") do
        index = index + 1
        if index == parts.month then month = name end
    end
    return string.format(MS.L.ACTIVE_DATE_FORMAT, parts.day, month or tostring(parts.month))
end

Kit.soundToggle = { id = "activeSounds", label = MS.L.ACTIVE_SOUNDS, hint = MS.L.ACTIVE_SOUNDS_HINT,
    get = function() return not (A.Store and A.Store.root and A.Store.root.muted) end,
    set = function(value)
        if A.Store and A.Store.root and not A.Store.readOnly then A.Store.root.muted = not value or nil end
    end }

local Settings = MS.JourneySettings
if Settings and Settings.AddExternalToggle then Settings:AddExternalToggle(Kit.soundToggle) end
if Settings and Settings.Listen then
    Settings:Listen(function(key)
        if key ~= "textScale" then return end
        for frame in pairs(zoomed) do frame:SetScale(Zoom()) end
    end)
end
