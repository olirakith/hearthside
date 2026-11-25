local MS = _G.MS
MS.Ink = MS.Ink or {}
-- L'Encre des Royaumes as a Journey tab. Three panes share the tab: the shelf (lists on the left,
-- the tale or draft on parchment on the right), the workshop (writing a tale) and the book
-- (reading one). The tab holds no state of its own beyond what is on screen.
local A = MS.Active
local I = MS.Ink
local T = I.Theme

local function L() return MS.L end

local Tab = { mode = "SHELF", panes = {} }
I.Tab = Tab

-- Shared words ---------------------------------------------------------------------------------
function Tab.ModeName(mode) return L()["INK_MODE_" .. tostring(mode)] or tostring(mode) end

function Tab.ItemName(itemID)
    local name
    if type(_G.C_Item) == "table" then name = A.Call(_G.C_Item.GetItemNameByID, itemID) end
    if type(name) ~= "string" then name = A.Call(_G.GetItemInfo, itemID) end
    return type(name) == "string" and name or string.format(L().INK_ITEM_UNKNOWN, itemID)
end

function Tab.ItemIcon(itemID)
    local icon
    if type(_G.C_Item) == "table" and type(_G.C_Item.GetItemIconByID) == "function" then icon = A.Call(_G.C_Item.GetItemIconByID, itemID) end
    if not icon and type(_G.GetItemIcon) == "function" then icon = A.Call(_G.GetItemIcon, itemID) end
    return icon or T.kinds.ITEM[2]
end

-- Hours of a page that opens at a time of day only, as the player reads a clock.
function Tab.Hours(when) return string.format(L().INK_HOURS, when.from, when.to) end

-- What keeps a page closed whatever the player does, in one sentence; nil when nothing.
function Tab.WaitText(page)
    local waiting = I.Waiting(page)
    if waiting == "LEVEL" then return string.format(L().INK_WAIT_LEVEL, page.when.level) end
    if waiting == "HOUR" then return string.format(L().INK_WAIT_HOUR, Tab.Hours(page.when)) end
end

-- What a page of people, emotes or kills asks for. A quest names who and where; a hunt or notes
-- leave that to the author's hint (an emote nobody could guess is always named).
function Tab.DeedText(page, tale, progress)
    local trigger, quest = page.trigger, tale.mode == "QUEST"
    if trigger.kind == "NPC" then
        return quest and string.format(L().INK_DEED_NPC, trigger.name) or L().INK_DEED_NPC_SECRET
    elseif trigger.kind == "KILL" then
        local count = progress and I.Progress.Kills(progress, page.key) or 0
        return string.format(L().INK_DEED_KILL, trigger.name, count, trigger.count)
    elseif trigger.kind == "EMOTE" then
        local command = I.Deeds.Command(trigger.token)
        if not trigger.npcID and not trigger.mapID then return string.format(L().INK_DEED_EMOTE, command) end
        if not quest then
            return string.format(trigger.npcID and L().INK_DEED_EMOTE_SECRET_NPC or L().INK_DEED_EMOTE_SECRET_PLACE, command)
        end
        local zone = trigger.mapID and (A.Position:MapName(trigger.mapID) or L().SEAL_SOMEWHERE)
        if trigger.npcID and zone then return string.format(L().INK_DEED_EMOTE_BOTH, command, trigger.name, zone) end
        if trigger.npcID then return string.format(L().INK_DEED_EMOTE_NPC, command, trigger.name) end
        return string.format(L().INK_DEED_EMOTE_PLACE, command, zone)
    end
end

function Tab.ProgressText(tale, progress)
    if progress and progress.finishedAt then return L().INK_STATUS_DONE end
    return string.format("%d / %d", progress and I.Progress.Count(tale, progress) or 0, #tale.pages)
end

-- Shell ----------------------------------------------------------------------------------------
function Tab:Create(parent)
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, parent)
    frame:Hide()
    frame.back = frame:CreateTexture(nil, "BACKGROUND")
    frame.back:SetAllPoints(frame)
    T.Grain(frame.back, "shell")
    self.frame = frame
    for name, pane in pairs(self.panes) do
        pane.frame = CreateFrame("Frame", nil, frame)
        pane.frame:SetAllPoints(frame)
        pane.frame:Hide()
        pane:Build(pane.frame)
        pane.name = name
    end
    -- The book follows the reader's steps once a second while it is shown.
    frame:SetScript("OnUpdate", function(_, elapsed)
        Tab.clock = (Tab.clock or 0) + (elapsed or 0)
        if Tab.clock < 1 then return end
        Tab.clock = 0
        -- The first second on screen: draw every text again (fonts loading late).
        if not Tab.touched then
            Tab.touched = true
            I.Theme.Touch()
            Tab:Refresh()
        end
        local pane = Tab.panes[Tab.mode]
        if pane and pane.Tick then pane:Tick() end
    end)
    return frame
