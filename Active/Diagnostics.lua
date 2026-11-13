local MS = _G.MS
MS.Active = MS.Active or {}
-- Bounded journal in AzerothJourneyActiveDB.diagnostics. Whitelisted, typed fields per event:
-- codes, counts and states only. A seal's words, its place, a recipient's or a group member's
-- name have no field to live in, so they can never be exported.
local D = { schema = 1, limit = 400, textLimit = 48 }
MS.Active.Diagnostics = D

local TEXT, NUM, BOOL = "text", "number", "boolean"
D.codes = {
    ACTIVE_SESSION_START = { store = TEXT, version = TEXT, build = TEXT, initial = BOOL },
    CAPABILITY_STATE = { reason = TEXT, caps = TEXT },
    CAPABILITY_PROVEN = { capability = TEXT, evidence = TEXT },
    COMPONENT_ERROR = { component = TEXT, phase = TEXT, reason = TEXT },
    CARD_SHOWN = { kind = TEXT, surface = TEXT },
    CARD_REFUSED = { kind = TEXT, reason = TEXT },
    -- Sur mes pas
    SEAL_CREATED = { kind = TEXT, bytes = NUM, mapType = NUM },
    SEAL_CREATE_REFUSED = { reason = TEXT },
    SEAL_IMPORTED = { kind = TEXT, result = TEXT },
    SEAL_ARMED = { count = NUM, here = NUM },
    SEAL_PROXIMITY_CHECKED = { result = TEXT },
    SEAL_NEAR_SAID = { count = NUM },
    SEAL_OPENED = { kind = TEXT, days = NUM, deferred = BOOL },
    SEAL_REFUSED = { reason = TEXT },
    SEAL_REPLIED = { kind = TEXT, result = TEXT },
    SEAL_OFFERED = { kind = TEXT },
    SEAL_OFFER_SKIPPED = { reason = TEXT },
    SEAL_OFFER_ANSWERED = { result = TEXT },
    SEAL_WHISPER_UNREACHED = { kind = TEXT },
    SEAL_ARCHIVED = { reason = TEXT, count = NUM },
    -- Contrat
    CONTRACT_CREATED = { mode = TEXT, source = TEXT, cards = TEXT },
    CONTRACT_STARTED = { mode = TEXT, cards = TEXT, group = NUM },
    CONTRACT_RULE_STATE = { card = TEXT, state = TEXT, reason = TEXT },
    CONTRACT_INTERRUPTED = { reason = TEXT, scope = TEXT, seconds = NUM },
    CONTRACT_COMPLETED = { mode = TEXT, outcome = TEXT, verdict = TEXT, duration = NUM },
    CONTRACT_RESULT_GENERATED = { verdict = TEXT, kept = NUM, broken = NUM, unverifiable = NUM, honor = NUM },
    CONTRACT_ANNOUNCED = { phase = TEXT, result = TEXT },
}

local function Clean(value, limit)
    -- Diagnostics stay plain ASCII (codes only): control bytes, "|" and any non-ASCII byte become
    -- "?", so a cut never splits a character. Explicit ranges: %c depends on the C locale.
    value = tostring(value):gsub("[%z\1-\31\127-\255|]", "?")
    if #value > limit then value = value:sub(1, limit) end
    return value
end

local function Store(spec, fields, textLimit)
    local stored = {}
    for key, value in pairs(type(fields) == "table" and fields or {}) do
        local kind = spec[key]
        if (kind == NUM or kind == BOOL) and type(value) == kind then
            if kind ~= NUM or value == value then stored[key] = value end
        elseif kind == TEXT and (type(value) == "string" or type(value) == "number") then
            stored[key] = Clean(value, textLimit)
        end
    end
    return stored
end

-- A stored counter: a finite, bounded, non-negative number (math.huge and NaN never survive).
local LIMIT = 2 ^ 31 - 1
local function Count(value) return type(value) == "number" and value >= 0 and value <= LIMIT end
local function Inc(value) return math.min((value or 0) + 1, LIMIT) end

function D:Bind(root, clock)
    self.clock = clock
    self.readOnly = type(root.schema) == "number" and root.schema > self.schema
    if self.readOnly then self.root = root; return end
    if root.schema ~= self.schema or type(root.entries) ~= "table" then root.entries, root.counters, root.dropped = {}, {}, 0 end
    root.schema = self.schema
    if not Count(root.seq) then root.seq = 0 end
    if type(root.counters) ~= "table" then root.counters = {} end
    if not Count(root.dropped) then root.dropped = 0 end
    -- Every stored entry is rebuilt against its spec: nothing malformed survives a reload.
    local entries = {}
    for _, entry in ipairs(root.entries) do
        if type(entry) == "table" and type(entry.c) == "string" and self.codes[entry.c] and type(entry.f) == "table"
            and type(entry.s) == "number" and type(entry.t) == "number" then
            entries[#entries + 1] = { s = entry.s, t = entry.t, c = entry.c, f = Store(self.codes[entry.c], entry.f, self.textLimit) }
        end
    end
    while #entries > self.limit do table.remove(entries, 1); root.dropped = Inc(root.dropped) end
    root.entries = entries
    local counters = {}
    for code, count in pairs(root.counters) do
        if self.codes[code] and Count(count) then counters[code] = math.floor(count) end
    end
    root.counters = counters
    self.root = root
end

function D:Log(code, fields)
    local root, spec = self.root, self.codes[code]
    if not root or self.readOnly or not spec then return nil end
    root.seq = Inc(root.seq)
    local entry = { s = root.seq, t = self.clock and self.clock() or 0, c = code, f = Store(spec, fields, self.textLimit) }
    root.entries[#root.entries + 1] = entry
    root.counters[code] = Inc(root.counters[code])
    while #root.entries > self.limit do table.remove(root.entries, 1); root.dropped = Inc(root.dropped) end
    return entry
end

function D:Reset()
    if not self.root or self.readOnly then return false end
    self.root.entries, self.root.counters, self.root.dropped, self.root.seq = {}, {}, 0, 0
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

function D:Export(header)
    local root = self.root
    if not root then return "AJ-ACTIVE-DIAG UNAVAILABLE" end
    if self.readOnly then return "AJ-ACTIVE-DIAG UNSUPPORTED_SCHEMA " .. tostring(root.schema) end
    local lines = { "AJ-ACTIVE-DIAG " .. self.schema }
    for _, line in ipairs(header or {}) do lines[#lines + 1] = Clean(line, 700) end
    local counters = {}
    for code, count in pairs(root.counters) do counters[#counters + 1] = code .. "=" .. count end
    table.sort(counters)
    lines[#lines + 1] = "counters " .. table.concat(counters, ",")
    lines[#lines + 1] = string.format("entries %d dropped %d", #root.entries, root.dropped or 0)
    for _, entry in ipairs(root.entries) do lines[#lines + 1] = self:Line(entry) end
    lines[#lines + 1] = "END"
    return table.concat(lines, "\n")
end
