local MS = _G.MS
MS.ChroniclesView = { visible = false, page = "HOME" }
local View = MS.ChroniclesView

local function Label(parent, style, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if style == "PAGE_TITLE" then MS.JourneyUIStyle:Heading(label, style, "ink")
    else MS.JourneyUIStyle:Body(label, style, "ink") end
    MS.JourneyUIStyle:Text(label, color == "textSecondary" and "inkSecondary" or "ink")
    label:SetJustifyH("LEFT")
    return label
end

local function Button(parent, onClick)
    local button = CreateFrame("Button", nil, parent)
    button.back = button:CreateTexture(nil, "BACKGROUND")
    button.back:SetAllPoints(button)
    MS.JourneyUIStyle:Color(button.back, "backgroundRaised")
    button.label = Label(button, "BODY", "textPrimary")
    button.label:SetPoint("LEFT", button, "LEFT", 10, 0)
    button:SetScript("OnClick", onClick)
    return button
end

local function Place(label, anchor, x, y, width, value)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -y)
    label:SetWidth(math.max(1, width))
    label:SetText(value)
end

function View:Create(parent)
    if self.frame then return end
    self.frame = CreateFrame("Frame", nil, parent)
    self.background = self.frame:CreateTexture(nil, "BACKGROUND")
    self.background:SetAllPoints(self.frame)
    MS.JourneyUIStyle:PageMaterial(self.background, "PAPER")
    self.title = Label(self.frame, "PAGE_TITLE", "gold")
    self.subtitle = Label(self.frame, "BODY", "textSecondary")
    self.titleLink = CreateFrame("Button", nil, self.frame)
    self.titleLink:SetScript("OnClick", function() View:OpenHome() end)
    MS.JourneyUIStyle:Link(self.titleLink, self.title, true)
    self.home = Button(self.frame, function() View:OpenHome() end)
    self.home.label:SetText(MS.L.CHRONICLES_HOME)
    self.breadcrumbs = { self.home }
    for index = 2, 3 do
        self.breadcrumbs[index] = Button(self.frame, function()
            if index == 2 then View.page = "GRIMOIRE"; View:Refresh()
            else View:OpenRegion(View.regionID) end
        end)
    end
    for _, button in ipairs(self.breadcrumbs) do
        button.back:Hide(); MS.JourneyUIStyle:Link(button, button.label, true)
    end
    self.homeScroll = CreateFrame("ScrollFrame", nil, self.frame)
    self.homeContent = CreateFrame("Frame", nil, self.homeScroll)
    self.homeContent:SetSize(1, 1)
    self.homeScroll:SetScrollChild(self.homeContent)
    self.homeScroll:EnableMouseWheel(true)
    self.homeScroll:SetScript("OnMouseWheel", function(frame, delta)
        local maximum = math.max(0, self.homeContent:GetHeight() - frame:GetHeight())
        frame:SetVerticalScroll(math.max(0,
            math.min(maximum, frame:GetVerticalScroll() - delta * 40)))
    end)
    self.unreadHeading = Label(self.homeContent, "SECTION", "gold")
    self.unreadEmpty = Label(self.homeContent, "BODY", "textSecondary")
    self.regionHeading = Label(self.homeContent, "SECTION", "gold")
    self.regionEmpty = Label(self.homeContent, "BODY", "textSecondary")
    self.grimoire = Button(self.homeContent, function()
        View.page = "GRIMOIRE"
        View:Refresh()
    end)
    self.grimoire.label:SetText(MS.L.CHRONICLES_GRIMOIRE)
    self.grimoire.back:Hide(); MS.JourneyUIStyle:Link(self.grimoire, self.grimoire.label, true)
    self.rows, self.regionRows = {}, {}
    self.collectionLabels, self.sealLabels = {}, {}
    self.reader = CreateFrame("ScrollFrame", nil, self.frame)
    self.readerContent = CreateFrame("Frame", nil, self.reader)
    self.readerContent:SetSize(1, 1)
    self.reader:SetScrollChild(self.readerContent)
    self.reader:EnableMouseWheel(true)
    self.reader:SetScript("OnMouseWheel", function(frame, delta)
        local maximum = math.max(0, self.readerContent:GetHeight() - frame:GetHeight())
        frame:SetVerticalScroll(math.max(0,
            math.min(maximum, frame:GetVerticalScroll() - delta * 40)))
    end)
    self.readerTitle = Label(self.readerContent, "PAGE_TITLE", "gold")
    self.readerMeta = Label(self.readerContent, "BODY", "textSecondary")
    self.readerBody = Label(self.readerContent, "BODY_LARGE", "textPrimary")
    self.readerBody:SetJustifyV("TOP")
    self.frame:Hide()
