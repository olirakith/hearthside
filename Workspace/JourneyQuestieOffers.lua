local MS = _G.MS

-- Experiment: quests to pick up, from QuestieDB when the player has installed it. Journey ships
-- none of its code or data; it only calls the published LibQuestieDB API (docs/api.md) and stays
-- silent when it is absent or too old. The index (map -> quest givers) is built once, outside
-- combat; availability is decided here on every refresh, from the player's own quest state.
local O = { CONTRACT = 3, stats = {}, lines = {}, unknown = {} }
MS.JourneyQuestieOffers = O

local function Note(text) O.lines[#O.lines + 1] = text end

-- Game quest categories (negative zoneOrSort) of holidays and world events: their quests exist
-- only while the event runs. The game calendar says which holiday runs today; the generic
-- "seasonal" category cannot be tied to one holiday and stays hidden.
O.EVENT_SORTS = { [-404] = true, [-402] = true, [-378] = true, [-376] = true, [-375] = true, [-374] = true,
    [-370] = true, [-369] = true, [-366] = true, [-364] = true, [-41] = true, [-22] = true, [-21] = true,
    [-368] = true, [-365] = true, [-241] = true }
-- Calendar holiday -> quest category. Event IDs measured on Forever; names as a fallback
-- (lowercase fragments of the English and French titles).
O.EVENT_BY_ID = { [263] = -364 }
O.EVENT_BY_NAME = {
    { "darkmoon", -364 }, { "sombrelune", -364 }, { "winter veil", -404 }, { "voile d'hiver", -404 },
    { "hallow", -21 }, { "sanssaint", -21 }, { "brewfest", -370 }, { "brasseurs", -370 },
    { "midsummer", -369 }, { "solstice", -369 }, { "lunar festival", -366 }, { "lunaire", -366 },
    { "love is in the air", -376 }, { "amour", -376 }, { "noblegarden", -374 }, { "jardin des nobles", -374 },
    { "children's week", -378 }, { "enfants", -378 }, { "harvest festival", -402 }, { "moissons", -402 },
    { "pilgrim", -375 }, { "pèlerin", -375 }, { "day of the dead", -41 }, { "jour des morts", -41 },
}
O.activeSorts, O.activeEvents = {}, {}

local function Minutes(time) return type(time) == "table" and (time.hour or 0) * 60 + (time.minute or 0) or nil end

function O:EventSort(event)
    local sort = self.EVENT_BY_ID[event.eventID]
    if sort then return sort end
    local title = type(event.title) == "string" and event.title:lower() or ""
    for _, pair in ipairs(self.EVENT_BY_NAME) do
        if title:find(pair[1], 1, true) then return pair[2] end
    end
end

-- Today's holidays, read from the game calendar. The calendar is only read, never moved: moving
-- it fires the very event that triggers this read. Today is found relative to the month it shows.
function O:ReadCalendar()
    if self.readingCalendar then return false end
    self.readingCalendar = true
    local ok, changed = pcall(self.ReadCalendarNow, self)
    self.readingCalendar = false
    return ok and changed == true
end

function O:ReadCalendarNow()
    local calendar, clock = _G.C_Calendar, _G.C_DateAndTime
    if type(calendar) ~= "table" or type(clock) ~= "table" or not clock.GetCurrentCalendarTime then return false end
    local now = clock.GetCurrentCalendarTime()
    if not now or not now.monthDay then return false end
    local offset = 0
    if calendar.GetMonthInfo then
        local shown = calendar.GetMonthInfo(0)
        if type(shown) == "table" and shown.month and shown.year then
            offset = (now.year - shown.year) * 12 + (now.month - shown.month)
        end
    end
    local sorts, names, minute = {}, {}, Minutes(now)
    local ok, count = pcall(calendar.GetNumDayEvents, offset, now.monthDay)
    for index = 1, (ok and count or 0) do
        local got, event = pcall(calendar.GetDayEvent, offset, now.monthDay, index)
        if got and type(event) == "table" and event.calendarType == "HOLIDAY" then
            local started = event.sequenceType ~= "START" or not Minutes(event.startTime) or minute >= Minutes(event.startTime)
            local running = event.sequenceType ~= "END" or not Minutes(event.endTime) or minute < Minutes(event.endTime)
            local sort = started and running and self:EventSort(event)
            if sort then sorts[sort] = true end
            -- Every holiday of today, for the report: id, and the quest category it opens if any.
            names[#names + 1] = string.format("%s#%s%s", tostring(event.title), tostring(event.eventID),
                sort and ("=" .. sort) or "")
        end
    end
    local changed = false
    for sort in pairs(sorts) do if not self.activeSorts[sort] then changed = true end end
    for sort in pairs(self.activeSorts) do if not sorts[sort] then changed = true end end
    self.activeSorts, self.activeEvents, self.calendarRead = sorts, names, time and time() or 0
    return changed
end

function O:AskCalendar()
    local calendar = _G.C_Calendar
    if type(calendar) == "table" and calendar.OpenCalendar then pcall(calendar.OpenCalendar) end
end

-- Bit test without 32-bit operations: QuestieDB masks can exceed 32 bits (Skyborne).
local function HasBit(mask, bit)
    if type(mask) ~= "number" or type(bit) ~= "number" or bit <= 0 then return false end
    return mask % (bit * 2) >= bit
end

function O:Library()
    local lib = _G.LibQuestieDB
    if type(lib) ~= "table" or type(lib.RequireContract) ~= "function" then return nil, "ABSENT" end
    local ok, accepted = pcall(lib.RequireContract, self.CONTRACT)
    if not ok or not accepted then return nil, "CONTRACT" end
    if type(lib.Quest) ~= "table" or type(lib.Npc) ~= "table" then return nil, "SHAPE" end
    return lib
end

-- QuestieDB publishes this table as Lua source: run it as pure data, with an empty environment.
function O:AreaToUiMap(lib)
    local ok, zone = pcall(lib.Support.Get, "ZoneDB")
    local source = ok and type(zone) == "table" and zone.private and zone.private.areaIdToUiMapId
    if type(source) ~= "string" then return nil end
    local chunk = loadstring(source)
    if not chunk then return nil end
    local env = {}
    setfenv(chunk, env)
    local done, result = pcall(chunk)
    if not done then return nil end
    if type(result) ~= "table" then
        for _, value in pairs(env) do if type(value) == "table" then result = value; break end end
    end
    return type(result) == "table" and result or nil
end

-- The zone QuestieDB files a quest under, as a uiMapID; nil for a category or without QuestieDB.
-- Cheap: no index needed, only the zone table, read once.
function O:QuestZone(questID)
    if type(questID) ~= "number" then return nil end
    local lib = self.lib or self:Library()
    if not lib then return nil end
    if self.areaToUi == nil then self.areaToUi = self:AreaToUiMap(lib) or false end
    if not self.areaToUi then return nil end
    local ok, zone = pcall(lib.Quest.Get, questID, "zoneOrSort")
    return ok and type(zone) == "number" and zone > 0 and self.areaToUi[zone] or nil
end

function O:BuildIndex()
    if self.index then return self.index end
    if InCombatLockdown() then return nil, "COMBAT" end
    local lib, reason = self:Library()
    if not lib then self.reason = reason; return nil, reason end
    local areaToUi = self:AreaToUiMap(lib)
    if not areaToUi then self.reason = "ZONES"; return nil, "ZONES" end
    local started = debugprofilestop and debugprofilestop()
    local index, starts, quests, givers = {}, {}, 0, 0
    local Quest = lib.Quest
    -- Quests start at an NPC or at an object (a wanted poster, a book...). A quest started by an
    -- item has no place on a map: the item drops somewhere, it is not found there.
    local function AddStarters(questID, ids, entity, key)
        if type(ids) ~= "table" or type(entity) ~= "table" then return false end
        for _, id in ipairs(ids) do
            local spawns = entity.Get(id, "spawns")
            if type(spawns) == "table" then
                for areaID, points in pairs(spawns) do
                    local uiMapID = areaToUi[areaID]
                    if uiMapID and type(points) == "table" then
                        for _, point in ipairs(points) do
                            if type(point[1]) == "number" and point[1] >= 0 then
                                local list = index[uiMapID] or {}
                                index[uiMapID] = list
                                list[#list + 1] = { questID = questID, [key] = id, x = point[1] / 100, y = point[2] / 100 }
                                starts[questID] = starts[questID] or uiMapID
                                givers = givers + 1
                            end
                        end
                    end
                end
            end
        end
        return #ids > 0
    end
    for _, questID in ipairs(Quest.GetAllIds()) do
        local startedBy = Quest.Get(questID, "startedBy")
        if type(startedBy) == "table" then
            local byNpc = AddStarters(questID, startedBy[1], lib.Npc, "npcID")
            local byObject = AddStarters(questID, startedBy[2], lib.Object, "objectID")
            if byNpc or byObject then quests = quests + 1 end
        end
    end
    self.index, self.lib, self.starts, self.areaToUi = index, lib, starts, areaToUi
    self.stats.quests, self.stats.givers = quests, givers
    self.stats.buildMs = started and (debugprofilestop() - started) or nil
    self:Recheck()
    return index
end

-- Quests the server refused to load are remembered per QuestieDB version and game build, so they
-- do not come back at every login; a new QuestieDB or a new build starts the list again. They are
-- asked for again once per session, quietly: one the server now knows returns to the map.
function O:SourceVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    local name = self.lib and self.lib.addonName or "QuestieDB"
    local ok, version = false, nil
    if type(get) == "function" then ok, version = pcall(get, name, "Version") end
    local build = GetBuildInfo and select(2, GetBuildInfo())
    return tostring(ok and version or "?") .. "|" .. tostring(build)
end

function O:Store()
    if self.store then return self.store end
    local db = MS.Database and MS.Database:Get()
    if type(db) ~= "table" or type(db.journey) ~= "table" then return nil end
    local version = self:SourceVersion()
    local saved = db.journey.questieUnknown
    if type(saved) ~= "table" or saved.version ~= version or type(saved.ids) ~= "table" then
        saved = { version = version, ids = {} }
    end
    db.journey.questieUnknown, self.store = saved, saved
    for questID in pairs(saved.ids) do self.unknown[questID] = true end
    return saved
end

function O:Recheck()
    local store = self:Store()
    if not store or not C_QuestLog.RequestLoadQuestByID then return end
    self.requested = self.requested or {}
    for questID in pairs(store.ids) do
        self.requested[questID] = true
        pcall(C_QuestLog.RequestLoadQuestByID, questID)
    end
end

-- True when the map must redraw.
function O:OnLoadResult(questID, success)
    if not self.requested or not self.requested[questID] then return false end
    local store = self:Store()
    if success == false then
        if self.unknown[questID] then return false end
        self.unknown[questID] = true
        if store then store.ids[questID] = true end
        return true
    end
    if not self.unknown[questID] then return false end
    self.unknown[questID] = nil
    if store then store.ids[questID] = nil end
    return true
end

local function Completed(questID)
    return C_QuestLog.IsQuestFlaggedCompleted(questID) == true
end

-- Race and class only: what a character can ever take, whatever its level or history.
function O:Fits(questID, who)
    local Quest = self.lib.Quest
    local races = Quest.Get(questID, "requiredRaces") or 0
    if races ~= 0 and not HasBit(races, who.raceMask) then return false, "RACE" end
    local classes = Quest.Get(questID, "requiredClasses") or 0
    if classes ~= 0 and not HasBit(classes, who.classMask) then return false, "CLASS" end
    return true
end

-- The player's own state decides; anything QuestieDB cannot tell keeps the quest hidden.
function O:Available(questID, player)
    local Quest = self.lib.Quest
    if C_QuestLog.GetLogIndexForQuestID(questID) or Completed(questID) then return false, "DONE_OR_TAKEN" end
    local sort = Quest.Get(questID, "zoneOrSort") or 0
    if self.EVENT_SORTS[sort] and not self.activeSorts[sort] then return false, "EVENT" end
    local required = Quest.Get(questID, "requiredLevel") or 0
    if required > player.level then return false, "LEVEL" end
    local maxLevel = Quest.Get(questID, "requiredMaxLevel") or 0
    if maxLevel ~= 0 and player.level > maxLevel then return false, "MAX_LEVEL" end
    local fits, why = self:Fits(questID, player)
    if not fits then return false, why end
    for _, other in ipairs(Quest.Get(questID, "exclusiveTo") or {}) do
        if Completed(other) or C_QuestLog.GetLogIndexForQuestID(other) then return false, "EXCLUSIVE" end
    end
    for _, before in ipairs(Quest.Get(questID, "preQuestGroup") or {}) do
        if before > 0 and not Completed(before) then return false, "PREQUEST" end
    end
    local single = Quest.Get(questID, "preQuestSingle")
    if type(single) == "table" and #single > 0 then
        local any = false
        for _, before in ipairs(single) do if Completed(before) then any = true; break end end
        if not any then return false, "PREQUEST" end
    end
    -- A profession requirement cannot be checked cheaply here: such quests stay hidden.
    if Quest.Get(questID, "requiredSkill") then return false, "SKILL" end
    return true
end

function O:Player(unit)
    unit = unit or "player"
    local _, _, raceID = UnitRace(unit)
    local _, _, classID = UnitClass(unit)
    local masks = self.lib.Enum and self.lib.Enum.raceMaskById
    local trivial = type(UnitQuestTrivialLevelRange) == "function" and UnitQuestTrivialLevelRange("player") or 5
    return { level = UnitLevel(unit), raceMask = masks and masks[raceID], classMask = classID and 2 ^ (classID - 1),
        trivial = trivial }
end

-- The quests the player can take on this map, one entry per quest (its first starter here).
function O:Collect(mapID, skip)
    local index = self:BuildIndex()
    local list = index and index[mapID]
    local found, rejected = {}, {}
    if not list then return found, rejected end
    local player, seen = self:Player(), {}
    for _, entry in ipairs(list) do
        local questID = entry.questID
        if self.unknown[questID] then
            rejected.UNKNOWN_ON_SERVER = (rejected.UNKNOWN_ON_SERVER or 0) + 1
        elseif not seen[questID] and not (skip and skip[questID]) then
            seen[questID] = true
            local ok, reason = self:Available(questID, player)
            if ok then
                local Quest = self.lib.Quest
                local questLevel = Quest.Get(questID, "questLevel") or 0
                found[#found + 1] = { questID = questID, entry = entry, name = Quest.Get(questID, "name"),
                    level = questLevel, required = Quest.Get(questID, "requiredLevel") or 0,
                    trivial = questLevel > 0 and questLevel < player.level - player.trivial,
                    repeatable = HasBit(Quest.Get(questID, "specialFlags") or 0, 1) }
            else
                rejected[reason] = (rejected[reason] or 0) + 1
            end
        end
    end
    return found, rejected
end

-- Adds QuestieDB offers to the offers Blizzard's provider is about to show, never replacing one.
function O:AddOffers(offers, mapID)
    if MS.JourneySettings:Get("showQuestieOffers") ~= true then return end
    local found, rejected = self:Collect(mapID, offers)
    self.stats.mapID, self.stats.shown, self.stats.rejected = mapID, #found, rejected
    for _, quest in ipairs(found) do
        local questID, entry = quest.questID, quest.entry
        offers[questID] = {
            questID = questID, questName = quest.name, x = entry.x, y = entry.y,
            startMapID = mapID, mapID = mapID, isQuestStart = true, numObjectives = 0, inProgress = false,
            isHidden = quest.trivial,
            questClassification = Enum.QuestClassification.Normal, questIcon = "QuestNormal", pinLevel = 1,
            pinAlpha = 1, floorLocation = Enum.QuestLineFloorLocation.Same, isLocalStory = false,
            journeyQuestie = { npcID = entry.npcID, objectID = entry.objectID, level = quest.level,
                required = quest.required },
        }
        self:Preload(questID)
    end
end

-- Ask the game for the quest's data now, so any tooltip on it has it at hover time.
function O:Preload(questID)
    if not C_QuestLog.RequestLoadQuestByID or (HaveQuestData and HaveQuestData(questID)) then return end
    self.requested = self.requested or {}
    self.requested[questID] = true
    pcall(C_QuestLog.RequestLoadQuestByID, questID)
end

-- Our own tooltip: Blizzard's waits for quest data the client never loaded for these quests.
function O:ShowTooltip(pin)
    local info = pin.journeyQuestie
    self.stats.tooltips = (self.stats.tooltips or 0) + 1
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip_SetTooltipWaitingForData(GameTooltip, false)
    GameTooltip_SetTitle(GameTooltip, pin.questName or "?")
    -- The quest's own level, coloured like the game colours quest difficulty; then from which level
    -- it can be taken, when that differs.
    if info.level and info.level > 0 then
        local color = type(GetQuestDifficultyColor) == "function" and GetQuestDifficultyColor(info.level)
        local r, g, b = 1, 1, 1
        if type(color) == "table" then r, g, b = color.r or 1, color.g or 1, color.b or 1 end
        GameTooltip:AddLine(string.format(MS.L.JOURNEY_QUESTIE_OFFER_LEVEL, info.level), r, g, b)
    end
    if info.required and info.required > 0 and info.required ~= info.level then
        GameTooltip:AddLine(string.format(MS.L.JOURNEY_QUESTIE_OFFER_REQUIRED, info.required), .8, .8, .8)
    end
    if info.npcID then
        local giver = self.lib and self.lib.Npc.Get(info.npcID, "name")
        if giver then GameTooltip:AddLine(string.format(MS.L.JOURNEY_QUESTIE_OFFER_FROM, giver), 1, 1, 1) end
    elseif info.objectID then
        local object = self.lib and self.lib.Object and self.lib.Object.Get(info.objectID, "name")
        if object then GameTooltip:AddLine(string.format(MS.L.JOURNEY_QUESTIE_OFFER_OBJECT, object), 1, 1, 1) end
    end
    if MS.JourneyQuestieGuide then MS.JourneyQuestieGuide:AddTooltipLines(GameTooltip, pin.questID) end
    GameTooltip:AddLine(MS.L.JOURNEY_QUESTIE_OFFER_SOURCE, .6, .6, .6)
    GameTooltip:Show()
end

function O:Report()
    local lines, lib, reason = {}, self:Library()
    local function add(...) lines[#lines + 1] = string.format(...) end
    add("setting=%s library=%s reason=%s", tostring(MS.JourneySettings:Get("showQuestieOffers")), tostring(lib ~= nil),
        tostring(reason or self.reason))
    if lib then
        add("contract=%s min=%s mode=%s", tostring(lib.contractVersion), tostring(lib.minSupportedContract), tostring(lib.readMode))
    end
    add("indexed=%s quests=%s givers=%s buildMs=%s", tostring(self.index ~= nil), tostring(self.stats.quests),
        tostring(self.stats.givers), self.stats.buildMs and string.format("%.0f", self.stats.buildMs) or "-")
    add("guideMs=%s", self.stats.guideMs and string.format("%.0f", self.stats.guideMs) or "-")
    add("map=%s shown=%s tooltips=%s", tostring(self.stats.mapID), tostring(self.stats.shown), tostring(self.stats.tooltips))
    local unknown = {}
    for questID in pairs(self.unknown) do unknown[#unknown + 1] = tostring(questID) end
    table.sort(unknown)
    add("unknown on server=%d %s", #unknown, table.concat(unknown, ","))
    add("remembered for %s", tostring(self.store and self.store.version))
    add("events today=%s", #self.activeEvents > 0 and table.concat(self.activeEvents, ", ") or "-")
    for why, count in pairs(self.stats.rejected or {}) do add("rejected %s=%d", why, count) end
    return table.concat(lines, "\n")
end

-- Taking, finishing or levelling changes what is available: the map redraws. A quest whose data
-- the server refuses to load does not exist on this server: it leaves the map.
O.events = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "QUEST_DATA_LOAD_RESULT",
    "PLAYER_ENTERING_WORLD", "CALENDAR_UPDATE_EVENT_LIST" }) do
    O.events:RegisterEvent(event)
end
O.events:SetScript("OnEvent", function(_, event, questID, success)
    if event == "PLAYER_ENTERING_WORLD" then O:AskCalendar(); return end
    if event == "CALENDAR_UPDATE_EVENT_LIST" and not O:ReadCalendar() then return end
    if event == "QUEST_DATA_LOAD_RESULT" and not O:OnLoadResult(questID, success) then return end
    if MS.JourneyQuestieGuide then MS.JourneyQuestieGuide:OnEvent(event, questID) end
    local canvas = MS.JourneyMapCanvas
    if canvas and canvas.offers and canvas.frame and canvas.frame:IsVisible() then
        C_Timer.After(0.5, function() pcall(canvas.offers.RefreshAllData, canvas.offers) end)
    end
end)

local Settings = MS.JourneySettings
Settings:Listen(function(key)
    if key ~= "showQuestieOffers" then return end
    local canvas = MS.JourneyMapCanvas
    if canvas and canvas.offers and canvas.frame then pcall(canvas.offers.RefreshAllData, canvas.offers) end
end)
Settings:AddExternalToggle({ id = "showQuestieOffers", label = MS.L.JOURNEY_SETTING_showQuestieOffers,
    hint = MS.L.JOURNEY_SETTINGS_QUESTIE_OFFERS_HINT,
    get = function() return Settings:Get("showQuestieOffers") end,
    set = function(value) Settings:Set("showQuestieOffers", value) end })
