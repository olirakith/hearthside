local MS = _G.MS
MS.Community = MS.Community or {}
-- Versioned, bounded Community journal stored in AzerothJourneyCommunityDB.diagnostics.
-- STANDARD (default): third parties pseudonymized. COMPLETE: raw identity, explicit opt-in,
-- expires on its own and is purged when it ends. Chat text has no field to live in.
local D = { schema = 1, limit = 500, textLimit = 64, completeSeconds = 7200 }
MS.Community.Diagnostics = D
local Bytes = MS.Community.Bytes

-- Whitelisted, typed fields per event. Anything else is dropped before storage; identities
-- are only ever stored as pseudonyms (plus raw_ copies while COMPLETE is active).
local ID, TEXT, NUM, BOOL, MAP, REF = "identity", "text", "number", "boolean", "map", "ref"
-- Opaque reference shapes produced by Community; anything else (legacy ids embedding a name or
-- realm) is dropped.
local REF_SHAPES = { "^f?s%d+%.%d+:e%d+$", "^s%d+%.%d+$", "^m%d+%.%d+$", "^r:%x+:%x+$", "^%x+$" }
local function RefValid(value)
    if type(value) ~= "string" or #value > 48 then return false end
    for _, shape in ipairs(REF_SHAPES) do if value:find(shape) then return true end end
    return false
end
D.codes = {
    COMMUNITY_SESSION_START = { store = TEXT, version = TEXT, enabled = BOOL, character = ID },
    CAPABILITY_STATE = { reason = TEXT, caps = MAP },
    CAPABILITY_PROVEN = { capability = TEXT, evidence = TEXT },
    FLAG_CHANGED = { flag = TEXT, value = BOOL },
    COMPONENT_ERROR = { component = TEXT, phase = TEXT, reason = TEXT },
    DIAG_LEVEL_CHANGED = { level = TEXT, reason = TEXT },
    GROUP_SESSION_START = { session = REF, raid = BOOL, members = NUM, presentAtStart = BOOL },
    GROUP_MEMBER_JOIN = { session = REF, subject = ID, guid = BOOL, realm = BOOL, presentAtStart = BOOL },
    GROUP_MEMBER_LEAVE = { session = REF, subject = ID, grouped = NUM },
    GROUP_SESSION_END = { session = REF, duration = NUM, members = NUM, candidates = NUM, reason = TEXT },
    ENCOUNTER_EVIDENCE = { session = REF, subject = ID, kind = TEXT, seconds = NUM, place = NUM },
    MEMORY_CANDIDATE = { session = REF, subject = ID, confidence = TEXT, reasons = TEXT, claims = TEXT, rejected = TEXT },
    MEMORY_PROPOSED = { candidate = REF, companions = NUM, place = NUM },
    MEMORY_KEPT = { candidate = REF, memory = REF, companions = NUM },
    MEMORY_DISMISSED = { candidate = REF, reason = TEXT },
    MEMORY_FORGOTTEN = { memory = REF, scope = TEXT },
    FAMILIAR_MATCH = { subject = ID, trigger = TEXT, memory = REF, basis = TEXT },
    FAMILIAR_MATCH_REJECTED = { subject = ID, trigger = TEXT, reason = TEXT },
    -- ASSIST_OFFERED / ASSIST_USED are no longer emitted (CEX-6.1); kept so older journals read back.
    ASSIST_OFFERED = { quest = NUM, fact = TEXT },
    ASSIST_USED = { quest = NUM },
    ASSIST_BLOCKED = { quest = NUM, reason = TEXT },
    -- Quest social actions: source is POPUP, QUEST_DETAIL or CONTEXT_MENU. The prepared text and
    -- whatever the player writes or sends afterwards have no field.
    QUEST_SOCIAL_SUGGESTION_SHOWN = { quest = NUM, source = TEXT, fact = TEXT },
    QUEST_SOCIAL_ACTION_OPENED = { quest = NUM, source = TEXT, surface = TEXT, actions = NUM },
    QUEST_SOCIAL_ACTION_SELECTED = { quest = NUM, source = TEXT, intent = TEXT },
    QUEST_CHAT_PREFILL_REQUESTED = { quest = NUM, source = TEXT, intent = TEXT },
    QUEST_CHAT_PREFILL_SUCCESS = { quest = NUM, source = TEXT, intent = TEXT, link = TEXT },
    QUEST_CHAT_PREFILL_FAILED = { quest = NUM, source = TEXT, intent = TEXT, reason = TEXT },
    QUEST_NATIVE_LINK_AVAILABLE = { quest = NUM, source = TEXT },
    QUEST_NATIVE_LINK_FALLBACK = { quest = NUM, source = TEXT, reason = TEXT },
    PEER_STATE = { state = TEXT, reason = TEXT },
    PEER_CONSENT = { peer = ID, action = TEXT },
    PEER_TX_ACCEPTED = { peer = ID, transfer = REF, fragments = NUM, bytes = NUM },
    PEER_RX = { peer = ID, type = TEXT, transfer = REF, mode = TEXT },
    PEER_ACK = { peer = ID, transfer = REF },
    PEER_TIMEOUT = { peer = ID, transfer = REF, phase = TEXT },
    PEER_PROTOCOL_ERROR = { peer = ID, transfer = REF, reason = TEXT, mode = TEXT },
    PEER_SEND_ERROR = { peer = ID, transfer = REF, reason = TEXT },
}