end

function View:Layout(rect)
    if not self.frame then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    self.frame:SetSize(rect.width, rect.height)
    self.width, self.height = rect.width, rect.height
    local readingWidth, inset = MS.JourneyUIStyle:ReadingColumn(rect.width)
    self.readingWidth = readingWidth
    Place(self.title, self.frame, inset, 20, readingWidth, MS.L.CHRONICLES_TITLE)
    Place(self.subtitle, self.frame, inset, 60, readingWidth, MS.L.CHRONICLES_SUBTITLE)
    self.titleLink:ClearAllPoints(); self.titleLink:SetPoint("TOPLEFT", self.frame, "TOPLEFT", inset, -16)
    self.titleLink:SetSize(math.min(340, readingWidth), 40)
    for index, button in ipairs(self.breadcrumbs) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", inset + (index - 1) * math.min(200, (readingWidth) / 3), -86)
        button:SetSize(math.max(1, math.min(196, (readingWidth) / 3)), 28)
        button.label:SetWidth(button:GetWidth() - 12)
    end
    self.reader:ClearAllPoints()
    self.reader:SetPoint("TOPLEFT", self.frame, "TOPLEFT", inset, -124)
    self.reader:SetSize(math.max(1, readingWidth), math.max(1, rect.height - 142))
    self.readerContent:SetWidth(math.max(1, readingWidth - 14))
    self.homeScroll:ClearAllPoints()
    self.homeScroll:SetPoint("TOPLEFT", self.frame, "TOPLEFT", inset, -124)
    self.homeScroll:SetSize(math.max(1, readingWidth),
        math.max(1, rect.height - 142))
    self.homeContent:SetWidth(math.max(1, readingWidth - 14))
    self:Refresh()
end

function View:SetVisible(visible)
    self.visible = visible == true
    if self.frame then self.frame:SetShown(self.visible) end
    if self.visible then self:Refresh() end
end

function View:OpenHome()
    self.page, self.openID, self.regionID, self.readerReturnPage = "HOME", nil, nil, nil
    self:Refresh()
    return true
end

function View:RefreshBreadcrumbs(item)
    local showHierarchy = self.page ~= "HOME"
    self.home:SetShown(showHierarchy)
    self.breadcrumbs[2].label:SetText(MS.L.CHRONICLES_GRIMOIRE)
    self.breadcrumbs[2]:SetShown(showHierarchy)
    local region = item and item.region or self.page == "REGION" and self.regionID
    self.breadcrumbs[3]:SetShown(region ~= nil and region ~= false)
    if region then
        self.regionID = region
        self.breadcrumbs[3].label:SetText(MS.Chronicles:GetRegionName(region))
    end
end

function View:OpenChronicle(id)
    local chronicles = MS.Chronicles
    if not self.visible or not self.frame or not self.width then return nil end
    local item = chronicles:GetChronicle(id)
    if not item then return nil end
    local previousPage, previousID = self.page, self.openID
    self.readerReturnPage = previousPage == "READER" and self.readerReturnPage or previousPage
    self.page, self.openID = "READER", id
    if not pcall(self.Refresh, self) then
        self.page, self.openID = previousPage, previousID
        pcall(self.Refresh, self)
        return nil
    end
    local clockOK, now = pcall(_G.time)
    if not clockOK then now = nil end
    -- false means this Chronicle was already read; nil means no valid commit.
    if chronicles:MarkChronicleRead(id, now) == nil then
        self.page, self.openID = previousPage, previousID
        self:Refresh()
        return nil
    end
    if MS.JourneyWorkspace and MS.JourneyWorkspace.RefreshChroniclesAttention then
        MS.JourneyWorkspace:RefreshChroniclesAttention()
    end
    return true
end

function View:OpenRegion(id)
    if not self.visible or not self.frame or not self.width then return nil end
    local summary = MS.Chronicles:GetRegionSummary(id)
    if not summary or summary.state == "UNKNOWN" and summary.discovered == 0 then return nil end
    self.regionID, self.page = id, "REGION"
    self:Refresh()
    return true
end

