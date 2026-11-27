local MS = _G.MS

-- The Parcours tab: the page of the day, written live on the second screen while the player plays.
-- Newest facts on top, a dungeon as one block that opens on its bosses, the day's numbers on the right.
-- Every animation is optional decoration (JourneyMotion): the page reads the same without it.
MS.JourneyDayView = { visible = false, dirty = true, refreshCount = 0, rows = {}, dayButtons = {},
    bossRows = {}, mates = {}, open = nil, pending = {} }
local View = MS.JourneyDayView

local GUTTER, ICON, GAP = 46, 26, 10
local INDEX_WIDTH, SIDE_WIDTH, BANNER_HEIGHT = 176, 232, 118
local WIDE, MEDIUM = 980, 640
local ICONS = {
    LOGIN = "Interface\\Icons\\INV_Misc_Rune_01", ZONE = "Interface\\Icons\\INV_Misc_Map_01",
    FIRST = "Interface\\Icons\\INV_Misc_Spyglass_02", QUEST = "Interface\\GossipFrame\\ActiveQuestIcon",
    LEVEL = "Interface\\Icons\\Spell_ChargePositive", DEATH = "Interface\\Icons\\Ability_Rogue_FeignDeath",
    KILLS = "Interface\\Icons\\Ability_DualWield", GROUP = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
    DUNGEON = "Interface\\Icons\\INV_Misc_Head_Dragon_01", INK = "Interface\\Icons\\INV_Misc_Book_09",
}
local TONES = { DEATH = { .88, .45, .35 }, LEVEL = { .44, .61, .91 }, QUEST = { .93, .73, .39 },
    DUNGEON = { .79, .54, .90 }, NOW = { .49, .83, .44 } }
local GOLD, LIVE = "ffe8b65a", "ff7ed36f"

local function Now() return type(_G.time) == "function" and time() or 0 end
local function Secret(value) return type(_G.issecretvalue) == "function" and issecretvalue(value) == true end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end
local function Style() return MS.JourneyUIStyle end
local function Paint(text, hex) return "|c" .. hex .. text .. "|r" end
local function Hidden() return MS.BroadcastMode and MS.BroadcastMode:IsOn() == true end

-- Formatting -----------------------------------------------------------------------------------------

function View:Clock(stamp)
    if type(stamp) ~= "number" or type(_G.date) ~= "function" then return "" end
    local hours, minutes = Call(date, "%H", stamp), Call(date, "%M", stamp)
    return string.format(MS.L.JOURNEY_DAY_CLOCK, tonumber(hours) or 0, tonumber(minutes) or 0)
end

function View:Duration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local hours, minutes = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
    if hours > 0 then return string.format(MS.L.JOURNEY_DAY_HOURS, hours, minutes) end
    return string.format(MS.L.JOURNEY_DAY_MINUTES, math.max(1, minutes))
end

function View:Number(value)
    local text = tostring(math.max(0, math.floor(value or 0)))
    local head, parts = #text % 3, {}
    if head > 0 then parts[1] = text:sub(1, head) end
    for index = head + 1, #text, 3 do parts[#parts + 1] = text:sub(index, index + 2) end
    return table.concat(parts, MS.L.JOURNEY_DAY_THOUSANDS)
end

function View:Name(name)
    if Hidden() or type(name) ~= "string" or name == "" then return MS.L.JOURNEY_DAY_COMPANION_HIDDEN end
    return name
end

