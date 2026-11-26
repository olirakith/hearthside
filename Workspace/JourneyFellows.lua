local MS = _G.MS

-- Guildmates and friends on the Journey map, on two levels:
--  * everyone online in the guild and on the friends list, by zone, as the game's own lists give
--    it (nothing is sent for that): a badge on their zone on a continent map, one in a corner of
--    the zone's own map;
--  * those who share where they are: a dot in their class colour where they stand.
-- Sharing speaks OpenMap's open protocol (MIT, prefix "OpenMapLoc", also read by OneForAll), so
-- players of those addons and of Hearthside see each other. Tab-separated messages:
--   L1 uiMapID x y CLASS level   where I stand (x, y on that map, 0..1)
--   L0                           I stopped sharing
--   H1 / H2                      hello to a friend as they come online, and its answer
-- OneForAll's own guild messages (prefix "OFAGuildPos") are only listened to, never sent:
--   P map x y CLASS level token   where they stand (x, y in ten-thousandths)
--   I dungeon CLASS level token   inside a dungeon       X   stopped
-- Sharing is off until the player turns it on, and only the place leaves; nothing from a
-- dungeon, raid or battleground. Streamer mode shows nobody. The game draws the party itself: group members get no dot and no badge.
MS.JourneyFellows = {
    prefix = "OpenMapLoc", oneForAll = "OFAGuildPos", tick = 2, sendEvery = 10, stillEvery = 60, goneAfter = 150, moved = .002,
    gap = .5, rosterEvery = 30, rosterStale = 5, listMax = 15,
    live = {}, known = {}, friends = {}, queue = {}, version = 0, sharing = false,
    last = { at = -math.huge },
}
local F = MS.JourneyFellows

-- Forever can hand addons "secret" values: any value the addon may not read counts as absent.
local function Readable(value)
    if value == nil then return nil end
    local check = _G.canaccessvalue
    if type(check) == "function" then
        local ok, accessible = pcall(check, value)
        if not ok or not accessible then return nil end
    end
    return value
end

-- Every return value of fn, filtered, in a table; nil when fn is missing or fails.
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    table.remove(result, 1)
    for index = 1, table.maxn(result) do result[index] = Readable(result[index]) end
    return result
end

local function First(fn, ...)
    local result = Call(fn, ...)
    return result and result[1]
end

local function Now() return tonumber(First(_G.GetTime)) or 0 end
local function Setting(key) return MS.JourneySettings and MS.JourneySettings:Get(key) end
local function Text(value) return type(value) == "string" and value ~= "" and value or nil end

function F:Showing() return Setting("mapIconFELLOW") ~= false and not (MS.BroadcastMode and MS.BroadcastMode:IsOn()) end
function F:Sharing() return Setting("mapShareWhere") == true end

-- One key per character, whatever the source writes: "First Surname", "First-Surname" or
-- "First Surname-Realm" all give "first-surname"; elsewhere "Name-Realm" gives "name-realm".
function F.Key(name)
    name = Text(name)
    if not name or #name > 100 then return nil end
    local one, two = name:match("^([^%- ]+)[%- ]([^%- ]+)")
    -- ASCII only: accented letters stay as they are, whatever the C library thinks of them.
    return ((one and one .. "-" .. two or name):gsub("[A-Z]", string.lower))
end

-- "First Surname" for the eye.
function F.Display(name)
    name = Text(name)
    if not name then return nil end
    local one, two = name:match("^([^%- ]+)[%- ]([^%- ]+)")
    return one and one .. " " .. two or name
end

-- A whisper takes "First-Surname".
function F.Address(name)
    name = Text(name)
    if not name or name:find("[%c\t]") then return nil end
    return (name:gsub("^([^%- ]+) ([^%- ]+)$", "%1-%2"))
end

function F:MyKey()
    if not self.myKey then
        local identity = MS.JourneyCharacterIdentity and MS.JourneyCharacterIdentity:Resolve()
        self.myKey = identity and F.Key(identity.fullName)
    end
    return self.myKey
end

function F:Changed() self.version = self.version + 1 end

-- Messages ---------------------------------------------------------------------------------------

