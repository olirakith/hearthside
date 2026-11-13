local MS = _G.MS
local Data = MS.JourneyMapData
local QuestData = MS.JourneyQuestData
local Style = MS.JourneyUIStyle
local PinAssets = MS.JourneyPinAssets
local ExplorationLayer = MS.JourneyExplorationLayer
local PLAYER_ARROW_ROTATION_OFFSET = 0

MS.MapView = {
	active = false,
	mode = "FOLLOW_PLAYER",
	tiles = {},
	questButtons = {},
	rows = {},
	breadcrumbs = {},
	playerTickerInterval = 0.25,
	status = { support = "PENDING", view = "HIDDEN", destination = "WORKSPACE" },
}
local Map = MS.MapView

local C = { ink = Style.colors.backgroundDeep, panel = Style.colors.paper,
	panelLight = Style.colors.paperRaised, gold = Style.colors.gold,
	muted = Style.colors.inkSecondary }

local function Paint(parent, layer, color, inset)
	local texture = parent:CreateTexture(nil, layer)
	if inset then
		texture:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
		texture:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
	else
		texture:SetAllPoints(parent)
	end
	texture:SetColorTexture(unpack(color))
	return texture
end

local function Label(parent, template, color, token)
	local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
	if color then
		label:SetTextColor(color[1], color[2], color[3])
	end
	label:SetJustifyH("LEFT")
	Style:Body(label, token or "BODY", "ink")
    if color then label:SetTextColor(color[1], color[2], color[3]) end
	return label
end

local function Button(parent, text, width)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, 24)
	button.background = Paint(button, "BACKGROUND", Style.colors.backgroundRaised)
    button.background:SetAlpha(.55)
	local label = Label(button, "GameFontNormalSmall", C.gold, "SMALL")
	label:SetPoint("CENTER", button, "CENTER")
	label:SetWidth(width - 10)
	label:SetJustifyH("CENTER")
	label:SetText(text)
	button.label = label
	button:SetScript("OnEnter", function()
		Style:Text(label, "textPrimary"); button.background:SetAlpha(.9)
	end)
	button:SetScript("OnLeave", function()
		Style:Text(label, button.baseColor or "gold"); button.background:SetAlpha(.55)
	end)
	button:SetScript("OnMouseDown", function() button.background:SetAlpha(1) end)
	button:SetScript("OnMouseUp", function() button.background:SetAlpha(.9) end)
	return button
end

local function SafeShort(value, maxLength)
	return string.sub(tostring(value or ""), 1, maxLength or 70)
end

function Map:LoadState()
	local db = MS.Database and MS.Database:Get()
	local saved = db and db.journeyMap
	if type(saved) ~= "table" then
		return
	end
	-- Activation preference is applied by BeginActivation; retain last map as history.
	self.mode = "FOLLOW_PLAYER"
	if type(saved.mapID) == "number" then
		self.savedMapID = saved.mapID
	end
end

function Map:SaveState()
	local db = MS.Database and MS.Database:Get()
	local saved = db and db.journeyMap
	if type(saved) ~= "table" then
		return
	end
	saved.mode, saved.mapID = self.mode, self.mapID
end

function Map:Create(parent)
	if self.frame then
		return true
	end
	self:LoadState()
	local frame = CreateFrame("Frame", "JourneyMapViewFrame", parent)
	frame:Hide()
	self.frame = frame
	Style:Material(Paint(frame, "BACKGROUND", Style.colors.backgroundDeep), "backgroundDeep")
	self.topRule = frame:CreateTexture(nil, "ARTWORK")
	self.topRule:SetPoint("TOPLEFT", frame, "TOPLEFT", 11, -39)
	self.topRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -11, -39)
	self.topRule:SetHeight(1)
	self.topRule:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.55)
	self.breadcrumb = CreateFrame("Frame", nil, frame)
		self.playerButton = Button(frame, MS.L.JOURNEY_MAP_PLAYER_MAP, 104)
    Style:Action(self.playerButton, self.playerButton.label)
		self.playerButton:SetScript("OnClick", function()
		Map:GoToPlayer()
	end)
	self.mapPanel = CreateFrame("Frame", nil, frame)
	-- Quests to pick up (QuestieDB) take the right column in place of the player's own quests.
	self.offersButton = Button(frame, "", 230)
	Style:Action(self.offersButton, self.offersButton.label)
	self.offersButton:SetScript("OnClick", function() Map:ToggleOffers() end)
	self.offersButton:Hide()
    self.zoneStrip = Label(self.mapPanel, "GameFontNormal", Style.colors.textSecondary, "SMALL")
    self.zoneStrip:SetWordWrap(false); self.zoneStrip:SetMaxLines(1)
	Paint(self.mapPanel, "BACKGROUND", Style.colors.backgroundDeep)
	self.canvas = CreateFrame("Frame", nil, self.mapPanel)
	self.canvas:EnableMouse(true)
	Paint(self.canvas, "BACKGROUND", Style.colors.backgroundDeep)
	Style:Rim(self.mapPanel, self.canvas)
	if MS.JourneyRoadNote then MS.JourneyRoadNote:Create(self.mapPanel) end
	self.artBackdrop = self.canvas:CreateTexture(nil, "ARTWORK")
	self.artBackdrop:SetAllPoints(self.canvas)
	self.artBackdrop:SetAlpha(1)
	self.artBackdrop:Hide()
	self.exploration = ExplorationLayer:Create(self.canvas)
	self.emptyArt = Label(self.canvas, "GameFontHighlight", C.gold, "BODY_LARGE")
	self.emptyArt:SetPoint("CENTER", self.canvas, "CENTER")
	self.emptyArt:SetWidth(280)
	self.emptyArt:SetJustifyH("CENTER")
	self.emptyArt:SetText(MS.L.JOURNEY_MAP_ART_UNAVAILABLE)
	self.canvas:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			Map:GoToParent()
		elseif button == "LeftButton" then
			if not Map:NavigateAtCursor() and MS.JourneyContextPanel then
				MS.JourneyContextPanel:Clear()
			end
		end
	end)
	self.playerPin = CreateFrame("Frame", nil, self.canvas)
	self.playerPin:SetSize(28, 28)
	self.playerPin:SetFrameLevel(self.canvas:GetFrameLevel() + 8)
	self.playerIcon = self.playerPin:CreateTexture(nil, "ARTWORK")
	self.playerIcon:SetPoint("CENTER", self.playerPin, "CENTER")
	self.playerIcon:SetSize(26, 26)
	self.playerPin:Hide()
	self.friendPin = CreateFrame("Frame", nil, self.canvas)
	self.friendPin:SetSize(28, 28)
	self.friendPin:SetFrameLevel(self.canvas:GetFrameLevel() + 7)
	self.friendIcon = self.friendPin:CreateTexture(nil, "ARTWORK")
	self.friendIcon:SetPoint("CENTER", self.friendPin, "CENTER")
	self.friendIcon:SetSize(26, 26)
	self.friendLabel = self.friendPin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.friendLabel:SetPoint("TOP", self.friendPin, "BOTTOM", 0, 0)
	self.friendPin:Hide()
	self.side = Style:DarkInset(frame)
	self.sideTitle = Label(self.side, "GameFontNormal", Style.colors.textPrimary, "SECTION")
	self.sideTitle:SetPoint("TOPLEFT", self.side, "TOPLEFT", 14, -14)
	self.sideTitle:SetText(MS.L.JOURNEY_MAP_REGION_QUESTS)
	-- With QuestieDB, two fixed tabs switch the column between the journal and the quests to pick up.
	self.segments = {}
	for index, offers in ipairs({ false, true }) do
		local button = Button(self.side, "", 120)
		button.rule = button:CreateTexture(nil, "ARTWORK")
		button.rule:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT"); button.rule:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT")
		button.rule:SetHeight(2); Style:Color(button.rule, "gold")
		button:SetScript("OnEnter", function() Style:TabState(button, button.active, true) end)
		button:SetScript("OnLeave", function() Style:TabState(button, button.active, false) end)
		button:SetScript("OnClick", function() Map:ToggleOffers(offers) end)
		button:Hide()
		self.segments[index] = button
	end
	-- The next step: one game fact from the road note, clickable when it names a quest.
	self.nextStep = CreateFrame("Button", nil, self.side)
	self.nextStep.background = Paint(self.nextStep, "BACKGROUND", Style.colors.backgroundRaised)
	self.nextStep.edge = self.nextStep:CreateTexture(nil, "BORDER")
	self.nextStep.edge:SetPoint("TOPLEFT", self.nextStep, "TOPLEFT"); self.nextStep.edge:SetPoint("BOTTOMLEFT", self.nextStep, "BOTTOMLEFT")
	self.nextStep.edge:SetWidth(3); Style:Color(self.nextStep.edge, "gold")
	self.nextStep.kicker = Label(self.nextStep, "GameFontNormalSmall", C.gold, "SMALL")
	self.nextStep.kicker:SetPoint("TOPLEFT", self.nextStep, "TOPLEFT", 12, -7)
	self.nextStep.kicker:SetText(MS.L.JOURNEY_MAP_NEXT_STEP)
	self.nextStep.text = Label(self.nextStep, "GameFontHighlightSmall", Style.colors.textPrimary, "BODY")
	self.nextStep.text:SetPoint("TOPLEFT", self.nextStep.kicker, "BOTTOMLEFT", 0, -4)
	self.nextStep.background:SetAlpha(.6)
	self.nextStep:SetScript("OnEnter", function() Map.nextStep.background:SetAlpha(1) end)
	self.nextStep:SetScript("OnLeave", function() Map.nextStep.background:SetAlpha(.6) end)
	self.nextStep:SetScript("OnClick", function() if Map.nextStepQuest then Map:SelectQuest(Map.nextStepQuest) end end)
	self.nextStep:Hide()
	self.detailPanel = Style:PaperInset(self.side)
	self.detailPanel:SetFrameLevel(self.canvas:GetFrameLevel() + 11)
    self.closeNote = Style:PaperCloseButton(self.detailPanel, function() MS.JourneyContextPanel:Clear() end)
    self.closeNote:SetPoint("TOPRIGHT", self.detailPanel, "TOPRIGHT", -2, -2)
	if MS.JourneyContextPanel then
		MS.JourneyContextPanel:Create(self.detailPanel)
		self.detailTitle, self.detailBody = MS.JourneyContextPanel.title, MS.JourneyContextPanel.body
	else
		self.detailTitle = Label(self.detailPanel)
		self.detailBody = Label(self.detailPanel)
	end
	self.detailPanel:Hide()
	self.scroll = CreateFrame("ScrollFrame", nil, self.side)
	self.scroll:EnableMouseWheel(true)
	self.scroll:SetScript("OnMouseWheel", function(scroll, delta)
		local maxScroll = math.max(0, self.scrollChild:GetHeight() - scroll:GetHeight())
		scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, scroll:GetVerticalScroll() - delta * 42)))
	end)
	self.scrollChild = CreateFrame("Frame", nil, self.scroll)
	self.scrollChild:SetSize(1, 1)
	self.scroll:SetScrollChild(self.scrollChild)
	self.eventFrame = CreateFrame("Frame", nil, frame)
	self.eventFrame:SetScript("OnEvent", function(_, event, ...)
		Map:OnEvent(event, ...)
	end)
	frame:SetScript("OnHide", function()
		Map:StopTicker()
	end)
	self.status.supported = self:IsSupported()
	return true
