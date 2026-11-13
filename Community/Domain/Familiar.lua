local MS = _G.MS
MS.Community = MS.Community or {}
-- A familiar name: a character exactly matching a kept moment reappears through a native
-- event. Journey reconnects PERSON + PLACE + MOMENT, once. It never searches, ranks or
-- recommends anyone, and received stories never make a name familiar.
local Familiar = { sessionCooldown = 1e9, globalGap = 120 }
MS.Community.Familiar = Familiar
local Identity = MS.Community.Identity

-- The first kept moment with this exact character: where you met.
-- Returns memory, companion, or nil and the most informative rejection.
function Familiar.Recall(bucket, identity)
    if type(bucket) ~= "table" or type(identity) ~= "table" then return nil, nil, "INVALID" end
    local nearMiss
    for index = #bucket.order, 1, -1 do
        local memory = bucket.memories[bucket.order[index]]
        if memory and memory.source ~= "RECEIVED" then
            for _, companion in ipairs(memory.companions) do
                local verdict = Identity.Compare(companion, identity)
                if verdict == "MATCH" then return memory, companion end
                -- Same visible name but not provably the same character: worth measuring, never echoing.
                if companion.name == identity.name and verdict ~= "DIFFERENT" then nearMiss = nearMiss or verdict end
            end
        end
    end
    return nil, nil, nearMiss or "NO_MEMORY"
end

-- RAM-only policy state: one echo per character per play session, a gap between echoes.
function Familiar.NewPolicy() return { echoed = {}, lastAt = nil } end

function Familiar.Allow(policy, key, now)
    if policy.echoed[key] then return false, "ALREADY_ECHOED" end
    if policy.lastAt and now - policy.lastAt < Familiar.globalGap then return false, "GAP" end
    return true
end

function Familiar.Mark(policy, key, now)
    policy.echoed[key], policy.lastAt = true, now
end

-- Lines for the echo: the claim is the one this companion's own basis supports.
function Familiar.Lines(memory, companion, L, formatDate)
    local basis = companion.basis
    local claim = basis == "SAME_INSTANCE" and string.format(L.COMMUNITY_CLAIM_INSTANCE, memory.place.name)
        or basis == "SHARED_ROUTE" and L.COMMUNITY_CLAIM_ROUTE
        or basis == "MANUAL" and L.COMMUNITY_CLAIM_MANUAL
        or L.COMMUNITY_CLAIM_GROUP_ONE
    return { name = companion.name, where = memory.place.name .. " · " .. formatDate(memory.at), claim = claim }
end
