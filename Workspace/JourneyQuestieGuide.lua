local MS = _G.MS

-- What QuestieDB adds beside the Journey map, when the player has it. A button under the map turns
-- the right column into the quests to pick up on the shown map: what follows a quest just turned
-- in, how much of the zone is done, each quest, and the zone with most to do at the player's
-- level. Party members who could take a quest too are named.
-- Everything is read from the player's own state; nothing is sent or stored.
local Guide = { MAX_FOLLOW_UPS = 2, SUGGEST_MIN = 3, followUps = {} }
MS.JourneyQuestieGuide = Guide
local O = MS.JourneyQuestieOffers

local function Enabled()
    return MS.JourneySettings:Get("showQuestieOffers") == true and O:BuildIndex() ~= nil
end

local function Completed(questID) return C_QuestLog.IsQuestFlaggedCompleted(questID) == true end

local function MapName(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or tostring(mapID)
end

local function Continent(mapID)
    local guard = 0
    while mapID and guard < 10 do
        local info = C_Map.GetMapInfo(mapID)
        if not info then return nil end
        if info.mapType == (Enum.UIMapType and Enum.UIMapType.Continent or 2) then return mapID end
        mapID, guard = info.parentMapID, guard + 1
    end
    return nil
end

-- Zone of each quest and the quest each one follows: one pass, outside combat, on first need.
function Guide:Index()
    if self.zones then return self.zones end
    if InCombatLockdown() or not O:BuildIndex() then return nil end
    local Quest, areaToUi = O.lib.Quest, O.areaToUi
    local started = debugprofilestop and debugprofilestop()
    local zones, previous = {}, {}
    for _, questID in ipairs(Quest.GetAllIds()) do
        local zone = Quest.Get(questID, "zoneOrSort")
        local uiMapID = type(zone) == "number" and zone > 0 and areaToUi[zone]
        if uiMapID then
            local list = zones[uiMapID] or {}
            zones[uiMapID] = list
            list[#list + 1] = questID
        end
        local nextID = Quest.Get(questID, "nextQuestInChain")
        if type(nextID) == "number" and nextID > 0 then previous[nextID] = questID end
    end
    self.zones, self.previous = zones, previous
    O.stats.guideMs = started and (debugprofilestop() - started) or nil
    return zones
end

-- Quests of a zone this character can ever take, and how many are done.
function Guide:Progress(mapID)
    local zones = self:Index()
    local list = zones and zones[mapID]
    if not list then return 0, 0 end
    local player, done, total = O:Player(), 0, 0
    for _, questID in ipairs(list) do
        if not O.unknown[questID] and O:Fits(questID, player) then
            total = total + 1
            if Completed(questID) then done = done + 1 end
        end
    end
    return done, total
end

function Guide:ProgressLabel(mapID)
    if not Enabled() then return nil end
    local done, total = self:Progress(mapID)
    if total == 0 then return nil end
    return string.format(MS.L.JOURNEY_OFFERS_PROGRESS, done, total)
end

-- Quests to pick up here, worth doing: follow-ups first, then by level. Gray quests stay on the
-- map only, like the game's own trivial quests.
-- Within reach: not repeatable, and at most a little above the player's level.
function Guide:Section(offer, level)
    if offer.repeatable then return "REPEATABLE" end
    if offer.level > 0 and offer.level > level + 2 then return "HARDER" end
    return "REACH"
end

function Guide:Offers(mapID)
    local found = O:Collect(mapID)
    local offers = {}
    for _, quest in ipairs(found) do
        if not quest.trivial then
            local before = self.previous and self.previous[quest.questID]
            quest.follows = before and Completed(before) and before or nil
            offers[#offers + 1] = quest
        end
    end
    table.sort(offers, function(a, b)
        if (a.follows ~= nil) ~= (b.follows ~= nil) then return a.follows ~= nil end
        if a.level ~= b.level then return a.level < b.level end
        return a.questID < b.questID
    end)
    return offers
end

-- The zone with most quests at the player's level, the current continent first.
function Guide:Suggestion(currentMapID)
    if not self.ranking then
        local ranking, level = {}, UnitLevel("player")
        for mapID in pairs(O.index or {}) do
            local count = 0
            for _, quest in ipairs((O:Collect(mapID))) do
                if not quest.trivial and quest.level >= level - 1 and quest.level <= level + 3 then count = count + 1 end
            end
            if count >= self.SUGGEST_MIN then ranking[#ranking + 1] = { mapID = mapID, count = count } end
        end
        table.sort(ranking, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.mapID < b.mapID
        end)
        self.ranking = ranking
    end
    local here = Continent(currentMapID)
    local fallback
    for _, zone in ipairs(self.ranking) do
        if zone.mapID ~= currentMapID then
            if here and Continent(zone.mapID) == here then return zone end
            fallback = fallback or zone
        end
    end
    return fallback
end

-- Party members whose level, race and class allow the quest and who do not have it. Whether they
-- already did it, the game does not tell: the tooltip says so.
function Guide:AlsoFor(questID)
    local group = MS.JourneyGroupQuests
    if not group then return {} end
    local names, Quest = {}, O.lib.Quest
    for _, member in ipairs(group:Members()) do
        local ok, can = pcall(function()
            local who = O:Player(member.unit)
            if type(who.level) ~= "number" or (Quest.Get(questID, "requiredLevel") or 0) > who.level then return false end
            if not O:Fits(questID, who) then return false end
            return C_QuestLog.IsUnitOnQuest == nil or C_QuestLog.IsUnitOnQuest(member.unit, questID) ~= true
        end)
        if ok and can then names[#names + 1] = member.name end
    end
    return names
end

-- Companions' names, or how many they are in streamer mode.
local function Names(names)
    return MS.BroadcastMode and MS.BroadcastMode:People(names) or table.concat(names, ", ")
end

function Guide:AddTooltipLines(tooltip, questID)
    if not questID or not self.previous then return end
    local before = self.previous[questID]
    if before and Completed(before) then
        local name = O.lib.Quest.Get(before, "name")
        if name then tooltip:AddLine(string.format(MS.L.JOURNEY_OFFERS_FOLLOW_UP, name), .85, .75, .5) end
    end
    local names = self:AlsoFor(questID)
    if #names > 0 then
        tooltip:AddLine(string.format(MS.L.JOURNEY_OFFERS_ALSO_TOOLTIP, Names(names)), .6, .8, 1, true)
    end
end

function Guide:Subtitle(offer)
    local parts = {}
    if offer.follows then
        parts[1] = string.format(MS.L.JOURNEY_OFFERS_FOLLOW_UP, O.lib.Quest.Get(offer.follows, "name") or "?")
    else
        local entry, name = offer.entry, nil
        if entry.npcID then name = O.lib.Npc.Get(entry.npcID, "name")
        elseif entry.objectID and O.lib.Object then name = O.lib.Object.Get(entry.objectID, "name") end
        parts[1] = name
    end
    local names = self:AlsoFor(offer.questID)
    if #names > 0 then parts[#parts + 1] = string.format(MS.L.JOURNEY_OFFERS_ALSO, Names(names)) end
    return #parts > 0 and table.concat(parts, "  ·  ") or nil
end

function Guide:IsAvailable()
    return Enabled() and self:Index() ~= nil
end

function Guide:Title(mapID)
    return string.format(MS.L.JOURNEY_OFFERS_TITLE, MapName(mapID))
end

-- The button follows the shown map: its count changes with every zone, by travel or by click.
function Guide:RefreshButton(map, offersMode)
    local button = map.offersButton
    if not button then return end
    -- The column tabs carry the count when they are shown: no second button under the map.
    if not map.mapID or not self:IsAvailable() or map.segmented then button:Hide(); map:PlaceOffersButton(); return end
    -- The same total as the list it opens: within reach, harder and repeatable together.
    local text = offersMode and MS.L.JOURNEY_OFFERS_BACK or string.format(MS.L.JOURNEY_OFFERS_BUTTON, self:OfferCount(map.mapID))
    button.label:SetText(text)
    button:Show()
    map:PlaceOffersButton()
end

function Guide:OfferCount(mapID)
    return #self:Offers(mapID)
end

function Guide:FollowUpsAway(mapID)
    local away = {}
    for _, follow in ipairs(self.followUps) do
        if follow.mapID ~= mapID and not Completed(follow.questID)
            and not C_QuestLog.GetLogIndexForQuestID(follow.questID) then away[#away + 1] = follow end
    end
    return away
end

function Guide:RenderRows(map)
    local mapID = map.mapID
    if not mapID or not self:IsAvailable() then return end
    local L = MS.L
    local offers = self:Offers(mapID)
    local done, total = self:Progress(mapID)
    if total > 0 then map:Row("HEADING", string.format(L.JOURNEY_OFFERS_ZONE_PROGRESS, done, total)) end
    for _, follow in ipairs(self:FollowUpsAway(mapID)) do
        map:Row("LINK", string.format(L.JOURNEY_OFFERS_FOLLOW_UP_AWAY, follow.name, MapName(follow.mapID)), nil,
            function() map:Navigate(follow.mapID) end)
    end
    local sections, level = { REACH = {}, HARDER = {}, REPEATABLE = {} }, UnitLevel("player")
    for _, offer in ipairs(offers) do
        local list = sections[self:Section(offer, level)]
        list[#list + 1] = offer
    end
    for _, section in ipairs({ { "REACH", L.JOURNEY_OFFERS_REACH }, { "HARDER", L.JOURNEY_OFFERS_HARDER },
        { "REPEATABLE", L.JOURNEY_OFFERS_REPEATABLE } }) do
        local list = sections[section[1]]
        if #list > 0 or section[1] == "REACH" then map:Row("HEADING", string.format(section[2], #list)) end
        if #list == 0 and section[1] == "REACH" then map:Row("HEADING", L.JOURNEY_OFFERS_NONE) end
        for _, offer in ipairs(list) do
            local quest = { questID = offer.questID, title = offer.name, level = offer.level, state = "AVAILABLE",
                journeyOffer = true }
            map:Row("QUEST", offer.name or "?", self:Subtitle(offer), function()
                if MS.JourneyMapCanvas then MS.JourneyMapCanvas:Ping(offer.questID) end
            end, quest)
        end
    end
    local suggestion = self:Suggestion(mapID)
    if suggestion then
        map:Row("HEADING", L.JOURNEY_OFFERS_ELSEWHERE)
        map:Row("LINK", string.format(L.JOURNEY_OFFERS_SUGGESTION, MapName(suggestion.mapID), suggestion.count), nil,
            function() map:Navigate(suggestion.mapID) end)
    end
end

-- A quest turned in may open its follow-up: remembered for the session, shown until taken.
function Guide:OnEvent(event, questID)
    self.ranking = nil
    if event == "QUEST_TURNED_IN" and type(questID) == "number" and O.lib then
        local nextID = O.lib.Quest.Get(questID, "nextQuestInChain")
        local mapID = type(nextID) == "number" and nextID > 0 and O.starts and O.starts[nextID]
        if mapID and not O.unknown[nextID] then
            table.insert(self.followUps, 1, { questID = nextID, mapID = mapID, name = O.lib.Quest.Get(nextID, "name") or "?" })
            self.followUps[self.MAX_FOLLOW_UPS + 1] = nil
        end
    end
    if self.renderPending then return end
    self.renderPending = true
    C_Timer.After(0.6, function()
        Guide.renderPending = nil
        local map = MS.MapView
        if map and map.active and map.RenderSidebar then pcall(map.RenderSidebar, map) end
    end)
end

Guide.events = CreateFrame("Frame")
pcall(Guide.events.RegisterEvent, Guide.events, "GROUP_ROSTER_UPDATE")
Guide.events:SetScript("OnEvent", function(_, event) Guide:OnEvent(event) end)
