local MS = _G.MS

-- The small menu set into the Journey map, top right: which icons the map draws. One row per kind,
-- with its icon, its name and a check box; every row is a setting of JourneySettings.
MS.JourneyMapFilter = { rows = {}, width = 230, rowHeight = 24 }
local Filter = MS.JourneyMapFilter
local L = function() return MS.L end

-- key: the setting; kind: an icon of JourneyMapExtras. The other two draw their own.
Filter.list = {
    { key = "showQuestieOffers", label = "JOURNEY_MAP_FILTER_OFFERS", quest = true },
    { key = "mapIconDUNGEON", label = "JOURNEY_MAP_FILTER_DUNGEONS", kind = "DUNGEON" },
    { key = "mapIconRAID", label = "JOURNEY_MAP_FILTER_RAIDS", kind = "RAID" },
    { key = "mapIconREPAIR", label = "JOURNEY_MAP_SERVICE_REPAIR", kind = "REPAIR" },
    { key = "mapIconFLIGHT", label = "JOURNEY_MAP_SERVICE_FLIGHT", kind = "FLIGHT" },
    { key = "mapIconINN", label = "JOURNEY_MAP_SERVICE_INN", kind = "INN" },
    { key = "mapIconTRAINER", label = "JOURNEY_MAP_SERVICE_TRAINER", kind = "TRAINER" },
    { key = "mapIconBANK", label = "JOURNEY_MAP_SERVICE_BANK", kind = "BANK" },
    { key = "mapIconAUCTION", label = "JOURNEY_MAP_SERVICE_AUCTION", kind = "AUCTION" },
    { key = "mapIconMAILBOX", label = "JOURNEY_MAP_FILTER_MAILBOXES", kind = "MAILBOX" },
    { key = "mapIconFELLOW", label = "JOURNEY_MAP_FILTER_FELLOWS", kind = "FELLOW" },
    { key = "showTravelTrace", label = "JOURNEY_MAP_FILTER_TRACE", trace = true },
}

local function On(key) return MS.JourneySettings:Get(key) ~= false end

local function Fill(frame, r, g, b, alpha)
    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(frame)
    texture:SetColorTexture(r, g, b, alpha)
    return texture
end

local function Text(parent, font, text)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetText(text)
    return label
end

local function PaintIcon(icon, item)
    if item.kind then
        MS.JourneyMapExtras:PaintIcon(icon, item.kind)
    elseif item.quest and MS.JourneyPinAssets then
        MS.JourneyPinAssets:Apply(icon, "AVAILABLE", { .93, .75, .33 })
    else
        icon:SetSize(16, 3) -- the route is a line
        icon:SetColorTexture(.75, .16, .1, 1)
    end
end

function Filter:Row(item, index)
    local row = CreateFrame("Button", nil, self.panel)
    row:SetSize(self.width - 12, self.rowHeight)
    row:SetPoint("TOPLEFT", self.panel, "TOPLEFT", 6, -6 - (index - 1) * self.rowHeight)
    row.hover = Fill(row, 1, 1, 1, .10)
    row.hover:Hide()
    row.box = row:CreateTexture(nil, "ARTWORK")
    row.box:SetSize(22, 22)
    row.box:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetSize(22, 22)
    row.check:SetPoint("CENTER", row.box, "CENTER")
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("CENTER", row, "LEFT", 37, 0)
    PaintIcon(row.icon, item)
    row.label = Text(row, "GameFontHighlight", L()[item.label])
    row.label:SetPoint("LEFT", row, "LEFT", 54, 0)
    row.item = item
    row:SetScript("OnEnter", function() row.hover:Show() end)
    row:SetScript("OnLeave", function() row.hover:Hide() end)
    row:SetScript("OnClick", function() MS.JourneySettings:Set(item.key, not On(item.key)) end)
    return row
end

-- Everything at once: hides all when every row is on, else shows all.
function Filter:AllOn()
    for _, item in ipairs(self.list) do
        if not On(item.key) then return false end
    end
    return true
end

function Filter:ToggleAll()
    local value = not self:AllOn()
    for _, item in ipairs(self.list) do MS.JourneySettings:Set(item.key, value) end
end

function Filter:Build(map)
    if self.button then return end
    self.map = map
    local level = (map:GetFrameLevel() or 0) + 210
    local button = CreateFrame("Button", nil, map)
    button:SetPoint("TOPRIGHT", map, "TOPRIGHT", -10, -10)
    button:SetFrameLevel(level)
    button.shade = Fill(button, 0, 0, 0, .6)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(18, 18)
    button.icon:SetPoint("LEFT", button, "LEFT", 6, 0)
    button.icon:SetTexture("Interface\\Minimap\\Tracking\\None")
    button.label = Text(button, "GameFontNormal", L().JOURNEY_MAP_FILTER)
    button.label:SetPoint("LEFT", button.icon, "RIGHT", 5, 0)
    button:SetSize(36 + (button.label:GetStringWidth() or 50), 26)
    button:SetScript("OnEnter", function() button.shade:SetColorTexture(.25, .2, .12, .85) end)
    button:SetScript("OnLeave", function() button.shade:SetColorTexture(0, 0, 0, .6) end)
    button:SetScript("OnClick", function() Filter:Toggle() end)
    local panel = CreateFrame("Frame", nil, map)
    panel:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
    panel:SetSize(self.width, 12 + #self.list * self.rowHeight + 30)
    panel:SetFrameLevel(level)
    panel:EnableMouse(true) -- a click between two rows must not reach the map
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function() end)
    Fill(panel, .08, .06, .04, .92)
    panel:Hide()
    self.button, self.panel = button, panel
    for index, item in ipairs(self.list) do self.rows[index] = self:Row(item, index) end
    local all = CreateFrame("Button", nil, panel)
    all:SetSize(self.width - 12, 24)
    all:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, 6)
    all.label = Text(all, "GameFontNormal", "")
    all.label:SetPoint("CENTER", all, "CENTER")
    all:SetScript("OnEnter", function() all.label:SetTextColor(1, 1, 1) end)
    all:SetScript("OnLeave", function() all.label:SetTextColor(1, .82, 0) end)
    all:SetScript("OnClick", function() Filter:ToggleAll() end)
    self.all = all
    map:HookScript("OnHide", function() panel:Hide() end)
    MS.JourneySettings:Listen(function() Filter:Refresh() end)
end

function Filter:Toggle()
    self.panel:SetShown(not self.panel:IsShown())
    self:Refresh()
end

function Filter:Refresh()
    local panel = self.panel
    if not panel or not panel:IsShown() then return end
    -- A short map shrinks the menu rather than cutting it.
    local room = (self.map:GetHeight() or 0) - 50
    panel:SetScale(math.max(.6, math.min(1, room / panel:GetHeight())))
    for _, row in ipairs(self.rows) do
        local on = On(row.item.key)
        row.check:SetShown(on)
        row.icon:SetAlpha(on and 1 or .35)
        row.label:SetAlpha(on and 1 or .55)
    end
    self.all.label:SetText(self:AllOn() and L().JOURNEY_MAP_FILTER_NONE or L().JOURNEY_MAP_FILTER_ALL)
end
