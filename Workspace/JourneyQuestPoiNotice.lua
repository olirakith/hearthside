local MS = _G.MS

-- Blizzard's quest pins and areas draw nothing while the questPOI option is off, and Questie turns
-- it off with its own icon theme. On the Journey map that hides the player's current quests: a
-- notice says so and offers to turn the game's markers back on. Nothing changes without a click.
local Notice = {}
MS.JourneyQuestPoiNotice = Notice

local function Enabled()
    if C_CVar and C_CVar.GetCVarBool then return C_CVar.GetCVarBool("questPOI") ~= false end
    return GetCVarBool("questPOI") ~= false
end

function Notice:Build(canvas)
    local frame = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    frame:SetPoint("TOP", canvas, "TOP", 0, -8)
    frame:SetSize(420, 58)
    frame:SetFrameLevel(canvas:GetFrameLevel() + 200)
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        frame:SetBackdropColor(0, 0, 0, .8)
        frame:SetBackdropBorderColor(1, .82, 0, .6)
    end
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.text:SetPoint("TOPLEFT", 10, -8)
    frame.text:SetPoint("TOPRIGHT", -10, -8)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetText(MS.L.JOURNEY_QUESTPOI_OFF)
    frame.button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.button:SetSize(120, 20)
    frame.button:SetPoint("BOTTOMRIGHT", -8, 6)
    frame.button:SetText(MS.L.JOURNEY_QUESTPOI_SHOW)
    frame.button:SetScript("OnClick", function() Notice:TurnOn() end)
    self.frame = frame
    return frame
end

function Notice:TurnOn()
    if InCombatLockdown() then return end
    if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar("questPOI", "1") else SetCVar("questPOI", "1") end
    self.turnedOn = (self.turnedOn or 0) + 1
    self:Update()
    local canvas = MS.JourneyMapCanvas and MS.JourneyMapCanvas.frame
    if canvas and canvas.RefreshAllDataProviders then pcall(canvas.RefreshAllDataProviders, canvas) end
end

function Notice:Update()
    local canvas = MS.JourneyMapCanvas and MS.JourneyMapCanvas.frame
    local wanted = canvas ~= nil and canvas:IsShown() and not Enabled()
    if wanted and not self.frame then self:Build(canvas) end
    if self.frame then self.frame:SetShown(wanted) end
end

Notice.events = CreateFrame("Frame")
Notice.events:RegisterEvent("CVAR_UPDATE")
Notice.events:SetScript("OnEvent", function() Notice:Update() end)