function F.Encode(mapID, x, y, class, level)
    return string.format("L1\t%d\t%.4f\t%.4f\t%s\t%d", mapID, x, y, type(class) == "string" and class or "",
        tonumber(level) or 0)
end

-- { kind = "L1", mapID, x, y, class, level } | { kind = "L0" | "H1" | "H2" } | nil
function F.Decode(text)
    if type(text) ~= "string" or #text > 255 then return nil end
    local kind = text:sub(1, 2)
    if (kind == "L0" or kind == "H1" or kind == "H2") and (#text == 2 or text:sub(3, 3) == "\t") then
        return { kind = kind }
    end
    if kind ~= "L1" then return nil end
    local mapID, x, y, class, level = text:match("^L1\t(%d+)\t([%d%.]+)\t([%d%.]+)\t(%u*)\t?(%d*)")
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not mapID or mapID <= 0 or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return { kind = "L1", mapID = mapID, x = x, y = y, class = class ~= "" and class or nil, level = tonumber(level) }
end

-- { kind = "P", mapID, x, y, class, level } | { kind = "I" | "X" } | nil
function F.DecodeOneForAll(text)
    if type(text) ~= "string" or #text > 255 then return nil end
    local kind = text:sub(1, 1)
    if kind == "X" and #text == 1 then return { kind = "X" } end
    if kind == "I" and text:find("^I\t[%w_]+\t") then return { kind = "I" } end
    if kind ~= "P" then return nil end
    local mapID, x, y, class, level = text:match("^P\t(%d+)\t(%d+)\t(%d+)\t(%u*)\t(%d+)")
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not mapID or mapID <= 0 or not x or not y or x > 10000 or y > 10000 then return nil end
    return { kind = "P", mapID = mapID, x = x / 10000, y = y / 10000, class = class ~= "" and class or nil, level = tonumber(level) }
end

-- A guildmate's place from OneForAll; it stands beside the open format, the freshest wins.
function F:HearOneForAll(text, channel, sender)
    text, channel, sender = Readable(text), Readable(channel), Readable(sender)
    if channel ~= "GUILD" then return end
    local message, key = F.DecodeOneForAll(text), F.Key(sender)
    if not message or not key or key == self:MyKey() then return end
    local member = self.live[key]
    if message.kind == "P" then
        self.live[key] = { kind = "L1", mapID = message.mapID, x = message.x, y = message.y, class = message.class,
            level = message.level, name = F.Display(sender), at = Now(), guild = true, source = "OFA" }
        self:Changed()
    elseif member and member.source == "OFA" then
        self.live[key] = nil
        self:Changed()
    end
end

function F:Hear(text, channel, sender)
    text, channel, sender = Readable(text), Readable(channel), Readable(sender)
    if channel ~= "GUILD" and channel ~= "WHISPER" and channel ~= "BN" then return end
    local message, key = F.Decode(text), F.Key(sender)
    if not message or not key or key == self:MyKey() then return end
    if channel ~= "GUILD" then self.known[key] = true end
    if message.kind == "H1" then
        self:Send("H2", channel, sender)
        if self.sharing and self.last.text then self:Send(self.last.text, channel, sender) end
    elseif message.kind == "L0" then
        if self.live[key] and self.live[key].source ~= "OFA" then self.live[key] = nil; self:Changed() end
    elseif message.kind == "L1" then
        message.name, message.at, message.guild = F.Display(sender), Now(), channel == "GUILD"
        self.live[key] = message
        self:Changed()
    end
end

-- Sending: one message every `gap` seconds; a newer place for the same audience replaces the one waiting.
function F:Send(text, channel, target)
    for _, waiting in ipairs(self.queue) do
        if waiting.channel == channel and waiting.target == target and waiting.text:sub(1, 1) == "L" and text:sub(1, 1) == "L" then
            waiting.text = text
            return
        end
    end
    self.queue[#self.queue + 1] = { text = text, channel = channel, target = target }
    self:Pump()
end

function F:Pump()
    if self.pumping or #self.queue == 0 then return end
    local item = table.remove(self.queue, 1)
    if item.channel == "BN" then
        local bn = _G.BNSendGameData or (_G.C_BattleNet and _G.C_BattleNet.SendGameData)
        Call(bn, item.target, self.prefix, item.text)
    else
        local chat = _G.C_ChatInfo
        if type(chat) == "table" then Call(chat.SendAddonMessage, self.prefix, item.text, item.channel, item.target) end
    end
    if #self.queue > 0 and _G.C_Timer and _G.C_Timer.After then
        self.pumping = true
        _G.C_Timer.After(self.gap, function() self.pumping = false; self:Pump() end)
    end
end

-- Where the player stands, unless inside an instance: mapID, x, y.
function F:Here()
    local inside = Call(_G.IsInInstance)
    if inside and inside[1] ~= false then return nil end
    local map = _G.C_Map
    if type(map) ~= "table" then return nil end
    local mapID = First(map.GetBestMapForUnit, "player")
    if type(mapID) ~= "number" then return nil end
    local spot = First(map.GetPlayerMapPosition, mapID, "player")
    if type(spot) ~= "table" then return nil end
    local x, y
    if type(spot.GetXY) == "function" then
        local xy = Call(spot.GetXY, spot)
        x, y = xy and xy[1], xy and xy[2]
    else
        x, y = Readable(spot.x), Readable(spot.y)
    end
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

function F:Broadcast(text)
    if First(_G.IsInGuild) then self:Send(text, "GUILD") end
    for key in pairs(self.known) do
        local friend = self.friends[key]
        if friend and friend.bn then self:Send(text, "BN", friend.bn)
        elseif friend and friend.whisper then self:Send(text, "WHISPER", friend.whisper) end
    end
end

-- Every `tick` seconds: the place goes out when it changed (at most every `sendEvery` seconds),
-- else every `stillEvery` seconds; "L0" once when sharing stops or the player goes inside.
function F:Tick()
    local t = Now()
    for key, member in pairs(self.live) do
        if t - member.at > self.goneAfter then self.live[key] = nil; self:Changed() end
    end
    local mapID, x, y
    if self:Sharing() then
        self:Roster() -- friends newly online get their hello
        mapID, x, y = self:Here()
    end
    if not mapID then
        if self.sharing then
            self.sharing, self.last = false, { at = -math.huge }
            self:Broadcast("L0")
        end
        return
    end
    local last = self.last
    local moved = last.mapID ~= mapID or math.abs(x - last.x) + math.abs(y - last.y) > self.moved
    if t - last.at < (moved and self.sendEvery or self.stillEvery) then return end
    local class = Call(_G.UnitClass, "player")
    local text = F.Encode(mapID, x, y, class and class[2], First(_G.UnitLevel, "player"))
    self.last = { at = t, mapID = mapID, x = x, y = y, text = text }
    self.sharing = true
    self:Broadcast(text)
end

-- The game's lists ----------------------------------------------------------------------------

local function ClassFile(localized)
    if type(localized) ~= "string" then return nil end
    for _, list in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
        for file, name in pairs(type(list) == "table" and list or {}) do
            if name == localized then return file end
        end
    end
end

-- Who of the group the game already draws, by key.
function F:Group()
    local group = {}
    local raid = First(_G.IsInRaid)
    local count = tonumber(First(_G.GetNumGroupMembers)) or 0
    for index = 1, math.min(count, 40) do
        local name = Call(_G.UnitName, (raid and "raid" or "party") .. index)
        local key = name and F.Key(name[2] and name[1] and name[1] .. " " .. name[2] or name[1])
        if key then group[key] = true end
    end
    return group
end

-- Online guildmates and friends: [key] = { name, class, level, zone, guild, friend }. Also notes
-- how each friend is reached, for the hellos.
function F:Roster()
    local t = Now()
    if self.roster and t - self.rosterAt < self.rosterStale then return self.roster end
    local roster, friends = {}, {}
    local function Add(name, class, level, zone, how)
        local key = F.Key(name)
        if not key or key == self:MyKey() then return end
        local entry = roster[key] or { name = F.Display(name) }
        entry.class = entry.class or class
        entry.level = entry.level or tonumber(level)
        entry.zone = entry.zone or Text(zone)
        entry[how] = true
        roster[key] = entry
    end
    if First(_G.IsInGuild) then
        local count = tonumber(First(_G.GetNumGuildMembers)) or 0
        for index = 1, math.min(count, 1000) do
            local row = Call(_G.GetGuildRosterInfo, index)
            if row and row[9] == true then Add(row[1], row[11], row[4], row[6], "guild") end
        end
    end
    local list = _G.C_FriendList
    local count = type(list) == "table" and tonumber(First(list.GetNumFriends)) or 0
    for index = 1, math.min(count, 100) do
        local info = First(list.GetFriendInfoByIndex, index)
        if type(info) == "table" and Readable(info.connected) == true then
            local name = Readable(info.name)
            Add(name, ClassFile(Readable(info.className)), Readable(info.level), Readable(info.area), "friend")
            local key = F.Key(name)
            if key then friends[key] = { whisper = F.Address(name) } end
        end
    end
    local bnet = _G.C_BattleNet
    local total = tonumber(First(_G.BNGetNumFriends)) or 0
    local project = Readable(_G.WOW_PROJECT_ID)
    for index = 1, math.min(total, 200) do
        local account = type(bnet) == "table" and First(bnet.GetFriendAccountInfo, index)
        local game = type(account) == "table" and Readable(account.gameAccountInfo)
        if type(game) == "table" and Readable(game.isOnline) == true and Readable(game.clientProgram) == "WoW"
            and (project == nil or Readable(game.wowProjectID) == project) then
            local name = Readable(game.characterName)
            Add(name, ClassFile(Readable(game.className)), Readable(game.characterLevel), Readable(game.areaName), "friend")
            local key = F.Key(name)
            local id = Readable(game.gameAccountID)
            if key and not friends[key] and type(id) == "number" then friends[key] = { bn = id } end
        end
    end
    -- A friend newly online gets one hello; one who left is forgotten.
    for key, friend in pairs(friends) do
        if not self.friends[key] then
            if friend.bn then self:Send("H1", "BN", friend.bn) elseif friend.whisper then self:Send("H1", "WHISPER", friend.whisper) end
        end
    end
    for key in pairs(self.known) do
        if not friends[key] and not (roster[key] and roster[key].guild) then self.known[key] = nil end
    end
    self.friends, self.roster, self.rosterAt = friends, roster, t
    return roster
end

-- Asked while the map is on screen: the game sends the guild list only when asked.
function F:AskGuild()
    local t = Now()
    if self.askedAt and t - self.askedAt < self.rosterEvery then return end
    self.askedAt = t
    if not First(_G.IsInGuild) then return end
    local guild = _G.C_GuildInfo
    if type(guild) == "table" and type(guild.GuildRoster) == "function" then Call(guild.GuildRoster)
    else Call(_G.GuildRoster) end
end

-- Placing ------------------------------------------------------------------------------------------

-- The point of one map on another (a zone on its continent), or nil.
function F.Place(fromMap, x, y, toMap)
    if fromMap == toMap then return x, y end
    local map, vector = _G.C_Map, _G.CreateVector2D
    if type(map) ~= "table" or type(vector) ~= "function" then return nil end
    local point = First(vector, x, y)
    local where = point and Call(map.GetWorldPosFromMapPos, fromMap, point)
    if not where or type(where[1]) ~= "number" or type(where[2]) ~= "table" then return nil end
    local there = Call(map.GetMapPosFromWorldPos, where[1], where[2], toMap)
    local spot = there and there[2]
    if type(spot) ~= "table" or there[1] ~= toMap then return nil end
    local px, py
    if type(spot.GetXY) == "function" then
        local xy = Call(spot.GetXY, spot)
        px, py = xy and xy[1], xy and xy[2]
    else
        px, py = Readable(spot.x), Readable(spot.y)
    end
    if type(px) ~= "number" or type(py) ~= "number" or px < 0 or px > 1 or py < 0 or py > 1 then return nil end
    return px, py
end

-- A zone's name as the lists give it, to its map, from the world's map tree (once).
function F:ZoneMap(name)
    if not self.zones then
        self.zones = {}
        local map = _G.C_Map
        for _, top in ipairs({ 947, 1414, 1415, 1945 }) do
            local children = type(map) == "table" and First(map.GetMapChildrenInfo, top, nil, true)
            for _, child in ipairs(type(children) == "table" and children or {}) do
                local id, label = Readable(child.mapID), Readable(child.name)
                if type(id) == "number" and type(label) == "string" and not self.zones[label] then self.zones[label] = id end
            end
        end
    end
    return name and self.zones[name]
end

-- Centre of a zone on the shown map, from its rectangle there.
function F.Centre(zoneID, mapID)
    local map = _G.C_Map
    if type(map) ~= "table" then return nil end
    local rect = Call(map.GetMapRectOnMap, zoneID, mapID)
    local left, right, top, bottom = rect and rect[1], rect and rect[2], rect and rect[3], rect and rect[4]
    if type(left) ~= "number" or type(right) ~= "number" or type(top) ~= "number" or type(bottom) ~= "number" then return nil end
    if right <= left or bottom <= top or right - left > .9 then return nil end
    return (left + right) / 2, (top + bottom) / 2
end

local function Color(class)
    local colors = _G.RAID_CLASS_COLORS
    local color = type(colors) == "table" and class and colors[class]
    if type(color) == "table" and type(color.r) == "number" then return { color.r, color.g, color.b } end
    return { .85, .85, .85 }
end

local function Who(entry)
    local L = MS.L
    local parts = {}
    if entry.level and entry.level > 0 then parts[#parts + 1] = string.format(L.JOURNEY_FELLOWS_LEVEL, entry.level) end
    local classes = _G.LOCALIZED_CLASS_NAMES_MALE
    if entry.class and type(classes) == "table" and classes[entry.class] then parts[#parts + 1] = classes[entry.class] end
    if entry.guild then parts[#parts + 1] = L.JOURNEY_FELLOWS_GUILD end
    if entry.friend then parts[#parts + 1] = L.JOURNEY_FELLOWS_FRIEND end
    return table.concat(parts, " · ")
end

-- The marks for the shown map: { kind = "FELLOW" | "FELLOWS", x, y, color?, count?, lines }.
function F:Marks(mapID)
    if not self:Showing() or type(mapID) ~= "number" then return {} end
    local L = MS.L
    local roster, group, marks = self:Roster(), self:Group(), {}
    local placed = {}
    for key, member in pairs(self.live) do
        if not group[key] then
            local x, y = F.Place(member.mapID, member.x, member.y, mapID)
            local entry = roster[key] or { name = member.name, guild = member.guild }
            entry.level = member.level or entry.level
            entry.class = member.class or entry.class
            placed[key] = true
            if x then
                marks[#marks + 1] = { kind = "FELLOW", x = x, y = y, color = Color(entry.class),
                    lines = { entry.name or member.name, Who(entry) } }
            end
        end
    end
    -- The others, by zone: on the zone's own map in a corner, on a bigger map on the zone.
    local zones = {}
    for key, entry in pairs(roster) do
        local zoneID = not placed[key] and not group[key] and self:ZoneMap(entry.zone)
        if zoneID then
            zones[zoneID] = zones[zoneID] or { name = entry.zone }
            table.insert(zones[zoneID], entry)
        end
    end
    for zoneID, people in pairs(zones) do
        local x, y
        if zoneID == mapID then x, y = .05, .07 else x, y = F.Centre(zoneID, mapID) end
        if x then
            table.sort(people, function(a, b) return (a.name or "") < (b.name or "") end)
            local lines = { people.name }
            for index = 1, math.min(#people, self.listMax) do
                local entry = people[index]
                lines[#lines + 1] = entry.level and string.format(L.JOURNEY_FELLOWS_NAME_LEVEL, entry.name, entry.level) or entry.name
            end
            if #people > self.listMax then lines[#lines + 1] = string.format(L.JOURNEY_FELLOWS_MORE, #people - self.listMax) end
            marks[#marks + 1] = { kind = "FELLOWS", x = x, y = y, count = #people, lines = lines, plain = true }
        end
    end
    return marks
end

-- The question, once ---------------------------------------------------------------------------
-- The first time the map opens with someone to share with, a card asks whether to share. Either
-- answer is final; the Settings switch stays the way to change one's mind. Not asked on stream.

function F:ShouldOffer()
    if Setting("mapShareAsked") == true or self:Sharing() or (MS.BroadcastMode and MS.BroadcastMode:IsOn()) then return false end
    return First(_G.IsInGuild) == true or next(self:Roster()) ~= nil
end

function F:Answer(share)
    local settings = MS.JourneySettings
    if not settings then return end
    if share then settings:Set("mapShareWhere", true) end
    settings:Set("mapShareAsked", true)
    if self.card then self.card:Hide() end
end

function F:BuildCard(canvas)
    local L = MS.L
    local card = _G.CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    card:SetPoint("BOTTOM", canvas, "BOTTOM", 0, 34)
    card:SetSize(460, 78)
    card:SetFrameLevel(canvas:GetFrameLevel() + 210)
    if card.SetBackdrop then
        card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        card:SetBackdropColor(0, 0, 0, .85)
        card:SetBackdropBorderColor(1, .82, 0, .6)
    end
    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", 12, -9)
    card.title:SetPoint("TOPRIGHT", -12, -9)
    card.title:SetJustifyH("LEFT")
    card.title:SetText(L.JOURNEY_FELLOWS_ASK_TITLE)
    card.text = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
    card.text:SetPoint("TOPRIGHT", card.title, "BOTTOMRIGHT", 0, -4)
    card.text:SetJustifyH("LEFT")
    card.text:SetText(L.JOURNEY_FELLOWS_ASK_TEXT)
    card.later = _G.CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    card.later:SetSize(130, 22)
    card.later:SetPoint("BOTTOMRIGHT", -10, 8)
    card.later:SetText(L.JOURNEY_FELLOWS_ASK_LATER)
    card.later:SetScript("OnClick", function() F:Answer(false) end)
    card.share = _G.CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    card.share:SetSize(130, 22)
    card.share:SetPoint("RIGHT", card.later, "LEFT", -8, 0)
    card.share:SetText(L.JOURNEY_FELLOWS_ASK_SHARE)
    card.share:SetScript("OnClick", function() F:Answer(true) end)
    self.card = card
    return card
end

-- Called each time the Journey map is shown or redrawn.
function F:Offer(canvas)
    local wanted = canvas ~= nil and canvas:IsShown() and self:ShouldOffer()
    if wanted and not self.card then self:BuildCard(canvas) end
    if self.card then self.card:SetShown(wanted) end
    return wanted
end

-- Wiring -----------------------------------------------------------------------------------------

function F:OnEvent(event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = ...
        prefix = Readable(prefix)
        if prefix == self.prefix then self:Hear(text, channel, sender)
        elseif prefix == self.oneForAll then self:HearOneForAll(text, channel, sender) end
    elseif event == "BN_CHAT_MSG_ADDON" then
        local prefix, text, _, senderID = ...
        if Readable(prefix) ~= self.prefix then return end
        -- The sender is a game account: its character is the friend we know by that number.
        for key, friend in pairs(self.friends) do
            if friend.bn == Readable(senderID) then
                local entry = self.roster and self.roster[key]
                self:Hear(text, "BN", entry and entry.name or key)
                return
            end
        end
    else
        self.rosterAt = -math.huge
        self:Changed()
    end
end

function F:Start()
    if self.frame or type(_G.CreateFrame) ~= "function" then return end
    local chat = _G.C_ChatInfo
    if type(chat) == "table" then
        Call(chat.RegisterAddonMessagePrefix, self.prefix)
        Call(chat.RegisterAddonMessagePrefix, self.oneForAll)
    end
    local frame = _G.CreateFrame("Frame")
    for _, event in ipairs({ "CHAT_MSG_ADDON", "BN_CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE",
        "BN_FRIEND_INFO_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, ...) F:OnEvent(event, ...) end)
    self.frame = frame
    if _G.C_Timer and _G.C_Timer.NewTicker then
        self.ticker = _G.C_Timer.NewTicker(self.tick, function() F:Tick() end)
    end
    if MS.JourneySettings then
        MS.JourneySettings:Listen(function(key)
            if key == "mapShareWhere" then F:Tick() end
            if key == "mapIconFELLOW" or key == "broadcastMode" then F:Changed() end
        end)
    end
end
