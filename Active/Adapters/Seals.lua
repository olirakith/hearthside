local MS = _G.MS
MS.Active = MS.Active or {}
-- Sur mes pas in the game: create, import, watch, open. The watcher only runs while this
-- character has a seal waiting, reads the place once a second and stores none of it.
local A = MS.Active
local S = { interval = 1, streak = {}, nearSaid = {}, nearRetry = 10 }
A.Seals = S

local function Book() return A.SealBook end
function S:All() return A.Store.root and A.Store.root.seals or {} end

function S:Armed()
    if not A:Ready() then return {} end
    return Book():ArmedFor(self:All(), A.identity)
end

-- What a bare typed name completes with: the realm, except where characters have a surname.
function S:DefaultRealm()
    if Book():Surname(A.identity) then return nil end
    return A.Text.NormalizeRealm(A.identity.realm)
end

-- Battle.net friends in this same game right now. The game only gives a friend's character while
-- that friend plays it, and whispers do not cross factions. Only the character name is read: an
-- account's real name or BattleTag never leaves the game's own frames.
local function BattleNetFriends(add)
    local api = _G.C_BattleNet
    local count = A.Call(_G.BNGetNumFriends)
    if type(api) ~= "table" or type(count) ~= "number" then return end
    local faction = A.Call(_G.UnitFactionGroup, "player")
    for index = 1, math.min(count, 200) do
        local account = A.Call(api.GetFriendAccountInfo, index)
        local game = type(account) == "table" and A.Readable(account.gameAccountInfo) or nil
        if type(game) == "table" and A.Readable(game.isOnline) == true and A.Readable(game.clientProgram) == "WoW"
            and A.Readable(game.wowProjectID) == _G.WOW_PROJECT_ID and A.Readable(game.factionName) == faction then
            add(A.Readable(game.characterName), true)
        end
    end
end

