local MS = _G.MS
MS.Ink = MS.Ink or {}
-- The quill's workshop in the Ink tab: the tale's table of contents on the left (title, mode,
-- order, prologue, pages, ending), the selected part on parchment on the right, and what is still
-- missing next to Try and Seal. Every field writes into the draft as the author types.
local A = MS.Active
local I = MS.Ink
local T = I.Theme
local Tab = I.Tab

local function L() return MS.L end

local Atelier = { rows = {}, offset = 0 }
Tab.panes.WORKSHOP = Atelier
I.Atelier = Atelier
Atelier.radii = { 3, 5, 8, 12, 20, 30, 50, 80, 120, 200 }
Atelier.side = 320

function Atelier:Draft() return self.draftId and I.Workshop:Draft(self.draftId) or nil end

function Atelier:Page()
    local draft = self:Draft()
    if not draft or self.selected == "INTRO" or self.selected == "ENDING" then return nil, nil, draft end
    local page, index = I.Draft.Page(draft, self.selected)
    return page, index, draft
end

local function Edit(apply)
    return function(text)
        local draft = Atelier:Draft()
        if not draft then return end
        apply(draft, text)
        I.Workshop:Touch(draft)
        Atelier.feedback = nil
        Atelier:Status()
    end
end

local function EditPage(apply)
    return function(text)
        local page, _, draft = Atelier:Page()
        if not page then return end
        apply(page, text)
        I.Workshop:Touch(draft)
        Atelier.feedback = nil
        Atelier:Status()
        Atelier:RefreshRows()
    end
end

function Atelier:Build(frame)
    local Tl = I.Tale
    -- Left: the table of contents.
    self.sideBack = frame:CreateTexture(nil, "BORDER")
    T.Color(self.sideBack, "shellDeep")
    self.sideRule = frame:CreateTexture(nil, "BORDER")
    T.Color(self.sideRule, "lineSoft")
    self.back = T.Button(frame, "GHOST", L().INK_BACK_DRAFTS, function() Tab:Show("SHELF", "DRAFTS") end, 110, 26)
    self.titleLabel = T.Text(frame, "UI", 12, "muted")
    self.titleLabel:SetText(L().INK_FIELD_TITLE)
    self.title = T.Line(frame, "TITLE", 19, Tl.titleBytes, L().INK_UNTITLED, Edit(function(d, text) d.title = text end))
    self.modes = T.Segmented(frame, { { value = "NOTES", label = L().INK_MODE_SHORT_NOTES },
        { value = "HUNT", label = L().INK_MODE_SHORT_HUNT }, { value = "QUEST", label = L().INK_MODE_SHORT_QUEST } },
        function(value) Atelier:Set("mode", value) end)
    self.orderLabel = T.Text(frame, "UI", 14, "textSoft")
    self.orderLabel:SetText(L().INK_ORDER_SWITCH)
    self.order = T.Switch(frame, function(on) Atelier:Set("order", on and "SEQUENCE" or "FREE") end)
    self.list = CreateFrame("Frame", nil, frame)
    self.list:EnableMouseWheel(true)
    self.list:SetScript("OnMouseWheel", function(_, delta) Atelier:Scroll(-delta) end)
    self.pagesLabel = T.Text(self.list, "UI", 12, "muted")
    self.thumb = T.Thumb(self.list)
    self.adds = {}
    for _, kind in ipairs(Tl.kinds) do
        self.adds[kind] = T.Button(frame, "DASHED", L()["INK_ADD_" .. kind], function() Atelier:Add(kind) end, 90, 32)
    end
    -- Right: the part being written.
    self.sheet = T.Parchment(frame)
    local sheet = self.sheet
    self.kicker = T.Text(sheet, "UI", 13, "inkSoft")
    self.up = T.Button(sheet, "PAPER", "‹", function() Atelier:Move(-1) end, 30, 26)
    self.down = T.Button(sheet, "PAPER", "›", function() Atelier:Move(1) end, 30, 26)
    self.remove = T.Confirm(sheet, "PAPER", L().INK_REMOVE_PAGE, L().INK_FORGET_CONFIRM, function() Atelier:Remove() end, 130, 26)
    self.pageTitle = T.Line(sheet, "TITLE", 20, Tl.titleBytes, L().INK_FIELD_PAGE_TITLE, EditPage(function(p, text) p.title = text end), true)
    self.hintLabel = T.Text(sheet, "UI", 13, "inkSoft")
    self.hintLabel:SetText(L().INK_FIELD_HINT)
    self.hint = T.Multi(sheet, "INK_ITALIC", 16, Tl.hintBytes, "", EditPage(function(p, text) p.hint = text end), true)
    self.textLabel = T.Text(sheet, "UI", 13, "inkSoft")
    self.textLabel:SetText(L().INK_FIELD_TEXT)
    self.text = T.Multi(sheet, "INK", 16, Tl.textBytes, "", EditPage(function(p, text) p.text = text end), true)
    self.prose = T.Multi(sheet, "INK", 17, Tl.introBytes, "", function(text)
        local draft = Atelier:Draft()
        if not draft then return end
        if Atelier.selected == "INTRO" then draft.intro = text else draft.ending = text end
        I.Workshop:Touch(draft)
        Atelier:RefreshRows()
    end, true)
    -- The trigger card.
    self.card = T.Box(frame, "raised", "lineSoft")
    local card = self.card
    self.mapTile = card:CreateTexture(nil, "ARTWORK")
    T.Color(self.mapTile, { .125, .196, .227, 1 })
    self.ring = card:CreateTexture(nil, "OVERLAY")
    self.ring:SetTexture(T.halo)
    self.ring:SetVertexColor(.85, .65, .29, 1)
    self.dot = T.Disc(card, 8, "text", "OVERLAY")
    self.where = T.Text(card, "UI_BOLD", 15, "text")
    T.MaxLines(self.where, 2)
    self.distance = T.Text(card, "UI", 13, "success", "RIGHT")
    if type(self.distance.SetWordWrap) == "function" then self.distance:SetWordWrap(false) end
    self.radiusLabel = T.Text(card, "UI", 14, "textSoft")
    self.radiusLabel:SetText(L().INK_RADIUS_LABEL)
    self.less = T.Button(card, "SECONDARY", "-", function() Atelier:Step(-1) end, 28, 26)
    self.track = card:CreateTexture(nil, "ARTWORK")
    T.Color(self.track, "track")
    self.fill = card:CreateTexture(nil, "ARTWORK")
    T.Color(self.fill, "gold")
    self.more = T.Button(card, "SECONDARY", "+", function() Atelier:Step(1) end, 28, 26)
    self.amount = T.Text(card, "UI", 14, "text", "RIGHT")
    self.placeHere = T.Button(card, "SECONDARY", L().INK_PLACE_HERE, function() Atelier:PlaceHere() end, 130, 30)
    self.seeMap = T.Button(card, "GHOST", L().INK_SEE_ON_MAP, function() Atelier:SeeOnMap() end, 130, 30)
    self.answersLabel = T.Text(card, "UI", 13, "muted")
    self.answersLabel:SetText(L().INK_FIELD_ANSWERS)
    self.answers = T.Line(card, "UI", 16, I.Draft.maxAnswerText, L().INK_ANSWERS_EXAMPLE, EditPage(function(p, text) p.trigger.answers = text end))
    self.itemIcon = T.Icon(card, 40, nil)
    self.itemLabel = T.Text(card, "UI", 13, "muted")
    self.itemLabel:SetText(L().INK_FIELD_ITEM)
    self.item = T.Line(card, "UI", 16, 120, L().INK_ITEM_EXAMPLE, function(text) Atelier:ItemTyped(text) end)
    self.help = T.Text(card, "UI", 13, "muted")
    -- People, emotes and kills: who, where, how many.
    self.emotePrevious = T.Button(card, "SECONDARY", "‹", function() Atelier:Emote(-1) end, 28, 26)
    self.emoteNext = T.Button(card, "SECONDARY", "›", function() Atelier:Emote(1) end, 28, 26)
    self.detail = T.Text(card, "UI", 14, "textSoft")
    self.take = T.Button(card, "SECONDARY", L().INK_TAKE_TARGET, function() Atelier:TakeTarget() end, 160, 30)
    self.clear = T.Button(card, "GHOST", L().INK_CLEAR_DEED, function() Atelier:ClearDeed() end, 100, 30)
    -- What else the page asks: an hour, a level.
    self.strip = T.Box(frame, "raised", "lineSoft")
    self.whenLabel = T.Text(self.strip, "UI", 14, "textSoft")
    self.whenLabel:SetText(L().INK_WHEN_LABEL)
    self.hours = T.Button(self.strip, "SECONDARY", "", function() Atelier:NextHours() end, 150, 28)
    if type(self.hours.label.SetWordWrap) == "function" then self.hours.label:SetWordWrap(false) end
    self.levelLabel = T.Text(self.strip, "UI", 14, "textSoft")
    self.levelLabel:SetText(L().INK_WHEN_LEVEL)
    self.level = T.Line(self.strip, "UI", 14, 2, "-", function(text) Atelier:LevelTyped(text) end)
    -- The footer.
    self.footBack = frame:CreateTexture(nil, "BORDER")
    T.Color(self.footBack, "shellDeep")
    self.footRule = frame:CreateTexture(nil, "ARTWORK")
    T.Color(self.footRule, "lineSoft")
    self.status = T.Text(frame, "UI", 14, "warning")
    if type(self.status.SetWordWrap) == "function" then self.status:SetWordWrap(false) end
    self.try = T.Button(frame, "SECONDARY", L().INK_TRY_ACTION, function() Atelier:Seal(true) end, 110, 36)
    self.seal = T.Button(frame, "PRIMARY", L().INK_SEAL_ACTION, function() Atelier:Seal(false) end, 120, 36)
    Atelier.HookLinks()