end

function Map:OnEvent(event)
	if not self.active then
		return
	end
	if event == "MAP_EXPLORATION_UPDATED" then
		self:RefreshExploration()
		return
	end
	if QuestData.indexing then return end
	if event == "PLAYER_REGEN_ENABLED" then
		if QuestData.indexDirty then
			self:RefreshQuests()
		end
		return
	end
	if
		event == "ZONE_CHANGED_NEW_AREA"
		or event == "ZONE_CHANGED"
		or event == "ZONE_CHANGED_INDOORS"
		or event == "PLAYER_ENTERING_WORLD"
	then
		local _, key = QuestData:Candidates(self.mapID)
		if event == "PLAYER_ENTERING_WORLD" or not QuestData.index or QuestData.index.candidateKey ~= key then
			QuestData:Invalidate(event)
		end
		if self.mode == "FOLLOW_PLAYER" then
			self:FollowPlayerMap(event)
		else
			self:ResolvePlayerJourneyMap() -- Diagnostic only; manual navigation owns the canvas.
			if QuestData.indexDirty then self:RefreshQuests() end
			self:UpdatePlayer()
			self:RefreshExploration()
		end
	elseif
		event == "QUEST_LOG_UPDATE"
		or event == "QUEST_TURNED_IN"
		or event == "QUEST_ACCEPTED"
		or event == "QUEST_REMOVED"
	then
		QuestData:ScheduleRefresh(event)
	end
end

function Map:Layout(region)
	if not self.frame or not region then
		return
	end
	self.region = region
	self.status.uiTextScale = MS.JourneySettings:Get("textScale")
	self.status.sessionJournalWidth = MS.JourneyWorkspace.sessionJournalWidth
	self.frame:ClearAllPoints()
	self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", region.x, region.y)
	self.frame:SetSize(region.width, region.height)
	local width, height = math.max(1, region.width), math.max(1, region.height)
	-- The plan follows the screen: map and column side by side, the journal under the map on a
	-- tall or narrow screen, or map, list and card in three columns on a very wide one.
	local layer = self.art and self.art.layer
	local aspect = layer and type(layer.layerWidth) == "number" and type(layer.layerHeight) == "number"
		and layer.layerHeight > 0 and layer.layerWidth / layer.layerHeight or 1000 / 700
	local Plan = MS.JourneyMapLayout
	local plan = Plan:Compute({ width = width, height = height, scale = MS.JourneySettings:Get("textScale"),
		aspect = aspect, card = "QUEST" })
	self.layoutPlan = plan
	self.status.layoutMode = plan.mode
	-- The card leaves the column for its own place in three columns and on a wide stacked screen.
	local outside = plan.card ~= nil and (plan.mode == "THREE" or (plan.mode == "STACK" and width >= Plan.STACK_MIN_WIDTH))
	self.cardRect = outside and plan.card or nil
	local column = plan.list
	if not outside and plan.card then
		column = { x = plan.list.x, y = plan.list.y, w = plan.list.w, h = plan.card.y + plan.card.h - plan.list.y }
	end
	self.breadcrumb:ClearAllPoints()
	self.breadcrumb:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -8)
	self.breadcrumb:SetSize(math.max(100, width - 140), 26)
		self.playerButton:ClearAllPoints()
	self.playerButton:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -12, -7)
	self.mapPanel:ClearAllPoints()
	self.mapPanel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", plan.map.x, -plan.map.y)
	self.mapPanel:SetSize(math.max(1, plan.map.w), math.max(1, plan.map.h))
	self.side:ClearAllPoints()
	self.side:SetPoint("TOPLEFT", self.frame, "TOPLEFT", column.x, -column.y)
	self.side:SetSize(math.max(1, column.w), math.max(1, column.h))
    self:LayoutRightColumn()
	self:LayoutCanvas()
	if self.active then
		self:RenderArt()
		self:RefreshBreadcrumb()
		self:RenderSidebar()
		self:RenderQuests()
		self:UpdatePlayer()
	end
end

function Map:LayoutRightColumn()
    if not self.side or not self.scroll then return end
    local context = MS.JourneyContextPanel and MS.JourneyContextPanel.selectedContext
    local shown = self.active and context and context.type ~= "EMPTY"
    local width, height = self.side:GetWidth(), self.side:GetHeight()
    local panel = MS.JourneyContextPanel
    local compact = shown and panel:IsCompactZone()
    local scale = MS.JourneySettings:Get("textScale")
    local header = self:LayoutColumnHeader(width)
    self.status.columnHeader = header
    local card = self.cardRect
    local cardHeight = 0
    self.detailPanel:ClearAllPoints()
    if card then
        -- Its own place: the full height for a quest, a short summary at the top for a zone.
        cardHeight = compact and math.min(card.h, panel:CompactHeight()) or card.h
        self.detailPanel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", card.x, -card.y)
        self.detailPanel:SetSize(math.max(1, card.w), math.max(1, cardHeight))
    else
        cardHeight = shown and math.min(height * .48, 330 * scale) or 0
        -- A zone reads as a short summary until the player asks for the whole text.
        if compact then cardHeight = math.min(cardHeight, panel:CompactHeight()) end
        -- The list keeps room for a few rows: the card gives way first (chat open, small screen).
        local room = height - header - 20 - 120 * scale
        if shown and not compact and cardHeight > room then
            cardHeight = math.max(math.min(cardHeight, panel:CompactHeight()), room)
        end
        self.detailPanel:SetPoint("BOTTOMLEFT", self.side, "BOTTOMLEFT", 6, 6)
        self.detailPanel:SetSize(math.max(1, width - 12), math.max(1, cardHeight))
    end
    self.detailPanel:SetShown(shown == true)
    local listCut = (shown and not card) and cardHeight + 10 or 0
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", self.side, "TOPLEFT", 11, -header)
    self.scroll:SetSize(math.max(1, width - 22), math.max(1, height - header - 10 - listCut))
    self.scrollChild:SetWidth(math.max(1, width - 24))
    self.scroll:SetVerticalScroll(math.min(self.scroll:GetVerticalScroll(),
        math.max(0, self.scrollChild:GetHeight() - self.scroll:GetHeight())))
    if MS.JourneyContextPanel and MS.JourneyWorkspace.view == "MAP" then
        MS.JourneyContextPanel:Mount(self.detailPanel)
        MS.JourneyContextPanel:Layout(self.detailPanel:GetWidth(), self.detailPanel:GetHeight(), "NOTE")
        -- The folded card is measured once drawn: fit it to its real text, once.
        if compact and not self.fittingCard and math.abs(panel:CompactHeight() - cardHeight) > 1 then
            self.fittingCard = true
            self:LayoutRightColumn()
            self.fittingCard = nil
        end
    end
end

-- Tabs and next step above the list; returns where the list starts.
function Map:LayoutColumnHeader(width)
    local top = 42
    if self.segments and self.segments[1]:IsShown() then
        local half = math.floor((width - 28) / 2)
        for index, button in ipairs(self.segments) do
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", self.side, "TOPLEFT", 12 + (index - 1) * (half + 4), -10)
            button:SetSize(math.max(1, half), 28); button.label:SetWidth(math.max(1, half - 10))
        end
        top = 48
    end
    if self.nextStep and self.nextStep:IsShown() then
        local inner = math.max(1, width - 48)
        self.nextStep.kicker:SetWidth(inner); self.nextStep.text:SetWidth(inner)
        local textHeight = self.nextStep.text:GetStringHeight()
        local bandHeight = math.ceil((type(textHeight) == "number" and textHeight or 16) + 34)
        self.nextStep:ClearAllPoints()
        self.nextStep:SetPoint("TOPLEFT", self.side, "TOPLEFT", 12, -top)
        self.nextStep:SetSize(math.max(1, width - 24), bandHeight)
        top = top + bandHeight + 8
    end
    return top
end

function Map:LayoutCanvas()
	if not self.canvas then
		return
	end
	local maxWidth = math.max(1, self.mapPanel:GetWidth() - 8)
	-- The zone line (name, quests done, quests to pick up) always keeps its room under the
	-- map: a lower region (chat open, small screen) shrinks the map rather than hiding it.
	local stripRoom = (32 + 8) * MS.JourneySettings:Get("textScale")
	local maxHeight = math.max(1, self.mapPanel:GetHeight() - 8 - stripRoom)
	local layer = self.art and self.art.layer
	local aspect = layer and layer.layerWidth / layer.layerHeight or maxWidth / maxHeight
	local width = math.min(maxWidth, maxHeight * aspect)
	local height = width / aspect
	self.canvas:ClearAllPoints()
	self.canvas:SetPoint("TOP", self.mapPanel, "TOP", 0, 0)
	self.canvas:SetSize(width, height)
	self.status.renderRect = string.format("%.0fx%.0f", width, height)
	self.status.mapPanelRect = string.format("%.0fx%.0f", self.mapPanel:GetWidth(), self.mapPanel:GetHeight())
	self.status.canvasMargin = string.format("%.0f/%.0f", (maxWidth - width) / 2, 0)
    self:RefreshZoneStrip()
    if MS.JourneyStatusBar and MS.JourneyStatusBar.PlaceForView then MS.JourneyStatusBar:PlaceForView() end
end

