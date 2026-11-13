local MS = _G.MS
MS.Community = MS.Community or {}
-- Release Forever may differ from the beta: every runtime dependency is a capability.
-- READY: present and locally validated, or seen working on this client build (evidence).
-- UNVERIFIED: present, semantics not proven on Forever. UNAVAILABLE: missing API.
-- DISABLED: switched off by a flag or by policy.
local Capabilities = {}
MS.Community.Capabilities = Capabilities

Capabilities.order = { "Memory", "RosterObservation", "MemberZoneObservation", "InstanceObservation",
    "QuestGroupFacts", "QuestLink", "ChatPrefill", "AddonMessaging", "WhisperTransport", "PartyTransport",
    "RaidTransport", "ChannelTransport", "BNetTransport", "PeerFeatures" }

local function Fn(value) return type(value) == "function" end

-- Reads only the presence of globals; never calls a WoW API.
function Capabilities:Probe(G)
    G = G or {}
    local map, chat, quest = G.C_Map, G.C_ChatInfo, G.C_QuestLog
    return {
        roster = Fn(G.GetNumGroupMembers) and Fn(G.UnitGUID) and Fn(G.UnitName) and Fn(G.UnitExists),
        memberMap = type(map) == "table" and Fn(map.GetBestMapForUnit),
        instance = Fn(G.IsInInstance),
        quest = (type(quest) == "table" and Fn(quest.GetInfo)) or Fn(G.GetQuestLogTitle),
        -- The client's own quest hyperlink; Journey never builds one (fallback: the title).
        questLink = Fn(G.GetQuestLink),
        chatPrefill = Fn(G.ChatFrame_OpenChat),
        addonMessaging = type(chat) == "table" and Fn(chat.SendAddonMessage) and Fn(chat.RegisterAddonMessagePrefix),
    }
end

-- Runtime evidence can only promote these, and only from UNVERIFIED: the player-side quest and
-- chat capabilities Journey sees working by itself. Network capabilities are never promoted.
Capabilities.provable = { QuestGroupFacts = true, QuestLink = true, ChatPrefill = true }

-- Evidence: { build = client build, [capability] = true }. Anything else is dropped.
function Capabilities:SanitizeEvidence(raw)
    if type(raw) ~= "table" or type(raw.build) ~= "string" or raw.build == "" or #raw.build > 32 then return nil end
    local evidence = { build = raw.build }
    for name in pairs(self.provable) do if raw[name] == true then evidence[name] = true end end
    return evidence
end

function Capabilities:Evaluate(env, flags, storeReady, evidence)
    env = env or {}
    local on = function(name) return flags and flags:IsOn(name) or false end
    local function present(value, state) return value and state or "UNAVAILABLE" end
    local function proven(value, name)
        if not value then return "UNAVAILABLE" end
        return self.provable[name] and type(evidence) == "table" and evidence[name] == true and "READY" or "UNVERIFIED"
    end
    local caps = {
        Memory = storeReady and "READY" or "UNAVAILABLE",
        RosterObservation = present(env.roster, "READY"),
        MemberZoneObservation = present(env.memberMap, "UNVERIFIED"),
        InstanceObservation = present(env.instance, "UNVERIFIED"),
        QuestGroupFacts = proven(env.quest, "QuestGroupFacts"),
        QuestLink = proven(env.questLink, "QuestLink"),
        ChatPrefill = proven(env.chatPrefill, "ChatPrefill"),
        AddonMessaging = present(env.addonMessaging, "UNVERIFIED"),
        -- V1 never joins a custom channel and has no Battle.net adapter.
        ChannelTransport = "DISABLED",
        BNetTransport = "DISABLED",
    }
    caps.WhisperTransport = present(env.addonMessaging, "UNVERIFIED")
    caps.PartyTransport = present(env.addonMessaging, "UNVERIFIED")
    caps.RaidTransport = present(env.addonMessaging, "UNVERIFIED")
    if not on("peerFeatures") then caps.PeerFeatures = "DISABLED"
    elseif caps.WhisperTransport == "UNAVAILABLE" or caps.Memory ~= "READY" then caps.PeerFeatures = "UNAVAILABLE"
    else caps.PeerFeatures = "UNVERIFIED" end
    return caps
end

function Capabilities.Usable(state)
    return state == "READY" or state == "UNVERIFIED"
end

-- Feature gates combine a flag with the capabilities it needs. A missing capability turns
-- the feature off cleanly; it never half-runs.
Capabilities.requirements = {
    encounterMemories = { "Memory", "RosterObservation" },
    familiarNames = { "Memory" },
    groupingAssist = { "QuestGroupFacts", "ChatPrefill" },
    peerFeatures = { "PeerFeatures" },
}

function Capabilities:Feature(name, caps, flags)
    if not (flags and flags:IsOn(name)) then return false, "FLAG_OFF" end
    for _, capability in ipairs(self.requirements[name] or {}) do
        if not self.Usable(caps and caps[capability]) then return false, "CAPABILITY_" .. capability end
    end
    return true
end
