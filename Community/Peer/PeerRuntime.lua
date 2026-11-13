local MS = _G.MS
MS.Community = MS.Community or {}
-- Peer runtime scaffold (CEX-7): wires the ported protocol to WoW for future two-client tests.
-- Off by default (peerFeatures). Tester commands only: nothing is shared automatically, nothing
-- is broadcast, no Reflet. All network state is RAM: a reload starts a new session; only the
-- per-character reference and the dedupe ledger persist.
local C = MS.Community
local R = { feature = "peerFeatures", pace = 0.25, queueLimit = 96, tickSeconds = 1 }
C.PeerRuntime = R

local Call = MS.Community.Call  -- pcall + secret-value filtering
local function Uptime() return Call(_G.GetTime) or 0 end
local Readable = C.Readable

-- Native sender "Name" (same realm) or "Name-Realm": addressing uses the full form.
function R.Address(sender)
    if type(sender) ~= "string" or sender == "" or #sender > 100 then return nil end
    if sender:find("-", 1, true) then return sender end
    local realm = Call(_G.GetNormalizedRealmName)
    return type(realm) == "string" and realm ~= "" and sender .. "-" .. realm or nil
end

function R:Target(id)
    local peer = self.peer
    local tx = peer.outgoing[id] or peer.incoming[id] or peer.hellos[id] or peer.requests[id]
    return tx and tx.target
end

local EVENT_MAP = {
    PROPOSAL_AVAILABLE = { "PEER_RX", "type", "PROPOSE" }, HELLO = { "PEER_RX", "type", "HELLO" },
    HELLO_ACK = { "PEER_RX", "type", "HELLO_ACK" }, CONSENT_TRANSFER = { "PEER_TX_ACCEPTED" },
    READY_TO_STORE = { "PEER_STATE", "state", "READY_TO_STORE" }, STORED = { "PEER_STATE", "state", "STORED" },
    DECLINED = { "PEER_STATE", "state", "DECLINED" }, REVOKED = { "PEER_STATE", "state", "REVOKED" },
    DELIVERED = { "PEER_ACK" }, DELIVERY_TIMEOUT = { "PEER_TIMEOUT", "phase", "DELIVERY" },
    HELLO_TIMEOUT = { "PEER_TIMEOUT", "phase", "HELLO" }, EXPIRED = { "PEER_TIMEOUT", "phase", "INCOMING" },
    LOCAL_SEND_ERROR = { "PEER_SEND_ERROR", "reason", "LOCAL" },
}

function R:OnPeerEvent(code, id)
    if code == "SEND_ATTEMPT" then return end
    local target = id and self.peer and self:Target(id)
    local map = EVENT_MAP[code]
    if map then
        local fields = { peer = target, transfer = id }
        if map[2] then fields[map[2]] = map[3] end
        C:Log(map[1], fields)
    else
        -- Drops and refusals (DROP_*, LOGICAL_INTEGRITY, MEMORY_SCHEMA, conflicts).
        C:Log("PEER_PROTOCOL_ERROR", { peer = target, transfer = id, reason = code, mode = "WHISPER" })
    end
    if code == "PROPOSAL_AVAILABLE" then C.Say("COMMUNITY_PEER_PROPOSAL", tostring(target), id)
    elseif code == "READY_TO_STORE" then C.Say("COMMUNITY_PEER_READY", id)
    elseif code == "DELIVERED" then C.Say("COMMUNITY_PEER_DELIVERED", id) end
end

-- Paced, bounded, cancellable queue: the lab's bursts never reach the native call as is.
function R:Enqueue(target, packet, id, kind)
    for _, item in ipairs(self.queue) do if item.packet == packet and item.target == target then return end end
    if #self.queue >= self.queueLimit then
        C:Log("PEER_SEND_ERROR", { peer = target, transfer = id, reason = "QUEUE_FULL" })
        error("QUEUE_FULL", 0)
    end
    -- Every packet expires in the queue after one retry interval: the protocol retries, the
    -- queue never emits stale traffic.
    self.queue[#self.queue + 1] = { target = target, packet = packet, id = id, kind = kind,
        deadline = Uptime() + self.peer.policy.retryAfter }
