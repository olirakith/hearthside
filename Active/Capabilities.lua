local MS = _G.MS
MS.Active = MS.Active or {}
-- Every Forever dependency of Sur mes pas and Contrat is a capability.
-- READY: seen working on this client build (evidence). UNVERIFIED: the API is present, its
-- behaviour on Forever is not proven yet. UNAVAILABLE: missing API.
-- An UNAVAILABLE capability removes what depends on it; an UNVERIFIED one is used, and any value
-- it cannot read during play becomes "not verifiable", never a verdict.
local Capabilities = {}
MS.Active.Capabilities = Capabilities

Capabilities.order = { "MapPosition", "MapDistance", "InstanceInfo", "CombatState", "PlayerDeath", "PartyDeath",
    "Taxi", "Mount", "AuctionHouse", "GroupRoster", "ServerTime", "LevelUp", "ChatPrefill",
    "SpellCast", "AuraRead" }

local function Fn(value) return type(value) == "function" end

-- Reads only the presence of globals; never calls a WoW API.
function Capabilities:Probe(G)
    G = G or {}
    local map = type(G.C_Map) == "table" and G.C_Map or {}
    return {
        -- Indoors is part of it: Sur mes pas only seals and opens outdoors (floors are unproven).
        MapPosition = Fn(map.GetBestMapForUnit) and Fn(map.GetPlayerMapPosition) and Fn(map.GetMapInfo) and Fn(G.IsIndoors),
        -- Yards on one map: normalized delta x world size. No percentage fallback.
        MapDistance = Fn(map.GetMapWorldSize),
        InstanceInfo = Fn(G.IsInInstance) and Fn(G.GetInstanceInfo),
        CombatState = Fn(G.InCombatLockdown),
        PlayerDeath = Fn(G.UnitIsDeadOrGhost),
        PartyDeath = Fn(G.UnitIsDeadOrGhost) and Fn(G.UnitExists) and Fn(G.GetNumSubgroupMembers),
        Taxi = Fn(G.UnitOnTaxi),
        Mount = Fn(G.IsMounted),
        -- An event cannot be probed; the frame that fires it can.
        AuctionHouse = true,
        GroupRoster = Fn(G.IsInGroup) and Fn(G.GetNumGroupMembers),
        ServerTime = Fn(G.GetServerTime) or Fn(G.time),
        LevelUp = Fn(G.UnitLevel),
        ChatPrefill = Fn(G.ChatFrame_OpenChat),
        -- An event cannot be probed; the watcher proves it.
        SpellCast = true,
        AuraRead = type(G.C_UnitAuras) == "table" and Fn(G.C_UnitAuras.GetAuraDataByIndex),
    }
end

-- Evidence: { build = client build, [capability] = true }. Anything else is dropped.
function Capabilities:SanitizeEvidence(raw)
    if type(raw) ~= "table" or type(raw.build) ~= "string" or raw.build == "" or #raw.build > 32 then return nil end
    local evidence = { build = raw.build }
    for _, name in ipairs(self.order) do if raw[name] == true then evidence[name] = true end end
    return evidence
end

function Capabilities:Evaluate(present, evidence)
    local caps = {}
    for _, name in ipairs(self.order) do
        if not (present and present[name]) then caps[name] = "UNAVAILABLE"
        elseif type(evidence) == "table" and evidence[name] == true then caps[name] = "READY"
        else caps[name] = "UNVERIFIED" end
    end
    return caps
end

function Capabilities.Usable(state)
    return state == "READY" or state == "UNVERIFIED"
end

function Capabilities:Text(caps)
    local parts = {}
    for _, name in ipairs(self.order) do parts[#parts + 1] = name .. "=" .. tostring(caps and caps[name]) end
    return table.concat(parts, ",")
end
