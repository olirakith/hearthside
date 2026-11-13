local MS = _G.MS
MS.Community = MS.Community or {}
-- Peer protocol: handshake, consent, states,
-- bounded retries, reassembly, dedupe ledger and progress snapshots. Same messages, same
-- states, same meaning of MEMORY_ACK. Production adaptations, each documented in 04-PEER-RUNTIME:
--   * policy is injectable (lab values in P.LAB_POLICY, production values in P.POLICY);
--   * an explicit local allow + trust-on-first-HELLO binding replaces lab fixture bindings;
--   * the durable ledger lives in the character's SavedVariables bucket;
--   * clock (monotonic, timeouts) and civil (dates) are separate.
local P = {}
MS.Community.Peer = P
local W, M, MB, Identity = MS.Community.Wire, MS.Community.MemoryCodec, MS.Community.MemoryBook, MS.Community.Identity
local Check, NULL = W.Check, W.NULL

P.LAB_POLICY = { retryAfter = 5, attempts = 3, ttl = 30, active = 8, history = 250, contacts = 8, diagnostics = 200 }
-- Paced native sends need more time per phase; attempts stay at the lab's three.
P.POLICY = { retryAfter = 10, attempts = 3, ttl = 60, active = 4, history = 250, contacts = 8, diagnostics = 200, maxFragments = 24 }
P.MODES = { SELF = true, WHISPER = true, PARTY = true, RAID = true, CHANNEL = true, BNET = true }