-- Defense in depth: a GUID-shaped token in free text is never stored in clear.
local function Scrub(value)
    return (value:gsub("Player%-%d+%-%x+", "<guid>"))
end

local function Clean(value, limit)
    -- Explicit ASCII ranges: %c depends on the C locale and can match UTF-8 bytes.
    value = tostring(value):gsub("[%z\1-\31\127|]", "?")
    if #value > limit then value = value:sub(1, limit) end
    return value
end

function D:Bind(root, clock, random)
    self.clock, self.random = clock, random or math.random
    self.readOnly = type(root.schema) == "number" and root.schema > self.schema
    if self.readOnly then self.root = root; return end
    if root.schema ~= self.schema or type(root.entries) ~= "table" then
        root.entries, root.counters, root.dropped = {}, {}, 0
    end
    root.schema = self.schema
    root.level = root.level == "COMPLETE" and "COMPLETE" or "STANDARD"
    if not Bytes.IsHex(root.salt, 16) then root.salt = Bytes.RandomHex(16, self.random) end
    if type(root.seq) ~= "number" or root.seq < 0 then root.seq = 0 end
    if type(root.counters) ~= "table" then root.counters = {} end
    if type(root.dropped) ~= "number" then root.dropped = 0 end
    self.root = root
    -- Rebuild every stored entry against its spec: corrupted or oversized values never survive
    -- a reload, and raw identities survive only while COMPLETE is still active.
    local entries, complete = {}, self:IsComplete()
    for _, entry in ipairs(root.entries) do
        if type(entry) == "table" and type(entry.c) == "string" and self.codes[entry.c] and type(entry.f) == "table"
            and type(entry.s) == "number" and type(entry.t) == "number" then
            entries[#entries + 1] = { s = entry.s, t = entry.t, c = entry.c, f = self:Rebuild(entry.c, entry.f, complete) }
        end
    end
    while #entries > self.limit do table.remove(entries, 1); root.dropped = root.dropped + 1 end
    root.entries = entries
    local counters = {}
    for code, count in pairs(root.counters) do
        if self.codes[code] and type(count) == "number" and count >= 0 then counters[code] = math.floor(count) end
    end
    root.counters = counters
    self:CheckExpiry()
end

function D:Rebuild(code, fields, complete)
    local spec, result = self.codes[code], {}
    for key, value in pairs(fields) do
        local kind = spec[key]
        if kind == ID then
            if type(value) == "string" and #value == 9 and value:find("^p%x+$") then result[key] = value end
        elseif kind == REF then
            if RefValid(value) then result[key] = value end
        elseif kind == TEXT or kind == MAP then
            if type(value) == "string" then result[key] = Scrub(Clean(value, kind == MAP and 600 or self.textLimit)) end
        elseif kind == NUM or kind == BOOL then
            if type(value) == kind then result[key] = value end
        elseif complete and type(key) == "string" and key:sub(1, 4) == "raw_" and spec[key:sub(5)] == ID and type(value) == "string" then
            result[key] = Clean(value, 120)
        end
    end
    return result
end

function D:Now() return self.clock and self.clock() or 0 end

function D:IsComplete()
    local root = self.root
    return root ~= nil and not self.readOnly and root.level == "COMPLETE"
        and type(root.completeUntil) == "number" and root.completeUntil > self:Now()
end

-- Raw identity never outlives COMPLETE: expiry or opt-out purges it from every entry.
function D:Purge()
    for _, entry in ipairs(self.root.entries) do
        for key in pairs(entry.f) do if key:sub(1, 4) == "raw_" then entry.f[key] = nil end end
    end
end

function D:CheckExpiry()
    local root = self.root
    if root and not self.readOnly and root.level == "COMPLETE" and not self:IsComplete() then
        root.level, root.completeUntil = "STANDARD", nil
        self:Purge()
        self:Log("DIAG_LEVEL_CHANGED", { level = "STANDARD", reason = "EXPIRED" })
    end
end

function D:SetComplete(enabled)
    if not self.root or self.readOnly then return false end
    if enabled then
        self.root.level, self.root.completeUntil = "COMPLETE", self:Now() + self.completeSeconds
        self:Log("DIAG_LEVEL_CHANGED", { level = "COMPLETE", reason = "PLAYER_OPT_IN" })
    else
        self.root.level, self.root.completeUntil = "STANDARD", nil
        self:Purge()
        self:Log("DIAG_LEVEL_CHANGED", { level = "STANDARD", reason = "PLAYER_OPT_OUT" })
    end
    return true
end

-- Identity value: { guid=, name=, realm= } or an opaque string address/key.
function D:IdentityText(value)
    if type(value) == "table" then
        local guid, name, realm = value.guid, value.name, value.realm
        return (guid and tostring(guid) or "") .. "/" .. (name and tostring(name) or "") .. "-" .. (realm and tostring(realm) or "")
    end
    return tostring(value)
end

function D:Pseudonym(value)
    if value == nil then return nil end
    return "p" .. Bytes.Crc32(self.root.salt .. "|" .. self:IdentityText(value))
end

local function MapText(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for index, key in ipairs(keys) do keys[index] = key .. "=" .. Clean(map[key], 24) end
    return table.concat(keys, ",")
end

function D:Log(code, fields)
    local root = self.root
    local spec = self.codes[code]
    if not root or self.readOnly or not spec then return nil end
    if code ~= "DIAG_LEVEL_CHANGED" then self:CheckExpiry() end
    local stored = {}
    for key, value in pairs(type(fields) == "table" and fields or {}) do
        local kind = spec[key]
        if kind == ID and value ~= nil then
            stored[key] = self:Pseudonym(value)
            if self:IsComplete() then stored["raw_" .. key] = Clean(self:IdentityText(value), 120) end
        elseif kind == MAP and type(value) == "table" then
            stored[key] = Clean(MapText(value), 600)
        elseif kind == REF then
            if RefValid(value) then stored[key] = value end
        elseif (kind == NUM or kind == BOOL) and type(value) == kind then
            stored[key] = value
        elseif kind == TEXT and (type(value) == "string" or type(value) == "number") then
            stored[key] = Scrub(Clean(value, self.textLimit))
        end
    end
    root.seq = root.seq + 1
    local entry = { s = root.seq, t = self:Now(), c = code, f = stored }
    root.entries[#root.entries + 1] = entry
    root.counters[code] = (root.counters[code] or 0) + 1
    while #root.entries > self.limit do table.remove(root.entries, 1); root.dropped = root.dropped + 1 end
    return entry
end

function D:Reset()
    if not self.root or self.readOnly then return false end
    local root = self.root
    root.entries, root.counters, root.dropped, root.seq = {}, {}, 0, 0
    root.level, root.completeUntil = "STANDARD", nil
    root.salt = Bytes.RandomHex(16, self.random)
    return true
end

function D:Line(entry)
    local keys = {}
    for key in pairs(entry.f) do keys[#keys + 1] = key end
    table.sort(keys)
    local parts = { string.format("%d %.0f %s", entry.s, entry.t, entry.c) }
    for _, key in ipairs(keys) do parts[#parts + 1] = key .. "=" .. tostring(entry.f[key]) end
    return table.concat(parts, " ")
end

-- Plain-text export, versioned and self-describing; the Companion can parse the same SV.
function D:Export(header)
    local root = self.root
    if not root then return "AJ-COMMUNITY-DIAG UNAVAILABLE" end
    if self.readOnly then return "AJ-COMMUNITY-DIAG UNSUPPORTED_SCHEMA " .. tostring(root.schema) end
    self:CheckExpiry()
    local lines = { "AJ-COMMUNITY-DIAG " .. self.schema, "level " .. (root.level or "?") }
    for _, line in ipairs(header or {}) do lines[#lines + 1] = Clean(line, 700) end
    local counters = {}
    for code, count in pairs(root.counters or {}) do counters[#counters + 1] = code .. "=" .. count end
    table.sort(counters)
    lines[#lines + 1] = "counters " .. table.concat(counters, ",")
    lines[#lines + 1] = string.format("entries %d dropped %d", #root.entries, root.dropped or 0)
    for _, entry in ipairs(root.entries) do lines[#lines + 1] = self:Line(entry) end
    lines[#lines + 1] = "END"
    return table.concat(lines, "\n")
end
