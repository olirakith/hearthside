local MS = _G.MS

-- The page under the map: what the day told, then one invitation to keep going. Prose only:
-- no counter and no percent. It appears only where the map leaves room for it.
MS.JourneyRoadNote = { MIN_HEIGHT = 130, GAP = 40 }
local Note = MS.JourneyRoadNote
local Style = MS.JourneyUIStyle
local MAX_MOMENTS = 3
local CLOSE_TO_DONE = 50
local CLOSE_TO_LEVEL = .9
local MOMENTS = { ZONE_ENTERED = "JOURNEY_NOTE_ZONE", LEVEL_UP = "JOURNEY_NOTE_LEVEL",
    QUEST_TURNED_IN = "JOURNEY_NOTE_TURNED_IN", DEATH = "JOURNEY_NOTE_DEATH" }

-- The last notable moments, oldest first, as one short paragraph.
function Note:Story(events)
    local moments = {}
    for _, event in ipairs(events or {}) do
        local key = MOMENTS[event.type]
        local text = key and string.format(MS.L[key], tostring(event.detail or ""))
        if text and text ~= moments[#moments] then moments[#moments + 1] = text end
    end
    if #moments == 0 then return MS.L.JOURNEY_NOTE_START end
    return table.concat(moments, " ", math.max(1, #moments - MAX_MOMENTS + 1), #moments)
end

local function Place(quest)
    local data = MS.JourneyQuestData
    return data and data.DisplayPlaceName and data:DisplayPlaceName(quest) or nil
end

local function Percent(quest)
    local percent = quest.progress and quest.progress.percent
    return type(percent) == "number" and percent or 0
end

-- One game fact, the nearest first: what waits here, then what waits elsewhere, then the road.
function Note:Invitation(quests, summary)
    local L, here = MS.L, quests and quests.here or {}
    local away = {}
    for _, list in ipairs({ quests and quests.elsewhere or {}, quests and quests.unlocated or {} }) do
        for _, quest in ipairs(list) do away[#away + 1] = quest end
    end
    for _, quest in ipairs(here) do
        if quest.state == "READY_TO_TURN_IN" then
            return { text = string.format(L.JOURNEY_NOTE_READY_HERE, quest.title), quest = quest }
        end
    end
    for _, quest in ipairs(away) do
        local place = Place(quest)
        if quest.state == "READY_TO_TURN_IN" and place then
            return { text = string.format(L.JOURNEY_NOTE_READY_AWAY, quest.title, place), quest = quest }
        end
    end
    local best
    for _, quest in ipairs(here) do
        if not best or Percent(quest) > Percent(best) then best = quest end
    end
    if best then
        local key = Percent(best) >= CLOSE_TO_DONE and "JOURNEY_NOTE_ALMOST" or "JOURNEY_NOTE_STILL_HERE"
        return { text = string.format(L[key], best.title), quest = best }
    end
    local level, xp, xpMax = summary and summary.level, summary and summary.xp, summary and summary.xpMax
    if type(level) == "number" and type(xp) == "number" and type(xpMax) == "number" and xpMax > 0
        and xp / xpMax >= CLOSE_TO_LEVEL then
        return { text = string.format(L.JOURNEY_NOTE_NEXT_LEVEL, level + 1) }
    end
    local place = away[1] and Place(away[1])
    if place then return { text = string.format(L.JOURNEY_NOTE_STILL_AWAY, away[1].title, place), quest = away[1] } end
    return { text = L.JOURNEY_NOTE_OPEN_ROAD }
end

function Note:Create(parent)
    if self.frame then return end
    self.frame = CreateFrame("Frame", nil, parent)
    self.background = self.frame:CreateTexture(nil, "BACKGROUND")
    self.background:SetAllPoints(self.frame); Style:Material(self.background, "paperRaised")
    self.accent = self.frame:CreateTexture(nil, "ARTWORK")
    self.accent:SetPoint("TOPLEFT", self.frame, "TOPLEFT"); self.accent:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT")
    self.accent:SetWidth(3); Style:Color(self.accent, "paperAccent")
    self.title = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Style:Heading(self.title, "TITLE", "ink")
    self.title:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 20, -14); self.title:SetJustifyH("LEFT")
    self.title:SetText(MS.L.JOURNEY_NOTE_TITLE)
    self.story = self.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Style:Body(self.story, "BODY", "ink"); self.story:SetJustifyH("LEFT")
    self.story:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -8)
    self.invite = self.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Style:Body(self.invite, "BODY", "ink"); self.invite:SetJustifyH("LEFT")
    self.invite:SetPoint("TOPLEFT", self.story, "BOTTOMLEFT", 0, -10)
    self.go = CreateFrame("Button", nil, self.frame)
    self.go:SetPoint("TOPLEFT", self.invite, "BOTTOMLEFT", 0, -6); self.go:SetHeight(22)
    self.goLabel = self.go:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Style:Body(self.goLabel, "BODY", "paperAccent"); self.goLabel:SetAllPoints(self.go)
    self.goLabel:SetJustifyH("LEFT"); self.goLabel:SetText(MS.L.JOURNEY_NOTE_GO)
    Style:Link(self.go, self.goLabel, true)
    self.go:SetScript("OnClick", function()
        if self.quest and MS.MapView then MS.MapView:SelectQuest(self.quest) end
    end)
    self.frame:Hide()
end

-- Sits under the canvas when spare height (below the zone strip) can hold a readable page.
function Note:Place(canvas, spare, scale)
    if not self.frame then return end
    local room = spare - self.GAP
    self.room, self.fits = room, room >= self.MIN_HEIGHT * scale
    self.frame:SetShown(self.fits)
    if not self.fits then return end
    local width = canvas:GetWidth()
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -self.GAP + 8)
    self.frame:SetWidth(width)
    local text = math.max(1, width - 40)
    self.title:SetWidth(text); self.story:SetWidth(text); self.invite:SetWidth(text); self.go:SetWidth(text)
    self:Refresh()
end

function Note:Refresh()
    if not self.frame or not self.fits then return end
    local session = MS.JourneySession
    self.story:SetText(self:Story(session and session.data and session.data.events))
    local invitation = self:Invitation(MS.MapView and MS.MapView.quests, session and session:GetSummary())
    self.invite:SetText(invitation.text)
    self.quest = invitation.quest
    self.go:SetShown(self.quest ~= nil)
    local function Height(label)
        local value = label:GetStringHeight()
        return type(value) == "number" and value or 18
    end
    local needed = 14 + Height(self.title) + 8 + Height(self.story) + 10 + Height(self.invite) + (self.quest and 28 or 0) + 14
    self.frame:SetHeight(math.min(self.room, needed))
end
