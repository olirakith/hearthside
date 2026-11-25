local MS = _G.MS
MS.Ink = MS.Ink or {}
-- Reading a tale as an open book. The leaves are the prologue, each page found, then the pages
-- still to find (their hints) or the ending. Wide: two leaves side by side, the last found on the
-- left and the next to find on the right. Narrow: one leaf.
local A = MS.Active
local I = MS.Ink
local T = I.Theme
local Tab = I.Tab

local function L() return MS.L end

local Book = { leafPages = {} }
Tab.panes.BOOK = Book
I.Book = Book

-- One leaf of parchment and what it can show.
local function Leaf(parent, spine)
    local leaf = T.Parchment(parent, spine)
    leaf.data = {}
    leaf.kicker = T.Text(leaf, "UI", 13, "inkSoft")
    leaf.heading = T.Text(leaf, "TITLE", 21, "ink")
    -- The text scrolls inside the leaf when the leaf is too low for it (wheel, or the gold mark).
    leaf.scroll = CreateFrame("ScrollFrame", nil, leaf)
    leaf.content = CreateFrame("Frame", nil, leaf.scroll)
    leaf.scroll:SetScrollChild(leaf.content)
    leaf.scroll:EnableMouseWheel(true)
    leaf.scroll:SetScript("OnMouseWheel", function(_, delta) Book:Wheel(leaf, delta) end)
    leaf.body = T.Text(leaf.content, "INK", 17, "ink")
    leaf.body:SetPoint("TOPLEFT", leaf.content, "TOPLEFT", 0, 0)
    leaf.thumb = T.Thumb(leaf)
    leaf.clue = T.Box(leaf, "paperDeep", "paperLine")
    leaf.clue:SetHeight(46)
    leaf.clueIcon = T.Icon(leaf.clue, 24, nil)
    leaf.clueIcon:SetPoint("LEFT", leaf.clue, "LEFT", 12, 0)
    leaf.clueText = T.Text(leaf.clue, "UI", 14, "ink")
    leaf.clueText:SetPoint("LEFT", leaf.clue, "LEFT", 46, 0)
    if type(leaf.clueText.SetJustifyV) == "function" then leaf.clueText:SetJustifyV("MIDDLE") end
    leaf.answer = T.Line(leaf, "INK", 17, I.Tale.answerBytes, L().INK_ANSWER_HINT, nil, true)
    leaf.answer:SetScript("OnEnterPressed", function() Book:Submit(leaf) end)
    leaf.submit = T.Button(leaf, "PAPER", L().INK_ANSWER_ACTION, function() Book:Submit(leaf) end, 110, 30)
    leaf.feedback = T.Text(leaf, "UI", 14, "wax")
    leaf.near = CreateFrame("Frame", nil, leaf)
    leaf.near:SetHeight(18)
    leaf.nearDot = T.Disc(leaf.near, 9, "wax")
    leaf.nearDot:SetPoint("LEFT", leaf.near, "LEFT", 0, 0)
    leaf.nearText = T.Text(leaf.near, "UI", 14, "inkSoft")
    leaf.nearText:SetPoint("LEFT", leaf.near, "LEFT", 16, 0)
    leaf.seal = T.Disc(leaf, 56, "wax", "ARTWORK")
    leaf.sealMark = leaf:CreateTexture(nil, "OVERLAY")
    leaf.sealMark:SetTexture(T.check)
    leaf.sealMark:SetSize(30, 30)
    leaf.sealMark:SetPoint("CENTER", leaf.seal, "CENTER")
    -- A wax mark, not a button: its caption says what it records.
    leaf.sealCaption = T.Text(leaf, "INK_ITALIC", 14, "inkSoft")
    leaf.sealCaption:SetPoint("RIGHT", leaf.seal, "LEFT", -10, 0)
    leaf.sealCaption:SetText(L().INK_LEAF_FOUND)
    leaf.signature = T.Text(leaf, "INK_ITALIC", 15, "inkSoft")
    return leaf
end

function Book:Build(frame)
    self.back = T.Button(frame, "GHOST", L().INK_BACK_SHELF, function() Tab:Show("SHELF") end, 110, 30)
    self.title = T.Text(frame, "TITLE", 20, "text")
    if type(self.title.SetWordWrap) == "function" then self.title:SetWordWrap(false) end
    self.author = T.Text(frame, "UI", 14, "muted")
    self.pips = T.Pips(frame)
    self.count = T.Text(frame, "UI", 14, "goldBright", "RIGHT")
    self.rule = frame:CreateTexture(nil, "BORDER")
    T.Color(self.rule, "lineSoft")
    self.left = Leaf(frame, "RIGHT")
    self.right = Leaf(frame, "LEFT")
    self.previous = T.Button(frame, "SECONDARY", "‹", function() Book:Step(-1) end, 44, 44)
    self.next = T.Button(frame, "SECONDARY", "›", function() Book:Step(1) end, 44, 44)
