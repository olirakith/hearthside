local MS = _G.MS
MS.Active = MS.Active or {}
-- Sur mes pas: one place, one line, one recipient. Three small tabs, no editor.
local A = MS.Active
local Kit = A.Kit
local View = { topic = "SEAL", tab = "WRITE", kind = "NEXT", rows = {}, pageSize = 6, page = 1 }
A.SealView = View

function View:Title() return MS.L.SEAL_NAME end

local KINDS = { "NEXT", "CHAR", "ANY" }

local function Tab(parent, width, key, onClick)
    local button = Kit.Button(parent, width, 24, onClick)
    button:SetLabel(MS.L[key])
    return button
end

-- Streamer mode (Workspace/BroadcastMode.lua): names and codes stay out of sight.
local function Broadcast() return MS.BroadcastMode ~= nil and MS.BroadcastMode:IsOn() end
local function Person(name) return MS.BroadcastMode and MS.BroadcastMode:Person(name) or name end

function View:Build(container, width)
    local L = MS.L
    self.width = width
    local third = math.floor((width - 16) / 3)
    self.tabs = {
        WRITE = Tab(container, third, "SEAL_TAB_WRITE", function() View:SetTab("WRITE") end),
        CODE = Tab(container, third, "SEAL_TAB_CODE", function() View:SetTab("CODE") end),
        LIST = Tab(container, third, "SEAL_TAB_LIST", function() View:SetTab("LIST") end),
    }
    self.tabs.WRITE:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    self.tabs.CODE:SetPoint("LEFT", self.tabs.WRITE, "RIGHT", 8, 0)
    self.tabs.LIST:SetPoint("LEFT", self.tabs.CODE, "RIGHT", 8, 0)

    -- WRITE
    local write = CreateFrame("Frame", nil, container)
    write:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -36)
    write:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    self.write = write
    self.place = Kit.Label(write, "BODY", "textPrimary")
    self.place:SetPoint("TOPLEFT", write, "TOPLEFT", 0, 0)
    self.place:SetWidth(width)
    self.forLabel = Kit.Label(write, "SECONDARY", "textSecondary")
    self.forLabel:SetPoint("TOPLEFT", write, "TOPLEFT", 0, -46)
    self.forLabel:SetText(L.SEAL_FOR)
    self.kinds = {}
    local previous
    for _, kind in ipairs(KINDS) do
        local button = Kit.Button(write, third, 26, function() View.kind = kind; View:Refresh() end)
        button:SetLabel(L["SEAL_KIND_" .. kind])
        Kit.Size(button.label, "SECONDARY")
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        else button:SetPoint("TOPLEFT", write, "TOPLEFT", 0, -66) end
        self.kinds[kind] = button
        previous = button
    end
    self.kindHint = Kit.Label(write, "SECONDARY", "muted")
    self.kindHint:SetPoint("TOPLEFT", write, "TOPLEFT", 0, -98)
    self.kindHint:SetWidth(width)
    self.name = Kit.Input(write, width, 60)
    self.name:SetPoint("TOPLEFT", write, "TOPLEFT", 0, -122)
    self.namePlaceholder = Kit.Label(self.name, "SECONDARY", "muted")
    self.namePlaceholder:SetPoint("LEFT", self.name, "LEFT", 8, 0)
    self.namePlaceholder:SetWidth(width - 100)
    self.namePlaceholder:SetText(L.SEAL_NAME_PLACEHOLDER)
    self.nameWidth = width
    self.friends = Kit.Button(write, 76, 26, function() View:OpenFriends() end)
    self.friends:SetPoint("TOPRIGHT", write, "TOPRIGHT", 0, -122)
    self.friends:SetLabel(L.SEAL_FRIENDS)
    Kit.Size(self.friends.label, "SECONDARY")
    self.name:SetScript("OnTextChanged", function() View:RefreshInputs() end)
    self.textLabel = Kit.Label(write, "SECONDARY", "textSecondary")
    self.textLabel:SetPoint("TOPLEFT", write, "TOPLEFT", 0, -158)
    self.textLabel:SetText(L.SEAL_TEXT_LABEL)
    self.counter = Kit.Label(write, "SECONDARY", "muted", "RIGHT")
    self.counter:SetPoint("TOPRIGHT", write, "TOPRIGHT", 0, -158)
    self.text = Kit.Input(write, width, A.SealCodec.textBytes)
    self.text:SetPoint("TOPLEFT", write, "TOPLEFT", 0, -178)
    self.text:SetScript("OnTextChanged", function() View:RefreshInputs() end)
    self.text:SetScript("OnEnterPressed", function() View:Seal() end)
    self.seal = Kit.Button(write, 200, 30, function() View:Seal() end)
    self.seal:SetPoint("TOPRIGHT", write, "TOPRIGHT", 0, -216)
    self.seal:SetLabel(L.SEAL_ACTION)
    self.feedback = Kit.Label(write, "SECONDARY", "textSecondary")
    self.feedback:SetPoint("TOPLEFT", write, "TOPLEFT", 0, -256)
    self.feedback:SetWidth(width)
    -- Shared code (CHAR / ANY), shown after sealing.
    self.code = Kit.Input(write, width, 400)
    self.code:SetPoint("TOPLEFT", write, "TOPLEFT", 0, -300)
    self.code:SetScript("OnTextChanged", function(box, user) if user and View.sharedCode then box:SetText(View.sharedCode); box:HighlightText() end end)
    self.code:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
    self.whisper = Kit.Button(write, 240, 26, function() View:Whisper() end)
    self.whisper:SetPoint("TOPRIGHT", write, "TOPRIGHT", 0, -334)
    self.whisper:SetLabel(L.SEAL_WHISPER_ACTION)

    -- CODE
    local code = CreateFrame("Frame", nil, container)
    code:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -36)
    code:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    self.codeTab = code
    self.codeIntro = Kit.Label(code, "BODY", "textSecondary")
    self.codeIntro:SetPoint("TOPLEFT", code, "TOPLEFT", 0, 0)
    self.codeIntro:SetWidth(width)
    self.codeIntro:SetText(L.SEAL_CODE_INTRO)
    self.paste = Kit.Input(code, width, 2000)
    self.paste:SetPoint("TOPLEFT", code, "TOPLEFT", 0, -64)
    self.paste:SetScript("OnEnterPressed", function() View:Import() end)
    self.import = Kit.Button(code, 200, 30, function() View:Import() end)
    self.import:SetPoint("TOPRIGHT", code, "TOPRIGHT", 0, -100)
    self.import:SetLabel(L.SEAL_IMPORT_ACTION)
    self.importFeedback = Kit.Label(code, "BODY", "textPrimary")
    self.importFeedback:SetPoint("TOPLEFT", code, "TOPLEFT", 0, -144)
    self.importFeedback:SetWidth(width)

    -- LIST
    local list = CreateFrame("Frame", nil, container)
    list:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -36)
    list:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    self.list = list
    self.empty = Kit.Label(list, "BODY", "textSecondary")
    self.empty:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
    self.empty:SetWidth(width)
    self.empty:SetText(L.SEAL_LIST_EMPTY)
    self.rowText = width - 130
    for index = 1, self.pageSize do
        local row = CreateFrame("Frame", nil, list)
        row:SetSize(width, 50)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * 54)
        row.title = Kit.Label(row, "BODY", "textPrimary")
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
        row.title:SetWidth(width - 130)
        row.detail = Kit.Label(row, "SECONDARY", "textSecondary")
        row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -24)
        row.detail:SetWidth(width - 130)
        -- Abandoning a waiting seal asks twice: the second click on the same row does it.
        row.action = Kit.Button(row, 116, 24, function()
            local entry = row.entry
            if not entry then return end
            if entry.confirm and not entry.armed then entry.armed = true; row.action:SetLabel(MS.L.SEAL_ROW_CONFIRM); return end
            entry.run()
        end)
        row.action:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.alt = Kit.Button(row, 76, 24, function() if row.entry and row.entry.altRun then row.entry.altRun() end end)
        row.alt:SetPoint("RIGHT", row.action, "LEFT", -8, 0)
        row.rule = Kit.Rule(row)
        row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        self.rows[index] = row
    end
    self:BuildPager(list, width)
