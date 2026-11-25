local MS = _G.MS
MS.Ink = MS.Ink or {}
-- Giving a tale to one player, in the game. The only file of L'Encre that talks to others, and
-- only by addon whisper to one named character: a proposal first, the seal only once the other
-- player accepted it. Nothing leaves in a fight. Every transfer lives for this session only.
--
-- Packets ("TYPE;id;..."), at most 255 bytes, prefix HSINK1:
--   giver    -> receiver   O;id;parts;length;crc;tale id;mode;pages;title   proposal
--                          D;id;n;chunk                                     one part
--                          X;id                                             taken back
--   receiver -> giver      A;id  seen   Y;id  accepted   N;id;reason  refused
--                          R;id;n,n,...  parts still missing   K;id;result  done
local A = MS.Active
local I = MS.Ink
local C = {
    prefix = "HSINK1", wire = 255, chunk = 200, maxParts = 120,
    pace = .25, burst = 8, refill = 1, queueLimit = 400,
    seenSeconds = 12, answerSeconds = 120, idleSeconds = 15, deadSeconds = 90,
    maxOffers = 3, senderGap = 20, throttleLimit = 30,
    outgoing = nil, offers = {}, queue = {}, lastFrom = {},
}
I.Courier = C

A.Diagnostics.codes.INK_OFFER = { way = "text", state = "text", reason = "text", parts = "number" }

local function Log(way, state, reason, parts)
    A:Log("INK_OFFER", { way = way, state = state, reason = reason, parts = parts })
end

local function InCombat() return A.Bool(A.Call(_G.InCombatLockdown)) ~= false end

-- "First Surname" as some events give it is "First-Surname" for a whisper.
function C.Address(sender)
    if type(sender) ~= "string" or sender == "" or #sender > 100 or sender:find("[%c;]") then return nil end
    return (sender:gsub("^([^%- ]+) ([^%- ]+)$", "%1-%2"))
end

local function First(name) return A.Text.FoldAscii(name:match("^[^%- ]+") or name) end

local function Integer(text, minimum, maximum)
    local value = type(text) == "string" and text:match("^%d+$") and #text <= 10 and tonumber(text) or nil
    return value and value >= minimum and value <= maximum and value or nil
end

local function Changed()
    if A.Panel then A.Panel:Changed("INK") end
end

