local MS = _G.MS
-- What a Journey quest offers, gathered from small providers (Journey itself, Community). The
-- registry decides nothing: each provider answers for one quest and one surface.
--   QUEST_DETAIL: the persistent action on the quest page (first action only).
--   CONTEXT_MENU: the right-click menu on Journey quest rows and map pins.
-- Provider: { Actions = function(self, quest, surface) -> { { id, label, run, rank } } | nil,
--             Opened = optional function(self, quest, where, actions) }.
MS.JourneyQuestActions = { providers = {}, order = {} }
local QA = MS.JourneyQuestActions

function QA:Register(name, provider)
    if type(name) ~= "string" or type(provider) ~= "table" or type(provider.Actions) ~= "function" then return false end
    if not self.providers[name] then self.order[#self.order + 1] = name end
    self.providers[name] = provider
    return true
end

function QA:Collect(quest, surface)
    local actions = {}
    if type(quest) ~= "table" or type(quest.questID) ~= "number" then return actions end
    for _, name in ipairs(self.order) do
        local provider = self.providers[name]
        local ok, list = pcall(provider.Actions, provider, quest, surface)
        for _, action in ipairs(ok and type(list) == "table" and list or {}) do
            if type(action) == "table" and type(action.label) == "string" and type(action.run) == "function" then
                action.order = #actions + 1
                actions[#actions + 1] = action
            end
        end
    end
    table.sort(actions, function(a, b)
        local ra, rb = tonumber(a.rank) or 50, tonumber(b.rank) or 50
        if ra ~= rb then return ra < rb end
        return a.order < b.order
    end)
    return actions
end

function QA:DetailAction(quest)
    return self:Collect(quest, "QUEST_DETAIL")[1]
end

-- where: QUESTS_LIST, MAP_LIST or MAP_PIN. Nothing opens when no provider offers anything.
function QA:OpenMenu(quest, where)
    local menu = MS.JourneyContextMenu
    if not menu then return false, "NO_MENU" end
    local actions = self:Collect(quest, "CONTEXT_MENU")
    local opened, reason = menu:Open({ owner = "QUEST", title = quest and quest.title, actions = actions })
    if not opened then return false, reason end
    for _, name in ipairs(self.order) do
        local provider = self.providers[name]
        if type(provider.Opened) == "function" then pcall(provider.Opened, provider, quest, where, actions) end
    end
    return true
end

-- A provider's offer changed (e.g. a feature switched): an open quest menu is stale and closes,
-- the quest page re-reads its action.
function QA:Changed()
    local menu = MS.JourneyContextMenu
    if menu and menu:IsOpen("QUEST") then menu:Close("CHANGED") end
    local panel = MS.JourneyContextPanel
    if panel and panel.Refresh then
        panel.dirty = true
        panel:Refresh()
    end
end

-- Follow or stop following a quest of the log, wherever its menu opens.
QA:Register("JourneyWatch", {
    Actions = function(_, quest, surface)
        local log = _G.C_QuestLog
        if surface ~= "CONTEXT_MENU" or not log or not log.GetLogIndexForQuestID(quest.questID) then return nil end
        local questID = quest.questID
        if log.GetQuestWatchType(questID) then
            return { { id = "UNWATCH", label = MS.L.JOURNEY_QUEST_UNWATCH, rank = 80,
                run = function() return log.RemoveQuestWatch(questID) end } }
        end
        return { { id = "WATCH", label = MS.L.JOURNEY_QUEST_WATCH, rank = 80,
            run = function() return log.AddQuestWatch(questID) end } }
    end,
})

-- Journey's own action, from QUÊTES: the same destination as the page's "Voir sur la carte".
QA:Register("JourneyMap", {
    Actions = function(_, quest, surface)
        local panel, journey = MS.JourneyContextPanel, MS.JourneyWorkspace
        if surface ~= "CONTEXT_MENU" or not panel or not journey or journey.view ~= "QUESTS" then return nil end
        local context = panel.selectedContext
        if not context or context.type ~= "QUEST" or context.questID ~= quest.questID or not panel:QuestMapID() then return nil end
        local questID = quest.questID
        -- The page may have moved to another quest since the menu opened: never open that one.
        return { { id = "SHOW_MAP", label = MS.L.JOURNEY_QUEST_SHOW_MAP, rank = 90, run = function()
            local current = panel.selectedContext
            if not current or current.type ~= "QUEST" or current.questID ~= questID then return nil end
            return panel:OpenQuestDestination()
        end } }
    end,
})