end

-- Opens a tale; on a page just found (key + result), else where the reader stands.
function Book:Open(id, key, result)
    self.taleId, self.wantKey, self.index = id, key, nil
    self.foundKey = result and key or nil
    for _, leaf in ipairs({ self.left, self.right }) do
        if leaf then leaf.answer:SetValue(""); leaf.feedback:SetText("") end
    end
    if result and A.Kit then A.Kit.Play("CRACK") end
    if id then I:Begin(id) end
end

function Book:Leaves()
    local entry, progress = I:Entry(self.taleId), I:ProgressOf(self.taleId)
    if not entry then return {} end
    local tale, leaves = entry.tale, {}
    if tale.intro then leaves[#leaves + 1] = { kind = "INTRO" } end
    progress = progress or I.Progress.New(tale, 0)
    for _, page in ipairs(I.Progress.FoundPages(tale, progress)) do leaves[#leaves + 1] = { kind = "PAGE", page = page } end
    if progress.finishedAt then
        leaves[#leaves + 1] = { kind = "ENDING" }
    else
        for _, page in ipairs(I.Progress.Open(tale, progress)) do leaves[#leaves + 1] = { kind = "OPEN", page = page } end
    end
    return leaves, tale, progress
end

-- The leaf to look at: the page just found, else the first page to find (or the ending), else
-- the prologue for a tale not begun.
function Book:Target(leaves, tale, progress)
    if self.wantKey then
        for index, leaf in ipairs(leaves) do
            if leaf.kind == "PAGE" and leaf.page.key == self.wantKey then return index end
        end
    end
    if I.Progress.Count(tale, progress) == 0 and leaves[1] and leaves[1].kind == "INTRO" then return 1 end
    for index, leaf in ipairs(leaves) do if leaf.kind == "OPEN" or leaf.kind == "ENDING" then return index end end
    return 1
end

function Book:Step(delta)
    self.index = (self.index or 1) + delta
    self.foundKey, self.wantKey = nil, nil
    Tab:Refresh()
end

function Book:Lay(width, height)
    local frame = self.frame
    self.wide = width >= 820
    self.width = width
    self.back:ClearAllPoints()
    self.back:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
    self.back:Fit(90, 160)
    self.title:ClearAllPoints()
    self.title:SetPoint("LEFT", self.back, "RIGHT", 14, 0)
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -24)
    self.pips:ClearAllPoints()
    self.pips:SetPoint("RIGHT", self.count, "LEFT", -12, 0)
    self.rule:ClearAllPoints()
    self.rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -62)
    self.rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -62)
    self.rule:SetHeight(1)
    -- A low tab (chat open under it) gives the page all the height there is, and a tighter leaf.
    local pageHeight = math.max(200, math.min(680, height - 62 - (height < 460 and 20 or 48)))
    local compact, tight = pageHeight < 360, pageHeight < 250
    self.pageHeight, self.compact, self.tight = pageHeight, compact, tight
    local pageWidth = self.wide and math.min(500, math.floor((width - 160) / 2)) or math.min(560, width - 140)
    local top = -62 - math.floor((height - 62 - pageHeight) / 2)
    local center = math.floor(width / 2)
    self.left:ClearAllPoints()
    self.left:SetSize(pageWidth, pageHeight)
    if self.wide then
        self.left:SetPoint("TOPRIGHT", frame, "TOPLEFT", center, top)
        self.right:ClearAllPoints()
        self.right:SetSize(pageWidth, pageHeight)
        self.right:SetPoint("TOPLEFT", frame, "TOPLEFT", center, top)
    else
        self.left:SetPoint("TOPLEFT", frame, "TOPLEFT", center - math.floor(pageWidth / 2), top)
    end
    self.right:SetShown(self.wide)
    self.previous:ClearAllPoints()
    self.previous:SetPoint("RIGHT", self.left, "LEFT", -18, 0)
    self.next:ClearAllPoints()
    self.next:SetPoint("LEFT", self.wide and self.right or self.left, "RIGHT", 18, 0)
    self.padTop, self.padBottom = compact and 20 or 32, compact and 16 or 26
    for _, leaf in ipairs({ self.left, self.right }) do
        local inner = pageWidth - 64
        self.inner = inner
        leaf.kicker:ClearAllPoints()
        leaf.kicker:SetPoint("TOPLEFT", leaf, "TOPLEFT", 32, -self.padTop)
        leaf.kicker:SetWidth(inner)
        if type(leaf.kicker.SetWordWrap) == "function" then leaf.kicker:SetWordWrap(false) end
        leaf.heading:SetWidth(inner)
        T.SetFont(leaf.heading, "TITLE", compact and 18 or 21)
        T.MaxLines(leaf.heading, compact and 1 or 2)
        leaf.body:SetWidth(inner)
        leaf.clue:SetWidth(inner)
        leaf.clue:SetHeight(compact and 36 or 46)
        leaf.clueText:SetWidth(inner - 58)
        T.MaxLines(leaf.clueText, compact and 1 or 2)
        leaf.submit:Fit(100, 160)
        leaf.answer:SetWidth(inner - leaf.submit:GetWidth() - 12)
        leaf.feedback:SetWidth(inner)
        if type(leaf.feedback.SetWordWrap) == "function" then leaf.feedback:SetWordWrap(false) end
        leaf.near:SetWidth(inner)
        leaf.nearText:SetWidth(inner - 16)
        if type(leaf.nearText.SetWordWrap) == "function" then leaf.nearText:SetWordWrap(false) end
        local seal = compact and 34 or 44
        leaf.seal:SetSize(seal, seal)
        leaf.sealMark:SetSize(compact and 18 or 24, compact and 18 or 24)
        leaf.seal:ClearAllPoints()
        leaf.seal:SetPoint("BOTTOMRIGHT", leaf, "BOTTOMRIGHT", -28, self.padBottom)
        leaf.signature:ClearAllPoints()
        leaf.signature:SetPoint("BOTTOMLEFT", leaf, "BOTTOMLEFT", 32, self.padBottom + 4)
        leaf.signature:SetWidth(inner - 80)
        if type(leaf.signature.SetWordWrap) == "function" then leaf.signature:SetWordWrap(false) end
    end
end

-- The text of a leaf under the wheel.
function Book:Wheel(leaf, delta)
    local range = math.max(0, (leaf.data.bodyHeight or 0) - (leaf.data.view or 0))
    leaf.data.offset = math.max(0, math.min(range, (leaf.data.offset or 0) - delta * 40))
    leaf.scroll:SetVerticalScroll(leaf.data.offset)
    leaf.thumb:Set(leaf.scroll, leaf.data.view or 0, leaf.data.offset, leaf.data.view or 0, leaf.data.bodyHeight or 0, 10)
end

-- What a reader is told about the page to find: the zone (never the spot), the item and how many
-- are carried, or the riddle's field.
function Book.Clue(page, tale, progress)
    local text, icon = Book.Asks(page, tale, progress)
    local wait = Tab.WaitText(page)
    return wait and wait .. " " .. text or text, icon
end

function Book.Asks(page, tale, progress)
    local trigger = page.trigger
    if trigger.kind == "PLACE" then
        return string.format(L().INK_CLUE_PLACE_LONG, A.Position:MapName(trigger.mapID) or L().SEAL_SOMEWHERE), T.kinds.PLACE[2]
    elseif trigger.kind == "ITEM" then
        return string.format(L().INK_CLUE_ITEM, Tab.ItemName(trigger.itemID), math.min(I.Watch.Carried(trigger.itemID), trigger.count),
            trigger.count), Tab.ItemIcon(trigger.itemID)
    elseif trigger.kind == "ANSWER" then
        return L().INK_CLUE_ANSWER, T.kinds.ANSWER[2]
    end
    return Tab.DeedText(page, tale, progress), T.kinds[trigger.kind][2]
end

function Book:Draw(leaf, item, tale, number)
    leaf:Show()
    local open = item and item.kind == "OPEN"
    local trigger = open and item.page.trigger
    local asking = open and trigger.kind == "ANSWER"
    leaf.data.page = open and item.page or nil
    -- A leaf that shows something else starts at the top of its text again.
    local shown = item and (item.kind .. ":" .. (item.page and item.page.key or "")) or ""
    if leaf.data.shown ~= shown then leaf.data.shown, leaf.data.offset = shown, 0 end
    if not item then
        leaf.kicker:SetText("")
        leaf.heading:SetText("")
        leaf.body:SetText(L().INK_LEAF_BLANK)
        T.SetFont(leaf.body, "INK_ITALIC", 17)
    elseif item.kind == "INTRO" then
        leaf.kicker:SetText(L().INK_LEAF_INTRO)
        leaf.heading:SetText(tale.title)
        leaf.body:SetText(tale.intro or "")
        T.SetFont(leaf.body, "INK", 17)
    elseif item.kind == "PAGE" then
        local found = I:ProgressOf(self.taleId)
        local at = found and found.found[item.page.key]
        local kicker = item.page.key == self.foundKey and L().INK_LEAF_FOUND or L().INK_LEAF_PAGE
        if at and A.Kit and type(_G.date) == "function" then
            local ok, clock = pcall(_G.date, "%H:%M", at)
            if ok and clock then kicker = string.format(L().INK_LEAF_FOUND_AT, kicker, clock) end
        end
        leaf.kicker:SetText(kicker)
        leaf.heading:SetText(item.page.title)
        leaf.body:SetText(item.page.text or L().INK_PAGE_BLANK)
        T.SetFont(leaf.body, "INK", 17)
    elseif item.kind == "ENDING" then
        leaf.kicker:SetText(L().INK_LEAF_ENDING)
        leaf.heading:SetText(tale.title)
        leaf.body:SetText(tale.ending or L().INK_ENDING_BLANK)
        T.SetFont(leaf.body, "INK", 17)
    else
        leaf.kicker:SetText(string.format(L().INK_LEAF_OPEN_N, number))
        leaf.heading:SetText(item.page.title)
        leaf.body:SetText(item.page.hint or L().INK_HINT_BLANK)
        T.SetFont(leaf.body, "INK_ITALIC", 17)
    end
    -- Below the text: the clue, the field, the warmth of the ink.
    leaf.clue:SetShown(open == true)
    leaf.answer:SetShown(asking == true)
    leaf.submit:SetShown(asking == true)
    leaf.feedback:SetShown(asking == true)
    local sealed = item and item.kind == "PAGE"
    local ending = item and item.kind == "ENDING"
    -- The room the text gets: the leaf minus what stands above it and what must stay below it.
    local compact, tight = self.compact, self.tight
    local hasKicker = not tight and (leaf.kicker:GetText() or "") ~= ""
    local hasHeading = (leaf.heading:GetText() or "") ~= ""
    leaf.kicker:SetShown(hasKicker)
    leaf.heading:SetShown(hasHeading)
    local y = self.padTop
    if hasKicker then y = y + T.LineHeight(13) + (compact and 4 or 10) end
    leaf.heading:ClearAllPoints()
    leaf.heading:SetPoint("TOPLEFT", leaf, "TOPLEFT", 32, -y)
    if hasHeading then y = y + (leaf.heading:GetStringHeight() or 24) + (compact and 8 or 14) end
    local gap = compact and 10 or 18
    local clueHeight = compact and 36 or 46
    local answerHeight = 33
    local under = 0
    if open then under = under + gap + clueHeight end
    if asking then under = under + 12 + answerHeight + 6 + T.LineHeight(14) end
    if open and trigger.kind == "PLACE" then under = under + 8 + 18 end
    if sealed then under = under + 8 + (compact and 34 or 44) end
    if ending then under = under + 8 + T.LineHeight(15) + 4 end
    local bodyHeight = leaf.body:GetStringHeight() or 40
    local view = math.max(T.LineHeight(17, true), math.min(bodyHeight, (self.pageHeight or 400) - y - under - self.padBottom))
    leaf.data.bodyHeight, leaf.data.view = bodyHeight, view
    leaf.data.offset = math.max(0, math.min(leaf.data.offset or 0, bodyHeight - view))
    leaf.scroll:ClearAllPoints()
    leaf.scroll:SetPoint("TOPLEFT", leaf, "TOPLEFT", 32, -y)
    leaf.scroll:SetSize(self.inner or 300, view)
    leaf.content:SetSize(self.inner or 300, bodyHeight)
    leaf.scroll:SetVerticalScroll(leaf.data.offset)
    leaf.thumb:Set(leaf.scroll, view, leaf.data.offset, view, bodyHeight, 10)
    local below = -(view + gap)
    if open then
        local text, icon = Book.Clue(item.page, tale, I:ProgressOf(self.taleId))
        leaf.clueText:SetText(text)
        leaf.clueIcon:SetTexture(icon)
        leaf.clue:ClearAllPoints()
        leaf.clue:SetPoint("TOPLEFT", leaf.scroll, "TOPLEFT", 0, below)
        below = below - clueHeight - 12
    end
    if asking then
        leaf.answer:ClearAllPoints()
        leaf.answer:SetPoint("TOPLEFT", leaf.scroll, "TOPLEFT", 0, below)
        leaf.submit:ClearAllPoints()
        leaf.submit:SetPoint("LEFT", leaf.answer, "RIGHT", 12, 0)
        leaf.feedback:ClearAllPoints()
        leaf.feedback:SetPoint("TOPLEFT", leaf.answer, "BOTTOMLEFT", 0, -6)
    end
    leaf.data.waiting = open and I.Waiting(item.page) or nil
    self:Warmth(leaf)
    leaf.seal:SetShown(sealed == true)
    leaf.sealMark:SetShown(sealed == true)
    leaf.sealCaption:SetShown(sealed == true)
    leaf.signature:SetShown(item and item.kind == "ENDING" or false)
    leaf.signature:SetText(string.format(L().INK_SIGNATURE, tale.author))
end

-- How close the reader is to a place page: a word, never a distance or a direction.
function Book:Warmth(leaf)
    local trigger = leaf.data.page and leaf.data.page.trigger
    local state = trigger and trigger.kind == "PLACE" and I.Watch.Proximity(trigger) or nil
    leaf.near:SetShown(state ~= nil)
    if not state then return end
    leaf.near:ClearAllPoints()
    leaf.near:SetPoint("BOTTOMLEFT", leaf, "BOTTOMLEFT", 32, self.padBottom or 26)
    leaf.nearText:SetText(L()["INK_NEAR_" .. state])
    T.Color(leaf.nearDot, state == "CLOSE" and "wax" or state == "WARM" and "gold" or "paperLine")
end

function Book:Tick()
    if not self.taleId then return end
    -- The hour came (or went), or a level was gained: the clue says something else now.
    for _, leaf in ipairs({ self.left, self.right }) do
        local page = leaf.data.page
        if page and page.when and I.Waiting(page) ~= leaf.data.waiting then return self:Refresh() end
    end
    self:Warmth(self.left)
    if self.wide then self:Warmth(self.right) end
end

function Book:Submit(leaf)
    local page = leaf.data.page
    if not page or page.trigger.kind ~= "ANSWER" then return end
    local result, reason = I:Answer(self.taleId, page.key, leaf.answer:GetText())
    if result then
        leaf.answer:SetValue("")
        leaf.answer:ClearFocus()
        leaf.feedback:SetText("")
    else
        leaf.feedback:SetText(reason == "WRONG" and L().INK_ANSWER_WRONG or reason == "WAIT" and Tab.WaitText(page) or "")
    end
end

function Book:Refresh()
    local leaves, tale, progress = self:Leaves()
    if not tale then return Tab:Show("SHELF") end
    local target = self:Target(leaves, tale, progress)
    if not self.index then
        -- Wide: the target on the right, what came before it on the left.
        self.index = (self.wide and target > 1 and leaves[target].kind ~= "PAGE") and target - 1 or target
    end
    self.wantKey = nil
    local last = self.wide and math.max(1, #leaves - 1) or #leaves
    self.index = math.max(1, math.min(last, self.index))
    self.title:SetText(tale.title)
    self.author:SetText(string.format(L().INK_BY_AUTHOR, tale.author))
    local count = I.Progress.Count(tale, progress)
    self.count:SetText(Tab.ProgressText(tale, progress))
    local width = self.width or 900
    local pips = math.min(220, #tale.pages * 32, math.max(60, math.floor(width * .2)))
    self.pips:Set(count, #tale.pages, not progress.finishedAt, pips)
    local room = width - (18 + self.back:GetWidth() + 14) - (28 + T.Width(self.count) + 12 + pips + 24)
    local author = T.Width(self.author)
    local showAuthor = room - author - 14 >= 160
    local titleWidth = math.max(80, math.min(T.Width(self.title) + 2, room - (showAuthor and author + 14 or 0)))
    self.title:SetWidth(titleWidth)
    self.author:SetShown(showAuthor)
    self.author:ClearAllPoints()
    self.author:SetPoint("LEFT", self.title, "LEFT", titleWidth + 12, -1)
    local openNumber = count + 1
    self:Draw(self.left, leaves[self.index], tale, openNumber)
    if self.wide then
        local second = leaves[self.index + 1]
        self:Draw(self.right, second, tale, openNumber + ((second and leaves[self.index].kind == "OPEN") and 1 or 0))
    end
    self.previous:SetActive(self.index > 1)
    self.next:SetActive(self.index < last)
end

function Book:Closed()
    self.foundKey = nil
end
