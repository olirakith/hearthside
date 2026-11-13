local MS = _G.MS

-- The Discussion panel (Docs/journey/CHAT-JOURNEY-FICHE.md, CHAT-FILTRES-FICHE.md): a band along
-- the bottom of Journey, above the status bar, on every tab, only on the second screen (never in
-- the one-screen window) and only when the player turned it on. While it shows, the game's chat
-- is hidden on the game screen and its own edit box is moved into the panel; Stop gives
-- everything back. The player's tabs come from JourneyChatTabs.
MS.JourneyChatView = { tabIndex = 1, unread = 0, shown = false, heights = { 150, 220, 300 },
    collapsedHeight = 36, headerHeight = 30, inputHeight = 30, pad = 18, searchWidth = 180 }
local View = MS.JourneyChatView

local function Settings() return MS.JourneySettings end
local function Style() return MS.JourneyUIStyle end
local function Tabs() return MS.JourneyChatTabs end

-- Shown when Journey runs on the second screen and the player wants it.
function View:Wanted()
    local journey, settings = MS.JourneyWorkspace, Settings()
    if not journey or journey.active ~= true or not settings then return false end
    if MS.JourneyWindow and MS.JourneyWindow.open then return false end
    return settings:Get("chatInJourney") == true
end

function View:Collapsed() return Settings():Get("chatCollapsed") == true end

-- The height Journey gives the band (0 when the panel is off).
function View:Height()
    if not self:Wanted() then return 0 end
    if self:Collapsed() then return self.collapsedHeight end
    return self.heights[Settings():Get("chatHeight")] or self.heights[2]
end

