local MS = _G.MS
MS.Community = MS.Community or {}
-- Encounter memories, schema 1. A memory is a MOMENT of the journey (place, time, companions);
-- a person only exists inside the moments the player chose to keep. No profile, no counter.
-- Pure: operates on the character bucket table owned by Community.Store.
local MB = { schema = 1, limit = 250, companionLimit = 8, titleLimit = 100, noteLimit = 500,
    duplicateWindow = 6 * 3600, shownCompanions = 3 }
MS.Community.MemoryBook = MB
local Identity, Bytes = MS.Community.Identity, MS.Community.Bytes

MB.BASES = { GROUP_MEMBER = 1, SHARED_ROUTE = 2, SAME_INSTANCE = 3, MANUAL = 4, RECEIVED = 5 }
MB.SOURCES = { OBSERVED = "LOCAL", MANUAL = "PLAYER", RECEIVED = "RECEIVED_FROM_PEER" }

local function Int(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value) and value >= minimum and value <= maximum
end
local function Stamp(value) return Int(value, 1, 4102444800) end
local function Text(value, limit)
    return type(value) == "string" and value ~= "" and Bytes.ValidUtf8(value) and Bytes.Utf16Length(value) <= limit
        and not value:find("[%z\1-\8\11\12\14-\31]")
end

-- Strength of observed evidence; 0 for bases an observed memory may not carry.
local function Rank(basis)
    return basis == "SAME_INSTANCE" and 3 or basis == "SHARED_ROUTE" and 2 or basis == "GROUP_MEMBER" and 1 or 0
end

local function CopyCompanion(raw)
    if type(raw) ~= "table" or not MB.BASES[raw.basis] then return nil end
    if raw.basis == "RECEIVED" then
        -- A received name is displayed, never matched: no GUID, realm optional.
        if raw.guid ~= nil or not Text(raw.name, 64) or (raw.realm ~= nil and not Text(raw.realm, 64)) then return nil end
        return { name = raw.name, realm = raw.realm, basis = "RECEIVED" }
    end
    local id = Identity.Make(raw.guid, raw.name, raw.realm)
    if not id or not id.name then return nil end
    return { guid = id.guid, name = id.name, realm = id.realm, basis = raw.basis }
end

-- Returns a clean copy or nil, reason. Unknown fields never survive.
function MB.Validate(raw)
    if type(raw) ~= "table" or raw.v ~= MB.schema then return nil, "SCHEMA" end
    if not Text(raw.id, 120) or not MB.SOURCES[raw.source] then return nil, "IDENTITY" end
    if not Stamp(raw.at) or (raw["until"] ~= nil and (not Stamp(raw["until"]) or raw["until"] < raw.at)) then return nil, "TIME" end
    local place = raw.place
    if type(place) ~= "table" or not Text(place.name, 120) or (place.mapID ~= nil and not Int(place.mapID, 1, 2147483647)) then
        return nil, "PLACE"
    end
    if type(raw.companions) ~= "table" or #raw.companions > MB.companionLimit then return nil, "COMPANIONS" end
    local memory = { v = MB.schema, id = raw.id, source = raw.source, at = raw.at, ["until"] = raw["until"],
        place = { mapID = place.mapID, name = place.name, instance = place.instance == true },
        companions = {}, keptAt = Stamp(raw.keptAt) and raw.keptAt or raw.at }
    local seen = {}
    for _, value in ipairs(raw.companions) do
        local companion = CopyCompanion(value)
        if not companion then return nil, "COMPANION" end
        if (raw.source == "RECEIVED") ~= (companion.basis == "RECEIVED") then return nil, "BASIS" end
        if raw.source == "MANUAL" and companion.basis ~= "MANUAL" then return nil, "BASIS" end
        if raw.source == "OBSERVED" and Rank(companion.basis) == 0 then return nil, "BASIS" end
        -- A line must never say "together in" a place that is not an instance, nor "your road" inside one.
        if companion.basis == "SAME_INSTANCE" and place.instance ~= true then return nil, "BASIS_PLACE" end
        if companion.basis == "SHARED_ROUTE" and place.instance == true then return nil, "BASIS_PLACE" end
        local key = Identity.Key(companion) or ("name:" .. companion.name)
        if seen[key] then return nil, "DUPLICATE_COMPANION" end
        seen[key] = true
        memory.companions[#memory.companions + 1] = companion
    end
    if raw.title ~= nil then if not Text(raw.title, MB.titleLimit) then return nil, "TITLE" end memory.title = raw.title end
    if raw.note ~= nil then if not Text(raw.note, MB.noteLimit) then return nil, "NOTE" end memory.note = raw.note end
    if raw.context ~= nil then
        local context = raw.context
        if type(context) ~= "table" or not Int(context.questID, 1, 2147483647) or not Text(context.title, 120)
            or raw.source ~= "OBSERVED" then return nil, "CONTEXT" end
        memory.context = { questID = context.questID, title = context.title }
    end
    if raw.source == "RECEIVED" then
        local provenance = raw.provenance
        if type(provenance) ~= "table" or not Text(provenance.reference, 64) then return nil, "PROVENANCE" end
        memory.provenance = { origin = "RECEIVED_FROM_PEER", reference = provenance.reference }
        -- The sender's kind and place reference are kept as told (display only).
        if raw.kind ~= nil then
            if raw.kind ~= "MOMENT" and raw.kind ~= "ZONE_ENTRY" and raw.kind ~= "INSTANCE_VISIT" then return nil, "KIND" end
            memory.kind = raw.kind
        end
        if place.reference ~= nil then
            if not Text(place.reference, 120) then return nil, "PLACE" end
            memory.place.reference = place.reference
        end
    else
        memory.provenance = { origin = MB.SOURCES[raw.source],
            reference = type(raw.provenance) == "table" and Text(raw.provenance.reference, 120) and raw.provenance.reference or "local" }
    end
    return memory
end

local function Order(bucket)
    local ids = {}
    for id in pairs(bucket.memories) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local ma, mb = bucket.memories[a], bucket.memories[b]
        if ma.at ~= mb.at then return ma.at > mb.at end
        return a < b
    end)
    bucket.order = ids