function View:HomeEmptyText()
    local chronicles = MS.Chronicles
    local state = chronicles.GetCharacterState and chronicles:GetCharacterState()
    local discovered, unread = false, false
    if type(state) == "table" and type(state.chronicles) == "table" then
        for _, record in pairs(state.chronicles) do
            if type(record) == "table" and record.discoveredAt then
                discovered = true
                if not record.readAt then unread = true end
            end
        end
    end
    if discovered then return MS.L[unread and "CHRONICLES_NOT_AVAILABLE" or "CHRONICLES_UP_TO_DATE"] end
    return MS.L.CHRONICLES_NOT_DISCOVERED
end

function View:Refresh()
    if not self.frame or not self.width then return end
    local chronicles = MS.Chronicles
    local item = self.page == "READER" and chronicles:GetChronicle(self.openID)
    if self.page == "READER" and not item then self.page = "HOME" end
    local reading = self.page == "READER"
    self.reader:SetShown(reading)
    self.homeScroll:SetShown(not reading)
    self:RefreshBreadcrumbs(item)
    self.unreadHeading:SetShown(not reading)
    self.unreadEmpty:SetShown(not reading)
    self.regionHeading:SetShown(self.page == "GRIMOIRE")
    self.regionEmpty:Hide()
    self.grimoire:Hide()
    for _, row in ipairs(self.rows) do row:SetShown(false) end
    for _, row in ipairs(self.regionRows) do row:SetShown(false) end
    for _, label in ipairs(self.collectionLabels) do label:Hide() end
    for _, label in ipairs(self.sealLabels) do label:Hide() end
    self.collectionLabelCount = 0
    if reading then
        local width = self.readerContent:GetWidth() - 20
        Place(self.readerTitle, self.readerContent, 0, 0, width, item.title)
        local metaY = (self.readerTitle:GetStringHeight() or 0) + 14
        local typeLabel = MS.L["CHRONICLES_TYPE_" .. item.type] or item.type
        local formatLabel = MS.L["CHRONICLES_FORMAT_" .. item.format] or item.format
        Place(self.readerMeta, self.readerContent, 0, metaY, width,
            chronicles:GetRegionName(item.region) .. "  ·  " .. typeLabel .. "  ·  " .. formatLabel)
        local bodyY = metaY + (self.readerMeta:GetStringHeight() or 0) + 18
        Place(self.readerBody, self.readerContent, 0, bodyY, width, item.body)
        self.readerContent:SetHeight(math.max(self.reader:GetHeight(),
            bodyY + (self.readerBody:GetStringHeight() or 0) + 24))
        self.reader:SetVerticalScroll(0)
        return
    end
    local width = self.homeContent:GetWidth() - 4
    local regionPage, grimoirePage = self.page == "REGION", self.page == "GRIMOIRE"
    Place(self.unreadHeading, self.homeContent, 0, 0, width,
        regionPage and chronicles:GetRegionName(self.regionID) or MS.L.CHRONICLES_UNREAD)
    self.unreadHeading:SetShown(not grimoirePage)
    local unread = regionPage and chronicles:GetChroniclesForRegion(self.regionID)
        or grimoirePage and {} or chronicles:GetUnreadChronicles()
    self.unreadEmpty:SetShown(not grimoirePage and #unread == 0)
    if #unread == 0 then
        Place(self.unreadEmpty, self.homeContent, 0, 34, math.min(width, 620),
            regionPage and MS.L.CHRONICLES_REGION_EMPTY or self:HomeEmptyText())
    end
    local y = grimoirePage and 0 or 34
    if #unread == 0 and not grimoirePage then
        y = y + (self.unreadEmpty:GetStringHeight() or 0) + 12
    end
    for index, entry in ipairs(unread) do
        local row = self.rows[index]
        if not row then
            row = Button(self.homeContent, function(button) View:OpenChronicle(button.chronicleID) end)
            self.rows[index] = row
        end
        MS.JourneyUIStyle:Link(row, row.label, true)
        row.back:Hide()
        row.chronicleID = entry.id
        row.label:SetText(entry.title .. "  ·  " .. chronicles:GetRegionName(entry.region))
        row.label:SetWidth(math.max(1, width - 20))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.homeContent, "TOPLEFT", 0, -y)
        local rowHeight = math.max(30, (row.label:GetStringHeight() or 0) + 12)
        row:SetSize(math.max(1, width), rowHeight)
        row:Show()
        y = y + rowHeight + 6
    end
    if regionPage then
        y = self:RenderCollections(self.regionID, y, width)
        y = self:RenderSeals(self.regionID, y, width)
        self.homeContent:SetHeight(math.max(self.homeScroll:GetHeight(), y + 20))
        self.homeScroll:SetVerticalScroll(0)
        return
    end
    if not grimoirePage then
        self.grimoire:ClearAllPoints()
        self.grimoire:SetPoint("TOPLEFT", self.homeContent, "TOPLEFT", 0, -(y + 20))
        self.grimoire:SetSize(math.max(1, width), 30)
        self.grimoire:Show()
        self.regionHeading:Hide()
        self.homeContent:SetHeight(math.max(self.homeScroll:GetHeight(), y + 70))
        self.homeScroll:SetVerticalScroll(0)
        return
    end
    self.grimoire:Hide()
    Place(self.regionHeading, self.homeContent, 0, y, width, MS.L.CHRONICLES_GRIMOIRE)
    y = y + 34
    local regions = chronicles:GetRegions()
    if #regions == 0 then
        Place(self.regionEmpty, self.homeContent, 0, y, width, MS.L.CHRONICLES_GRIMOIRE_EMPTY)
        self.regionEmpty:Show()
        y = y + (self.regionEmpty:GetStringHeight() or 0) + 12
    end
    for index, region in ipairs(regions) do
        local row = self.regionRows[index]
        if not row then
            row = Button(self.homeContent, function(button) View:OpenRegion(button.regionID) end)
            self.regionRows[index] = row
        end
        MS.JourneyUIStyle:Link(row, row.label, true)
        row.back:Hide()
        row.regionID = region.id
        local stateLabel = MS.L["CHRONICLES_STATE_" .. region.state] or region.state
        local count = region.discovered > 0 and "  ·  " .. region.discovered or ""
        row.label:SetText((region.name or MS.L.CHRONICLES_UNKNOWN_REGION)
            .. "  ·  " .. stateLabel .. count)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 10 + region.depth * 14, 0)
        row.label:SetWidth(math.max(1, width - 20 - region.depth * 14))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.homeContent, "TOPLEFT", 0, -y)
        local rowHeight = math.max(30, (row.label:GetStringHeight() or 0) + 12)
        row:SetSize(math.max(1, width), rowHeight)
        row:Show()
        y = y + rowHeight + 6
        y = self:RenderCollections(region.id, y, width, true)
    end
    y = self:RenderSeals(nil, y, width)
    self.homeContent:SetHeight(math.max(self.homeScroll:GetHeight(), y + 20))
    self.homeScroll:SetVerticalScroll(0)