end

function View:SetTab(tab)
    self.tab, self.page = tab, 1
    self:Refresh()
end

function View:BuildPager(list, width)
    self.previous = Kit.Button(list, 130, 24, function() View.page = View.page - 1; View:RefreshList() end)
    self.previous:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 0, 0)
    self.previous:SetLabel(MS.L.SEAL_LIST_PREVIOUS)
    self.nextPage = Kit.Button(list, 130, 24, function() View.page = View.page + 1; View:RefreshList() end)
    self.nextPage:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
    self.nextPage:SetLabel(MS.L.SEAL_LIST_NEXT)
    self.pageLabel = Kit.Label(list, "SECONDARY", "muted", "CENTER")
    self.pageLabel:SetPoint("BOTTOM", list, "BOTTOM", 0, 6)
    self.pageLabel:SetWidth(width - 280)
end

local function Bytes(box)
    local text = box:GetText() or ""
    return #text, text
end

function View:RefreshInputs()
    local L = MS.L
    local used = Bytes(self.text)
    self.counter:SetText(string.format(L.SEAL_COUNTER, used, A.SealCodec.textBytes))
    Kit.Paint(self.counter, used > A.SealCodec.textBytes and "critical" or "muted")
    self.namePlaceholder:SetShown((self.name:GetText() or "") == "")
    -- The exact name the seal will be bound to, before sealing (the realm defaults to yours).
    local hint = L["SEAL_KIND_" .. self.kind .. "_HINT"]
    if self.kind == "CHAR" then
        local recipient = A.Text.RecipientName(self.name:GetText(), A.Seals:DefaultRealm())
        if recipient then hint = string.format(L.SEAL_KIND_CHAR_FOR, Person(recipient)) end
    end
    self.kindHint:SetText(hint)
