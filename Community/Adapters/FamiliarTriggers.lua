local MS = _G.MS
MS.Community = MS.Community or {}
-- Native moments where a name naturally reappears: a member joins the group, an invitation,
-- a whisper. Only the sender identity (name, GUID) is read: never the message text, never a
-- list of players, never a periodic scan.
local C = MS.Community
local T = { feature = "familiarNames", deferSeconds = 60, duration = 12 }
C.FamiliarTriggers = T

local Call = MS.Community.Call  -- pcall + secret-value filtering

local Readable = C.Readable

local function RealmOf(guid)
    if not guid or type(_G.GetPlayerInfoByGUID) ~= "function" then return nil end
    local _, _, _, _, _, _, realm = Call(_G.GetPlayerInfoByGUID, guid)
    return type(realm) == "string" and realm ~= "" and realm or nil
end

function T:Roster()
    local roster = {}
    local count = Call(_G.GetNumGroupMembers) or 0
    if type(count) ~= "number" or count <= 1 then return roster end
    local raid = Call(_G.IsInRaid) == true
    local total = raid and math.min(count, 40) or math.min(count - 1, 4)
    local mine = Call(_G.UnitGUID, "player")
    for index = 1, total do
        local unit = (raid and "raid" or "party") .. index
        local guid = Call(_G.UnitGUID, unit)
        if guid and guid ~= mine then
            local identity = C.Identity.Make(guid, Call(_G.UnitName, unit), RealmOf(guid))
            if identity then roster[guid] = identity end
        end
    end
    return roster
end

function T:Echo(identity, trigger)
    local bucket = C.bucket
    if not bucket or not identity then return end
    local key = C.Identity.Key(identity)
    local memory, companion, reason = C.Familiar.Recall(bucket, identity)
    if not memory then
        -- Only near misses (same visible name) are measured; strangers leave no trace at all.
        if reason ~= "NO_MEMORY" and reason ~= "INVALID" then
            C:Log("FAMILIAR_MATCH_REJECTED", { subject = identity, trigger = trigger, reason = reason })
        end
        return
    end
    local now = C.Now()
    local allowed, why = C.Familiar.Allow(self.policy, key, now)
    if not allowed then C:Log("FAMILIAR_MATCH_REJECTED", { subject = identity, trigger = trigger, reason = why }); return end
    local L = MS.L
    local lines = C.Familiar.Lines(memory, companion, L, C.FormatDate)
    local shown, failure = C.MomentCard:Show({ kind = "FAMILIAR", heading = L.COMMUNITY_FAMILIAR_HEADING,
        title = lines.name, lines = { lines.where, lines.claim }, duration = self.duration })
    if not shown then
        if failure == "COMBAT" then self.deferred = { identity = identity, trigger = trigger, at = now } end
        C:Log("FAMILIAR_MATCH_REJECTED", { subject = identity, trigger = trigger, reason = failure })
        return
    end
    C.Familiar.Mark(self.policy, key, now)
    C:Log("FAMILIAR_MATCH", { subject = identity, trigger = trigger, memory = memory.id, basis = companion.basis })
end

function T:OnEvent(event, ...)
    if event == "GROUP_ROSTER_UPDATE" then
        local roster = self:Roster()
        local arrivals = {}
        for guid in pairs(roster) do if not self.roster[guid] then arrivals[#arrivals + 1] = guid end end
        -- Stable order by GUID: one echo at most (global gap), the others are logged, never ranked.
        table.sort(arrivals)
        for _, guid in ipairs(arrivals) do self:Echo(roster[guid], "GROUP_JOIN") end
        self.roster = roster
    elseif event == "PARTY_INVITE_REQUEST" then
        local name = Readable((...))
        local guid = Readable((select(7, ...)))
        guid = C.Identity.IsGUID(guid) and guid or nil
        self:Echo(C.Identity.FromAddress(type(name) == "string" and name or nil, guid), "INVITE")
    elseif event == "CHAT_MSG_WHISPER" then
        -- Argument 1 (the text) is deliberately never read.
        local sender = Readable((select(2, ...)))
        local guid = Readable((select(12, ...)))
        guid = C.Identity.IsGUID(guid) and guid or nil
        local identity = C.Identity.FromAddress(type(sender) == "string" and sender or nil, guid)
        if identity and guid and not identity.realm then identity.realm = RealmOf(guid) end
        self:Echo(identity, "WHISPER")
    elseif event == "PLAYER_REGEN_ENABLED" then
        local deferred = self.deferred
        self.deferred = nil
        if deferred and C.Now() - deferred.at <= self.deferSeconds then self:Echo(deferred.identity, deferred.trigger) end
    end
end

function T:Start()
    -- The once-per-session policy survives flag toggles (Stop/Start) within the Lua session.
    self.policy = self.policy or C.Familiar.NewPolicy()
    -- Members already present at login or reload are a baseline, not a reappearance.
    self.roster = self:Roster()
    if not self.frame then
        self.frame = CreateFrame("Frame")
        self.frame:SetScript("OnEvent", function(_, event, ...) T:OnEvent(event, ...) end)
    end
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_INVITE_REQUEST", "CHAT_MSG_WHISPER", "PLAYER_REGEN_ENABLED" }) do
        pcall(self.frame.RegisterEvent, self.frame, event)
    end
end

function T:Stop()
    if self.frame then self.frame:UnregisterAllEvents() end
    self.roster, self.deferred = {}, nil
    if C.MomentCard:IsShowing("FAMILIAR") then C.MomentCard:Close("STOPPED") end
end

-- Tester command: replays the echo of the most recent kept companion through the same path.
C.commands = C.commands or {}
C.commands.test = function(self, rest)
    if rest ~= "familiar" or not self:IsRunning("FamiliarTriggers") or not self.bucket then C.Say("COMMUNITY_TEST_HELP"); return end
    for _, id in ipairs(self.bucket.order) do
        local memory = self.bucket.memories[id]
        if memory.source ~= "RECEIVED" and memory.companions[1] then
            -- Isolated: the test uses a throwaway policy and leaves the session policy untouched.
            local session = T.policy
            T.policy = C.Familiar.NewPolicy()
            T:Echo(C.Identity.Copy(memory.companions[1]), "TEST")
            T.policy = session
            return
        end
    end
    C.Say("COMMUNITY_TEST_NO_MEMORY")
end

C:Register("FamiliarTriggers", T)