end

-- A packet may leave only with live consent, before its queue deadline, and, when it belongs
-- to a local transaction, while that transaction is live at this exact moment.
function R:MayEmit(item, now)
    if not self.peer.identity.allowed[item.target] or now > item.deadline then return false end
    local may = self.peer:MayEmit(item.id, item.kind, now)
    if may == nil then return true end   -- a reply (HELLO_ACK, SNAPSHOT_RESPONSE, replayed ACK, REFUSE)
    return may
end

function R:Flush()
    while #self.queue > 0 do
        local item = table.remove(self.queue, 1)
        -- Consent and deadlines are re-checked at emission: a dead transfer never emits.
        if self:MayEmit(item, Uptime()) then
            if Call(_G.IsInInstance) == true then
                C:Log("PEER_SEND_ERROR", { peer = item.target, transfer = item.id, reason = "INSTANCE" })
            else
                local ok, failure = pcall(self.native.send, item.target, item.packet)
                if not ok then C:Log("PEER_SEND_ERROR", { peer = item.target, transfer = item.id, reason = tostring(failure) }) end
            end
            return
        end
    end
end

function R:OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= C.Transport.prefix or not self.peer then return end
    text, channel, sender = Readable(text), Readable(channel), Readable(sender)
    if type(text) ~= "string" or type(channel) ~= "string" then return end
    -- Broadcast audiences are refused for every Peer packet, both directions.
    if not C.Transport.Allowed(channel) then
        self.refusedBroadcast = (self.refusedBroadcast or 0) + 1
        return
    end
    local address = R.Address(sender)
    if not address then return end
    self.peer:receive({ from = address, mode = channel }, text)
end

function R:Start()
    local bucket = C.bucket
    if not bucket then return false end
    local P, Bytes = C.Peer, C.Bytes
    local random = C.random or math.random
    bucket.peer = bucket.peer or P.SanitizeDurable({})
    -- Per character, never per account: a peer cannot link two characters of one player.
    if not bucket.peer.reference then bucket.peer.reference = Bytes.RandomHex(12, random) end
    bucket.peer.sessionCounter = ((bucket.peer.sessionCounter or 0) + 1) % 65536
    local session = string.format("%04x", bucket.peer.sessionCounter) .. Bytes.RandomHex(4, random)
    local chat = _G.C_ChatInfo
    if type(chat) ~= "table" or not Call(chat.RegisterAddonMessagePrefix, C.Transport.prefix) then
        C:Log("PEER_STATE", { state = "UNAVAILABLE", reason = "PREFIX" })
        return false
    end
    self.queue, self.native = {}, C.Transport.Native("WHISPER")
    local identity = C.identity or {}
    local character = C.Identity.Make(identity.guid, identity.firstName, identity.realm) or { name = "?", realm = "?" }
    self.peer = P.New({ senderReference = bucket.peer.reference, session = session, character = character,
        durable = P.DurableStore(bucket), policy = P.POLICY, clock = Uptime, civil = C.Now,
        transport = { mode = "WHISPER", send = function(target, packet, id, kind) R:Enqueue(target, packet, id, kind) end },
        onEvent = function(code, id) R:OnPeerEvent(code, id) end })
    if not self.frame then
        self.frame = CreateFrame("Frame")
        self.frame:SetScript("OnEvent", function(_, _, ...) R:OnAddonMessage(...) end)
    end
    self.frame:RegisterEvent("CHAT_MSG_ADDON")
    self.ticker = C_Timer.NewTicker(self.tickSeconds, function() if R.peer then R.peer:tick() end end)
    self.pacer = C_Timer.NewTicker(self.pace, function() if R.peer then R:Flush() end end)
    C:Log("PEER_STATE", { state = "RUNNING", reason = "START" })
end

-- Reload, logout or switch-off: every transient state (consent, handshakes, buffers, queue) is dropped.
function R:Stop(reason)
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if self.pacer then self.pacer:Cancel(); self.pacer = nil end
    if self.frame then self.frame:UnregisterAllEvents() end
    if self.peer then C:Log("PEER_STATE", { state = "STOPPED", reason = tostring(reason) }) end
    self.peer, self.queue = nil, {}
