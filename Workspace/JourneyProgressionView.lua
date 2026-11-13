local MS = _G.MS
MS.JourneyProgressionView = { visible = false, dirty = true, refreshCount = 0,
    milestoneCount = 0, zoneCount = 0, sessionCount = 0, questCount = 0 }
local View = MS.JourneyProgressionView
View.expandedZones = {}

local function Label(parent, style, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if style == "PAGE_TITLE" or style == "TITLE" or style == "CHAPTER_TITLE" then
        MS.JourneyUIStyle:Heading(label, style, "ink")
    else MS.JourneyUIStyle:Body(label, style, "ink") end
    local ink = color == "gold" and "ink" or color == "textPrimary" and "ink"
        or color == "textSecondary" and "inkSecondary" or color
    MS.JourneyUIStyle:Text(label, ink)
    label:SetJustifyH("LEFT"); label:SetJustifyV("TOP")
    return label
end
local function Rule(parent, color)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    MS.JourneyUIStyle:Color(rule, color)
    return rule
end
local function Place(label, parent, x, y, width, value, lineBudget)
    -- A height left from the last refresh would cut the text and its measure: an opened chapter stayed short.
    label:SetHeight(0)
    label:SetWidth(math.max(1, width)); label:SetText(value)
    label:ClearAllPoints(); label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    label:Show()
    local ok, height = pcall(label.GetStringHeight, label)
    if not ok or type(height) ~= "number" or height <= 0 then
        local _, size = label:GetFont()
        height = size or 14
    end
    height = math.ceil(height)
    label:SetHeight(height)
    return height
end

function View:ShortDateLabel(stamp)
    if type(stamp) == "number" and type(date) == "function" then
        local ok, result = pcall(date, MS.L.JOURNEY_MEMORY_DATE_FORMAT, stamp)
        if ok and type(result) == "string" then return result end
    end
    return MS.L.JOURNEY_MEMORY_DATE_UNKNOWN
end

-- Whole local calendar days from stamp to now; nil when the client cannot tell.
function View:DaysSince(stamp, now)
    now = now or (type(time) == "function" and time())
    if type(stamp) ~= "number" or type(now) ~= "number" or type(date) ~= "function" then return nil end
    local ok, days = pcall(function()
        local today = date("*t", now)
        local thenDay = date("*t", stamp)
        if type(today) ~= "table" or type(thenDay) ~= "table" then return nil end
        today.hour, today.min, today.sec = 12, 0, 0
        thenDay.hour, thenDay.min, thenDay.sec = 12, 0, 0
        return math.floor((time(today) - time(thenDay)) / 86400 + 0.5)
    end)
    return ok and type(days) == "number" and days or nil
end

-- Presentation only: timestamps and factual builders remain unchanged.
function View:RecentDate(stamp, now)
    if type(stamp) ~= "number" then return MS.L.JOURNEY_MEMORY_DATE_UNKNOWN end
    local days = self:DaysSince(stamp, now)
    if days then
        if days == 0 then return MS.L.JOURNEY_UI_TODAY end
        if days == 1 then return MS.L.JOURNEY_UI_YESTERDAY end
        if days > 1 and days <= 6 then return string.format(MS.L.JOURNEY_UI_DAYS_AGO, days) end
    end
    if type(date) == "function" then
        local ok, value = pcall(date, MS.L.JOURNEY_UI_SHORT_DATE, stamp)
        if ok and type(value) == "string" then return value end
    end
    return self:ShortDateLabel(stamp)
end

function View:IdentityLine()
    local parts = { self:CharacterName() }
    for _, api in ipairs({ "UnitRace", "UnitClass" }) do
        if type(_G[api]) == "function" then
            local ok, value = pcall(_G[api], "player")
            if ok and type(value) == "string" and value ~= "" then parts[#parts + 1] = value end
        end
    end
    if type(UnitLevel) == "function" then
        local ok, level = pcall(UnitLevel, "player")
        if ok and type(level) == "number" and level > 0 then
            parts[#parts + 1] = string.format(MS.L.JOURNEY_UI_LEVEL, level)
        end
    end
    return table.concat(parts, " · ")
end

function View:StartContext(journal)
    if not journal.start then return "" end
    local lines = { string.format(MS.L.JOURNEY_UI_CARNET_START, self:RecentDate(journal.start.timestamp)) }
    if type(journal.start.level) == "number" and journal.start.level > 1 then
        lines[#lines + 1] = MS.L.JOURNEY_JOURNAL_PARTIAL
    end
    return table.concat(lines, "\n")
end

function View:AdventureText(session)
    local parts = { string.format(MS.L.JOURNEY_UI_LAST_TIME, self:RecentDate(session.startedAt)) }
    if type(session.duration) == "number" and session.duration >= 60 then
        parts[#parts + 1] = string.format(MS.L[session.interrupted and
            "JOURNEY_UI_RECORDED_MINUTES" or "JOURNEY_MEMORY_DURATION"], math.floor(session.duration / 60))
    end
    if session.questTurnIns and session.questTurnIns > 0 then
        parts[#parts + 1] = string.format(MS.L[session.questTurnIns == 1 and
            "JOURNEY_JOURNAL_SESSION_QUEST" or "JOURNEY_JOURNAL_SESSION_QUESTS"], session.questTurnIns)
    end
    if session.startLevel and session.endLevel and session.endLevel > session.startLevel then
        parts[#parts + 1] = string.format(MS.L.JOURNEY_JOURNAL_SESSION_LEVELS, session.startLevel, session.endLevel)
    end
    if session.zonesVisitedCount and session.zonesVisitedCount > 0 then
        parts[#parts + 1] = string.format(MS.L[session.zonesVisitedCount == 1 and
            "JOURNEY_JOURNAL_SESSION_ZONE" or "JOURNEY_JOURNAL_SESSION_ZONES"], session.zonesVisitedCount)
    end
    return table.concat(parts, " · ")
end

-- Decorative snapshots are rebuilt only on navigation or a current-zone transition.
function View:ChapterArtLayout(mapID)
    if type(mapID) ~= "number" or mapID <= 0 or mapID ~= mapID then return nil end
    self.artCache = self.artCache or {}
    local cached = self.artCache[mapID]
    if cached ~= nil then return cached or nil end
    local snapshot = MS.JourneyChapterArt:Capture(mapID)
    self.artCache[mapID] = snapshot or false
    return snapshot
end

function View:ChapterArt(mapID)
    local layout = self:ChapterArtLayout(mapID)
    return layout and layout.tiles[1].file or nil
end

function View:ChapterBannerHeight()
    local scale = MS.JourneySettings:Get("textScale") or 1
    return math.floor(math.max(160, math.min(210, 176 * scale)) + .5)
end

function View:CharacterName()
    local memory = MS.JourneyMemory
    local identity = MS.JourneyCharacterIdentity:Resolve()
    if memory and identity.key == memory.key and identity.fullName then return identity.fullName end
    return MS.L.JOURNEY_JOURNAL_TRAVELER
end

function View:JournalDateLabel(stamp)
    if type(stamp) == "number" and type(date) == "function" then
        local ok, day, month, year = pcall(function()
            return tonumber(date("%d", stamp)), tonumber(date("%m", stamp)), date("%Y", stamp)
        end)
        if ok and day and month and MS.L["JOURNEY_JOURNAL_MONTH_" .. month] then
            return string.format(MS.L.JOURNEY_JOURNAL_LONG_DATE, day, MS.L["JOURNEY_JOURNAL_MONTH_" .. month], year)
        end
    end
    return self:ShortDateLabel(stamp)
end

function View:DateLabel(stamp)
    return self:JournalDateLabel(stamp)
end

function View:Create(parent)
    if self.frame then return end
    self.frame = CreateFrame("ScrollFrame", nil, parent)
    self.content = CreateFrame("Frame", nil, self.frame); self.content:SetSize(1, 1)
    self.frame:SetScrollChild(self.content); self.frame:EnableMouseWheel(true)
    self.frame:SetScript("OnMouseWheel", function(frame, delta)
        local maximum = math.max(0, self.content:GetHeight() - frame:GetHeight())
        frame:SetVerticalScroll(math.max(0, math.min(maximum, frame:GetVerticalScroll() - delta * 40)))
    end)
    self.paper = Rule(self.content, "paperRaised")
    if type(self.paper.SetDrawLayer) == "function" then self.paper:SetDrawLayer("BACKGROUND", 0) end
    MS.JourneyUIStyle:PageMaterial(self.paper, "PAPER")
    self.edge = Rule(self.content, "borderMuted")
    self.title = Label(self.content, "PAGE_TITLE", "gold")
    self.subtitle = Label(self.content, "BODY", "textSecondary")
    self.journalContext = Label(self.content, "BODY", "textSecondary")
    self.recapHeading = Label(self.content, "SECTION", "gold")
    self.recapText = Label(self.content, "BODY_LARGE", "textPrimary")
    self.archiveButton = CreateFrame("Button", nil, self.content)
    self.archiveButton.label = Label(self.archiveButton, "SECTION", "textSecondary")
    self.archiveButton.label:SetAllPoints(self.archiveButton)
    self.archiveButton:SetScript("OnClick", function()
        self.showArchives = not self.showArchives; self:Invalidate()
    end)
    MS.JourneyUIStyle:Link(self.archiveButton, self.archiveButton.label, true)
    self.summary = Label(self.content, "BODY", "textPrimary")
    self.headerRule = Rule(self.content, "borderMuted")
    MS.JourneyUIStyle:Separator(self.headerRule, true)
    self.chronicleHeading = Label(self.content, "SECTION", "gold")
    self.empty = Label(self.content, "BODY_LARGE", "textSecondary")
    self.timelineRows, self.memorySections = {}, {}
    for _, key in ipairs({ "JOURNEY_JOURNAL_LEVELS", "JOURNEY_MEMORY_SESSIONS", "JOURNEY_JOURNAL_UNPLACED" }) do
        local section = { heading = Label(self.content, "SECTION", "gold"), rows = {},
            rule = Rule(self.content, "borderMuted") }
        section.heading:SetText(MS.L[key])
        self.memorySections[#self.memorySections + 1] = section
    end
    self.olderSessions = Label(self.content, "SMALL", "textSecondary")
    self.sidebarRule = Rule(self.content, "borderMuted")
    self.frame:Hide()
end

function View:Layout(rect)
    if not self.frame then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    self.frame:SetSize(rect.width, rect.height)
    self.content:SetWidth(math.max(1, rect.width - 12))
    local scale = MS.JourneySettings:Get("textScale")
    if self.width ~= rect.width or self.scale ~= scale then
        self.width, self.scale, self.dirty = rect.width, scale, true
    end
    self:Refresh()
end
function View:SetVisible(visible)
    self.visible = visible == true
    if self.frame then self.frame:SetShown(self.visible) end
    if self.visible then self.artCache = {}; self.dirty = true; self:Refresh() end
end
function View:Invalidate()
    self.dirty = true
    self:Refresh()
end

function View:MilestoneTitle(entry)
    local memory = MS.JourneyMemory
    if entry.type == "LEVEL_REACHED" and entry.level then
        local firstSeen = memory.data and memory.data.character.firstSeenAt
        local key = firstSeen and entry.timestamp > firstSeen and "JOURNEY_MEMORY_LEVEL"
            or "JOURNEY_JOURNAL_LEVEL_OBSERVED"
        return string.format(MS.L[key], entry.level)
    elseif entry.type == "FIRST_ZONE_VISIT" then
        local zone = memory:GetZone(entry.mapID)
        if zone then return string.format(MS.L.JOURNEY_MEMORY_FIRST_ZONE,
            zone.nameSnapshot or MS.L.JOURNEY_MAP_UNKNOWN_ZONE) end
    elseif entry.type == "FIRST_QUEST_TURNIN" then
        local quest = memory:GetQuest(entry.questID)
        if quest then return string.format(MS.L.JOURNEY_MEMORY_FIRST_QUEST,
            quest.titleSnapshot or MS.L.JOURNEY_QUEST_DETAILS) end
    end
end

-- Display copies only. M3 stores up to 250 milestones and 30 closed sessions;
-- its zone/quest maps and separate openSession remain untouched.
function View:Collect()
    local data = MS.JourneyMemory and MS.JourneyMemory.data
    local result = { milestones = {}, zones = {}, sessions = {}, quests = {} }
    if not data then return result end
    for index, entry in ipairs(data.milestones) do
        local title = self:MilestoneTitle(entry)
        if title then
            local context
            if entry.type == "FIRST_ZONE_VISIT" then
                local zone = data.zones[entry.mapID]
                if zone and zone.firstVisitedLevel then
                    context = string.format(MS.L.JOURNEY_MEMORY_AT_LEVEL, zone.firstVisitedLevel)
                end
            end
            result.milestones[#result.milestones + 1] = {
                timestamp = entry.timestamp, order = index, type = entry.type, title = title, context = context }
        end
    end
    table.sort(result.milestones, function(a, b)
        if a.timestamp ~= b.timestamp then return a.timestamp > b.timestamp end
        return a.order > b.order
    end)
    for id, zone in pairs(data.zones) do result.zones[#result.zones + 1] = { id = id, fact = zone } end
    table.sort(result.zones, function(a, b)
        if a.fact.firstVisitedAt ~= b.fact.firstVisitedAt then
            return a.fact.firstVisitedAt > b.fact.firstVisitedAt end
        return a.id < b.id
    end)
    for index, session in ipairs(data.sessions) do
        result.sessions[#result.sessions + 1] = { order = index, fact = session }
    end
    table.sort(result.sessions, function(a, b)
        if a.fact.startedAt ~= b.fact.startedAt then return a.fact.startedAt > b.fact.startedAt end
        return a.order > b.order
    end)
    for id, quest in pairs(data.quests) do result.quests[#result.quests + 1] = { id = id, fact = quest } end
    table.sort(result.quests, function(a, b)
        if a.fact.lastTurnedInAt ~= b.fact.lastTurnedInAt then
            return a.fact.lastTurnedInAt > b.fact.lastTurnedInAt end
        return a.id < b.id
    end)
    return result
end

local function TimelineRow(view, index)
    local row = view.timelineRows[index]
    if row then return row end
    row = { date = Label(view.content, "SMALL", "textSecondary"),
        title = Label(view.content, "BODY_LARGE", "textPrimary"),
        context = Label(view.content, "BODY", "textPrimary"),
        separator = Rule(view.content, "borderMuted"),
        paper = Rule(view.content, "paper"),
        dot = Rule(view.content, "bronze"), line = Rule(view.content, "borderMuted"),
        accent = Rule(view.content, "paperAccent"),
        art = view.content:CreateTexture(nil, "ARTWORK", nil, 1),
        art2 = view.content:CreateTexture(nil, "ARTWORK", nil, 1),
        marker = Label(view.content, "CHAPTER_MARKER", "inkSecondary"),
        current = Label(view.content, "SMALL", "inkSecondary") }
    if type(row.paper.SetDrawLayer) == "function" then row.paper:SetDrawLayer("BACKGROUND", 1) end
    row.details = CreateFrame("Button", nil, view.content)
    row.details.label = Label(row.details, "SMALL", "gold")
    row.details.label:SetAllPoints(row.details)
    MS.JourneyUIStyle:Link(row.details, row.details.label, true)
    row.details:SetScript("OnClick", function(button)
        view.expandedZones[button.mapID] = not view.expandedZones[button.mapID]
        view:Invalidate()
    end)
    row.dot:SetSize(6, 6); view.timelineRows[index] = row
    return row
end

local function SessionText(session)
    local parts = {}
    if session.duration and session.duration >= 60 then
        parts[#parts + 1] = string.format(MS.L.JOURNEY_MEMORY_DURATION, math.floor(session.duration / 60))
    end
    for _, spec in ipairs({ { "questTurnIns", "JOURNEY_JOURNAL_SESSION_QUEST" },
        { "xpGained", "JOURNEY_JOURNAL_SESSION_XP" }, { "deaths", "JOURNEY_JOURNAL_SESSION_DEATH" },
        { "zonesVisitedCount", "JOURNEY_JOURNAL_SESSION_ZONE" } }) do
        local value = session[spec[1]]
        if value and value > 0 then
            local key = spec[2]
            if spec[1] ~= "xpGained" and value ~= 1 then key = key .. "S" end
            parts[#parts + 1] = string.format(MS.L[key], value)
        end
    end
    return table.concat(parts, "  ·  ")
end

-- Read-only presentation of existing current-character facts. Archived sessions
-- have no map IDs: do not attribute their counters or quests to a zone.
function View:Journal(facts)
    facts = facts or self:Collect()
    local data = MS.JourneyMemory and MS.JourneyMemory.data
    local journal = { chapters = {}, levels = {}, unplaced = {}, context = {} }
    if not data then return journal end
    local byMap, name = {}, self:CharacterName()
    for _, entry in ipairs(facts.zones) do
        local chapter = { mapID = entry.id, fact = entry.fact, quests = {}, turnIns = 0 }
        journal.chapters[#journal.chapters + 1] = chapter
        byMap[entry.id] = chapter
    end
    for _, entry in ipairs(facts.quests) do
        local chapter = byMap[entry.fact.mapID]
        local list = chapter and chapter.quests or journal.unplaced
        list[#list + 1] = entry
        if chapter then chapter.turnIns = chapter.turnIns + entry.fact.turnInCount end
    end
    table.sort(journal.chapters, function(a, b)
        if a.fact.lastVisitedAt ~= b.fact.lastVisitedAt then
            return a.fact.lastVisitedAt > b.fact.lastVisitedAt end
        return a.mapID < b.mapID
    end)
    for chapterIndex, chapter in ipairs(journal.chapters) do
        local zone, lines = chapter.fact, {}
        chapter.zoneName = zone.nameSnapshot or MS.L.JOURNEY_JOURNAL_CHAPTER_FALLBACK
        chapter.title = string.format(MS.L.JOURNEY_JOURNAL_CHAPTER_TITLE, chapterIndex, chapter.zoneName)
        chapter.period = self:JournalDateLabel(zone.firstVisitedAt)
        if zone.lastVisitedAt > zone.firstVisitedAt then chapter.period = string.format(
            MS.L.JOURNEY_JOURNAL_PERIOD, chapter.period, self:JournalDateLabel(zone.lastVisitedAt)) end
        chapter.timestamp = zone.firstVisitedAt
        local firstTrace = string.format(MS.L.JOURNEY_JOURNAL_TRACE, self:JournalDateLabel(zone.firstVisitedAt))
        if zone.firstVisitedLevel then firstTrace = firstTrace .. " " ..
            string.format(MS.L.JOURNEY_JOURNAL_TRACE_LEVEL, name, zone.firstVisitedLevel) end
        lines[#lines + 1] = firstTrace
        if #chapter.quests > 0 then
            lines[#lines + 1] = string.format(MS.L[#chapter.quests == 1 and "JOURNEY_JOURNAL_QUEST_ONE"
                or "JOURNEY_JOURNAL_QUEST_PROSE"], #chapter.quests)
        end
        local chronicles = MS.Chronicles
        if chronicles and chronicles.available and chronicles.registry then
            local ok, count = pcall(function()
                local region = chronicles.registry:GetRegionByMapID(chapter.mapID)
                local summary = region and chronicles:GetRegionSummary(region)
                return summary and summary.discovered
            end)
            if ok and type(count) == "number" and count >= 0 then
                chapter.chronicleCount = count
                if count > 0 then lines[#lines + 1] = string.format(MS.L.JOURNEY_JOURNAL_CHRONICLES, count) end
            end
        end
        chapter.expanded = self.expandedZones[chapter.mapID] == true
        for index = 1, chapter.expanded and #chapter.quests or math.min(3, #chapter.quests) do
            local quest = chapter.quests[index].fact
            lines[#lines + 1] = string.format(MS.L.JOURNEY_JOURNAL_QUEST,
                quest.titleSnapshot or MS.L.JOURNEY_QUEST_DETAILS, self:DateLabel(quest.lastTurnedInAt))
        end
        chapter.context = table.concat(lines, "\n")
    end
    local current = byMap[data.character.lastMapID]
    if current then
        journal.context[#journal.context + 1] = string.format(MS.L.JOURNEY_JOURNAL_CONTEXT, current.zoneName)
    end
    local prior = facts.sessions[1] and facts.sessions[1].fact
    if prior then
        journal.recap = { startedAt = prior.startedAt, endedAt = prior.endedAt,
            lastObservedAt = prior.lastObservedAt, interrupted = prior.interrupted,
            questTurnIns = prior.questTurnIns, xpGained = prior.xpGained,
            startLevel = prior.startLevel, endLevel = prior.endLevel }
        local recap = { string.format(MS.L.JOURNEY_JOURNAL_RETURN, self:DateLabel(prior.startedAt)) }
        if prior.duration and prior.duration >= 60 then
            local minutes = math.floor(prior.duration / 60)
            local durationKey = prior.interrupted and "JOURNEY_JOURNAL_RECAP_OBSERVED" or "JOURNEY_JOURNAL_RECAP_DURATION"
            if minutes == 1 then durationKey = durationKey .. "_ONE" end
            recap[#recap + 1] = string.format(MS.L[durationKey], minutes)
        end
        if prior.questTurnIns and prior.questTurnIns > 0 then recap[#recap + 1] =
            string.format(MS.L[prior.questTurnIns == 1 and "JOURNEY_JOURNAL_RECAP_QUEST_ONE"
                or "JOURNEY_JOURNAL_RECAP_QUESTS"], prior.questTurnIns) end
        if prior.startLevel and prior.endLevel and prior.endLevel > prior.startLevel then
            recap[#recap + 1] = string.format(MS.L.JOURNEY_JOURNAL_SESSION_LEVELS, prior.startLevel, prior.endLevel)
        end
        if prior.interrupted then recap[#recap + 1] = string.format(MS.L.JOURNEY_JOURNAL_CHECKPOINT,
            self:DateLabel(prior.lastObservedAt))
        elseif prior.endedAt then recap[#recap + 1] = string.format(MS.L.JOURNEY_JOURNAL_ENDED, self:DateLabel(prior.endedAt)) end
        journal.recapText = table.concat(recap, " ")
    end
    if data.character.firstSeenAt then
        journal.start = { timestamp = data.character.firstSeenAt }
        for _, entry in ipairs(data.milestones) do
            if entry.type == "LEVEL_REACHED" and entry.timestamp == journal.start.timestamp then
                journal.start.level = entry.level; break
            end
        end
        local beginning = string.format(MS.L.JOURNEY_JOURNAL_START, self:JournalDateLabel(journal.start.timestamp))
        if journal.start.level then beginning = string.format(MS.L.JOURNEY_JOURNAL_START_LEVEL,
            self:JournalDateLabel(journal.start.timestamp), name, journal.start.level) end
        journal.context[#journal.context + 1] = beginning
    end
    journal.context[#journal.context + 1] = MS.L[journal.start and "JOURNEY_JOURNAL_PARTIAL" or "JOURNEY_JOURNAL_PARTIAL_UNKNOWN"]
    for _, entry in ipairs(facts.milestones) do
        -- Zone/quest milestones are represented by their durable chapter facts.
        -- Observations and tracked level gains remain secondary details.
        if entry.type == "LEVEL_REACHED" then journal.levels[#journal.levels + 1] = entry end
    end
    return journal
end

local function PlaceSection(view, section, x, y, width, entries)
    y = y + Place(section.heading, view.content, x, y, width, section.heading:GetText()) + 8
    section.rule:ClearAllPoints(); section.rule:SetPoint("TOPLEFT", view.content, "TOPLEFT", x, -y)
    section.rule:SetSize(width, 1); y = y + 13
    if #entries == 0 then entries = { { title = MS.L.JOURNEY_MEMORY_NONE } } end
    for index, entry in ipairs(entries) do
        local row = section.rows[index]
        if not row then
            row = { title = Label(view.content, "BODY", "textPrimary"),
                detail = Label(view.content, "SMALL", "textSecondary") }
            section.rows[index] = row
        end
        y = y + Place(row.title, view.content, x, y, width, entry.title) + 2
        if entry.detail and entry.detail ~= "" then
            y = y + Place(row.detail, view.content, x, y, width, entry.detail) + 10
        else row.detail:Hide(); y = y + 10 end
    end
    for index = #entries + 1, #section.rows do
        section.rows[index].title:Hide(); section.rows[index].detail:Hide()
    end
    return y + 15
end

local function HideSection(section)
    section.heading:Hide(); section.rule:Hide()
    for _, row in ipairs(section.rows) do row.title:Hide(); row.detail:Hide() end
end

local function ChapterReading(chapter)
    local view, zone = View, chapter.fact
    local first = view:RecentDate(zone.firstVisitedAt)
    local last = view:RecentDate(zone.lastVisitedAt)
    local facts = { first == last and first or string.format(MS.L.JOURNEY_JOURNAL_PERIOD, first, last) }
    if zone.firstVisitedLevel then
        facts[#facts + 1] = string.format(MS.L.JOURNEY_UI_FIRST_LEVEL, zone.firstVisitedLevel)
    end
    if #chapter.quests > 0 then facts[#facts + 1] = string.format(
        MS.L[#chapter.quests == 1 and "JOURNEY_UI_REMEMBERED_QUEST" or "JOURNEY_UI_REMEMBERED_QUESTS"], #chapter.quests) end
    if chapter.chronicleCount and chapter.chronicleCount > 0 then
        facts[#facts + 1] = string.format(MS.L.JOURNEY_JOURNAL_CHRONICLES, chapter.chronicleCount)
    end
    local lines = { table.concat(facts, " · ") }
    -- Community (experimental): moments the player chose to keep in this region.
    if MS.Community and MS.Community.ChapterLines then
        for _, line in ipairs(MS.Community:ChapterLines(chapter.mapID)) do lines[#lines + 1] = line end
    end
    for index = 1, chapter.expanded and #chapter.quests or math.min(3, #chapter.quests) do
        lines[#lines + 1] = string.format(MS.L.JOURNEY_CHAPTER_QUEST,
            chapter.quests[index].fact.titleSnapshot or MS.L.JOURNEY_QUEST_DETAILS)
    end
    return table.concat(lines, "\n")
end

function View:Refresh()
    if not self.visible or not self.frame or not self.dirty then return end
    local facts = self:Collect()
    local status = MS.JourneyMemory:GetStatus()
    local journal = self:Journal(facts)
    self.milestoneCount, self.zoneCount = #facts.milestones, #facts.zones
    self.sessionCount, self.questCount = #facts.sessions, #facts.quests
    local width = self.content:GetWidth()
    local readingWidth, x = MS.JourneyUIStyle:ReadingColumn(width)
    self.readingWidth, self.readingMargin = readingWidth, x
    self.layoutMode = "READING"
    local spacing = MS.JourneyUIStyle.space
    local y = spacing.lg
    y = y + Place(self.title, self.content, x, y, readingWidth, MS.L.JOURNEY_JOURNAL_TITLE, 1) + spacing.sm
    y = y + Place(self.subtitle, self.content, x, y, readingWidth, self:IdentityLine()) + spacing.md
    if journal.recapText then
        y = y + Place(self.recapHeading, self.content, x, y, readingWidth, MS.L.JOURNEY_JOURNAL_LAST_ADVENTURE) + spacing.sm
        y = y + Place(self.recapText, self.content, x, y, readingWidth, self:AdventureText(facts.sessions[1].fact), 5) + spacing.md
    else self.recapHeading:Hide(); self.recapText:Hide() end
    y = y + Place(self.journalContext, self.content, x, y, readingWidth, self:StartContext(journal)) + spacing.md
    self.headerRule:ClearAllPoints(); self.headerRule:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -y)
    self.headerRule:SetSize(readingWidth, 8); y = y + spacing.md
    y = y + Place(self.chronicleHeading, self.content, x, y, readingWidth, MS.L.JOURNEY_JOURNAL_CHAPTERS) + spacing.md
    self.empty:SetShown(#journal.chapters == 0)
    if #journal.chapters == 0 then y = y + Place(self.empty, self.content, x, y, readingWidth, MS.L.JOURNEY_MEMORY_EMPTY) + spacing.md end
    -- One decision per refresh drives the badge, the card colour and the accent together.
    local currentZone = MS.JourneyMapData:PlayerLocalZone()
    if self.artCurrentZone ~= currentZone then
        self.artCache = {}; self.artCurrentZone = currentZone
    end
    self.currentChapterMapID = nil
    for index, chapter in ipairs(journal.chapters) do
        local row = TimelineRow(self, index)
        local isCurrent = currentZone ~= nil and currentZone == chapter.mapID
        row.isCurrent = isCurrent
        if isCurrent then self.currentChapterMapID = chapter.mapID end
        local chapterY, textX, textWidth = y, x + 64, math.max(1, readingWidth - 80)
        local layout = self:ChapterArtLayout(chapter.mapID)
        local bannerHeight = self:ChapterBannerHeight()
        local placed, artSource = MS.JourneyChapterArt:Render(row, self.content, layout, textX, y, textWidth, bannerHeight)
        row.artState = not layout and "NO_USABLE_ART" or placed > 0 and "RENDERED" or "TEXTURE_REJECTED"
        row.artSource = artSource
        row.artTiles, row.mapID = placed, chapter.mapID
        if placed > 0 then y = y + bannerHeight + spacing.sm end
        row.dot:ClearAllPoints(); row.dot:SetPoint("TOPLEFT", self.content, "TOPLEFT", x - 8, -y-6); row.dot:Show()
        row.date:Hide()
        MS.JourneyUIStyle:ChapterMarker(row.marker, index)
        MS.JourneyUIStyle:Heading(row.marker, "CHAPTER_MARKER", "inkSecondary")
        Place(row.marker, self.content, x + spacing.sm, y, 52, row.marker:GetText(), 1)
        MS.JourneyUIStyle:Heading(row.title, "CHAPTER_TITLE", "ink")
        local titleHeight = Place(row.title, self.content, textX, y,
            math.max(1, textWidth - (isCurrent and 96 or 0)), chapter.zoneName)
        if isCurrent then
            Place(row.current, self.content, textX + textWidth - 88, y, 88, MS.L.JOURNEY_CHAPTER_CURRENT)
        else row.current:Hide() end
        y = y + titleHeight + spacing.sm
        y = y + Place(row.context, self.content, textX, y, textWidth, ChapterReading(chapter)) + spacing.sm
        if #chapter.quests > 3 then
            row.details.mapID = chapter.mapID
            row.details:ClearAllPoints(); row.details:SetPoint("TOPLEFT", self.content, "TOPLEFT", textX, -y)
            row.details:SetSize(textWidth, 26)
            row.details.label:SetText(chapter.expanded and MS.L.JOURNEY_JOURNAL_COLLAPSE
                or string.format(MS.L.JOURNEY_JOURNAL_OTHER_QUESTS, #chapter.quests - 3))
            row.details:Show(); y = y + 34
        else row.details:Hide() end
        row.paper:ClearAllPoints(); row.paper:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -chapterY + spacing.sm)
        row.paper:SetSize(readingWidth, y - chapterY + spacing.md); row.paper:Show()
        -- Past chapters sit on the page material so only the current chapter reads as highlighted.
        MS.JourneyUIStyle:Color(row.paper, isCurrent and "paperSelected" or "paperRaised")
        row.accent:ClearAllPoints(); row.accent:SetPoint("TOPLEFT", row.paper, "TOPLEFT")
        row.accent:SetSize(3, y - chapterY + spacing.md); row.accent:SetShown(isCurrent)
        row.line:ClearAllPoints(); row.line:SetPoint("TOPLEFT", self.content, "TOPLEFT", x - 6, -chapterY-14)
        row.line:SetSize(1, math.max(1, y - chapterY + 40)); row.line:SetShown(index < #journal.chapters)
        y = y + spacing.md
        row.separator:ClearAllPoints(); row.separator:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -y)
        row.separator:SetSize(readingWidth, 1); row.separator:Show(); y = y + spacing.md
    end
    for index = #journal.chapters + 1, #self.timelineRows do
        local row = self.timelineRows[index]
        row.isCurrent = false; row.accent:Hide()
        MS.JourneyChapterArt:Hide(row); row.current:Hide(); row.date:Hide(); row.title:Hide(); row.context:Hide(); row.marker:Hide(); row.dot:Hide(); row.line:Hide(); row.details:Hide(); row.separator:Hide(); row.paper:Hide()
    end
    self.sidebarRule:Hide()
    self.archiveButton:ClearAllPoints(); self.archiveButton:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -y)
    self.archiveButton:SetSize(readingWidth, 30)
    self.archiveButton.label:SetText(self.showArchives and MS.L.JOURNEY_JOURNAL_HIDE_ARCHIVES or MS.L.JOURNEY_JOURNAL_ARCHIVES)
    y = y + 42
    if self.showArchives then
        y = y + Place(self.summary, self.content, x, y, readingWidth, string.format(MS.L.JOURNEY_MEMORY_SUMMARY,
            status.maxLevel or MS.L.JOURNEY_UNKNOWN, #facts.zones, #facts.quests, #facts.sessions)) + spacing.md
        local levels, sessions, quests = {}, {}, {}
        for _, entry in ipairs(journal.levels) do levels[#levels + 1] = { title = entry.title, detail = self:RecentDate(entry.timestamp) } end
        for index = 1, math.min(5, #facts.sessions) do
            local entry = facts.sessions[index]
            sessions[#sessions + 1] = { title = self:RecentDate(entry.fact.startedAt), detail = SessionText(entry.fact) }
        end
        for _, entry in ipairs(journal.unplaced) do quests[#quests + 1] = { title = entry.fact.titleSnapshot or MS.L.JOURNEY_QUEST_DETAILS,
            detail = self:RecentDate(entry.fact.lastTurnedInAt) } end
        y = PlaceSection(self, self.memorySections[1], x, y, readingWidth, levels)
        y = PlaceSection(self, self.memorySections[2], x, y, readingWidth, sessions)
        if #facts.sessions > 5 then
            y = y + Place(self.olderSessions, self.content, x, y, readingWidth,
                string.format(MS.L.JOURNEY_JOURNAL_OLDER_SESSIONS, #facts.sessions - 5)) + 20
        else self.olderSessions:Hide() end
        y = PlaceSection(self, self.memorySections[3], x, y, readingWidth, quests)
    else
        self.summary:Hide(); self.olderSessions:Hide()
        for _, section in ipairs(self.memorySections) do HideSection(section) end
    end
    local bottom = y + spacing.md
    self.content:SetHeight(math.max(self.frame:GetHeight(), bottom))
    self.paper:ClearAllPoints(); self.paper:SetPoint("TOPLEFT", self.content, "TOPLEFT", x - math.min(24, x), -12)
    self.paper:SetSize(readingWidth + math.min(24, x) * 2, bottom - 24)
    self.edge:ClearAllPoints(); self.edge:SetPoint("TOPLEFT", self.content, "TOPLEFT", x - math.min(24, x), -12)
    self.edge:SetSize(2, math.max(1, bottom - 24))
    local maximum = math.max(0, self.content:GetHeight() - self.frame:GetHeight())
    self.frame:SetVerticalScroll(math.min(maximum, self.frame:GetVerticalScroll()))
    self.dirty, self.refreshCount = false, self.refreshCount + 1
end

function View:GetStatus()
    local missing = {}
    for mapID, texture in pairs(self.artCache or {}) do if texture == false then missing[#missing + 1] = mapID end end
    table.sort(missing)
    local rendered, sources = {}, {}
    for _, row in ipairs(self.timelineRows or {}) do
        if row.mapID and row.title:IsShown() then rendered[row.mapID] = row.artState; sources[row.mapID] = row.artSource end
    end
    return { visible = self.visible, dirty = self.dirty, refreshCount = self.refreshCount,
        chapterArtUnavailableMapIDs = missing, chapterArtRenderStates = rendered, chapterArtSources = sources,
        milestoneCount = self.milestoneCount, zoneCount = self.zoneCount,
        sessionCount = self.sessionCount, questCount = self.questCount }
end