local function Count(map) local n = 0 for _ in pairs(map) do n = n + 1 end return n end
local function Keys(map) local keys = {} for key in pairs(map) do keys[#keys + 1] = key end table.sort(keys) return keys end
local function Array(...) return { n = select("#", ...), ... } end
local function Plain(value)
    local copy = {}
    for index = 1, (value.n or #value) do copy[index] = value[index] end
    return copy
end
local function Manifest(value)
    return type(value) == "table" and value ~= NULL and (value.n or #value) == 3 and W.Integer(value[1], 1, W.LIMITS.logical)
        and W.token(value[2], 8) and value[3] == math.ceil(value[1] / W.LIMITS.fragment)
end
P.ManifestValid = Manifest
local function TransferKey(sender, id) return sender .. ":" .. id end

-- ---------- identity provider ----------
local IP = {}
IP.__index = IP
function P.IdentityProvider(character, policy)
    return setmetatable({ character = Identity.Copy(character), bindings = {}, allowed = {}, policy = policy or P.POLICY }, IP)
end
-- Explicit association (lab fixture bindings, and the result of a consented first HELLO).
function IP:bind(address, senderReference, character)
    Check(type(address) == "string" and #address > 0 and #address <= 100 and W.token(senderReference, 12)
        and type(character) == "table", "BINDING")
    local old = self.bindings[address]
    if old then
        Check(old.senderReference == senderReference and Identity.Same(old.character, character), "IDENTITY_CONFLICT")
        return
    end
    -- One reference per address and one address per reference (production hardening).
    for other, binding in pairs(self.bindings) do
        Check(binding.senderReference ~= senderReference or other == address, "IDENTITY_CONFLICT")
    end
    Check(Count(self.bindings) < self.policy.contacts, "CONTACT_CAPACITY")
    self.bindings[address] = { senderReference = senderReference, character = Identity.Copy(character) }
end
function IP:resolve(address) return self.bindings[address] end
-- Local, explicit, revocable consent to exchange with one exact native address.
function IP:allow(address, character)
    Check(type(address) == "string" and #address > 0 and #address <= 100 and type(character) == "table", "BINDING")
    Check(self.allowed[address] or Count(self.allowed) < self.policy.contacts, "CONTACT_CAPACITY")
    self.allowed[address] = Identity.Copy(character)
end
function IP:revoke(address) self.allowed[address], self.bindings[address] = nil, nil end

-- ---------- durable store (character bucket) ----------
local DS = {}
DS.__index = DS
function P.SanitizeDurable(raw)
    local peer = { reference = W.token(raw.reference, 12) and raw.reference or nil,
        sessionCounter = W.Integer(raw.sessionCounter, 0, 65535) and raw.sessionCounter or 0, completed = {}, origins = {} }
    local function Bounded(source, valid)
        local keys = {}
        for key, value in pairs(type(source) == "table" and source or {}) do
            if type(key) == "string" and type(value) == "table" and valid(key, value) then keys[#keys + 1] = key end
        end
        table.sort(keys)
        local result = {}
        for index = 1, math.min(#keys, P.POLICY.history) do result[keys[index]] = source[keys[index]] end
        return result
    end
    local function MemoryRef(value) return type(value) == "string" and #value <= 120 and value:find("^[%w%.:]+$") ~= nil end
    peer.completed = Bounded(raw.completed, function(key, value)
        return key:find("^%x%x%x%x%x%x%x%x%x%x%x%x:%x+$") and #key == 29 and Manifest(value.manifest) and MemoryRef(value.memoryId)
    end)
    peer.origins = Bounded(raw.origins, function(key, value)
        return #key <= 140 and key:find("^%x%x%x%x%x%x%x%x%x%x%x%x:") and W.token(value.hash, 8)
            and W.Integer(value.length, 1, W.LIMITS.logical) and MemoryRef(value.memoryId)
    end)
    -- Rows are rebuilt with their allowed fields only: nothing else survives a reload.
    for key, value in pairs(peer.completed) do peer.completed[key] = { manifest = Plain(value.manifest), memoryId = value.memoryId } end
    for key, value in pairs(peer.origins) do peer.origins[key] = { hash = value.hash, length = value.length, memoryId = value.memoryId } end
    return peer
end

function P.DurableStore(bucket, policy)
    bucket.peer = bucket.peer or P.SanitizeDurable({})
    bucket.peer.completed = bucket.peer.completed or {}
    bucket.peer.origins = bucket.peer.origins or {}
    return setmetatable({ bucket = bucket, completed = bucket.peer.completed, origins = bucket.peer.origins,
        policy = policy or P.POLICY }, DS)
end
function DS:required(memoryId)
    local memory = self.bucket.memories[memoryId]
    Check(memory ~= nil, "MEMORY_NOT_FOUND")
    return memory
end
-- Memory and ledger change together or not at all (one synchronous Lua step; SavedVariables
-- are written at logout, so a crash can lose the last step, never split it).
function DS:commit(key, manifest, candidate, originKey)
    local completed = self.completed[key]
    if completed then Check(W.equal(completed.manifest, manifest), "TRANSFER_CONFLICT"); return completed end
    Check(Count(self.completed) < self.policy.history, "LEDGER_CAPACITY")
    local original = self.origins[originKey]
    if original then Check(original.hash == manifest[2] and original.length == manifest[1], "SOURCE_CONFLICT") end
    if not original then Check(Count(self.origins) < self.policy.history, "LEDGER_CAPACITY") end
    local record = { manifest = Plain(manifest), memoryId = original and original.memoryId or candidate.id }
    if not original then
        local memory, reason = MB:Insert(self.bucket, candidate)
        Check(memory ~= nil, tostring(reason))
    end
    self.completed[key] = record
    if not original then self.origins[originKey] = { hash = manifest[2], length = manifest[1], memoryId = candidate.id } end
    return record
end

-- ---------- peer ----------
local Peer = {}
Peer.__index = Peer
P.Peer = Peer

function P.New(o)
    local policy = o.policy or P.POLICY
    Check(W.token(o.senderReference, 12) and W.token(o.session, 8) and type(o.transport) == "table"
        and P.MODES[o.transport.mode], "PEER_CONFIG")
    return setmetatable({ reference = o.senderReference, session = o.session, policy = policy,
        identity = o.identity or P.IdentityProvider(o.character, policy), transport = o.transport, clock = o.clock,
        civil = o.civil or o.clock, durable = o.durable, onEvent = o.onEvent, counter = 0,
        ready = {}, hellos = {}, outgoing = {}, incoming = {}, requests = {}, snapshots = {}, events = {} }, Peer)
end

function Peer:event(code, id, detail)
    self.events[#self.events + 1] = { at = self.clock(), code = code, id = id }
    if #self.events > self.policy.diagnostics then table.remove(self.events, 1) end
    if self.onEvent then pcall(self.onEvent, code, id, detail) end
end

function Peer:id()
    Check(self.counter < 0xffffffff, "SESSION_EXHAUSTED")
    self.counter = self.counter + 1
    return self.session .. string.format("%08x", self.counter)
end

function Peer:send(target, kind, id, value)
    local payload = W.json(value)
    local packet = W.encode({ type = kind, senderReference = self.reference, messageId = id, totalLength = #payload,
        hash = W.checksum(payload), payload = payload })
    -- Local transport return is diagnostic only. It NEVER advances delivery state.
    local ok = pcall(self.transport.send, target, packet, id, kind)
    self:event(ok and "SEND_ATTEMPT" or "LOCAL_SEND_ERROR", id, kind)
end

function Peer:hello(target)
    local known = self.identity:resolve(target) or self.identity.allowed[target]
    Check(known and Count(self.hellos) < self.policy.contacts, "UNKNOWN_TARGET_OR_CAPACITY")
    local id = self:id()
    self.hellos[id] = { target = target, attempts = 1, nextAt = self.clock() + self.policy.retryAfter }
    self:send(target, "HELLO", id, Array(1))
    return id
end

local function Live(tx, states) for _, state in ipairs(states) do if tx.state == state then return true end end return false end
local SENDING, RECEIVING = { "PROPOSED", "WAIT_ACK" }, { "PROPOSED", "RECEIVING", "READY_TO_STORE" }

function Peer:activeOutgoing()
    local n = 0
    for _, tx in pairs(self.outgoing) do if Live(tx, SENDING) then n = n + 1 end end
    return n
end

function Peer:propose(target, memoryId)
    Check(self.ready[target] and Count(self.outgoing) < self.policy.history and self:activeOutgoing() < self.policy.active,
        "NOT_READY_OR_CAPACITY")
    local bytes = M.pack(self.durable:required(memoryId))
    local pieces = W.fragments(bytes)
    Check(not self.policy.maxFragments or #pieces <= self.policy.maxFragments, "TOO_LARGE_FOR_PACING")
    local id = self:id()
    local tx = { id = id, target = target, bytes = bytes, manifest = Array(#bytes, W.checksum(bytes), #pieces),
        state = "PROPOSED", attempts = 1, expires = self.clock() + self.policy.ttl, nextAt = self.clock() + self.policy.retryAfter }
    self.outgoing[id] = tx
    self:send(target, "MEMORY_PROPOSE", id, tx.manifest)
    return id
end

function Peer:acceptProposal(id)
    local tx = self.incoming[id]
    Check(tx and tx.state == "PROPOSED" and self.clock() < tx.expires, "NO_LIVE_PROPOSAL")
    tx.state, tx.expires = "RECEIVING", self.clock() + self.policy.ttl
    self:send(tx.target, "MEMORY_ACCEPT", id, tx.manifest)
    self:event("CONSENT_TRANSFER", id)
end

function Peer:declineProposal(id)
    local tx = self.incoming[id]
    Check(tx and tx.state == "PROPOSED" and self.clock() < tx.expires, "NO_LIVE_PROPOSAL")
    tx.state = "DECLINED"
    self:send(tx.target, "MEMORY_DECLINE", id, Array())
    self:event("DECLINED", id)
end

function Peer:sendContent(tx)
    for index, payload in ipairs(W.fragments(tx.bytes)) do
        local packet = W.encode({ type = "MEMORY_FRAGMENT", senderReference = self.reference, messageId = tx.id,
            index = index, count = tx.manifest[3], totalLength = tx.manifest[1], hash = tx.manifest[2], payload = payload })
        if not pcall(self.transport.send, tx.target, packet, tx.id, "MEMORY_FRAGMENT") then self:event("LOCAL_SEND_ERROR", tx.id) end
    end
    self:send(tx.target, "MEMORY_COMPLETE", tx.id, tx.manifest)
end

function Peer:storeReceived(id)
    local tx = self.incoming[id]
    Check(tx and tx.state == "READY_TO_STORE" and self.clock() < tx.expires, "NOT_READY_TO_STORE")
    local ok, result = pcall(function()
        local memory, originId = M.unpack(tx.bytes, tx.sender, id, self.civil())
        local record = self.durable:commit(TransferKey(tx.sender, id), tx.manifest, memory, tx.sender .. ":" .. originId)
        return record.memoryId
    end)
    if not ok then self:failIncoming(tx, W.Code(result)); return nil end
    tx.state, tx.parts, tx.bytes = "STORED", {}, nil
    self:event("STORED", id)
    self:send(tx.target, "MEMORY_ACK", id, Array(tx.manifest[1], tx.manifest[2]))
    return result
end

function Peer:failIncoming(tx, reason)
    tx.state, tx.parts, tx.bytes = "REFUSED", {}, nil
    self:event(reason, tx.id)
    self:send(tx.target, "REFUSE", tx.id, Array("TRANSFER_REJECTED"))
end

function Peer:assemble(tx)
    if tx.state ~= "RECEIVING" or not tx.completeSeen or Count(tx.parts) ~= tx.manifest[3] then return end
    local chunks = {}
    for index = 1, tx.manifest[3] do chunks[index] = tx.parts[index] end
    local bytes = table.concat(chunks)
    if #bytes ~= tx.manifest[1] or W.checksum(bytes) ~= tx.manifest[2] then self:failIncoming(tx, "LOGICAL_INTEGRITY"); return end
    if not pcall(M.unpack, bytes, tx.sender, tx.id, self.civil()) then self:failIncoming(tx, "MEMORY_SCHEMA"); return end
    tx.bytes, tx.state = bytes, "READY_TO_STORE"
    self:event("READY_TO_STORE", tx.id)
end

function Peer:requestSnapshot(target, transferId)
    local tx = self.outgoing[transferId]
    Check(self.ready[target] and tx and tx.target == target and Count(self.requests) < self.policy.active, "SNAPSHOT_SCOPE")
    local id = self:id()
    self.requests[id] = { target = target, transferId = transferId, expires = self.clock() + self.policy.ttl }
    self:send(target, "SNAPSHOT_REQUEST", id, Array(transferId))
    return id
end

-- Production: a first HELLO / HELLO_ACK from an allowed, unbound address may bind its
-- reference, only once the frame is otherwise fully valid.
function Peer:learn(from, frame)
    local allowed = self.identity.allowed[from]
    if not allowed or self.identity:resolve(from) then return end
    if frame.type ~= "HELLO" and frame.type ~= "HELLO_ACK" then return end
    local ok, value = pcall(W.parse, frame.payload)
    if not ok or not W.equal(value, Array(1)) then return end
    if frame.type == "HELLO_ACK" then
        local pending = self.hellos[frame.messageId]
        if not pending or pending.target ~= from then return end
    end
    local bound = pcall(self.identity.bind, self.identity, from, frame.senderReference, allowed)
    if not bound then self:event("DROP_IDENTITY_CONFLICT", frame.messageId) end
end

function Peer:receive(metadata, packet)
    local ok, frame = pcall(W.decode, packet)
    if not ok then self:event("DROP_" .. W.Code(frame)); return end
    if type(metadata) ~= "table" or type(metadata.from) ~= "string" or not P.MODES[metadata.mode] then
        self:event("DROP_METADATA", frame.messageId); return
    end
    -- The transport mode is checked before any identity mutation (first-HELLO binding).
    if metadata.mode ~= self.transport.mode then self:event("DROP_IDENTITY", frame.messageId); return end
    self:learn(metadata.from, frame)
    local binding = self.identity:resolve(metadata.from)
    if not binding or binding.senderReference ~= frame.senderReference then
        self:event("DROP_IDENTITY", frame.messageId); return
    end
    local handled, err = pcall(self.handle, self, metadata.from, frame)
    if not handled then self:event("DROP_" .. W.Code(err), frame.messageId) end
end

function Peer:handle(target, f)
    local id, key = f.messageId, TransferKey(f.senderReference, f.messageId)
    local policy, now = self.policy, self.clock()
    if f.type == "HELLO" or f.type == "HELLO_ACK" then
        Check(W.equal(W.parse(f.payload), Array(1)), "SCHEMA_VERSION")
        if f.type == "HELLO" then self.ready[target] = true; self:send(target, "HELLO_ACK", id, Array(1))
        else
            local pending = self.hellos[id]
            Check(pending and pending.target == target, "HELLO_CORRELATION")
            self.hellos[id] = nil
            self.ready[target] = true
        end
        self:event(f.type, id)
        return
    end
    Check(self.ready[target], "HANDSHAKE_REQUIRED")
    if f.type == "MEMORY_FRAGMENT" then self:fragment(target, f); return end
    local value = W.parse(f.payload)
    if f.type == "MEMORY_PROPOSE" then
        Check(Manifest(value), "MANIFEST")
        local completed = self.durable.completed[key]
        if completed then
            Check(W.equal(value, completed.manifest), "TRANSFER_CONFLICT")
            self:send(target, "MEMORY_ACK", id, Array(value[1], value[2])); return
        end
        local existing = self.incoming[id]
        if existing then
            Check(existing.target == target and existing.sender == f.senderReference and W.equal(value, existing.manifest), "TRANSFER_CONFLICT")
            if now >= existing.expires then self:failIncoming(existing, "EXPIRED"); return end
            if existing.state == "RECEIVING" or existing.state == "READY_TO_STORE" then self:send(target, "MEMORY_ACCEPT", id, value)
            elseif existing.state ~= "PROPOSED" then self:send(target, "MEMORY_DECLINE", id, Array()) end
            return
        end
        local live = 0
        for _, tx in pairs(self.incoming) do if Live(tx, RECEIVING) then live = live + 1 end end
        Check(Count(self.incoming) < policy.history and live < policy.active, "INCOMING_CAPACITY")
        self.incoming[id] = { id = id, target = target, sender = f.senderReference, manifest = Array(value[1], value[2], value[3]),
            parts = {}, completeSeen = false, state = "PROPOSED", expires = now + policy.ttl }
        self:event("PROPOSAL_AVAILABLE", id)
        return
    end
    local outgoing = self.outgoing[id]
    if f.type == "MEMORY_ACCEPT" or f.type == "MEMORY_DECLINE" or f.type == "MEMORY_ACK" or f.type == "ERROR" or f.type == "REFUSE" then
        Check(outgoing and outgoing.target == target, "OUTGOING_CORRELATION")
        if not Live(outgoing, SENDING) then return end
        if now >= outgoing.expires then outgoing.state = "FAILED"; return end
        if f.type == "MEMORY_ACCEPT" then
            Check(W.equal(value, outgoing.manifest), "MANIFEST")
            if outgoing.state ~= "PROPOSED" then return end
            outgoing.state, outgoing.attempts = "WAIT_ACK", 1
            outgoing.expires, outgoing.nextAt = now + policy.ttl, now + policy.retryAfter
            self:sendContent(outgoing)
        elseif f.type == "MEMORY_ACK" then
            Check(outgoing.state == "WAIT_ACK" and W.equal(value, Array(outgoing.manifest[1], outgoing.manifest[2])), "ACK_CORRELATION")
            outgoing.state = "DELIVERED"
            self:event("DELIVERED", id)
        elseif f.type == "MEMORY_DECLINE" then
            Check(W.equal(value, Array()), "DECLINE_SCHEMA")
            outgoing.state = "DECLINED"
        else
            Check(type(value) == "table" and value.n == 1 and type(value[1]) == "string" and #value[1] <= 40, "ERROR_SCHEMA")
            outgoing.state = "FAILED"
        end
        return
    end
    if f.type == "MEMORY_COMPLETE" then
        Check(Manifest(value), "MANIFEST")
        local completed = self.durable.completed[key]
        if completed then
            Check(W.equal(completed.manifest, value), "TRANSFER_CONFLICT")
            self:send(target, "MEMORY_ACK", id, Array(value[1], value[2])); return
        end
        local tx = self.incoming[id]
        if not tx or tx.target ~= target or tx.sender ~= f.senderReference or not (tx.state == "RECEIVING" or tx.state == "READY_TO_STORE")
            or now >= tx.expires then
            self:send(target, "REFUSE", id, Array("NO_LIVE_CONSENT")); return
        end
        Check(W.equal(value, tx.manifest), "MANIFEST")
        tx.completeSeen = true
        self:assemble(tx)
        return
    end
    if f.type == "SNAPSHOT_REQUEST" then
        Check(type(value) == "table" and value.n == 1 and W.token(value[1], 16), "SNAPSHOT_SCHEMA")
        local transferId = value[1]
        local completed, tx = self.durable.completed[TransferKey(f.senderReference, transferId)], self.incoming[transferId]
        if completed then self:send(target, "SNAPSHOT_RESPONSE", id, Array(transferId, "STORED", ""))
        elseif tx and tx.target == target and tx.sender == f.senderReference and (tx.state == "RECEIVING" or tx.state == "READY_TO_STORE")
            and now < tx.expires then
            self:send(target, "SNAPSHOT_RESPONSE", id, Array(transferId, tx.state, P.Bitmask(tx.parts)))
        else self:send(target, "SNAPSHOT_RESPONSE", id, Array(transferId, "UNAVAILABLE", "")) end
        return
    end
    if f.type == "SNAPSHOT_RESPONSE" then
        local request = self.requests[id]
        local states = { STORED = true, RECEIVING = true, READY_TO_STORE = true, UNAVAILABLE = true }
        Check(request and request.target == target and now < request.expires and type(value) == "table" and value.n == 3
            and value[1] == request.transferId and states[value[2]] and type(value[3]) == "string"
            and #value[3] <= 16 and not value[3]:find("[^a-f0-9]"), "SNAPSHOT_CORRELATION")
        self.requests[id] = nil
        if Count(self.snapshots) < policy.history then self.snapshots[id] = Plain(value) end
        self:event("SNAPSHOT_STATUS_ONLY", id)
        return
    end
    Check(false, "UNHANDLED_TYPE")
end

-- Hex of the received-fragment bitmask (bit i-1 for index i), like BigInt.toString(16).
function P.Bitmask(parts)
    local nibbles = {}
    for index = 1, 16 do nibbles[index] = 0 end
    for index in pairs(parts) do
        local bit = index - 1
        local nibble = math.floor(bit / 4) + 1
        nibbles[nibble] = nibbles[nibble] + 2 ^ (bit % 4)
    end
    local out, started = {}, false
    for index = 16, 1, -1 do
        if nibbles[index] > 0 then started = true end
        if started then out[#out + 1] = string.format("%x", nibbles[index]) end
    end
    return started and table.concat(out) or "0"
end

function Peer:fragment(target, f)
    local completed = self.durable.completed[TransferKey(f.senderReference, f.messageId)]
    if completed then Check(W.equal(completed.manifest, Array(f.totalLength, f.hash, f.count)), "TRANSFER_CONFLICT"); return end
    local tx = self.incoming[f.messageId]
    if not tx or tx.target ~= target or tx.sender ~= f.senderReference or not (tx.state == "RECEIVING" or tx.state == "READY_TO_STORE")
        or self.clock() >= tx.expires then
        self:send(target, "REFUSE", f.messageId, Array("NO_LIVE_CONSENT")); return
    end
    Check(W.equal(tx.manifest, Array(f.totalLength, f.hash, f.count)), "MANIFEST")
    local expected = f.index < f.count and W.LIMITS.fragment or f.totalLength - W.LIMITS.fragment * (f.count - 1)
    Check(#f.payload == expected, "FRAGMENT_LENGTH")
    local previous = tx.parts[f.index]
    if previous and previous ~= f.payload then self:failIncoming(tx, "FRAGMENT_CONFLICT"); return end
    if tx.state == "RECEIVING" then tx.parts[f.index] = f.payload; self:assemble(tx) end
end

-- Revoking consent ends everything with that address now: no new proposal, no retry,
-- no buffered content; the paced queue drops pending packets through IsLive.
function Peer:revoke(address)
    self.identity:revoke(address)
    self.ready[address] = nil
    for id, hello in pairs(self.hellos) do if hello.target == address then self.hellos[id] = nil end end
    for id, request in pairs(self.requests) do if request.target == address then self.requests[id] = nil end end
    for _, tx in pairs(self.outgoing) do
        if tx.target == address and Live(tx, SENDING) then tx.state = "FAILED"; self:event("REVOKED", tx.id) end
    end
    for _, tx in pairs(self.incoming) do
        if tx.target == address and Live(tx, RECEIVING) then tx.state, tx.parts, tx.bytes = "REFUSED", {}, nil; self:event("REVOKED", tx.id) end
    end
end

-- Which packet types a local transaction may still emit in each state.
local EMITS = {
    outgoing = { PROPOSED = { MEMORY_PROPOSE = true }, WAIT_ACK = { MEMORY_FRAGMENT = true, MEMORY_COMPLETE = true } },
    -- A refusal is always safe to send; a decline answers a repeated proposal after the decision.
    incoming = { PROPOSED = { REFUSE = true }, RECEIVING = { MEMORY_ACCEPT = true, REFUSE = true },
        READY_TO_STORE = { MEMORY_ACCEPT = true, REFUSE = true }, STORED = { MEMORY_ACK = true, REFUSE = true },
        DECLINED = { MEMORY_DECLINE = true, REFUSE = true }, REFUSED = { MEMORY_DECLINE = true, REFUSE = true },
        EXPIRED = { MEMORY_DECLINE = true, REFUSE = true } },
}

-- May this packet leave right now? nil when the id is not a local transaction (a reply).
function Peer:MayEmit(id, kind, now)
    now = now or self.clock()
    local hello = self.hellos[id]
    if hello then return kind == "HELLO" and now < hello.nextAt end
    local request = self.requests[id]
    if request then return kind == "SNAPSHOT_REQUEST" and now < request.expires end
    local outgoing, incoming = self.outgoing[id], self.incoming[id]
    local tx, side = outgoing or incoming, outgoing and "outgoing" or "incoming"
    if not tx then return nil end
    local allowed = EMITS[side][tx.state]
    if not allowed or not allowed[kind] then return false end
    -- Refusals and declines never depend on the transfer's deadline (queue validity still applies).
    if kind == "REFUSE" or kind == "MEMORY_DECLINE" then return true end
    if Live(tx, SENDING) or Live(tx, RECEIVING) then return now < tx.expires end
    return true
end

-- Is this local transaction still allowed to emit right now? Used by the paced queue before
-- every native send; the deadline is checked against the clock, not left to the next tick().
-- Returns nil when the id is not a local transaction (a reply to the remote's message).
function Peer:IsLive(id, now)
    now = now or self.clock()
    local hello = self.hellos[id]
    if hello then return now < hello.nextAt end
    local request = self.requests[id]
    if request then return now < request.expires end
    local tx = self.outgoing[id] or self.incoming[id]
    if not tx then return nil end
    if Live(tx, SENDING) or Live(tx, RECEIVING) then return now < tx.expires end
    -- Terminal states only emit their own replies (ACK, DECLINE, REFUSE).
    return tx.state == "STORED" or tx.state == "DECLINED" or tx.state == "REFUSED"
end

function Peer:tick()
    local now, policy = self.clock(), self.policy
    for _, id in ipairs(Keys(self.hellos)) do
        local hello = self.hellos[id]
        if now >= hello.nextAt then
            if hello.attempts >= policy.attempts then self.hellos[id] = nil; self:event("HELLO_TIMEOUT", id)
            else hello.attempts, hello.nextAt = hello.attempts + 1, now + policy.retryAfter; self:send(hello.target, "HELLO", id, Array(1)) end
        end
    end
    for _, id in ipairs(Keys(self.outgoing)) do
        local tx = self.outgoing[id]
        if Live(tx, SENDING) and now >= tx.nextAt then
            if now >= tx.expires or tx.attempts >= policy.attempts then tx.state = "FAILED"; self:event("DELIVERY_TIMEOUT", tx.id, tx.state)
            else
                tx.attempts, tx.nextAt = tx.attempts + 1, now + policy.retryAfter
                if tx.state == "PROPOSED" then self:send(tx.target, "MEMORY_PROPOSE", tx.id, tx.manifest) else self:sendContent(tx) end
            end
        end
    end
    for _, id in ipairs(Keys(self.incoming)) do
        local tx = self.incoming[id]
        if Live(tx, RECEIVING) and now >= tx.expires then
            tx.state, tx.parts, tx.bytes = "EXPIRED", {}, nil
            self:event("EXPIRED", tx.id)
        end
    end
    for _, id in ipairs(Keys(self.requests)) do if now >= self.requests[id].expires then self.requests[id] = nil end end
end
