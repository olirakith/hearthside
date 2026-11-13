local MS = _G.MS

MS.QuestJournal = { active = false, questCount = 0, completedCount = 0 }
local Journal = MS.QuestJournal

function Journal:Create(parent)
    if self.frame then return end
    self.frame = CreateFrame("Frame", nil, parent)
    self.background = self.frame:CreateTexture(nil, "BACKGROUND")
    self.background:SetAllPoints(self.frame); MS.JourneyUIStyle:PageMaterial(self.background, "DARK")
    self.listPanel = CreateFrame("Frame", nil, self.frame)
    self.listBackground = self.listPanel:CreateTexture(nil, "BACKGROUND")
    self.listBackground:SetAllPoints(self.listPanel); MS.JourneyUIStyle:PageMaterial(self.listBackground, "DARK")
    self.detailPanel = CreateFrame("Frame", nil, self.frame)
    self.detailBackground = self.detailPanel:CreateTexture(nil, "BACKGROUND")
    self.detailBackground:SetAllPoints(self.detailPanel); MS.JourneyUIStyle:Color(self.detailBackground, "backgroundDeep")
    self.spine = self.frame:CreateTexture(nil, "ARTWORK")
    MS.JourneyUIStyle:Color(self.spine, "borderMuted")
    self.spine:SetWidth(1)
    self.scroll = CreateFrame("ScrollFrame", nil, self.frame)
    self.scroll:SetPoint("TOPLEFT", self.listPanel, "TOPLEFT", 8, -8)
    self.scroll:SetPoint("BOTTOMRIGHT", self.listPanel, "BOTTOMRIGHT", -8, 8)
    self.content = CreateFrame("Frame", nil, self.scroll)
    self.content:SetSize(1, 1)
    self.scroll:SetScrollChild(self.content)
    self.scroll:EnableMouseWheel(true)
    self.scroll:SetScript("OnMouseWheel", function(scroll, delta)
        local maximum = math.max(0, self.content:GetHeight() - scroll:GetHeight())
        scroll:SetVerticalScroll(math.max(0,
            math.min(maximum, scroll:GetVerticalScroll() - delta * 40)))
    end)
    self.rows = {}
    self.hitRows = {}
    self.groupRules = {}
end

function Journal:Layout(rect)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    self.frame:SetSize(rect.width, rect.height)
    local listWidth = math.max(205, math.min(rect.width * .31, 440))
    self.listPanel:ClearAllPoints(); self.listPanel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
    self.listPanel:SetSize(listWidth, rect.height)
    local available = math.max(1, rect.width - listWidth - 10)
    local pageWidth = math.min(available, 728)
    self.detailPanel:ClearAllPoints()
    self.detailPanel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", listWidth + 10 + (available - pageWidth) / 2, 0)
    self.detailPanel:SetSize(pageWidth, rect.height)
    self.spine:ClearAllPoints()
    self.spine:SetPoint("TOPLEFT", self.listPanel, "TOPRIGHT", 3, 0)
    self.spine:SetPoint("BOTTOMLEFT", self.listPanel, "BOTTOMRIGHT", 3, 0)
    self.content:SetWidth(math.max(1, listWidth - 16))
    if MS.JourneyContextPanel and MS.JourneyWorkspace.view == "QUESTS" then
        MS.JourneyContextPanel:Mount(self.detailPanel)
        MS.JourneyContextPanel:Layout(self.detailPanel:GetWidth(), rect.height, "PAGE")
    end
    self.dirty = true
    self:Refresh()
end

local function Entries(snapshot)
    snapshot = snapshot or MS.JourneyQuestData:ReadSnapshot({ errors = {}, shapes = {} })
    return snapshot.count, function(index)
        local info = snapshot.entries[index]
        if type(info) ~= "table" then return nil end
        local model = snapshot.byID and snapshot.byID[info.questID]
        local complete = model and model.isComplete
        if complete == nil then complete = info.isComplete == true or info.isComplete == 1 end
        return { title = info.title, level = info.level,
            header = info.isHeader == true or info.isHeader == 1,
            complete = complete, questID = info.questID, index = index,
            modern = snapshot.modern }
    end
end

function Journal:Invalidate()
    self.dirty = true
    if self.active and not self.visible then
        self.deferredRefreshCount = (self.deferredRefreshCount or 0) + 1
    end
