local MS = _G.MS
MS.InventoryView = { active = false, supported = false, visible = false, dirty = true,
    refreshCount = 0, deferredRefreshCount = 0, selectedCategory = "OVERVIEW" }
local View = MS.InventoryView
local KINDS = { "OVERVIEW", "TRACKED", "FINDS", "QUEST", "CONSUMABLE",
    "EQUIPMENT", "CRAFTING", "RECIPE", "OTHER" }
local CATEGORIES = { "CONSUMABLE", "EQUIPMENT", "CRAFTING", "RECIPE", "OTHER" }

local function Label(parent, style, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    MS.JourneyUIStyle:Apply(label, style); MS.JourneyUIStyle:Text(label, color)
    label:SetJustifyH("LEFT"); label:SetJustifyV("TOP")
    return label
end
local function Rule(parent, color)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    MS.JourneyUIStyle:Color(texture, color)
    return texture
end
local function Place(label, parent, x, y, width, value)
    label:SetWidth(math.max(1, width)); label:SetText(value or "")
    label:ClearAllPoints(); label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    label:Show()
    return math.max(16, label:GetStringHeight() or 0)
end
local function Sorted(map, data)
    local result = {}
    for id in pairs(map or {}) do result[#result + 1] = id end
    table.sort(result, function(a, b)
        local an = data.items[a] and data.items[a].name or ""
        local bn = data.items[b] and data.items[b].name or ""
        if an == bn then return a < b end
        return an < bn
    end)
    return result
end
local function Name(item, id)
    return item and item.name or string.format(MS.L.JOURNEY_INVENTORY_UNKNOWN_ITEM, id)
end
local function Button(parent, text, callback)
    local button = CreateFrame("Button", nil, parent)
    button.back = Rule(button, "parchmentDark"); button.back:SetAllPoints(button)
    button.label = Label(button, "BODY", "textPrimary")
    button.label:SetPoint("CENTER", button, "CENTER")
    button.label:SetJustifyH("CENTER"); button.label:SetText(text)
    button:SetScript("OnClick", callback)
    MS.JourneyUIStyle:Action(button, button.label)
    return button
end

function View:Create(parent)
    if self.frame then return end
    self.frame = CreateFrame("Frame", nil, parent)
    self.paper = Rule(self.frame, "backgroundPanel"); self.paper:SetAllPoints(self.frame)
    MS.JourneyUIStyle:Material(self.paper, "backgroundPanel")
    self.edge = Rule(self.frame, "borderMuted")
    self.title = Label(self.frame, "PAGE_TITLE", "gold")
    self.subtitle = Label(self.frame, "BODY", "textSecondary")
    self.summary = Label(self.frame, "BODY", "textPrimary")
    self.headerRule = Rule(self.frame, "borderMuted")
    self.unavailable = Label(self.frame, "BODY_LARGE", "textSecondary")
    self.indexHeading = Label(self.frame, "SECTION", "gold")
    self.indexButtons = {}
    for _, kind in ipairs(KINDS) do
        local button = CreateFrame("Button", nil, self.frame)
        button.back = Rule(button, "backgroundDeep"); button.back:SetAllPoints(button)
        button.rule = Rule(button, "borderMuted")
        button.label = Label(button, "BODY", "textPrimary")
        button.count = Label(button, "SMALL", "gold")
        button.kind = kind
        button:SetScript("OnClick", function() View:SelectCategory(kind) end)
        self.indexButtons[kind] = button
    end
    self.listHeading = Label(self.frame, "SECTION", "gold")
    self.listRule = Rule(self.frame, "borderMuted")
    self.scroll = CreateFrame("ScrollFrame", nil, self.frame)
    self.content = CreateFrame("Frame", nil, self.scroll); self.content:SetSize(1, 1)
    self.scroll:SetScrollChild(self.content); self.scroll:EnableMouseWheel(true)
    self.scroll:SetScript("OnMouseWheel", function(scroll, delta)
        local maximum = math.max(0, self.content:GetHeight() - scroll:GetHeight())
        scroll:SetVerticalScroll(math.max(0,
            math.min(maximum, scroll:GetVerticalScroll() - delta * 42)))
    end)
    self.empty = Label(self.content, "BODY", "textSecondary")
    self.sections, self.rows, self.summaryRows, self.gridCells = {}, {}, {}, {}
    for _, kind in ipairs({ "TRACKED", "FINDS", "QUEST", "CATEGORIES" }) do
        self.sections[kind] = { heading = Label(self.content, "SECTION", "gold"),
            rule = Rule(self.content, "borderMuted"),
            empty = Label(self.content, "BODY", "textSecondary") }
    end
    for _, kind in ipairs(CATEGORIES) do
        local row = { name = Label(self.content, "BODY", "textPrimary"),
            count = Label(self.content, "BODY", "gold") }
        self.summaryRows[kind] = row
    end
    self:CreateDetail()
    self.frame:Hide()
end

function View:CreateDetail()
    local d = CreateFrame("Frame", nil, self.frame)
    self.detail = d
    d.paper = Rule(d, "backgroundRaised"); d.paper:SetAllPoints(d)
    d.heading = Label(d, "SECTION", "gold")
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.name = Label(d, "ITEM_TITLE", "textPrimary")
    d.category = Label(d, "SMALL", "textSecondary")
    d.owned = Label(d, "BODY", "textPrimary")
    d.bags = Label(d, "BODY", "textSecondary")
    d.finds = Label(d, "BODY", "textSecondary")
    d.target = Label(d, "BODY", "textPrimary")
    d.targetLabel = Label(d, "BODY", "textSecondary")
    d.notice = Label(d, "SMALL", "warning")
    d.action = Button(d, "", function()
        if not View.selectedID then return end
        local data = MS.JourneyInventoryData
        if data.tracked[View.selectedID] then data:Untrack(View.selectedID)
        else
            local ok, reason = data:Track(View.selectedID)
            if not ok and reason == "LIMIT" then
                View.notice = MS.L.JOURNEY_INVENTORY_LIMIT
            end
        end
        View.dirty = true; View:Refresh()
    end)
    d.edit = CreateFrame("EditBox", nil, d)
    d.edit:SetFontObject(GameFontHighlightSmall); d.edit:SetAutoFocus(false)
    MS.JourneyUIStyle:Apply(d.edit, "BODY")
    d.edit.back = Rule(d.edit, "backgroundDeep"); d.edit.back:SetAllPoints(d.edit)
    d.edit:SetNumeric(true); d.edit:SetMaxLetters(9)
    d.edit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    d.edit:SetScript("OnEnterPressed", function(box) View:SaveTarget(); box:ClearFocus() end)
    d.save = Button(d, MS.L.JOURNEY_INVENTORY_SAVE,
        function() View:SaveTarget() end)
    d.clear = Button(d, MS.L.JOURNEY_INVENTORY_CLEAR_TARGET, function()
        if View.selectedID then MS.JourneyInventoryData:SetTarget(View.selectedID, nil) end
        View.dirty = true; View:Refresh()
    end)
end
function View:SaveTarget()
    if not self.selectedID then return end
    local target = tonumber(self.detail.edit:GetText() or "")
    local ok = MS.JourneyInventoryData:SetTarget(self.selectedID, target)
    self.notice = ok and nil or MS.L.JOURNEY_INVENTORY_INVALID_TARGET
    self.dirty = true; self:Refresh()
end
function View:SelectCategory(kind)
    for _, candidate in ipairs(KINDS) do
        if candidate == kind then
            self.selectedCategory, self.selectedID, self.notice = kind, nil, nil
            self.dirty = true
            if self.scroll then self.scroll:SetVerticalScroll(0) end
            self:Refresh()
            return true
        end
    end
end
function View:Layout(rect)
    if not self.frame then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    self.frame:SetSize(rect.width, rect.height)
    local scale = MS.JourneySettings:Get("textScale")
    if self.width ~= rect.width or self.height ~= rect.height or self.scale ~= scale then
        self.width, self.height, self.scale, self.dirty =
            rect.width, rect.height, scale, true
    end
    self:Refresh()
end
function View:Invalidate()
    self.dirty = true
    if self.active and not self.visible then
        self.deferredRefreshCount = (self.deferredRefreshCount or 0) + 1
    end
end
function View:ScheduleRefresh()
    if not self.active then return end
    self:Invalidate()
    if not self.visible or self.refreshTicket then return end
    local ticket = {}
    self.refreshTicket = ticket
    local function Flush()
        if self.refreshTicket ~= ticket then return end
        self.refreshTicket = nil
        if self.active and self.visible then self:Refresh() end
    end
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, Flush)
    else Flush() end
end
function View:Groups()
    local data = MS.JourneyInventoryData
    local groups = {}
    for _, kind in ipairs(KINDS) do groups[kind] = {} end
    groups.TRACKED = Sorted(data.tracked, data)
    local finds = {}
    for id, count in pairs(data.finds) do
        if count > 0 then finds[id] = true end
    end
    groups.FINDS = Sorted(finds, data)
    for id, item in pairs(data.items) do
        if (data.bags[id] or 0) > 0 then
            local kind = item.category or "OTHER"
            groups[kind][#groups[kind] + 1] = id
        end
    end
    for _, kind in ipairs({ "QUEST", "CONSUMABLE", "EQUIPMENT",
        "CRAFTING", "RECIPE", "OTHER" }) do
        table.sort(groups[kind], function(a, b)
            local an = data.items[a] and data.items[a].name or ""
            local bn = data.items[b] and data.items[b].name or ""
            if an == bn then return a < b end
            return an < bn
        end)
    end
    return groups
end
function View:PlaceIndex(groups, width, startY, margin, large)
    self.indexHeading:SetShown(large)
    if large then Place(self.indexHeading, self.frame, margin, startY, 210,
        MS.L.JOURNEY_INVENTORY_INDEX) end
    local indexWidth = large and 225 or (width - margin * 2 - 4 * 8) / 5
    local rowHeight = math.max(36, 32 * self.scale)
    for index, kind in ipairs(KINDS) do
        local button = self.indexButtons[kind]
        local x, y
        if large then
            x, y = margin, startY + 31 + (index - 1) * (rowHeight + 3)
        else
            local column = index <= 4 and index - 1 or index - 5
            x = margin + column * (indexWidth + 8)
            y = startY + (index <= 4 and 0 or rowHeight + 7)
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
        button:SetSize(indexWidth, rowHeight)
        MS.JourneyUIStyle:Color(button.back,
            kind == self.selectedCategory and "parchmentDark" or "backgroundDeep")
        button.rule:ClearAllPoints()
        button.rule:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        button.rule:SetSize(indexWidth, 1)
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", button, "LEFT", 9, 0)
        button.label:SetWidth(indexWidth - 42)
        button.label:SetText(MS.L["JOURNEY_INVENTORY_" .. kind])
        button.count:ClearAllPoints()
        button.count:SetPoint("RIGHT", button, "RIGHT", -8, 0)
        button.count:SetWidth(30); button.count:SetJustifyH("RIGHT")
        button.count:SetText(kind == "OVERVIEW" and "" or tostring(#groups[kind]))
        MS.JourneyUIStyle:Text(button.label, (kind == "OVERVIEW" or #groups[kind] > 0) and "textPrimary" or "textSecondary")
        MS.JourneyUIStyle:Text(button.count, #groups[kind] > 0 and "gold" or "textSecondary")
    end
    return large and 225 or indexWidth
end
function View:Row(index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, self.content)
    -- Selection sits under the icon (BACKGROUND fill, BORDER accent); the icon stays ARTWORK.
    row.selected = row:CreateTexture(nil, "BACKGROUND"); row.selected:SetAllPoints(row)
    MS.JourneyUIStyle:Color(row.selected, "parchmentDark")
    row.selectedAccent = row:CreateTexture(nil, "BORDER")
    row.selectedAccent:SetPoint("TOPLEFT", row, "TOPLEFT"); row.selectedAccent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
    row.selectedAccent:SetWidth(3); MS.JourneyUIStyle:Color(row.selectedAccent, "borderActive")
    row.rule = Rule(row, "borderMuted")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.name = Label(row, "BODY", "textPrimary")
    row.count = Label(row, "BODY", "gold")
    row.note = Label(row, "SMALL", "textSecondary")
    row:SetScript("OnClick", function(frame)
        View.selectedID, View.notice = frame.itemID, nil
        View.dirty = true; View:Refresh()
    end)
    row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1); row.hover:SetAllPoints(row)
    MS.JourneyUIStyle:ReactiveRow(row, function(frame) View:ShowItemTooltip(frame) end,
        function(frame) View:HideItemTooltip(frame) end)
    self.rows[index] = row
    return row
end
function View:PlaceRow(index, id, kind, y, width)
    local data = MS.JourneyInventoryData
    local item, row = data:EnsureItem(id), self:Row(index)
    local count
    if kind == "TRACKED" then
        local target = data.tracked[id] and data.tracked[id].targetCount
        count = target and string.format(MS.L.JOURNEY_INVENTORY_TARGET_COUNT,
            data.owned[id] or 0, target)
            or string.format(MS.L.JOURNEY_INVENTORY_OWNED_COUNT, data.owned[id] or 0)
    elseif kind == "FINDS" then count = "+" .. tostring(data.finds[id] or 0)
    else count = tostring(data.bags[id] or 0) end
    local countWidth = math.max(82, math.floor(width * .28))
    local nameWidth = width - countWidth - 50
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
    row:SetWidth(width)
    row.icon:ClearAllPoints(); row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -4)
    row.icon:SetSize(29, 29)
    row.icon:SetTexture(item and item.icon or "Interface\\Buttons\\WHITE8X8")
    row.icon:SetVertexColor(item and item.icon and 1 or .4,
        item and item.icon and 1 or .36, item and item.icon and 1 or .28)
    row.name:ClearAllPoints(); row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 40, -2)
    row.name:SetWidth(nameWidth); row.name:SetText(Name(item, id))
    row.count:ClearAllPoints(); row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -2)
    row.count:SetWidth(countWidth); row.count:SetJustifyH("RIGHT")
    row.count:SetText(count)
    row.note:ClearAllPoints(); row.note:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.note:SetWidth(nameWidth)
    local hint = kind == "TRACKED" and MS.L.JOURNEY_INVENTORY_TRACKED_HINT
        or kind == "QUEST" and MS.L.JOURNEY_INVENTORY_QUEST_HINT
        or kind == "FINDS" and MS.L.JOURNEY_INVENTORY_FINDS_HINT or nil
    row.note:SetText(hint or ""); row.note:SetShown(hint ~= nil)
    local height = math.max(42 * self.scale,
        (row.name:GetStringHeight() or 16) + (hint and 25 or 10))
    row:SetHeight(height)
    row.rule:ClearAllPoints(); row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 40, 0)
    row.rule:SetSize(math.max(1, width - 40), 1)
    row.selected:SetShown(self.selectedID == id); row.selectedAccent:SetShown(self.selectedID == id)
    row.itemID, row.bag, row.slot = id, item and item.bag, item and item.slot
    row:Show()
    return y + height + 4
end
function View:PlaceSection(kind, ids, y, width, limit)
    local section = self.sections[kind]
    y = y + Place(section.heading, self.content, 0, y, width,
        MS.L["JOURNEY_INVENTORY_" .. kind]) + 7
    section.rule:ClearAllPoints()
    section.rule:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
    section.rule:SetSize(width, 1); section.rule:Show(); y = y + 11
    if #ids == 0 then
        local empty = kind == "TRACKED" and MS.L.JOURNEY_INVENTORY_EMPTY_TRACKED
            or kind == "FINDS" and MS.L.JOURNEY_INVENTORY_EMPTY_FINDS
            or MS.L.JOURNEY_INVENTORY_EMPTY_SECTION
        y = y + Place(section.empty, self.content, 40, y,
            width - 40, empty) + 13
    else
        section.empty:Hide()
        for index = 1, math.min(#ids, limit or #ids) do
            self.renderedRowCount = self.renderedRowCount + 1
            y = self:PlaceRow(self.renderedRowCount, ids[index], kind, y, width)
        end
        y = y + 15
    end
    return y
end
function View:BagSummary()
    local data = MS.JourneyInventoryData
    return string.format(MS.L[data.freeSlots == 1 and "JOURNEY_INVENTORY_SUMMARY_ONE" or "JOURNEY_INVENTORY_SUMMARY"],
        data.freeSlots or 0, data.totalSlots or 0)
end

function View:OverviewSummary()
    local data, found = MS.JourneyInventoryData, 0
    for _, count in pairs(data.finds) do if count > 0 then found = found + 1 end end
    local tracked = #Sorted(data.tracked, data)
    -- Bag capacity already sits under the page title; the summary keeps only new facts.
    return string.format(
        MS.L[tracked == 1 and "JOURNEY_UI_TRACKED_ONE" or "JOURNEY_UI_TRACKED"], tracked) ..
        " · " .. string.format(MS.L[found == 1 and "JOURNEY_UI_FINDS_ONE" or "JOURNEY_UI_FINDS"], found)
end

function View:PlaceDetail(width)
    local d, data, id = self.detail, MS.JourneyInventoryData, self.selectedID
    local item = id and data:EnsureItem(id) or nil
    local inner, y = width - 32, 17
    d:SetWidth(width)
    y = y + Place(d.heading, d, 16, y, inner,
        MS.L[id and "JOURNEY_INVENTORY_DETAIL" or "JOURNEY_INVENTORY_BAG_SUMMARY"]) + 17
    for _, key in ipairs({ "icon", "category", "owned", "bags", "finds",
        "target", "targetLabel", "action", "edit", "save", "clear" }) do d[key]:Hide() end
    if not id then
        y = y + Place(d.name, d, 16, y, inner,
            self:OverviewSummary()) + 16
    else
        d.icon:ClearAllPoints(); d.icon:SetPoint("TOPLEFT", d, "TOPLEFT", 16, -y)
        d.icon:SetSize(34, 34)
        d.icon:SetTexture(item and item.icon or "Interface\\Buttons\\WHITE8X8")
        d.icon:Show()
        local nameHeight = Place(d.name, d, 60, y, inner - 44, Name(item, id))
        y = y + math.max(37, nameHeight + 4)
        y = y + Place(d.category, d, 16, y, inner,
            MS.L["JOURNEY_INVENTORY_" .. (item and item.category or "OTHER")]) + 20
        y = y + Place(d.owned, d, 16, y, inner,
            string.format(MS.L.JOURNEY_INVENTORY_DETAIL_OWNED, data.owned[id] or 0)) + 7
        y = y + Place(d.bags, d, 16, y, inner,
            string.format(MS.L.JOURNEY_INVENTORY_DETAIL_BAGS, data.bags[id] or 0)) + 7
        if (data.finds[id] or 0) > 0 then
            y = y + Place(d.finds, d, 16, y, inner,
                string.format(MS.L.JOURNEY_INVENTORY_DETAIL_FINDS, data.finds[id])) + 7
        end
        local tracked = data.tracked and data.tracked[id]
        if tracked and tracked.targetCount then
            y = y + Place(d.target, d, 16, y, inner,
                string.format(MS.L.JOURNEY_INVENTORY_DETAIL_TARGET,
                    data.owned[id] or 0, tracked.targetCount)) + 10
        end
        d.action:ClearAllPoints(); d.action:SetPoint("TOPLEFT", d, "TOPLEFT", 16, -y)
        d.action:SetSize(inner, 30); d.action.label:SetWidth(inner - 10)
        d.action.label:SetText(tracked and MS.L.JOURNEY_INVENTORY_UNTRACK
            or MS.L.JOURNEY_INVENTORY_TRACK)
        d.action:Show(); y = y + 43
        if tracked then
            y = y + Place(d.targetLabel, d, 16, y, inner,
                MS.L.JOURNEY_INVENTORY_TARGET_LABEL) + 6
            d.edit:ClearAllPoints(); d.edit:SetPoint("TOPLEFT", d, "TOPLEFT", 16, -y)
            d.edit:SetSize(math.max(55, inner - 86), 28); d.edit:Show()
            if self.editingID ~= id or self.editingTarget ~= tracked.targetCount then
                d.edit:SetText(tracked.targetCount and tostring(tracked.targetCount) or "")
                self.editingID, self.editingTarget = id, tracked.targetCount
            end
            d.save:ClearAllPoints(); d.save:SetPoint("TOPRIGHT", d, "TOPRIGHT", -16, -y)
            d.save:SetSize(62, 28); d.save:Show(); y = y + 36
            if tracked.targetCount then
                d.clear:ClearAllPoints()
                d.clear:SetPoint("TOPLEFT", d, "TOPLEFT", 16, -y)
                d.clear:SetSize(inner, 26); d.clear:Show(); y = y + 34
            end
        end
    end
    d.notice:Hide()
    if self.notice then y = y + Place(d.notice, d, 16, y, inner, self.notice) + 8 end
    d:SetHeight(y + 13)
    return y + 13
end
-- Use the existing dedicated native GameTooltip so Surface Manager ownership stays intact.
function View:HideItemTooltip(cell)
    local tooltip = cell and cell.itemTooltip
    if type(tooltip) == "table" or type(tooltip) == "userdata" then tooltip:Hide() end
    if cell then cell.itemTooltip = nil end
end

function View:ShowItemTooltip(cell)
    self:HideItemTooltip(cell)
    local data = MS.JourneyInventoryData
    local item = data and data.items[cell.itemID]
    local bag, slot = item and item.bag, item and item.slot
    local validBag = type(bag) == "number" and type(slot) == "number"
    -- Validate cached slot identity at hover time; a bag may have changed since capture.
    local infoAPI = _G.C_Container and C_Container.GetContainerItemInfo
    if validBag and type(infoAPI) == "function" then
        local ok, info = pcall(infoAPI, bag, slot)
        validBag = ok and type(info) == "table" and info.itemID == cell.itemID
    else validBag = false end
    local link = item and item.link
    if not (type(link) == "string" and tonumber(link:match("item:(%d+)")) == cell.itemID) then
        local api = _G.C_Item and C_Item.GetItemInfo or _G.GetItemInfo
        if type(api) == "function" then
            local ok, _, value = pcall(api, cell.itemID)
            if ok then link = value end
        end
    end
    if not validBag and not (type(link) == "string" and tonumber(link:match("item:(%d+)")) == cell.itemID) then return end
    local bridge = MS.TooltipBridge
    if not bridge or type(bridge.PrepareWorkspaceTooltip) ~= "function" then return end
    local tooltip = bridge:PrepareWorkspaceTooltip(cell)
    if not tooltip then return end
    -- Native cursor anchor instead of the workspace corner; no manual positioning.
    if type(tooltip.SetOwner) == "function" then
        if type(tooltip.ClearAllPoints) == "function" then tooltip:ClearAllPoints() end
        tooltip:SetOwner(cell, "ANCHOR_CURSOR")
    end
    local ok
    if validBag and type(tooltip.SetBagItem) == "function" then
        local accepted
        ok, accepted = pcall(tooltip.SetBagItem, tooltip, bag, slot)
        ok = ok and accepted ~= false
    end
    if not ok and type(link) == "string" and tonumber(link:match("item:(%d+)")) == cell.itemID
        and type(tooltip.SetHyperlink) == "function" then
        local accepted
        ok, accepted = pcall(tooltip.SetHyperlink, tooltip, link)
        ok = ok and accepted ~= false
    end
    if ok then cell.itemTooltip = tooltip; tooltip:Show() else tooltip:Hide() end
end

-- Combined carried-item totals from the existing snapshot; no bag operations.
function View:PlaceGrid(y, width)
    local data = MS.JourneyInventoryData
    local carried = {}
    for id, count in pairs(data.bags) do if count > 0 then carried[id] = true end end
    local ids = Sorted(carried, data)
    y = y + Place(self.sections.CATEGORIES.heading, self.content, 0, y, width,
        MS.L.JOURNEY_UI_BAG_CONTENTS) + 12
    local size, gap = 48, MS.JourneyUIStyle.space.sm
    local columns = math.max(1, math.floor((width + gap) / (size + gap)))
    self.gridColumns, self.gridCount = columns, #ids
    if #ids == 0 then
        return y + Place(self.sections.CATEGORIES.empty, self.content, 0, y, width,
            MS.L.JOURNEY_INVENTORY_EMPTY_SECTION) + 16
    end
    for index, id in ipairs(ids) do
        local cell = self.gridCells[index]
        if not cell then
            cell = CreateFrame("Frame", nil, self.content)
            -- BACKGROUND neutral fill, BORDER quality edges, ARTWORK icon, OVERLAY count/hover.
            cell.background = cell:CreateTexture(nil, "BACKGROUND"); cell.background:SetAllPoints(cell)
            MS.JourneyUIStyle:Color(cell.background, "backgroundDeep")
            cell.edges = {}
            for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
                local edge = cell:CreateTexture(nil, "BORDER")
                if side == "TOP" or side == "BOTTOM" then
                    edge:SetPoint(side .. "LEFT", cell, side .. "LEFT"); edge:SetPoint(side .. "RIGHT", cell, side .. "RIGHT")
                    edge:SetHeight(2)
                else
                    edge:SetPoint("TOP" .. side, cell, "TOP" .. side); edge:SetPoint("BOTTOM" .. side, cell, "BOTTOM" .. side)
                    edge:SetWidth(2)
                end
                cell.edges[#cell.edges + 1] = edge
            end
            cell.icon = cell:CreateTexture(nil, "ARTWORK")
            cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, -2)
            cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -2, 2)
            cell.fallback = Label(cell, "SMALL", "textSecondary")
            cell.fallback:SetAllPoints(cell); cell.fallback:SetJustifyH("CENTER")
            cell.quantity = Label(cell, "SMALL", "textPrimary")
            cell.quantity:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -4, 4)
            cell.quantity:SetJustifyH("RIGHT"); cell.quantity:SetWidth(size - 8)
            cell.hover = cell:CreateTexture(nil, "OVERLAY"); cell.hover:SetAllPoints(cell.icon)
            cell.hover:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); cell.hover:SetBlendMode("ADD")
            cell.hover:Hide()
            cell.selected = cell:CreateTexture(nil, "OVERLAY", nil, 1)
            cell.selected:SetPoint("TOPLEFT", cell, "TOPLEFT", -2, 2)
            cell.selected:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 2, -2)
            MS.JourneyUIStyle:Color(cell.selected, "borderActive"); cell.selected:SetAlpha(.35)
            cell:EnableMouse(true)
            -- A click only opens the item's sheet (follow, target). Never a use action: the cell
            -- stays a plain Frame without OnClick.
            cell:SetScript("OnMouseUp", function(frame, button)
                if button ~= "LeftButton" then return end
                View.selectedID, View.notice = frame.itemID, nil
                View.dirty = true; View:Refresh()
            end)
            cell:SetScript("OnEnter", function(frame) frame.hover:Show(); View:ShowItemTooltip(frame) end)
            cell:SetScript("OnLeave", function(frame) frame.hover:Hide(); View:HideItemTooltip(frame) end)
            cell:SetScript("OnHide", function(frame) frame.hover:Hide(); View:HideItemTooltip(frame) end)
            self.gridCells[index] = cell
        end
        local item = data.items[id]
        cell.itemID, cell.readOnly = id, true
        cell:ClearAllPoints(); cell:SetPoint("TOPLEFT", self.content, "TOPLEFT",
            ((index - 1) % columns) * (size + gap), -(y + math.floor((index - 1) / columns) * (size + gap)))
        cell:SetSize(size, size)
        cell.icon:SetTexture(item and item.icon or "Interface\\Buttons\\WHITE8X8")
        cell.icon:SetVertexColor(item and item.icon and 1 or .25, item and item.icon and 1 or .22, item and item.icon and 1 or .17)
        cell.fallback:SetText(tostring(id)); cell.fallback:SetShown(not (item and item.icon))
        -- Quality only colours the edges; common/unknown quality keeps a neutral edge.
        local quality = item and type(item.quality) == "number" and item.quality ~= 1
            and type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[item.quality]
        cell.qualityColored = type(quality) == "table" and quality.r ~= nil and quality.g ~= nil and quality.b ~= nil
        for _, edge in ipairs(cell.edges) do
            if cell.qualityColored then edge:SetColorTexture(quality.r, quality.g, quality.b, 1)
            else MS.JourneyUIStyle:Color(edge, "borderMuted") end
        end
        local count = data.bags[id] or 0
        cell.quantity:SetText(count > 1 and tostring(count) or "")
        cell.selected:SetShown(self.selectedID == id)
        cell:Show()
    end
    return y + math.ceil(#ids / columns) * (size + gap) + 16
end

function View:RenderContent(groups, width)
    local kind, y = self.selectedCategory, 8
    self.renderedRowCount = 0
    self.empty:Hide()
    for _, cell in ipairs(self.gridCells) do cell:Hide() end
    for _, section in pairs(self.sections) do
        section.heading:Hide(); section.rule:Hide(); section.empty:Hide()
    end
    for _, row in pairs(self.summaryRows) do row.name:Hide(); row.count:Hide() end
    if kind == "OVERVIEW" then
        for _, sectionKind in ipairs({ "TRACKED", "FINDS", "QUEST" }) do
            y = self:PlaceSection(sectionKind, groups[sectionKind], y, width, 5)
        end
        y = self:PlaceGrid(y, width)
    elseif #groups[kind] == 0 then
        local empty = kind == "TRACKED" and MS.L.JOURNEY_INVENTORY_EMPTY_TRACKED
            or kind == "FINDS" and MS.L.JOURNEY_INVENTORY_EMPTY_FINDS
            or MS.L.JOURNEY_INVENTORY_EMPTY_SECTION
        y = y + Place(self.empty, self.content, 10, y, width - 20, empty) + 20
    else
        for _, id in ipairs(groups[kind]) do
            self.renderedRowCount = self.renderedRowCount + 1
            y = self:PlaceRow(self.renderedRowCount, id, kind, y, width)
        end
    end
    for index = self.renderedRowCount + 1, #self.rows do self.rows[index]:Hide() end
    self.content:SetHeight(math.max(self.scroll:GetHeight(), y + 15))
    local maximum = math.max(0, self.content:GetHeight() - self.scroll:GetHeight())
    self.scroll:SetVerticalScroll(math.min(maximum, self.scroll:GetVerticalScroll()))
end
function View:Refresh()
    if not self.frame or not self.active or not self.visible or not self.dirty then return end
    local data = MS.JourneyInventoryData
    self.supported = data.supported
    local width, height, margin = self.frame:GetWidth(), self.frame:GetHeight(), 22
    local large = width >= 1400
    self.layoutMode = large and "THREE_COLUMN" or "COMPACT"
    local groups = self:Groups()
    local y = 17
    y = y + Place(self.title, self.frame, margin, y, width - margin * 2,
        MS.L.JOURNEY_VIEW_INVENTORY) + 2
    y = y + Place(self.subtitle, self.frame, margin, y, width - margin * 2,
        MS.L.JOURNEY_INVENTORY_SUBTITLE) + 7
    y = y + Place(self.summary, self.frame, margin, y, width - margin * 2,
        self:BagSummary()) + 10
    self.headerRule:ClearAllPoints()
    self.headerRule:SetPoint("TOPLEFT", self.frame, "TOPLEFT", margin, -y)
    self.headerRule:SetSize(width - margin * 2, 1); y = y + 13
    self.unavailable:SetShown(not self.supported)
    if not self.supported then
        y = y + Place(self.unavailable, self.frame, margin, y,
            width - margin * 2, MS.L.JOURNEY_INVENTORY_UNAVAILABLE) + 10
    end
    local listX, listWidth, listTop, listBottom
    if large then
        local indexWidth = self:PlaceIndex(groups, width, y, margin, true)
        local detailWidth = math.min(410, math.max(335, width * .23))
        listX = margin + indexWidth + 20
        listWidth = width - margin * 2 - indexWidth - detailWidth - 40
        listTop, listBottom = y + 3, height - 15
        local detailX = listX + listWidth + 20
        self.detail:ClearAllPoints()
        self.detail:SetPoint("TOPLEFT", self.frame, "TOPLEFT", detailX, -listTop)
        self:PlaceDetail(detailWidth); self.detail:Show()
    else
        self:PlaceIndex(groups, width, y, margin, false)
        listX, listWidth = margin, width - margin * 2
        listTop = y + math.max(36, 32 * self.scale) * 2 + 22
        if self.selectedID then
            local detailWidth = math.min(700, listWidth)
            local detailHeight = self:PlaceDetail(detailWidth)
            self.detail:ClearAllPoints()
            self.detail:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT",
                margin, 12)
            self.detail:Show()
            listBottom = height - detailHeight - 24
        else
            self.detail:Hide()
            listBottom = height - 12
        end
    end
    self.listHeading:ClearAllPoints()
    self.listHeading:SetPoint("TOPLEFT", self.frame, "TOPLEFT", listX, -listTop)
    self.listHeading:SetWidth(listWidth)
    self.listHeading:SetText(MS.L["JOURNEY_INVENTORY_" .. self.selectedCategory])
    local headingHeight = math.max(17, self.listHeading:GetStringHeight() or 0)
    self.listRule:ClearAllPoints()
    self.listRule:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
        listX, -(listTop + headingHeight + 7))
    self.listRule:SetSize(listWidth, 1)
    local scrollTop = listTop + headingHeight + 15
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", self.frame, "TOPLEFT", listX, -scrollTop)
    self.scroll:SetSize(math.max(1, listWidth), math.max(1, listBottom - scrollTop))
    self.content:SetWidth(math.max(1, listWidth - 10))
    self:RenderContent(groups, self.content:GetWidth())
    self.edge:ClearAllPoints()
    self.edge:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 9, -9)
    self.edge:SetSize(2, math.max(1, height - 18))
    self.dirty, self.refreshCount = false, self.refreshCount + 1
end
function View:Start()
    if self.active then return end
    self.active, self.dirty = true, true
    self.selectedCategory, self.selectedID = "OVERVIEW", nil
    self.refreshCount, self.deferredRefreshCount = 0, 0
    MS.JourneyInventoryData:Start()
    self.deferredRefreshCount = 0
    self.supported = MS.JourneyInventoryData.supported
    self:Refresh()
end
function View:Stop()
    self.active, self.visible, self.refreshTicket = false, false, nil
end
function View:GetStatus()
    local status = MS.JourneyInventoryData:GetStatus()
    status.visible, status.dirty, status.refreshCount =
        self.visible, self.dirty, self.refreshCount
    status.category, status.renderedRowCount, status.layoutMode =
        self.selectedCategory, self.renderedRowCount or 0, self.layoutMode
    return status
end