end

function Atelier:Open(id, selected)
    self.draftId, self.offset, self.feedback, self.reveal = id, 0, nil, true
    local draft = self:Draft()
    self.selected = selected or (draft and draft.pages[1] and draft.pages[1].key) or "INTRO"
    if self.remove then self.remove:Reset() end
end

-- Rows of the table of contents -----------------------------------------------------------------
function Atelier:Row(index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, self.list)
    row:SetHeight(32)
    row.hovered = false
    row.back = T.Fill(row, "selected")
    row.mark = row:CreateTexture(nil, "BORDER")
    row.mark:SetPoint("TOPLEFT", row, "TOPLEFT")
    row.mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
    row.mark:SetWidth(2)
    T.Color(row.mark, "gold")
    row.number = T.Text(row, "UI", 13, "muted")
    row.number:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.icon = T.Icon(row, 18, nil)
    row.icon:SetPoint("LEFT", row, "LEFT", 32, 0)
    row.label = T.Text(row, "UI", 14, "text")
    row.label:SetPoint("LEFT", row, "LEFT", 58, 0)
    if type(row.label.SetWordWrap) == "function" then row.label:SetWordWrap(false) end
    row.note = T.Text(row, "UI", 12, "muted", "RIGHT")
    row.note:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.warn = T.Disc(row, 8, "warning", "OVERLAY")
    row.warn:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row:SetScript("OnEnter", function(self) self.hovered = true; Atelier.PaintRow(self) end)
    row:SetScript("OnLeave", function(self) self.hovered = false; Atelier.PaintRow(self) end)
    row:SetScript("OnClick", function(self) Atelier:Select(self.target) end)
    self.rows[index] = row
    return row
end

function Atelier.PaintRow(row)
    local on = row.target == Atelier.selected
    row.back:SetShown(on or row.hovered == true)
    T.Color(row.back, on and "selected" or "raised")
    row.mark:SetShown(on)
    T.SetFont(row.label, on and "UI_BOLD" or "UI", 14)
    T.TextColor(row.number, on and "gold" or "muted")
end

function Atelier:Select(target)
    if not target then return end
    self.selected = target
    self.reveal = true
    if self.remove then self.remove:Reset() end
    self.feedback = nil
    Tab:Refresh()
end

-- A page lacks what sealing needs: the dot in the table of contents.
local function Missing(page)
    if not I.Tale.Line(page.title, I.Tale.titleBytes) then return true end
    local trigger = page.trigger
    if trigger.kind == "PLACE" then return trigger.mapID == nil end
    if trigger.kind == "ITEM" then return trigger.itemID == nil end
    if trigger.kind == "NPC" or trigger.kind == "KILL" then return trigger.npcID == nil end
    if trigger.kind == "EMOTE" then return false end
    return #I.Draft.Answers(trigger.answers) == 0 and not trigger.hashes