end

function Tab:Layout(rect)
    if not self.frame then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    self.frame:SetSize(rect.width, rect.height)
    self.width, self.height = rect.width, rect.height
    if self.visible then self:Refresh() end
end

-- For a host without a Journey workspace (tests, a future window): any parent, any size.
function Tab:Place(parent, width, height)
    self:Create(parent)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", parent, "TOPLEFT")
    self.frame:SetSize(width, height)
    self.width, self.height = width, height
end

function Tab:SetVisible(visible)
    self.visible = visible == true
    if not self.frame then return end
    self.frame:SetShown(self.visible)
    if self.visible then self:Show(self.mode) end
end

-- mode: SHELF | WORKSHOP | BOOK; the rest goes to the pane's Open.
function Tab:Show(mode, ...)
    local pane = self.panes[mode]
    if not pane or not self.frame then return end
    for _, other in pairs(self.panes) do if other ~= pane and other.frame then other.frame:Hide() end end
    if self.mode ~= mode and self.panes[self.mode] and self.panes[self.mode].Closed then self.panes[self.mode]:Closed() end
    self.mode = mode
    if select("#", ...) > 0 and pane.Open then pane:Open(...) end
    pane.frame:Show()
    self:Refresh()
end

function Tab:Refresh()
    local pane = self.panes[self.mode]
    if not self.visible or not pane or not self.width then return end
    pane:Lay(self.width, self.height)
    pane:Refresh()
end

-- Something changed in the store (a page found, a tale kept): redraw what is shown.
function Tab:Changed()
    if self.visible then self:Refresh() end
end

-- Opens the tab from anywhere (home card, slash command, found page): the Journey window comes
-- up first when the second screen is not shown.
function I:OpenTab(mode, ...)
    local journey = MS.JourneyWorkspace
    if not journey then return false end
    if not journey.active then
        local window = MS.JourneyWindow
        if not (window and window.Open and window:Open()) then return false end
    end
    if journey.view ~= "INK" and not journey:SelectView("INK") then return false end
    Tab:Show(mode or "SHELF", ...)
    return true
end

-- SHELF ----------------------------------------------------------------------------------------
local Shelf = { section = nil, page = 1, rows = {}, lines = {} }
Tab.panes.SHELF = Shelf
I.Shelf = Shelf

local SECTIONS = { "FOLLOWING", "SHELF", "DRAFTS", "SEAL" }

