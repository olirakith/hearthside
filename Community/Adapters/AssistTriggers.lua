local MS = _G.MS
MS.Community = MS.Community or {}
-- Grouping assist (experimental, off by default): the proactive door of quest social actions.
-- Trigger: the player accepts a quest the game marks as a group/dungeon activity. One card, one
-- verb; the click goes through QuestSocial like the quest page and the right-click menu.
local C = MS.Community
local A = { feature = "groupingAssist", duration = 180 }
C.AssistTriggers = A

local Call = MS.Community.Call  -- pcall + secret-value filtering

local function InGroup() return (Call(_G.GetNumGroupMembers) or 0) > 1 end

-- The game says "several"; Journey only offers the question when it can help right now.
function A:Blocked(questID)
    if InGroup() then return "IN_GROUP" end
    if Call(_G.IsInInstance) == true then return "INSTANCE" end
    if not C.QuestFacts:GroupFact(questID) then return "QUEST_GONE" end
end

function A:Offer(questID)
    if self.offered[questID] then return end
    local title, fact, size = C.QuestFacts:GroupFact(questID)
    if not title then return end
    local reason = self:Blocked(questID)
    if reason then C:Log("ASSIST_BLOCKED", { quest = questID, reason = reason }); return end
    local L = MS.L
    local shown, failure = C.MomentCard:Show({ kind = "ASK", heading = L.COMMUNITY_ASK_HEADING, title = title,
        lines = { C.GroupingAssist.FactLine(L, fact, size) },
        primary = { label = L.COMMUNITY_SOCIAL_FIND, action = function() A:Ask(questID) end },
        duration = self.duration })
    if not shown then
        -- A temporary refusal does not consume the offer; combat gets one bounded retry.
        if failure == "COMBAT" then self.deferred = questID end
        C:Log("ASSIST_BLOCKED", { quest = questID, reason = failure })
        return
    end
    self.offered[questID] = true
    self.visibleQuest = questID
    C:Log("QUEST_SOCIAL_SUGGESTION_SHOWN", { quest = questID, source = "POPUP", fact = fact })
    -- The game itself just named a freshly accepted quest a group activity.
    C:Prove("QuestGroupFacts", "QUEST_SOCIAL_SUGGESTION_SHOWN")
end

function A:Ask(questID)
    local blocked = self:Blocked(questID)
    if blocked then
        C:Log("ASSIST_BLOCKED", { quest = questID, reason = blocked })
        self:Withdraw(blocked)
        return
    end
    C.QuestSocial:Select(questID, "POPUP")
    -- QuestSocial replaced this card by its acknowledgement when it could; otherwise it is done.
    if self.visibleQuest == questID then
        self.visibleQuest = nil
        C.MomentCard:Close("USED")
    end
end

function A:Withdraw(reason)
    if self.visibleQuest and C.MomentCard:IsShowing("ASK") then C.MomentCard:Close(reason) end
    self.visibleQuest = nil
    C.QuestSocial:WithdrawFeedback(nil)
end

function A:OnEvent(event, first, second)
    if event == "QUEST_ACCEPTED" then
        -- Forever passes only the questID; older clients pass (logIndex, questID).
        local questID = type(second) == "number" and second or first
        if type(questID) == "number" and questID > 0 then self:Offer(questID) end
    elseif event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
        if first == self.visibleQuest then self:Withdraw("QUEST_GONE") end
        C.QuestSocial:WithdrawFeedback(first)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if InGroup() then self:Withdraw("GROUPED") end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if Call(_G.IsInInstance) == true then self:Withdraw("INSTANCE") end
    elseif event == "PLAYER_REGEN_ENABLED" then
        local deferred = self.deferred
        self.deferred = nil
        if deferred then self:Offer(deferred) end
    end
end

function A:Start()
    self.offered, self.visibleQuest = {}, nil
    if not self.frame then
        self.frame = CreateFrame("Frame")
        self.frame:SetScript("OnEvent", function(_, event, ...) A:OnEvent(event, ...) end)
    end
    for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED" }) do
        pcall(self.frame.RegisterEvent, self.frame, event)
    end
end

function A:Stop()
    self.deferred = nil
    if self.frame then self.frame:UnregisterAllEvents() end
    self:Withdraw("STOPPED")
end

C:Register("AssistTriggers", A)