local function ClassHex(class)
    local color = type(_G.RAID_CLASS_COLORS) == "table" and class and _G.RAID_CLASS_COLORS[class]
    if type(color) ~= "table" or type(color.r) ~= "number" then return nil end
    return string.format("ff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
end

local function ClassName(class)
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    return type(names) == "table" and class and names[class] or nil
end

-- What one line of the feed says: { icon, title, meta, tone }. Pure: the tests read it.
function View:Describe(entry, ordinal)
    local L, kind = MS.L, entry.kind
    local zone = type(entry.zone) == "string" and entry.zone or ""
    if kind == "LOGIN" then
        return { icon = ICONS.LOGIN, title = string.format(L.JOURNEY_DAY_LOGIN, zone),
            meta = string.format(L.JOURNEY_DAY_LOGIN_META, ordinal or 1) }
    elseif kind == "ZONE" then
        local flown = type(entry.from) == "string" and string.format(L.JOURNEY_DAY_FLIGHT_META, entry.from) or nil
        if entry.first then
            return { icon = ICONS.FIRST, title = string.format(L.JOURNEY_DAY_FIRST, Paint(zone, GOLD)),
                meta = flown or L.JOURNEY_DAY_FIRST_META, tone = TONES.QUEST }
        end
        return { icon = ICONS.ZONE, title = string.format(L.JOURNEY_DAY_ZONE, Paint(zone, GOLD)), meta = flown }
    elseif kind == "QUEST" then
        local title = type(entry.title) == "string" and entry.title or L.JOURNEY_QUEST_DETAILS
        return { icon = ICONS.QUEST, title = string.format(L.JOURNEY_DAY_QUEST, Paint(title, GOLD)),
            meta = zone ~= "" and zone or nil, tone = TONES.QUEST }
    elseif kind == "LEVEL" then
        local level = tonumber(entry.level) or 0
        local meta = zone
        if type(entry.seconds) == "number" and entry.seconds > 0 and level > 1 then
            local spent = string.format(L.JOURNEY_DAY_LEVEL_META, self:Duration(entry.seconds), level - 1)
            meta = meta ~= "" and (meta .. " · " .. spent) or spent
        end
        return { icon = ICONS.LEVEL, title = Paint(string.format(L.JOURNEY_DAY_LEVEL, level), "ff8fb4f0"),
            meta = meta ~= "" and meta or nil, tone = TONES.LEVEL }
    elseif kind == "DEATH" then
        local place = type(entry.subzone) == "string" and entry.subzone ~= "" and entry.subzone ~= zone
            and (zone .. ", " .. entry.subzone) or zone
        local meta
        if type(entry.killer) == "string" and entry.killer ~= "" then
            local who = entry.killer
            if type(entry.killerLevel) == "number" then
                who = who .. ", " .. string.format(L.JOURNEY_DAY_LEVEL_SHORT,
                    entry.killerLevel > 0 and tostring(entry.killerLevel) or "??")
            end
            if entry.killerElite then who = who .. " " .. L.JOURNEY_DAY_ELITE end
            meta = string.format(entry.guessed and L.JOURNEY_DAY_KILLED_GUESS or L.JOURNEY_DAY_KILLED_BY, who)
        end
        return { icon = ICONS.DEATH, title = Paint(L.JOURNEY_DAY_DEATH, "ffe0735a") .. (place ~= "" and (" · " .. place) or ""),
            meta = meta, tone = TONES.DEATH }
    elseif kind == "KILLS" then
        local count = tonumber(entry.count) or 0
        local text = string.format(count == 1 and L.JOURNEY_DAY_KILLS_ONE or L.JOURNEY_DAY_KILLS_MANY, count)
        return { icon = ICONS.KILLS, title = Paint(text, GOLD), meta = zone ~= "" and zone or nil }
    elseif kind == "INK" then
        return { icon = ICONS.INK, title = string.format(L.INK_PARCOURS_FINISHED, Paint(entry.title or "?", GOLD), entry.author or "?"),
            tone = TONES.QUEST }
    elseif kind == "GROUP" then
        local hex = not Hidden() and ClassHex(entry.class)
        local name = self:Name(entry.name)
        local meta = {}
        local class = ClassName(entry.class)
        if class then meta[#meta + 1] = class end
        if type(entry.level) == "number" and entry.level >= 1 then meta[#meta + 1] = string.format(L.JOURNEY_DAY_LEVEL_SHORT, tostring(entry.level)) end
        return { icon = ICONS.GROUP, title = string.format(L.JOURNEY_DAY_GROUP, hex and Paint(name, hex) or Paint(name, GOLD)),
            meta = #meta > 0 and table.concat(meta, ", ") or nil }
    end
end

-- The dungeon's bosses in the game's order, each marked beaten or not; bosses beaten but unknown to the
-- table come after. { name, npcID, at, beaten }.
function View:Bosses(entry)
    local list, seen, beaten = {}, {}, {}
    for _, boss in ipairs(type(entry.bosses) == "table" and entry.bosses or {}) do
        if type(boss) == "table" and boss.encounterID then beaten[boss.encounterID] = boss end
    end
    local french = Call(_G.GetLocale) == "frFR"
    local known = MS.JourneyDungeonBosses and entry.id and MS.JourneyDungeonBosses[entry.id]
    for _, info in ipairs(type(known) == "table" and known or {}) do
        local id, done = info[1], beaten[info[1]]
        seen[id] = true
        list[#list + 1] = { name = done and done.name or (french and info[3] or info[2]),
            npcID = done and done.npcID, at = done and done.at, beaten = done ~= nil }
    end
    for _, boss in ipairs(type(entry.bosses) == "table" and entry.bosses or {}) do
        if type(boss) == "table" and not seen[boss.encounterID] then
            list[#list + 1] = { name = boss.name or "?", npcID = boss.npcID, at = boss.at, beaten = true }
        end
    end
    return list
end

function View:DungeonMeta(entry)
    local L, parts = MS.L, {}
    local beaten = 0
    for _, boss in ipairs(self:Bosses(entry)) do if boss.beaten then beaten = beaten + 1 end end
    local since, last = entry.since or entry.at, entry.at
    parts[1] = self:Clock(since) .. " – " .. (entry.done and self:Clock(last) or L.JOURNEY_DAY_IN_PROGRESS)
    if type(since) == "number" and type(last) == "number" and last > since then parts[#parts + 1] = self:Duration(last - since) end
    local total = tonumber(entry.total) or #self:Bosses(entry)
    if total > 0 then
        parts[#parts + 1] = string.format(L.JOURNEY_DAY_BOSSES_OF, beaten, total)
    end
    return table.concat(parts, " · ")
end

function View:DungeonTitle(entry)
    local name = Paint(type(entry.name) == "string" and entry.name or "?", "ffc98ae6")
    local mates = {}
    for _, mate in ipairs(type(entry.companions) == "table" and entry.companions or {}) do
        mates[#mates + 1] = self:Name(mate)
        if #mates == 4 then break end
    end
    if #mates == 0 then return name end
    return name .. ", " .. string.format(MS.L.JOURNEY_DAY_WITH, table.concat(mates, ", "))
end

-- Ink tales this character finished on that day (L'Encre keeps them; the day log does not).
function View:InkEntries(day)
    local ink, list = MS.Ink, {}
    if type(day) ~= "table" or not ink or type(ink.Ready) ~= "function" or not ink:Ready() or type(ink.bucket) ~= "table" then return list end
    for id, progress in pairs(type(ink.bucket.progress) == "table" and ink.bucket.progress or {}) do
        local at = type(progress) == "table" and progress.finishedAt
        if type(at) == "number" and Call(_G.date, "%Y-%m-%d", at) == day.key then
            local entry = Call(ink.Entry, ink, id)
            local tale = type(entry) == "table" and type(entry.tale) == "table" and entry.tale or {}
            list[#list + 1] = { kind = "INK", at = at, title = tale.title, author = tale.author }
        end
    end
    return list
end

-- The feed of a day, newest first, with the breaks between sessions. { entry | pause seconds }.
function View:Feed(day)
    local entries = type(day) == "table" and type(day.entries) == "table" and day.entries or {}
    local sorted = {}
    for _, entry in ipairs(entries) do
        -- Joins saved before the game knew the player ("Unknown") say nothing.
        local unknown = type(entry) == "table" and entry.kind == "GROUP" and (entry.name == _G.UNKNOWNOBJECT or entry.name == _G.UNKNOWN)
        if not unknown and type(entry) == "table" and type(entry.at) == "number" and (entry.kind == "DUNGEON" or ICONS[entry.kind]) then
            sorted[#sorted + 1] = entry
        end
    end
    for _, entry in ipairs(self:InkEntries(day)) do sorted[#sorted + 1] = entry end
    table.sort(sorted, function(a, b) return a.at < b.at end)
    local feed, logins, previous = {}, 0, nil
    for _, entry in ipairs(sorted) do
        if entry.kind == "LOGIN" then
            logins = logins + 1
            if previous and entry.at - previous >= 600 then feed[#feed + 1] = { pause = entry.at - previous } end
        end
        feed[#feed + 1] = { entry = entry, ordinal = logins }
        previous = math.max(previous or 0, entry.at)
    end
    local reversed = {}
    for index = #feed, 1, -1 do reversed[#reversed + 1] = feed[index] end
    return reversed
end

-- Widgets ----------------------------------------------------------------------------------------------

local function Label(parent, size, color, justify)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Style():Apply(label, size); Style():Text(label, color)
    label:SetJustifyH(justify or "LEFT"); label:SetJustifyV("TOP")
    if type(label.SetWordWrap) == "function" then label:SetWordWrap(true) end
    return label
end

local function Fill(parent, layer, token)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    if token then Style():Color(texture, token) end
    return texture
end

-- Sets a label's text and width at a point; returns its height.
local function Place(label, parent, x, y, width, text)
    label:SetHeight(0); label:SetWidth(math.max(1, width)); label:SetText(text or "")
    label:ClearAllPoints(); label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y); label:Show()
    local ok, height = pcall(label.GetStringHeight, label)
    if not ok or type(height) ~= "number" or height <= 0 then
        local _, size = label:GetFont(); height = size or 14
    end
    height = math.ceil(height); label:SetHeight(height)
    return height
end

local function Box(frame, parent, x, y, width, height)
    frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    frame:SetSize(math.max(1, width), math.max(1, height)); frame:Show()
end

local function Icon(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder.back = Fill(holder, "BACKGROUND", "backgroundDeep"); holder.back:SetAllPoints(holder)
    holder.edge = Fill(holder, "BORDER", "borderMuted")
    holder.edge:SetPoint("TOPLEFT", holder, "TOPLEFT", -1, 1); holder.edge:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 1, -1)
    holder.icon = holder:CreateTexture(nil, "ARTWORK")
    holder.icon:SetPoint("TOPLEFT", holder, "TOPLEFT", 1, -1); holder.icon:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -1, 1)
    if type(holder.icon.SetTexCoord) == "function" then holder.icon:SetTexCoord(.08, .92, .08, .92) end
    return holder
end

function View:Row(index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, self.content)
    row.back = Fill(row, "BACKGROUND"); row.back:SetAllPoints(row)
    row.rule = Fill(row, "BORDER", "borderMuted"); row.rule:SetHeight(1)
    row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT"); row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT")
    row.time = Label(row, "SECONDARY", "textSecondary", "RIGHT")
    row.icon = Icon(row, ICON)
    row.title = Label(row, "BODY", "textPrimary")
    row.meta = Label(row, "SECONDARY", "textSecondary")
    row.pause = Label(row, "SECONDARY", "textSecondary", "CENTER")
    row.chevron = Label(row, "SECONDARY", "gold", "RIGHT")
    row.faces = {}
    row:SetScript("OnClick", function(button)
        if button.dungeon then
            local key = button.dungeon.since or button.dungeon.at
            self.open = self.open ~= key and key or nil
            self.selectedBoss = nil
            self:Invalidate()
        end
    end)
    self.rows[index] = row
    return row
end

local function HideRow(row)
    row:Hide(); row.dungeon, row.entry = nil, nil
    for _, face in ipairs(row.faces) do face.frame:Hide() end
end

-- Page -------------------------------------------------------------------------------------------------

function View:Create(parent)
    if self.frame then return end
    self.frame = CreateFrame("ScrollFrame", nil, parent)
    self.content = CreateFrame("Frame", nil, self.frame); self.content:SetSize(1, 1)
    self.frame:SetScrollChild(self.content); self.frame:EnableMouseWheel(true)
    self.frame:SetScript("OnMouseWheel", function(frame, delta)
        local maximum = math.max(0, self.content:GetHeight() - frame:GetHeight())
        frame:SetVerticalScroll(math.max(0, math.min(maximum, frame:GetVerticalScroll() - delta * 40)))
    end)
    self.back = Fill(self.content, "BACKGROUND", "backgroundDeep"); self.back:SetAllPoints(self.content)
    self.indexTitle = Label(self.content, "SECTION", "gold")
    self.sideTitle = Label(self.content, "SECTION", "gold")
    self.empty = Label(self.content, "BODY_LARGE", "textSecondary")
    self.pastTitle = Label(self.content, "TITLE", "gold")
    self.pastMeta = Label(self.content, "SECONDARY", "textSecondary")
    self:CreateBanner(); self:CreateSide()
    self.frame:Hide()
end

function View:CreateBanner()
    self.art = {}
    local banner = CreateFrame("Frame", nil, self.content)
    banner:SetFrameLevel(self.content:GetFrameLevel() + 4)
    banner.plain = Fill(banner, "BACKGROUND", "backgroundRaised"); banner.plain:SetAllPoints(banner)
    banner.shade = banner:CreateTexture(nil, "OVERLAY", nil, -2); banner.shade:SetAllPoints(banner)
    banner.shade:SetColorTexture(1, 1, 1, 1)
    local shaded = type(_G.CreateColor) == "function" and pcall(banner.shade.SetGradient, banner.shade, "HORIZONTAL",
        CreateColor(.08, .055, .03, .94), CreateColor(.08, .055, .03, 0))
    if not shaded then
        banner.shade:SetColorTexture(.08, .055, .03, .6)
    end
    banner.edge = Fill(banner, "OVERLAY", "borderMuted"); banner.edge:SetHeight(1)
    banner.edge:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT"); banner.edge:SetPoint("BOTTOMRIGHT", banner, "BOTTOMRIGHT")
    banner.now = Label(banner, "SECONDARY", "textSecondary")
    banner.place = Label(banner, "TITLE", "gold")
    banner.who = Label(banner, "BODY", "textPrimary")
    if MS.JourneyFaces then
        local ok, hero = pcall(MS.JourneyFaces.NewHero, MS.JourneyFaces, banner)
        if ok and hero then
            banner.hero = hero
            hero.frame:SetSize(66, 92); hero.frame:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", 10, 6)
        end
    end
    self.banner = banner
end

function View:CreateSide()
    local cards = {}
    local function Card()
        local card = CreateFrame("Frame", nil, self.content)
        card.back = Fill(card, "BACKGROUND", "backgroundPanel"); card.back:SetAllPoints(card)
        cards[#cards + 1] = card
        return card
    end
    local time = Card()
    time.label = Label(time, "SECONDARY", "textSecondary"); time.value = Label(time, "TITLE", "gold")
    time.note = Label(time, "SECONDARY", "textSecondary")
    local level = Card()
    level.label = Label(level, "SECONDARY", "textSecondary"); level.note = Label(level, "SECONDARY", "textSecondary")
    level.barBack = Fill(level, "ARTWORK", "backgroundDeep")
    level.bar = level:CreateTexture(nil, "OVERLAY"); level.bar:SetColorTexture(.37, .55, .88, 1)
    level.spark = level:CreateTexture(nil, "OVERLAY")
    level.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    if type(level.spark.SetBlendMode) == "function" then level.spark:SetBlendMode("ADD") end
    level.spark:SetSize(16, 22)
    local numbers = Card()
    numbers.cells = {}
    for index, key in ipairs({ "JOURNEY_DAY_QUESTS", "JOURNEY_DAY_KILLS", "JOURNEY_DAY_BOSSES", "JOURNEY_DAY_DEATHS" }) do
        numbers.cells[index] = { key = key, label = Label(numbers, "SECONDARY", "textSecondary"), value = Label(numbers, "TITLE", "textPrimary") }
    end
    local mates = Card()
    mates.label = Label(mates, "SECONDARY", "textSecondary")
    self.side = { time = time, level = level, numbers = numbers, mates = mates, cards = cards }
end

function View:Layout(rect)
    if not self.frame then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    self.frame:SetSize(rect.width, rect.height)
    self.content:SetWidth(math.max(1, rect.width - 12))
    local scale = MS.JourneySettings:Get("textScale")
    if self.width ~= rect.width or self.scale ~= scale then self.width, self.scale, self.dirty = rect.width, scale, true end
    self:Refresh()
end

function View:SetVisible(visible)
    self.visible = visible == true
    if self.frame then self.frame:SetShown(self.visible) end
    if self.visible then
        self:Listen(); self.dirty = true; self:Refresh(); self:StartTicker()
    else
        self:StopTicker(); self.pending = {}
        if MS.JourneyMotion then pcall(MS.JourneyMotion.StopAll, MS.JourneyMotion) end
        if self.stage then pcall(self.stage.Stop, self.stage) end
    end
end

function View:Invalidate()
    self.dirty = true
    self:Refresh()
end

-- Live: new facts while the page is open play their short arrival; nothing animates on opening.
function View:Listen()
    if self.listening or not MS.JourneyDayLog or type(MS.JourneyDayLog.Listen) ~= "function" then return end
    self.listening = true
    MS.JourneyDayLog:Listen(function(kind, entry)
        if not self.visible then self.dirty = true; return end
        if (self.selected or self:TodayKey()) ~= self:TodayKey() then return end
        if (kind == "ADD" or kind == "UPDATE") and type(entry) == "table" then
            self.pending[#self.pending + 1] = { kind = kind, entry = entry }
        end
        self:Invalidate()
    end)
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_DEAD", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event)
        if not self.visible then return end
        if event == "PLAYER_XP_UPDATE" then self:RefreshLevel(true) else self:RefreshHero() end
    end)
    self.events = events
end

function View:StartTicker()
    if self.ticker or type(_G.C_Timer) ~= "table" or type(C_Timer.NewTicker) ~= "function" then return end
    self.ticker = C_Timer.NewTicker(30, function()
        if self.visible then self:RefreshClocks() end
    end)
end

function View:StopTicker()
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
end

function View:TodayKey()
    local log = MS.JourneyDayLog
    return log and type(log.TodayKey) == "function" and log:TodayKey() or nil
end

function View:SelectedDay()
    local log = MS.JourneyDayLog
    if not log then return nil end
    local key = self.selected or self:TodayKey()
    return log:Day(key), key
end

function View:Refresh()
    if not self.frame or not self.visible or not self.dirty then return end
    self.dirty = false
    self.refreshCount = self.refreshCount + 1
    local width = math.max(320, self.content:GetWidth())
    local mode = width >= WIDE and "WIDE" or width >= MEDIUM and "MEDIUM" or "NARROW"
    local pad = 16
    local top = pad
    local mainX, mainWidth, sideX, sideY
    if mode == "WIDE" then
        local indexHeight = self:PlaceIndex(pad, top, INDEX_WIDTH, false)
        mainX = pad + INDEX_WIDTH + 18
        mainWidth = width - mainX - SIDE_WIDTH - 18 - pad
        sideX, sideY = width - SIDE_WIDTH - pad, top
        self.indexBottom = top + indexHeight
    else
        local indexHeight = self:PlaceIndex(pad, top, width - pad * 2, true)
        top = top + indexHeight + 14
        mainX = pad
        if mode == "MEDIUM" then
            mainWidth = width - pad * 2 - SIDE_WIDTH - 18
            sideX, sideY = width - SIDE_WIDTH - pad, top
        else
            mainWidth = width - pad * 2
        end
        self.indexBottom = top
    end
    local day, key = self:SelectedDay()
    local today = key ~= nil and key == self:TodayKey()
    local y = top
    y = y + self:PlaceHeader(day, today, mainX, y, mainWidth) + 12
    y = self:PlaceFeed(day, mainX, y, mainWidth)
    local sideBottom
    if mode == "NARROW" then
        sideBottom = self:PlaceSide(day, today, pad, y + 18, width - pad * 2)
    else
        sideBottom = self:PlaceSide(day, today, sideX, sideY, SIDE_WIDTH)
    end
    self.content:SetHeight(math.max(y, sideBottom or 0, self.indexBottom or 0) + pad)
    self:PlayPending()
end

function View:PlaceIndex(x, y, width, strip)
    local log, days = MS.JourneyDayLog, {}
    if log and type(log.Days) == "function" then days = log:Days() or {} end
    local today = self:TodayKey()
    local height = 0
    if not strip then
        height = Place(self.indexTitle, self.content, x, y, width, MS.L.JOURNEY_DAY_DAYS) + 8
    else
        self.indexTitle:Hide()
    end
    local columns = strip and math.max(1, math.floor(width / 170)) or 1
    local cellWidth = strip and math.floor((width - (columns - 1) * 4) / columns) or width
    local shown = strip and math.min(#days, columns * 2) or math.min(#days, 14)
    local rowY = y + height
    for index = 1, math.max(shown, #self.dayButtons) do
        local button = self.dayButtons[index]
        local day = days[index]
        if index <= shown and day then
            if not button then
                button = CreateFrame("Button", nil, self.content)
                button.back = Fill(button, "BACKGROUND", "parchmentDark"); button.back:SetAllPoints(button)
                button.name = Label(button, "BODY", "textPrimary"); button.note = Label(button, "SECONDARY", "textSecondary")
                button:SetScript("OnClick", function(self_)
                    View.selected = self_.key ~= today and self_.key or nil
                    View.open, View.selectedBoss = nil, nil
                    View:Invalidate()
                end)
                self.dayButtons[index] = button
            end
            button.key = day.key
            local column = strip and (index - 1) % columns or 0
            local line = strip and math.floor((index - 1) / columns) or index - 1
            local selected = (self.selected or today) == day.key
            Style():Color(button.back, selected and "backgroundRaised" or "parchmentDark")
            Style():Text(button.name, selected and "gold" or "textPrimary")
            local bx = x + column * (cellWidth + 4)
            local name = self:DayName(day, today)
            local nameHeight = Place(button.name, button, 9, 6, cellWidth - 18, name)
            local noteHeight = Place(button.note, button, 9, 6 + nameHeight + 1, cellWidth - 18, self:DayNote(day, today))
            local buttonHeight = nameHeight + noteHeight + 13
            Box(button, self.content, bx, strip and (rowY + line * (buttonHeight + 4)) or rowY, cellWidth, buttonHeight)
            if not strip then rowY = rowY + buttonHeight + 2
            elseif column == columns - 1 or index == shown then rowY = rowY + buttonHeight + 4 end
        elseif button then
            button:Hide()
        end
    end
    return rowY - y
end

function View:DayName(day, today)
    if day.key == today then return MS.L.JOURNEY_DAY_TODAY .. "  " .. Paint(MS.L.JOURNEY_DAY_LIVE, LIVE) end
    local progression = MS.JourneyProgressionView
    local stamp = day.firstAt
    if progression and type(progression.RecentDate) == "function" then
        local ok, text = pcall(progression.RecentDate, progression, stamp)
        if ok and type(text) == "string" then return (text:gsub("^%l", string.upper)) end
    end
    return day.key
end

function View:DayNote(day, today)
    local progression = MS.JourneyProgressionView
    if day.key == today and progression and type(progression.JournalDateLabel) == "function" then
        local ok, text = pcall(progression.JournalDateLabel, progression, day.firstAt)
        if ok and type(text) == "string" then return text end
    end
    local parts = { self:Duration(day.playSeconds or 0) }
    if day.startLevel and day.endLevel and day.endLevel > day.startLevel then
        parts[2] = string.format(MS.L.JOURNEY_DAY_LEVELS, day.startLevel, day.endLevel)
    elseif day.endLevel or day.startLevel then
        parts[2] = string.format(MS.L.JOURNEY_DAY_LEVEL_SHORT, tostring(day.endLevel or day.startLevel))
    end
    return table.concat(parts, " · ")
end

-- The banner of today (where the player is now), or the date of a past day.
function View:PlaceHeader(day, today, x, y, width)
    local banner = self.banner
    if not today then
        banner:Hide(); MS.JourneyChapterArt:Hide(self.art)
        local progression = MS.JourneyProgressionView
        local title = day and day.key or ""
        if day and progression and type(progression.JournalDateLabel) == "function" then
            local ok, text = pcall(progression.JournalDateLabel, progression, day.firstAt)
            if ok and type(text) == "string" then title = text end
        end
        local height = Place(self.pastTitle, self.content, x, y, width, title)
        return height + 4 + Place(self.pastMeta, self.content, x, y + height + 4, width, day and self:DayNote(day) or "")
    end
    self.pastTitle:Hide(); self.pastMeta:Hide()
    Box(banner, self.content, x, y, width, BANNER_HEIGHT)
    local current = MS.JourneyDayLog and MS.JourneyDayLog:Current() or {}
    local live = _G.C_Map and Call(C_Map.GetBestMapForUnit, "player")
    local zoneMap = self:ZoneMap(not Secret(live) and type(live) == "number" and live or current.mapID)
    if zoneMap ~= self.artMap or self.artWidth ~= width then
        self.artMap, self.artWidth = zoneMap, width
        MS.JourneyChapterArt:Hide(self.art)
        local snapshot = zoneMap and MS.JourneyChapterArt:Capture(zoneMap)
        local placed = 0
        if snapshot then
            local ok, count = pcall(MS.JourneyChapterArt.Render, MS.JourneyChapterArt, self.art, banner, snapshot, 0, 0, width, BANNER_HEIGHT)
            placed = ok and count or 0
        end
        banner.plain:SetShown(placed == 0)
    end
    local textX = banner.hero and 90 or 14
    banner.place:SetWidth(math.max(1, width - textX - 14)); banner.place:SetText(current.zone or Call(_G.GetZoneText) or "")
    banner.who:SetWidth(math.max(1, width - textX - 14)); banner.who:SetText(self:WhoLine())
    banner.now:SetWidth(math.max(1, width - textX - 14))
    banner.who:ClearAllPoints(); banner.who:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", textX, 12)
    banner.place:ClearAllPoints(); banner.place:SetPoint("BOTTOMLEFT", banner.who, "TOPLEFT", 0, 2)
    banner.now:ClearAllPoints(); banner.now:SetPoint("BOTTOMLEFT", banner.place, "TOPLEFT", 0, 2)
    self:RefreshClocks(); self:RefreshHero()
    return BANNER_HEIGHT
end

-- The zone a map belongs to: the banner shows the whole zone, not a cave or a district.
function View:ZoneMap(mapID)
    local zone = _G.Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local api = _G.C_Map
    for _ = 1, 6 do
        if type(mapID) ~= "number" or not api or type(api.GetMapInfo) ~= "function" then return mapID end
        local info = Call(api.GetMapInfo, mapID)
        if type(info) ~= "table" then return mapID end
        -- A continent or the world would fill the banner with all of Azeroth: better plain.
        if type(info.mapType) == "number" and info.mapType < zone then return nil end
        if info.mapType == zone or not info.parentMapID or info.parentMapID == 0 then return mapID end
        mapID = info.parentMapID
    end
    return mapID
end

function View:WhoLine()
    local parts = {}
    local progression = MS.JourneyProgressionView
    if progression and type(progression.CharacterName) == "function" then
        local ok, name = pcall(progression.CharacterName, progression)
        if ok and type(name) == "string" and not Hidden() then parts[#parts + 1] = name end
    end
    local class = Call(_G.UnitClass, "player")
    if type(class) == "string" and not Secret(class) then parts[#parts + 1] = class end
    local level = Call(_G.UnitLevel, "player")
    if type(level) == "number" and not Secret(level) then parts[#parts + 1] = string.format(MS.L.JOURNEY_DAY_LEVEL_SHORT, tostring(level)) end
    return table.concat(parts, " · ")
end

function View:RefreshClocks()
    local banner = self.banner
    if banner and banner:IsShown() then
        local current = MS.JourneyDayLog and MS.JourneyDayLog:Current() or {}
        local since = type(current.since) == "number" and Now() - current.since or nil
        local when = (not since or since < 60) and MS.L.JOURNEY_DAY_JUST_NOW or string.format(MS.L.JOURNEY_DAY_SINCE, self:Duration(since))
        banner.now:SetText(MS.L.JOURNEY_DAY_NOW .. "  " .. Paint(when, LIVE))
    end
    local day = self:SelectedDay()
    local card = self.side and self.side.time
    if card and day then card.value:SetText(self:Duration(day.playSeconds or 0)) end
end

function View:RefreshHero()
    local hero = self.banner and self.banner.hero
    if not hero then return end
    pcall(hero.Refresh, hero)
    local dead = Call(_G.UnitIsDeadOrGhost, "player")
    pcall(hero.Ghost, hero, not Secret(dead) and dead == true)
end

-- The feed ------------------------------------------------------------------------------------------

function View:PlaceFeed(day, x, y, width)
    local feed = self:Feed(day)
    local used = 0
    self.stageUsed = false
    if #feed == 0 then
        Place(self.empty, self.content, x, y, width, MS.L.JOURNEY_DAY_EMPTY)
        y = y + self.empty:GetHeight() + 12
    else
        self.empty:Hide()
    end
    for _, item in ipairs(feed) do
        used = used + 1
        local row = self:Row(used)
        row.entry, row.dungeon = item.entry, nil
        if item.pause then
            y = y + self:PlacePause(row, item.pause, x, y, width)
        elseif item.entry.kind == "DUNGEON" then
            y = y + self:PlaceDungeon(row, item.entry, x, y, width)
        else
            y = y + self:PlaceFact(row, self:Describe(item.entry, item.ordinal), item.entry, x, y, width)
        end
    end
    for index = used + 1, #self.rows do HideRow(self.rows[index]) end
    if self.stage and not self.stageUsed then self.stage.frame:Hide() end
    return y
end

function View:PlacePause(row, seconds, x, y, width)
    row.time:Hide(); row.icon:Hide(); row.title:Hide(); row.meta:Hide(); row.chevron:Hide()
    for _, face in ipairs(row.faces) do face.frame:Hide() end
    row.back:SetColorTexture(0, 0, 0, 0)
    local height = Place(row.pause, row, 0, 8, width, string.format(MS.L.JOURNEY_DAY_PAUSE, self:Duration(seconds))) + 16
    Box(row, self.content, x, y, width, height)
    return height
end

function View:PlaceFact(row, info, entry, x, y, width)
    row.pause:Hide(); row.chevron:Hide()
    for _, face in ipairs(row.faces) do face.frame:Hide() end
    row.back:SetColorTexture(0, 0, 0, 0)
    local textX = GUTTER + GAP + ICON + GAP
    local textWidth = width - textX - 4
    Place(row.time, row, 0, 9, GUTTER, self:Clock(entry.at))
    local height = Place(row.title, row, textX, 7, textWidth, info and info.title or "")
    if info and info.meta then
        height = height + 2 + Place(row.meta, row, textX, 7 + height + 2, textWidth, info.meta)
    else
        row.meta:Hide()
    end
    height = math.max(ICON, height) + 14
    row.icon.icon:SetTexture(info and info.icon or ICONS.ZONE)
    row.icon:ClearAllPoints(); row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", GUTTER + GAP, -math.floor((height - ICON) / 2)); row.icon:Show()
    row.tone = info and info.tone or TONES.NOW
    Box(row, self.content, x, y, width, height)
    return height
end

function View:Face(row, index, size)
    local face = row.faces[index]
    if not face and MS.JourneyFaces then
        local ok, made = pcall(MS.JourneyFaces.NewPortrait, MS.JourneyFaces, row, size)
        if ok and made then face = made; row.faces[index] = face end
    end
    return face
end

local function ShowBoss(face, boss)
    if not face then return end
    if boss.npcID then pcall(face.SetNPC, face, boss.npcID) else pcall(face.SetIcon, face, ICONS.DUNGEON) end
    pcall(face.SetBeaten, face, not boss.beaten) -- dimmed while not beaten yet
    pcall(face.SetRing, face, boss.beaten and .79 or .35, boss.beaten and .54 or .29, boss.beaten and .90 or .37)
end

function View:PlaceDungeon(row, entry, x, y, width)
    row.pause:Hide()
    row.dungeon = entry
    row.back:SetColorTexture(.20, .14, .21, 1)
    local key = entry.since or entry.at
    local open = self.open == key
    local textX = GUTTER + GAP + ICON + GAP
    local textWidth = width - textX - 28
    Place(row.time, row, 0, 11, GUTTER, self:Clock(entry.at))
    local height = 9 + Place(row.title, row, textX, 9, textWidth, self:DungeonTitle(entry))
    height = height + 2 + Place(row.meta, row, textX, height + 2, textWidth, self:DungeonMeta(entry))
    local bosses = self:Bosses(entry)
    local faceY = height + 6
    for index = 1, math.max(#bosses, #row.faces) do
        local boss = bosses[index]
        local face = boss and self:Face(row, index, 24)
        if face and boss then
            ShowBoss(face, boss)
            face.frame:ClearAllPoints(); face.frame:SetPoint("TOPLEFT", row, "TOPLEFT", textX + (index - 1) * 28, -faceY); face.frame:Show()
        elseif row.faces[index] then
            row.faces[index].frame:Hide()
        end
    end
    if #bosses > 0 then height = faceY + 24 end
    height = height + 10
    row.chevron:SetText(open and "v" or ">")
    row.chevron:ClearAllPoints(); row.chevron:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -12); row.chevron:Show()
    row.icon.icon:SetTexture(ICONS.DUNGEON)
    row.icon:ClearAllPoints(); row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", GUTTER + GAP, -10); row.icon:Show()
    row.tone = TONES.DUNGEON
    if open then height = height + self:PlaceInside(row, entry, bosses, textX, height, width - textX - 12) end
    Box(row, self.content, x, y, width, height)
    return height + 6
end

-- Inside an opened dungeon: the chosen boss on a lit stand, the list of bosses with their times.
function View:PlaceInside(row, entry, bosses, x, y, width)
    local showModels = MS.JourneySettings:Get("showModels") ~= false and MS.JourneyFaces
    local stageWidth = showModels and width >= 360 and 150 or 0
    if stageWidth > 0 then
        if not self.stage then
            local ok, stage = pcall(MS.JourneyFaces.NewStage, MS.JourneyFaces, self.content)
            self.stage = ok and stage or nil
        end
        if self.stage then
            local frame = self.stage.frame
            frame:SetParent(row); frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
            frame:SetSize(stageWidth, 170); frame:Show()
            self.stageUsed = true
        else
            stageWidth = 0
        end
    end
    local listX = x + (stageWidth > 0 and stageWidth + 14 or 0)
    local listWidth = width - (listX - x)
    self.bossRows[row] = self.bossRows[row] or {}
    local list = self.bossRows[row]
    local chosen = self.selectedBoss
    if not chosen then
        for index, boss in ipairs(bosses) do if boss.beaten and boss.npcID then chosen = index end end
    end
    local lineY = y
    for index = 1, math.max(#bosses, #list) do
        local line, boss = list[index], bosses[index]
        if boss then
            if not line then
                line = CreateFrame("Button", nil, row)
                line.hover = Fill(line, "BACKGROUND"); line.hover:SetAllPoints(line); line.hover:SetColorTexture(.79, .54, .90, 0)
                line.name = Label(line, "BODY", "textPrimary"); line.time = Label(line, "SECONDARY", "textSecondary", "RIGHT")
                if MS.JourneyFaces then
                    local ok, face = pcall(MS.JourneyFaces.NewPortrait, MS.JourneyFaces, line, 34)
                    if ok and face then line.face = face; face.frame:SetPoint("LEFT", line, "LEFT", 2, 0) end
                end
                line:SetScript("OnClick", function(self_) View.selectedBoss = self_.index; View:Invalidate() end)
                list[index] = line
            end
            line.index = index
            ShowBoss(line.face, boss)
            line.hover:SetColorTexture(.79, .54, .90, index == chosen and .14 or 0)
            Style():Text(line.name, boss.beaten and "textPrimary" or "textSecondary")
            Place(line.time, line, listWidth - 90, 12, 86, boss.at and self:Clock(boss.at) or MS.L.JOURNEY_DAY_NOT_BEATEN)
            Place(line.name, line, 44, 12, listWidth - 140, boss.name)
            Box(line, row, listX, lineY, listWidth, 38)
            lineY = lineY + 40
        elseif line then
            line:Hide()
        end
    end
    if self.stageUsed then
        local boss = chosen and bosses[chosen]
        local display = boss and boss.npcID and MS.JourneyFaces:Get(boss.npcID)
        if display then
            pcall(self.stage.SetDisplay, self.stage, display)
        elseif boss and boss.npcID then
            MS.JourneyFaces:Resolve(boss.npcID, function(id)
                if id and self.stage and self.visible then pcall(self.stage.SetDisplay, self.stage, id) end
            end)
        end
    end
    return math.max(lineY - y, stageWidth > 0 and 170 or 0) + 10
end

-- The right column -----------------------------------------------------------------------------------

function View:PlaceSide(day, today, x, y, width)
    local L, side = MS.L, self.side
    local top = y
    if width >= SIDE_WIDTH and x > 16 then
        y = y + Place(self.sideTitle, self.content, x, y, width, L.JOURNEY_DAY_THE_DAY) + 8
    else
        self.sideTitle:Hide()
    end
    local inner = width - 26
    -- Play time.
    local card = side.time
    local h = 10 + Place(card.label, card, 13, 10, inner, L.JOURNEY_DAY_PLAYTIME)
    h = h + 2 + Place(card.value, card, 13, h + 2, inner, self:Duration(day and day.playSeconds or 0))
    local sessions = day and day.sessions or 0
    h = h + 2 + Place(card.note, card, 13, h + 2, inner, sessions > 1 and string.format(L.JOURNEY_DAY_SESSIONS, sessions) or L.JOURNEY_DAY_SESSION_ONE)
    Box(card, self.content, x, y, width, h + 11); y = y + h + 11 + 10
    -- Level and experience.
    card = side.level
    self.levelToday = today
    h = self:RefreshLevel(false, day)
    Box(card, self.content, x, y, width, h); y = y + h + 10
    -- Numbers.
    card = side.numbers
    local values = { day and day.quests or 0, day and day.kills, day and day.bosses or 0, day and day.deaths or 0 }
    local cellWidth = math.floor((inner - 12) / 2)
    local rowHeight = 0
    for index, cell in ipairs(card.cells) do
        local cx = 13 + ((index - 1) % 2) * (cellWidth + 12)
        local cy = 10 + math.floor((index - 1) / 2) * (rowHeight + 8)
        local lh = Place(cell.label, card, cx, cy, cellWidth, L[cell.key])
        local value = values[index]
        local old = cell.shown
        local text = value and self:Number(value) or "–"
        local vh = Place(cell.value, card, cx, cy + lh + 1, cellWidth, text)
        if value and old and value > old and MS.JourneyMotion and today then
            pcall(MS.JourneyMotion.Count, MS.JourneyMotion, cell.value, old, value, function(n) return self:Number(n) end)
        end
        cell.shown = value
        rowHeight = math.max(rowHeight, lh + vh + 1)
    end
    h = 10 + rowHeight * 2 + 8 + 10
    Box(card, self.content, x, y, width, h); y = y + h + 10
    -- Companions of the day, longest first.
    card = side.mates
    local mates = {}
    for name, info in pairs(day and type(day.companions) == "table" and day.companions or {}) do
        if type(info) == "table" then mates[#mates + 1] = { name = name, seconds = info.seconds or 0, class = info.class } end
    end
    table.sort(mates, function(a, b) return a.seconds > b.seconds end)
    if #mates == 0 then
        card:Hide()
        for _, line in ipairs(self.mates) do line:Hide() end
    else
        h = 10 + Place(card.label, card, 13, 10, inner, L.JOURNEY_DAY_WITH_YOU) + 6
        for index = 1, math.max(math.min(#mates, 6), #self.mates) do
            local line, mate = self.mates[index], index <= 6 and mates[index]
            if mate then
                if not line then
                    line = CreateFrame("Frame", nil, card)
                    line.icon = line:CreateTexture(nil, "ARTWORK"); line.icon:SetSize(22, 22); line.icon:SetPoint("LEFT", line, "LEFT")
                    line.name = Label(line, "BODY", "textPrimary"); line.time = Label(line, "SECONDARY", "textSecondary", "RIGHT")
                    self.mates[index] = line
                end
                local coords = type(_G.CLASS_ICON_TCOORDS) == "table" and mate.class and _G.CLASS_ICON_TCOORDS[mate.class]
                if coords and not Hidden() then
                    line.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
                    line.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                else
                    line.icon:SetTexture(ICONS.GROUP); line.icon:SetTexCoord(.08, .92, .08, .92)
                end
                local hex = not Hidden() and ClassHex(mate.class)
                local name = self:Name(mate.name)
                Place(line.time, line, inner - 64, 4, 64, self:Duration(mate.seconds))
                Place(line.name, line, 30, 4, inner - 100, hex and Paint(name, hex) or name)
                Box(line, card, 13, h, inner, 26)
                h = h + 28
            elseif line then
                line:Hide()
            end
        end
        Box(card, self.content, x, y, width, h + 8); y = y + h + 8 + 10
    end
    return y
end

-- The level card; also moves the experience bar when experience comes in while the page is open.
function View:RefreshLevel(animate, day)
    local card, L = self.side and self.side.level, MS.L
    if not card then return 0 end
    day = day or self:SelectedDay()
    local inner = (card:GetWidth() or SIDE_WIDTH) - 26
    if inner <= 1 then inner = SIDE_WIDTH - 26 end
    local h = 10
    if self.levelToday then
        local level = Call(_G.UnitLevel, "player")
        local xp, max = Call(_G.UnitXP, "player"), Call(_G.UnitXPMax, "player")
        if Secret(level) or type(level) ~= "number" then level = day and day.endLevel or 0 end
        local fraction = (not Secret(xp) and not Secret(max) and type(xp) == "number" and type(max) == "number" and max > 0) and xp / max or 0
        h = h + Place(card.label, card, 13, h, inner, string.format(L.JOURNEY_DAY_LEVEL_TOWARD, level, level + 1)) + 6
        card.barBack:ClearAllPoints(); card.barBack:SetPoint("TOPLEFT", card, "TOPLEFT", 13, -h); card.barBack:SetSize(inner, 9); card.barBack:Show()
        card.bar:ClearAllPoints(); card.bar:SetPoint("TOPLEFT", card.barBack, "TOPLEFT"); card.bar:SetHeight(9); card.bar:Show()
        card.spark:ClearAllPoints(); card.spark:SetPoint("CENTER", card.barBack, "LEFT", inner * fraction, 0)
        local motion = MS.JourneyMotion
        if animate and motion and card.fraction and fraction > card.fraction then
            pcall(motion.Bar, motion, card.bar, card.spark, fraction, inner)
        else
            card.bar:SetWidth(math.max(1, inner * fraction)); card.spark:SetAlpha(fraction > 0 and .9 or 0); card.spark:Show()
        end
        card.fraction = fraction
        h = h + 9 + 6
    else
        card.barBack:Hide(); card.bar:Hide(); card.spark:Hide()
        local start, finish = day and day.startLevel, day and day.endLevel
        local text = start and finish and finish > start and string.format(L.JOURNEY_DAY_LEVELS, start, finish)
            or string.format(L.JOURNEY_DAY_LEVEL_SHORT, tostring(finish or start or "?"))
        h = h + Place(card.label, card, 13, h, inner, text) + 6
    end
    h = h + Place(card.note, card, 13, h, inner, string.format(L.JOURNEY_DAY_XP_TODAY, self:Number(day and day.xpGained or 0))) + 10
    if animate then card:SetHeight(h) end
    return h
end

-- Live arrivals: the row of a new fact slides in with its mark; a level and a death have their own.
function View:PlayPending()
    if #self.pending == 0 then return end
    local pending = self.pending
    self.pending = {}
    local motion = MS.JourneyMotion
    if not motion then return end
    for _, item in ipairs(pending) do
        for _, row in ipairs(self.rows) do
            if row:IsShown() and (row.entry == item.entry or row.dungeon == item.entry) then
                local tone = row.tone or TONES.NOW
                if item.kind == "ADD" then
                    pcall(motion.Arrive, motion, row, tone[1], tone[2], tone[3])
                    if item.entry.kind == "LEVEL" then
                        pcall(motion.Rays, motion, row.icon)
                        local hero = self.banner and self.banner.hero
                        if hero then pcall(hero.Cheer, hero) end
                    elseif item.entry.kind == "DEATH" then
                        pcall(motion.Tint, motion, row, TONES.DEATH[1], TONES.DEATH[2], TONES.DEATH[3])
                        self:RefreshHero()
                    end
                elseif item.kind == "UPDATE" then
                    pcall(motion.Arrive, motion, row, tone[1], tone[2], tone[3])
                end
                break
            end
        end
    end
end

function View:GetStatus()
    local log = MS.JourneyDayLog
    local days = log and type(log.Days) == "function" and log:Days() or {}
    return { visible = self.visible, refreshCount = self.refreshCount, days = #days,
        selected = self.selected or "TODAY", rows = #self.rows }
end