function Shelf:Build(frame)
    self.title = T.Text(frame, "TITLE", 22, "text")
    self.title:SetText(L().INK_NAME)
    if type(self.title.SetWordWrap) == "function" then self.title:SetWordWrap(false) end
    self.counts = T.Text(frame, "UI", 13, "muted")
    if type(self.counts.SetWordWrap) == "function" then self.counts:SetWordWrap(false) end
    self.write = T.Button(frame, "PRIMARY", L().INK_WRITE_SHORT, function() Shelf:New() end, 110, 32)
    local items = {}
    for _, section in ipairs(SECTIONS) do items[#items + 1] = { value = section, label = L()["INK_SECTION_" .. section] } end
    self.tabs = T.Tabs(frame, items, function(value) Shelf:Section(value) end)
    self.list = CreateFrame("Frame", nil, frame)
    self.list:EnableMouseWheel(true)
    self.list:SetScript("OnMouseWheel", function(_, delta) Shelf:Turn(-delta) end)
    self.empty = T.Text(frame, "UI", 15, "muted")
    self.previous = T.Button(frame, "GHOST", "‹", function() Shelf:Turn(-1) end, 32, 28)
    self.next = T.Button(frame, "GHOST", "›", function() Shelf:Turn(1) end, 32, 28)
    self.pageLabel = T.Text(frame, "UI", 13, "muted", "CENTER")
    -- Paste a seal.
    self.sealHelp = T.Text(frame, "UI", 15, "textSoft")
    self.sealHelp:SetText(L().INK_INTRO)
    self.paste = T.Multi(frame, "UI", 13, I.Codec.maxInput, L().INK_PASTE_HINT, nil, false)
    self.keep = T.Button(frame, "PRIMARY", L().INK_IMPORT_ACTION, function() Shelf:Import() end, 170, 34)
    self.feedback = T.Text(frame, "UI", 14, "textSoft")
    self.separator = frame:CreateTexture(nil, "BORDER")
    T.Color(self.separator, "lineSoft")
    -- The preview: parchment on the right.
    self.sheet = T.Parchment(frame)
    local sheet = self.sheet
    self.kicker = T.Text(sheet, "UI", 13, "inkSoft")
    self.heading = T.Text(sheet, "TITLE", 22, "ink")
    self.intro = T.Text(sheet, "INK", 16, "ink")
    self.rule = sheet:CreateTexture(nil, "ARTWORK")
    T.Color(self.rule, "paperLine")
    self.more = T.Text(sheet, "UI", 13, "inkSoft")
    self.open = T.Button(frame, "PRIMARY", L().INK_OPEN_BOOK, function() Shelf:Primary() end, 200, 36)
    self.copy = T.Button(frame, "SECONDARY", L().INK_GIVE_ACTION, function() Shelf:Share() end, 150, 36)
    self.edit = T.Button(frame, "SECONDARY", L().INK_EDIT_ACTION, function() Shelf:Edit() end, 110, 36)
    self.forget = T.Confirm(frame, "GHOST", L().INK_FORGET_ACTION, L().INK_FORGET_CONFIRM, function() Shelf:Forget() end, 120, 36)
end

-- One marked line of the page list on the preview.
function Shelf:Line(index)
    local line = self.lines[index]
    if line then return line end
    local sheet = self.sheet
    line = CreateFrame("Frame", nil, sheet)
    line:SetHeight(24)
    line.disc = T.Disc(line, 18, "wax")
    line.disc:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.check = line:CreateTexture(nil, "OVERLAY")
    line.check:SetTexture(T.check)
    line.check:SetSize(16, 16)
    line.check:SetPoint("CENTER", line.disc, "CENTER")
    line.ring = line:CreateTexture(nil, "ARTWORK")
    line.ring:SetTexture(T.halo)
    line.ring:SetSize(26, 26)
    line.ring:SetPoint("CENTER", line.disc, "CENTER")
    line.label = T.Text(line, "UI", 15, "ink")
    line.label:SetPoint("LEFT", line, "LEFT", 28, 0)
    if type(line.label.SetWordWrap) == "function" then line.label:SetWordWrap(false) end
    self.lines[index] = line
    return line
end

function Shelf:Row(index)
    local row = self.rows[index]
    if row then return row end
    row = T.ListRow(self.list, 64)
    row:SetScript("OnClick", function(clicked) Shelf:Pick(clicked.item) end)
    self.rows[index] = row
    return row
end

function Shelf:Items()
    local section, items = self.section, {}
    if section == "FOLLOWING" then
        for _, f in ipairs(I:Following()) do items[#items + 1] = { kind = "TALE", id = f.id } end
    elseif section == "SHELF" then
        for _, e in ipairs(I:Entries()) do items[#items + 1] = { kind = "TALE", id = e.id } end
    elseif section == "DRAFTS" then
        for _, d in ipairs(I.Workshop:List()) do items[#items + 1] = { kind = "DRAFT", id = d.id } end
    end
    return items
end

function Shelf:Section(section)
    if self.section ~= section then
        self.section, self.page, self.selected = section, 1, nil
        self.feedback:SetText("")
    end
    Tab:Refresh()
end

function Shelf:Open(section, selected)
    if section then self.section, self.page = section, 1 end
    if selected then self.selected = selected end
end

function Shelf:Turn(delta)
    self.page = self.page + delta
    Tab:Refresh()
end

-- A narrow tab has no room for the preview: a click opens the tale or the draft at once.
function Shelf:Pick(item)
    if not item then return end
    self.selected = item
    self.forget:Reset()
    if not self.wide then return self:Primary() end
    Tab:Refresh()
end

function Shelf:New()
    local draft, reason = I.Workshop:New()
    if not draft then
        self.section = "DRAFTS"
        self.feedback:SetText(L()["INK_DESK_" .. tostring(reason)] or L().INK_DESK_NOT_READY)
        return Tab:Refresh()
    end
    Tab:Show("WORKSHOP", draft.id)
end

function Shelf:Primary()
    local item = self.selected
    if not item then return end
    if item.kind == "DRAFT" then return Tab:Show("WORKSHOP", item.id) end
    Tab:Show("BOOK", item.id)
end

-- Give the tale to a player, or copy its seal.
function Shelf:Share()
    local item = self.selected
    if not item or item.kind ~= "TALE" then return end
    I.GiveCard:Focus(item.id)
    A.Panel:Open("INK_GIVE")
end

function Shelf:Edit()
    local item = self.selected
    if not item or item.kind ~= "TALE" then return end
    local draft = I.Workshop:Edit(item.id)
    if draft then Tab:Show("WORKSHOP", draft.id) end
end

function Shelf:Forget()
    local item = self.selected
    if not item then return end
    local done
    if item.kind == "DRAFT" then done = I.Workshop:Discard(item.id) else done = I:Forget(item.id) end
    if done then self.selected = nil end
    Tab:Refresh()
end

function Shelf:Import()
    local entry, reason = I:Import(self.paste:GetValue())
    if entry then
        self.paste:SetValue("")
        self.paste.box:ClearFocus()
        self.feedback:SetText(string.format(L()["INK_IMPORT_" .. reason], entry.tale.title))
        self.section, self.page, self.selected = "SHELF", 1, { kind = "TALE", id = entry.tale.id }
    else
        self.feedback:SetText(L()["INK_IMPORT_" .. tostring(reason)] or L().INK_IMPORT_INVALID)
    end
    Tab:Refresh()
end

function Shelf:Lay(width, height)
    self.wide = width >= 760
    local left = self.wide and math.max(400, math.min(520, math.floor(width * .44))) or width
    self.leftWidth, self.width, self.height = left, width, height
    local frame, pad = self.frame, 26
    self.write:ClearAllPoints()
    self.write:SetPoint("TOPRIGHT", frame, "TOPLEFT", left - pad, -24)
    self.write:Fit(100, 160)
    -- The name keeps one line: a narrow column gets it smaller rather than folded over the tabs.
    local room = left - pad * 2 - self.write:GetWidth() - 14
    for _, size in ipairs({ 22, 19, 16, 14 }) do
        T.SetFont(self.title, "TITLE", size)
        if T.Width(self.title) <= room then break end
    end
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -24)
    self.title:SetWidth(room)
    self.counts:ClearAllPoints()
    self.counts:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -60)
    self.counts:SetWidth(left - pad * 2)
    self.tabs:ClearAllPoints()
    self.tabs:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -86)
    self.tabs:Lay(left - pad * 2)
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", frame, "TOPLEFT", pad - 8, -130)
    self.list:SetSize(left - pad * 2 + 16, height - 130 - 52)
    self.empty:ClearAllPoints()
    self.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -140)
    self.empty:SetWidth(left - pad * 2)
    self.previous:ClearAllPoints()
    self.previous:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", left - pad - 36, 14)
    self.next:ClearAllPoints()
    self.next:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", left - pad, 14)
    self.pageLabel:ClearAllPoints()
    self.pageLabel:SetPoint("RIGHT", self.previous, "LEFT", -6, 0)
    self.sealHelp:ClearAllPoints()
    self.sealHelp:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -140)
    self.sealHelp:SetWidth(left - pad * 2)
    self.paste:ClearAllPoints()
    -- A low tab drops the explanation (the field says what to paste) to keep the button in view.
    self.sealLow = height < 400
    self.paste:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, self.sealLow and -140 or -210)
    self.paste:Lay(left - pad * 2, math.max(44, math.min(220, height - (self.sealLow and 250 or 330))))
    self.keep:ClearAllPoints()
    self.keep:SetPoint("TOPLEFT", self.paste, "BOTTOMLEFT", 0, -12)
    self.keep:Fit(150, 240)
    self.feedback:ClearAllPoints()
    self.feedback:SetWidth(left - pad * 2)
    self.separator:ClearAllPoints()
    self.separator:SetPoint("TOPLEFT", frame, "TOPLEFT", left, 0)
    self.separator:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", left, 0)
    self.separator:SetWidth(1)
    self.separator:SetShown(self.wide)
    -- Preview.
    local px, pw = left + pad, width - left - pad * 2
    self.previewWidth = pw
    self.twoRows = pw < 540
    self.sheet:ClearAllPoints()
    self.sheet:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -24)
    self.sheet:SetSize(pw, height - 24 - 36 - 14 - 22 - (self.twoRows and 44 or 0))
    local sheet, inner = self.sheet, pw - 56
    self.kicker:ClearAllPoints()
    self.kicker:SetPoint("TOPLEFT", sheet, "TOPLEFT", 28, -26)
    self.kicker:SetWidth(inner)
    if type(self.kicker.SetWordWrap) == "function" then self.kicker:SetWordWrap(false) end
    self.heading:ClearAllPoints()
    self.heading:SetPoint("TOPLEFT", self.kicker, "BOTTOMLEFT", 0, -10)
    self.heading:SetWidth(inner)
    T.MaxLines(self.heading, 2)
    self.intro:ClearAllPoints()
    self.intro:SetPoint("TOPLEFT", self.heading, "BOTTOMLEFT", 0, -12)
    self.intro:SetWidth(inner)
    self.rule:ClearAllPoints()
    self.rule:SetPoint("TOPLEFT", self.intro, "BOTTOMLEFT", 0, -16)
    self.rule:SetSize(inner, 1)
    self.open:ClearAllPoints()
    self.open:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", px, 22)