local function Label(parent, size, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Style():Body(label, size, color)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end

local function ActionButton(parent, run)
    local button = CreateFrame("Button", nil, parent)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Style():Body(button.label, "SECONDARY", "textPrimary")
    button.label:SetPoint("CENTER", button, "CENTER")
    Style():Action(button, button.label)
    button:SetScript("OnClick", run)
    return button
end

local function Short(text)
    return (tostring(text or ""):gsub("\n", " "))
end

-- The current tab (the first one if the chosen one was removed).
function View:Tab()
    local count = Tabs():Count()
    if self.tabIndex > count then self.tabIndex = count end
    if self.tabIndex < 1 then self.tabIndex = 1 end
    return Tabs():Get(self.tabIndex)
end

function View:Query()
    return self.query ~= nil and self.query ~= "" and self.query or nil
end

-- A tab word in the header: left click shows it, right click offers to edit it.
function View:TabButton(index)
    self.tabButtons = self.tabButtons or {}
    local button = self.tabButtons[index]
    if button then return button end
    button = CreateFrame("Button", nil, self.frame)
    button.index = index
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Style():Body(button.label, "BODY", "textSecondary")
    button.label:SetPoint("LEFT", button, "LEFT", 0, 1)
    button.label:SetWordWrap(false)
    button.rule = button:CreateTexture(nil, "ARTWORK")
    button.rule:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    button.rule:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    button.rule:SetHeight(2)
    Style():Color(button.rule, "borderActive")
    if button.RegisterForClicks then button:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    button:SetScript("OnClick", function(owner, mouse)
        if mouse == "RightButton" then View:OpenTabMenu(owner.index) else View:SetTab(owner.index) end
    end)
    button:SetScript("OnEnter", function() button.hovered = true; View:StyleTabs() end)
    button:SetScript("OnLeave", function() button.hovered = false; View:StyleTabs() end)
    self.tabButtons[index] = button
    return button
end

function View:Create(parent)
    if self.frame then return end
    local frame = CreateFrame("Frame", nil, parent)
    frame:EnableMouse(true)
    frame:Hide()
    self.frame = frame
    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints(frame)
    Style():Material(frame.background, "backgroundDeep")
    frame.rule = frame:CreateTexture(nil, "ARTWORK")
    frame.rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.rule:SetHeight(1)
    Style():Color(frame.rule, "borderActive")

    self.title = Label(frame, "SECONDARY", "gold")
    self.toggle = ActionButton(frame, function() View:SetCollapsed(not View:Collapsed()) end)
    self.copyButton = ActionButton(frame, function() View:CopyTab() end)
    self.searchButton = ActionButton(frame, function() View:OpenSearch() end)
    -- One menu button instead of the tab words when they do not fit.
    self.tabMenu = ActionButton(frame, function() View:OpenTabList() end)
    if self.tabMenu.RegisterForClicks then self.tabMenu:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    self.tabMenu:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then View:OpenTabMenu(View.tabIndex) else View:OpenTabList() end
    end)

    -- The search field, in the header while a search is open.
    local search = CreateFrame("EditBox", nil, frame)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    search:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlight)
    search:SetTextInsets(8, 8, 0, 0)
    search.back = search:CreateTexture(nil, "BACKGROUND")
    search.back:SetAllPoints(search)
    Style():Color(search.back, "backgroundPanel")
    search.edge = search:CreateTexture(nil, "BORDER")
    search.edge:SetPoint("BOTTOMLEFT", search, "BOTTOMLEFT", 0, 0)
    search.edge:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", 0, 0)
    search.edge:SetHeight(1)
    Style():Color(search.edge, "borderActive")
    search:SetScript("OnTextChanged", function(owner) View:SetQuery(owner:GetText()) end)
    search:SetScript("OnEscapePressed", function() View:CloseSearch() end)
    search:SetScript("OnEnterPressed", function(owner) owner:ClearFocus() end)
    search:Hide()
    self.search = search

    self.messages = CreateFrame("ScrollingMessageFrame", nil, frame)
    local messages = self.messages
    messages:SetFontObject(_G.ChatFontNormal or _G.GameFontNormal)
    messages:SetJustifyH("LEFT")
    messages:SetFading(false)
    messages:SetMaxLines(MS.JourneyChat.limit)
    messages:SetHyperlinksEnabled(true)
    messages:EnableMouseWheel(true)
    messages:SetScript("OnMouseWheel", function(scroller, delta)
        if delta > 0 then scroller:ScrollUp() else scroller:ScrollDown() end
    end)
    -- Our own links copy; the game's work as in its chat (a click on a name opens its menu).
    messages:SetScript("OnHyperlinkClick", function(_, link, text, button) View:OnLink(link, text, button) end)
    messages:SetScript("OnHyperlinkEnter", function(scroller, link) View:ShowLinkTooltip(scroller, link) end)
    messages:SetScript("OnHyperlinkLeave", function()
        local tooltip = MS.TooltipBridge and MS.TooltipBridge.tooltip
        if tooltip then tooltip:Hide() end
    end)

    self.lockdown = Label(frame, "SECONDARY", "textSecondary")
    self.latest = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.latest:SetFontObject(_G.ChatFontNormal or _G.GameFontNormal)
    self.latest:SetJustifyH("LEFT")
    self.latest:SetWordWrap(false)
    self.unreadMark = Label(frame, "SECONDARY", "textPrimary")
    self.unreadBack = frame:CreateTexture(nil, "BORDER")
    Style():Color(self.unreadBack, "parchmentDark")
    self.hint = Label(frame, "SECONDARY", "textSecondary")
    -- The edit box sits over this strip when the player types.
    self.inputStrip = CreateFrame("Frame", nil, frame)

    MS.JourneyChat:Listen(function(what, line) View:OnChat(what, line) end)
    Tabs():Listen(function() View:OnTabsChanged() end)
    -- While the player types, the line under the edit box (last message, hint) steps aside.
    frame:SetScript("OnUpdate", function() View:RefreshTyping() end)
end

function View:RefreshTyping()
    local box = MS.JourneyNativeChat:EditBox()
    local typing = box ~= nil and type(box.HasFocus) == "function" and box:HasFocus() == true
    if typing == self.typing then return end
    self.typing = typing
    self.latest:SetAlpha(typing and 0 or 1)
    self.hint:SetAlpha(typing and 0 or 1)
    self.unreadMark:SetAlpha(typing and 0 or 1)
    self.unreadBack:SetAlpha(typing and 0 or 1)