-- Who the friends button offers: in-game friends, Battle.net friends in the game, then the people
-- this account already sent a code to, online first. online is nil when nobody can tell.
-- Read when asked, never stored or logged.
function S:Friends()
    local list, seen, Text = {}, {}, A.Text
    local realm, own = self:DefaultRealm(), Text.NameKey(Book():IdentityName(A.identity))
    local function Add(name, online)
        local key = type(name) == "string" and Text.NameKey(Text.RecipientName(name, realm)) or nil
        if not key or key == own then return end
        local known = seen[key]
        if known then
            if online == true then known.online = true end
            return
        end
        seen[key] = { name = name, online = online }
        list[#list + 1] = seen[key]
    end
    local api = _G.C_FriendList
    if type(api) == "table" then
        local count = A.Call(api.GetNumFriends)
        for index = 1, type(count) == "number" and count or 0 do
            local info = A.Call(api.GetFriendInfoByIndex, index)
            if type(info) == "table" then Add(A.Readable(info.name), A.Readable(info.connected) == true) end
        end
    end
    BattleNetFriends(Add)
    for _, seal in pairs(self:All()) do
        if seal.state == "SENT" and seal.kind == "CHAR" then Add(seal.recipient) end
    end
    table.sort(list, function(a, b)
        if (a.online == true) ~= (b.online == true) then return a.online == true end
        return a.name:lower() < b.name:lower()
    end)
    return list
end

-- false only when the friend list says so; nil for anyone it does not know.
function S:RecipientOnline(recipient)
    local Text = A.Text
    local realm, wanted = self:DefaultRealm(), Text.NameKey(recipient)
    for _, friend in ipairs(self:Friends()) do
        if Text.NameKey(Text.RecipientName(friend.name, realm)) == wanted then return friend.online end
    end
end

function S:Refresh(reason)
    local armed = self:Armed()
    local mapID, here = A.Position:MapID(), 0
    for _, seal in ipairs(armed) do if seal.mapID == mapID then here = here + 1 end end
    if reason then A:Log("SEAL_ARMED", { count = #armed, here = here }) end
    if #armed > 0 and not self.ticker and _G.C_Timer then
        self.ticker = C_Timer.NewTicker(self.interval, function() S:Tick() end)
    elseif #armed == 0 and self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    self.streak = {}
    if A.Panel then A.Panel:Changed("SEAL") end
end

function S:OnLogin()
    -- A seal opened just before a reload, a disconnect or a fight is shown again until seen.
    for _, seal in pairs(self:All()) do
        if seal.state == "OPENED" and seal.seen == false and seal.openedBy == A.identity.key and A.Reveal then A.Reveal:Queue(seal) end
    end
    self:Refresh("LOGIN")
end

function S:OnEnteringWorld() self.streak = {} end
function S:OnCombat() self.streak = {} end

-- Any zone change restarts every streak: the next three samples are read on the new map.
local zones = CreateFrame("Frame")
for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS" }) do
    pcall(zones.RegisterEvent, zones, event)
end
zones:SetScript("OnEvent", function() S.streak = {} end)

-- In the radius but kept closed (a fight, a ghost, a flight): said once per change, never where.
local HELD = { COMBAT = true, DEAD = true, TAXI = true }

-- Diagnostics only record when the answer changes (FAR -> NEAR...), never the place itself.
function S:Note(result)
    if result ~= self.lastResult then
        self.lastResult = result
        A:Log("SEAL_PROXIMITY_CHECKED", { result = result })
    end
end

-- "The seal feels close": once per seal and per session, never where; one message covers every
-- seal close by. A refused card (another card showing, a cooldown) is asked again a little later
-- while the player is still near.
function S:SayNear(seals)
    local now, unsaid = A.Uptime(), false
    for _, seal in ipairs(seals) do unsaid = unsaid or not self.nearSaid[seal.id] end
    if not unsaid or now < (self.nearNextTry or 0) then return end
    if A.Toast and A.Toast:Near() then
        for _, seal in ipairs(seals) do self.nearSaid[seal.id] = true end
        A:Log("SEAL_NEAR_SAID", { count = #seals })
    else
        self.nearNextTry = now + self.nearRetry
    end
end

function S:Tick()
    if not A:Ready() then return end
    local mapID = A.Position:MapID()
    local candidates = {}
    for _, seal in ipairs(self:Armed()) do if seal.mapID == mapID then candidates[#candidates + 1] = seal end end
    if #candidates == 0 then
        self.streak, self.lastRefused = {}, nil
        self:Note("OTHER_MAP")
        return
    end
    local sample = A.Position:Sample()
    local best
    local close = {}
    for _, seal in ipairs(candidates) do
        local result = Book():Classify(seal, sample)
        if result == "NEAR" then
            self.streak[seal.id] = (self.streak[seal.id] or 0) + 1
            if self.streak[seal.id] >= Book().streak then return self:Open(seal) end
        else
            self.streak[seal.id] = 0
            if HELD[result] and self.lastRefused ~= result then
                self.lastRefused = result
                A:Log("SEAL_REFUSED", { reason = result })
            end
        end
        if Book():Vicinity(seal, sample) then close[#close + 1] = seal end
        if not best or result == "NEAR" then best = result end
    end
    self:SayNear(close)
    self:Note(best)
end

function S:Open(seal)
    local now = A.Now()
    local opened = Book():Open(self:All(), seal.id, A.identity, now)
    self.streak = {}
    if not opened then return end
    A:Log("SEAL_OPENED", { kind = opened.kind, days = Book().Days(opened.createdAt, now) })
    if A.Reveal then A.Reveal:Queue(opened) end
    self:Refresh()
end

-- What the creation view shows for the current place (no write).
function S:Here()
    local sample = A.Position:Sample()
    local ok, reason = Book():CanSealHere(sample)
    return ok, reason, sample, ok and A.Position:MapName(sample.mapID) or nil, A.Call(_G.GetSubZoneText)
end

-- kind: NEXT | CHAR | ANY. Returns the record, or nil and a reason the view can explain.
function S:Create(kind, text, recipientTyped)
    if not A:Ready() or not A.identity.key then return nil, "NOT_READY" end
    local recipient
    if kind == "CHAR" then
        recipient = A.Text.RecipientName(recipientTyped, self:DefaultRealm())
        if not recipient then A:Log("SEAL_CREATE_REFUSED", { reason = "RECIPIENT" }); return nil, "RECIPIENT" end
    end
    local sample = A.Position:Sample()
    local hint = A.Call(_G.GetSubZoneText)
    if type(hint) ~= "string" or hint == A.Position:MapName(sample.mapID) then hint = nil end
    local seal, reason = Book():Create(self:All(), { kind = kind, text = text, recipient = recipient, identity = A.identity,
        sample = sample, now = A.Now(), random = A.random or math.random, hint = hint })
    if not seal then
        A:Log("SEAL_CREATE_REFUSED", { reason = reason })
        return nil, reason
    end
    A:Log("SEAL_CREATED", { kind = kind, bytes = #seal.text, mapType = sample.mapType })
    self:Refresh()
    return seal
end

-- From the code box or /aj code. Returns the armed record, or nil and a reason.
function S:Import(text, source)
    if not A:Ready() then return nil, "NOT_READY" end
    local decoded, reason = A.SealCodec.Decode(text, A.Now())
    if decoded then
        decoded, reason = Book():Import(self:All(), decoded, A.identity, A.Now())
    end
    A:Log("SEAL_IMPORTED", { kind = decoded and decoded.kind or "?", result = decoded and "ARMED" or reason })
    if decoded then self:Refresh("IMPORT") end
    return decoded, reason
end

function S:ImportFromText(text, source)
    local seal, reason = self:Import(text, source)
    if seal then
        A:Say("SEAL_IMPORT_OK", A.Position:MapName(seal.mapID) or MS.L.SEAL_SOMEWHERE)
    else
        A:Say("SEAL_IMPORT_" .. (reason or "MALFORMED"))
    end
    return seal, reason
end

-- The author's copy of a code for one character: a whisper prepared for that character.
function S:WhisperCode(seal)
    if seal.state ~= "SENT" or seal.kind ~= "CHAR" or not seal.recipient then return false, "NO_RECIPIENT" end
    if self:RecipientOnline(seal.recipient) == false then
        A:Log("SEAL_REPLIED", { kind = "SHARE", result = "OFFLINE" })
        return false, "OFFLINE"
    end
    local text = string.format(MS.L.SEAL_WHISPER_TEXT, seal.code)
    local ok, reason = A.Chat:Prefill("/w " .. seal.recipient .. " ", text)
    if not ok and reason == "TOO_LONG" then ok, reason = A.Chat:Prefill("/w " .. seal.recipient .. " ", seal.code) end
    A:Log("SEAL_REPLIED", { kind = "SHARE", result = ok and "PREFILLED" or reason })
    if ok and A.SealOffers then A.SealOffers:Watch(seal.recipient) end
    return ok, reason
end

-- Reply to an opened seal from someone else: a whisper to its author (prepared, not sent).
function S:Reply(seal)
    if seal.origin ~= "IMPORTED" or not seal.author then return false, "NO_AUTHOR" end
    local ok, reason = A.Chat:Prefill("/w " .. seal.author .. " ", MS.L.SEAL_REPLY_TEXT)
    A:Log("SEAL_REPLIED", { kind = seal.kind, result = ok and "PREFILLED" or reason })
    return ok, reason
end

function S:Abandon(id)
    if Book():Abandon(self:All(), id, A.Now()) then
        A:Log("SEAL_ARCHIVED", { reason = "ABANDONED", count = 1 })
        self:Refresh()
        return true
    end
    return false
end

function S:MarkSeen(seal)
    if seal and seal.state == "OPENED" then seal.seen = true end
end

A:Register("Seals", S)