end

-- The preview of one tale: what it promises, then each page as found, current or sealed.
function Shelf:ShowTale(id)
    local entry = I:Entry(id)
    if not entry then return false end
    local tale, progress = entry.tale, I:ProgressOf(id)
    local kicker = string.format(L().INK_PREVIEW_KICKER, Tab.ModeName(tale.mode), tale.author)
    if entry.from then
        local mode = MS.BroadcastMode
        kicker = kicker .. " · " .. string.format(L().INK_GIVEN_BY, mode and mode:Person(entry.from) or entry.from)
    end
    self.kicker:SetText(kicker)
    self.heading:SetText(tale.title)
    self.intro:SetText(tale.intro or L().INK_NO_INTRO)
    local found, open = {}, {}
    if progress then
        for _, page in ipairs(I.Progress.FoundPages(tale, progress)) do found[page.key] = true end
        for _, page in ipairs(I.Progress.Open(tale, progress)) do open[page.key] = true end
    end
    self:Lines(tale.pages, function(page)
        if found[page.key] then return "FOUND", page.title end
        if open[page.key] then return "OPEN", string.format(L().INK_PREVIEW_CURRENT, page.title) end
        return "SEALED", L().INK_PREVIEW_SEALED
    end)
    self.open:SetLabel(progress and L().INK_OPEN_BOOK or L().INK_BEGIN_BOOK)
    self.copy:Show()
    self.edit:SetShown(entry.origin == "WRITTEN")
    return true
