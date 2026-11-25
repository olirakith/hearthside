-- Pure logic for the "what I missed" band: no frames, events, WoW API or text.
-- Time is always passed in (seconds).
local MS = _G.MS

local Missed = {}
MS.JourneyMissed = Missed

Missed.MIN_AWAY = 30
Missed.MAX_SENDERS = 20
Missed.REASONS = { AFK = "AFK", TAXI = "TAXI", COMBAT = "COMBAT", OFFLINE = "OFFLINE" }
Missed.KINDS = { WHISPER = "WHISPER", MAIL = "MAIL", COOLDOWN = "COOLDOWN", FRIEND = "FRIEND" }

local REASON_ORDER = { "AFK", "TAXI", "COMBAT", "OFFLINE" }
local KIND_ORDER = { "WHISPER", "MAIL", "COOLDOWN", "FRIEND" }

local active, start, counts, senders, durations, pending

function Missed:Reset()
    active, start, counts, senders, durations, pending = {}, nil, nil, nil, nil, nil
end

local function addSender(list, who)
    if type(who) ~= "string" or who == "" or #list >= Missed.MAX_SENDERS then return end
    for i = 1, #list do
        if list[i] == who then return end
    end
    list[#list + 1] = who
end

local function build(till)
    local total, out = 0, {}
    for _, kind in ipairs(KIND_ORDER) do
        local n = counts[kind] or 0
        if n > 0 then out[kind] = n; total = total + n end
    end
    if total == 0 or till - start < Missed.MIN_AWAY then return nil end
    local best, bestTime = nil, -1
    for _, reason in ipairs(REASON_ORDER) do
        local d = durations[reason]
        if d and d > bestTime then best, bestTime = reason, d end
    end
    local list = {}
    for i = 1, #senders do list[i] = senders[i] end
    return { reason = best, since = start, till = till, counts = out, senders = list }
end

local function merge(old, new)
    for kind, n in pairs(new.counts) do
        old.counts[kind] = (old.counts[kind] or 0) + n
    end
    for i = 1, #new.senders do addSender(old.senders, new.senders[i]) end
    if new.since < old.since then old.since = new.since end
    if new.till > old.till then old.till = new.till end
end

local function anyActive()
    for _ in pairs(active) do return true end
    return false
end

function Missed:SetAway(reason, on, now)
    if not Missed.REASONS[reason] or type(now) ~= "number" then return end
    if on then
        if active[reason] then return end
        if not anyActive() then
            start, counts, senders, durations = now, {}, {}, {}
        end
        active[reason] = now
    else
        if not active[reason] then return end
        durations[reason] = (durations[reason] or 0) + (now - active[reason])
        active[reason] = nil
        if not anyActive() then
            local digest = build(now)
            if digest then
                if pending then merge(pending, digest) else pending = digest end
            end
            start, counts, senders, durations = nil, nil, nil, nil
        end
    end
end

function Missed:IsAway()
    return anyActive()
end

function Missed:Count(kind, now, who)
    if not anyActive() or not Missed.KINDS[kind] then return end
    counts[kind] = (counts[kind] or 0) + 1
    if kind == "WHISPER" then addSender(senders, who) end
end

function Missed:Pending()
    return pending
end

function Missed:Dismiss()
    pending = nil
end

-- Copy of a digest without sender names (streamer mode).
function Missed:Hide(digest)
    if type(digest) ~= "table" then return nil end
    local c = {}
    for k, v in pairs(digest.counts or {}) do c[k] = v end
    return { reason = digest.reason, since = digest.since, till = digest.till, counts = c, senders = {} }
end

function Missed.Cooldowns(records, lastSeen, now)
    local out = {}
    if type(records) ~= "table" or type(lastSeen) ~= "number" or type(now) ~= "number" then return out end
    for _, rec in ipairs(records) do
        if type(rec) == "table" and type(rec.professions) == "table" then
            for _, prof in ipairs(rec.professions) do
                if type(prof) == "table" and type(prof.cooldowns) == "table" then
                    for _, cd in ipairs(prof.cooldowns) do
                        local at = type(cd) == "table" and cd.readyAt
                        if type(at) == "number" and at > lastSeen and at <= now then
                            out[#out + 1] = { character = rec.name, profession = prof.name, name = cd.name, readyAt = at }
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.readyAt < b.readyAt end)
    return out
end

Missed:Reset()
