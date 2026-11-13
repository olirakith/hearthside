local MS = _G.MS
MS.Active = MS.Active or {}
-- Sur mes pas codes travelling by whisper. The chat cannot be copied, so Journey recognises a code
-- sent to this character and asks whether to keep it: nothing is armed without that click. Only a
-- valid code leaves the event; the rest of a whisper is neither kept nor logged, and offers live
-- for this session only.
local A = MS.Active
local O = { pending = {}, limit = 3, senderGap = 30, lastFrom = {}, watchSeconds = 300 }
A.SealOffers = O

local function Skip(reason) A:Log("SEAL_OFFER_SKIPPED", { reason = reason }) end

function O:Receive(text, sender)
    text, sender = A.Readable(text), A.Readable(sender)
    if type(text) ~= "string" or not text:find("AJ1:", 1, true) then return end
    if type(sender) ~= "string" or sender == "" or not A:Ready() then return end
    local now = A.Now()
    local decoded, reason = A.Call(A.SealCodec.Decode, text, now)
    if not decoded then return Skip(reason or "MALFORMED") end
    local ok
    ok, reason = A.SealBook:CanImport(A.Seals:All(), decoded, A.identity, now)
    -- A full book still asks: keeping the seal is what explains why it cannot be kept.
    if not ok and reason ~= "FULL" then return Skip(reason) end
    for _, offer in ipairs(self.pending) do if offer.id == decoded.id then return Skip("PENDING") end end
    if #self.pending >= self.limit then return Skip("LIMIT") end
    local uptime = A.Uptime()
    local last = self.lastFrom[sender]
    if last and uptime - last < self.senderGap then return Skip("SENDER_GAP") end
    self.lastFrom[sender] = uptime
    self.pending[#self.pending + 1] = { id = decoded.id, mapID = decoded.mapID, code = "AJ1:" .. A.SealCodec.Find(text),
        sender = sender:match("^[^%-]+") or sender }
    A:Log("SEAL_OFFERED", { kind = decoded.kind })
    self:Pump()
end

-- The first offer stays in the list until answered: a fight or a more important card only hides
-- it, and it comes back here.
function O:Pump()
    if #self.pending == 0 then
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
        return
    end
    if not self.ticker and _G.C_Timer then self.ticker = C_Timer.NewTicker(2, function() O:Pump() end) end
    local toast = A.Toast
    if not toast or (toast.token and toast.kind == "OFFER") or A.Panel.suspended then return end
    if MS.JourneyCardArbiter:Allow("OFFER") then toast:Offer(self.pending[1]) end
end

function O:Answer(keep)
    local offer = table.remove(self.pending, 1)
    if not offer then return end
    A:Log("SEAL_OFFER_ANSWERED", { result = keep and "KEPT" or "IGNORED" })
    if keep then A.Seals:ImportFromText(offer.code, "WHISPER") end
    self:Pump()
end

-- After a prepared whisper: the game answers a player it cannot reach with one system line.
function O:Watch(recipient)
    self.watched = { name = recipient:match("^[^%-]+") or recipient, untilAt = A.Uptime() + self.watchSeconds }
end

function O:System(text)
    local watched = self.watched
    if not watched then return end
    if A.Uptime() > watched.untilAt then self.watched = nil; return end
    text = A.Readable(text)
    local template = _G.ERR_CHAT_PLAYER_NOT_FOUND_S
    if type(text) ~= "string" or type(template) ~= "string" then return end
    local head, tail = template:match("^(.-)%%[%d%$]*s(.*)$")
    if not head or not text:find(head, 1, true) or not text:find(tail, 1, true) or not text:find(watched.name, 1, true) then return end
    self.watched = nil
    A:Log("SEAL_WHISPER_UNREACHED", { kind = "CHAR" })
    A:Say("SEAL_WHISPER_UNREACHED", watched.name)
end

local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "CHAT_MSG_WHISPER")
pcall(events.RegisterEvent, events, "CHAT_MSG_SYSTEM")
events:SetScript("OnEvent", function(_, event, text, sender)
    if event == "CHAT_MSG_WHISPER" then O:Receive(text, sender) else O:System(text) end
end)