end

function View:OpenFriends()
    local L, actions = MS.L, {}
    local broadcast = Broadcast()
    for index, friend in ipairs(A.Seals:Friends()) do
        local shown = broadcast and string.format(L.BROADCAST_FRIEND_N, index) or friend.name
        actions[#actions + 1] = {
            label = friend.online and string.format(L.SEAL_FRIEND_ONLINE, shown) or shown,
            run = function() View.name:SetText(friend.name); View.text:SetFocus() end,
        }
    end
    MS.JourneyContextMenu:Open({ owner = "SEAL_FRIENDS", title = L.SEAL_FRIENDS_TITLE, actions = actions })
end

-- Typed names and pasted codes show as stars; a code to copy turns clear but stays copyable.
function View:ApplyBroadcast()
    local mode = MS.BroadcastMode
    if not mode or not self.name then return end
    mode:Password(self.name)
    mode:Password(self.paste)
    mode:Conceal(self.code)
    self.whisperArmed = nil
end

function View:Refresh()
    local L = MS.L
    self:ApplyBroadcast()
    for name, button in pairs(self.tabs) do button:SetSelected(name == self.tab) end
    self.tabs.LIST:SetLabel(string.format(L.SEAL_TAB_LIST_COUNT, #A.Seals:Armed()))
    self.write:SetShown(self.tab == "WRITE")
    self.codeTab:SetShown(self.tab == "CODE")
    self.list:SetShown(self.tab == "LIST")
    if self.tab == "WRITE" then self:RefreshWrite() elseif self.tab == "LIST" then self:RefreshList() end
end

-- Where the seal would go, re-read every second while the tab is open: "un instant…" turns into
-- the place by itself, and walking indoors says so at once.
function View:Tick()
    if self.tab == "WRITE" and self.write:IsShown() then self:RefreshPlace() end
end

function View:RefreshPlace()
    local L = MS.L
    local ok, reason, _, zone, subzone = A.Seals:Here()
    if ok then
        local place = zone or L.SEAL_SOMEWHERE
        if type(subzone) == "string" and subzone ~= "" and subzone ~= zone then place = place .. " — " .. A.Text.CleanLine(subzone, 64) end
        self.place:SetText(string.format(L.SEAL_HERE, place))
        Kit.Paint(self.place, "textPrimary")
    else
        self.place:SetText(L["SEAL_CANNOT_" .. reason] or L.SEAL_CANNOT_NO_POSITION)
        Kit.Paint(self.place, "warning")
    end
    self.canSeal = ok
    self.seal:SetEnabled(ok)
    self.seal.actionDisabled = not ok
end

function View:RefreshWrite()
    self:RefreshPlace()
    for kind, button in pairs(self.kinds) do button:SetSelected(kind == self.kind) end
    self.name:SetShown(self.kind == "CHAR")
    -- The menu lives on the workspace; without one, or without friends, the field stays whole.
    local menu = MS.JourneyContextMenu
    local friends = self.kind == "CHAR" and menu ~= nil and menu:Surface() ~= nil and #A.Seals:Friends() > 0
    self.friends:SetShown(friends)
    self.name:SetWidth(friends and self.nameWidth - 84 or self.nameWidth)
    self:RefreshInputs()
    local shared = self.sharedCode ~= nil
    self.code:SetShown(shared)
    self.whisper:SetShown(shared and self.sharedKind == "CHAR")
end

function View:Seal()
    local L = MS.L
    local seal, reason = A.Seals:Create(self.kind, self.text:GetText(), self.name:GetText())
    if not seal then
        self.feedback:SetText(L["SEAL_REFUSED_" .. tostring(reason)] or L["SEAL_CANNOT_" .. tostring(reason)] or L.SEAL_REFUSED_UNKNOWN)
        Kit.Paint(self.feedback, "warning")
        return
    end
    self.text:SetText("")
    self.text:ClearFocus()
    if seal.kind == "NEXT" then
        self.sharedCode, self.sharedKind, self.sharedSeal = nil, nil, nil
        self.feedback:SetText(L.SEAL_DONE_NEXT)
    else
        self.sharedCode, self.sharedKind, self.sharedSeal = seal.code, seal.kind, seal
        self.code:SetText(seal.code)
        local done = seal.kind == "CHAR" and string.format(L.SEAL_DONE_CHAR, Person(seal.recipient)) or L.SEAL_DONE_ANY
        self.feedback:SetText(Broadcast() and done .. " " .. L.BROADCAST_CODE_READY or done)
    end
    Kit.Paint(self.feedback, "success")
    self:RefreshWrite()
    if self.sharedCode then self.code:SetFocus(); self.code:HighlightText() end
end

local function Short(name) return name:match("^[^%-]+") or name end

function View:Whisper()
    if not self.sharedSeal then return end
    local L = MS.L
    -- Streaming: the prepared line shows the code in the game's chat box; the second click says go.
    if Broadcast() and not self.whisperArmed then
        self.whisperArmed = true
        self.feedback:SetText(L.BROADCAST_WHISPER_WARN)
        Kit.Paint(self.feedback, "warning")
        return
    end
    self.whisperArmed = nil
    local ok, reason = A.Seals:WhisperCode(self.sharedSeal)
    local text = reason == "OFFLINE" and string.format(L.SEAL_WHISPER_OFFLINE, Person(Short(self.sharedSeal.recipient)))
        or L["ACTIVE_CHAT_" .. tostring(reason)] or L.ACTIVE_CHAT_FAILED
    self.feedback:SetText(ok and L.SEAL_WHISPER_READY or text)
    Kit.Paint(self.feedback, ok and "success" or "warning")
end

local function ShowCode(seal, instruction)
    instruction = instruction or MS.L.SEAL_CODE_COPY
    if Broadcast() then instruction = instruction .. " " .. MS.L.BROADCAST_CODE_READY end
    MS.Diagnostics:ShowCopyableReport(MS.L.SEAL_CODE_TITLE, seal.code, "SEAL_CODE", instruction, Broadcast())
end

-- From the list: the chat box opens on its own; an absent friend goes straight to the copy box.
function View:WhisperFromList(seal)
    local ok, reason = A.Seals:WhisperCode(seal)
    if ok then A:Say("SEAL_WHISPER_READY")
    elseif reason == "OFFLINE" then ShowCode(seal, string.format(MS.L.SEAL_CODE_OFFLINE, Person(Short(seal.recipient))))
    else A:Say(MS.L["ACTIVE_CHAT_" .. tostring(reason)] and "ACTIVE_CHAT_" .. tostring(reason) or "ACTIVE_CHAT_FAILED") end
end

function View:Import()
    local L = MS.L
    local seal, reason = A.Seals:Import(self.paste:GetText(), "PANEL")
    if seal then
        self.paste:SetText("")
        self.importFeedback:SetText(string.format(L.SEAL_IMPORT_OK, A.Position:MapName(seal.mapID) or L.SEAL_SOMEWHERE))
        Kit.Paint(self.importFeedback, "gold")
    else
        self.importFeedback:SetText(L["SEAL_IMPORT_" .. tostring(reason)] or L.SEAL_IMPORT_MALFORMED)
        Kit.Paint(self.importFeedback, "warning")
    end
    self.tabs.LIST:SetLabel(string.format(L.SEAL_TAB_LIST_COUNT, #A.Seals:Armed()))
end

-- Waiting seals (zone only, never the spot), shared codes, then opened ones to read again.
function View:Entries()
    local entries, L, Kit = {}, MS.L, A.Kit
    for _, seal in ipairs(A.Seals:Armed()) do
        local zone = A.Position:MapName(seal.mapID) or L.SEAL_SOMEWHERE
        entries[#entries + 1] = { title = seal.hint and string.format(L.SEAL_ROW_WAITING_HINT, zone, seal.hint)
            or string.format(L.SEAL_ROW_WAITING, zone),
            detail = seal.kind == "NEXT" and string.format(L.SEAL_ROW_FROM_SELF, seal.author, Kit.Date(seal.createdAt))
                or string.format(L.SEAL_ROW_FROM, Person(seal.author), Kit.Date(seal.createdAt)),
            action = L.SEAL_ROW_ABANDON, confirm = true, run = function() A.Seals:Abandon(seal.id) end }
    end
    local sent, opened = {}, {}
    for _, seal in pairs(A.Seals:All()) do
        if seal.state == "SENT" then sent[#sent + 1] = seal
        elseif seal.state == "OPENED" and seal.openedBy == A.identity.key then opened[#opened + 1] = seal end
    end
    table.sort(sent, function(a, b) return a.createdAt > b.createdAt end)
    table.sort(opened, function(a, b) return (a.openedAt or 0) > (b.openedAt or 0) end)
    for _, seal in ipairs(sent) do
        local zone = A.Position:MapName(seal.mapID) or L.SEAL_SOMEWHERE
        local entry = { title = seal.kind == "CHAR" and string.format(L.SEAL_ROW_SENT_CHAR, Person(seal.recipient or "?"))
            or L.SEAL_ROW_SENT_ANY, detail = string.format(L.SEAL_ROW_SENT_DETAIL, zone, Kit.Date(seal.createdAt)),
            action = L.SEAL_ROW_CODE, run = function() ShowCode(seal) end }
        if seal.kind == "CHAR" and seal.recipient then
            entry.alt, entry.altRun = entry.action, entry.run
            entry.action, entry.run = L.SEAL_ROW_WHISPER, function() View:WhisperFromList(seal) end
            -- Streaming: the whisper puts the code in the chat line, so it asks twice.
            entry.confirm = Broadcast()
        end
        entries[#entries + 1] = entry
    end
    for _, seal in ipairs(opened) do
        entries[#entries + 1] = { title = string.format(L.SEAL_ROW_OPENED, seal.text),
            detail = string.format(L.SEAL_ROW_OPENED_DETAIL, A.Position:MapName(seal.mapID) or L.SEAL_SOMEWHERE,
                seal.kind == "NEXT" and seal.author or Person(seal.author), Kit.Date(seal.openedAt)),
            action = L.SEAL_ROW_READ, run = function() if A.Reveal then A.Reveal:Queue(seal, true) end end }
    end
    return entries
end

-- Every kept seal is reachable: six rows a page.
function View:RefreshList()
    local entries = self:Entries()
    local pages = math.max(1, math.ceil(#entries / self.pageSize))
    self.page = math.max(1, math.min(self.page or 1, pages))
    self.empty:SetShown(#entries == 0)
    self.previous:SetShown(self.page > 1)
    self.nextPage:SetShown(self.page < pages)
    self.pageLabel:SetShown(pages > 1)
    self.pageLabel:SetText(string.format(MS.L.SEAL_LIST_PAGE, self.page, pages))
    local offset = (self.page - 1) * self.pageSize
    for index, row in ipairs(self.rows) do
        local entry = entries[offset + index]
        row:SetShown(entry ~= nil)
        if entry then
            row.title:SetText(entry.title)
            row.detail:SetText(entry.detail)
            row.action:SetLabel(entry.action)
            row.alt:SetShown(entry.alt ~= nil)
            row.alt:SetLabel(entry.alt)
            local room = self.rowText - (entry.alt and 84 or 0)
            row.title:SetWidth(room)
            row.detail:SetWidth(room)
            row.entry = entry
        end
    end
end

function View:Closed()
    self.sharedCode, self.sharedKind, self.sharedSeal = nil, nil, nil
    self.feedback:SetText("")
    self.importFeedback:SetText("")
end

A.Panel:RegisterView("SEAL", View)
