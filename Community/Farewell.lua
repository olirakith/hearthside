local MS = _G.MS
MS.Community = MS.Community or {}
-- The farewell: when a group (or a long-time member) leaves, offer to keep the moment.
-- One optional gesture; ignoring it leaves no trace, no counter, no reminder.
local C = MS.Community
local F = { feature = "encounterMemories", pendingLimit = 40, pendingTTL = 900, cooldown = 600, duration = 60 }
C.Farewell = F

local MONTH = "JOURNEY_JOURNAL_MONTH_"
function C.FormatDate(stamp)
    if type(stamp) == "number" and type(_G.date) == "function" then
        local ok, day, month = pcall(function() return tonumber(_G.date("%d", stamp)), tonumber(_G.date("%m", stamp)) end)
        if ok and day and month and MS.L[MONTH .. month] then
            return (MS.L.COMMUNITY_DAY_MONTH:gsub("{day}", tostring(day)):gsub("{month}", MS.L[MONTH .. month]))
        end
    end
    return MS.L.JOURNEY_MEMORY_DATE_UNKNOWN
end

function C:OnMemoriesChanged()
    if MS.JourneyProgressionView and MS.JourneyProgressionView.Invalidate then pcall(MS.JourneyProgressionView.Invalidate, MS.JourneyProgressionView) end
    if MS.JourneyLivingMapView and MS.JourneyLivingMapView.InvalidateCommunity then pcall(MS.JourneyLivingMapView.InvalidateCommunity, MS.JourneyLivingMapView) end
end

