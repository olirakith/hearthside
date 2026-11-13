local MS = _G.MS

MS.JourneySettings = {
    -- Alpha text presets; the legacy journal width remains stored unchanged.
    defaults = { textScale = 1.1, sessionJournalWidth = 220, showQuestProgressBars = true, followPlayerOnStart = true, showChronicles = true, mapKeyOpensJourney = false, showTravelTrace = true, showQuestieOffers = true,
        -- One-screen window: the minimap button, and the fade while the character moves.
        showMinimapButton = true, minimapAngle = 210, fadeWhenMoving = true, movingOpacity = .4,
        -- Streamer mode (BroadcastMode): never reset with the others, a stream may be live.
        broadcastMode = false,
        -- The Contrat's live view (JourneyLiveView), for streamers only: off until asked.
        contractLive = false,
        -- Chat in Journey (JourneyChat): off by default during the beta; panel height 1-3.
        chatInJourney = false, chatHeight = 2, chatShowTime = false, chatCollapsed = false,
        -- Keep the panel's last lines across /reload, per character (JourneyChat). Off: whispers
        -- would be written to disk.
        chatKeepHistory = false,
        -- A sound when a whisper arrives (JourneyWhisperSound): 0 none, else which sound.
        chatWhisperSound = 1 },
    rules = { textScale = { min = 1.0, max = 1.2, choices = { 1.0, 1.1, 1.2 } },
        sessionJournalWidth = { min = 180, max = 320, step = 20 },
        minimapAngle = { min = 0, max = 359 },
        movingOpacity = { min = .2, max = .8, choices = { .2, .4, .6, .8 } },
        chatHeight = { min = 1, max = 3, choices = { 1, 2, 3 } },
        chatWhisperSound = { min = 0, max = 4, choices = { 0, 1, 2, 3, 4 } } },
    values = {}, listeners = {}, viewDirty = true, refreshCount = 0,
}
local Settings = MS.JourneySettings
-- Toggles owned by other modules (e.g. Community experimental): { id, label, hint, get, set }.
Settings.external = Settings.external or {}