end

function View:RenderCollections(regionID, y, width, append)
    local items = MS.Chronicles.GetCollectionsForRegion
        and MS.Chronicles:GetCollectionsForRegion(regionID) or {}
    local index = append and (self.collectionLabelCount or 0) or 0
    for _, item in ipairs(items) do
        index = index + 1
        local label = self.collectionLabels[index]
        if not label then
            label = Label(self.homeContent, "BODY", "textSecondary")
            self.collectionLabels[index] = label
        end
        local progress = item.total and string.format(MS.L.CHRONICLES_COLLECTION_PROGRESS,
            item.discovered, item.total) or string.format(MS.L.CHRONICLES_COLLECTION_DISCOVERIES, item.discovered)
        local complete = item.state == "COMPLETED" and "  ·  " .. MS.L.CHRONICLES_COLLECTION_COMPLETED or ""
        Place(label, self.homeContent, 14, y, width - 14, item.name .. "  ·  " .. progress .. complete)
        label:Show()
        y = y + (label:GetStringHeight() or 0) + 12
    end
    self.collectionLabelCount = index
    return y
end

function View:RenderSeals(regionID, y, width)
    local items = MS.Chronicles.GetSealsForRegion and MS.Chronicles:GetSealsForRegion(regionID) or {}
    for index, item in ipairs(items) do
        local label = self.sealLabels[index]
        if not label then
            label = Label(self.homeContent, "BODY", "gold")
            self.sealLabels[index] = label
        end
        local text = string.format(MS.L.CHRONICLES_SEAL_OBTAINED, item.name)
        if item.description then text = text .. " — " .. item.description end
        Place(label, self.homeContent, 14, y + 8, width - 14, text)
        label:Show()
        y = y + (label:GetStringHeight() or 0) + 20
    end
    return y
end