end

function Shelf:ShowDraft(id)
    local draft = I.Workshop:Draft(id)
    if not draft then return false end
    local state = draft.baseVersion > 0 and string.format(L().INK_DRAFT_SEALED_VERSION, draft.baseVersion) or L().INK_DRAFT_NEVER_SEALED
    self.kicker:SetText(string.format(L().INK_PREVIEW_DRAFT, Tab.ModeName(draft.mode), state))
    self.heading:SetText(I.Tale.Line(draft.title, I.Tale.titleBytes) or L().INK_UNTITLED)
    self.intro:SetText(I.Tale.Block(draft.intro, I.Tale.introBytes) or L().INK_NO_INTRO)
    self:Lines(draft.pages, function(page)
        return "KIND:" .. page.trigger.kind, I.Tale.Line(page.title, I.Tale.titleBytes) or L().INK_UNTITLED
    end)
    self.open:SetLabel(L().INK_CONTINUE_WRITING)
    self.copy:Hide()
    self.edit:Hide()
    return true
end

-- The page list on the parchment, as many lines as fit under the introduction.
function Shelf:Lines(pages, describe)
    -- The parchment holds: surtitle, title, introduction, rule, page lines. A low parchment
    -- shortens the introduction first, then drops the page lines.
    local sheetHeight = self.sheet:GetHeight()
    local line = T.LineHeight(16, true)
    local above = 26 + T.LineHeight(13) + 10 + (self.heading:GetStringHeight() or 24) + 12
    local left = sheetHeight - above - 24
    local wanted = #pages > 0 and (16 + 12 + math.min(#pages, 3) * 28) or 0
    local introLines = math.floor((left - wanted) / line)
    if introLines < 2 then introLines, wanted = math.floor(left / line), 0 end
    T.MaxLines(self.intro, math.max(1, introLines))
    self.intro:SetShown(introLines >= 1)
    local top = above + (introLines >= 1 and (self.intro:GetStringHeight() or 20) or 0) + 16 + 12
    local room = wanted > 0 and math.max(0, math.floor((sheetHeight - top - 20) / 28)) or 0
    local shown = math.min(#pages, room)
    if #pages > room then shown = math.max(0, room - 1) end
    self.rule:SetShown(room > 0)
    for index = 1, math.max(shown, #self.lines) do
        local line = index <= shown and self:Line(index) or self.lines[index]
        if line then
            line:SetShown(index <= shown)
            if index <= shown then
                local state, text = describe(pages[index])
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", self.rule, "BOTTOMLEFT", 2, -12 - (index - 1) * 28)
                line:SetWidth(self.previewWidth - 60)
                line.label:SetWidth(self.previewWidth - 90)
                line.label:SetText(text)
                local kind = state:match("^KIND:(.+)")
                line.disc:SetShown(kind == nil)
                line.check:SetShown(state == "FOUND")
                line.ring:SetShown(state == "OPEN")
                if kind then
                    line.check:SetShown(true)
                    line.check:SetTexture(T.kinds[kind] and T.kinds[kind][2] or T.check)
                    line.check:SetTexCoord(.08, .92, .08, .92)
                else
                    line.check:SetTexture(T.check)
                    line.check:SetTexCoord(0, 1, 0, 1)
                    T.Color(line.disc, state == "SEALED" and "paperLine" or "wax")
                    if state == "OPEN" then line.ring:SetVertexColor(.62, .23, .17, 1); T.Color(line.disc, "paperDeep") end
                end
                T.SetFont(line.label, state == "OPEN" and "UI_BOLD" or "UI", 15)
                T.TextColor(line.label, state == "SEALED" and "inkSoft" or "ink")
            end
        end
    end
    self.more:ClearAllPoints()
    self.more:SetPoint("TOPLEFT", self.rule, "BOTTOMLEFT", 2, -12 - shown * 28)
    self.more:SetShown(#pages > shown and room > 0)
    self.more:SetText(string.format(L().INK_PREVIEW_MORE, #pages - shown))
end

function Shelf:Refresh()
    if not self.section then self.section = #I:Following() > 0 and "FOLLOWING" or "SHELF" end
    local following, entries, drafts = #I:Following(), #I:Entries(), I.Workshop and #I.Workshop:List() or 0
    self.counts:SetText(string.format(L().INK_COUNTS, following, entries, drafts))
    self.tabs:Select(self.section)
    local sealing = self.section == "SEAL"
    self.sealHelp:SetShown(sealing and not self.sealLow)
    self.paste:SetShown(sealing)
    self.keep:SetShown(sealing)
    self.feedback:ClearAllPoints()
    if sealing then self.feedback:SetPoint("TOPLEFT", self.keep, "BOTTOMLEFT", 0, -12)
    else self.feedback:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 26, 20) end
    local items = sealing and {} or self:Items()
    local perPage = math.max(1, math.floor((self.list:GetHeight() + 6) / 70))
    local pages = math.max(1, math.ceil(#items / perPage))
    self.page = math.max(1, math.min(self.page, pages))
    -- Keep a selection when there is room to show it.
    if self.wide and not sealing then
        local still = false
        for _, item in ipairs(items) do
            if self.selected and item.kind == self.selected.kind and item.id == self.selected.id then still = true end
        end
        if not still then self.selected = items[(self.page - 1) * perPage + 1] end
    end
    for index = 1, math.max(perPage, #self.rows) do
        local item = index <= perPage and items[(self.page - 1) * perPage + index] or nil
        local row = item and self:Row(index) or self.rows[index]
        if row then
            row:SetShown(item ~= nil)
            row.item = item
            if item then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -(index - 1) * 70)
                self:FillRow(row, item)
                row:SetSelected(self.wide and self.selected ~= nil and self.selected.kind == item.kind and self.selected.id == item.id)
                row:Lay(self.list:GetWidth())
            end
        end
    end
    self.empty:SetShown(not sealing and #items == 0)
    self.empty:SetText(L()["INK_EMPTY_" .. self.section] or "")
    self.previous:SetShown(pages > 1)
    self.next:SetShown(pages > 1)
    self.pageLabel:SetShown(pages > 1)
    self.pageLabel:SetText(string.format("%d / %d", self.page, pages))
    self.previous:SetActive(self.page > 1)
    self.next:SetActive(self.page < pages)
    -- Preview.
    local item = self.wide and self.selected or nil
    local shown = false
    if item then
        if item.kind == "TALE" then shown = self:ShowTale(item.id) else shown = self:ShowDraft(item.id) end
    end
    if not shown and self.wide then
        self.kicker:SetText(L().INK_NAME)
        self.heading:SetText(L().INK_PREVIEW_EMPTY_TITLE)
        self.intro:SetText(L().INK_PREVIEW_EMPTY)
        self:Lines({}, function() end)
    end
    self.sheet:SetShown(self.wide)
    self.open:SetShown(self.wide and shown)
    self.forget:SetShown(self.wide and shown)
    if not (self.wide and shown) then self.copy:Hide(); self.edit:Hide() end
    if self.wide and shown then
        local x = self.leftWidth + 26
        local width = self.previewWidth
        local buttons = { self.open }
        if self.copy:IsShown() then buttons[#buttons + 1] = self.copy end
        if self.edit:IsShown() then buttons[#buttons + 1] = self.edit end
        self.forget:SetLabel(item.kind == "DRAFT" and (self.forget.armed and L().INK_FORGET_CONFIRM or L().INK_DISCARD_ACTION)
            or (self.forget.armed and L().INK_FORGET_CONFIRM or L().INK_FORGET_ACTION))
        if self.twoRows then
            -- A narrow parchment: the main action on its own row, the others share the row below.
            self.open:ClearAllPoints()
            self.open:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x, 22 + 44)
            self.open:SetWidth(width)
            local others = #buttons - 1 + 1
            local each = math.floor((width - (others - 1) * 8) / others)
            for index = 2, #buttons do
                buttons[index]:ClearAllPoints()
                buttons[index]:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x + (index - 2) * (each + 8), 22)
                buttons[index]:SetWidth(each)
            end
            self.forget:SetWidth(each)
        else
            local used = self.forget:Fit(90, 200) + 10
            for index = 2, #buttons do used = used + buttons[index]:Fit(90, 200) + 10 end
            self.open:SetWidth(math.max(140, width - used))
            for index, button in ipairs(buttons) do
                button:ClearAllPoints()
                button:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x, 22)
                x = x + button:GetWidth() + 10
            end
        end
        self.forget:ClearAllPoints()
        self.forget:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMLEFT", self.leftWidth + 26 + width, 22)
    end
end

function Shelf:FillRow(row, item)
    if item.kind == "TALE" then
        local entry = I:Entry(item.id)
        local tale, progress = entry.tale, I:ProgressOf(item.id)
        local palette = T.modes[tale.mode] or T.modes.NOTES
        T.Color(row.tile, palette[1])
        row.icon:SetTexture(palette[3])
        row.title:SetText(tale.title)
        row.value:SetText(Tab.ProgressText(tale, progress))
        T.TextColor(row.value, progress and progress.finishedAt and "success" or progress and "gold" or "muted")
        row.chips[1]:Set(Tab.ModeName(tale.mode), palette[1], palette[2])
        row.chips[2]:Set(L()["INK_ORDER_" .. tale.order], "track", "textSoft")
        row.chips[3]:Set(string.format(L().INK_BY_AUTHOR, tale.author), false, "muted")
    else
        local draft = I.Workshop:Draft(item.id)
        local palette = T.modes[draft.mode] or T.modes.NOTES
        T.Color(row.tile, "track")
        row.icon:SetTexture(palette[3])
        row.title:SetText(I.Tale.Line(draft.title, I.Tale.titleBytes) or L().INK_UNTITLED)
        row.value:SetText(string.format(L().INK_PAGES_COUNT, #draft.pages))
        T.TextColor(row.value, "muted")
        row.chips[1]:Set(Tab.ModeName(draft.mode), palette[1], palette[2])
        row.chips[2]:Set(draft.baseVersion > 0 and string.format(L().INK_DRAFT_SEALED_VERSION, draft.baseVersion)
            or L().INK_DRAFT_NEVER_SEALED, "track", "textSoft")
        row.chips[3]:Set(nil)
    end
end

function Shelf:Closed() if self.forget then self.forget:Reset() end end
