local MS = _G.MS
MS.Ink = MS.Ink or {}
-- The tales written as quests, in the Journey quest list: one row a tale, its objectives under
-- it. The quest journal calls Draw at the end of its own list and gets the new height back; a
-- click opens the book. Drawn in the journal's own style, so the list reads as one.
local A = MS.Active
local I = MS.Ink
local T = I.Theme

local function L() return MS.L end
local function Style() return MS.JourneyUIStyle end

local Section = { rows = {}, indent = 80 }
I.QuestSection = Section

-- Followed tales written as quests.
function Section:Tales()
    local tales = {}
    for _, following in ipairs(I:Following()) do
        if following.tale.mode == "QUEST" then tales[#tales + 1] = following end
    end
    return tales
end

-- What is done and what is asked now. A page not open yet (a tale in order) stays unsaid.
function Section.Objectives(following)
    local tale, progress, list = following.tale, following.progress, {}
    local open = {}
    for _, page in ipairs(I.Progress.Open(tale, progress)) do open[page.key] = true end
    for _, page in ipairs(tale.pages) do
        local trigger = page.trigger
        if progress.found[page.key] then
            list[#list + 1] = { text = page.title, done = true }
        elseif open[page.key] then
            local text
            if trigger.kind == "PLACE" then
                text = string.format(L().INK_QUEST_OBJECTIVE_PLACE, page.title, A.Position:MapName(trigger.mapID) or L().SEAL_SOMEWHERE)
            elseif trigger.kind == "ITEM" then
                text = string.format(L().INK_QUEST_OBJECTIVE_ITEM, page.title, I.Tab.ItemName(trigger.itemID),
                    math.min(I.Watch.Carried(trigger.itemID), trigger.count), trigger.count)
            elseif trigger.kind == "ANSWER" then
                text = string.format(L().INK_QUEST_OBJECTIVE_ANSWER, page.title)
            else
                text = string.format(L().INK_QUEST_OBJECTIVE_DEED, page.title, I.Tab.DeedText(page, tale, progress))
            end
            local wait = I.Tab.WaitText(page)
            if wait then text = text .. " " .. wait end
            list[#list + 1] = { text = text, done = false, item = trigger.kind == "ITEM" }
        end
    end
    return list
end

local function Label(parent, token, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Style():Body(label, token, color)
    label:SetJustifyH("LEFT")
    return label
end

function Section:Build(content)
    self.content = content
    self.heading = Label(content, "HEADING", "gold")
    self.rule = content:CreateTexture(nil, "ARTWORK")
    self.rule:SetHeight(1)
    Style():Color(self.rule, "borderMuted")
end

function Section:Row(index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, self.content)
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints(row)
    Style():ReactiveRow(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -8)
    row.icon:SetSize(20, 20)
    row.icon:SetTexture(T.modes.QUEST[3])
    row.icon:SetTexCoord(.08, .92, .08, .92)
    row.count = Label(row, "BODY", "textPrimary")
    row.count:SetPoint("TOPLEFT", row, "TOPLEFT", 36, -8)
    row.count:SetWidth(42)
    row.title = Label(row, "ITEM_TITLE", "textPrimary")
    row.meta = Label(row, "SMALL", "textSecondary")
    row.lines = {}
    row.separator = row:CreateTexture(nil, "ARTWORK")
    row.separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, -3)
    row.separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, -3)
    row.separator:SetHeight(1)
    Style():Color(row.separator, "borderMuted")
    row.separator:SetAlpha(.45)
    row:SetScript("OnClick", function(self) if self.taleId then I:OpenTab("BOOK", self.taleId) end end)
    self.rows[index] = row
    return row
end

local function Line(row, index)
    local line = row.lines[index]
    if line then return line end
    line = { label = Label(row, "SMALL", "textSecondary") }
    line.check = row:CreateTexture(nil, "OVERLAY")
    line.check:SetTexture(T.check)
    line.check:SetSize(14, 14)
    line.dot = row:CreateTexture(nil, "OVERLAY")
    line.dot:SetSize(5, 5)
    Style():Color(line.dot, "gold")
    row.lines[index] = line
    return line
end

local function Height(label, fallback)
    local height = label:GetStringHeight()
    return type(height) == "number" and height > 0 and height or fallback
end

-- Draws under the journal's own rows, from y down. Returns the new y.
function Section:Draw(content, y)
    if not self.content then self:Build(content) end
    local tales = I:Ready() and self:Tales() or {}
    self.shown, self.watchesItems = #tales, false
    self.heading:SetShown(#tales > 0)
    self.rule:SetShown(#tales > 0)
    for index = #tales + 1, #self.rows do self.rows[index]:Hide() end
    if #tales == 0 then return y end
    local style, width = Style(), content:GetWidth() or 0
    y = y + style.space.md
    self.heading:ClearAllPoints()
    self.heading:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
    self.heading:SetWidth(math.max(1, width - 8))
    self.heading:SetText(L().INK_NAME)
    y = y + math.max(22, Height(self.heading, 16) + 6)
    self.rule:ClearAllPoints()
    self.rule:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y - 3))
    self.rule:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -(y - 3))
    y = y + 4
    local inner = math.max(1, width - self.indent - 12)
    for index, following in ipairs(tales) do
        local row, tale = self:Row(index), following.tale
        row.taleId = following.id
        row.count:SetText(I.Tab.ProgressText(tale, following.progress))
        row.title:ClearAllPoints()
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", self.indent, -7)
        row.title:SetWidth(inner)
        row.title:SetText(tale.title)
        local used = 7 + Height(row.title, 16) + 3
        row.meta:ClearAllPoints()
        row.meta:SetPoint("TOPLEFT", row, "TOPLEFT", self.indent, -used)
        row.meta:SetWidth(inner)
        row.meta:SetText(string.format(L().INK_BY_AUTHOR, tale.author))
        used = used + Height(row.meta, 13) + 6
        local objectives = Section.Objectives(following)
        for number, objective in ipairs(objectives) do
            local line = Line(row, number)
            line.label:ClearAllPoints()
            line.label:SetPoint("TOPLEFT", row, "TOPLEFT", self.indent + 18, -used)
            line.label:SetWidth(math.max(1, inner - 18))
            line.label:SetText(objective.text)
            style:Text(line.label, objective.done and "textSecondary" or "textPrimary")
            line.check:ClearAllPoints()
            line.check:SetPoint("TOPLEFT", row, "TOPLEFT", self.indent - 1, -used + 1)
            line.check:SetShown(objective.done)
            line.dot:ClearAllPoints()
            line.dot:SetPoint("TOPLEFT", row, "TOPLEFT", self.indent + 4, -used - 5)
            line.dot:SetShown(not objective.done)
            line.label:Show()
            line.done = objective.done
            used = used + Height(line.label, 13) + 4
            if objective.item then self.watchesItems = true end
        end
        for number = #objectives + 1, #row.lines do
            local line = row.lines[number]
            line.label:Hide(); line.check:Hide(); line.dot:Hide()
        end
        row.objectives = #objectives
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y)
        row:SetSize(math.max(1, width - 4), used + 6)
        row:Show()
        y = y + used + 6 + 6
    end
    return y
end

-- Bags moved while an item objective is listed: the count on screen is stale.
function Section:OnBags()
    local journal = MS.QuestJournal
    if self.watchesItems and journal and journal.Invalidate then
        journal:Invalidate()
        journal:Refresh()
    end
end

local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function() Section:OnBags() end)
