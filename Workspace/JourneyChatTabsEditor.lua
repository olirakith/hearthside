local MS = _G.MS

-- Settings > Discussion > Tabs (Docs/journey/CHAT-FILTRES-FICHE.md): the player's tabs as chips,
-- the chosen tab's name, order and content (the game's message groups by section, and channels),
-- copying the game's window, and going back to the default tabs. Lives on the Settings page;
-- JourneySettings places it and lends its widgets.
MS.JourneyChatTabsEditor = { selected = 1, columnWidth = 210, rowHeight = 24 }
local Editor = MS.JourneyChatTabsEditor

local function Tabs() return MS.JourneyChatTabs end
local function Style() return MS.JourneyUIStyle end

-- A small check box with its label.
function Editor:Check(key, run)
    self.checks = self.checks or {}
    local check = self.checks[key]
    if check then check.run = run; return check end
    check = CreateFrame("Button", nil, self.page)
    check.run = run
    check.box = check:CreateTexture(nil, "ARTWORK")
    check.box:SetSize(14, 14)
    check.box:SetPoint("LEFT", check, "LEFT", 2, 0)
    Style():Color(check.box, "borderActive")
    check.fill = check:CreateTexture(nil, "ARTWORK", nil, 1)
    check.fill:SetPoint("TOPLEFT", check.box, "TOPLEFT", 1, -1)
    check.fill:SetPoint("BOTTOMRIGHT", check.box, "BOTTOMRIGHT", -1, 1)
    Style():Color(check.fill, "backgroundDeep")
    check.mark = check:CreateTexture(nil, "OVERLAY")
    check.mark:SetPoint("TOPLEFT", check.box, "TOPLEFT", 3, -3)
    check.mark:SetPoint("BOTTOMRIGHT", check.box, "BOTTOMRIGHT", -3, 3)
    Style():Color(check.mark, "gold")
    check.label = self.widgets.Label(check, "BODY", "textPrimary", "")
    check.label:SetPoint("LEFT", check.box, "RIGHT", 8, 0)
    check.label:SetPoint("RIGHT", check, "RIGHT", -4, 0)
    check.label:SetWordWrap(false)
    check.hover = check:CreateTexture(nil, "BACKGROUND")
    check.hover:SetAllPoints(check)
    Style():Color(check.hover, "backgroundRaised")
    check.hover:SetAlpha(0)
    check:SetScript("OnEnter", function() check.hover:SetAlpha(.35) end)
    check:SetScript("OnLeave", function() check.hover:SetAlpha(0) end)
    check:SetScript("OnClick", function() if check.run then check.run(not check.on) end end)
    self.checks[key] = check
    return check
end

function Editor:SetCheck(check, on)
    check.on = on == true
    check.mark:SetShown(check.on)
    Style():Text(check.label, check.on and "textPrimary" or "textSecondary")
end

function Editor:Create(page, widgets)
    if self.page then return end
    self.page, self.widgets = page, widgets
    local L, Label, Button = MS.L, widgets.Label, widgets.Button
    self.heading = Label(page, "SECTION", "gold", L.CHAT_TABS_TITLE)
    self.hint = Label(page, "SECONDARY", "textSecondary", L.CHAT_TABS_HINT)
    self.chips = {}
    for index = 1, Tabs().max do
        local chip = Button(page, "", function() Editor:Select(index); Editor:Refresh() end, "preset")
        chip.index = index
        self.chips[index] = chip
    end
    self.add = Button(page, L.CHAT_TAB_ADD, function()
        local added = Tabs():Add()
        if added then Editor:Select(added) end
    end, "small")

    self.nameLabel = Label(page, "BODY_LARGE", "textPrimary", L.CHAT_TAB_NAME)
    local name = CreateFrame("EditBox", nil, page)
    name:SetAutoFocus(false)
    name:SetMaxLetters(Tabs().nameLength)
    name:SetFontObject(_G.GameFontHighlight)
    name:SetTextInsets(10, 10, 0, 0)
    name.back = name:CreateTexture(nil, "BACKGROUND")
    name.back:SetAllPoints(name)
    Style():Color(name.back, "backgroundDeep")
    name.edge = name:CreateTexture(nil, "BORDER")
    name.edge:SetPoint("BOTTOMLEFT", name, "BOTTOMLEFT", 0, 0)
    name.edge:SetPoint("BOTTOMRIGHT", name, "BOTTOMRIGHT", 0, 0)
    name.edge:SetHeight(1)
    Style():Color(name.edge, "borderActive")
    local function commit(owner)
        if owner.reverting then owner.reverting = false; return end
        Tabs():Rename(Editor.selected, owner:GetText())
    end
    name:SetScript("OnEnterPressed", function(owner) owner:ClearFocus() end)
    name:SetScript("OnEditFocusLost", commit)
    name:SetScript("OnEscapePressed", function(owner)
        owner.reverting = true
        owner:SetText(Tabs():Name(Tabs():Get(Editor.selected)))
        owner:ClearFocus()
    end)
    self.name = name

    self.left = Button(page, L.CHAT_TAB_LEFT, function() Editor:Select(Tabs():Move(Editor.selected, -1)) end, "small")
    self.right = Button(page, L.CHAT_TAB_RIGHT, function() Editor:Select(Tabs():Move(Editor.selected, 1)) end, "small")
    self.remove = Button(page, L.CHAT_TAB_REMOVE, function()
        if Tabs():Remove(Editor.selected) then Editor:Select(math.max(1, Editor.selected - 1)) end
    end, "small")

    self.sectionLabels = {}
    for _, key in ipairs({ "TALK", "CREATURES", "REWARDS", "SYSTEM", "OTHER", "CHANNELS" }) do
        self.sectionLabels[key] = Label(page, "BODY_LARGE", "gold", L["CHAT_SECTION_" .. key])
    end
    self.copyGame = Button(page, L.CHAT_TABS_FROM_GAME, function() Tabs():CopyGame(Editor.selected) end, "small")
    self.resetButton = Button(page, L.CHAT_TABS_RESET, function() Editor.confirming = true; Editor:Refresh() end, "small")
    self.resetPrompt = Label(page, "SECONDARY", "textSecondary", L.CHAT_TABS_RESET_CONFIRM)
    self.confirm = Button(page, L.JOURNEY_CONFIRM, function()
        Editor.confirming = false
        Tabs():Reset()
        Editor:Select(1)
    end, "small")
    self.cancel = Button(page, L.JOURNEY_CANCEL, function() Editor.confirming = false; Editor:Refresh() end, "small")

    Tabs():Listen(function() Editor:Changed() end)