end

function View:OnLink(link, text, button)
    local Copy, Chat = MS.JourneyChatCopy, MS.JourneyChat
    local kind, value = Copy:Parse(link)
    if kind == "copy" then
        local line = Chat:Find(value)
        if line then Copy:Open(Copy:Plain(Chat:Format(line)), self.frame) end
        return
    end
    if kind == "url" then
        Copy:Open(value, self.frame)
        return
    end
    -- The game's own player menu opens on the game screen, where the player is not looking:
    -- Journey shows its own beside the name.
    if button == "RightButton" and self:OpenPlayerMenu(link, text) then return end
    if type(_G.SetItemRef) == "function" then pcall(_G.SetItemRef, link, text, button, _G.DEFAULT_CHAT_FRAME) end
end

-- "player:Name-Realm:12" -> "Name-Realm", false; "BNplayer:Name:5:12:..." -> "Name", true.
function View.PlayerFromLink(link)
    if type(link) ~= "string" then return nil end
    local name = link:match("^player:([^:]+)")
    if name and name ~= "" then return name, false end
    name = link:match("^BNplayer:([^:]+)")
    if name and name ~= "" then return name, true end
    return nil
end

local function IsSelf(name)
    local me = type(_G.UnitName) == "function" and _G.UnitName("player")
    return type(me) == "string" and (name:match("^([^%-]+)") or name) == me
end

