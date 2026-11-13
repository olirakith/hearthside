local MS = _G.MS
MS.JourneySessionJournal = { dirty = true, expanded = false, refreshCount = 0 }
local Journal = MS.JourneySessionJournal
local Style = MS.JourneyUIStyle
-- What kind of moment a line is, at a glance. Anything else stays quiet.
local EVENT_TOKENS = { LEVEL_UP = "gold", QUEST_TURNED_IN = "gold", DEATH = "critical", SESSION_STARTED = "textSecondary" }
local TIME_WIDTH, DOT_X, TEXT_X = 44, 52, 70

function Journal:Create(parent)
    if self.frame then return end
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetFrameLevel(parent:GetFrameLevel() + 12)
    self.background = self.frame:CreateTexture(nil, "BACKGROUND")
    self.background:SetAllPoints(self.frame); Style:Color(self.background, "backgroundPanel")
    self.rule = self.frame:CreateTexture(nil, "BORDER")
    self.rule:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
    self.rule:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, 0)
    self.rule:SetHeight(1); Style:Color(self.rule, "borderActive")
    self.bar = CreateFrame("Frame", nil, self.frame)
    self.bar:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT")
    self.bar:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT")
    self.bar:SetHeight(36)
    self.title = self.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Style:Apply(self.title, "SECTION"); Style:Text(self.title, "gold")
    self.title:SetPoint("LEFT", self.bar, "LEFT", 12, 0)
    self.title:SetText(MS.L.JOURNEY_SESSION_JOURNAL)
    if type(self.title.SetWordWrap) == "function" then self.title:SetWordWrap(false) end
    if type(self.title.SetMaxLines) == "function" then self.title:SetMaxLines(1) end
    self.latest = self.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Style:Apply(self.latest, "BODY"); Style:Text(self.latest, "textSecondary")
    self.latest:SetPoint("LEFT", self.title, "RIGHT", 18, 0)
    self.latest:SetJustifyH("LEFT")
    if type(self.latest.SetWordWrap) == "function" then self.latest:SetWordWrap(false) end
    if type(self.latest.SetMaxLines) == "function" then self.latest:SetMaxLines(1) end
    self.toggle = CreateFrame("Button", nil, self.bar)
    self.toggle:SetSize(86, 30)
    self.toggle:SetPoint("RIGHT", self.bar, "RIGHT", -8, 0)
    self.toggle.label = self.toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Style:Apply(self.toggle.label, "BODY")
    self.toggle.label:SetPoint("CENTER", self.toggle, "CENTER")
    Style:Text(self.toggle.label, "gold")
    self.toggle:SetScript("OnClick", function()
        self.expanded, self.dirty = not self.expanded, true
        MS.JourneyWorkspace:LayoutView(MS.JourneyWorkspace.view)
    end)
    self.toggle:SetScript("OnEnter", function() Style:Text(self.toggle.label, "textPrimary") end)
    self.toggle:SetScript("OnLeave", function() Style:Text(self.toggle.label, "gold") end)
    self.summary = self.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Style:Apply(self.summary, "BODY"); Style:Text(self.summary, "textPrimary")
    self.summary:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -12)
    self.summary:SetJustifyH("LEFT")
    self.scroll = CreateFrame("ScrollFrame", nil, self.frame)
    self.scroll:SetPoint("TOPLEFT", self.summary, "BOTTOMLEFT", 0, -12)
    self.scroll:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -12, 12)
    self.content = CreateFrame("Frame", nil, self.scroll); self.content:SetSize(1, 1)
    self.scroll:SetScrollChild(self.content); self.scroll:EnableMouseWheel(true)
    self.scroll:SetScript("OnMouseWheel", function(frame, delta)
        local maximum = math.max(0, self.content:GetHeight() - frame:GetHeight())
        frame:SetVerticalScroll(math.max(0, math.min(maximum, frame:GetVerticalScroll() - delta * 36)))
    end)
    self.lines = {}
    self.spine = self.content:CreateTexture(nil, "ARTWORK")
    self.spine:SetWidth(1); Style:Color(self.spine, "borderMuted")
    self.spine:SetPoint("TOPLEFT", self.content, "TOPLEFT", DOT_X + 3, -4)
    self.spine:SetPoint("BOTTOMLEFT", self.content, "BOTTOMLEFT", DOT_X + 3, 4)
end

function Journal:SetVisible(visible)
    self.visible = visible == true
    if self.frame then self.frame:SetShown(self.visible and self.expanded) end
    if self.visible then self:Refresh() end
end

