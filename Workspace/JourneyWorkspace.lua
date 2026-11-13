local MS = _G.MS

MS.JourneyWorkspace = { active = false, view = "MAP" }
local Journey = MS.JourneyWorkspace
-- Logical px kept empty under the footer (second-screen taskbar / physical edge).
Journey.BOTTOM_SAFE_INSET = 28
local VIEWS = { "MAP", "QUESTS", "PROGRESSION", "CHRONICLES", "INVENTORY", "SETTINGS" }

local function ChronicleUI(target, method, ...)
    return target and type(target[method]) == "function"
        and pcall(target[method], target, ...) or false
end

local TAB_LEVEL = 20

function Journey:Create()
    if self.header then return end
    local parent = MS.Workspace.frame
    self.shellBackground = parent:CreateTexture(nil, "BACKGROUND")
    self.shellBackground:SetAllPoints(parent)
    MS.JourneyUIStyle:PageMaterial(self.shellBackground, "DARK")
    self.header = CreateFrame("Frame", nil, parent)
    -- Window mode only: the header is the drag handle (the mouse is enabled by JourneyWindow).
    self.header:RegisterForDrag("LeftButton")
    self.header:SetScript("OnDragStart", function()
        if MS.JourneyWindow and MS.JourneyWindow:IsOpen() then MS.JourneyWindow:StartDrag() end
    end)
    self.header:SetScript("OnDragStop", function()
        if MS.JourneyWindow then MS.JourneyWindow:StopDrag() end
    end)
    self.headerBackground = self.header:CreateTexture(nil, "BACKGROUND")
    self.headerBackground:SetAllPoints(self.header)
    MS.JourneyUIStyle:Material(self.headerBackground, "backgroundDeep")
    self.headerRule = self.header:CreateTexture(nil, "ARTWORK")
    self.headerRule:SetPoint("BOTTOMLEFT", self.header, "BOTTOMLEFT", 5, 0)
    self.headerRule:SetPoint("BOTTOMRIGHT", self.header, "BOTTOMRIGHT", -5, 0)
    self.headerRule:SetHeight(1)
    MS.JourneyUIStyle:Color(self.headerRule, "borderActive")
    self.title = self.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    MS.JourneyUIStyle:Heading(self.title, "TITLE", "gold")
    self.title:SetPoint("TOPLEFT", self.header, "TOPLEFT", 14, -10)
    MS.JourneyUIStyle:Text(self.title, "gold")
    self.title:SetJustifyH("LEFT")
    self.tabs = {}
    for index, view in ipairs(VIEWS) do
        local button = CreateFrame("Button", nil, parent)
        button:SetSize(126, 28)
        button.background = button:CreateTexture(nil, "BACKGROUND")
        button.background:SetAllPoints(button)
        MS.JourneyUIStyle:Color(button.background, "backgroundPanel")
        button.rule = button:CreateTexture(nil, "ARTWORK")
        button.rule:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 8, 2)
        button.rule:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -8, 2)
        button.rule:SetHeight(2)
        MS.JourneyUIStyle:Color(button.rule, "borderActive")
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        MS.JourneyUIStyle:Body(label, index > 4 and "SECONDARY" or "BODY", "textSecondary")
        label:SetPoint("CENTER", button, "CENTER")
        label:SetText(MS.L["JOURNEY_VIEW_" .. view])
        button.label = label
        button:SetScript("OnClick", function()
            local previous = Journey.view
            Journey:SelectView(view)
            if Journey.view ~= previous then Journey:PlayTabSound() end
        end)
        button:SetScript("OnEnter", function() button.hovered = true; Journey:StyleTabs() end)
        button:SetScript("OnLeave", function() button.hovered, button.pressed = false, false; Journey:StyleTabs() end)
        button:SetScript("OnMouseDown", function() button.pressed = true; Journey:StyleTabs() end)
        button:SetScript("OnMouseUp", function() button.pressed = false; Journey:StyleTabs() end)
        button.index = index
        button.view, button.secondary = view, view == "SETTINGS" or view == "INVENTORY"
        if view == "SETTINGS" then
            self.settingsButton = button
            MS.JourneyUIStyle:Action(button, button.label)
            local actionEnter, actionLeave = button:GetScript("OnEnter"), button:GetScript("OnLeave")
            button:SetScript("OnEnter", function()
                if type(actionEnter) == "function" then actionEnter(button) end
                button.hovered = true; Journey:StyleTabs()
                if GameTooltip and GameTooltip.SetOwner then
                    GameTooltip:SetOwner(button, "ANCHOR_TOP")
                    GameTooltip:AddLine(MS.L.JOURNEY_VIEW_SETTINGS); GameTooltip:Show()
                end
            end)
            button:SetScript("OnLeave", function()
                if type(actionLeave) == "function" then actionLeave(button) end
                button.hovered = false; Journey:StyleTabs(); if GameTooltip then GameTooltip:Hide() end
            end)
        end
        self.tabs[index] = button
    end
    -- The gold rule that travels from one tab to the next; each tab's own rule takes over after.
    self.tabSlider = self.header:CreateTexture(nil, "OVERLAY")
    self.tabSlider:SetHeight(2); MS.JourneyUIStyle:Color(self.tabSlider, "borderActive")
    self.tabSlider:Hide()
    self:CreateBroadcastBadge(parent)
    self:CreateTabMenu(parent)
    MS.SessionFeed:Create(parent)
    MS.JourneySettings:CreateView(parent)
    if MS.JourneyProgressionView then MS.JourneyProgressionView:Create(parent) end
    MS.QuestJournal:Create(parent)
    MS.MapView:Create(parent)
    MS.InventoryView:Create(parent)
    if not (MS.Config and MS.Config.chroniclesPaused) then
        self.chroniclesViewReady = ChronicleUI(MS.ChroniclesView, "Create", parent)
        self.chroniclesToastReady = ChronicleUI(MS.ChroniclesDiscoveryToast, "Create", parent)
    end
    if MS.JourneyChatView then MS.JourneyChatView:Create(parent) end
    if MS.JourneyMentorBand then MS.JourneyMentorBand:Create(parent) end
    if MS.JourneyContractBand then MS.JourneyContractBand:Create(parent) end
    if MS.JourneyLiveView then MS.JourneyLiveView:Create(parent) end
    MS.JourneyStatusBar:Create(parent)
    if not self.settingsListener then
        MS.JourneySettings:Listen(function(key)
            if not Journey.active then return end
            if key == "textScale" or key == "sessionJournalWidth" then Journey:LayoutView(Journey.view)
            elseif key == "showChronicles" then
                if not MS.JourneySettings:Get(key) and Journey.view == "CHRONICLES" then Journey:SelectView("MAP")
                else Journey:LayoutView(Journey.view) end
            elseif key == "showQuestProgressBars" and MS.MapView.active then MS.MapView:UpdateProgressBars()
            elseif key == "showTravelTrace" then MS.JourneyTrace:Draw()
            elseif key == "broadcastMode" then Journey:LayoutView(Journey.view)
            elseif key == "contractLive" then
                if not MS.JourneySettings:Get(key) and MS.JourneyLiveView then MS.JourneyLiveView:Close() end
                if MS.JourneyContractBand then MS.JourneyContractBand:ShowLive() end
            elseif key == "chatInJourney" or key == "chatHeight" or key == "chatCollapsed" then
                if MS.JourneyChatView then MS.JourneyChatView:Sync() end
                Journey:LayoutView(Journey.view)
            elseif key == "chatShowTime" and MS.JourneyChatView then MS.JourneyChatView:Redraw() end
        end)
        self.settingsListener = true
    end