-- Parcours reads names as a sentence: "A and B", "A, B and C", "A, B, C +2".
function C.NameList(memory)
    local names, shown = {}, C.MemoryBook.shownCompanions
    for index = 1, math.min(#memory.companions, shown) do names[index] = memory.companions[index].name end
    if #memory.companions > shown then
        return table.concat(names, ", ") .. " " .. string.format(MS.L.COMMUNITY_MORE_COMPANIONS, #memory.companions - shown)
    end
    if #names <= 1 then return names[1] or "" end
    return string.format(MS.L.COMMUNITY_NAMES_LAST, table.concat(names, ", ", 1, #names - 1), names[#names])
end

-- Parcours chapter lines: at most two kept moments of this region, received stories excluded.
function C:ChapterLines(mapID)
    local bucket = self.bucket
    if not bucket or not self.Flags:IsOn("communityEnabled") or type(mapID) ~= "number" then return {} end
    local data = MS.JourneyMapData
    local zone = data and data.RelationZone and data:RelationZone(mapID) or mapID
    local lines = {}
    for _, memory in ipairs(self.MemoryBook:AtPlace(bucket, zone)) do
        if memory.source ~= "RECEIVED" then
            local text = self.MemoryBook.Lines(memory, MS.L, C.FormatDate)
            -- "With ..." only when a shared presence is established; otherwise the group fact.
            local claim = self.MemoryBook.Claim(memory)
            local key = (claim == "SHARED_ROUTE" or claim == "SAME_INSTANCE") and "COMMUNITY_PARCOURS_WITH" or "COMMUNITY_PARCOURS_GROUP"
            lines[#lines + 1] = string.format(MS.L[key], C.NameList(memory), text.date)
            if #lines >= 2 then break end
        end
    end
    return lines
end

function C:OnCandidate(candidate)
    if not F.running then return end
    local now = C.Now()
    if not F.pending[candidate.id] then
        F.order[#F.order + 1] = candidate.id
        while #F.order > F.pendingLimit do F.pending[table.remove(F.order, 1)] = nil end
    end
    F.pending[candidate.id] = { candidate = candidate, at = now }
    F.fresh = true
end

-- Called once per observation, after all its departures: simultaneous leavers share one card.
function C:OnEncounterSample(sessionOpen)
    if not F.running or not F.fresh then return end
    F.fresh = false
    -- A long-time companion leaves while the group goes on: offer now unless we just did.
    if sessionOpen and C.Now() - (F.lastShownAt or 0) < F.cooldown then return end
    F:TryShow(sessionOpen and "MEMBER_LEFT" or "SESSION_END")
end


function F:Candidates(now)
    local list, order = {}, {}
    for _, id in ipairs(self.order) do
        local entry = self.pending[id]
        if entry and now - entry.at <= self.pendingTTL then
            list[#list + 1] = entry.candidate; order[#order + 1] = id
        else
            self.pending[id] = nil
        end
    end
    self.order = order
    return list
end

function F:Clear()
    self.pending, self.order = {}, {}
end

function F:TryShow(trigger)
    local bucket = C.bucket
    local now = C.Now()
    local candidates = self:Candidates(now)
    if #candidates == 0 or not bucket then return end
    if C.MomentCard:IsShowing("FAREWELL") then return end
    local proposal, overflow = C.MemoryBook:Propose(bucket, candidates, now)
    for _, id in ipairs(overflow or {}) do C:Log("MEMORY_DISMISSED", { candidate = id, reason = "COMPANION_LIMIT" }) end
    if not proposal then
        for _, candidate in ipairs(candidates) do C:Log("MEMORY_DISMISSED", { candidate = candidate.id, reason = "RECENTLY_KEPT" }) end
        self:Clear()
        return
    end
    local L = MS.L
    local lines = C.MemoryBook.Lines(proposal, L, C.FormatDate)
    local shown, reason = C.MomentCard:Show({ kind = "FAREWELL", heading = L.COMMUNITY_FAREWELL_HEADING,
        -- The moment is now: the place alone, no date (the date lives in Parcours and in the echo).
        title = lines.place, lines = { lines.names, lines.claim },
        primary = { label = L.COMMUNITY_KEEP, action = function() F:Keep(proposal) end },
        duration = self.duration,
        onClose = function(why)
            C:Log("MEMORY_DISMISSED", { candidate = proposal.id, reason = why })
            F:Resume()
        end })
    if not shown then
        if reason == "COMBAT" then self.waitingCombat = true; return end
        -- No second screen right now: the moment passes, nothing is stored.
        C:Log("MEMORY_DISMISSED", { candidate = proposal.id, reason = reason })
        self:Clear()
        return
    end
    self.lastShownAt = now
    self:Clear()
    C:Log("MEMORY_PROPOSED", { candidate = proposal.id, companions = #proposal.companions, place = proposal.place.mapID })
end

-- Candidates that arrived while a farewell was visible get their own card afterwards.
function F:Resume()
    if self.running and #self.order > 0 then
        C_Timer.After(1, function() if F.running then F:TryShow("QUEUED") end end)
    end
end

function F:Keep(proposal)
    local bucket = C.bucket
    if not bucket then return end
    self.serial = (self.serial or 0) + 1
    local memory, reason = C.MemoryBook:Keep(bucket, proposal, C.Now(), self.serial)
    if memory then
        C:Log("MEMORY_KEPT", { candidate = proposal.id, memory = memory.id, companions = #memory.companions })
        C.MomentCard:Confirm(MS.L.COMMUNITY_KEPT, nil, function() F:Resume() end)
        C:OnMemoriesChanged()
    else
        C:Log("MEMORY_DISMISSED", { candidate = proposal.id, reason = reason })
        C.MomentCard:Confirm(reason == "CAPACITY" and MS.L.COMMUNITY_KEEP_FULL or MS.L.COMMUNITY_KEEP_FAILED, nil, function() F:Resume() end)
    end
end

function F:Start()
    self.running = true
    self:Clear()
    if not self.frame then
        self.frame = CreateFrame("Frame")
        self.frame:SetScript("OnEvent", function()
            if F.waitingCombat then F.waitingCombat = false; F:TryShow("COMBAT_ENDED") end
        end)
    end
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function F:Stop()
    self.running, self.waitingCombat = false, false
    self:Clear()
    if self.frame then self.frame:UnregisterAllEvents() end
    if C.MomentCard:IsShowing("FAREWELL") then C.MomentCard:Close("STOPPED") end
end

C:Register("Farewell", F)
