local MS = _G.MS

-- The right column while a dungeon plan is shown: the player's quests there, those still to take,
-- the bosses in order, beaten ones ticked. QuestieDB, when present, tells which quests belong to it.
MS.JourneyDungeonPanel = { MAX_OFFERS = 15 }
local Panel = MS.JourneyDungeonPanel
local BEATEN = "|TInterface\\RaidFrame\\ReadyCheck-Ready:16:16|t "
local ALIVE = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:16:16|t "

local function Areas(dungeon)
    local set = {}
    for _, area in ipairs(dungeon.areas or {}) do set[area] = true end
    return set
end

-- The names the quest log may file the dungeon under, in the client's language.
local function Names(dungeon)
    local names, map = { [dungeon.name] = true }, _G.C_Map
    for _, area in ipairs(dungeon.areas or {}) do
        local ok, name = false, nil
        if type(map) == "table" and type(map.GetAreaInfo) == "function" then ok, name = pcall(map.GetAreaInfo, area) end
        if ok and type(name) == "string" and name ~= "" then names[name] = true end
    end
    names[""] = nil
    return names
end

-- QuestieDB: filed under the dungeon, or with a creature to slay or meet inside.
local function QuestieHere(questID, areas)
    local O = MS.JourneyQuestieOffers
    local lib = O and (O.lib or O:Library())
    if not lib or type(questID) ~= "number" then return false end
    local ok, here = pcall(function()
        if areas[lib.Quest.Get(questID, "zoneOrSort")] then return true end
        local objectives = lib.Quest.Get(questID, "objectives")
        for _, target in ipairs(type(objectives) == "table" and type(objectives[1]) == "table" and objectives[1] or {}) do
            local npcID = type(target) == "table" and target[1] or target
            local spawns = type(npcID) == "number" and lib.Npc.Get(npcID, "spawns")
            for area in pairs(type(spawns) == "table" and spawns or {}) do
                if areas[area] then return true end
            end
        end
        return false
    end)
    return ok and here == true
end

function Panel:Quests(dungeon, quests)
    local areas, names, list = Areas(dungeon), Names(dungeon), {}
    for _, quest in ipairs(quests or {}) do
        if names[quest.headerName or ""] or QuestieHere(quest.questID, areas) then list[#list + 1] = quest end
    end
    return list
end

-- Quests of the dungeon the player can take now; gray and repeatable ones are left out.
function Panel:Offers(dungeon)
    local O, Guide = MS.JourneyQuestieOffers, MS.JourneyQuestieGuide
    if not O or not Guide or not Guide:IsAvailable() or type(Guide.areas) ~= "table" then return {} end
    local player, list, seen, Quest = O:Player(), {}, {}, O.lib.Quest
    for _, area in ipairs(dungeon.areas or {}) do
        for _, questID in ipairs(Guide.areas[area] or {}) do
            if not seen[questID] and not O.unknown[questID] then
                seen[questID] = true
                local level = Quest.Get(questID, "questLevel") or 0
                local gray = level > 0 and level < player.level - player.trivial
                local repeatable = (Quest.Get(questID, "specialFlags") or 0) % 2 == 1
                if not gray and not repeatable and O:Available(questID, player) then
                    list[#list + 1] = { questID = questID, title = Quest.Get(questID, "name") or "?", level = level,
                        state = "AVAILABLE", journeyOffer = true, mapID = O.starts and O.starts[questID] }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.questID < b.questID
    end)
    return list
end

local function OfferPlace(offer)
    local info = offer.mapID and MS.JourneyMapData:Info(offer.mapID)
    return info and info.name or nil
end

function Panel:Render(map, dungeon)
    local L, QuestData = MS.L, MS.JourneyQuestData
    map.sideTitle:SetText(dungeon.name)
    map.sideTitle:Show()
    for _, button in ipairs(map.segments or {}) do button:Hide() end
    map.segmented, map.nextStepQuest = false, nil
    map.nextStep:Hide()
    map.offersButton:Hide()
    map:LayoutRightColumn()

    local active = map.quests and map.quests.active or {}
    local here = QuestData:ReadyFirst(self:Quests(dungeon, active))
    map:Row("HEADING", L.JOURNEY_DUNGEON_QUESTS:format(#here))
    if #here == 0 then map:Row("NOTE", L.JOURNEY_DUNGEON_NO_QUEST) end
    for _, quest in ipairs(here) do
        local subtitle = quest.state == "IN_PROGRESS" and QuestData:ObjectiveLine(quest) or map:StateLabel(quest.state)
        map:Row("QUEST", quest.title, subtitle, function() map:SelectQuest(quest) end, quest)
    end

    local offers = self:Offers(dungeon)
    if #offers > 0 then
        map:Row("HEADING", L.JOURNEY_DUNGEON_OFFERS:format(#offers))
        for index = 1, math.min(#offers, self.MAX_OFFERS) do
            local offer = offers[index]
            -- Its place is on another map: the click reads that map, "Dungeon plan" comes back.
            map:Row("QUEST", offer.title, OfferPlace(offer), function()
                if offer.mapID then map:Navigate(offer.mapID) end
            end, offer)
        end
    end

    local bosses, done = MS.JourneyDungeonRun:Bosses(dungeon)
    if #bosses > 0 then
        map:Row("HEADING", L.JOURNEY_DUNGEON_BOSSES:format(done, #bosses))
        for _, boss in ipairs(bosses) do
            map:Row("NOTE", (boss.beaten and BEATEN or ALIVE) .. boss.name)
            local row = map.rows[map.rowCount]
            if row then MS.JourneyUIStyle:Text(row.title, boss.beaten and "textSecondary" or "textPrimary") end
        end
    end
    map.status.dungeonQuests, map.status.dungeonOffers, map.status.dungeonBosses = #here, #offers, #bosses
    if #active > #here then
        map:Row("LINK", L.JOURNEY_DUNGEON_ALL_QUESTS:format(#active), nil, function() MS.JourneyWorkspace:SelectView("QUESTS") end)
    end
end