function Settings:AddExternalToggle(spec)
    if type(spec) ~= "table" or type(spec.get) ~= "function" or type(spec.set) ~= "function" then return end
    self.external[#self.external + 1] = spec
end

function Settings:MarkExternalDirty()
    self.viewDirty = true
    self:RefreshView()
end

function Settings:Validate(key, value)
    local default, rule = self.defaults[key], self.rules[key]
    if default == nil then return nil end
    if type(default) == "boolean" then
        if type(value) == "boolean" then return value end
        return default
    end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return default end
    value = math.max(rule.min, math.min(rule.max, value))
    if rule.choices then
        local nearest = rule.choices[1]
        for _, choice in ipairs(rule.choices) do if math.abs(choice - value) < math.abs(nearest - value) then nearest = choice end end
        return nearest
    end
    return math.floor(value + .5)
end

function Settings:Initialize(db)
    db.journey = type(db.journey) == "table" and db.journey or {}
    local saved = type(db.journey.settings) == "table" and db.journey.settings or {}
    local values = {}
    for key in pairs(self.defaults) do values[key] = self:Validate(key, saved[key]) end
    db.journey.settings, self.values = values, values
    if type(db.schemaVersion) ~= "number" or db.schemaVersion ~= db.schemaVersion
        or db.schemaVersion == math.huge or db.schemaVersion < 3 then db.schemaVersion = 3 end
    self.initialized, self.viewDirty = true, true
end

-- A setting of a feature this edition leaves out reads as off (MS.Edition); the saved value stays.
local function Allowed(key)
    return not MS.Edition or MS.Edition:Allows(key)
end

function Settings:Get(key)
    if not Allowed(key) then return false end
    local value = self.values[key]
    if value == nil then return self.defaults[key] end
    return value
end

function Settings:Listen(callback)
    if type(callback) == "function" then self.listeners[#self.listeners + 1] = callback end
end

function Settings:Set(key, value)
    if self.defaults[key] == nil or not Allowed(key) then return nil end
    if not self.initialized then self:Initialize(MS.Database:Get()) end
    value = self:Validate(key, value)
    if self.values[key] == value then return true end
    self.values[key], self.viewDirty = value, true
    for _, callback in ipairs(self.listeners) do pcall(callback, key, value) end
    self:RefreshView()
    return true
end

function Settings:Reset()
    for _, key in ipairs({ "textScale", "sessionJournalWidth", "showQuestProgressBars", "followPlayerOnStart", "showChronicles", "mapKeyOpensJourney", "showTravelTrace", "showQuestieOffers",
        "showMinimapButton", "fadeWhenMoving", "movingOpacity" }) do
        self:Set(key, self.defaults[key])
    end
    return true
end

MS.JourneyUIStyle = {
	version = 2,
	sizes = { SMALL = 12, SECONDARY = 13, BODY = 14, BODY_LARGE = 15, SECTION = 15, HEADING = 16, TITLE = 18, PAGE_TITLE = 30 },
	space = { xs = 4, sm = 8, md = 14, lg = 22 },
	colors = {
		backgroundDeep = { .13, .105, .078, 1 }, backgroundPanel = { .19, .15, .108, 1 },
		backgroundRaised = { .25, .197, .137, 1 }, parchmentDark = { .34, .265, .174, 1 },
		paper = { .69, .565, .366, 1 }, paperRaised = { .78, .654, .443, 1 },
		paperInset = { .56, .449, .292, 1 }, ink = { .17, .127, .079, 1 },
		inkSecondary = { .30, .238, .15, 1 },
		borderMuted = { .48, .36, .22, .65 }, borderActive = { .76, .59, .32, .9 },
		textPrimary = { .95, .87, .68, 1 }, textSecondary = { .8, .7, .53, 1 },
		gold = { .93, .73, .39, 1 }, bronze = { .68, .47, .26, 1 },
		success = { .64, .86, .58, 1 }, warning = { .95, .72, .38, 1 },
		muted = { .58, .59, .56, 1 },
	},
	labels = setmetatable({}, { __mode = "k" }),
	questStates = {
		AVAILABLE = { color = { 0.93, 0.75, 0.33 } },
		IN_PROGRESS = { color = { 0.52, 0.79, 0.93 } },
		COMPLETE_OBJECTIVES = { color = { 0.57, 0.88, 0.67 } },
		READY_TO_TURN_IN = { color = { 0.51, 0.96, 0.57 } },
		UNKNOWN = { color = { 0.77, 0.78, 0.73 } },
	},
}
local Style = MS.JourneyUIStyle

function Style:Color(texture, token)
	local color = self.colors[token]
	if texture and color then texture:SetColorTexture(unpack(color)) end
end

function Style:Text(label, token)
	local color = self.colors[token]
	if label and color then label:SetTextColor(color[1], color[2], color[3]) end
end

function Style:ApplyAt(label, token, scale)
	if not label or not self.sizes[token] then
		return false
	end
	local path, _, flags = label:GetFont()
	if type(path) ~= "string" then
		return false
	end
	if self.headingFont and self.headingTokens[token] then path = self.headingFont end
	pcall(label.SetFont, label, path, self.sizes[token] * scale, flags)
	return true
end

function Style:Apply(label, token)
	if self:ApplyAt(label, token, Settings:Get("textScale")) then self.labels[label] = token end
end

Settings:Listen(function(key)
	if key ~= "textScale" then
		return
	end
	for label, token in pairs(Style.labels) do
		Style:Apply(label, token)
	end
end)

local function Label(parent, token, color, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    MS.JourneyUIStyle:Apply(label, token)
    MS.JourneyUIStyle:Text(label, color)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function StyleControl(button)
    local selected = button.selected == true
    local hovered = button.hovered == true
    local kind = button.kind
    if kind == "small" then return end
    MS.JourneyUIStyle:Color(button.background,
        selected and "parchmentDark" or hovered and "backgroundRaised" or "backgroundPanel")
    button.background:SetAlpha(kind == "preset" and (selected and .72 or hovered and .28 or .08)
        or kind == "toggle" and (hovered and .12 or 0)
        or kind == "link" and (hovered and .13 or 0)
        or kind == "small" and (hovered and .28 or .14) or .04)
    MS.JourneyUIStyle:Text(button.label,
        kind == "link" and (hovered and "gold" or "textSecondary")
        or selected and "gold" or "textPrimary")
    button.rule:SetShown(kind == "preset" and selected)
    if kind == "toggle" and (type(button.marker) == "table" or type(button.marker) == "userdata") then
        MS.JourneyUIStyle:Color(button.marker, selected and "backgroundRaised" or "backgroundPanel")
        button.marker:SetAlpha(1)
        button.stateLabel:SetText(selected and MS.L.JOURNEY_TOGGLE_ON or MS.L.JOURNEY_TOGGLE_OFF)
        if type(button.knob) == "table" or type(button.knob) == "userdata" then
            button.knob:ClearAllPoints()
            button.knob:SetPoint(selected and "TOPRIGHT" or "TOPLEFT", button.marker,
                selected and "TOPRIGHT" or "TOPLEFT", selected and -4 or 4, -4)
            MS.JourneyUIStyle:Color(button.marker, selected and "borderActive" or "borderMuted")
            MS.JourneyUIStyle:Color(button.knob, selected and "textPrimary" or "textSecondary")
        end
        MS.JourneyUIStyle:Text(button.stateLabel, selected and "gold" or "textSecondary")
    end
end

local function SettingsButton(parent, text, action, kind)
    local button = CreateFrame("Button", nil, parent)
    button.kind = kind
    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetAllPoints(button)
    button.rule = button:CreateTexture(nil, "ARTWORK")
    button.rule:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 8, 2)
    button.rule:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -8, 2)
    button.rule:SetHeight(2)
    MS.JourneyUIStyle:Color(button.rule, "borderActive")
    button.label = Label(button, "BODY", "textPrimary", text)
    button.label:SetPoint("CENTER", button, "CENTER")
    button:SetScript("OnClick", action)
    button:SetScript("OnEnter", function() button.hovered = true; StyleControl(button) end)
    button:SetScript("OnLeave", function() button.hovered = false; StyleControl(button) end)
    StyleControl(button)
    if kind == "small" then
        -- Action buttons share one look: framed, centred label, no preset underline.
        button.rule:Hide(); button.label:SetJustifyH("CENTER")
        MS.JourneyUIStyle:Action(button, button.label)
    end
    if kind == "link" then MS.JourneyUIStyle:Link(button, button.label) end
    return button
end

local function Toggle(parent, key, hint, label)
    local button = SettingsButton(parent, label or MS.L["JOURNEY_SETTING_" .. key], function()
        Settings:Set(key, not Settings:Get(key))
    end, "toggle")
    button.label:ClearAllPoints()
    button.label:SetPoint("TOPLEFT", button, "TOPLEFT", 70, -8)
    button.marker = button:CreateTexture(nil, "ARTWORK")
    button.marker:SetPoint("TOPLEFT", button, "TOPLEFT", 8, -8)
    button.marker:SetSize(52, 24)
    button.stateLabel = Label(button, "SMALL", "textPrimary", "")
    button.knob = button:CreateTexture(nil, "OVERLAY")
    button.knob:SetSize(16, 16)
    button.stateLabel:SetPoint("TOPLEFT", button.marker, "BOTTOMLEFT", 0, -4)
    button.hint = Label(button, "SECONDARY", "textSecondary", hint)
    button.hint:SetPoint("TOPLEFT", button, "TOPLEFT", 70, -32)
    StyleControl(button)
    return button
end

-- Lent to pieces that live on the Settings page (JourneyChatTabsEditor).
Settings.widgets = { Label = Label, Button = SettingsButton, Style = StyleControl }

function Settings:CreateView(parent)
    if self.frame then return end
    self.frame = CreateFrame("Frame", nil, parent); self.frame:Hide()
    self.scroll = CreateFrame("ScrollFrame", nil, self.frame)
    self.content = CreateFrame("Frame", nil, self.scroll); self.content:SetSize(1, 1)
    self.scroll:SetScrollChild(self.content)
    self.scroll:EnableMouseWheel(true)
    self.scroll:SetScript("OnMouseWheel", function(scroll, delta)
        local maximum = math.max(0, self.content:GetHeight() - scroll:GetHeight())
        scroll:SetVerticalScroll(math.max(0, math.min(maximum, scroll:GetVerticalScroll() - delta * 40)))
    end)
    self.page = CreateFrame("Frame", nil, self.content)
    self.pageBackground = self.page:CreateTexture(nil, "BACKGROUND")
    self.pageBackground:SetAllPoints(self.page)
    MS.JourneyUIStyle:Material(self.pageBackground, "backgroundPanel")
    -- Cards are textures under the labels, which live on the page itself.
    self.cards = {}
    for _, key in ipairs({ "interface", "behavior", "layout", "chatTabs", "support" }) do
        local edge = self.page:CreateTexture(nil, "BACKGROUND", nil, 1)
        local fill = self.page:CreateTexture(nil, "BACKGROUND", nil, 2)
        MS.JourneyUIStyle:Color(edge, "borderMuted")
        MS.JourneyUIStyle:Material(fill, "backgroundDeep")
        fill:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)
        edge.fill = fill
        self.cards[key] = edge
    end
    self.pageEdge = self.page:CreateTexture(nil, "ARTWORK")
    self.pageEdge:SetPoint("TOPLEFT", self.page, "TOPLEFT", 0, 0)
    self.pageEdge:SetPoint("BOTTOMLEFT", self.page, "BOTTOMLEFT", 0, 0)
    self.pageEdge:SetWidth(2)
    MS.JourneyUIStyle:Color(self.pageEdge, "borderActive")
    self.pageEdge:SetAlpha(.55)
    self.titleRule = self.page:CreateTexture(nil, "ARTWORK")
    self.titleRule:SetHeight(1)
    MS.JourneyUIStyle:Color(self.titleRule, "borderActive")
    self.titleRule:SetAlpha(.55)
    self.leftRule = self.page:CreateTexture(nil, "ARTWORK")
    self.leftRule:SetHeight(1)
    MS.JourneyUIStyle:Color(self.leftRule, "borderMuted")
    self.rightRule = self.page:CreateTexture(nil, "ARTWORK")
    self.rightRule:SetHeight(1)
    MS.JourneyUIStyle:Color(self.rightRule, "borderMuted")
    self.title = Label(self.page, "PAGE_TITLE", "gold", MS.L.JOURNEY_VIEW_SETTINGS)
    self.subtitle = Label(self.page, "BODY", "textSecondary", MS.L.JOURNEY_SETTINGS_SUBTITLE)
    self.headings = {
        interface = Label(self.page, "SECTION", "gold", MS.L.JOURNEY_SETTINGS_INTERFACE),
        behavior = Label(self.page, "SECTION", "gold", MS.L.JOURNEY_SETTINGS_BEHAVIOR),
        map = Label(self.page, "SECTION", "gold", MS.L.JOURNEY_SETTINGS_MAP),
        quests = Label(self.page, "SECTION", "gold", MS.L.JOURNEY_SETTINGS_QUESTS),
    }
    self.textLabel = Label(self.page, "BODY_LARGE", "textPrimary", MS.L.JOURNEY_SETTING_textScale)
    self.textHint = Label(self.page, "SECONDARY", "textSecondary", MS.L.JOURNEY_SETTINGS_TEXT_HINT)
    self.controls = { textScale = {} }
    for index, value in ipairs(self.rules.textScale.choices) do
        local caption = string.format(MS.L.JOURNEY_CONTEXT_PERCENT, math.floor(value * 100 + .5))
        local button = SettingsButton(self.page, caption, function() Settings:Set("textScale", value) end, "preset")
        button.value = value
        self.controls.textScale[index] = button
    end
    self.headings.window = Label(self.page, "SECTION", "gold", MS.L.JOURNEY_SETTINGS_WINDOW)
    self.windowHint = Label(self.page, "SECONDARY", "textSecondary", MS.L.JOURNEY_SETTINGS_WINDOW_HINT)
    self.controls.showMinimapButton = Toggle(self.page, "showMinimapButton", MS.L.JOURNEY_SETTINGS_MINIMAP_HINT)
    self.controls.fadeWhenMoving = Toggle(self.page, "fadeWhenMoving", MS.L.JOURNEY_SETTINGS_FADE_HINT)
    self.opacityLabel = Label(self.page, "BODY_LARGE", "textPrimary", MS.L.JOURNEY_SETTING_movingOpacity)
    self.controls.movingOpacity = {}
    for index, value in ipairs(self.rules.movingOpacity.choices) do
        local caption = string.format(MS.L.JOURNEY_CONTEXT_PERCENT, math.floor(value * 100 + .5))
        local button = SettingsButton(self.page, caption, function() Settings:Set("movingOpacity", value) end, "preset")
        button.value = value
        self.controls.movingOpacity[index] = button
    end
    self.headings.broadcast = Label(self.page, "SECTION", "gold", MS.L.JOURNEY_SETTINGS_BROADCAST)
    self.controls.broadcastMode = Toggle(self.page, "broadcastMode", MS.L.JOURNEY_SETTINGS_BROADCAST_HINT)
    self.controls.contractLive = Toggle(self.page, "contractLive", MS.L.JOURNEY_SETTINGS_CONTRACT_LIVE_HINT)
    self.controls.followPlayerOnStart = Toggle(self.page, "followPlayerOnStart", MS.L.JOURNEY_SETTINGS_FOLLOW_HINT)
    self.controls.showTravelTrace = Toggle(self.page, "showTravelTrace", MS.L.JOURNEY_SETTINGS_TRACE_HINT)
    self.controls.showQuestProgressBars = Toggle(self.page, "showQuestProgressBars", MS.L.JOURNEY_SETTINGS_PROGRESS_HINT)
    self.headings.features = Label(self.page, "SECTION", "gold", MS.L.JOURNEY_SETTINGS_FEATURES)
    self.controls.showChronicles = Toggle(self.page, "showChronicles", MS.L.JOURNEY_SETTINGS_CHRONICLES_HINT)
    self.headings.chat = Label(self.page, "SECTION", "gold", MS.L.JOURNEY_SETTINGS_CHAT)
    self.controls.chatInJourney = Toggle(self.page, "chatInJourney", MS.L.JOURNEY_SETTINGS_CHAT_HINT)
    self.chatHeightLabel = Label(self.page, "BODY_LARGE", "textPrimary", MS.L.JOURNEY_SETTING_chatHeight)
    self.controls.chatHeight = {}
    for index, value in ipairs(self.rules.chatHeight.choices) do
        local button = SettingsButton(self.page, MS.L["CHAT_HEIGHT_" .. value], function() Settings:Set("chatHeight", value) end, "preset")
        button.value = value
        self.controls.chatHeight[index] = button
    end
    self.chatSoundLabel = Label(self.page, "BODY_LARGE", "textPrimary", MS.L.JOURNEY_SETTING_chatWhisperSound)
    self.chatSoundHint = Label(self.page, "SECONDARY", "textSecondary", MS.L.JOURNEY_SETTINGS_CHAT_SOUND_HINT)
    self.controls.chatWhisperSound = {}
    for index, value in ipairs(self.rules.chatWhisperSound.choices) do
        -- Choosing a sound plays it: the buttons are also the way to listen.
        local button = SettingsButton(self.page, MS.L["CHAT_SOUND_" .. value], function()
            Settings:Set("chatWhisperSound", value)
            if MS.JourneyWhisperSound then MS.JourneyWhisperSound:Play(value, true) end
        end, "preset")
        button.value = value
        self.controls.chatWhisperSound[index] = button
    end
    self.controls.chatShowTime = Toggle(self.page, "chatShowTime", MS.L.JOURNEY_SETTINGS_CHAT_TIME_HINT)
    self.controls.chatKeepHistory = Toggle(self.page, "chatKeepHistory", MS.L.JOURNEY_SETTINGS_CHAT_KEEP_HINT)
    self.clearHistory = SettingsButton(self.page, MS.L.CHAT_HISTORY_CLEAR, function()
        if MS.JourneyChat then MS.JourneyChat:ClearHistory() end
    end, "small")
    if MS.JourneyChatTabsEditor then MS.JourneyChatTabsEditor:Create(self.page, self.widgets) end
    self.externalControls = {}
    for index, spec in ipairs(self.external) do
        local button = Toggle(self.page, nil, spec.hint, spec.label)
        button:SetScript("OnClick", function() spec.set(not spec.get()); Settings:MarkExternalDirty() end)
        self.externalControls[index] = button
    end
    self.headings.layout = Label(self.page, "SECTION", "gold", MS.L.JOURNEY_UI_GAME_LAYOUT)
    self.layoutHint = Label(self.page, "SECONDARY", "textSecondary", MS.L.JOURNEY_UI_GAME_LAYOUT_HINT)
    self.supportHeading = Label(self.page, "SECTION", "gold", MS.L.JOURNEY_SETTINGS_SUPPORT)
    self.supportRule = self.page:CreateTexture(nil, "ARTWORK")
    self.supportRule:SetHeight(1)
    MS.JourneyUIStyle:Color(self.supportRule, "borderMuted")
    self.reset = SettingsButton(self.page, MS.L.JOURNEY_SETTINGS_RESET, function()
        self.awaitingReset = true
        self:RefreshConfirmation()
    end, "small")
    self.resetPrompt = Label(self.page, "SECONDARY", "textSecondary", MS.L.JOURNEY_SETTINGS_RESET_CONFIRM)
    self.confirm = SettingsButton(self.page, MS.L.JOURNEY_CONFIRM, function()
        self:Reset()
        self.awaitingReset = false
        self:RefreshConfirmation()
    end, "small")
    self.cancel = SettingsButton(self.page, MS.L.JOURNEY_CANCEL, function()
        self.awaitingReset = false
        self:RefreshConfirmation()
    end, "small")
    self:RefreshConfirmation()
    self.onboardingEntry = SettingsButton(self.page, MS.L.ONBOARD_OPEN, function()
        if MS.JourneyOnboarding then MS.JourneyOnboarding:Open() end
    end, "small")
    self.diagnosticHeading = Label(self.page, "SECTION", "gold", MS.L.PLAYER_DIAG_TITLE)
    self.diagnosticStatus = Label(self.page, "BODY", "textPrimary", "")
    self.diagnosticReason = Label(self.page, "SECONDARY", "textSecondary", "")
    self.diagnosticCopy = SettingsButton(self.page, MS.L.PLAYER_DIAG_COPY, function()
        if MS.PlayerDiagnostic then MS.PlayerDiagnostic:Open() end
    end, "small")
    self.diagnosticLimitations = Label(self.page, "SECONDARY", "textSecondary",
        MS.L.PLAYER_DIAG_LIMITATIONS .. "\n" .. MS.L.PLAYER_DIAG_LIMIT_SCREEN_API .. "\n"
        .. MS.L.PLAYER_DIAG_LIMIT_COMPAT)