function Journal:Layout(rect)
    if not self.frame then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    self.frame:SetSize(rect.width, rect.height)
    self.frame:SetShown(self.visible == true and self.expanded)
    self.bar:Hide()
    self.compact = rect.width <= 1300
    self.title:SetText(self.compact and MS.L.JOURNEY_SESSION_JOURNAL_COMPACT or MS.L.JOURNEY_SESSION_JOURNAL)
    self.title:SetWidth(self.compact and 95 or 190)
    local gap = self.compact and 12 or 18
    self.latest:ClearAllPoints()
    self.latest:SetPoint("LEFT", self.title, "RIGHT", gap, 0)
    self.latest:SetWidth(math.max(1, rect.width - self.title:GetWidth() - self.toggle:GetWidth() - gap - 30))
    self.summary:SetWidth(math.max(1, rect.width - 28))
    self.content:SetWidth(math.max(1, rect.width - 28))
    self.summary:SetShown(self.expanded)
    self.scroll:SetShown(self.expanded)
    self.toggle.label:SetText(self.expanded and MS.L.JOURNEY_JOURNAL_COLLAPSE or MS.L.JOURNEY_JOURNAL_EXPAND)
    self:Refresh()
end

function Journal:RefreshSummary()
    if not self.visible or not self.frame then return end
    local info = MS.JourneySession:GetSummary()
    if not info then return end
    local events = MS.JourneySession.data and MS.JourneySession.data.events or {}
    local event = events[#events]
    local stamp = event and type(date) == "function" and date("%H:%M", event.timestamp) or ""
    local latest = event and string.format(MS.L.JOURNEY_SESSION_LINE, stamp, event.title) or ""
    if latest ~= self.latestText then
        self.latestText = latest; self.latest:SetText(latest)
        if MS.JourneyRoadNote then MS.JourneyRoadNote:Refresh() end
    end
    if MS.JourneyStatusBar and MS.JourneyStatusBar.RenderText then MS.JourneyStatusBar:RenderText() end
    if not self.expanded then return end
    local parts = {} -- The shared utility rail owns the session clock.
    for _, field in ipairs({ { "xpGained", "JOURNEY_SESSION_XP" }, { "questTurnIns", "JOURNEY_SESSION_TURNINS" },
        { "deaths", "JOURNEY_SESSION_DEATHS" }, { "zonesVisited", "JOURNEY_SESSION_ZONES" } }) do
        if type(info[field[1]]) == "number" then parts[#parts + 1] = string.format(MS.L[field[2]], info[field[1]]) end
    end
    local value = table.concat(parts, "  ·  ")
    if value ~= self.summaryText then self.summaryText = value; self.summary:SetText(value) end
end

function Journal:Refresh()
    self.dirty = true
    if not self.visible or not self.frame then return end
    self:RefreshSummary()
    if not self.expanded then return end
    local events = MS.JourneySession.data and MS.JourneySession.data.events or {}
    local y = 0
    for index = 1, #events do
        local event = events[#events - index + 1]
        local line = self.lines[index]
        if not line then
            line = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            Style:Apply(line, "BODY"); line:SetJustifyH("LEFT"); self.lines[index] = line
            line.stamp = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            Style:Apply(line.stamp, "SMALL"); Style:Text(line.stamp, "textSecondary")
            line.stamp:SetJustifyH("RIGHT"); line.stamp:SetWidth(TIME_WIDTH)
            line.dot = self.content:CreateTexture(nil, "OVERLAY")
            line.dot:SetSize(7, 7)
        end
        local stamp = type(date) == "function" and date("%H:%M", event.timestamp) or ""
        line:ClearAllPoints(); line:SetPoint("TOPLEFT", self.content, "TOPLEFT", TEXT_X, -y)
        line:SetWidth(math.max(1, self.content:GetWidth() - TEXT_X))
        line:SetText(event.title)
        Style:Text(line, index == 1 and "textPrimary" or "textSecondary")
        line.stamp:ClearAllPoints(); line.stamp:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(y + 2))
        line.stamp:SetText(stamp)
        line.dot:ClearAllPoints(); line.dot:SetPoint("TOPLEFT", self.content, "TOPLEFT", DOT_X, -(y + 4))
        Style:Color(line.dot, EVENT_TOKENS[event.type] or "borderActive")
        local height = line:GetStringHeight()
        y = y + (type(height) == "number" and height or 28) + 8
        line:Show(); line.stamp:Show(); line.dot:Show()
    end
    for index = #events + 1, #self.lines do
        local line = self.lines[index]
        line:Hide(); line.stamp:Hide(); line.dot:Hide()
    end
    self.spine:SetShown(#events > 1)
    self.content:SetHeight(math.max(1, y)); self.scroll:SetVerticalScroll(0)
    self.dirty, self.refreshCount = false, self.refreshCount + 1
end

function Journal:GetStatus()
    local data = MS.JourneySession.data or {}
    return { eventCount = #(data.events or {}), sessionQuestTurnIns = data.questTurnIns,
        zonesVisited = data.zonesVisited, expanded = self.expanded, compact = self.compact }
end
