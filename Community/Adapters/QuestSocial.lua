local MS = _G.MS
MS.Community = MS.Community or {}
-- Quest social actions (experimental, behind groupingAssist). One action, three doors: the
-- proactive card (POPUP), the quest page (QUEST_DETAIL) and the Journey right-click menu
-- (CONTEXT_MENU). Journey prepares the text, the native chat line carries it, the player sends.
-- Diagnostics record the gesture and its outcome, never the text.
local C = MS.Community
local S = {}
C.QuestSocial = S

local Call = C.Call  -- pcall + secret-value filtering
-- The single social intent; diagnostics keep the field so CEX-6.1 journals read the same.
S.INTENT = "FIND_GROUP"

-- Running only while the groupingAssist feature (flag + capabilities) runs.
function S:Enabled() return C:IsRunning("AssistTriggers") end

function S:PlayerFacts(title, link)
    return { title = title, link = link, className = Call(_G.UnitClass, "player"), level = Call(_G.UnitLevel, "player"),
        place = Call(_G.GetSubZoneText), zone = Call(_G.GetZoneText) }
end

-- A message the player has started in the active chat line is never overwritten. The text is
-- only tested for emptiness: never kept, never logged.
local function DraftPresent()
    local active = type(_G.ChatEdit_GetActiveWindow) == "function" and Call(_G.ChatEdit_GetActiveWindow) or nil
    if type(active) ~= "table" or type(active.GetText) ~= "function" then return false end
    local text = Call(active.GetText, active)
    return type(text) == "string" and text:find("%S") ~= nil
end

-- Journey is the second screen and the chat line is on the game screen: say on Journey where
-- the message went (or why it did not). The proactive card of the same quest gives way to it.
-- Lowest priority (ASK_READY): an acknowledgement never holds back a real moment.
S.feedbackSeconds = 6
function S:Feedback(questID, title, headingKey, lineKey)
    local Card, A, L = C.MomentCard, C.AssistTriggers, MS.L
    if Card:IsShowing("ASK") and A.visibleQuest == questID then
        A.visibleQuest = nil
        Card:Close("USED")
    end
    -- A newer acknowledgement replaces the previous one (same priority would refuse it).
    if Card:IsShowing("ASK_READY") then Card:Close("REPLACED") end
    local shown = Card:Show({ kind = "ASK_READY", heading = L[headingKey], title = title, lines = { L[lineKey] },
        duration = self.feedbackSeconds, onClose = function() S.readyQuest = nil end })
    self.readyQuest = shown and questID or nil
end

-- The acknowledgement leaves with its quest (questID) or with the feature (nil).
function S:WithdrawFeedback(questID)
    if self.readyQuest and (questID == nil or questID == self.readyQuest) and C.MomentCard:IsShowing("ASK_READY") then
        C.MomentCard:Close("WITHDRAWN")
    end
end

-- Opens the native chat line only. No SendChatMessage: the last gesture stays the player's.
function S:Prefill(questID, source)
    local intent = self.INTENT
    C:Log("QUEST_CHAT_PREFILL_REQUESTED", { quest = questID, source = source, intent = intent })
    local function Fail(reason)
        C:Log("QUEST_CHAT_PREFILL_FAILED", { quest = questID, source = source, intent = intent, reason = reason })
        return false, reason
    end
    if not self:Enabled() then return Fail("FEATURE_OFF") end
    local title = C.QuestFacts:LogEntry(questID)
    if not title then return Fail("QUEST_GONE") end
    local link, linkFailure = C.QuestFacts:NativeLink(questID)
    local text, used = C.GroupingAssist.Compose(MS.L, self:PlayerFacts(title, link))
    if not text then return Fail("NO_TEXT") end
    if used == "NATIVE" then
        C:Log("QUEST_NATIVE_LINK_AVAILABLE", { quest = questID, source = source })
        C:Prove("QuestLink", "QUEST_NATIVE_LINK_AVAILABLE")
    else C:Log("QUEST_NATIVE_LINK_FALLBACK", { quest = questID, source = source, reason = linkFailure or "TOO_LONG" }) end
    local open = _G.ChatFrame_OpenChat
    if type(open) ~= "function" then return Fail("NATIVE_CHAT_UNAVAILABLE") end
    if DraftPresent() then
        self:Feedback(questID, title, "COMMUNITY_SOCIAL_DRAFT_HEADING", "COMMUNITY_SOCIAL_DRAFT")
        return Fail("DRAFT_PRESENT")
    end
    if not pcall(open, text) then return Fail("NATIVE_CHAT_ERROR") end
    C:Log("QUEST_CHAT_PREFILL_SUCCESS", { quest = questID, source = source, intent = intent, link = used })
    C:Prove("ChatPrefill", "QUEST_CHAT_PREFILL_SUCCESS")
    self:Feedback(questID, title, "COMMUNITY_SOCIAL_READY_HEADING", "COMMUNITY_SOCIAL_READY")
    return true
end

function S:Select(questID, source)
    C:Log("QUEST_SOCIAL_ACTION_SELECTED", { quest = questID, source = source, intent = self.INTENT })
    return self:Prefill(questID, source)
end

-- The one action for one of the player's own quests, with the same words on every door.
-- QUEST_DETAIL: only for a quest the game marks as a group activity. CONTEXT_MENU: any quest.
function S:Actions(quest, surface)
    local questID = type(quest) == "table" and quest.questID
    if not self:Enabled() or type(questID) ~= "number" or not C.QuestFacts:LogEntry(questID) then return nil end
    if surface == "QUEST_DETAIL" and not C.QuestFacts:GroupFact(questID) then return nil end
    if surface ~= "QUEST_DETAIL" and surface ~= "CONTEXT_MENU" then return nil end
    return { { id = self.INTENT, label = MS.L.COMMUNITY_SOCIAL_FIND, rank = 10, social = true,
        run = function() return S:Select(questID, surface) end } }
end

S.provider = {
    Actions = function(_, quest, surface) return S:Actions(quest, surface) end,
    Opened = function(_, quest, where, actions)
        local count = 0
        for _, action in ipairs(actions or {}) do if action.social then count = count + 1 end end
        if count > 0 then
            C:Log("QUEST_SOCIAL_ACTION_OPENED", { quest = quest.questID, source = "CONTEXT_MENU", surface = where, actions = count })
        end
    end,
}

-- The quest page and the menu ask Journey's registry; Community only answers.
function S:Changed()
    if MS.JourneyQuestActions and MS.JourneyQuestActions.Changed then MS.JourneyQuestActions:Changed() end
end
if MS.JourneyQuestActions and MS.JourneyQuestActions.Register then
    MS.JourneyQuestActions:Register("CommunityQuestSocial", S.provider)
end
