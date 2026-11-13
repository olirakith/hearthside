local MS = _G.MS

-- Which quests of the player's log a party member also has. The game answers for any member,
-- with or without this addon. Asked at each render, never stored or logged. Up to a party: in a
-- raid the question stops meaning anything.
MS.JourneyGroupQuests = { refreshDelay = 1, maxParty = 4, watchDelay = 5 }
local Group = MS.JourneyGroupQuests

-- Inside pcall, because comparing a secret value throws.
local function IsTrue(fn, ...) return fn(...) == true end
local function Ask(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, answer = pcall(IsTrue, fn, ...)
    return ok and answer
end

local function FirstName(unit)
    local ok, name = pcall(function()
        local value = _G.UnitName(unit)
        return type(value) == "string" and value ~= "" and value .. "" or nil
    end)
    return ok and name or nil
end

-- Connected party members, as { unit, name }.
function Group:Members()
    local members = {}
    if Ask(_G.IsInRaid) then return members end
    for index = 1, self.maxParty do
        local unit = "party" .. index
        if Ask(_G.UnitExists, unit) and Ask(_G.UnitIsConnected, unit) then
            local name = FirstName(unit)
            if name then members[#members + 1] = { unit = unit, name = name } end
        end
    end
    return members
end

local function Band()
    local band = MS.JourneyMentorBand
    return band and band:IsActive() and band or nil
end

function Group:IsActive()
    return Band() ~= nil or #self:Members() > 0
end

function Group:Shares(questID)
    local band = Band()
    if band then return band:Shares(questID) end
    local log = _G.C_QuestLog
    if type(log) ~= "table" or type(questID) ~= "number" then return false end
    for _, member in ipairs(self:Members()) do
        if Ask(log.IsUnitOnQuest, member.unit, questID) then return true end
    end
    return false
end

function Group:Heading()
    local band = Band()
    local mode = MS.BroadcastMode
    local function Person(name) return mode and mode:Person(name) or name end
    if band then return string.format(MS.L.JOURNEY_MENTOR_SHARED, Person(tostring(band:FriendName() or ""))) end
    local members = self:Members()
    if #members == 1 then return string.format(MS.L.JOURNEY_MENTOR_SHARED, Person(members[1].name)) end
    return MS.L.JOURNEY_GROUP_SHARED
end

function Group:RefreshViews()
    self.refreshPending = nil
    local journal = MS.QuestJournal
    if journal and journal.Invalidate then
        journal:Invalidate()
        if journal.visible and journal.Refresh then journal:Refresh() end
    end
    local map = MS.MapView
    if map and map.active and map.RenderSidebar then map:RenderSidebar() end
end

-- A party changes in bursts; one refresh covers them.
function Group:OnEvent()
    self:Watch()
    if self.refreshPending then return end
    self.refreshPending = true
    _G.C_Timer.After(self.refreshDelay, function() Group:RefreshViews() end)
end

-- The game learns a member's quests only once close to them, and no event says so: while in a
-- party and a list is on screen, the shared quests are checked every few seconds, and the views
-- redraw only when they changed.
function Group:Signature()
    local log = _G.C_QuestLog
    if type(log) ~= "table" or type(log.GetNumQuestLogEntries) ~= "function" then return "" end
    local shared = {}
    for index = 1, (log.GetNumQuestLogEntries() or 0) do
        local questID = log.GetQuestIDForLogIndex and log.GetQuestIDForLogIndex(index)
        if type(questID) == "number" and questID > 0 and self:Shares(questID) then shared[#shared + 1] = questID end
    end
    return table.concat(shared, ",")
end

local function Visible()
    local map, journal = MS.MapView, MS.QuestJournal
    return (map and map.active) or (journal and journal.visible)
end

function Group:Tick()
    self.watching = false
    if #self:Members() == 0 then self.signature = nil; return end
    if Visible() then
        local signature = self:Signature()
        if signature ~= self.signature then
            local first = self.signature == nil
            self.signature = signature
            if not first then self:RefreshViews() end
        end
    end
    self:Watch()
end

function Group:Watch()
    if self.watching or #self:Members() == 0 then return end
    self.watching = true
    _G.C_Timer.After(self.watchDelay, function() Group:Tick() end)
end

Group.frame = _G.CreateFrame("Frame")
Group.frame:SetScript("OnEvent", function() Group:OnEvent() end)
for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "UNIT_QUEST_LOG_CHANGED", "UNIT_CONNECTION" }) do
    pcall(Group.frame.RegisterEvent, Group.frame, event)
end

-- Streamer mode: the shared-quest headings and companions' names redraw.
if MS.BroadcastMode then MS.BroadcastMode:Listen(function() Group:RefreshViews() end) end