-- Whisper, invite, add as friend, ignore, who, copy name. Battle.net friends: whisper only
-- (their names are protected strings the game alone can draw or copy).
function View:OpenPlayerMenu(link, text)
    local menu = MS.JourneyContextMenu
    local name, battleNet = View.PlayerFromLink(link)
    if not menu or not name then return false end
    local L = MS.L
    local function Whisper()
        if type(_G.SetItemRef) == "function" then _G.SetItemRef(link, text, "LeftButton", _G.DEFAULT_CHAT_FRAME) end
    end
    local actions = { { label = L.CHAT_PLAYER_WHISPER, run = Whisper } }
    local title = battleNet and L.CHAT_PLAYER_BATTLENET or name
    if not battleNet then
        local party, friends = _G.C_PartyInfo, _G.C_FriendList
        local invite = party and party.InviteUnit or _G.InviteUnit
        if not IsSelf(name) then
            if type(invite) == "function" then
                actions[#actions + 1] = { label = L.CHAT_PLAYER_INVITE, run = function() invite(name) end }
            end
            if friends and type(friends.AddFriend) == "function" then
                actions[#actions + 1] = { label = L.CHAT_PLAYER_FRIEND, run = function() friends.AddFriend(name) end }
            end
            if friends and type(friends.AddIgnore) == "function" then
                actions[#actions + 1] = { label = L.CHAT_PLAYER_IGNORE, run = function() friends.AddIgnore(name) end }
            end
        end
        -- Out of combat an action button sends /who on the click; in combat the search is written
        -- in the edit box for Enter. The whole name gets one answer, as a chat line.
        local who = MS.JourneyWho
        if who and who:Available() then
            actions[#actions + 1] = { label = L.CHAT_PLAYER_WHO, macro = who.Command(name), run = function() who:Ask(name) end }
        end
        actions[#actions + 1] = { label = L.CHAT_PLAYER_COPY, run = function() MS.JourneyChatCopy:Open(name, self.frame) end }
    end
    return menu:Open({ owner = "JOURNEY_CHAT_PLAYER", title = title, actions = actions }) == true
end

function View:ShowLinkTooltip(owner, link)
    local bridge = MS.TooltipBridge
    local kind = MS.JourneyChatCopy:Parse(link)
    if kind then
        local tooltip = bridge and bridge.PrepareWorkspaceTooltip and bridge:PrepareWorkspaceTooltip(owner)
        if not tooltip then return end
        tooltip:ClearAllPoints()
        tooltip:SetOwner(owner, "ANCHOR_CURSOR")
        tooltip:AddLine(MS.L[kind == "url" and "CHAT_COPY_URL_TIP" or "CHAT_COPY_LINE_TIP"], 1, 1, 1)
        tooltip:Show()
        return
    end
    kind = type(link) == "string" and link:match("^(%a+):")
    if kind ~= "item" and kind ~= "spell" and kind ~= "quest" and kind ~= "enchant" and kind ~= "achievement" then return end
    local tooltip = bridge and bridge.PrepareWorkspaceTooltip and bridge:PrepareWorkspaceTooltip(owner)
    if not tooltip then return end
    tooltip:ClearAllPoints()
    tooltip:SetOwner(owner, "ANCHOR_CURSOR")
    if pcall(tooltip.SetHyperlink, tooltip, link) then tooltip:Show() end
end

function View:ApplyFont()
    local font = _G.ChatFontNormal
    if not font or type(font.GetFont) ~= "function" then return end
    local path, size, flags = font:GetFont()
    local scale = Settings():Get("textScale") or 1
    size = math.floor((size or 14) * scale + .5)
    if path then
        self.messages:SetFont(path, size, flags or "")
        self.latest:SetFont(path, size, flags or "")
        if self.search.SetFont then self.search:SetFont(path, size, flags or "") end
    end
end

local function Fit(button, text, height)
    button.label:SetText(text)
    local width = math.max(64, (button.label:GetStringWidth() or 50) + 24)
    button:SetSize(width, height)
    return width
end

function View:Layout(rect)
    if not self.frame then return end
    self.rect = rect
    if not rect or rect.height <= 0 or not self.shown then self.frame:Hide(); return end
    local frame, pad, L = self.frame, self.pad, MS.L
    self.width = rect.width
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    frame:SetSize(rect.width, rect.height)
    frame:Show()
    self:ApplyFont()
    local collapsed = self:Collapsed()
    self.title:SetText(L.CHAT_TITLE)
    self.title:ClearAllPoints()
    local toggleWidth = Fit(self.toggle, collapsed and L.CHAT_EXPAND or L.CHAT_COLLAPSE, 24)
    self.toggle:SetWidth(math.max(84, toggleWidth))
    toggleWidth = self.toggle:GetWidth()
    self.toggle:ClearAllPoints()

    self.messages:SetShown(not collapsed)
    self.hint:SetShown(not collapsed)
    self.latest:SetShown(collapsed)
    self.copyButton:SetShown(not collapsed)
    local searching = self.searchOpen == true and not collapsed
    self.search:SetShown(searching)
    self.searchButton:SetShown(not collapsed and not searching)

    if collapsed then
        for _, button in ipairs(self.tabButtons or {}) do button:Hide() end
        self.tabMenu:Hide()
        self.title:SetPoint("LEFT", frame, "LEFT", pad, 0)
        self.toggle:SetPoint("RIGHT", frame, "RIGHT", -pad, 0)
        -- The edit box stays left of the Open button: on top of it, it would take its clicks.
        self.inputStrip:ClearAllPoints()
        self.inputStrip:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -4)
        self.inputStrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(self.pad + toggleWidth + 12), 4)
    else
        local top = self.headerHeight
        self.title:SetPoint("LEFT", frame, "TOPLEFT", pad, -top / 2)
        -- Right side, from the edge: Collapse, Copy, Search (or the search field).
        self.toggle:SetPoint("RIGHT", frame, "TOPRIGHT", -pad, -top / 2)
        local copyWidth = Fit(self.copyButton, L.CHAT_COPY_TAB, 22)
        self.copyButton:ClearAllPoints()
        self.copyButton:SetPoint("RIGHT", self.toggle, "LEFT", -8, 0)
        local rightEdge = pad + toggleWidth + 8 + copyWidth + 8
        if searching then
            self.search:SetSize(self.searchWidth, 22)
            self.search:ClearAllPoints()
            self.search:SetPoint("RIGHT", self.copyButton, "LEFT", -8, 0)
            rightEdge = rightEdge + self.searchWidth
        else
            local searchWidth = Fit(self.searchButton, L.CHAT_SEARCH, 22)
            self.searchButton:ClearAllPoints()
            self.searchButton:SetPoint("RIGHT", self.copyButton, "LEFT", -8, 0)
            rightEdge = rightEdge + searchWidth
        end
        local x = pad + (self.title:GetStringWidth() or 80) + 26
        self:LayoutTabs(x, rect.width - rightEdge - 16, top)
        self.messages:ClearAllPoints()
        self.messages:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -(top + 4))
        self.messages:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, self.inputHeight + 2)
        self.inputStrip:ClearAllPoints()
        self.inputStrip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        self.inputStrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        self.inputStrip:SetHeight(self.inputHeight)
        self.hint:ClearAllPoints()
        self.hint:SetPoint("LEFT", frame, "BOTTOMLEFT", pad, self.inputHeight / 2)
    end
    self:Dock()
    self:Redraw()
    self:StyleTabs()
end

-- The tab words when they fit between the title and the buttons, else one menu button.
function View:LayoutTabs(x, right, top)
    local L, list = MS.L, Tabs():List()
    local widths, total = {}, 0
    for index, tab in ipairs(list) do
        local button = self:TabButton(index)
        button.label:SetText(Tabs():Name(tab))
        widths[index] = (button.label:GetStringWidth() or 60) + 4
        total = total + widths[index] + 22
    end
    for index = #list + 1, #(self.tabButtons or {}) do self.tabButtons[index]:Hide() end
    local fits = x + total <= right
    for index = 1, #list do
        local button = self.tabButtons[index]
        button:SetShown(fits)
        if fits then
            button:SetSize(widths[index], top - 4)
            button:ClearAllPoints()
            button:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", x, -top)
            x = x + widths[index] + 22
        end
    end
    self.tabMenu:SetShown(not fits)
    if not fits then
        local label = Tabs():Name(self:Tab()) .. (self.unread > 0 and ("  " .. self.unread) or "") .. "  ›"
        local width = math.max(80, math.min(right - x, (Fit(self.tabMenu, label, 22))))
        self.tabMenu:SetWidth(math.max(60, width))
        self.tabMenu:ClearAllPoints()
        self.tabMenu:SetPoint("LEFT", self.frame, "TOPLEFT", x, -top / 2)
    end
    self.tabsFit = fits
end

-- The game's edit box along the panel's input strip.
function View:Dock()
    if self.shown and self.inputStrip then MS.JourneyNativeChat:Dock(self.inputStrip, self.pad, 1, self.pad) end
end

function View:StyleTabs()
    local current = self.tabIndex
    for index, button in ipairs(self.tabButtons or {}) do
        local tab = Tabs():Get(index)
        if tab then
            local active = index == current
            Style():Text(button.label, active and "gold" or button.hovered and "textPrimary" or "textSecondary")
            button.rule:SetShown(active)
            local name = Tabs():Name(tab)
            if self.unread > 0 and not active and Tabs():ShowsWhispers(tab) then name = name .. "  " .. self.unread end
            button.label:SetText(name)
        end
    end
end

function View:SetTab(index)
    self.tabIndex = index
    if self:SeesWhispers() then self.unread = 0 end
    if self.rect then self:Layout(self.rect) end
end

-- Every tab, for the narrow header.
function View:OpenTabList()
    local menu = MS.JourneyContextMenu
    if not menu then return end
    local actions = {}
    for index, tab in ipairs(Tabs():List()) do
        actions[#actions + 1] = { label = Tabs():Name(tab), run = function() View:SetTab(index) end }
    end
    menu:Open({ owner = "JOURNEY_CHAT_TABS", actions = actions })
end

-- Right click on a tab: edit it, or add one.
function View:OpenTabMenu(index)
    local menu = MS.JourneyContextMenu
    if not menu then return end
    local L = MS.L
    local actions = { { label = L.CHAT_TAB_EDIT, run = function() View:EditTab(index) end } }
    if Tabs():Count() < Tabs().max then
        actions[#actions + 1] = { label = L.CHAT_TAB_ADD, run = function()
            local added = Tabs():Add()
            if added then View:EditTab(added) end
        end }
    end
    menu:Open({ owner = "JOURNEY_CHAT_TAB", title = Tabs():Name(Tabs():Get(index)), actions = actions })
end

-- Opens Settings on this tab's editor.
function View:EditTab(index)
    local editor = MS.JourneyChatTabsEditor
    if editor then editor:Select(index) end
    if MS.JourneyWorkspace and MS.JourneyWorkspace.SelectView then MS.JourneyWorkspace:SelectView("SETTINGS") end
    if editor then editor:Reveal() end
end

function View:OnTabsChanged()
    if not self.shown then return end
    if self.rect then self:Layout(self.rect) end
end

function View:SetCollapsed(collapsed)
    Settings():Set("chatCollapsed", collapsed == true)
end

-- Copy ----------------------------------------------------------------------------------------

function View:CopyTab()
    local text = MS.JourneyChat:CopyText(self:Tab(), self:Query())
    MS.JourneyChatCopy:Open(text, self.frame)
end

-- Search --------------------------------------------------------------------------------------

function View:OpenSearch()
    self.searchOpen = true
    if self.rect then self:Layout(self.rect) end
    self.search:SetFocus()
end

function View:CloseSearch()
    self.searchOpen, self.query = false, nil
    if self.search then
        self.search:SetText("")
        self.search:ClearFocus()
    end
    if self.rect then self:Layout(self.rect) end
end

function View:SetQuery(text)
    text = type(text) == "string" and text or ""
    if text == (self.query or "") then return end
    self.query = text
    self:Redraw()
end

-- Whispers seen: the panel is open on a tab that shows them.
function View:SeesWhispers()
    return self.shown and not self:Collapsed() and Tabs():ShowsWhispers(self:Tab())
end

function View:Redraw()
    if not self.messages or not self.shown then return end
    local Chat, L = MS.JourneyChat, MS.L
    self.messages:Clear()
    local lines = Chat:Lines(self:Tab(), self:Query())
    for _, line in ipairs(lines) do
        self.messages:AddMessage(Chat:Display(line), Chat:Color(line))
    end
    if self:Query() then
        self.hint:SetText(string.format(L[#lines == 1 and "CHAT_SEARCH_ONE" or "CHAT_SEARCH_COUNT"], #lines))
    else
        self.hint:SetText(L.CHAT_HINT)
    end
    self:RefreshLatest()
    self:RefreshLockdown()
end

function View:RefreshLatest()
    local Chat, L = MS.JourneyChat, MS.L
    local line = Chat:Latest(nil)
    if line then
        self.latest:SetText(Short(Chat:Format(line)))
        self.latest:SetTextColor(Chat:Color(line))
    else
        self.latest:SetText("")
    end
    local collapsed = self:Collapsed()
    local count = self.unread
    local showMark = collapsed and count > 0
    self.unreadMark:SetShown(showMark)
    self.unreadBack:SetShown(showMark)
    local frame = self.frame
    self.latest:ClearAllPoints()
    if not collapsed then return end
    local right = -self.pad - self.toggle:GetWidth() - 14
    if showMark then
        self.unreadMark:SetText(string.format(L[count == 1 and "CHAT_UNREAD_ONE" or "CHAT_UNREAD"], count))
        self.unreadMark:ClearAllPoints()
        self.unreadMark:SetPoint("RIGHT", frame, "RIGHT", right - 8, 0)
        self.unreadBack:ClearAllPoints()
        self.unreadBack:SetPoint("TOPLEFT", self.unreadMark, "TOPLEFT", -8, 4)
        self.unreadBack:SetPoint("BOTTOMRIGHT", self.unreadMark, "BOTTOMRIGHT", 8, -4)
        right = right - (self.unreadMark:GetStringWidth() or 80) - 30
    end
    self.latest:SetPoint("LEFT", self.title, "RIGHT", 22, 0)
    self.latest:SetPoint("RIGHT", frame, "RIGHT", right, 0)
end

function View:RefreshLockdown()
    local locked = MS.JourneyChat.lockdown == true and not self:Collapsed()
    self.lockdown:SetShown(locked)
    if not locked then return end
    self.lockdown:SetText(MS.L.CHAT_LOCKDOWN)
    self.lockdown:ClearAllPoints()
    self.lockdown:SetPoint("RIGHT", self.frame, "BOTTOMRIGHT", -self.pad, self.inputHeight / 2)
end

function View:OnChat(what, line)
    if not self.shown then return end
    local Chat = MS.JourneyChat
    if what == "LINE" then
        if line.whisper and line.chatType ~= "WHISPER_INFORM" and line.chatType ~= "BN_WHISPER_INFORM"
            and not self:SeesWhispers() then
            self.unread = self.unread + 1
            if self.tabsFit == false and self.rect then self:Layout(self.rect) else self:StyleTabs() end
        end
        if not self:Collapsed() and Chat:Shows(self:Tab(), line) then
            if self:Query() then self:Redraw()
            else self.messages:AddMessage(Chat:Display(line), Chat:Color(line)) end
        end
        self:RefreshLatest()
    elseif what == "LOCKDOWN" then
        self:RefreshLockdown()
    else
        self:Redraw()
    end
end

-- Shows or hides the panel to match Wanted(), and hides or gives back the game's chat with it.
-- Returns true when the band height changed (Journey lays its views out again).
function View:Sync()
    local wanted = self:Wanted()
    local changed = wanted ~= self.shown
    self.shown = wanted
    if wanted then
        -- The first tab copies the game's window once, while the game's chat is still there.
        Tabs():ImportOnce()
        MS.JourneyChat:Start()
        MS.JourneyNativeChat:Conceal()
        self:StartWatch()
    else
        self:StopWatch()
        MS.JourneyNativeChat:Restore()
        MS.JourneyChat:Stop()
        if MS.JourneyChatCopy then MS.JourneyChatCopy:Close() end
        if self.frame then self.frame:Hide() end
    end
    return changed
end

-- Blizzard may move its edit box back (chat settings, font size, Edit Mode) and shows its chat
-- windows again after a loading screen: Journey hides them and docks the box again. Right after
-- Blizzard's chat events, and a light check once a second while the panel shows; no hook on
-- Blizzard code.
local CHAT_EVENTS = { "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS", "PLAYER_ENTERING_WORLD" }

function View:Keep()
    if not self.shown then return end
    MS.JourneyNativeChat:Conceal()
    if self.inputStrip and not MS.JourneyNativeChat:Docked(self.inputStrip) then self:Dock() end
end

function View:StartWatch()
    local timer = _G.C_Timer
    if self.watch or type(timer) ~= "table" or type(timer.NewTicker) ~= "function" then return end
    self.watch = timer.NewTicker(1, function() View:Keep() end)
    if not self.events and type(_G.CreateFrame) == "function" then
        self.events = _G.CreateFrame("Frame")
        -- After Blizzard's own handlers for the same event, which show the windows.
        self.events:SetScript("OnEvent", function()
            if type(timer.After) == "function" then timer.After(0, function() View:Keep() end) else View:Keep() end
        end)
    end
    if self.events then
        for _, event in ipairs(CHAT_EVENTS) do pcall(self.events.RegisterEvent, self.events, event) end
    end
end

function View:StopWatch()
    if self.watch then pcall(self.watch.Cancel, self.watch) end
    self.watch = nil
    if self.events then pcall(self.events.UnregisterAllEvents, self.events) end
end

-- Journey stops (one screen, safety cut, emergency restore): everything goes back.
function View:Stop()
    self.shown = false
    self:StopWatch()
    MS.JourneyNativeChat:Restore()
    MS.JourneyChat:Stop()
    if MS.JourneyChatCopy then MS.JourneyChatCopy:Close() end
    if self.frame then self.frame:Hide() end
end
