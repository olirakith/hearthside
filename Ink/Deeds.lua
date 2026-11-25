local MS = _G.MS
MS.Ink = MS.Ink or {}
-- What the player does that opens a page: talking to someone, an emote, creatures killed. Events
-- only, and only looked at while an open page waits for that kind. Nothing is written to chat.
local A = MS.Active
local I = MS.Ink
local D = { seen = {}, recent = {}, keep = 60, pairSeconds = 1 }
I.Deeds = D

-- The number of a creature in its GUID; nil for a player, a pet, an object or a hidden GUID.
function D.Creature(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

-- Talking --------------------------------------------------------------------------------------
local TALK = { "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "MERCHANT_SHOW", "TRAINER_SHOW" }

function D:Talked()
    local open = I.Watch.OpenPages("NPC")
    if #open == 0 then return end
    local npcID = self.Creature((A.Call(_G.UnitGUID, "npc")))
    local result = npcID and "OTHER" or "HIDDEN"
    for _, entry in ipairs(open) do
        if npcID and entry.page.trigger.npcID == npcID then
            result = I:Found(entry.id, entry.page.key, "NPC") or "WAIT"
            if result ~= "WAIT" then break end
        end
    end
    A:Log("INK_DEED", { kind = "NPC", source = "TALK", result = result })
end

-- Emotes ---------------------------------------------------------------------------------------
D.emotes = { "WAVE", "HELLO", "BYE", "BOW", "SALUTE", "KNEEL", "PRAY", "THANK", "CHEER", "APPLAUD", "DANCE", "LAUGH",
    "CRY", "MOURN", "KISS", "HUG", "POINT", "SIT", "SLEEP", "DRINK", "EAT", "ROAR", "BEG", "FLEX" }

-- How the game names an emote ("/wave"), in the language of the client.
local commands = {}
function D.Command(token)
    if commands[token] then return commands[token] end
    local plain = "/" .. string.lower(token)
    local chosen
    for index = 1, 700 do
        if A.Readable(_G["EMOTE" .. index .. "_TOKEN"]) == token then
            for number = 1, 4 do
                local command = A.Readable(_G["EMOTE" .. index .. "_CMD" .. number])
                if type(command) == "string" and command ~= "" then
                    chosen = chosen or command
                    -- Other languages also keep the English command: theirs is the one to show.
                    if A.Call(_G.GetLocale) ~= "enUS" and command ~= plain then chosen = command; break end
                end
            end
            break
        end
    end
    commands[token] = chosen or plain
    return commands[token]
end

function D.DoneHere(trigger)
    if trigger.npcID and D.Creature((A.Call(_G.UnitGUID, "target"))) ~= trigger.npcID then return false end
    if trigger.mapID and I.Watch.Classify(trigger, A.Position:Sample()) ~= "NEAR" then return false end
    return true
end

function D:Emoted(token)
    token = A.Readable(token)
    if type(token) ~= "string" or not I:Ready() then return end
    local open = I.Watch.OpenPages("EMOTE")
    if #open == 0 then return end
    token = token:upper()
    local result = "OTHER"
    for _, entry in ipairs(open) do
        local trigger = entry.page.trigger
        if trigger.token == token then
            result = "ELSEWHERE"
            if D.DoneHere(trigger) then
                result = I:Found(entry.id, entry.page.key, "EMOTE") or "WAIT"
                if result ~= "WAIT" then break end
            end
        end
    end
    A:Log("INK_DEED", { kind = "EMOTE", source = "HOOK", result = result })
end

-- The game's emote functions are only observed, once per session. One may call the other: two
-- calls in the same instant are one emote (a tale in order must not open two pages with it).
function D:Hook()
    if self.hooked or type(_G.hooksecurefunc) ~= "function" then return end
    self.hooked = true
    local function Seen(token)
        local now = A.Uptime()
        if self.emotedAt == now then return end
        self.emotedAt = now
        D:Emoted(token)
    end
    if type(_G.C_ChatInfo) == "table" and type(_G.C_ChatInfo.PerformEmote) == "function" then
        pcall(_G.hooksecurefunc, _G.C_ChatInfo, "PerformEmote", Seen)
    end
    if type(_G.DoEmote) == "function" then pcall(_G.hooksecurefunc, "DoEmote", Seen) end
end

-- Kills ----------------------------------------------------------------------------------------
-- PARTY_KILL names what the player or the group killed. The game may hide its target, or a pet
-- or a lasting wound may finish the creature without it: UNIT_DIED then counts, but only for a
-- creature that fell right after a hidden PARTY_KILL, or that the player was fighting and that
-- nobody else had first.
function D:Fallen(guid, source)
    local npcID = self.Creature(guid)
    if not npcID or self.seen[guid] then return end -- the same death is announced several times
    local wanted = false
    for _, entry in ipairs(I.Watch.OpenPages("KILL")) do
        if entry.page.trigger.npcID == npcID then
            wanted = true
            local count = I:Kill(entry.id, entry.page.key)
            A:Log("INK_DEED", { kind = "KILL", source = source, result = count and "COUNTED" or "WAIT" })
        end
    end
    if not wanted then return end
    self.seen[guid] = true
    self.recent[#self.recent + 1] = guid
    if #self.recent > self.keep then self.seen[table.remove(self.recent, 1)] = nil end
end

local function Mine(guid)
    for _, unit in ipairs({ "target", "pettarget" }) do
        if A.Call(_G.UnitGUID, unit) == guid then
            return A.Bool(A.Call(_G.UnitAffectingCombat, "player")) == true
                and A.Bool(A.Call(_G.UnitIsTapDenied, unit)) == false
        end
    end
    return false
end

function D:PartyKill(_, target)
    if #I.Watch.OpenPages("KILL") == 0 then return end
    target = A.Readable(target)
    if type(target) == "string" then return self:Fallen(target, "GROUP") end
    self.hiddenAt = A.Uptime()
end

function D:Died(guid)
    if #I.Watch.OpenPages("KILL") == 0 then return end
    guid = A.Readable(guid)
    if not self.Creature(guid) then return end
    if self.hiddenAt and A.Uptime() - self.hiddenAt <= self.pairSeconds then
        self.hiddenAt = nil
        return self:Fallen(guid, "PAIRED")
    end
    if Mine(guid) then self:Fallen(guid, "TARGET") end
end

-- Lifecycle --------------------------------------------------------------------------------------
function D:OnLogin() self:Hook() end

local events = CreateFrame("Frame")
for _, event in ipairs(TALK) do pcall(events.RegisterEvent, events, event) end
for _, event in ipairs({ "PARTY_KILL", "UNIT_DIED" }) do pcall(events.RegisterEvent, events, event) end
events:SetScript("OnEvent", function(_, event, ...)
    if not I:Ready() then return end
    if event == "PARTY_KILL" then D:PartyKill(...)
    elseif event == "UNIT_DIED" then D:Died(...)
    else D:Talked() end
end)

A:Register("InkDeeds", D)