end

function Editor:Select(index)
    -- A name being typed belongs to the tab it was typed for: the game keeps the focus on the
    -- field when another chip is clicked.
    local name = self.name
    if name and name:HasFocus() then
        name.reverting = true
        name:ClearFocus()
        Tabs():Rename(self.selected, name:GetText())
    end
    self.selected = math.max(1, math.min(Tabs():Count(), tonumber(index) or 1))
    self:Changed()
end

-- A tab changed: the page lays out again (channels and chips may differ).
function Editor:Changed()
    local settings = MS.JourneySettings
    if self.page and settings and settings.visible and settings.lastRect then
        settings:LayoutView(settings.lastRect)
    else
        self:Refresh()
    end
end

function Editor:Hide()
    if not self.page then return end
    for _, element in ipairs(self:Elements()) do element:Hide() end
    for _, check in pairs(self.checks or {}) do check:Hide() end
end

function Editor:Elements()
    local list = { self.heading, self.hint, self.add, self.nameLabel, self.name, self.left, self.right, self.remove,
        self.copyGame, self.resetButton, self.resetPrompt, self.confirm, self.cancel }
    for _, chip in ipairs(self.chips) do list[#list + 1] = chip end
    for _, label in pairs(self.sectionLabels) do list[#list + 1] = label end
    return list
end

local function Place(page, element, x, y, width, height)
    element:ClearAllPoints()
    element:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
    if width then element:SetWidth(width) end
    if height then element:SetHeight(height) end
    element:Show()
end

local function Text(page, label, x, y, width)
    Place(page, label, x, y, width)
    return math.max(18, label:GetStringHeight() or 18)
end

local function ButtonWidth(button, minimum)
    return math.max(minimum or 96, (button.label:GetStringWidth() or 80) + 28)
end

-- Lays the editor out from (x, y) on the page; returns the y under it.
function Editor:Layout(x, y, width)
    if not self.page then return y end
    local page, L = self.page, MS.L
    self.top = y
    local list = Tabs():List()
    self.selected = math.max(1, math.min(#list, self.selected))
    for _, check in pairs(self.checks or {}) do check:Hide() end

    y = y + Text(page, self.heading, x, y, width) + 8
    y = y + Text(page, self.hint, x, y, width) + 14

    -- Chips, wrapping onto new rows.
    local cx, rowY = x, y
    for index, chip in ipairs(self.chips) do
        local tab = list[index]
        if tab then
            chip.label:SetText(Tabs():Name(tab))
            local chipWidth = ButtonWidth(chip, 90)
            if cx > x and cx + chipWidth > x + width then cx, rowY = x, rowY + 40 end
            Place(page, chip, cx, rowY, chipWidth, 32)
            cx = cx + chipWidth + 8
        else
            chip:Hide()
        end
    end
    local addWidth = ButtonWidth(self.add)
    if cx > x and cx + addWidth > x + width then cx, rowY = x, rowY + 40 end
    Place(page, self.add, cx, rowY, addWidth, 32)
    self.add:SetEnabled(#list < Tabs().max)
    self.add:SetAlpha(#list < Tabs().max and 1 or .45)
    y = rowY + 32 + 18

    -- The chosen tab: name and order.
    y = y + Text(page, self.nameLabel, x, y, width) + 8
    local nameWidth = math.min(280, width)
    Place(page, self.name, x, y, nameWidth, 30)
    if not self.name:HasFocus() then self.name:SetText(Tabs():Name(list[self.selected])) end
    local bx = x + nameWidth + 12
    for _, button in ipairs({ self.left, self.right, self.remove }) do
        local buttonWidth = ButtonWidth(button)
        if bx + buttonWidth > x + width then bx, y = x, y + 38 end
        Place(page, button, bx, y, buttonWidth, 30)
        bx = bx + buttonWidth + 8
    end
    self.left:SetEnabled(self.selected > 1); self.left:SetAlpha(self.selected > 1 and 1 or .45)
    self.right:SetEnabled(self.selected < #list); self.right:SetAlpha(self.selected < #list and 1 or .45)
    self.remove:SetEnabled(#list > 1); self.remove:SetAlpha(#list > 1 and 1 or .45)
    y = y + 30 + 22

    -- What the tab shows.
    local columns = math.max(1, math.floor(width / self.columnWidth))
    local cellWidth = width / columns
    local tab = list[self.selected]
    local function grid(items)
        for position, item in ipairs(items) do
            local column = (position - 1) % columns
            local row = math.floor((position - 1) / columns)
            Place(page, item, x + column * cellWidth, y + row * self.rowHeight, cellWidth - 8, self.rowHeight - 2)
        end
        return math.ceil(#items / columns) * self.rowHeight
    end
    local sections = {}
    for _, section in ipairs(Tabs().SECTIONS) do
        local known = {}
        for _, group in ipairs(section.groups) do
            if Tabs():Known(group) then known[#known + 1] = group end
        end
        sections[#sections + 1] = { key = section.key, groups = known }
    end
    sections[#sections + 1] = { key = "OTHER", groups = Tabs():OtherGroups() }
    for _, section in ipairs(sections) do
        local label = self.sectionLabels[section.key]
        if #section.groups == 0 then
            label:Hide()
        else
            y = y + Text(page, label, x, y, width) + 6
            local items = {}
            for _, group in ipairs(section.groups) do
                local check = self:Check("g:" .. group, function(on) Tabs():SetGroup(Editor.selected, group, on) end)
                check.label:SetText(Tabs():GroupLabel(group))
                self:SetCheck(check, tab and tab.groupSet and tab.groupSet[group])
                items[#items + 1] = check
            end
            y = y + grid(items) + 14
        end
    end
    y = y + Text(page, self.sectionLabels.CHANNELS, x, y, width) + 6
    local items = {}
    local all = self:Check("all", function(on) Tabs():SetAllChannels(Editor.selected, on) end)
    all.label:SetText(L.CHAT_ALL_CHANNELS)
    self:SetCheck(all, tab and tab.allChannels)
    items[1] = all
    for _, channel in ipairs(Tabs():KnownChannels(self.selected)) do
        local check = self:Check("c:" .. string.lower(channel), function(on) Tabs():SetChannel(Editor.selected, channel, on) end)
        check.label:SetText(channel)
        local on = tab and tab.channelSet and tab.channelSet[string.lower(channel)]
        self:SetCheck(check, tab and (tab.allChannels or on))
        check:SetAlpha(tab and tab.allChannels and .5 or 1)
        items[#items + 1] = check
    end
    y = y + grid(items) + 22

    -- Copy the game's window, back to defaults (confirmed on the page).
    local copyWidth = math.min(width, ButtonWidth(self.copyGame, 200))
    Place(page, self.copyGame, x, y, copyWidth, 32)
    local resetWidth = math.min(width, ButtonWidth(self.resetButton, 200))
    if copyWidth + 12 + resetWidth <= width then
        Place(page, self.resetButton, x + copyWidth + 12, y, resetWidth, 32)
    else
        y = y + 40
        Place(page, self.resetButton, x, y, resetWidth, 32)
    end
    y = y + 32 + 12
    local confirming = self.confirming == true
    if confirming then
        y = y + Text(page, self.resetPrompt, x, y, width) + 8
        Place(page, self.confirm, x, y, 112, 30)
        Place(page, self.cancel, x + 120, y, 112, 30)
        y = y + 30 + 8
    else
        self.resetPrompt:Hide(); self.confirm:Hide(); self.cancel:Hide()
    end
    self:Refresh()
    return y
end

-- Chip and button looks.
function Editor:Refresh()
    if not self.page then return end
    for index, chip in ipairs(self.chips) do
        chip.selected = index == self.selected
        self.widgets.Style(chip)
    end
end

-- Scrolls Settings so the editor shows.
function Editor:Reveal()
    local settings = MS.JourneySettings
    if not (settings and settings.scroll and self.top) then return end
    local maximum = math.max(0, settings.content:GetHeight() - settings.scroll:GetHeight())
    settings.scroll:SetVerticalScroll(math.max(0, math.min(maximum, self.top)))
end