end

function Settings:RefreshConfirmation()
    local shown = self.awaitingReset == true
    self.resetPrompt:SetShown(shown)
    self.confirm:SetShown(shown)
    self.cancel:SetShown(shown)
end

function Settings:LayoutView(rect)
    if not self.frame then return end
    self.lastRect = rect
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    self.frame:SetSize(rect.width, rect.height)
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", self.frame, "TOPLEFT")
    self.scroll:SetSize(rect.width, rect.height)
    local contentWidth = math.max(1, rect.width - 12)
    self.content:SetWidth(contentWidth)
    local physical = MS.Workspace.physicalRect
    local wide = (physical and physical.width or rect.width) >= 1600 and rect.width >= 1050
    local pageWidth = math.max(1, math.min(contentWidth - 24,
        wide and rect.width * .74 or math.min(rect.width * .90, 980)))
    local padding, gap = 32, 48
    local innerWidth = math.max(1, pageWidth - padding * 2)
    local columnWidth = wide and (innerWidth - gap) / 2 or innerWidth
    local leftX, rightX = padding, wide and padding + columnWidth + gap or padding
    self.layoutColumns = wide and 2 or 1
    local function place(label, x, y, width)
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", self.page, "TOPLEFT", x, -y)
        label:SetWidth(width)
        return math.max(18, label:GetStringHeight())
    end
    local function rule(texture, x, y, width)
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", self.page, "TOPLEFT", x, -y)
        texture:SetWidth(width)
    end
    local function toggle(button, x, y)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", self.page, "TOPLEFT", x, -y)
        button:SetWidth(columnWidth)
        button.label:SetWidth(math.max(1, columnWidth - 78))
        button.hint:SetWidth(math.max(1, columnWidth - 78))
        local labelHeight = button.label:GetStringHeight()
        button.hint:ClearAllPoints()
        button.hint:SetPoint("TOPLEFT", button, "TOPLEFT", 70, -(16 + labelHeight))
        local height = math.max(64, 24 + labelHeight + button.hint:GetStringHeight())
        button:SetHeight(height)
        return height
    end
    local titleY = 30
    local subtitleY = titleY + place(self.title, padding, titleY, innerWidth) + 10
    local titleRuleY = subtitleY + place(self.subtitle, padding, subtitleY, innerWidth) + 24
    rule(self.titleRule, padding, titleRuleY, innerWidth)
    self:RefreshDiagnostic()
    local groupY = titleRuleY + 24
    local leftY = groupY + place(self.headings.interface, leftX, groupY, columnWidth) + 10
    rule(self.leftRule, leftX, leftY, columnWidth)
    leftY = leftY + 23
    leftY = leftY + place(self.textLabel, leftX, leftY, columnWidth) + 15
    local segmentGap = 8
    local segmentWidth = math.max(1, math.min(112, (columnWidth - segmentGap * 2) / 3))
    for index, button in ipairs(self.controls.textScale) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", self.page, "TOPLEFT",
            leftX + (index - 1) * (segmentWidth + segmentGap), -leftY)
        button:SetSize(segmentWidth, 34)
    end
    leftY = leftY + 34 + 15
    leftY = leftY + place(self.textHint, leftX, leftY, columnWidth) + 24
    leftY = leftY + place(self.headings.window, leftX, leftY, columnWidth) + 8
    leftY = leftY + place(self.windowHint, leftX, leftY, columnWidth) + 14
    leftY = leftY + toggle(self.controls.showMinimapButton, leftX, leftY) + 20
    leftY = leftY + toggle(self.controls.fadeWhenMoving, leftX, leftY) + 20
    leftY = leftY + place(self.opacityLabel, leftX, leftY, columnWidth) + 15
    local opacityWidth = math.max(1, math.min(96, (columnWidth - segmentGap * 3) / 4))
    for index, button in ipairs(self.controls.movingOpacity) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", self.page, "TOPLEFT",
            leftX + (index - 1) * (opacityWidth + segmentGap), -leftY)
        button:SetSize(opacityWidth, 34)
    end
    leftY = leftY + 34 + 24
    -- Diffusion: streamer edition only.
    local streamer = not MS.Edition or MS.Edition:Streamer()
    self.headings.broadcast:SetShown(streamer)
    self.controls.broadcastMode:SetShown(streamer)
    self.controls.contractLive:SetShown(streamer)
    if streamer then
        leftY = leftY + place(self.headings.broadcast, leftX, leftY, columnWidth) + 14
        leftY = leftY + toggle(self.controls.broadcastMode, leftX, leftY) + 20
        leftY = leftY + toggle(self.controls.contractLive, leftX, leftY) + 24
    end
    local rightY = wide and groupY or leftY + 19
    rightY = rightY + place(self.headings.behavior, rightX, rightY, columnWidth) + 10
    rule(self.rightRule, rightX, rightY, columnWidth)
    rightY = rightY + 25
    rightY = rightY + place(self.headings.map, rightX, rightY, columnWidth) + 10
    rightY = rightY + toggle(self.controls.followPlayerOnStart, rightX, rightY) + 20
    rightY = rightY + toggle(self.controls.showTravelTrace, rightX, rightY) + 24
    rightY = rightY + place(self.headings.quests, rightX, rightY, columnWidth) + 10
    rightY = rightY + toggle(self.controls.showQuestProgressBars, rightX, rightY) + 20
    rightY = rightY + place(self.headings.features, rightX, rightY, columnWidth) + 10
    if MS.Config and MS.Config.chroniclesPaused then self.controls.showChronicles:Hide()
    else rightY = rightY + toggle(self.controls.showChronicles, rightX, rightY) + 20 end
    for _, button in ipairs(self.externalControls or {}) do rightY = rightY + toggle(button, rightX, rightY) + 20 end
    rightY = rightY + 4 + place(self.headings.chat, rightX, rightY + 4, columnWidth) + 10
    rightY = rightY + toggle(self.controls.chatInJourney, rightX, rightY) + 16
    rightY = rightY + place(self.chatHeightLabel, rightX, rightY, columnWidth) + 12
    local chatWidth = math.max(1, math.min(112, (columnWidth - segmentGap * 2) / 3))
    for index, button in ipairs(self.controls.chatHeight) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", self.page, "TOPLEFT", rightX + (index - 1) * (chatWidth + segmentGap), -rightY)
        button:SetSize(chatWidth, 34)
    end
    rightY = rightY + 34 + 16
    rightY = rightY + place(self.chatSoundLabel, rightX, rightY, columnWidth) + 6
    rightY = rightY + place(self.chatSoundHint, rightX, rightY, columnWidth) + 10
    -- Five sounds: two rows of three columns.
    for index, button in ipairs(self.controls.chatWhisperSound) do
        local column, row = (index - 1) % 3, math.floor((index - 1) / 3)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", self.page, "TOPLEFT", rightX + column * (chatWidth + segmentGap), -(rightY + row * (34 + segmentGap)))
        button:SetSize(chatWidth, 34)
    end
    rightY = rightY + 34 * 2 + segmentGap + 16
    rightY = rightY + toggle(self.controls.chatShowTime, rightX, rightY) + 20
    rightY = rightY + toggle(self.controls.chatKeepHistory, rightX, rightY) + 12
    self.clearHistory:ClearAllPoints()
    self.clearHistory:SetPoint("TOPLEFT", self.page, "TOPLEFT", rightX, -rightY)
    self.clearHistory:SetSize(math.min(260, columnWidth), 30)
    rightY = rightY + 30 + 20
    local function card(key, x, top, width, bottom)
        local edge = self.cards[key]
        edge:ClearAllPoints()
        edge:SetPoint("TOPLEFT", self.page, "TOPLEFT", x - 16, -(top - 14))
        edge:SetSize(width + 32, math.max(1, bottom - top + 14))
    end
    card("interface", leftX, groupY, columnWidth, leftY - 6)
    card("behavior", rightX, wide and groupY or leftY + 19, columnWidth, rightY)
    -- On a wide page the short left column also holds the layout card, under Reading.
    local sectionY = wide and leftY + 22 or rightY + 32
    local layoutTop = sectionY
    sectionY = sectionY + place(self.headings.layout, leftX, sectionY, columnWidth) + 8
    sectionY = sectionY + place(self.layoutHint, leftX, sectionY, columnWidth) + 16
    local button = self.onboardingEntry
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", self.page, "TOPLEFT", leftX, -sectionY)
    button:SetSize(math.min(420, columnWidth), 40)
    button.label:SetWidth(math.max(1, button:GetWidth() - 16))
    sectionY = sectionY + 48
    card("layout", leftX, layoutTop, columnWidth, sectionY)
    local diagnosticY = math.max(sectionY, rightY) + 32
    -- The Discussion tabs, full width, while the chat is in Journey.
    local editor = MS.JourneyChatTabsEditor
    local tabsCard = self.cards.chatTabs
    if editor and self:Get("chatInJourney") == true then
        local tabsTop = diagnosticY
        diagnosticY = editor:Layout(padding, tabsTop, innerWidth)
        card("chatTabs", padding, tabsTop, innerWidth, diagnosticY)
        tabsCard:Show(); tabsCard.fill:Show()
        diagnosticY = diagnosticY + 32
    else
        if editor then editor:Hide() end
        tabsCard:Hide(); tabsCard.fill:Hide()
    end
    local supportTop = diagnosticY
    -- Assistance is a top-level section (gold + rule, like Lecture); Diagnostic sits inside it.
    diagnosticY = diagnosticY + place(self.supportHeading, padding, diagnosticY, innerWidth) + 10
    rule(self.supportRule, padding, diagnosticY, innerWidth)
    diagnosticY = diagnosticY + 23
    diagnosticY = diagnosticY + place(self.diagnosticHeading, padding, diagnosticY, innerWidth) + 8
    diagnosticY = diagnosticY + place(self.diagnosticStatus, padding, diagnosticY, innerWidth) + 8
    diagnosticY = diagnosticY + place(self.diagnosticReason, padding, diagnosticY, innerWidth) + 12
    self.diagnosticCopy:ClearAllPoints()
    self.diagnosticCopy:SetPoint("TOPLEFT", self.page, "TOPLEFT", padding, -diagnosticY)
    self.diagnosticCopy:SetSize(math.min(320, innerWidth), 32)
    diagnosticY = diagnosticY + 48
    local resetY = diagnosticY + place(self.diagnosticLimitations, padding, diagnosticY, innerWidth) + 32
    self.reset:ClearAllPoints()
    self.reset:SetPoint("TOPLEFT", self.page, "TOPLEFT", padding, -resetY)
    self.reset:SetSize(math.min(260, innerWidth), 32)
    local promptY = resetY + 48
    local promptHeight = place(self.resetPrompt, padding, promptY, innerWidth)
    local actionsY = promptY + promptHeight + 8
    for index, button in ipairs({ self.confirm, self.cancel }) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", self.page, "TOPLEFT", padding + (index - 1) * 120, -actionsY)
        button:SetSize(112, 32)
    end
    card("support", padding, supportTop, innerWidth, promptY + promptHeight)
    local pageHeight = actionsY + 48
    self.page:ClearAllPoints()
    local pageTop = 16
    self.page:SetPoint("TOPLEFT", self.content, "TOPLEFT", (contentWidth - pageWidth) / 2, -pageTop)
    self.page:SetSize(pageWidth, pageHeight)
    self.content:SetHeight(math.max(rect.height, pageTop + pageHeight + 16))
    local maximum = math.max(0, self.content:GetHeight() - self.scroll:GetHeight())
    self.scroll:SetVerticalScroll(math.min(maximum, self.scroll:GetVerticalScroll()))
    self.viewDirty = true
    self:RefreshView()
