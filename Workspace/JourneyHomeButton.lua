local MS = _G.MS

-- The Hearthside home (Sur mes pas, Contrat, L'Encre) has no tab: the brand at the left of the tab
-- row is its button. A wax-red mark tells something waits there: a Contrat sheet not closed yet,
-- or a seal opened and not read. Both clear where they are read, not when the home opens.
MS.JourneyHomeButton = {}
local Home = MS.JourneyHomeButton

local HEIGHT, MIN_WIDTH, MAX_WIDTH, PAD = 28, 112, 146, 32
local MARK = { .88, .38, .30 }

local function Active()
    local active = MS.Active
    return active and active:Ready() and active or nil
end

-- Something the player has not seen yet in the home.
function Home:Waiting()
    local A = Active()
    if not A then return false end
    if A.Contracts and A.Contracts:Unseen() then return true end
    local me = A.identity and A.identity.key
    for _, seal in ipairs(A.Seals and A.Seals:All() or {}) do
        if seal.state == "OPENED" and seal.seen == false and seal.openedBy == me then return true end
    end
    return false
end

function Home:Create(parent)
    if self.button then return end
    local Style, L = MS.JourneyUIStyle, MS.L
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(MAX_WIDTH, HEIGHT)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Style:Heading(button.label, "HEADING", "gold")
    button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
    if type(button.label.SetWordWrap) == "function" then button.label:SetWordWrap(false) end
    button.label:SetText(L.JOURNEY_BRAND)
    button.selected = true -- a gold edge: it reads as a way in, not as a tab
    Style:Action(button, button.label)
    -- Action paints its label as body text; the brand stays gold.
    local enter, leave = button:GetScript("OnEnter"), button:GetScript("OnLeave")
    button:SetScript("OnEnter", function(self)
        if enter then enter(self) end
        Style:Text(self.label, "textBright")
        Home:Tooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        if leave then leave(self) end
        Style:Text(self.label, "gold")
        if GameTooltip then GameTooltip:Hide() end
    end)
    Style:Text(button.label, "gold")
    button.mark = button:CreateTexture(nil, "OVERLAY")
    button.mark:SetSize(7, 7)
    button.mark:SetPoint("TOPRIGHT", button, "TOPRIGHT", -4, -4)
    button.mark:SetColorTexture(MARK[1], MARK[2], MARK[3], 1)
    button.mark:Hide()
    -- A rule between the way in and the tabs.
    button.rule = parent:CreateTexture(nil, "ARTWORK")
    button.rule:SetSize(1, HEIGHT - 6)
    button.rule:SetPoint("LEFT", button, "RIGHT", 7, 0)
    Style:Color(button.rule, "borderMuted")
    button:SetScript("OnClick", function() Home:Open() end)
    self.button = button
    self:Refresh()
end

function Home:Tooltip(owner)
    if not (GameTooltip and GameTooltip.SetOwner) then return end
    local L = MS.L
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(L.JOURNEY_HOME_TOOLTIP_TITLE)
    GameTooltip:AddLine(Active() and L.JOURNEY_HOME_TOOLTIP or L.JOURNEY_HOME_UNAVAILABLE, 1, 1, 1, true)
    if self:Waiting() then GameTooltip:AddLine(L.JOURNEY_HOME_WAITING, MARK[1], MARK[2], MARK[3], true) end
    GameTooltip:Show()
end

function Home:Open()
    local A = Active()
    if not (A and A.Panel) then return false end
    A.Panel:Open("HOME")
    return true
end

-- Left of the tabs, on their row; returns the x where the tabs may start.
function Home:Place(header, level)
    local button = self.button
    if not button then return nil end
    local measured = button.label.GetStringWidth and button.label:GetStringWidth()
    local width = math.max(MIN_WIDTH, math.min(MAX_WIDTH, (type(measured) == "number" and measured or MAX_WIDTH) + PAD))
    button:SetSize(width, HEIGHT)
    if type(button.label.SetWidth) == "function" then button.label:SetWidth(width - 12) end
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 8, 2)
    if level then button:SetFrameLevel(level) end
    button:Show()
    return 8 + width + 16
end

function Home:Refresh()
    local button = self.button
    if not button then return end
    local A = Active()
    button.actionDisabled = A == nil
    button:SetAlpha(A and 1 or .45)
    button.mark:SetShown(self:Waiting())
end