function Map:RefreshZoneStrip()
    if not self.zoneStrip or not self.canvas then return end
    local spare = self.mapPanel:GetHeight() - self.canvas:GetHeight()
    self.zoneStrip:SetShown(spare >= 32 * MS.JourneySettings:Get("textScale"))
    self.zoneStrip:ClearAllPoints(); self.zoneStrip:SetPoint("TOPLEFT", self.canvas, "BOTTOMLEFT", 0, -8)
    self.zoneStrip:SetSize(self.canvas:GetWidth(), 24 * MS.JourneySettings:Get("textScale"))
    self:PlaceOffersButton()
    local zoneID = Data:LocalZone(self.mapID)
    local info = Data:Info(zoneID or self.mapID)
    local parts = { info and info.name or MS.L.JOURNEY_MAP_UNKNOWN_ZONE }
    local memory = MS.JourneyMemory
    local zone = zoneID and memory and memory:GetZone(zoneID)
    if zone then
        local count = memory:CompletedQuestCount(zoneID) or 0
        if count > 0 then parts[#parts + 1] = string.format(MS.L[count == 1 and "JOURNEY_UI_ZONE_QUEST_ONE" or "JOURNEY_UI_ZONE_QUESTS"], count) end
    end
    local readyHere = 0
    for _, quest in ipairs(self.quests and self.quests.here or {}) do
        if quest.state == "READY_TO_TURN_IN" then readyHere = readyHere + 1 end
    end
    if readyHere > 0 then
        parts[#parts + 1] = string.format(MS.L[readyHere == 1 and "JOURNEY_ZONE_SUMMARY_READY_ONE" or "JOURNEY_ZONE_SUMMARY_READY"], readyHere)
    end
    self.zoneStrip:SetText(table.concat(parts, " · "))
    if MS.JourneyRoadNote then MS.JourneyRoadNote:Place(self.canvas, spare, MS.JourneySettings:Get("textScale")) end
end

-- Under the map, right of the zone line, when there is room; in the column header otherwise.
function Map:PlaceOffersButton()
    local button = self.offersButton
    if not button then return end
    if not button:IsShown() then
        if self.zoneStrip:IsShown() then self.zoneStrip:SetWidth(math.max(1, self.canvas:GetWidth())) end
        return
    end
    local scale = MS.JourneySettings:Get("textScale")
    local width = math.min(260 * scale, math.max(160, (button.label:GetStringWidth() or 0) + 28))
    button:SetSize(width, 24 * scale)
    button.label:SetWidth(width - 10)
    button:ClearAllPoints()
    -- The zone name keeps at least 120 units beside the button, else the button moves up.
    if self.zoneStrip:IsShown() and self.canvas:GetWidth() - width - 10 >= 120 then
        button:SetPoint("TOPRIGHT", self.canvas, "BOTTOMRIGHT", 0, -4)
        self.zoneStrip:SetWidth(math.max(1, self.canvas:GetWidth() - width - 10))
    else
        button:SetPoint("TOPRIGHT", self.side, "TOPRIGHT", -10, -10)
        if self.zoneStrip:IsShown() then self.zoneStrip:SetWidth(math.max(1, self.canvas:GetWidth())) end
    end
    button:SetFrameLevel(self.canvas:GetFrameLevel() + 20)
end

function Map:ToggleOffers(wanted)
    if wanted == nil then wanted = not self.offersMode end
    self.offersMode = wanted == true
    if self.scroll then self.scroll:SetVerticalScroll(0) end
    self:RenderSidebar()
end

function Map:HoverQuest(questID)
    self.hoveredQuestID = questID
    self:RefreshSelection()
    if MS.JourneyMapCanvas then MS.JourneyMapCanvas:Highlight(questID) end
end

-- A native pin can show a quest Journey does not list here.
function Map:QuestFromPin(questID)
    local quests = self.quests or {}
    for _, list in ipairs({ quests.here or {}, quests.elsewhere or {}, quests.unlocated or {} }) do
        for _, quest in ipairs(list) do
            if quest.questID == questID then return quest end
        end
    end
    local log = _G.C_QuestLog
    local title = log and log.GetTitleForQuestID and log.GetTitleForQuestID(questID)
    return { questID = questID, title = title or MS.L.JOURNEY_QUEST_DETAILS, state = "UNKNOWN",
        mapName = self.status.mapName, mapID = self.mapID }
end

function Map:RevealQuestRow(questID)
    for _, row in ipairs(self.rows) do
        if row:IsShown() and row.questID == questID then
            local top, height, scroll = row.rowTop or 0, self.scroll:GetHeight(), self.scroll:GetVerticalScroll()
            local nextScroll = top < scroll and top or top + row:GetHeight() > scroll + height and top + row:GetHeight() - height or scroll
            self.scroll:SetVerticalScroll(math.max(0, math.min(nextScroll, self.scrollChild:GetHeight() - height)))
            return
        end
    end
end

function Map:RenderArt()
	for _, tile in ipairs(self.tiles) do
		tile:Hide()
	end
	self.artBackdrop:Hide()
	self.status.backgroundAtlas = nil
	local atlas = Data:BackgroundAtlas(self.mapID)
	if atlas and type(self.artBackdrop.SetAtlas) == "function" then
		local ok = pcall(self.artBackdrop.SetAtlas, self.artBackdrop, atlas)
		if ok then
			self.artBackdrop:Show()
			self.status.backgroundAtlas = atlas
		end
	end
	local art = self.art
	local count, missing = 0, 0
	if art then
		local layer, textures = art.layer, art.textures
		local width, height = self.canvas:GetWidth(), self.canvas:GetHeight()
		for row = 0, art.rows - 1 do
			for column = 0, art.columns - 1 do
				local index = row * art.columns + column + 1
				local file = textures[index]
				if (type(file) == "number" and file > 0) or (type(file) == "string" and file ~= "") then
					local tile = self.tiles[index]
					if not tile then
						tile = self.canvas:CreateTexture(nil, "ARTWORK")
						self.tiles[index] = tile
					end
					local ok = pcall(tile.SetTexture, tile, file)
					if ok then
						local tw = math.min(layer.tileWidth, layer.layerWidth - column * layer.tileWidth)
						local th = math.min(layer.tileHeight, layer.layerHeight - row * layer.tileHeight)
						tile:ClearAllPoints()
						tile:SetPoint(
							"TOPLEFT",
							self.canvas,
							"TOPLEFT",
							column * layer.tileWidth / layer.layerWidth * width,
							-row * layer.tileHeight / layer.layerHeight * height
						)
						tile:SetSize(tw / layer.layerWidth * width, th / layer.layerHeight * height)
						tile:SetTexCoord(0, tw / layer.tileWidth, 0, th / layer.tileHeight)
						tile:SetAlpha(1)
						tile:Show()
						count = count + 1
					else
						missing = missing + 1
					end
				else
					missing = missing + 1
				end
			end
		end
	end
	self.emptyArt:SetShown(count == 0)
	self.status.artTiles = count
	self.status.missingTiles = missing
	self.status.artSource = art and art.source or "JOURNEY_BACKDROP_FALLBACK"
	self.status.artFallback = count == 0 and (self.artBackdrop:IsShown() and "BACKGROUND_ATLAS" or "JOURNEY_BACKDROP")
		or missing > 0 and "MISSING_TILE"
		or "NONE"
	self.status.support = count > 0 and missing == 0 and "READY" or "PARTIAL"
	self:RefreshExploration()
end

function Map:RefreshExploration()
	if not self.exploration then
		return
	end
	local result = self.exploration:Render(self.mapID, self.art)
	self.status["exploration.supported"] = result.supported
	self.status["exploration.textureCount"] = result.textureCount
	self.status["exploration.source"] = result.source
	self.status["exploration.error"] = result.error
	self.status["exploration.shape"] = result.shape
end

function Map:RefreshBreadcrumb()
	local chain = self.chain or {}
	for _, button in ipairs(self.breadcrumbs) do
		button:Hide()
	end
	local x, width = 0, self.breadcrumb:GetWidth()
	for index, info in ipairs(chain) do
		local text = info.name or MS.L.JOURNEY_MAP_UNKNOWN_ZONE
        if index < #chain then text = string.format(MS.L.JOURNEY_MAP_BREADCRUMB_LINK, text) end
		local button = self.breadcrumbs[index]
		if not button then
			button = Button(self.breadcrumb, "", 70)
			button:SetHeight(22)
            button.background:Hide()
            Style:Link(button, button.label)
			self.breadcrumbs[index] = button
		end
		local perLevel = math.max(1, (width - math.max(0, #chain - 1) * 5) / math.max(1, #chain))
        local buttonWidth = math.min(perLevel, 150, math.max(36, #text * 7 + 18))
		if x + buttonWidth > width then
			break
		end
		button:SetWidth(buttonWidth)
		button.label:SetWidth(buttonWidth - 8)
        button.label:SetWordWrap(false); button.label:SetMaxLines(1)
		button.label:SetText(text)
        button.baseColor = index == #chain and "gold" or "textSecondary"
        Style:Text(button.label, button.baseColor)
		button:ClearAllPoints()
		button:SetPoint("LEFT", self.breadcrumb, "LEFT", x, 0)
		local id = info.mapID
		button:SetScript("OnClick", function()
			Map:Navigate(id)
		end)
		button:Show()
		x = x + buttonWidth + 5
	end
	self.status.breadcrumbDepth = #chain
end

Map.SIDEBAR_ROW_CAPACITY = 96

function Map:Row(kind, title, subtitle, action, quest)
	local index = self.rowCount + 1
	if index > self.SIDEBAR_ROW_CAPACITY then
		return
	end
	self.rowCount = index
	local row = self.rows[index]
	if not row then
		row = CreateFrame("Button", nil, self.scrollChild)
		row.hover = Paint(row, "BACKGROUND", Style.colors.backgroundRaised)
		row.hover:SetAlpha(.5); row.hover:Hide()
		row.selection = Paint(row, "BORDER", Style.colors.backgroundRaised)
		row.selection:SetAlpha(.9); row.selection:Hide()
		row.selectedRule = row:CreateTexture(nil, "ARTWORK")
		row.selectedRule:SetPoint("TOPLEFT", row, "TOPLEFT")
		row.selectedRule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
		row.selectedRule:SetWidth(3)
		Style:Color(row.selectedRule, "bronze")
		row.selectedRule:Hide()
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -7)
		row.icon:SetSize(17, 17)
		row.levelBack = Paint(row, "ARTWORK", Style.colors.backgroundDeep)
        -- Paint() fills the row; drop both anchors so the chip keeps its own bounded size.
        row.levelBack:ClearAllPoints()
        row.levelBack:SetPoint("TOPLEFT", row, "TOPLEFT", 29, -2)
        row.levelBack:SetSize(48, 22)
        row.levelLabel = Label(row, "GameFontNormal", Style.colors.textPrimary, "BODY")
        row.levelLabel:SetPoint("TOPLEFT", row, "TOPLEFT", 31, -3)
        row.levelLabel:SetWidth(48)
		row.title = Label(row, "GameFontHighlightSmall", Style.colors.textPrimary, "BODY")
		row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 7, -3)
		row.subtitle = Label(row, "GameFontHighlightSmall", C.muted, "SMALL")
		row.subtitle:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
		self.rows[index] = row
	end
	local height = kind == "HEADING" and 29 or subtitle and 45 or 31
	row.rowTop = self.rowY
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -self.rowY)
	row:SetSize(self.scrollChild:GetWidth(), height)
	row.title:SetWidth(math.max(1, row:GetWidth() - (quest and 88 or 14)))
	row.subtitle:SetWidth(math.max(1, row:GetWidth() - (quest and 88 or 14)))
	row.title:ClearAllPoints()
	row.title:SetPoint("TOPLEFT", row, "TOPLEFT", quest and 79 or 7, -3)
	Style:QuestRowState(row.icon, row.levelLabel, quest and quest.state or "UNKNOWN", quest and quest.level)
    row.levelBack:SetShown(quest ~= nil and type(quest.level) == "number" and quest.level > 0)
	row.icon:SetShown(quest ~= nil)
	if quest then
		local color = (Style.questStates[quest.state] or Style.questStates.UNKNOWN).color
		Style:QuestStateGlyph(row.icon, quest.state, color)
	end
	if kind == "ZONE" then Style:Heading(row.title, "TITLE", "textPrimary")
    else Style:Body(row.title, quest and "ITEM_TITLE" or "BODY", "textPrimary") end
	row.title:SetText(title)
	Style:Text(row.title, kind == "HEADING" and "textSecondary" or "textPrimary")
	row.subtitle:SetText(subtitle or "")
	row.subtitle:SetShown(subtitle ~= nil)
	row.questID = quest and quest.questID
	local selected = MS.JourneyContextPanel and MS.JourneyContextPanel.selectedContext
	local isSelected = row.questID ~= nil and selected and selected.questID == row.questID
	Style:DarkSelection(row.selection, row.selectedRule, quest and row.title or nil, quest and row.subtitle or nil, isSelected == true)
	row.inert = action == nil
	row.rowHovered = row.IsMouseOver and row:IsMouseOver() == true
	Style:RowState(row)
	-- Quest rows also answer the right-click with Journey's quest menu.
	if quest then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") else row:RegisterForClicks("LeftButtonUp") end
	if quest then
		row:SetScript("OnClick", function(_, mouseButton)
			if mouseButton == "RightButton" then Map:OpenQuestMenu(quest, "MAP_LIST") elseif action then action() end
		end)
	else
		row:SetScript("OnClick", action)
	end
	Style:ReactiveRow(row, quest and function() Map:HoverQuest(quest.questID) end,
		quest and function() Map:HoverQuest(nil) end)
    if kind == "LINK" then Style:Link(row, row.title, false) end
	row:EnableMouse(action ~= nil or quest ~= nil)
	local titleHeight, subHeight = row.title:GetStringHeight(), row.subtitle:GetStringHeight()
	if type(titleHeight) == "number" then
		height = math.max(height, titleHeight + (subtitle and type(subHeight) == "number" and subHeight or 0) + 12)
		row:SetHeight(height)
	end
	row:Show()
	self.rowY = self.rowY + height + Style.space.xs
end

function Map:StateLabel(state)
	if state ~= "IN_PROGRESS" and state ~= "READY_TO_TURN_IN" and state ~= "AVAILABLE" then return MS.L.JOURNEY_QUEST_DETAILS end
	return MS.L["JOURNEY_MAP_STATE_" .. state]
end

function Map:QuestSubtitle(quest)
	return string.format(
		MS.L.JOURNEY_MAP_QUEST_ROW,
		QuestData:DisplayPlaceName(quest),
		self:StateLabel(quest.state)
	)
end

-- Plans the quest list inside the row capacity before any row is emitted. Local quests come
-- first; when other-region quests exist, one row is always kept for them (heading + rows, or
-- the disclosure link), and a heading is never planned without at least one child row.
function Map:PlanQuestRows(localCount, otherCount, capacity)
	local plan = { localShown = 0, otherShown = 0, otherHidden = 0 }
	local remaining = math.max(0, capacity)
	if localCount > 0 then
		local reserve = otherCount > 0 and 1 or 0
		plan.localShown = math.max(0, math.min(localCount, remaining - 1 - reserve))
		if plan.localShown > 0 then remaining = remaining - 1 - plan.localShown end
	end
	if otherCount > 0 then
		if 1 + otherCount <= remaining then
			plan.otherShown = otherCount
		else
			-- Heading + visible rows + disclosure link must all fit.
			plan.otherShown = math.max(0, remaining - 2)
		end
		plan.otherHidden = otherCount - plan.otherShown
	end
	plan.localHeading, plan.otherHeading = plan.localShown > 0, plan.otherShown > 0
	plan.disclosure = plan.otherHidden > 0
	plan.rows = (plan.localHeading and 1 + plan.localShown or 0)
		+ (plan.otherHeading and 1 + plan.otherShown or 0) + (plan.disclosure and 1 or 0)
	plan.remaining = math.max(0, capacity) - plan.rows
	return plan
end

function Map:RenderSidebar()
	local previousScroll = self.scroll:GetVerticalScroll()
	local mapChanged = self.sidebarMapID ~= self.mapID
	self.sidebarMapID = self.mapID
	for _, row in ipairs(self.rows) do
		row:Hide()
	end
	self.rowCount, self.rowY = 0, 0
	local quests = self.quests or {}
	local Guide = MS.JourneyQuestieGuide
	local offersMode = self.offersMode == true and Guide ~= nil and Guide:IsAvailable()
	self.status.offersMode = offersMode
	self.sideTitle:SetText(offersMode and Guide:Title(self.mapID) or MS.L.JOURNEY_MAP_REGION_QUESTS)
	self.segmented = Guide ~= nil and self.mapID ~= nil and Guide:IsAvailable()
	self.status.segmented = self.segmented
	self.sideTitle:SetShown(not self.segmented)
	local journalCount = 0
	for _, list in ipairs({ quests.here or {}, quests.elsewhere or {}, quests.unlocated or {}, quests.ambiguous or {} }) do
		journalCount = journalCount + #list
	end
	for index, button in ipairs(self.segments or {}) do
		button:SetShown(self.segmented)
		if self.segmented then
			button.active = (index == 2) == offersMode
			button.label:SetText(index == 1 and string.format(MS.L.JOURNEY_MAP_TAB_JOURNAL, journalCount)
				or string.format(MS.L.JOURNEY_MAP_TAB_OFFERS, Guide:OfferCount(self.mapID)))
			Style:TabState(button, button.active, false)
		end
	end
	local invite = not offersMode and MS.JourneyRoadNote
		and MS.JourneyRoadNote:Invitation(quests, MS.JourneySession and MS.JourneySession:GetSummary()) or nil
	self.nextStepQuest = invite and invite.quest or nil
	self.nextStep.text:SetText(invite and invite.text or "")
	self.nextStep:SetShown(self.nextStepQuest ~= nil)
	self.status.nextStepQuestID = self.nextStepQuest and self.nextStepQuest.questID or nil
	self:LayoutRightColumn()
	if Guide then pcall(Guide.RefreshButton, Guide, self, offersMode) end
	if offersMode then
		local ok, err = pcall(Guide.RenderRows, Guide, self)
		if not ok then self.status.offersError = tostring(err) end
	else
	local other = {}
	for _, list in ipairs({ quests.elsewhere or {}, quests.unlocated or {}, quests.ambiguous or {} }) do
		for _, quest in ipairs(list) do other[#other + 1] = quest end
	end
	local here = QuestData:ReadyFirst(quests.here)
	other = QuestData:ReadyFirst(other)
	-- Quests ready to turn in lead the list, wherever they are: the one action that pays now.
	local ready = {}
	local function TakeReady(list)
		local kept = {}
		for _, quest in ipairs(list) do
			if quest.state == "READY_TO_TURN_IN" then ready[#ready + 1] = quest else kept[#kept + 1] = quest end
		end
		return kept
	end
	here, other = TakeReady(here), TakeReady(other)
	self.status.readyQuests = #ready
	if #ready > 0 then
		self:Row("HEADING", string.format(MS.L.JOURNEY_MAP_READY_GROUP, #ready))
		for _, quest in ipairs(ready) do
			self:Row("QUEST", quest.title, QuestData:DisplayPlaceName(quest), function() Map:SelectQuest(quest) end, quest)
		end
	end
	local function questRow(quest, isHere)
		local subtitle = isHere and self:StateLabel(quest.state) or self:QuestSubtitle(quest)
		-- A quest in progress reads by its next objective; the state stays on the glyph.
		local objective = quest.state == "IN_PROGRESS" and QuestData:ObjectiveLine(quest)
		if objective then
			subtitle = isHere and objective or string.format(MS.L.JOURNEY_MAP_QUEST_ROW, objective, QuestData:DisplayPlaceName(quest))
		elseif QuestData:HasCountedObjectives(quest) and type(quest.progress.percent) == "number" and quest.progress.percent > 0 then
			subtitle = subtitle .. " " .. string.format(MS.L.JOURNEY_CONTEXT_PERCENT, math.floor(quest.progress.percent + .5))
		end
		self:Row("QUEST", quest.title, subtitle, function() Map:SelectQuest(quest) end, quest)
	end
	-- Quests shared with the party move into a first group; the rest keeps its order.
	local Group = MS.JourneyGroupQuests
	if Group and Group:IsActive() then
		local shared, sharedHere = {}, {}
		for _, source in ipairs({ { here, true }, { other, false } }) do
			local kept = {}
			for _, quest in ipairs(source[1]) do
				if Group:Shares(quest.questID) then
					shared[#shared + 1] = quest; sharedHere[quest] = source[2]
				else
					kept[#kept + 1] = quest
				end
			end
			if source[2] then here = kept else other = kept end
		end
		local shown = math.max(0, math.min(#shared, self.SIDEBAR_ROW_CAPACITY - self.rowCount - 1))
		if shown > 0 then
			self:Row("HEADING", Group:Heading())
			for index = 1, shown do questRow(shared[index], sharedHere[shared[index]]) end
		end
	end
	local plan = self:PlanQuestRows(#here, #other, self.SIDEBAR_ROW_CAPACITY - self.rowCount)
	self.questRowPlan = plan
	for _, group in ipairs({ { MS.L.JOURNEY_MAP_QUESTS_HERE, here, true, plan.localShown },
		{ MS.L.JOURNEY_MAP_QUESTS_ELSEWHERE, other, false, plan.otherShown } }) do
		-- A heading is emitted only when the plan displays at least one of its quests.
		if group[4] > 0 then self:Row("HEADING", group[1]) end
		for index = 1, group[4] do questRow(group[2][index], group[3]) end
	end
    -- Nothing in progress anywhere: say so, and point to the quests to pick up when known.
    self.status.emptyJournal = #here == 0 and #other == 0 and self.rowCount == 0 and #ready == 0
    if self.status.emptyJournal then
        self:Row("NOTE", MS.L.JOURNEY_MAP_EMPTY)
        local offers = Guide and Guide:IsAvailable() and self.mapID and Guide:OfferCount(self.mapID) or 0
        if offers > 0 then
            self:Row("LINK", string.format(MS.L.JOURNEY_MAP_EMPTY_OFFERS, offers), nil, function() Map:ToggleOffers(true) end)
        end
    end
    -- The link stands only for other-region quests the plan left out.
    self.status.hiddenOtherQuests = plan.otherHidden
    if plan.otherHidden > 0 then
        self:Row("LINK", string.format(MS.L[plan.otherHidden == 1 and "JOURNEY_UI_OTHER_QUEST_ONE" or "JOURNEY_UI_OTHER_QUESTS"], plan.otherHidden),
            nil, function() MS.JourneyWorkspace:SelectView("QUESTS") end)
    end
    self:RefreshZoneStrip()
	local children = self.children or {}
	if #children > 0 then self:Row("HEADING", MS.L.JOURNEY_MAP_ZONES) end
	for index = 1, math.min(#children, 24) do
		local child = children[index]
		local count = 0
		for _, quest in ipairs(quests.active or {}) do
			if quest.mapID and QuestData:DescendsFrom(quest.mapID, child.mapID) then count = count + 1 end
		end
		local title = count > 0 and string.format(MS.L[count == 1 and "JOURNEY_MAP_ZONE_QUEST_COUNT_ONE" or "JOURNEY_MAP_ZONE_QUEST_COUNT"], child.name, count) or child.name
		-- Memory lookup only; a visited place simply carries a quiet reminder.
		local visited = MS.JourneyMemory and MS.JourneyMemory:GetZone(child.mapID) and MS.L.JOURNEY_MAP_ZONE_VISITED or nil
		local progress = MS.JourneyQuestieGuide and MS.JourneyQuestieGuide:ProgressLabel(child.mapID)
		if progress then visited = visited and (visited .. "  ·  " .. progress) or progress end
		self:Row("ZONE", title, visited, function() Map:Navigate(child.mapID) end)
	end
	end
	self.scrollChild:SetHeight(math.max(1, self.rowY))
	self.scroll:SetVerticalScroll(
		mapChanged and 0 or math.min(previousScroll, math.max(0, self.rowY - self.scroll:GetHeight()))
	)
    local selected = MS.JourneyContextPanel and MS.JourneyContextPanel.selectedContext
    if selected and selected.type == "QUEST" then self:RevealQuestRow(selected.questID) end
	self.status.offRegionQuests = #(quests.elsewhere or {})
	self.status.hereQuests = #(quests.here or {})
	self.status.unlocatedQuests = #(quests.unlocated or {})
	self.status.ambiguousQuests = #(quests.ambiguous or {})
	self.status.childCount = #(self.children or {})
end

function Map:SelectQuest(quest)
	if MS.JourneyContextPanel then MS.JourneyContextPanel:SelectQuest(quest) end
    self:RevealQuestRow(quest.questID)
    if MS.JourneyMapCanvas then MS.JourneyMapCanvas:Ping(quest.questID) end
end

function Map:OpenQuestMenu(quest, where)
	if not quest or quest.journeyOffer or not MS.JourneyQuestActions then return false end
	-- Nothing to offer here: the right-click stays without effect, as before.
	if #MS.JourneyQuestActions:Collect(quest, "CONTEXT_MENU") == 0 then return false end
	self:SelectQuest(quest)
	return MS.JourneyQuestActions:OpenMenu(quest, where)
end

function Map:RefreshSelection()
    self:LayoutRightColumn()
	local context = MS.JourneyContextPanel and MS.JourneyContextPanel.selectedContext
	local selectedQuestID = context and context.type == "QUEST" and context.questID
	if self.detailPanel then self.detailPanel:SetShown(self.active and context and context.type ~= "EMPTY") end
	if self.closeNote then self.closeNote:SetShown(context and context.type == "QUEST") end
	for _, button in ipairs(self.questButtons) do
		local selected = button.pinVisible and button.questID == selectedQuestID
        button.glow:SetShown(selected or button.hovered == true or button.pinVisible and button.questID == self.hoveredQuestID)
        button.glow:SetAlpha(selected and .38 or .17)
		button.selectedQuestID = selected and button.questID or nil
		button:SetFrameLevel(self.canvas:GetFrameLevel() + (selected and 7 or button.baseLevel or 3))
	end
	for _, row in ipairs(self.rows) do
		local selected = row.questID ~= nil and row.questID == selectedQuestID
		Style:DarkSelection(row.selection, row.selectedRule, row.questID and row.title or nil, row.questID and row.subtitle or nil, selected)
        row.hover:SetShown(row.questID ~= nil and row.questID == self.hoveredQuestID)
	end
end

function Map:UpdateProgressBars()
	local show = MS.JourneySettings:Get("showQuestProgressBars") ~= false
	for _, button in ipairs(self.questButtons) do
		button.progressBackground:SetShown(show and type(button.percent) == "number" and button.percent > 0)
		button.progress:SetShown(show and type(button.percent) == "number" and button.percent > 0)
	end
	self.status.progressOverlay = show
end

function Map:RenderQuests()
	PinAssets:Resolve()
	for _, button in ipairs(self.questButtons) do
		button.pinVisible = false
		button.hovered = false
		button:Hide()
	end
	local pins = self.quests and self.quests.pins or {}
	local counts = { AVAILABLE = 0, IN_PROGRESS = 0, READY_TO_TURN_IN = 0, UNKNOWN = 0 }
	self.status.questPinRenderer = "NONE"
	local glowAsset = PinAssets.assets.SELECTED_GLOW
	local nativeGlow = glowAsset and glowAsset.type == "ATLAS"
	self.status.selectedPinGlow = nativeGlow and "NATIVE_ATLAS" or "JOURNEY_HALO"
	local width, height = self.canvas:GetWidth(), self.canvas:GetHeight()
	for index = 1, #pins do
		local pin = pins[index]
		local button = self.questButtons[index]
		if not button then
			button = CreateFrame("Button", nil, self.canvas)
			button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			button:SetSize(36, 36)
			button:SetFrameLevel(self.canvas:GetFrameLevel() + 2)
			button.glow = button:CreateTexture(nil, "BORDER")
			button.glow:SetPoint("CENTER", button, "CENTER")
			button.glow:SetSize(54, 54)
			button.glow:SetBlendMode("ADD")
			button.glow:SetAlpha(.38)
			button.glow:Hide()
			button.background = Paint(button, "BACKGROUND", C.ink)
			button.icon = button:CreateTexture(nil, "ARTWORK")
			button.icon:SetPoint("CENTER", button, "CENTER", 0, 1)
			button.icon:SetSize(27, 27)
			button.progressBackground = button:CreateTexture(nil, "ARTWORK")
			button.progressBackground:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 5, 0)
			button.progressBackground:SetSize(26, 5)
			button.progressBackground:SetColorTexture(0.08, 0.06, 0.04, 0.82)
			button.progress = button:CreateTexture(nil, "OVERLAY")
			button.progress:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 5, 0)
			button.progress:SetHeight(5)
			self.questButtons[index] = button
		end
		button:ClearAllPoints()
		button:SetPoint("CENTER", self.canvas, "TOPLEFT", pin.x * width, -pin.y * height)
		if nativeGlow and type(button.glow.SetAtlas) == "function" then
			local ok = pcall(button.glow.SetAtlas, button.glow, glowAsset.value, false)
			if not ok then
				button.glow:SetTexture("Interface\\AddOns\\" .. (MS.addonName or "Hearthside") .. "\\Media\\JourneySelectedHalo.tga")
				self.status.selectedPinGlow = "JOURNEY_HALO"
			end
		else
			button.glow:SetTexture("Interface\\AddOns\\" .. (MS.addonName or "Hearthside") .. "\\Media\\JourneySelectedHalo.tga")
		end
		local progress = pin.quest and pin.quest.progress
		local visual = pin.state == "IN_PROGRESS"
				and progress
				and progress.totalObjectives > 0
				and progress.completedObjectives == progress.totalObjectives
				and "COMPLETE_OBJECTIVES"
			or pin.state
		local style = Style.questStates[visual] or Style.questStates.UNKNOWN
		local renderer = Style:QuestStateGlyph(button.icon, pin.state, style.color)
		local baseAsset = PinAssets.assets.IN_PROGRESS_BASE
		local nativeBase = pin.state == "IN_PROGRESS"
			and baseAsset
			and baseAsset.type == "ATLAS"
			and type(button.background.SetAtlas) == "function"
		if nativeBase then
			local ok = pcall(button.background.SetAtlas, button.background, baseAsset.value, false)
			button.background:SetAlpha(ok and 1 or 0)
			button.icon:SetSize(25, 25)
		else
			button.background:SetColorTexture(unpack(C.ink))
			button.background:SetAlpha(renderer == "JOURNEY_TEXTURE_FALLBACK" and 0.85 or 0)
			button.icon:SetSize(pin.state == "READY_TO_TURN_IN" and 30 or pin.state == "AVAILABLE" and 28 or 25,
				pin.state == "READY_TO_TURN_IN" and 30 or pin.state == "AVAILABLE" and 28 or 25)
		end
		local percent = pin.state == "IN_PROGRESS" and progress and progress.percent
		button.percent = percent
		local show = MS.JourneySettings:Get("showQuestProgressBars") ~= false
		button.progressBackground:SetShown(show and type(percent) == "number" and percent > 0)
		button.progress:SetShown(show and type(percent) == "number" and percent > 0)
		if type(percent) == "number" then
			button.progress:SetWidth(math.max(1, 26 * math.max(0, math.min(100, percent)) / 100))
			button.progress:SetColorTexture(unpack(C.gold))
		end
		local selected = pin.quest
			or {
				questID = pin.questID,
				title = MS.L.JOURNEY_QUEST_DETAILS,
				state = pin.state,
				mapName = self.status.mapName,
				mapID = self.mapID,
			}
		button.questID = selected.questID
		button.baseLevel = pin.state == "READY_TO_TURN_IN" and 5 or pin.state == "AVAILABLE" and 4 or 3
		button:SetFrameLevel(self.canvas:GetFrameLevel() + button.baseLevel)
		button.hovered = false
		button:SetScript("OnClick", function(_, mouseButton)
			if mouseButton == "RightButton" then Map:OpenQuestMenu(selected, "MAP_PIN") else Map:SelectQuest(selected) end
		end)
		button:SetScript("OnEnter", function(frame)
			frame.hovered = true
            Map:HoverQuest(frame.questID)
			local tooltip = MS.TooltipBridge:PrepareWorkspaceTooltip(frame)
			if tooltip then
				tooltip:SetText(selected.title or MS.L.JOURNEY_QUEST_DETAILS)
				tooltip:AddLine(Map:StateLabel(selected.state), 1, .83, .53)
				if type(percent) == "number" then tooltip:AddLine(string.format(MS.L.JOURNEY_CONTEXT_PERCENT, math.floor(percent + .5))) end
				tooltip:Show()
			end
		end)
		button:SetScript("OnLeave", function(frame)
			frame.hovered = false
            Map:HoverQuest(nil)
			local tooltip = MS.TooltipBridge:GetWorkspaceTooltip()
			if tooltip then tooltip:Hide() end
		end)
		button.pinVisible = true
		button:Show()
		if self.status.questPinRenderer == "NONE" then
			self.status.questPinRenderer = renderer
		elseif self.status.questPinRenderer ~= renderer then
			self.status.questPinRenderer = "MIXED"
		end
		counts[pin.state] = (counts[pin.state] or 0) + 1
	end
	self.status.questPins = #pins
	self.status.visibleJourneyPins = #pins
	self.status.journeyRenderedQuestPins = #pins
	self.status.availablePins = counts.AVAILABLE
	self.status.progressPins = counts.IN_PROGRESS
	self.status.turnInPins = counts.READY_TO_TURN_IN
	self.status.unknownPins = counts.UNKNOWN
	self.status.questPinStates = string.format(
		"AVAILABLE:%d,IN_PROGRESS:%d,READY_TO_TURN_IN:%d,UNKNOWN:%d",
		counts.AVAILABLE,
		counts.IN_PROGRESS,
		counts.READY_TO_TURN_IN,
		counts.UNKNOWN
	)
	self.status.questSource = self.quests and self.quests.source or "NONE"
	self.status.progressOverlay = MS.JourneySettings:Get("showQuestProgressBars") ~= false
	self.status.questFallback = self.quests
			and self.quests.stateCounts
			and (self.quests.stateCounts.READY_TO_TURN_IN or 0) > counts.READY_TO_TURN_IN
			and "READY_QUEST_LOCATION_UNVERIFIED"
		or "NONE"
	self:RefreshSelection()
end

function Map:RefreshQuests()
	if not self.mapID then
		return
	end
	local ok, quests = pcall(QuestData.Collect, QuestData, self.mapID)
	if not ok then
		self.status.error = SafeShort(quests, 160)
		return
	end
	self.dirty = false
	self.questModelRefreshCount = (self.questModelRefreshCount or 0) + 1
	self.quests = quests
	if MS.JourneyContextPanel then MS.JourneyContextPanel:Sync(quests, Data:Info(self.mapID)) end
	local states, diagnostic = quests.stateCounts or {}, quests.diagnostic or {}
	local index = quests.index or {}
	for _, name in ipairs({
		"status",
		"mapsScanned",
		"legacyMapsScanned",
		"iconCalls",
		"questMatches",
		"coordinateMatches",
		"headerMatches",
		"ambiguous",
		"unknown",
		"originalPoiMap",
		"restoredPoiMap",
		"poiStateRestored",
		"lastBuildReason",
		"lastError",
		"legacyShape",
		"iconShape",
		"mapListShape",
		"legacyEntryShape",
		"iconReturnShape",
	}) do
		self.status["questMapIndex." .. name] = index[name]
	end
	self.status.visibleQuestSource = diagnostic.visibleQuestSource
	self.status.visibleMapQuestStatus = diagnostic.visibleMapQuestStatus
	self.status.visibleMapQuestEntries = diagnostic.visibleMapQuestEntries or 0
	self.status.nativeMapQuestEntries = self.status.visibleMapQuestEntries
	for _, name in ipairs({ "nativeCount", "legacyCount", "headerCount" }) do
		self.status["sourceSelection." .. name] = (diagnostic.sourceSelection or {})[name] or 0
	end
	local update = index.legacyUpdate or {}
	local function IconSnapshot(value)
		if not value then
			return "NOT_PROBED"
		end
		return string.format(
			"ok=%s,completed=%s,x=%s,y=%s,objective=%s",
			tostring(value.ok),
			tostring(value.completed),
			tostring(value.x),
			tostring(value.y),
			tostring(value.objective)
		)
	end
	self.status["legacyUpdate.available"] = index.legacyUpdateAvailable == true
	self.status["legacyUpdate.changed"] = update.changed
	self.status["legacyUpdate.status"] = update.status or "NOT_PROBED"
	self.status["legacyUpdate.questID"] = update.questID
	self.status["legacyUpdate.mapID"] = update.mapID
	self.status["legacyUpdate.before"] = IconSnapshot(update.before)
	self.status["legacyUpdate.after"] = IconSnapshot(update.after)
	self.status.legacyBeforeUpdate = self.status["legacyUpdate.before"]
	self.status.legacyAfterUpdate = self.status["legacyUpdate.after"]
	self.status.legacyUpdateChanged = update.changed
	self.status.poiStateRestored = index.poiStateRestored
	self.status.nativeExclusions = diagnostic.nativeExclusions or {}
	self.status.sourceComparison = {}
	local function Coordinates(value)
		if type(value) ~= "table" then
			return "none"
		end
		return tostring(value.x) .. "/" .. tostring(value.y)
	end
	for i, example in ipairs(diagnostic.sourceComparison or {}) do
		local native = type(example.nativeMap) == "table" and example.nativeMap or {}
		local selected = example.selected or {}
		self.status.sourceComparison[i] = string.format(
			"questID=%s,state=%s,mapID=%s,nativeXY=%s,nativeEntryMapID=%s,inProgress=%s,isQuestStart=%s,isMapIndicatorQuest=%s,numObjectives=%s,legacyXY=%s,legacy.available=%s,selectedXY=%s,selectedSource=%s,pinType=%s,exclusion=%s",
			tostring(example.questID),
			tostring(example.state),
			tostring(example.mapID),
			Coordinates(example.nativeMap),
			tostring(native.mapID),
			tostring(native.inProgress),
			tostring(native.isQuestStart),
			tostring(native.isMapIndicatorQuest),
			tostring(native.numObjectives),
			Coordinates(example.legacy),
			tostring(example.legacyAvailable),
			Coordinates(example.selected),
			tostring(selected.source or "NONE"),
			tostring(selected.pinType or "NONE"),
			tostring(example.exclusion or "NONE")
		)
	end
	for _, relation in ipairs({ "HERE", "OFF_REGION", "AMBIGUOUS", "UNKNOWN" }) do
		self.status["questDisplayRelation." .. relation] = (diagnostic.questDisplayRelation or {})[relation] or 0
	end
	local confidence = diagnostic.confidenceCounts or {}
	self.status.questLocationConfidence = string.format(
		"HIGH:%d,MEDIUM:%d,UNKNOWN:%d,AMBIGUOUS:%d",
		confidence.HIGH or 0,
		confidence.MEDIUM or 0,
		confidence.UNKNOWN or 0,
		confidence.AMBIGUOUS or 0
	)
	self.status.availableQuests = states.AVAILABLE or 0
	self.status.inProgressQuests = states.IN_PROGRESS or 0
	self.status.readyToTurnInQuests = states.READY_TO_TURN_IN or 0
	self.status.unknownStateQuests = states.UNKNOWN or 0
	self.status.questLocationSources = diagnostic.locationSources or "NONE"
	self.status.questStateSources = diagnostic.stateSources or "NONE"
	self.status.questProgressSupported = diagnostic.questProgressSupported or "UNAVAILABLE"
	self.status.questsWithProgress = diagnostic.questsWithProgress or 0
	self.status.questProgressExample = diagnostic.questProgressExample or "NONE"
	self.status.waypointShape = diagnostic.shapes and diagnostic.shapes.GetNextWaypoint or "UNAVAILABLE"
	self.status.waypointForMapShape = diagnostic.shapes and diagnostic.shapes.GetNextWaypointForMap or "UNAVAILABLE"
	self.status.taskLocationShape = diagnostic.shapes and diagnostic.shapes.GetQuestLocation or "UNAVAILABLE"
	self.status.taskZoneShape = diagnostic.shapes and diagnostic.shapes.GetQuestZoneID or "UNAVAILABLE"
	self.status.readyForTurnInShape = diagnostic.shapes and diagnostic.shapes.ReadyForTurnIn or "UNAVAILABLE"
	self.status.isCompleteShape = diagnostic.shapes and diagnostic.shapes.IsComplete or "UNAVAILABLE"
	self.status.questUiMapShape = diagnostic.shapes and diagnostic.shapes.GetQuestUiMapID or "UNAVAILABLE"
	self.status.objectiveShape = diagnostic.objectiveShape or "UNAVAILABLE"
	self.status.questPOIMapID = index.originalPoiMap
	self.status.questDataErrors = diagnostic.errors
			and #diagnostic.errors > 0
			and table.concat(diagnostic.errors, " | ")
		or "NONE"
	self.status.questExamples = {}
	for index, quest in ipairs(quests.examples or {}) do
		local progress = quest.progress or {}
		self.status.questExamples[index] = string.format(
			"%s,%s,%s,%s,%s,%s,%s,indicator=%s/%s,objectives=%s,turnIn=%s,header=%s,progress=%s/%s(%s),pin=%s,globalLocation=%s,displayRelation=%s,displayedMapMatch=%s,displayLocation=%s",
			tostring(quest.questID or "?"),
			SafeShort(quest.title, 35),
			quest.state or "UNKNOWN",
			tostring(quest.questMapID or "none"),
			SafeShort(quest.mapName, 24),
			quest.locationSource or "UNKNOWN",
			quest.locationConfidence or "UNKNOWN",
			tostring(quest.mapIndicatorX or "nil"),
			tostring(quest.mapIndicatorY or "nil"),
			tostring(#(quest.objectivePOIs or {})),
			quest.turnInPOI and string.format("%.3f/%.3f", quest.turnInPOI.x, quest.turnInPOI.y) or "none",
			SafeShort(quest.headerName or "none", 24),
			tostring(progress.completedObjectives or 0),
			tostring(progress.totalObjectives or 0),
			progress.percent and string.format("%.0f", progress.percent) or "none",
			quest.state == "READY_TO_TURN_IN" and (quest.turnInPOI and "READY_TURNIN" or "NONE_NO_TURNIN_COORDINATE")
				or (quest.pinSource or "NONE"),
			tostring(quest.globalLocation),
			tostring(quest.displayRelation),
			tostring(quest.displayedMapMatch),
			tostring(quest.displayMapID or "none") .. ":" .. SafeShort(quest.displayMapName or "none", 24)
		)
	end
	local poiCounts = { ACTIVE_OBJECTIVE = 0, READY_TURNIN = 0, GENERIC_MAP_INDICATOR = 0 }
	for _, pin in ipairs(quests.pins or {}) do
		poiCounts[pin.role] = (poiCounts[pin.role] or 0) + 1
	end
	self.status["questPOI.source"] = quests.source
	self.status["questPOI.nativeCount"] = self.status["sourceSelection.nativeCount"]
	self.status["questPOI.activeObjectiveCount"] = poiCounts.ACTIVE_OBJECTIVE
	self.status["questPOI.turnInCount"] = poiCounts.READY_TURNIN
	self.status["questPOI.genericCount"] = poiCounts.GENERIC_MAP_INDICATOR
	self.status["GetQuestPOIs.entryShape"] = index.legacyEntryShape
	self.status["GetQuestPOIs.entries"] = index.legacyEntries
	self.status["QuestPOIGetIconInfo.shape"] = index.iconReturnShape
	self:RenderQuests()
	self:RenderSidebar()
end

function Map:CalibrateNative()
	local native = _G.WorldMapFrame
	if
		not self.active
		or not native
		or type(native.IsShown) ~= "function"
		or type(native.EnumeratePins) ~= "function"
	then
		return
	end
	local shownOK, shown = pcall(native.IsShown, native)
	if not shownOK or not shown then
		return
	end
	local mapID
	if type(native.GetMapID) == "function" then
		local mapOK, value = pcall(native.GetMapID, native)
		if mapOK then
			mapID = value
		end
	end
	if mapID ~= self.mapID then
		return
	end
	self.status["nativeCalibration.mapID"] = mapID
	local entries, scanned, matches = {}, 0, 0
	local function Asset(texture)
		if type(texture) ~= "table" and type(texture) ~= "userdata" then
			return nil
		end
		if type(texture.GetAtlas) == "function" then
			local atlas = texture:GetAtlas()
			if type(atlas) == "string" and atlas ~= "" then
				return atlas
			end
		end
		if type(texture.GetTexture) == "function" then
			local file = texture:GetTexture()
			if type(file) == "number" then
				return file
			end
		end
	end
	local ok, err = pcall(function()
		for pin in native:EnumeratePins() do
			scanned = scanned + 1
			if scanned > 128 or #entries >= 32 then
				break
			end
			local questID = type(pin.GetQuestID) == "function" and pin:GetQuestID() or pin.questID
			if type(questID) == "number" then
				local x, y
				if type(pin.GetPosition) == "function" then
					x, y = pin:GetPosition()
				end
				local texture = pin.NormalTexture
				if not texture and type(pin.GetNormalTexture) == "function" then
					texture = pin:GetNormalTexture()
				end
				local display = pin.Display
				local displayAsset = display and (Asset(display.Icon) or Asset(display.Texture) or Asset(display))
				local name = type(pin.pinTemplate) == "string" and pin.pinTemplate
					or type(pin.template) == "string" and pin.template
					or nil
				entries[#entries + 1] = {
					questID = questID,
					mapID = mapID,
					x = x,
					y = y,
					template = type(name) == "string" and string.sub(name, 1, 60) or "unknown",
					asset = Asset(texture) or "unknown",
					displayAsset = displayAsset or "unknown",
				}
				for _, journeyPin in ipairs(self.quests and self.quests.pins or {}) do
					if
						journeyPin.questID == questID
						and type(x) == "number"
						and type(y) == "number"
						and math.abs(journeyPin.x - x) < 0.01
						and math.abs(journeyPin.y - y) < 0.01
					then
						matches = matches + 1
						break
					end
				end
			end
		end
	end)
	self.status["nativeCalibration.available"] = ok
	self.status["nativeCalibration.pinCount"] = #entries
	self.status["nativeCalibration.matches"] = matches
	self.status["nativeCalibration.scanned"] = scanned
	self.status["nativeCalibration.error"] = ok and "none" or SafeShort(err, 120)
	self.status["nativeCalibration.examples"] = {}
	for i = 1, math.min(8, #entries) do
		local entry = entries[i]
		self.status["nativeCalibration.examples"][i] = string.format(
			"%s@%s:%.3f,%.3f:%s:base=%s:display=%s",
			tostring(entry.questID),
			tostring(entry.mapID),
			tonumber(entry.x) or -1,
			tonumber(entry.y) or -1,
			tostring(entry.template),
			tostring(entry.asset),
			tostring(entry.displayAsset)
		)
	end
end

function Map:UpdatePlayer()
	local x, y = Data:PlayerPosition(self.mapID)
	local facing
	if type(_G.GetPlayerFacing) == "function" then
		local ok, value = pcall(GetPlayerFacing)
		if ok and type(value) == "number" then
			facing = value
		end
	end
	self.status.playerFacingSupported = type(_G.GetPlayerFacing) == "function"
	self.status.playerFacing = facing
	self.status.playerArrowRotationOffset = PLAYER_ARROW_ROTATION_OFFSET
	if facing and type(self.playerIcon.SetRotation) == "function" then
		local turn = 2 * math.pi
		self.targetAngle = facing % turn
		if self.displayAngle == nil then
			self.displayAngle = self.targetAngle
		else
			local delta = (self.targetAngle - self.displayAngle + math.pi) % turn - math.pi
			self.displayAngle = (self.displayAngle + delta * 0.8) % turn
		end
		self.status.playerTargetAngle = self.targetAngle
		local angle = self.displayAngle + PLAYER_ARROW_ROTATION_OFFSET
		local ok = pcall(self.playerIcon.SetRotation, self.playerIcon, angle)
		if ok then
			self.status.playerDisplayAngle = angle
		end
	end
	local visible = Data.Normal(x, y) and self.active and self.frame:IsVisible()
	self.playerPin:SetShown(visible == true)
	self.status.playerPin = visible == true
	self.status.playerPinCount = visible and 1 or 0
	if visible then
		self.playerPin:ClearAllPoints()
		self.playerPin:SetPoint(
			"CENTER",
			self.canvas,
			"TOPLEFT",
			x * self.canvas:GetWidth(),
			-y * self.canvas:GetHeight()
		)
		self.status.playerPosition = string.format("%.4f,%.4f", x, y)
	else
		self.status.playerPosition = "UNAVAILABLE_ON_THIS_MAP"
	end
	self:UpdateFriendPin()
end

-- The friend's pin: gold, named, only on the map the friend is on; hidden otherwise and after Clear.
function Map:UpdateFriendPin()
	if not self.friendPin then return end
	local Band = MS.JourneyMentorBand
	local mapID, x, y
	if Band and Band:IsActive() then mapID, x, y = Band:FriendPosition() end
	-- Streamer mode: where a friend stands is theirs to share, so the pin stays hidden.
	local broadcast = MS.BroadcastMode ~= nil and MS.BroadcastMode:IsOn()
	local visible = not broadcast and mapID ~= nil and mapID == self.mapID and Data.Normal(x, y) and self.active
		and self.frame:IsVisible()
	self.friendPin:SetShown(visible == true)
	if not visible then return end
	if not self.friendPinRenderer then
		self.friendPinRenderer = PinAssets:Apply(self.friendIcon, "PLAYER", { 1, .82, .35 })
	end
	self.friendLabel:SetText(tostring(Band:FriendName() or ""))
	self.friendPin:ClearAllPoints()
	self.friendPin:SetPoint("CENTER", self.canvas, "TOPLEFT", x * self.canvas:GetWidth(), -y * self.canvas:GetHeight())
end

function Map:StopTicker()
	if self.ticker then
		pcall(self.ticker.Cancel, self.ticker)
		self.ticker = nil
	end
	self.status.playerTicker = false
end

function Map:StartTicker()
	self:StopTicker()
	if not self.active or not self.mapID or not self.frame:IsVisible() then
		return
	end
	if not (_G.C_Timer and type(C_Timer.NewTicker) == "function") then
		return
	end
	local ok, ticker = pcall(C_Timer.NewTicker, self.playerTickerInterval, function()
		if Map.active and Map.frame:IsVisible() then
			Map:UpdatePlayer()
		else
			Map:StopTicker()
		end
	end)
	if ok then
		self.ticker = ticker
	else
		self.status.error = SafeShort(ticker, 160)
	end
	self.status.playerTicker = self.ticker ~= nil
end

function Map:SetMapID(mapID, reason)
	local info = Data:Info(mapID)
	if not info then
		self.status.error = "MAP_INFO_UNAVAILABLE"
		return nil
	end
	local changed = self.mapID ~= info.mapID
	if changed then
		local counter = self.mode == "FOLLOW_PLAYER" and "autoMapChanges" or "manualMapChanges"
		self.status[counter] = (self.status[counter] or 0) + 1
	end
	if self.mode == "FOLLOW_PLAYER" and (changed or not self.status.lastAutoMapChangeReason) then
		self.status.lastAutoMapChangeReason = reason
	end
	self.mapID = info.mapID
	self.savedMapID = info.mapID
	self.status.displayedMapID = info.mapID
	self.art = Data:Art(mapID)
	self.chain = Data:Hierarchy(mapID)
	self.children = Data:Children(mapID)
	self.status.mapID, self.status.mapName = mapID, info.name
	self.status.mapType = info.mapType
	self.status.mode = self.mode
	self.status.followPlayer = self.mode == "FOLLOW_PLAYER"
	self.status.navigation = #self.chain > 0 and "HIERARCHY_AND_CHILD_LIST" or "UNAVAILABLE"
	self.status.error = nil
	self:SaveState()
	self:LayoutCanvas()
	self:RenderArt()
	if MS.JourneyMapCanvas then MS.JourneyMapCanvas:Sync(info.mapID) end
	self:RefreshBreadcrumb()
	if self.active then self:RefreshQuests() else self.dirty = true end
	self:UpdatePlayer()
	if self.active and not self.ticker then
		self:StartTicker()
	end
	return true
end

function Map:SetMode(mode)
	self.mode = mode
	self.status.mode, self.status.followPlayer = mode, mode == "FOLLOW_PLAYER"
end

function Map:ResolvePlayerJourneyMap()
	local resolved = Data:ResolvePlayerJourneyMap()
	self.status.rawPlayerMapID = resolved.rawPlayerMapID
	self.status.rawPlayerMapName = resolved.rawPlayerMapName
	self.status.canonicalPlayerMapID = resolved.canonicalJourneyMapID
	self.status.canonicalPlayerMapName = resolved.canonicalJourneyMapName
	return resolved.canonicalJourneyMapID
end

function Map:BeginActivation(reason)
	self.activationStarted = true
	if MS.JourneyContextPanel then MS.JourneyContextPanel.refreshCount = 0; MS.JourneyContextPanel.lastMapID = nil; MS.JourneyContextPanel:Clear() end
	self.questModelRefreshCount, self.dirty = 0, true
	self:SetMode("FOLLOW_PLAYER")
	self.displayAngle, self.targetAngle = nil, nil
	self.status.autoMapChanges, self.status.manualMapChanges = 0, 0
	self.status.lastAutoMapChangeReason = nil
	self.status.blizzardModule = Data:EnsureMapAPI()
	if MS.JourneySettings:Get("followPlayerOnStart") == false then
		self:SetMode("MANUAL_MAP")
		local mapID = self.savedMapID
		local art = mapID and Data:Info(mapID) and Data:Art(mapID)
		local usable = false
		for _, file in ipairs(art and art.textures or {}) do
			if (type(file) == "number" and file > 0) or (type(file) == "string" and file ~= "") then usable = true; break end
		end
		if not usable then mapID = self:ResolvePlayerJourneyMap() end
		if not mapID or not self:SetMapID(mapID, "MANUAL_START") then self:ClearMap() end
		return
	end
	if not self:FollowPlayerMap(reason or "JOURNEY_ENABLE", true) then
		self:ClearMap()
	end
end

function Map:FollowPlayerMap(reason, force)
	local id = self:ResolvePlayerJourneyMap()
	if not id then
		self.status.error = "PLAYER_MAP_UNAVAILABLE"
		return nil
	end
	if force or id ~= self.mapID then
		return self:SetMapID(id, reason)
	end
	if QuestData.indexDirty then
		self:RefreshQuests()
	end
	self:RefreshExploration()
	self:UpdatePlayer()
	self.status.error = nil
	return true
end

function Map:Navigate(mapID)
	if not Data:Info(mapID) then
		return nil
	end
	self:SetMode("MANUAL_MAP")
	return self:SetMapID(mapID, "MANUAL_NAVIGATION")
end

function Map:GoToParent()
	local info = Data:Info(self.mapID)
	if info and type(info.parentMapID) == "number" and info.parentMapID > 0 then
		return self:Navigate(info.parentMapID)
	end
end

function Map:GoToPlayer()
	self:SetMode("FOLLOW_PLAYER")
	local result = self:FollowPlayerMap("MY_POSITION", true)
	if result then
		self.scroll:SetVerticalScroll(0)
	end
	self:SaveState()
	return result
end

function Map:NavigateAtCursor()
	if type(_G.GetCursorPosition) ~= "function" or not self.mapID then
		return
	end
	if not (_G.C_Map and type(C_Map.GetMapInfoAtPosition) == "function") then
		return
	end
	local x, y = GetCursorPosition()
	local scale = self.canvas:GetEffectiveScale()
	local left, top = self.canvas:GetLeft(), self.canvas:GetTop()
	local width, height = self.canvas:GetWidth(), self.canvas:GetHeight()
	if
		type(x) ~= "number"
		or type(y) ~= "number"
		or type(scale) ~= "number"
		or scale <= 0
		or type(left) ~= "number"
		or type(top) ~= "number"
		or width <= 0
		or height <= 0
	then
		return
	end
	local nx, ny = (x / scale - left) / width, (top - y / scale) / height
	if not Data.Normal(nx, ny) then
		return
	end
	local ok, info = pcall(C_Map.GetMapInfoAtPosition, self.mapID, nx, ny)
	if ok and type(info) == "table" and type(info.mapID) == "number" and info.mapID ~= self.mapID then
		return self:Navigate(info.mapID)
	end
end

function Map:ClearMap()
	self.mapID = nil
	if MS.JourneyContextPanel then MS.JourneyContextPanel:Clear() end
	self.status.mapID = "UNAVAILABLE"
	self.status.displayedMapID = nil
	self.status.mapName = nil
	self.art, self.chain, self.children = nil, {}, {}
	self.quests = { here = {}, elsewhere = {}, unlocated = {}, pins = {}, stateCounts = {}, source = "NONE" }
	for _, key in ipairs({
		"availableQuests",
		"inProgressQuests",
		"readyToTurnInQuests",
		"unknownStateQuests",
		"questsWithProgress",
	}) do
		self.status[key] = 0
	end
	self.status.questExamples = {}
	self.status.sourceComparison, self.status.nativeExclusions = {}, {}
	self.status.visibleMapQuestEntries, self.status.nativeMapQuestEntries = 0, 0
	self.status.visibleMapQuestStatus = "UNAVAILABLE"
	for _, name in ipairs({ "nativeCount", "legacyCount", "headerCount" }) do
		self.status["sourceSelection." .. name] = 0
	end
	for _, relation in ipairs({ "HERE", "OFF_REGION", "AMBIGUOUS", "UNKNOWN" }) do
		self.status["questDisplayRelation." .. relation] = 0
	end
	self:RenderArt()
	if MS.JourneyMapCanvas then MS.JourneyMapCanvas:Sync(nil) end
	self:RefreshBreadcrumb()
	self:RenderQuests()
	self:RenderSidebar()
	self.status.support = "UNAVAILABLE"
	self.status.error = self.status.error or "PLAYER_MAP_UNAVAILABLE"
end

function Map:Show()
	if not self.frame then
		return nil
	end
	self.active = true
	if MS.JourneyContextPanel then MS.JourneyContextPanel:SetVisible(false) end
	self.status.error = nil
	self.status.blizzardModule = Data:EnsureMapAPI()
	PinAssets:Resolve()
	for key, kind in pairs({
		available = "AVAILABLE",
		inProgress = "IN_PROGRESS",
		inProgressBase = "IN_PROGRESS_BASE",
		ready = "READY_TO_TURN_IN",
		player = "PLAYER",
	}) do
		local asset = PinAssets.assets[kind] or {}
		for _, field in ipairs({ "type", "value", "source", "validated" }) do
			self.status["pinAssets." .. key .. "." .. field] = asset[field]
		end
	end
	self.status.unicodePinGlyphs = false
	self.status.playerPinRenderer = PinAssets:Apply(self.playerIcon, "PLAYER", { 0.35, 0.88, 1 })
	self.status.playerFallbackVisible = self.status.playerPinRenderer == "JOURNEY_TEXTURE_FALLBACK"
	self.status.playerPinBackgroundVisible = false
	self.status.pinRenderer = "NATIVE_ATLAS_FILE_ID_OR_JOURNEY_TEXTURE"
	local native = _G.WorldMapFrame
	if MS.WorldMapGameBridge and MS.WorldMapGameBridge.forensicsEnabled
		and native and type(native.HookScript) == "function" and not self.nativeHooked then
		local hooked = pcall(native.HookScript, native, "OnShow", function()
			if Map.active and _G.C_Timer and type(C_Timer.After) == "function" then
				C_Timer.After(0, function()
					if not Map.active then return end
					local ok, err = pcall(Map.CalibrateNative, Map)
					if not ok then
						Map.status["nativeCalibration.error"] = SafeShort(err, 120)
					end
				end)
			end
		end)
		self.nativeHooked = hooked
	end
	if native and type(native.IsShown) == "function" then
		local ok, shown = pcall(native.IsShown, native)
		self.status.nativeWorldMapShownAtOpen = ok and shown == true or false
	else
		self.status.nativeWorldMapShownAtOpen = false
	end
	for _, event in ipairs({
		"PLAYER_ENTERING_WORLD",
		"PLAYER_REGEN_ENABLED",
		"ZONE_CHANGED",
		"ZONE_CHANGED_NEW_AREA",
		"ZONE_CHANGED_INDOORS",
		"MAP_EXPLORATION_UPDATED",
		"QUEST_LOG_UPDATE",
		"QUEST_ACCEPTED",
		"QUEST_REMOVED",
		"QUEST_TURNED_IN",
	}) do
		pcall(self.eventFrame.RegisterEvent, self.eventFrame, event)
	end
	local navigated
	if not self.activationStarted then
		self:BeginActivation("INITIALIZE")
		navigated = self.mapID ~= nil
	elseif self.mode == "FOLLOW_PLAYER" then
		navigated = self:FollowPlayerMap("MAP_SHOWN", true)
	else
		self:ResolvePlayerJourneyMap()
		navigated = self:SetMapID(self.mapID, "MAP_SHOWN")
	end
	if not navigated then
		self:ClearMap()
	end
	if MS.JourneyContextPanel then MS.JourneyContextPanel:SetVisible(true) end
	self.frame:Show()
	self:UpdatePlayer()
	self.status.view = "VISIBLE"
	self.status.supported = self:IsSupported()
	self:StartTicker()
	return true
end

function Map:Hide()
	self.active = false
	if MS.JourneyContextPanel then MS.JourneyContextPanel:SetVisible(false) end
	self.status.view = "HIDDEN"
	self.status.playerPin = false
	self.status.playerPinCount = 0
	self:StopTicker()
	if self.eventFrame then
		self.eventFrame:UnregisterAllEvents()
	end
	if self.frame then
		self.frame:Hide()
	end
end

function Map:Restore()
	self:Hide()
	self.activationStarted = nil
	return true
end

function Map:IsSupported()
	return type(_G.C_Map) == "table"
		and type(C_Map.GetMapInfo) == "function"
		and (
			type(C_Map.GetBestMapForUnit) == "function"
			or type(C_Map.GetMapForUnit) == "function"
			or type(_G.GetCurrentMapAreaID) == "function"
		)
end

function Map:GetStatus()
	-- /ms report reads this cache; it must not resolve APIs, frames, or quest data.
	local result = {}
	for key, value in pairs(self.status) do
		result[key] = value
	end
	result.supported = self.status.supported == true
	result.active = self.active
	result.mode = self.mode
	result.playerTicker = self.ticker ~= nil
	result.independent = true
	result.engine = "CUSTOM_C_MAP_TEXTURES"
	result.frame = "JourneyMapViewFrame"
	result.destination = "WORKSPACE"
	return result
end