-- Sending: a token bucket (the game gives each prefix a burst, then about one packet a second).
function C:Enqueue(target, packet, id)
    if #packet > self.wire or #self.queue >= self.queueLimit then return false end
    self.queue[#self.queue + 1] = { target = target, packet = packet, id = id }
    if not self.pacer and _G.C_Timer then self.pacer = C_Timer.NewTicker(self.pace, function() C:Flush() end) end
    return true
end

function C:Drop(id)
    for index = #self.queue, 1, -1 do if self.queue[index].id == id then table.remove(self.queue, index) end end
end

-- true sent, "THROTTLED" to try again, false refused by the client.
local function Send(target, packet)
    local chat = _G.C_ChatInfo
    if type(chat) ~= "table" or type(chat.SendAddonMessage) ~= "function" then return false end
    local ok, result = pcall(chat.SendAddonMessage, C.prefix, packet, "WHISPER", target)
    if not ok or result == false then return false end
    if type(result) == "number" and result ~= 0 then
        local throttled = result == 3 or result == 8
        return throttled and "THROTTLED" or false
    end
    return true
end

function C:Flush()
    local now = A.Uptime()
    self.tokens = math.min(self.burst, (self.tokens or self.burst) + (now - (self.tokensAt or now)) * self.refill)
    self.tokensAt = now
    local item = self.queue[1]
    if not item then
        if self.pacer then self.pacer:Cancel(); self.pacer = nil end
        return
    end
    if InCombat() or self.tokens < 1 then return end
    local sent = Send(item.target, item.packet)
    self.tokens = sent == "THROTTLED" and 0 or self.tokens - 1
    if sent == "THROTTLED" then
        item.tries = (item.tries or 0) + 1
        if item.tries <= self.throttleLimit then return end
        sent = false
    end
    table.remove(self.queue, 1)
    local out = self.outgoing
    if not sent and out and out.id == item.id then self:Finish("REFUSED_BY_GAME") end
    if sent and out and out.id == item.id then out.sentAt = now end
end

-- One check a second while anything is under way.
function C:Wake()
    if not self.ticker and _G.C_Timer then self.ticker = C_Timer.NewTicker(1, function() C:Tick() end) end
end

-- GIVER -----------------------------------------------------------------------------------------
-- Returns true, or false and NOT_READY | NAME | BUSY | COMBAT | UNKNOWN | TOO_LONG | UNAVAILABLE.
function C:Offer(taleId, typed)
    if not I:Ready() then return false, "NOT_READY" end
    if not self.registered then return false, "UNAVAILABLE" end
    if self:Busy() then return false, "BUSY" end
    if InCombat() then return false, "COMBAT" end
    local target = A.Text.RecipientName(typed, A.Seals:DefaultRealm())
    if not target then return false, "NAME" end
    local entry, seal = I:Entry(taleId), I:Seal(taleId)
    if not entry or not seal then return false, "UNKNOWN" end
    local parts = {}
    for from = 1, #seal, self.chunk do parts[#parts + 1] = seal:sub(from, from + self.chunk - 1) end
    if #parts > self.maxParts then return false, "TOO_LONG" end
    local Bytes = MS.Community.Bytes
    local id = Bytes.RandomHex(8, A.random or math.random)
    local head = table.concat({ "O", id, #parts, #seal, Bytes.Crc32(seal), entry.tale.id, entry.tale.mode,
        #entry.tale.pages }, ";") .. ";"
    local packet = head .. A.Text.CleanLine(entry.tale.title, 64)
    self.outgoing = { id = id, taleId = taleId, title = entry.tale.title, target = target, parts = parts, state = "SENT",
        deadline = nil }
    if not self:Enqueue(target, packet, id) then self.outgoing = nil; return false, "UNAVAILABLE" end
    Log("OUT", "SENT", nil, #parts)
    self:Wake()
    Changed()
    return true
end

function C:Busy()
    local out = self.outgoing
    return out ~= nil and out.state ~= "DONE"
end

-- The offer is over; its outcome stays readable until the next one.
function C:Finish(reason)
    local out = self.outgoing
    if not out or out.state == "DONE" then return end
    out.state, out.reason, out.parts = "DONE", reason, nil
    self:Drop(out.id)
    Log("OUT", "DONE", reason)
    local person = MS.BroadcastMode and MS.BroadcastMode:Person(out.target) or out.target
    A:Say("INK_GIVE_" .. reason, person, out.title)
    Changed()
end

function C:Cancel()
    local out = self.outgoing
    if not self:Busy() then return end
    local target, id = out.target, out.id
    self:Finish("CANCELLED")
    self:Enqueue(target, "X;" .. id, "X" .. id)
end

local function SendParts(out, wanted)
    for _, number in ipairs(wanted) do
        C:Enqueue(out.target, "D;" .. out.id .. ";" .. number .. ";" .. out.parts[number], out.id)
    end
end

C.results = { KEPT = "DELIVERED", SAME = "ALREADY", OLDER = "ALREADY", FULL = "FULL", FAILED = "FAILED" }
local REFUSALS = { DECLINED = "DECLINED", BUSY = "THEY_ARE_BUSY", EXPIRED = "NO_ANSWER" }

function C:Reply(kind, out, rest)
    if kind == "A" and out.state == "SENT" then
        out.state, out.askedAt = "ASKED", A.Uptime()
    elseif kind == "Y" and (out.state == "SENT" or out.state == "ASKED") then
        out.state, out.heardAt = "SENDING", A.Uptime()
        local all = {}
        for number = 1, #out.parts do all[number] = number end
        Log("OUT", "SENDING", nil, #all)
        SendParts(out, all)
    elseif kind == "N" and (out.state == "SENT" or out.state == "ASKED") then
        return self:Finish(REFUSALS[rest] or "DECLINED")
    elseif kind == "R" and out.state == "SENDING" and not out.resent then
        -- One more try, for the parts the receiver did not get.
        out.resent, out.heardAt = true, A.Uptime()
        local wanted, seen = {}, {}
        for text in rest:gmatch("%d+") do
            local number = Integer(text, 1, #out.parts)
            if number and not seen[number] then seen[number] = true; wanted[#wanted + 1] = number end
        end
        -- The request is one packet: with many parts missing, everything after the last one named.
        if rest:sub(-1) == "+" and #wanted > 0 then
            for number = wanted[#wanted] + 1, #out.parts do wanted[#wanted + 1] = number end
        end
        self:Drop(out.id)
        SendParts(out, wanted)
    elseif kind == "K" and out.state == "SENDING" then
        return self:Finish(self.results[rest] or "FAILED")
    else
        return
    end
    Changed()
end

-- RECEIVER --------------------------------------------------------------------------------------
function C:Find(id)
    for index, offer in ipairs(self.offers) do if offer.id == id then return offer, index end end
end

local function Remove(offer)
    local _, index = C:Find(offer.id)
    if index then table.remove(C.offers, index) end
    Changed()
end

local function Ignored(sender)
    local api = _G.C_FriendList
    return type(api) == "table" and A.Call(api.IsIgnored, sender) == true
end

function C:Proposed(sender, id, rest)
    local parts, length, crc, taleId, mode, pages, title = rest:match("^(%d+);(%d+);(%x+);(%x+);(%a+);(%d+);(.+)$")
    parts, length, pages = Integer(parts, 1, self.maxParts), Integer(length, 1, self.maxParts * self.chunk), Integer(pages, 1, I.Tale.maxPages)
    title = title and A.Text.CleanLine(title, I.Tale.titleBytes)
    if not (parts and length and pages and title and #crc == 8 and #taleId == 8 and I.Tale.modes[mode])
        or math.ceil(length / self.chunk) ~= parts then return end
    if not I:Ready() or Ignored(sender) or self:Find(id) then return end
    local now, key = A.Uptime(), First(sender)
    local last = self.lastFrom[key]
    if #self.offers >= self.maxOffers or (last and now - last < self.senderGap) then
        Log("IN", "SKIPPED", "LIMIT")
        self:Enqueue(sender, "N;" .. id .. ";BUSY", id)
        return
    end
    self.lastFrom[key] = now
    self.offers[#self.offers + 1] = { id = id, sender = sender, title = title, mode = mode, pages = pages, taleId = taleId,
        count = parts, length = length, crc = crc:lower(), state = "ASKING", deadline = now + self.answerSeconds, got = {}, have = 0 }
    Log("IN", "ASKING", nil, parts)
    self:Enqueue(sender, "A;" .. id, id)
    self:Wake()
    self:Pump()
end

-- The card asks about the oldest proposal. Never in a fight, never over an open window.
function C:Pump()
    local offer
    for _, candidate in ipairs(self.offers) do if candidate.state == "ASKING" then offer = candidate; break end end
    -- A card still telling how the previous one ended is left to the player.
    if not offer or not A.Panel or InCombat() or A.Panel:IsShown() or A.Panel.suspended then return end
    -- A busy stage is asked again a little later.
    local now = A.Uptime()
    if self.retryAt and now < self.retryAt then return end
    self.asking = offer
    if A.Panel:Open("INK_OFFERED", "RESULT") then self.retryAt = nil else self.retryAt = now + I.retrySeconds end
end

function C:Accept(offer)
    if not offer or offer.state ~= "ASKING" then return end
    offer.state, offer.heardAt = "RECEIVING", A.Uptime()
    Log("IN", "RECEIVING", nil, offer.count)
    self:Enqueue(offer.sender, "Y;" .. offer.id, offer.id)
    Changed()
end

function C:Decline(offer, reason)
    if not offer or offer.state ~= "ASKING" then return end
    Log("IN", "DECLINED", reason)
    self:Enqueue(offer.sender, "N;" .. offer.id .. ";" .. (reason or "DECLINED"), offer.id)
    Remove(offer)
end

local function Missing(offer)
    local list = {}
    for number = 1, offer.count do if not offer.got[number] then list[#list + 1] = number end end
    return list
end

function C:Part(offer, rest)
    local number, chunk = rest:match("^(%d+);(.+)$")
    number = Integer(number, 1, offer.count)
    if not number or offer.state ~= "RECEIVING" or #chunk > self.chunk or offer.got[number] then return end
    offer.got[number], offer.have, offer.heardAt = chunk, offer.have + 1, A.Uptime()
    if offer.have == offer.count then return self:Assemble(offer) end
    Changed()
end

-- All parts are here: the same decoder as a pasted seal decides, and only the promised tale counts.
function C:Assemble(offer)
    local seal, Bytes = table.concat(offer.got), MS.Community.Bytes
    local tale, entry, reason
    if #seal == offer.length and Bytes.Crc32(seal) == offer.crc then
        tale = I.Codec.Decode(seal, A.Now())
    end
    if tale and tale.id == offer.taleId then entry, reason = I:Keep(tale, "KEPT", offer.sender) end
    local result = entry and "KEPT" or C.results[reason] and reason or "FAILED"
    Log("IN", "DONE", reason or "FAILED", offer.count)
    self:Enqueue(offer.sender, "K;" .. offer.id .. ";" .. result, offer.id)
    offer.state = "DONE"
    offer.result, offer.kept = tale and reason or "FAILED", tale and I:Entry(tale.id) ~= nil and reason ~= "CONFLICT"
    Remove(offer)
    if tale and reason then A:Say("INK_IMPORT_" .. reason, tale.title) else A:Say("INK_OFFER_FAILED") end
end

local function Fail(offer, reason)
    Log("IN", "DONE", reason)
    offer.state, offer.result = "DONE", "FAILED"
    Remove(offer)
    A:Say("INK_OFFER_FAILED")
end

-- Clock -----------------------------------------------------------------------------------------
function C:Tick()
    local now, out = A.Uptime(), self.outgoing
    if self:Busy() then
        -- The waiting starts when the packets have left (a fight holds them).
        local queued = false
        for _, item in ipairs(self.queue) do if item.id == out.id then queued = true end end
        if queued then out.waitFrom = now end
        local since = math.max(out.waitFrom or 0, out.sentAt or 0, out.heardAt or 0, out.askedAt or 0)
        if out.state == "SENT" and not queued and now - since > self.seenSeconds then self:Finish("UNREACHED")
        elseif out.state == "ASKED" and now - since > self.answerSeconds + 10 then self:Finish("NO_ANSWER")
        elseif out.state == "SENDING" and not queued and now - since > self.deadSeconds then self:Finish("FAILED") end
    end
    for index = #self.offers, 1, -1 do
        local offer = self.offers[index]
        if offer and offer.state == "ASKING" and now > offer.deadline then
            self:Decline(offer, "EXPIRED")
        elseif offer and offer.state == "RECEIVING" then
            local idle = now - offer.heardAt
            if idle > self.deadSeconds then
                Fail(offer, "LOST")
            elseif idle > self.idleSeconds and not offer.asked then
                offer.asked = true
                local text, list = "", Missing(offer)
                for _, number in ipairs(list) do
                    if #text > 220 then text = text .. "+"; break end
                    text = text .. (text ~= "" and "," or "") .. number
                end
                self:Enqueue(offer.sender, "R;" .. offer.id .. ";" .. text, offer.id)
            end
        end
    end
    self:Pump()
    if not self:Busy() and #self.offers == 0 and self.ticker then self.ticker:Cancel(); self.ticker = nil end
end

-- Wire ------------------------------------------------------------------------------------------
function C:OnAddonMessage(prefix, text, channel, sender)
    prefix, text, channel, sender = A.Readable(prefix), A.Readable(text), A.Readable(channel), A.Readable(sender)
    if prefix ~= self.prefix or channel ~= "WHISPER" or type(text) ~= "string" or #text > self.wire then return end
    local address = C.Address(sender)
    local kind, id, rest = text:match("^(%u);(%x+);?(.*)$")
    if not address or not kind or #id ~= 8 then return end
    if kind == "O" then return self:Proposed(address, id, rest) end
    if kind == "D" or kind == "X" then
        local offer = self:Find(id)
        if not offer or First(offer.sender) ~= First(address) then return end
        if kind == "D" then return self:Part(offer, rest) end
        Log("IN", "DONE", "WITHDRAWN")
        offer.state = "DONE"
        return Remove(offer)
    end
    local out = self.outgoing
    if out and out.id == id and self:Busy() and First(out.target) == First(address) then self:Reply(kind, out, rest) end
end

-- The game answers an unknown or offline character with one system line.
function C:OnSystem(text)
    local out = self.outgoing
    if not out or out.state ~= "SENT" then return end
    text = A.Readable(text)
    local template = _G.ERR_CHAT_PLAYER_NOT_FOUND_S
    if type(text) ~= "string" or type(template) ~= "string" then return end
    local head, tail = template:match("^(.-)%%[%d%$]*s(.*)$")
    local name = out.target:match("^[^%-]+")
    if head and text:find(head, 1, true) and text:find(tail, 1, true) and text:find(name, 1, true) then self:Finish("OFFLINE") end
end

function C:OnLogin()
    local chat = _G.C_ChatInfo
    local ok, result = false, nil
    if type(chat) == "table" and type(chat.RegisterAddonMessagePrefix) == "function" then
        ok, result = pcall(chat.RegisterAddonMessagePrefix, self.prefix)
    end
    -- true on older clients; newer ones return an enum: 0 done, 1 already registered.
    self.registered = ok and (result == true or result == 0 or result == 1 or result == nil)
    if not self.registered or self.frame then return end
    self.frame = CreateFrame("Frame")
    pcall(self.frame.RegisterEvent, self.frame, "CHAT_MSG_ADDON")
    pcall(self.frame.RegisterEvent, self.frame, "CHAT_MSG_SYSTEM")
    self.frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then C:OnAddonMessage(...) else C:OnSystem(...) end
    end)
end

function C:OnCombat(inCombat)
    if not inCombat then self:Pump() end
end

A:Register("InkCourier", C)
