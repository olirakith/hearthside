local MS = _G.MS

-- Dialogue frames that anchor to the screen, while UIParent = GAME.
-- The screen is the whole span here:
-- those anchors move to UIParent, with the same points and offsets.
-- During a dialogue UIParent can be hidden: WORKSPACE_ROOT leaves it meanwhile.
-- Those frames keep their behaviour, and without a span nothing happens.
MS.DialogueUICompat = { hooked = {} }
local Compat = MS.DialogueUICompat

local DIALOGS = { "DUIQuestFrame", "DUIBookFrame" }
local ANCHORED = { "DUIQuestFrame", "DUIBookFrame", "DUIDialogSettings" }

local function Spanned()
    local viewport = MS.UIParentViewport
    return viewport ~= nil and viewport:IsApplied()
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

function Compat:Move(frame, point, relativePoint, x, y)
    self.moving = true
    pcall(frame.SetPoint, frame, point, UIParent, relativePoint, x, y)
    self.moving = false
end

function Compat:Hook(frame)
    if self.hooked[frame] or type(frame.SetPoint) ~= "function" then return end
    self.hooked[frame] = true
    hooksecurefunc(frame, "SetPoint", function(_, point, relativeTo, relativePoint, x, y)
        if self.moving or relativeTo ~= nil or type(relativePoint) ~= "string" or not Spanned() then return end
        self:Move(frame, point, relativePoint, x, y)
    end)
end

-- Anchors written before the hook, or before the span.
function Compat:Retarget(frame)
    if type(frame.GetNumPoints) ~= "function" then return end
    for index = 1, frame:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
        if point and relativeTo == nil then self:Move(frame, point, relativePoint, x, y) end
    end
end

-- The status bars, the chat and the banner become children after loading.
function Compat:Cover(frame)
    self:Hook(frame)
    if Spanned() then self:Retarget(frame) end
    for _, child in ipairs({ frame:GetChildren() }) do
        self:Hook(child)
        if Spanned() then self:Retarget(child) end
    end
end

function Compat:Sync()
    local roots = MS.ViewportRoots
    local open = false
    for _, name in ipairs(DIALOGS) do
        local frame = _G[name]
        open = open or (frame ~= nil and frame:IsShown())
    end
    if InCombat() then self.pending = true; return end
    self.pending = nil
    if open and Spanned() then roots:DetachWorkspace() else roots:AttachWorkspace() end
end

function Compat:Install()
    for _, name in ipairs(ANCHORED) do
        local frame = _G[name]
        if frame then
            self:Cover(frame)
            frame:HookScript("OnShow", function() self:Cover(frame); self:Sync() end)
            frame:HookScript("OnHide", function() self:Sync() end)
        end
    end
    self.installed = _G.DUIQuestFrame ~= nil
end

if type(CreateFrame) == "function" then
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_LOGIN")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then Compat:Install()
        elseif Compat.pending then Compat:Sync() end
    end)
end