end

function Journal:Refresh()
    if not self.content then return end
    if not self.active or not self.visible then self.dirty = true; return end
    if not self.dirty then return end
    self.dirty = false
    self.refreshCount = (self.refreshCount or 0) + 1
    local playerMapID = MS.JourneyMapData:PlayerZone()
    local quests = playerMapID and MS.JourneyQuestData:Collect(playerMapID)
    local snapshot = quests and quests.snapshot
    if not snapshot then
        local _, _, current = MS.JourneyQuestData:ReadLog({ errors = {}, shapes = {} })
        snapshot = current
    end
    local count, getEntry = Entries(snapshot)
    local rows, questCount, completeCount, entries = {}, 0, 0, {}
    local hereIDs = {}
    -- Collect owns the same relation/evidence policy used by the map sidebar.
    for _, quest in ipairs(quests and quests.here or {}) do
        hereIDs[quest.questID] = true
    end
    for index = 1, count do
        local entry = getEntry(index)
        if entry and not entry.header then
                questCount = questCount + 1
                if entry.complete then completeCount = completeCount + 1 end
                entries[#entries + 1] = entry
        end
    end
    local here, other = {}, {}
    for _, entry in ipairs(entries) do
        local group = hereIDs[entry.questID] and here or other
        group[#group + 1] = entry
    end
    local models = snapshot.byID or {}
    local function stateOf(entry)
        local model = models[entry.questID]
        return model and model.state or entry.complete and "READY_TO_TURN_IN" or "UNKNOWN"
    end
    here = MS.JourneyQuestData:ReadyFirst(here, stateOf)
    -- Build explicit zone groups before rendering: a header never depends on the raw
    -- log order, and a quest without a known zone never inherits a neighbour's header.
    local latest = MS.JourneyQuestData.latestByID or {}
    local zoneGroups, byZone, unknown = {}, {}, {}
    for _, entry in ipairs(other) do
        local model = latest[entry.questID]
        -- Same authority as CARTE: only a zone that passes TrustedZone groups a quest.
        local zoneID = model and MS.JourneyQuestData:TrustedZone(model)
        local zone = zoneID and MS.JourneyMapData:Info(zoneID)
        local header = not (zone and zone.name) and model and model.headerVerified
            and type(model.headerName) == "string" and model.headerName ~= "" and model.headerName or nil
        if (zone and zone.name) or header then
            local key = zone and zone.name and zoneID or ("HEADER:" .. header)
            local group = byZone[key]
            if not group then
                group = { text = zone and zone.name or header, entries = {} }
                byZone[key] = group
                zoneGroups[#zoneGroups + 1] = group
            end
            group.entries[#group.entries + 1] = entry
        else
            unknown[#unknown + 1] = entry
        end
    end
    -- Zones keep first-appearance log order; entries keep log order inside each zone.
    if #unknown > 0 then zoneGroups[#zoneGroups + 1] = { text = MS.L.JOURNEY_MAP_UNKNOWN_ZONE, entries = unknown } end
    local ordered = {}
    for _, group in ipairs(zoneGroups) do
        for _, entry in ipairs(group.entries) do ordered[#ordered + 1] = entry end
    end
    -- Classification (hereEntries / otherEntries) is unchanged; presentation lists every quest
    -- ready to turn in first (ici before ailleurs), then active quests ici, then elsewhere.
    local ready = {}
    for _, list in ipairs({ here, ordered }) do
        for _, entry in ipairs(list) do
            if stateOf(entry) == "READY_TO_TURN_IN" then ready[#ready + 1] = entry end
        end
    end
    self.hereEntries, self.otherEntries, self.readyEntries, self.playerMapID = here, ordered, ready, playerMapID
    rows[#rows + 1] = { text = string.format(MS.L[questCount == 1 and "JOURNEY_UI_ACTIVE_QUEST_ONE" or "JOURNEY_UI_ACTIVE_QUESTS"], questCount), kind = "HEADER" }
    local function addQuest(entry)
        rows[#rows + 1] = { text = entry.title or MS.L.JOURNEY_QUEST_DETAILS,
            kind = entry.complete and "COMPLETE" or "QUEST", entry = entry, state = stateOf(entry) }
    end
    -- Quests shared with the party are moved into their own first group for display only.
    local Group = MS.JourneyGroupQuests
    local sharedList, isShared = {}, {}
    if Group and Group:IsActive() then
        for _, entry in ipairs(entries) do
            if Group:Shares(entry.questID) then sharedList[#sharedList + 1] = entry; isShared[entry] = true end
        end
    end
    if #sharedList > 0 then
        rows[#rows + 1] = { text = Group:Heading(), kind = "HEADER" }
        for _, entry in ipairs(sharedList) do addQuest(entry) end
    end
    local function active(list)
        local result = {}
        for _, entry in ipairs(list) do
            if stateOf(entry) ~= "READY_TO_TURN_IN" and not isShared[entry] then result[#result + 1] = entry end
        end
        return result
    end
    local shownReady = {}
    for _, entry in ipairs(ready) do
        if not isShared[entry] then shownReady[#shownReady + 1] = entry end
    end
    local hereActive, otherActive = active(here), active(ordered)
    local showGroupHeaders = #shownReady > 0 or #hereActive > 0 or #otherActive > 1
    if #shownReady > 0 then rows[#rows + 1] = { text = MS.L.JOURNEY_QUESTS_READY_HEADING, kind = "HEADER" } end
    for _, entry in ipairs(shownReady) do addQuest(entry) end
    if #hereActive > 0 and showGroupHeaders then rows[#rows + 1] = { text = MS.L.JOURNEY_MAP_QUESTS_HERE, kind = "HEADER" } end
    for _, entry in ipairs(hereActive) do addQuest(entry) end
    if #otherActive > 0 and showGroupHeaders then rows[#rows + 1] = { text = MS.L.JOURNEY_MAP_QUESTS_ELSEWHERE, kind = "HEADER" } end
    for _, group in ipairs(zoneGroups) do
        local groupEntries = active(group.entries)
        if #groupEntries > 0 then rows[#rows + 1] = { text = group.text, kind = "HEADER" } end
        for _, entry in ipairs(groupEntries) do addQuest(entry) end
    end
    self.questCount, self.completedCount = questCount, completeCount
    if #entries == 0 then rows[#rows + 1] = { text = MS.L.JOURNEY_NO_QUESTS, kind = "OBJECTIVE" } end
    local y = 4
    for index, row in ipairs(rows) do
        local font = self.rows[index]
        if not font then
            font = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            MS.JourneyUIStyle:Body(font, row.kind == "HEADER" and "HEADING" or "ITEM_TITLE", "textPrimary")
            font:SetJustifyH("LEFT")
            self.rows[index] = font
        end
        font:SetParent(self.content)
        MS.JourneyUIStyle:Apply(font, row.kind == "HEADER" and "HEADING" or "ITEM_TITLE")
        font:SetWidth(math.max(1, self.content:GetWidth() - (row.entry and 88 or 8)))
        font:SetText(row.text)
        font:ClearAllPoints()
        -- A group opens with air above it and a rule under it; rows then read as one list.
        local groupHeader = row.kind == "HEADER" and index > 1
        if groupHeader then y = y + MS.JourneyUIStyle.space.md end
        local rowTop = y
        font:SetPoint("TOPLEFT", self.content, "TOPLEFT", row.entry and 82 or 4, -y)
        local height = font:GetStringHeight()
        local metadataHeight = row.entry and 20 or 0
        local rowPadding = row.entry and 12 or 0
        y = y + math.max(22, (type(height) == "number" and height or 16) + metadataHeight + rowPadding + 6)
        MS.JourneyUIStyle:Text(font, groupHeader and "gold" or row.kind == "HEADER" and "textSecondary" or "textPrimary")
        font:Show()
        local rule = self.groupRules[index]
        if groupHeader and not rule then
            rule = self.content:CreateTexture(nil, "ARTWORK"); rule:SetHeight(1)
            MS.JourneyUIStyle:Color(rule, "borderMuted"); self.groupRules[index] = rule
        end
        if rule then
            rule:SetShown(groupHeader)
            rule:ClearAllPoints()
            rule:SetPoint("TOPLEFT", self.content, "TOPLEFT", 4, -(y - 3))
            rule:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -4, -(y - 3))
            if groupHeader then y = y + 4 end
        end
        local hit = self.hitRows[index]
        if row.entry then
            if not hit then
                hit = CreateFrame("Button", nil, self.content)
                hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                hit.hover = hit:CreateTexture(nil, "BACKGROUND")
                hit.hover:SetAllPoints(hit); MS.JourneyUIStyle:ReactiveRow(hit)
                hit.selected = hit:CreateTexture(nil, "BORDER")
                hit.selected:SetAllPoints(hit); MS.JourneyUIStyle:Color(hit.selected, "paperInset")
                hit.selected:SetAlpha(.9); hit.selected:Hide()
                hit.selectedRule = hit:CreateTexture(nil, "ARTWORK")
                hit.selectedRule:SetPoint("TOPLEFT", hit, "TOPLEFT")
                hit.selectedRule:SetPoint("BOTTOMLEFT", hit, "BOTTOMLEFT")
                hit.selectedRule:SetWidth(4)
                MS.JourneyUIStyle:Color(hit.selectedRule, "bronze")
                hit.selectedRule:Hide()
                hit.icon = hit:CreateTexture(nil, "ARTWORK")
                hit.icon:SetPoint("LEFT", hit, "LEFT", 10, 0)
                hit.icon:SetSize(20, 20)
                hit.levelLabel = hit:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                MS.JourneyUIStyle:Body(hit.levelLabel, "BODY", "textPrimary")
                hit.levelLabel:SetPoint("TOPLEFT", hit, "TOPLEFT", 30, -7)
                hit.levelLabel:SetWidth(48)
                hit.meta = hit:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                MS.JourneyUIStyle:Body(hit.meta, "SMALL", "textSecondary")
                hit.meta:SetJustifyH("LEFT")
                hit.separator = hit:CreateTexture(nil, "ARTWORK")
                hit.separator:SetPoint("BOTTOMLEFT", hit, "BOTTOMLEFT", 8, -3)
                hit.separator:SetPoint("BOTTOMRIGHT", hit, "BOTTOMRIGHT", -8, -3)
                hit.separator:SetHeight(1); MS.JourneyUIStyle:Color(hit.separator, "borderMuted")
                hit.separator:SetAlpha(.45)
                self.hitRows[index] = hit
            end
            hit:ClearAllPoints(); hit:SetPoint("TOPLEFT", self.content, "TOPLEFT", 2, -rowTop)
            hit:SetSize(self.content:GetWidth() - 4, math.max(24, (type(height) == "number" and height or 16) + metadataHeight + rowPadding))
            hit.meta:ClearAllPoints(); hit.meta:SetPoint("TOPLEFT", font, "BOTTOMLEFT", 0, -3)
            hit.meta:SetWidth(math.max(1, self.content:GetWidth() - 40))
            local model = MS.JourneyQuestData.latestByID and MS.JourneyQuestData.latestByID[row.entry.questID]
            local stateText = MS.L["JOURNEY_MAP_STATE_" .. row.state] or MS.L.JOURNEY_QUEST_DETAILS
            local place = model and MS.JourneyQuestData:DisplayPlaceName(model)
            hit.meta:SetText(stateText .. (place and " · " .. place or ""))
            font:SetParent(hit)
            font:ClearAllPoints(); font:SetPoint("TOPLEFT", hit, "TOPLEFT", 80, -7)
            MS.JourneyUIStyle:QuestRowState(hit.icon, hit.levelLabel, row.state, row.entry.level)
            hit.title = font
            hit.entry = row.entry
            hit.rowTop = rowTop
            if MS.JourneyPinAssets and MS.JourneyPinAssets.Apply then
                MS.JourneyUIStyle:QuestStateGlyph(hit.icon, row.state,
                    (MS.JourneyUIStyle.questStates[row.state] or MS.JourneyUIStyle.questStates.UNKNOWN).color)
            end
            local context = MS.JourneyContextPanel and MS.JourneyContextPanel.selectedContext
            local selected = context and context.type == "QUEST" and context.questID == row.entry.questID
            MS.JourneyUIStyle:DarkSelection(hit.selected, hit.selectedRule, font, hit.meta, selected == true)
            hit.rowHovered = hit.IsMouseOver and hit:IsMouseOver() == true
            MS.JourneyUIStyle:RowState(hit)
            hit:SetScript("OnClick", function(button, mouseButton)
                if mouseButton == "RightButton" then Journal:OpenQuestMenu(button.entry)
                else Journal:SelectQuest(button.entry) end
            end)
            hit:Show()
        elseif hit then hit.entry, hit.title = false, false; hit:Hide() end
    end
    for index = #rows + 1, #self.rows do self.rows[index]:Hide() end
    for index, rule in pairs(self.groupRules) do if index > #rows then rule:Hide() end end
    -- hitRows is sparse (header rows have no hit frame): never rely on # across its holes.
    for index, hit in pairs(self.hitRows) do
        if index > #rows then hit.entry, hit.title = false, false; hit:Hide() end
    end
    self.content:SetHeight(math.max(self.scroll:GetHeight(), y + 4))
    if #entries > 0 then
        local selectedEntry
        local context = MS.JourneyContextPanel and MS.JourneyContextPanel.selectedContext
        local selectedQuestID = context and context.type == "QUEST" and context.questID
        local firstShown
        for _, row in ipairs(rows) do
            if row.entry then firstShown = firstShown or row.entry end
            if row.entry and row.entry.questID == selectedQuestID then selectedEntry = row.entry; break end
        end
        self:SelectQuest(selectedEntry or firstShown or entries[1])
    end
end

function Journal:SelectQuest(entry)
    if not entry then return end
    local quest = MS.JourneyQuestData.latestByID and MS.JourneyQuestData.latestByID[entry.questID]
    if not quest then quest = { questID = entry.questID, title = entry.title,
        level = entry.level, state = entry.complete and "READY_TO_TURN_IN" or "UNKNOWN" } end
    if MS.JourneyContextPanel then MS.JourneyContextPanel:SelectQuest(quest) end
end

-- Right-click: the quest becomes the page's quest, then Journey's menu opens on it.
function Journal:OpenQuestMenu(entry)
    if not entry or not MS.JourneyQuestActions then return false end
    self:SelectQuest(entry)
    local quest = MS.JourneyContextPanel and MS.JourneyContextPanel.questRecord
    if not quest or quest.questID ~= entry.questID then return false end
    return MS.JourneyQuestActions:OpenMenu(quest, "QUESTS_LIST")
end

function Journal:RefreshSelection()
    local context = MS.JourneyContextPanel and MS.JourneyContextPanel.selectedContext
    local selectedQuestID = context and context.type == "QUEST" and context.questID
    for _, hit in pairs(self.hitRows) do
        if hit.entry then
            local selected = hit.entry.questID == selectedQuestID
            MS.JourneyUIStyle:DarkSelection(hit.selected, hit.selectedRule, hit.title, hit.meta, selected)
        end
    end
end

function Journal:RevealSelectedQuest()
    local context = MS.JourneyContextPanel and MS.JourneyContextPanel.selectedContext
    if not context or context.type ~= "QUEST" or not self.scroll then return end
    for _, hit in pairs(self.hitRows) do
        if hit:IsShown() and hit.entry and hit.entry.questID == context.questID then
            local scroll = self.scroll:GetVerticalScroll()
            local top, bottom = hit.rowTop or 0, (hit.rowTop or 0) + hit:GetHeight()
            local height = self.scroll:GetHeight()
            if top < scroll or bottom > scroll + height then
                local maximum = math.max(0, self.content:GetHeight() - height)
                self.scroll:SetVerticalScroll(math.max(0, math.min(maximum, top)))
            end
            return
        end
    end
end

-- Keep diagnostic totals fresh without constructing objective rows for a hidden view.
function Journal:RefreshCounts()
    local count, getEntry = Entries()
    local quests, complete = 0, 0
    for index = 1, count do
        local entry = getEntry(index)
        if entry and not entry.header then
            quests = quests + 1
            if entry.complete then complete = complete + 1 end
        end
    end
    self.questCount, self.completedCount = quests, complete
end

function Journal:Start()
    if self.active then return end
    self.active = true
    self.dirty, self.refreshCount, self.deferredRefreshCount = true, 0, 0
    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:SetScript("OnEvent", function(_, event)
            MS.JourneyQuestData:ScheduleRefresh(event)
        end)
    end
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
        "QUEST_TURNED_IN", "QUEST_WATCH_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
        "ZONE_CHANGED_INDOORS", "PLAYER_ENTERING_WORLD" }) do
        pcall(self.eventFrame.RegisterEvent, self.eventFrame, event)
    end
    self:RefreshCounts()
    self:Refresh()
end

function Journal:Stop()
    self.active, self.visible = false, false
    self.refreshTicket = nil
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
end