end

function MB:SanitizeBucket(bucket)
    local clean = {}
    for key, raw in pairs(type(bucket.memories) == "table" and bucket.memories or {}) do
        local memory = MB.Validate(raw)
        if memory and memory.id == key then clean[key] = memory end
    end
    bucket.memories = clean
    Order(bucket)
    -- A corrupted file can exceed the bound: keep the newest, deterministically.
    while #bucket.order > self.limit do
        clean[bucket.order[#bucket.order]] = nil
        table.remove(bucket.order)
    end
    bucket.decisions = nil
    return bucket
end

function MB:Count(bucket) return #bucket.order end

function MB:List(bucket)
    local result = {}
    for _, id in ipairs(bucket.order) do result[#result + 1] = bucket.memories[id] end
    return result
end

local function CandidateBasis(candidate, place)
    local shared = candidate.place and place and candidate.place.mapID == place.mapID
    if shared and candidate.claims.SAME_INSTANCE and place.instance then return "SAME_INSTANCE" end
    if shared and candidate.claims.SHARED_ROUTE and not place.instance then return "SHARED_ROUTE" end
    return "GROUP_MEMBER"
end

-- Recently kept with the same companion at the same place: the farewell would repeat itself.
function MB:RecentlyKept(bucket, identity, mapID, now)
    for _, id in ipairs(bucket.order) do
        local memory = bucket.memories[id]
        if memory.source ~= "RECEIVED" and now - memory.keptAt <= self.duplicateWindow and memory.place.mapID == mapID then
            for _, companion in ipairs(memory.companions) do
                if Identity.Same(companion, identity) then return true end
            end
        end
    end
    return false
end

-- Builds one farewell proposal (RAM only) from a session's candidates. The place is the one
-- most candidates share; a companion whose shared evidence is elsewhere keeps only GROUP_MEMBER.
function MB:Propose(bucket, candidates, now)
    -- One person, one companion: several episodes of the same exact identity (left and came
    -- back after the grace window) merge into their strongest episode.
    local best, merged, order = {}, {}, {}
    for _, candidate in ipairs(candidates) do
        if candidate.propose and candidate.place and candidate.identity and candidate.identity.name
            and not self:RecentlyKept(bucket, candidate.identity, candidate.place.mapID, now) then
            local key = Identity.Key(candidate.identity) or ("name:" .. candidate.identity.name)
            local current = best[key]
            if not current then order[#order + 1] = key end
            if not current or (candidate.placeShared and not current.placeShared)
                or (candidate.placeShared == current.placeShared and candidate.grouped > current.grouped) then
                best[key] = candidate
            end
            merged[key] = merged[key] or {}
            merged[key][#merged[key] + 1] = candidate
        end
    end
    local usable, places = {}, {}
    for _, key in ipairs(order) do
        local candidate = best[key]
        for _, other in ipairs(merged[key]) do
            candidate.startedAt = math.min(candidate.startedAt or now, other.startedAt or now)
            candidate.endedAt = math.max(candidate.endedAt or now, other.endedAt or now)
        end
        usable[#usable + 1] = candidate
        local placeKey = candidate.place.mapID
        places[placeKey] = places[placeKey] or { place = candidate.place, weight = 0 }
        places[placeKey].weight = places[placeKey].weight + (candidate.placeShared and 2 or 1)
    end
    if #usable == 0 then return nil end
    local chosen
    for _, entry in pairs(places) do
        if not chosen or entry.weight > chosen.weight or (entry.weight == chosen.weight and entry.place.mapID < chosen.place.mapID) then
            chosen = entry
        end
    end
    local place = chosen.place
    table.sort(usable, function(a, b)
        local ra, rb = Rank(CandidateBasis(a, place)), Rank(CandidateBasis(b, place))
        if ra ~= rb then return ra > rb end
        if a.grouped ~= b.grouped then return a.grouped > b.grouped end
        return a.id < b.id
    end)
    local proposal = { id = "f" .. usable[1].id, source = "OBSERVED", place = { mapID = place.mapID, name = place.name, instance = place.instance },
        at = now, companions = {}, candidates = {} }
    local overflow = {}
    for index, candidate in ipairs(usable) do
        if index > self.companionLimit then overflow[#overflow + 1] = candidate.id; break end
        proposal.at = math.min(proposal.at, candidate.startedAt or now)
        proposal["until"] = math.max(proposal["until"] or 0, candidate.endedAt or now)
        proposal.companions[#proposal.companions + 1] = { guid = candidate.identity.guid, name = candidate.identity.name,
            realm = candidate.identity.realm, basis = CandidateBasis(candidate, place) }
        proposal.candidates[#proposal.candidates + 1] = candidate.id
        if candidate.context and not proposal.context then proposal.context = candidate.context end
    end
    for index = self.companionLimit + 2, #usable do overflow[#overflow + 1] = usable[index].id end
    return proposal, overflow
end

function MB:Keep(bucket, proposal, now, serial)
    if self:Count(bucket) >= self.limit then return nil, "CAPACITY" end
    local id = string.format("m%.0f.%d", now, serial or 1)
    while bucket.memories[id] do serial = (serial or 1) + 1; id = string.format("m%.0f.%d", now, serial) end
    local memory, reason = MB.Validate({ v = self.schema, id = id, source = "OBSERVED", at = proposal.at,
        ["until"] = proposal["until"], place = proposal.place, companions = proposal.companions, keptAt = now,
        context = proposal.context, provenance = { reference = proposal.id } })
    if not memory then return nil, reason end
    bucket.memories[id] = memory
    Order(bucket)
    return memory
end

-- Inserts an already validated memory (received copies); the bound is never bypassed.
function MB:Insert(bucket, raw)
    if self:Count(bucket) >= self.limit then return nil, "CAPACITY" end
    local memory, reason = MB.Validate(raw)
    if not memory then return nil, reason end
    if bucket.memories[memory.id] then return nil, "DUPLICATE" end
    bucket.memories[memory.id] = memory
    Order(bucket)
    return memory
end

function MB:Forget(bucket, id)
    if not bucket.memories[id] then return false end
    bucket.memories[id] = nil
    Order(bucket)
    return true
end

-- Only the player's own words may change; source, place, companions and evidence never do.
function MB:Edit(bucket, id, patch)
    local memory = bucket.memories[id]
    if not memory or type(patch) ~= "table" then return nil, "NOT_FOUND" end
    local copy = {}
    for key, value in pairs(memory) do copy[key] = value end
    for key, value in pairs(patch) do
        if key ~= "title" and key ~= "note" then return nil, "FIELD" end
        copy[key] = value ~= "" and value or nil
    end
    local clean, reason = MB.Validate(copy)
    if not clean then return nil, reason end
    bucket.memories[id] = clean
    return clean
end

-- Memories kept at a place (Parcours chapters, Carte zone card).
function MB:AtPlace(bucket, mapID, relation)
    local result = {}
    for _, id in ipairs(bucket.order) do
        local memory = bucket.memories[id]
        local placeID = memory.place.mapID
        if placeID and (placeID == mapID or (relation and relation(placeID) == mapID)) then result[#result + 1] = memory end
    end
    return result
end

-- What a player-facing line may say: the claim every listed companion supports.
function MB.Claim(memory)
    if memory.source == "RECEIVED" then return "RECEIVED" end
    if memory.source == "MANUAL" then return "MANUAL" end
    local weakest
    for _, companion in ipairs(memory.companions) do
        local rank = Rank(companion.basis)
        if not weakest or rank < weakest then weakest = rank end
    end
    if weakest == 3 then
        for _, companion in ipairs(memory.companions) do if companion.basis ~= "SAME_INSTANCE" then return "SHARED_ROUTE" end end
        return "SAME_INSTANCE"
    end
    return weakest == 2 and "SHARED_ROUTE" or "GROUP_MEMBER"
end

-- Player-facing lines. L is the locale table, formatDate a presentation callback.
function MB.Lines(memory, L, formatDate)
    local names = {}
    for index, companion in ipairs(memory.companions) do
        if index > MB.shownCompanions then
            names[#names + 1] = string.format(L.COMMUNITY_MORE_COMPANIONS, #memory.companions - MB.shownCompanions)
            break
        end
        names[#names + 1] = companion.name
    end
    local claim = MB.Claim(memory)
    local claimLine = claim == "SAME_INSTANCE" and string.format(L.COMMUNITY_CLAIM_INSTANCE, memory.place.name)
        or claim == "SHARED_ROUTE" and L.COMMUNITY_CLAIM_ROUTE
        or claim == "RECEIVED" and L.COMMUNITY_CLAIM_RECEIVED
        or claim == "MANUAL" and L.COMMUNITY_CLAIM_MANUAL
        or (#memory.companions == 1 and L.COMMUNITY_CLAIM_GROUP_ONE or L.COMMUNITY_CLAIM_GROUP)
    return {
        place = memory.place.name,
        date = formatDate(memory.at),
        names = table.concat(names, " · "),
        claim = claimLine,
        context = memory.context and string.format(L.COMMUNITY_CONTEXT_QUEST, memory.context.title) or nil,
    }
end