end

function Settings:ShowView()
    if MS.PlayerDiagnostic then MS.PlayerDiagnostic:Capture() end
    self:RefreshDiagnostic()
    self.visible = true; self.frame:Show(); self:RefreshView()
end

function Settings:RefreshDiagnostic()
    if not self.diagnosticStatus then return end
    local diagnostic = MS.PlayerDiagnostic
    self.diagnosticStatus:SetText(string.format(MS.L.PLAYER_DIAG_STATUS, diagnostic and diagnostic.status or "UNKNOWN"))
    self.diagnosticReason:SetText(diagnostic and diagnostic.reason and MS.L[diagnostic.reason] or "")
    MS.JourneyUIStyle:Text(self.diagnosticStatus, diagnostic and diagnostic.status == "OK" and "success" or "warning")
end

function Settings:HideView()
    self.visible, self.awaitingReset = false, false
    if self.frame then self.frame:Hide(); self:RefreshConfirmation() end
end

function Settings:RefreshView()
    if not self.visible or not self.frame or not self.viewDirty then return end
    for _, button in ipairs(self.controls.textScale) do
        button.selected = self:Get("textScale") == button.value
        StyleControl(button)
    end
    local fading = self:Get("fadeWhenMoving") == true
    for _, button in ipairs(self.controls.movingOpacity) do
        button.selected = self:Get("movingOpacity") == button.value
        button:SetAlpha(fading and 1 or .55)
        StyleControl(button)
    end
    self.opacityLabel:SetAlpha(fading and 1 or .55)
    local chatting = self:Get("chatInJourney") == true
    for _, button in ipairs(self.controls.chatHeight) do
        button.selected = self:Get("chatHeight") == button.value
        button:SetAlpha(chatting and 1 or .55)
        StyleControl(button)
    end
    self.chatHeightLabel:SetAlpha(chatting and 1 or .55)
    for _, button in ipairs(self.controls.chatWhisperSound) do
        button.selected = self:Get("chatWhisperSound") == button.value
        StyleControl(button)
    end
    self.clearHistory:SetAlpha(self:Get("chatKeepHistory") == true and 1 or .55)
    for _, key in ipairs({ "followPlayerOnStart", "showTravelTrace", "showQuestProgressBars", "showChronicles",
        "showMinimapButton", "fadeWhenMoving", "broadcastMode", "contractLive", "chatInJourney", "chatShowTime",
        "chatKeepHistory" }) do
        local button = self.controls[key]
        button.selected = self:Get(key) == true
        StyleControl(button)
    end
    for index, button in ipairs(self.externalControls or {}) do
        local spec = self.external[index]
        local ok, value = pcall(spec.get)
        -- blocked(): optional reason the switch cannot act now; it is shown off, greyed, explained.
        local blockedOk, blocked = true, nil
        if type(spec.blocked) == "function" then blockedOk, blocked = pcall(spec.blocked) end
        blocked = blockedOk and type(blocked) == "string" and blocked or nil
        button.selected = ok and value == true and not blocked
        button:SetEnabled(not blocked)
        button:SetAlpha(blocked and .55 or 1)
        button.hint:SetText(blocked or spec.hint or "")
        StyleControl(button)
    end
    self.viewDirty, self.refreshCount = false, self.refreshCount + 1
end