end

-- ---------- tester commands: /ms community peer ... ----------
local function MemoryAt(index)
    local bucket = C.bucket
    local count = 0
    for _, id in ipairs(bucket and bucket.order or {}) do
        local memory = bucket.memories[id]
        if memory.source ~= "RECEIVED" then
            count = count + 1
            if count == index then return memory end
        end
    end
end

function R:StatusLines()
    local lines = {}
    local peer = self.peer
    if not peer then return { MS.L.COMMUNITY_PEER_OFF } end
    local D = C.Diagnostics
    local clear = D.IsComplete and D:IsComplete()
    local function Who(address) return clear and address or (D.root and D:Pseudonym(address) or "?") end
    lines[#lines + 1] = "session " .. peer.session .. "  queue " .. #self.queue .. "  broadcastRefused " .. (self.refusedBroadcast or 0)
    for address in pairs(peer.identity.allowed) do
        local binding = peer.identity:resolve(address)
        lines[#lines + 1] = string.format("allowed %s  bound=%s  ready=%s", Who(address), tostring(binding ~= nil), tostring(peer.ready[address] == true))
    end
    for id, tx in pairs(peer.outgoing) do lines[#lines + 1] = string.format("out %s %s %s", id, Who(tx.target), tx.state) end
    for id, tx in pairs(peer.incoming) do lines[#lines + 1] = string.format("in  %s %s %s", id, Who(tx.target), tx.state) end
    local index = 1
    while true do
        local memory = MemoryAt(index)
        if not memory then break end
        local text = C.MemoryBook.Lines(memory, MS.L, C.FormatDate)
        lines[#lines + 1] = string.format("memory %d  %s · %s  %s", index, text.place, text.date,
            clear and text.names or string.format(MS.L.COMMUNITY_PEER_COMPANIONS, #memory.companions))
        index = index + 1
    end
    return lines
end

local function Need(condition, code) if not condition then error({ code = code }, 0) end end

C.commands = C.commands or {}
C.commands.peer = function(self, rest)
    local verb, arg1, arg2 = string.match(rest or "", "^([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)")
    local peer = R.peer
    if verb == "status" or verb == "" then
        MS.Diagnostics:ShowCopyableReport(MS.L.COMMUNITY_PEER_TITLE, table.concat(R:StatusLines(), "\n"), "COMMUNITY_PEER")
        return
    end
    if not peer then C.Say("COMMUNITY_PEER_OFF"); return end
    local ok, failure = pcall(function()
        if verb == "allow" then
            local identity = C.Identity.FromAddress(arg1)
            Need(identity and identity.realm, "ADDRESS")
            peer.identity:allow(arg1, identity)
            C:Log("PEER_CONSENT", { peer = arg1, action = "ALLOW" })
            C.Say("COMMUNITY_PEER_ALLOWED", arg1)
        elseif verb == "revoke" then
            peer:revoke(arg1)
            C:Log("PEER_CONSENT", { peer = arg1, action = "REVOKE" })
            C.Say("COMMUNITY_PEER_REVOKED", arg1)
        elseif verb == "hello" then
            peer:hello(arg1)
        elseif verb == "offer" then
            local memory = MemoryAt(tonumber(arg1) or 0)
            Need(memory, "MEMORY_NOT_FOUND")
            local id = peer:propose(arg2, memory.id)
            C.Say("COMMUNITY_PEER_OFFERED", id)
        elseif verb == "accept" then peer:acceptProposal(arg1)
        elseif verb == "decline" then peer:declineProposal(arg1)
        elseif verb == "store" then
            Need(peer:storeReceived(arg1), "STORE_REFUSED")
            if C.OnMemoriesChanged then C:OnMemoriesChanged() end
            C.Say("COMMUNITY_PEER_STORED", arg1)
        else
            Need(false, "UNKNOWN_COMMAND")
        end
    end)
    if not ok then C.Say("COMMUNITY_PEER_ERROR", C.Wire.Code(failure)) end
end

C:Register("PeerRuntime", R)