end

function Atelier:Entries()
    local draft = self:Draft()
    local entries = { { target = "INTRO", label = L().INK_PROLOGUE, note = draft.intro ~= "" and string.format(L().INK_CHARS, #draft.intro) or L().INK_EMPTY_PART } }
    entries[#entries + 1] = { header = true }
    for index, page in ipairs(draft.pages) do
        entries[#entries + 1] = { target = page.key, number = index, kind = page.trigger.kind,
            label = I.Tale.Line(page.title, I.Tale.titleBytes) or L().INK_UNTITLED, warn = Missing(page) }
    end
    entries[#entries + 1] = { target = "ENDING", label = L().INK_ENDING, note = draft.ending ~= "" and string.format(L().INK_CHARS, #draft.ending) or L().INK_EMPTY_PART }
    return entries
end

function Atelier:Scroll(delta)
    self.offset = math.max(0, self.offset + delta)
    self:RefreshRows()
end

function Atelier:RefreshRows()
    local draft = self:Draft()
    if not draft or not self.listHeight then return end
    local entries = self:Entries()
    local fit = math.max(1, math.floor(self.listHeight / 34))
    if self.reveal then
        -- The part being written stays in view (a page just added, a move, a low list).
        self.reveal = nil
        for index, entry in ipairs(entries) do
            if entry.target == self.selected then
                if index <= self.offset then self.offset = index - 1
                elseif index > self.offset + fit then self.offset = index - fit end
            end
        end
    end
    self.offset = math.max(0, math.min(self.offset, #entries - fit))
    self.thumb:Set(self.list, fit * 34, self.offset, fit, #entries, 0)
    local y, used = 0, 0
    self.pagesLabel:Hide()
    for index = 1, math.max(#self.rows, fit) do
        local entry = entries[index + self.offset]
        if index > fit then entry = nil end
        local row = (entry and not entry.header) and self:Row(index) or self.rows[index]
        if row then row:Hide() end
        if entry and entry.header then
            self.pagesLabel:ClearAllPoints()
            self.pagesLabel:SetPoint("TOPLEFT", self.list, "TOPLEFT", 10, -y - 12)
            self.pagesLabel:SetText(string.format(L().INK_PAGES_HEADER, #draft.pages, I.Tale.maxPages))
            self.pagesLabel:Show()
        elseif entry then
            row:Show()
            row.target = entry.target
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -y)
            row:SetWidth(self.listWidth)
            row.number:SetText(entry.number and tostring(entry.number) or "")
            row.icon:SetShown(true)
            row.icon:SetTexture(entry.kind and T.kinds[entry.kind][2] or T.modes.NOTES[3])
            row.label:SetText(entry.label)
            row.label:SetWidth(self.listWidth - 58 - 70)
            row.note:SetText(entry.note or "")
            row.note:SetShown(entry.note ~= nil)
            row.warn:SetShown(entry.warn == true)
            Atelier.PaintRow(row)
        end
        if entry then y, used = y + 34, used + 1 end
    end
end

-- Choices of the tale ------------------------------------------------------------------------------
function Atelier:Set(field, value)
    local draft = self:Draft()
    if not draft then return end
    draft[field] = value
    I.Workshop:Touch(draft)
    Tab:Refresh()
end

function Atelier:Add(kind)
    local draft = self:Draft()
    if not draft then return end
    local page = I.Draft.AddPage(draft, kind)
    if not page then
        self.feedback = { L().INK_DRAFT_FULL, "warning" }
        return Tab:Refresh()
    end
    I.Workshop:Touch(draft)
    -- A place page starts where the author stands, when the game says where that is.
    if kind == "PLACE" then I.Workshop:PlaceHere(draft, page) end
    -- Someone already targeted is who the page is about.
    if kind == "NPC" or kind == "KILL" then I.Workshop:TakeTarget(draft, page) end
    self.selected = page.key
    self.offset = math.max(0, #draft.pages + 3 - math.floor((self.listHeight or 300) / 34))
    Tab:Refresh()
end

function Atelier:Move(delta)
    local _, _, draft = self:Page()
    if draft and I.Draft.Move(draft, self.selected, delta) then
        I.Workshop:Touch(draft)
        Tab:Refresh()
    end
end

function Atelier:Remove()
    local _, index, draft = self:Page()
    if draft and I.Draft.Remove(draft, self.selected) then
        I.Workshop:Touch(draft)
        local neighbour = draft.pages[math.min(index, #draft.pages)]
        self.selected = neighbour and neighbour.key or "INTRO"
        Tab:Refresh()
    end
end

function Atelier:PlaceHere()
    local page, _, draft = self:Page()
    if not page then return end
    local ok, result = I.Workshop:PlaceHere(draft, page)
    self.feedback = ok and { L().INK_PLACED, "success" } or { L()["INK_PLACE_" .. tostring(result)] or L().INK_PLACE_NO_POSITION, "warning" }
    Tab:Refresh()
end

function Atelier:TakeTarget()
    local page, _, draft = self:Page()
    if not page then return end
    local ok, reason = I.Workshop:TakeTarget(draft, page)
    self.feedback = not ok and { L()["INK_TARGET_" .. reason], "warning" } or nil
    Tab:Refresh()
end

function Atelier:ClearDeed()
    local page, _, draft = self:Page()
    if not page or page.trigger.kind ~= "EMOTE" then return end
    I.Workshop:ClearDeed(draft, page)
    self.feedback = nil
    Tab:Refresh()
end

-- The next emote of the list, round and round.
function Atelier:Emote(delta)
    local page, _, draft = self:Page()
    if not page or page.trigger.kind ~= "EMOTE" then return end
    local list, at = I.Deeds.emotes, 1
    for index, token in ipairs(list) do if token == page.trigger.token then at = index end end
    page.trigger.token = list[(at - 1 + delta) % #list + 1]
    I.Workshop:Touch(draft)
    Tab:Refresh()
end

-- Times of day offered to the author: from, to (realm hours).
Atelier.times = { { "ANY" }, { "DAY", 6, 20 }, { "NIGHT", 20, 6 }, { "DAWN", 5, 8 }, { "DUSK", 18, 21 }, { "MIDNIGHT", 0, 1 } }

local function TimeIndex(when)
    for index, time in ipairs(Atelier.times) do
        if time[2] == (when and when.from) and time[3] == (when and when.to) then return index end
    end
end

function Atelier:NextHours()
    local page, _, draft = self:Page()
    if not page then return end
    local time = self.times[(TimeIndex(page.when) or 0) % #self.times + 1]
    page.when = I.Tale.SanitizeWhen({ from = time[2], to = time[3], level = page.when and page.when.level })
    I.Workshop:Touch(draft)
    Tab:Refresh()
end

function Atelier:LevelTyped(text)
    local page, _, draft = self:Page()
    if not page then return end
    page.when = I.Tale.SanitizeWhen({ from = page.when and page.when.from, to = page.when and page.when.to, level = tonumber(text) })
    I.Workshop:Touch(draft)
end

function Atelier:RefreshWhen(page)
    local strip, index = self.strip, TimeIndex(page.when)
    local width = self.cardWidth
    local wide = width >= 520
    self.whenLabel:SetShown(wide)
    self.whenLabel:ClearAllPoints()
    self.whenLabel:SetPoint("LEFT", strip, "LEFT", 18, 0)
    self.level:ClearAllPoints()
    self.level:SetPoint("RIGHT", strip, "RIGHT", -18, 0)
    self.level:SetWidth(28)
    if not self.level:HasFocus() then self.level:SetValue(page.when and page.when.level and tostring(page.when.level) or "") end
    self.levelLabel:ClearAllPoints()
    self.levelLabel:SetPoint("RIGHT", self.level, "LEFT", -8, 0)
    self.hours:SetLabel(index and L()["INK_TIME_" .. self.times[index][1]] or Tab.Hours(page.when))
    self.hours:ClearAllPoints()
    local left = wide and 18 + T.Width(self.whenLabel) + 12 or 12
    self.hours:SetPoint("LEFT", strip, "LEFT", left, 0)
    self.hours:Fit(80, math.max(80, width - left - 18 - 28 - 8 - T.Width(self.levelLabel) - 12))
end

-- The Journey map on this page's zone: the layer there shows every place of the draft while
-- the workshop stays open on it.
function Atelier:SeeOnMap()
    local page = self:Page()
    local journey, map = MS.JourneyWorkspace, MS.MapView
    if not page or not page.trigger.mapID or not journey or not map or not map.Navigate then return false end
    if not journey:SelectView("MAP") then return false end
    map:Navigate(page.trigger.mapID)
    if I.MapLayer then I.MapLayer:Changed() end
    return true
end

local function Index(list, value)
    for index, entry in ipairs(list) do if entry >= value then return index end end
    return #list
end

-- - / +: the radius of a place, or how many of an item.
function Atelier:Step(delta)
    local page, _, draft = self:Page()
    if not page then return end
    local trigger = page.trigger
    if trigger.kind == "PLACE" then
        trigger.radius = self.radii[math.max(1, math.min(#self.radii, Index(self.radii, trigger.radius) + delta))]
    elseif trigger.kind == "ITEM" then
        trigger.count = math.max(1, math.min(I.Tale.maxItemCount, trigger.count + delta))
    elseif trigger.kind == "KILL" then
        trigger.count = math.max(1, math.min(I.Tale.maxKills, trigger.count + delta))
    end
    I.Workshop:Touch(draft)
    Tab:Refresh()
end

-- An item number or a link ("|Hitem:6948:...|h"). Anything else leaves the item unset.
function Atelier.ParseItem(text)
    if type(text) ~= "string" then return nil end
    local id = tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
    if id and id >= 1 and id <= 4294967295 then return id end
end

function Atelier:ItemTyped(text)
    local page, _, draft = self:Page()
    if not page or page.trigger.kind ~= "ITEM" then return end
    page.trigger.itemID = Atelier.ParseItem(text)
    I.Workshop:Touch(draft)
    self:RefreshCard(page)
    self:RefreshRows()
    self:Status()
end

-- Shift-click on an item while an item page is open writes its link into the item field. The
-- click on the bag can take the focus away from the field, so the open field is what counts,
-- unless the chat box is being typed in. Each path a client may use is only observed.
function Atelier.OfferLink(link)
    local field = Atelier.item
    if type(link) ~= "string" or not link:find("item:%d+") or not field or not field:IsVisible() then return end
    local chat = type(_G.ChatEdit_GetActiveWindow) == "function" and A.Call(_G.ChatEdit_GetActiveWindow)
    if chat and chat ~= field then return end
    field:SetValue(link)
    Atelier:ItemTyped(link)
    field:SetValue(tostring(Atelier.ParseItem(link) or ""))
end

function Atelier.HookLinks()
    if Atelier.linksHooked or type(_G.hooksecurefunc) ~= "function" then return end
    Atelier.linksHooked = true
    for _, name in ipairs({ "ChatEdit_InsertLink", "HandleModifiedItemClick" }) do
        if type(_G[name]) == "function" then pcall(_G.hooksecurefunc, name, Atelier.OfferLink) end
    end
    if type(_G.ChatFrameUtil) == "table" and type(_G.ChatFrameUtil.InsertLink) == "function" then
        pcall(_G.hooksecurefunc, _G.ChatFrameUtil, "InsertLink", Atelier.OfferLink)
    end
end

-- Sealing ---------------------------------------------------------------------------------------------
function Atelier.Reason(reason, index)
    local text = L()["INK_SEAL_" .. tostring(reason)] or L().INK_SEAL_INVALID
    return index and string.format(text, index) or text
end

function Atelier:Seal(try)
    local draft = self:Draft()
    if not draft then return end
    local tale, seal, index = I.Workshop:Seal(draft, try)
    if not tale then
        self.feedback = { Atelier.Reason(seal, index), "warning" }
        return self:Status()
    end
    if try then return Tab:Show("BOOK", tale.id) end
    local message = string.format(L().INK_SEALED, tale.version, #seal)
    if #seal > 2000 then message = message .. " " .. L().INK_SEAL_LONG end
    self.feedback = { message, #seal > 2000 and "warning" or "success" }
    self:Status()
    MS.Diagnostics:ShowCopyableReport(L().INK_SHARE_TITLE, seal, "INK_SEAL", string.format(L().INK_SHARE_INSTRUCTION, #seal))
end

-- The footer says the latest result, else what still keeps the tale from being sealed.
function Atelier:Status()
    local draft = self:Draft()
    if not draft or not self.status then return end
    if self.feedback then
        self.status:SetText(self.feedback[1])
        T.TextColor(self.status, self.feedback[2])
        return
    end
    local tale, reason, index = I.Draft.ToTale(draft, A.Now())
    if tale then
        self.status:SetText(L().INK_READY_TO_SEAL)
        T.TextColor(self.status, "success")
    else
        self.status:SetText(Atelier.Reason(reason, index))
        T.TextColor(self.status, "warning")
    end
end

-- Layout -------------------------------------------------------------------------------------------
function Atelier:Lay(width, height)
    local frame, side = self.frame, self.side
    self.width, self.height = width, height
    local footer = 64
    self.sideBack:ClearAllPoints()
    self.sideBack:SetPoint("TOPLEFT", frame, "TOPLEFT")
    self.sideBack:SetSize(side, height)
    self.sideRule:ClearAllPoints()
    self.sideRule:SetPoint("TOPLEFT", frame, "TOPLEFT", side, 0)
    self.sideRule:SetSize(1, height)
    -- A low tab: no label above the title (the field says what it is), tighter rows.
    local low = height < 520
    self.back:ClearAllPoints()
    self.back:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, low and -8 or -14)
    self.back:Fit(90, 200)
    local y = low and 38 or 68
    self.titleLabel:SetShown(not low)
    self.titleLabel:ClearAllPoints()
    self.titleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -52)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -y)
    self.title:SetWidth(side - 44)
    y = y + (low and 40 or 44)
    self.modes:ClearAllPoints()
    self.modes:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -y)
    self.modes:Lay(side - 44)
    y = y + (low and 40 or 48)
    self.orderLabel:ClearAllPoints()
    self.orderLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -y)
    self.orderLabel:SetWidth(side - 100)
    if type(self.orderLabel.SetWordWrap) == "function" then self.orderLabel:SetWordWrap(false) end
    self.order:ClearAllPoints()
    self.order:SetPoint("TOPRIGHT", frame, "TOPLEFT", side - 22, -y + 2)
    y = y + (low and 28 or 34)
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -y)
    self.listWidth, self.listHeight = side - 24, height - y - (low and 72 or 98)
    self.list:SetSize(self.listWidth, self.listHeight)
    if self.laidHeight ~= self.listHeight then self.laidHeight, self.reveal = self.listHeight, true end
    local each = math.floor((side - 24 - 12) / 3)
    for index, kind in ipairs(I.Tale.kinds) do
        local button, column = self.adds[kind], (index - 1) % 3
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12 + column * (each + 6),
            (low and 8 or 16) + (index <= 3 and (low and 30 or 38) or 0))
        button:SetSize(each, low and 26 or 32)
    end
    -- Right.
    local left, pad = side + 26, 26
    local room = width - left - pad
    -- The trigger card sits under the sheet when the tab is tall; beside it when the tab is low
    -- and wide enough, so the sheet keeps the whole height for writing.
    local beside = height < 620 and room >= 640
    local cardWidth = beside and math.max(260, math.min(320, math.floor(room * .34))) or 0
    local inner = beside and math.min(760, room - cardWidth - 14) or math.min(760, room)
    self.inner, self.beside = inner, beside
    self.footBack:ClearAllPoints()
    self.footBack:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", side + 1, 0)
    self.footBack:SetSize(width - side - 1, footer)
    self.footRule:ClearAllPoints()
    self.footRule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", side + 1, footer)
    self.footRule:SetSize(width - side - 1, 1)
    self.seal:ClearAllPoints()
    self.seal:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, 14)
    self.seal:Fit(110, 200)
    self.try:ClearAllPoints()
    self.try:SetPoint("RIGHT", self.seal, "LEFT", -10, 0)
    self.try:Fit(100, 200)
    self.status:ClearAllPoints()
    self.status:SetPoint("LEFT", frame, "BOTTOMLEFT", left, footer / 2)
    self.status:SetWidth(math.max(80, width - left - pad - self.seal:GetWidth() - self.try:GetWidth() - 30))
    local top = height < 420 and 14 or 22
    local full = height - top - footer - 16
    local strip = 44
    local cardHeight = beside and full - strip - 8 or 140
    local sheetHeight = beside and full or full - cardHeight - 14 - strip - 8
    local used = beside and inner + 14 + cardWidth or inner
    self.sheet:ClearAllPoints()
    -- A wide screen centres the sheet in the room right of the table of contents.
    self.sheet:SetPoint("TOPLEFT", frame, "TOPLEFT", left + math.max(0, math.floor((room - used) / 2)), -top)
    self.card:ClearAllPoints()
    if beside then
        self.card:SetPoint("TOPLEFT", self.sheet, "TOPRIGHT", 14, 0)
        self.card:SetSize(cardWidth, cardHeight)
    else
        self.card:SetPoint("TOPLEFT", self.sheet, "BOTTOMLEFT", 0, -14)
        self.card:SetSize(inner, cardHeight)
    end
    self.strip:ClearAllPoints()
    self.strip:SetPoint("TOPLEFT", self.card, "BOTTOMLEFT", 0, -8)
    self.strip:SetSize(beside and cardWidth or inner, strip)
    self.cardWidth, self.cardHeight, self.sheetHeight, self.fullHeight = beside and cardWidth or inner, cardHeight, sheetHeight, full
end

function Atelier:LaySheet(page)
    local sheet, inner = self.sheet, self.inner
    local height = page and self.sheetHeight or self.fullHeight
    -- The prologue and the ending have no trigger card: the sheet takes its place too.
    if not page and self.beside then inner = inner + 14 + self.cardWidth end
    sheet:SetSize(inner, height)
    local w = inner - 48
    self.kicker:ClearAllPoints()
    self.kicker:SetPoint("TOPLEFT", sheet, "TOPLEFT", 24, -20)
    if type(self.kicker.SetWordWrap) == "function" then self.kicker:SetWordWrap(false) end
    self.remove:ClearAllPoints()
    self.remove:SetPoint("TOPRIGHT", sheet, "TOPRIGHT", -20, -14)
    self.remove:Fit(100, 180)
    self.down:ClearAllPoints()
    self.down:SetPoint("RIGHT", self.remove, "LEFT", -6, 0)
    self.up:ClearAllPoints()
    self.up:SetPoint("RIGHT", self.down, "LEFT", -4, 0)
    self.kicker:SetWidth(math.max(60, w - (page and self.remove:GetWidth() + 80 or 0)))
    if page then
        self.pageTitle:ClearAllPoints()
        self.pageTitle:SetPoint("TOPLEFT", sheet, "TOPLEFT", 24, -46)
        self.pageTitle:SetWidth(w)
        local label = T.LineHeight(13) + 4
        local fields = height - 46 - 36 - 12 - 20
        for _, text in ipairs({ self.hintLabel, self.textLabel }) do
            if type(text.SetWordWrap) == "function" then text:SetWordWrap(false) end
        end
        self.hintLabel:ClearAllPoints()
        self.hintLabel:SetPoint("TOPLEFT", self.pageTitle, "BOTTOMLEFT", 0, -12)
        self.hint:ClearAllPoints()
        self.hint:SetPoint("TOPLEFT", self.hintLabel, "BOTTOMLEFT", 0, -4)
        self.textLabel:ClearAllPoints()
        self.text:ClearAllPoints()
        self.text:SetPoint("TOPLEFT", self.textLabel, "BOTTOMLEFT", 0, -4)
        if fields < 2 * label + 10 + 150 and w >= 300 then
            -- A low sheet: the hint and the text side by side rather than two slivers.
            local hintWidth = math.floor((w - 14) * .4)
            local fieldHeight = math.max(40, fields - label)
            self.hintLabel:SetWidth(hintWidth)
            self.hint:Lay(hintWidth, fieldHeight)
            self.textLabel:SetPoint("TOPLEFT", self.hintLabel, "TOPLEFT", hintWidth + 14, 0)
            self.textLabel:SetWidth(w - hintWidth - 14)
            self.text:Lay(w - hintWidth - 14, fieldHeight)
        else
            local rest = fields - 2 * label - 10
            local hintHeight = math.max(40, math.floor(rest * .32))
            self.hintLabel:SetWidth(w)
            self.hint:Lay(w, hintHeight)
            self.textLabel:SetPoint("TOPLEFT", self.hint, "BOTTOMLEFT", 0, -10)
            self.textLabel:SetWidth(w)
            self.text:Lay(w, math.max(40, rest - hintHeight))
        end
    else
        self.prose:ClearAllPoints()
        self.prose:SetPoint("TOPLEFT", sheet, "TOPLEFT", 24, -50)
        self.prose:Lay(w, height - 50 - 24)
    end
end

function Atelier:RefreshCard(page)
    local trigger, card, inner = page.trigger, self.card, self.cardWidth
    local beside = self.beside
    local place, answer, item = trigger.kind == "PLACE", trigger.kind == "ANSWER", trigger.kind == "ITEM"
    local emote, kill = trigger.kind == "EMOTE", trigger.kind == "KILL"
    local deed = emote or kill or trigger.kind == "NPC"
    for _, region in ipairs({ self.distance, self.radiusLabel, self.track, self.fill }) do
        region:SetShown(place)
    end
    self.placeHere:SetShown(place or emote)
    self.emotePrevious:SetShown(emote)
    self.emoteNext:SetShown(emote)
    self.detail:SetShown(emote)
    self.take:SetShown(deed)
    self.clear:SetShown(emote and (trigger.npcID ~= nil or trigger.mapID ~= nil))
    -- Beside the sheet the card is narrow: the little map gives its place to the controls.
    for _, region in ipairs({ self.mapTile, self.ring, self.dot }) do region:SetShown(place and not beside) end
    self.seeMap:SetShown(place and trigger.mapID ~= nil and MS.MapView ~= nil)
    self.less:SetShown(place or item or kill)
    self.more:SetShown(place or item or kill)
    self.amount:SetShown(place or item or kill)
    self.answersLabel:SetShown(answer)
    self.answers:SetShown(answer)
    self.itemIcon:SetShown(item or deed)
    self.itemLabel:SetShown(item)
    self.item:SetShown(item)
    self.where:SetShown(place or item or deed)
    self.help:SetShown(answer or item or deed)
    local x = (place and not beside) and 140 or (item or deed) and 72 or 18
    local w = inner - x - 18
    self.where:ClearAllPoints()
    self.where:SetPoint("TOPLEFT", card, "TOPLEFT", x, -18)
    self.where:SetWidth(beside and w or w - 150)
    -- Under the sheet the rows of the card sit at fixed heights: the name keeps one line there.
    T.MaxLines(self.where, beside and 2 or 1)
    if deed then return self:RefreshDeed(page, w) end
    if place and beside then
        self.where:SetText(trigger.mapID and string.format(L().INK_PLACE_AT_SHORT, A.Position:MapName(trigger.mapID) or L().SEAL_SOMEWHERE,
            trigger.x * 100, trigger.y * 100) or L().INK_PLACE_UNSET)
        -- Every row below starts from the real height of the name (one or two lines).
        local measured = self.where:GetStringHeight()
        local y = 18 + math.max(T.LineHeight(15), type(measured) == "number" and measured or 0) + 6
        self.distance:ClearAllPoints()
        self.distance:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
        self.distance:SetWidth(w)
        self.distance:SetJustifyH("LEFT")
        self:Distance(page)
        y = y + T.LineHeight(13) + 10
        local index = Index(self.radii, trigger.radius)
        self.radiusLabel:ClearAllPoints()
        self.radiusLabel:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
        self.amount:ClearAllPoints()
        self.amount:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -y)
        self.amount:SetWidth(80)
        self.amount:SetText(string.format(L().INK_RADIUS, trigger.radius))
        y = y + T.LineHeight(14) + 6
        self.less:ClearAllPoints()
        self.less:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
        local trackWidth = math.max(40, w - 28 - 28 - 16)
        self.track:ClearAllPoints()
        self.track:SetPoint("LEFT", self.less, "RIGHT", 8, 0)
        self.track:SetSize(trackWidth, 4)
        self.fill:ClearAllPoints()
        self.fill:SetPoint("LEFT", self.track, "LEFT")
        self.fill:SetSize(math.max(2, trackWidth * (index - 1) / (#self.radii - 1)), 4)
        self.more:ClearAllPoints()
        self.more:SetPoint("LEFT", self.track, "RIGHT", 8, 0)
        y = y + 26 + 12
        self.placeHere:ClearAllPoints()
        self.placeHere:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
        self.placeHere:Fit(110, w)
        self.seeMap:ClearAllPoints()
        if self.placeHere:GetWidth() + 8 + self.seeMap:Fit(100, w) <= w then
            self.seeMap:SetPoint("LEFT", self.placeHere, "RIGHT", 8, 0)
        else
            self.seeMap:SetPoint("TOPLEFT", self.placeHere, "BOTTOMLEFT", 0, -6)
            -- A card too low for a second row keeps the action that places the page.
            if y + 30 + 6 + 30 + 10 > self.cardHeight then self.seeMap:Hide() end
        end
    elseif place then
        self.distance:SetJustifyH("RIGHT")
        self.mapTile:ClearAllPoints()
        self.mapTile:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -14)
        self.mapTile:SetSize(110, 110)
        local index = Index(self.radii, trigger.radius)
        local ring = 24 + (index - 1) * 8
        self.ring:ClearAllPoints()
        self.ring:SetPoint("CENTER", self.mapTile, "CENTER")
        self.ring:SetSize(ring, ring)
        self.dot:ClearAllPoints()
        self.dot:SetPoint("CENTER", self.mapTile, "CENTER")
        self.where:SetText(trigger.mapID and string.format(L().INK_PLACE_AT_SHORT, A.Position:MapName(trigger.mapID) or L().SEAL_SOMEWHERE,
            trigger.x * 100, trigger.y * 100) or L().INK_PLACE_UNSET)
        self.distance:ClearAllPoints()
        self.distance:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -19)
        self.distance:SetWidth(140)
        self:Distance(page)
        self.radiusLabel:ClearAllPoints()
        self.radiusLabel:SetPoint("TOPLEFT", card, "TOPLEFT", x, -56)
        self.less:ClearAllPoints()
        self.less:SetPoint("TOPLEFT", card, "TOPLEFT", x + 60, -50)
        local trackWidth = math.max(60, w - 60 - 28 - 28 - 70 - 16)
        self.track:ClearAllPoints()
        self.track:SetPoint("LEFT", self.less, "RIGHT", 8, 0)
        self.track:SetSize(trackWidth, 4)
        self.fill:ClearAllPoints()
        self.fill:SetPoint("LEFT", self.track, "LEFT")
        self.fill:SetSize(math.max(2, trackWidth * (index - 1) / (#self.radii - 1)), 4)
        self.more:ClearAllPoints()
        self.more:SetPoint("LEFT", self.track, "RIGHT", 8, 0)
        self.amount:ClearAllPoints()
        self.amount:SetPoint("LEFT", self.more, "RIGHT", 8, 0)
        self.amount:SetWidth(60)
        self.amount:SetText(string.format(L().INK_RADIUS, trigger.radius))
        self.placeHere:ClearAllPoints()
        self.placeHere:SetPoint("TOPLEFT", card, "TOPLEFT", x, -92)
        self.placeHere:Fit(110, 220)
        self.seeMap:ClearAllPoints()
        self.seeMap:SetPoint("LEFT", self.placeHere, "RIGHT", 8, 0)
        self.seeMap:Fit(110, 220)
    elseif answer then
        self.answersLabel:ClearAllPoints()
        self.answersLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -18)
        self.answersLabel:SetWidth(inner - 36)
        T.MaxLines(self.answersLabel, 1)
        self.answers:ClearAllPoints()
        self.answers:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -38)
        self.answers:SetWidth(inner - 36)
        if not self.answers:HasFocus() then self.answers:SetValue(trigger.answers) end
        self.help:ClearAllPoints()
        self.help:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -86)
        self.help:SetWidth(inner - 36)
        self.help:SetText(trigger.hashes and #I.Draft.Answers(trigger.answers) == 0 and L().INK_ANSWER_KEPT or L().INK_ANSWER_HELP)
        T.MaxLines(self.help, math.max(1, math.floor((self.cardHeight - 86 - 12) / T.LineHeight(13))))
    else
        self.itemIcon:ClearAllPoints()
        self.itemIcon:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -18)
        self.itemIcon:SetTexture(trigger.itemID and Tab.ItemIcon(trigger.itemID) or T.kinds.ITEM[2])
        self.where:SetText(trigger.itemID and Tab.ItemName(trigger.itemID) or L().INK_ITEM_UNSET)
        self.itemLabel:ClearAllPoints()
        self.itemLabel:SetPoint("TOPLEFT", card, "TOPLEFT", x, -46)
        self.itemLabel:SetWidth(w)
        T.MaxLines(self.itemLabel, 1)
        self.item:ClearAllPoints()
        self.item:SetPoint("TOPLEFT", card, "TOPLEFT", x, -62)
        self.item:SetWidth(beside and w or math.max(70, w - 150))
        if not self.item:HasFocus() then self.item:SetValue(trigger.itemID and tostring(trigger.itemID) or "") end
        self.less:ClearAllPoints()
        -- Beside the sheet the card is narrow: how many goes on its own row under the field.
        if beside then self.less:SetPoint("TOPLEFT", card, "TOPLEFT", x, -104)
        else self.less:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18 - 28 - 8 - 50 - 8, -62) end
        self.amount:ClearAllPoints()
        self.amount:SetPoint("LEFT", self.less, "RIGHT", 8, 0)
        self.amount:SetWidth(50)
        self.amount:SetText(string.format("x %d", trigger.count))
        self.more:ClearAllPoints()
        self.more:SetPoint("LEFT", self.amount, "RIGHT", 8, 0)
        self.help:ClearAllPoints()
        local helpY = beside and 140 or 104
        self.help:SetPoint("TOPLEFT", card, "TOPLEFT", beside and 18 or x, -helpY)
        self.help:SetWidth(beside and inner - 36 or w)
        self.help:SetText(L().INK_ITEM_HELP)
        local lines = math.floor((self.cardHeight - helpY - 10) / T.LineHeight(13))
        T.MaxLines(self.help, math.max(1, lines))
        self.help:SetShown(lines >= 1)
    end
end

-- People, emotes, kills: the name (or the emote), its controls, then what to know about it.
function Atelier:RefreshDeed(page, w)
    local trigger, card, beside = page.trigger, self.card, self.beside
    local emote, kill = trigger.kind == "EMOTE", trigger.kind == "KILL"
    self.itemIcon:ClearAllPoints()
    self.itemIcon:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
    self.itemIcon:SetTexture(T.kinds[trigger.kind][2])
    self.where:SetWidth(emote and w - 72 or (beside or not kill) and w or w - 150)
    self.where:SetText(emote and I.Deeds.Command(trigger.token) or trigger.name or L().INK_TARGET_UNSET)
    -- The two arrows, or - x 5 +: at the right of the name (how many: on its own row in a narrow card).
    local y = 18 + T.LineHeight(15) + 6
    local first, last = emote and self.emotePrevious or self.less, emote and self.emoteNext or self.more
    if emote or kill then
        first:ClearAllPoints()
        if beside and kill then
            local measured = self.where:GetStringHeight()
            y = math.max(y, 18 + (type(measured) == "number" and measured or 0) + 6)
            first:SetPoint("TOPLEFT", card, "TOPLEFT", 72, -y)
            y = y + 26 + 8
        else
            first:SetPoint("TOPRIGHT", card, "TOPRIGHT", emote and -18 - 28 - 8 or -18 - 28 - 8 - 50 - 8, -14)
        end
        last:ClearAllPoints()
        if kill then
            self.amount:ClearAllPoints()
            self.amount:SetPoint("LEFT", first, "RIGHT", 8, 0)
            self.amount:SetWidth(50)
            self.amount:SetText(string.format("x %d", trigger.count))
            last:SetPoint("LEFT", self.amount, "RIGHT", 8, 0)
        else
            last:SetPoint("LEFT", first, "RIGHT", 8, 0)
        end
    end
    local x = beside and 18 or 72
    local room = beside and self.cardWidth - 36 or w
    if emote then
        local parts = {}
        if trigger.npcID then parts[#parts + 1] = trigger.name end
        if trigger.mapID then
            parts[#parts + 1] = string.format(L().INK_PLACE_AT_SHORT, A.Position:MapName(trigger.mapID) or L().SEAL_SOMEWHERE,
                trigger.x * 100, trigger.y * 100)
        end
        y = math.max(y, beside and 60 or 44)
        self.detail:ClearAllPoints()
        self.detail:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
        self.detail:SetWidth(room)
        T.MaxLines(self.detail, 1)
        self.detail:SetText(#parts > 0 and table.concat(parts, " · ") or L().INK_EMOTE_ANYWHERE)
        y = y + T.LineHeight(14) + 4
    end
    y = math.max(y, beside and 62 or 50)
    -- The buttons, one after the other, on a new row when one does not fit.
    local left = 0
    for _, button in ipairs({ self.take, self.placeHere, self.clear }) do
        if button:IsShown() then
            local width = button:Fit(90, room)
            if left > 0 and left + width > room then left, y = 0, y + 34 end
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", card, "TOPLEFT", x + left, -y)
            left = left + width + 8
            if y + 30 + 6 > self.cardHeight then button:Hide() end
        end
    end
    y = y + 30 + 6
    self.help:ClearAllPoints()
    self.help:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
    self.help:SetWidth(room)
    self.help:SetText(emote and (trigger.npcID or trigger.mapID) and L().INK_EMOTE_HELP_SET or L()["INK_" .. trigger.kind .. "_HELP"])
    local lines = math.floor((self.cardHeight - y - 4) / T.LineHeight(13))
    T.MaxLines(self.help, math.max(1, lines))
    self.help:SetShown(lines >= 1)
end

-- For the author: how far the place is from here (their own tale, so no secret is spoiled).
function Atelier:Distance(page)
    local trigger = page and page.trigger
    if not trigger or trigger.kind ~= "PLACE" or not trigger.mapID then self.distance:SetText(""); return end
    local sample = A.Position:Sample()
    local distance = sample and sample.settled and sample.x and sample.mapID and I.Watch.Distance(trigger, sample)
    self.distance:SetText(distance and string.format(L().INK_AUTHOR_DISTANCE, distance) or "")
    T.TextColor(self.distance, distance and distance <= trigger.radius and "success" or "muted")
end

function Atelier:Tick()
    local page = self:Page()
    if page and page.trigger.kind == "PLACE" then self:Distance(page) end
end

function Atelier:Refresh()
    local draft = self:Draft()
    if not draft then return Tab:Show("SHELF", "DRAFTS") end
    if not self.title:HasFocus() then self.title:SetValue(draft.title) end
    self.modes:Select(draft.mode)
    self.order:Set(draft.order == "SEQUENCE")
    local page, index = self:Page()
    if self.selected ~= "INTRO" and self.selected ~= "ENDING" and not page then
        self.selected = draft.pages[1] and draft.pages[1].key or "INTRO"
        page, index = self:Page()
    end
    self:LaySheet(page)
    for _, region in ipairs({ self.up, self.down, self.remove, self.pageTitle, self.hintLabel, self.hint, self.textLabel, self.text }) do
        region:SetShown(page ~= nil)
    end
    self.prose:SetShown(page == nil)
    self.card:SetShown(page ~= nil)
    self.strip:SetShown(page ~= nil)
    if page then
        self.kicker:SetText(string.format(L().INK_PAGE_KICKER, index, #draft.pages, L()["INK_TRIGGER_" .. page.trigger.kind]))
        if not self.pageTitle:HasFocus() then self.pageTitle:SetValue(page.title) end
        if not self.hint.box:HasFocus() then self.hint:SetValue(page.hint) end
        if not self.text.box:HasFocus() then self.text:SetValue(page.text) end
        self.up:SetActive(index > 1)
        self.down:SetActive(index < #draft.pages)
        self:RefreshCard(page)
        self:RefreshWhen(page)
    else
        local intro = self.selected == "INTRO"
        self.kicker:SetText(intro and L().INK_FIELD_INTRO or L().INK_FIELD_ENDING)
        if not self.prose.box:HasFocus() then self.prose:SetValue(intro and draft.intro or draft.ending) end
    end
    for _, button in pairs(self.adds) do button:SetActive(#draft.pages < I.Tale.maxPages) end
    self:RefreshRows()
    self:Status()
end

function Atelier:Closed()
    if self.remove then self.remove:Reset() end
    self.feedback = nil
end