end

function Journey:VisibleDestinations()
    local visible = {}
    for _, button in ipairs(self.tabs or {}) do
        if button.view ~= "SETTINGS" and button.available ~= false
            and (button.view ~= "CHRONICLES" or (MS.JourneySettings:Get("showChronicles")
                and not (MS.Config and MS.Config.chroniclesPaused))) then
            visible[#visible + 1] = button
        end
    end
    return visible
end

function Journey:LayoutView(view)
    local layout = MS.Workspace.layout
    if not layout then return end
    local main, side = layout.main, layout.side
    local left = math.min(main.x, side.x)
    local right = math.max(main.x + main.width, side.x + side.width)
    -- Second-screen safe area: lift the footer (and the content above it) off the physical
    -- bottom edge / OS taskbar. Journey-only; the shared workspace layout is unchanged.
    local inset = self.BOTTOM_SAFE_INSET
    local bottom = math.min(main.y, side.y) + inset
    local top = math.max(main.y + main.height, side.y + side.height)
    local full = { x = left, y = bottom, width = right - left, height = top - bottom }
    self.sessionJournalWidth = MS.JourneySettings:Get("sessionJournalWidth")
    self.mainWidth = full.width

    -- The Discussion band (JourneyChatView) sits lowest, right above the status bar.
    local chatView = MS.JourneyChatView
    local chatHeight = chatView and chatView:Height() or 0
    if chatView then chatView:Layout({ x = full.x, y = full.y, width = full.width, height = chatHeight }) end
    full = { x = full.x, y = full.y + chatHeight, width = full.width, height = full.height - chatHeight }
    local journalHeight = MS.JourneySessionJournal.expanded and 194 or 0
    local journalRect = { x = full.x, y = full.y, width = full.width, height = math.max(1, journalHeight) }
    local destinations = self:VisibleDestinations()
    -- Tabs fit their word, so the row reads as a sentence and not as equal boxes.
    local badgeWidth = self:PlaceBroadcastBadge()
    local available = math.max(1, self.header:GetWidth() - 160 - 104 - 32 - badgeWidth)
    local gap, wanted, total = 8, {}, 0
    for index, button in ipairs(destinations) do
        local measured = button.label.GetStringWidth and button.label:GetStringWidth()
        wanted[index] = math.max(84, (type(measured) == "number" and measured or 84) + 36)
        total = total + wanted[index]
    end
    local gaps = math.max(0, #destinations - 1) * gap
    local tabX = 160
    for _, button in ipairs(self.tabs) do button:Hide(); button.tabX = false end
    -- Too narrow for every word (a small second screen): one menu button instead of
    -- overlapping labels.
    local folded = total + gaps > available
    self:PlaceTabMenu(folded, destinations, view)
    if not folded then
        for index, button in ipairs(destinations) do
            local width = wanted[index]
            button:SetSize(width, 28); button:ClearAllPoints()
            button:SetPoint("BOTTOMLEFT", self.header, "BOTTOMLEFT", tabX, 2)
            button.tabX, button.tabWidth = tabX, width
            button:Show(); tabX = tabX + width + gap
        end
    end
    self.settingsButton:SetSize(104, 28); self.settingsButton:ClearAllPoints()
    self.settingsButton:SetPoint("BOTTOMRIGHT", self.header, "BOTTOMRIGHT", -12, 2)
    self.settingsButton:Show()
    local band = MS.JourneyMentorBand
    local bandHeight = band and band:Height(view) or 0
    local contractBand = MS.JourneyContractBand
    local contractHeight = contractBand and contractBand:Height(view) or 0
    local content = { x = full.x, y = full.y + journalHeight,
        width = full.width, height = math.max(1, full.height - journalHeight - bandHeight - contractHeight) }
    self.contentRect = content
    if band then
        band:Layout({ x = full.x, y = content.y + content.height, width = full.width, height = bandHeight })
    end
    if contractBand then
        contractBand:Layout({ x = full.x, y = content.y + content.height + bandHeight, width = full.width,
            height = contractHeight })
    end
    MS.SessionFeed:Layout(journalRect, "STRIP")
    MS.QuestJournal:Layout(content)
    MS.MapView:Layout(content)
    MS.InventoryView:Layout(content)
    if self.chroniclesViewReady then
        self.chroniclesViewReady = ChronicleUI(MS.ChroniclesView, "Layout", content)
    end
    if self.chroniclesToastReady then
        self.chroniclesToastReady = ChronicleUI(MS.ChroniclesDiscoveryToast, "Layout")
    end
    MS.JourneySettings:LayoutView(content)
    if MS.JourneyProgressionView then MS.JourneyProgressionView:Layout(content) end
    if MS.JourneyLiveView then MS.JourneyLiveView:Layout(content) end
    local footer = layout.bottom
    self.footerRect = { x = footer.x, y = footer.y + inset, width = footer.width, height = footer.height }
    MS.JourneyStatusBar:Layout(self.footerRect)
end

function Journey:Layout()
    local layout = MS.Workspace.layout
    if not layout then return end
    local header = layout.header
    self.header:ClearAllPoints()
    self.header:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", header.x, header.y)
    self.header:SetSize(header.width, header.height)
    -- Tabs sit on the header as siblings: in window mode the header takes the mouse for dragging,
    -- and siblings of one level have no fixed order, so the tabs must be above it explicitly.
    for _, button in ipairs(self.tabs) do button:SetFrameLevel(MS.Workspace.frame:GetFrameLevel() + TAB_LEVEL) end
    self.title:SetWidth(math.max(1, math.min(146, header.width - 28)))
    self:LayoutView(self.view)
    self:RefreshHeader()
end

-- Streamer mode reminder, left of Settings: a small wax-red mark; a click opens the settings.
local BADGE_COLOR = { .88, .38, .30 }

function Journey:CreateBroadcastBadge(parent)
    local badge = CreateFrame("Button", nil, parent)
    badge.edge = badge:CreateTexture(nil, "BACKGROUND")
    badge.edge:SetAllPoints(badge)
    badge.edge:SetColorTexture(BADGE_COLOR[1], BADGE_COLOR[2], BADGE_COLOR[3], .55)
    badge.fill = badge:CreateTexture(nil, "BORDER")
    badge.fill:SetPoint("TOPLEFT", badge, "TOPLEFT", 1, -1)
    badge.fill:SetPoint("BOTTOMRIGHT", badge, "BOTTOMRIGHT", -1, 1)
    MS.JourneyUIStyle:Color(badge.fill, "backgroundDeep")
    badge.label = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    MS.JourneyUIStyle:Body(badge.label, "SECONDARY", "textPrimary")
    badge.label:SetTextColor(BADGE_COLOR[1], BADGE_COLOR[2], BADGE_COLOR[3])
    badge.label:SetPoint("CENTER", badge, "CENTER")
    badge.label:SetText(MS.L.BROADCAST_BADGE)
    badge:SetScript("OnClick", function() Journey:SelectView("SETTINGS") end)
    badge:SetScript("OnEnter", function()
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(badge, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(MS.L.BROADCAST_BADGE_TOOLTIP, 1, 1, 1, true); GameTooltip:Show()
        end
    end)
    badge:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    badge:Hide()
    self.broadcastBadge = badge
end

-- Returns the width the badge takes from the tab row (0 when streamer mode is off).
function Journey:PlaceBroadcastBadge()
    local badge = self.broadcastBadge
    if not badge then return 0 end
    local on = MS.BroadcastMode ~= nil and MS.BroadcastMode:IsOn()
    badge:SetShown(on)
    if not on then return 0 end
    local measured = badge.label.GetStringWidth and badge.label:GetStringWidth()
    local width = math.max(72, (type(measured) == "number" and measured or 72) + 20)
    badge:SetSize(width, 22); badge:ClearAllPoints()
    badge:SetPoint("BOTTOMRIGHT", self.header, "BOTTOMRIGHT", -12 - 104 - 10, 5)
    badge:SetFrameLevel(MS.Workspace.frame:GetFrameLevel() + TAB_LEVEL)
    return width + 10
end

-- Narrow header: a menu button (three bars and the current tab) opens the tab list.
function Journey:CreateTabMenu(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(140, 28)
    button.bars = {}
    for index = 1, 3 do
        local bar = button:CreateTexture(nil, "ARTWORK")
        bar:SetSize(14, 2)
        bar:SetPoint("LEFT", button, "LEFT", 10, 6 - (index - 1) * 5)
        MS.JourneyUIStyle:Color(bar, "gold")
        button.bars[index] = bar
    end
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    MS.JourneyUIStyle:Body(button.label, "BODY", "gold")
    button.label:SetPoint("LEFT", button, "LEFT", 32, 0)
    button.label:SetJustifyH("LEFT")
    button.rule = button:CreateTexture(nil, "ARTWORK")
    button.rule:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 8, 2)
    button.rule:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -8, 2)
    button.rule:SetHeight(2)
    MS.JourneyUIStyle:Color(button.rule, "borderActive")
    button:SetScript("OnClick", function() Journey:OpenTabMenu() end)
    button:Hide()
    self.tabMenu = button
end

function Journey:PlaceTabMenu(folded, destinations, view)
    local button = self.tabMenu
    if not button then return end
    self.tabsFolded = folded == true
    button:SetShown(self.tabsFolded)
    if not self.tabsFolded then return end
    self.foldedDestinations = destinations
    local current
    for _, tab in ipairs(destinations) do if tab.view == view then current = tab end end
    button.label:SetText(current and current.label:GetText() or MS.L.JOURNEY_TABS_MENU)
    local measured = button.label.GetStringWidth and button.label:GetStringWidth()
    button:SetSize(math.max(96, (type(measured) == "number" and measured or 64) + 46), 28)
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", self.header, "BOTTOMLEFT", 160, 2)
    button:SetFrameLevel(MS.Workspace.frame:GetFrameLevel() + TAB_LEVEL)
    button.rule:SetShown(current ~= nil)
end

function Journey:OpenTabMenu()
    local menu = MS.JourneyContextMenu
    if not menu then return false end
    if menu:IsOpen("JOURNEY_TABS") then menu:Close("TOGGLE"); return false end
    local actions = {}
    for _, tab in ipairs(self.foldedDestinations or self:VisibleDestinations()) do
        local view = tab.view
        actions[#actions + 1] = { label = tab.label:GetText(), run = function()
            local previous = Journey.view
            Journey:SelectView(view)
            if Journey.view ~= previous then Journey:PlayTabSound() end
        end }
    end
    return menu:Open({ owner = "JOURNEY_TABS", title = MS.L.JOURNEY_TABS_MENU, actions = actions })
end

function Journey:RefreshHeader()
    if not self.title then return end
    self.title:SetText(MS.L.JOURNEY_BRAND)
    if MS.JourneyStatusBar and MS.JourneyStatusBar.RefreshSession then
        MS.JourneyStatusBar:RefreshSession()
    end
end

function Journey:StyleTabs()
    for index, button in ipairs(self.tabs) do
        local active = VIEWS[index] == self.view
        MS.JourneyUIStyle:TabState(button, active, button.hovered, button.secondary)
        if button.view == "SETTINGS" then
            button.background:SetAlpha(1)
            MS.JourneyUIStyle:Color(button.background, active and "backgroundRaised" or "backgroundPanel")
        end
    end
    self:RefreshChroniclesAttention()
end

function Journey:RefreshChroniclesAttention(refreshView)
    local button = self.tabs and self.tabs[4]
    if not button then return end
    local count = 0
    if MS.Chronicles then
        local ok, value = pcall(MS.Chronicles.GetUnreadCount, MS.Chronicles)
        if ok and type(value) == "number" then count = value end
    end
    local label = MS.L.JOURNEY_VIEW_CHRONICLES
    if count > 0 then label = label .. "  ·  " .. count end
    button.label:SetText(label)
    local active = self.view == "CHRONICLES"
    MS.JourneyUIStyle:Text(button.label, (active or count > 0) and "gold"
        or button.hovered and "textPrimary" or "textSecondary")
    button.rule:SetShown(active or count > 0 or button.hovered == true)
    MS.JourneyUIStyle:Color(button.rule, not active and count > 0 and "bronze" or "borderActive")
    if refreshView and active and self.chroniclesViewReady then
        ChronicleUI(MS.ChroniclesView, "Refresh")
    end
    if refreshView and self.view == "MAP" and MS.JourneyContextPanel then
        MS.JourneyContextPanel:RefreshMemory()
    end
end

-- Only for a tab the player clicked; the Journey sounds switch and the combat guard live in Kit.
function Journey:PlayTabSound()
    local kit = MS.Active and MS.Active.Kit
    if kit then kit.Play("TAB") end
end

function Journey:ViewFrame(view)
    local owners = { MAP = MS.MapView, QUESTS = MS.QuestJournal, INVENTORY = MS.InventoryView,
        SETTINGS = MS.JourneySettings, PROGRESSION = MS.JourneyProgressionView, CHRONICLES = MS.ChroniclesView }
    return owners[view] and owners[view].frame
end

function Journey:TabFor(view)
    for _, button in ipairs(self.tabs) do
        if button.view == view and view ~= "SETTINGS" and button.tabX then return button end
    end
end

-- Moves the rule between two tabs, then gives it back to the tab, and fades the new view in.
function Journey:AnimateChange(previous, view)
    if previous == view then return end
    local style, frame = MS.JourneyUIStyle, self:ViewFrame(view)
    if frame then style:FadeIn(frame, .15) end
    local from, to, slider = self:TabFor(previous), self:TabFor(view), self.tabSlider
    if not from or not to or not slider then return end
    to.rule:SetAlpha(0); slider:Show()
    style:Tween(slider, .16, function(progress)
        local eased = 1 - (1 - progress) * (1 - progress)
        local left = from.tabX + (to.tabX - from.tabX) * eased
        local width = from.tabWidth + (to.tabWidth - from.tabWidth) * eased
        slider:ClearAllPoints()
        slider:SetPoint("BOTTOMLEFT", self.header, "BOTTOMLEFT", left + 8, 4)
        slider:SetWidth(math.max(1, width - 16))
        if progress >= 1 then slider:Hide(); to.rule:SetAlpha(1) end
    end)
end

function Journey:SelectView(view)
    if view ~= "QUESTS" and view ~= "MAP" and view ~= "INVENTORY" and view ~= "SETTINGS" and view ~= "PROGRESSION" and view ~= "CHRONICLES" then return nil end
    if not self.active then return nil end
    if MS.JourneyContextMenu then MS.JourneyContextMenu:Close("VIEW") end
    -- A tab click leaves the live view for that tab.
    if MS.JourneyLiveView then MS.JourneyLiveView:Close() end
    if view == "CHRONICLES" and (not self.chroniclesViewReady or not MS.JourneySettings:Get("showChronicles")) then return nil end
    if view ~= "MAP" then MS.MapView:Hide() end
    local previous = self.view
    self.view = view
    MS.QuestJournal.visible, MS.InventoryView.visible = view == "QUESTS", view == "INVENTORY"
    MS.QuestJournal.frame:SetShown(view == "QUESTS")
    MS.InventoryView.frame:SetShown(view == "INVENTORY")
    if MS.JourneySettings.HideView then MS.JourneySettings:HideView() end
    if MS.JourneyProgressionView then MS.JourneyProgressionView:SetVisible(false) end
    if self.chroniclesViewReady then ChronicleUI(MS.ChroniclesView, "SetVisible", false) end
    self:LayoutView(view)
    if MS.JourneyProgressionView then MS.JourneyProgressionView:SetVisible(view == "PROGRESSION") end
    if self.chroniclesViewReady and not ChronicleUI(MS.ChroniclesView, "SetVisible", view == "CHRONICLES") then
        self.chroniclesViewReady = false
        if view == "CHRONICLES" then return self:SelectView("MAP") end
    end
    if view == "SETTINGS" then MS.JourneySettings:ShowView() end
    if view == "MAP" then MS.MapView:Show() end
    if view == "QUESTS" and MS.JourneyContextPanel then MS.JourneyContextPanel:SetVisible(true) end
    local saved = MS.Database:Get().workspace
    saved.view = view
    if view ~= "SETTINGS" then saved.lastMainView = view end
    if view == "QUESTS" then MS.QuestJournal:Refresh() end
    if view == "INVENTORY" then MS.InventoryView:Refresh() end
    self:StyleTabs()
    self:AnimateChange(previous, view)
    return true
end

function Journey:Start()
    if not self.active then
        MS.JourneyQuestData.refreshTicket, MS.JourneyQuestData.coalescedCount = nil, 0
    end
    local ok, detail = pcall(function()
        if MS.JourneySettings.Initialize and not MS.JourneySettings.initialized then MS.JourneySettings:Initialize(MS.Database:Get()) end
        self:Create()
        self:Layout()
        if MS.JourneySessionJournal then MS.JourneySessionJournal:SetVisible(true) end
        if not self.active then MS.MapView:BeginActivation("JOURNEY_ENABLE") end
        self.active = true
        MS.QuestJournal:Start()
        MS.InventoryView:Start()
        MS.JourneyStatusBar:Start()
        MS.JourneySession:StartClock()
        local saved = MS.Database:Get().workspace
        local view = saved.view or saved.lastMainView or "MAP"
        if view == "SETTINGS" then
            view = MS.Database:Get().workspace.lastMainView
            if view ~= "MAP" and view ~= "QUESTS" and view ~= "INVENTORY" and view ~= "PROGRESSION" and view ~= "CHRONICLES" then view = "MAP" end
        end
        -- The Discussion panel decides before the first layout of the views.
        if MS.JourneyChatView then MS.JourneyChatView:Sync() end
        if not self:SelectView(view) then self:SelectView("MAP") end
        if MS.JourneyMapKey then MS.JourneyMapKey:Apply() end
    end)
    if not ok then self.lastError = tostring(detail); return nil, "ERROR_JOURNEY_CREATE" end
    self.lastError = nil
    return true
end

function Journey:Stop()
    self.active = false
    -- First: the game's chat comes back whatever happens next.
    if MS.JourneyChatView then pcall(MS.JourneyChatView.Stop, MS.JourneyChatView) end
    if MS.JourneyLiveView then pcall(MS.JourneyLiveView.Close, MS.JourneyLiveView) end
    if MS.JourneyMapKey then MS.JourneyMapKey:Apply() end
    if MS.JourneyProgressionView then MS.JourneyProgressionView:SetVisible(false) end
    if self.chroniclesViewReady then ChronicleUI(MS.ChroniclesView, "SetVisible", false) end
    if self.chroniclesToastReady then ChronicleUI(MS.ChroniclesDiscoveryToast, "Dismiss") end
    if MS.JourneySettings.HideView then MS.JourneySettings:HideView() end
    if MS.JourneySessionJournal then MS.JourneySessionJournal:SetVisible(false) end
    MS.JourneyQuestData.refreshTicket = nil
    MS.JourneySession:StopClock()
    MS.QuestJournal:Stop()
    MS.InventoryView:Stop()
    MS.JourneyStatusBar:Stop()
    local restored, reason = MS.MapView:Restore()
    if not restored then return nil, reason end
    return true
end

function Journey:GetStatus()
    local layout = MS.Workspace.layout
    local physical = MS.Workspace.physicalRect
    local width = physical and physical.width or 0
    local responsive = width >= 1600 and "LARGE" or width >= 1000 and "BALANCED" or "REDUCED"
    local session = MS.JourneySession:GetSummary()
    return { active = self.active, view = self.view, error = self.lastError,
        questView = { visible = MS.QuestJournal.visible == true, dirty = MS.QuestJournal.dirty == true,
            refreshCount = MS.QuestJournal.refreshCount or 0, deferredRefreshCount = MS.QuestJournal.deferredRefreshCount or 0 },
        inventoryView = { visible = MS.InventoryView.visible == true, dirty = MS.InventoryView.dirty == true,
            refreshCount = MS.InventoryView.refreshCount or 0, deferredRefreshCount = MS.InventoryView.deferredRefreshCount or 0 },
        inventory = MS.InventoryView.GetStatus and MS.InventoryView:GetStatus(),
        mapView = { visible = MS.MapView.active == true, dirty = MS.MapView.dirty == true,
            questModelRefreshCount = MS.MapView.questModelRefreshCount or 0,
            questModelCoalescedCount = MS.JourneyQuestData.coalescedCount or 0 },
        memory = MS.JourneyMemory and MS.JourneyMemory:GetStatus(),
        progressionView = MS.JourneyProgressionView and MS.JourneyProgressionView:GetStatus(),
        contextPanel = MS.JourneyContextPanel and MS.JourneyContextPanel:GetStatus(),
        sessionJournal = MS.JourneySessionJournal and MS.JourneySessionJournal:GetStatus(),
        settings = { textScale = MS.JourneySettings:Get("textScale"), sessionJournalWidth = MS.JourneySettings:Get("sessionJournalWidth"),
            showQuestProgressBars = MS.JourneySettings:Get("showQuestProgressBars"), followPlayerOnStart = MS.JourneySettings:Get("followPlayerOnStart") },
        sessionActive = MS.JourneySession.active,
        sessionDuration = session and session.duration,
        sessionEvents = session and session.events,
        xpGained = session and session.xpGained,
        xpPerHour = session and session.xpPerHour,
        etaNextLevel = session and session.etaNextLevel,
        questCount = MS.QuestJournal.questCount,
        completedQuestCount = MS.QuestJournal.completedCount,
        bagFree = MS.JourneyStatusBar.bagFree,
        bagTotal = MS.JourneyStatusBar.bagTotal,
        mapSupported = MS.MapView:IsSupported(),
        inventorySupported = MS.InventoryView.supported,
        uiTextScale = MS.JourneySettings:Get("textScale"),
        sessionJournalWidth = self.sessionJournalWidth,
        mapMainWidth = self.mainWidth,
        responsiveMode = layout and responsive or "unavailable" }
end
