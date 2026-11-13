local MS = _G.MS

-- Chat in Journey (Docs/journey/CHAT-JOURNEY-FICHE.md, CHAT-FILTRES-FICHE.md): receives the
-- game's chat messages, keeps the last ones and formats them with the game's own colours, links
-- and wording. Which tab shows a line is JourneyChatTabs' business. Journey never sends anything:
-- the player types in the game's edit box.
-- Lines keep the raw message; formatting happens at render time, so streamer mode and the time
-- setting apply to the whole history at once.
MS.JourneyChat = { lines = {}, limit = 500, listeners = {}, active = false, lockdown = false, nextId = 0,
    -- History kept across /reload (setting chatKeepHistory): per character, this many lines.
    keep = 200, keepDays = 30 }
local Chat = MS.JourneyChat

local OUTGOING = { WHISPER_INFORM = true, BN_WHISPER_INFORM = true }
local BATTLE_NET = { BN_WHISPER = true, BN_WHISPER_INFORM = true }
-- The game writes these as they are, without a speaker.
local PLAIN = { SYSTEM = true, TEXT_EMOTE = true, SKILL = true, LOOT = true, CURRENCY = true, MONEY = true,
    OPENING = true, TRADESKILLS = true, PET_INFO = true, COMBAT_MISC_INFO = true, COMBAT_XP_GAIN = true,
    COMBAT_HONOR_GAIN = true, COMBAT_FACTION_CHANGE = true, RESTRICTED = true, FILTERED = true,
    TARGETICONS = true, BG_SYSTEM_HORDE = true, BG_SYSTEM_ALLIANCE = true, BG_SYSTEM_NEUTRAL = true, PING = true }
-- The speaker's name goes inside the text (%s).
local NAME_IN_TEXT = { ACHIEVEMENT = true, GUILD_ACHIEVEMENT = true, MONSTER_EMOTE = true, RAID_BOSS_EMOTE = true,
    RAID_BOSS_WHISPER = true }

local function Tabs() return MS.JourneyChatTabs end

local function Readable(value)
    if value == nil then return true end
    local can = _G.canaccessvalue
    if type(can) == "function" then
        local ok, result = pcall(can, value)
        if not ok or not result then return false end
    end
    return true
end

local function Locked()
    local info = _G.C_ChatInfo
    if type(info) ~= "table" or type(info.InChatMessagingLockdown) ~= "function" then return false end
    local ok, locked = pcall(info.InChatMessagingLockdown)
    return ok and locked == true
end

-- Blizzard's own filter pass when the client has one (ChatFrameUtil on Forever, measured
-- 2026-11-10): it runs every addon's filter exactly as for the game's chat. Returns handled,
-- discard, args (nil args: unchanged).
local function Process(event, ...)
    local util = _G.ChatFrameUtil
    local process = type(util) == "table" and util.ProcessMessageEventFilters
    if type(process) ~= "function" then return false end
    local results = { pcall(process, _G.DEFAULT_CHAT_FRAME, event, ...) }
    if not results[1] then return false end
    if results[2] == true then return true, true end
    -- New arguments only when they look like a message: an unknown return keeps the original.
    if type(results[3]) == "string" then return true, false, { unpack(results, 3, select("#", ...) + 2) } end
    return true, false
end

-- Otherwise the filter list: ChatFrameUtil, or the old global on other clients.
local function FilterSource()
    local util = _G.ChatFrameUtil
    if type(util) == "table" and type(util.GetMessageEventFilters) == "function" then
        return function(event) return util.GetMessageEventFilters(event) end
    end
    local get = _G.ChatFrame_GetMessageEventFilters
    if type(get) == "function" then return get end
end

-- Other addons' anti-spam filters apply here too.
local function Filtered(event, ...)
    local handled, discard, changed = Process(event, ...)
    if handled then
        if discard then return true end
        if changed then return false, unpack(changed, 1, select("#", ...)) end
        return false, ...
    end
    local get = FilterSource()
    if not get then return false, ... end
    local ok, filters = pcall(get, event)
    if not ok or type(filters) ~= "table" then return false, ... end
    -- A registry may keep them by key rather than as a list.
    if #filters == 0 then
        local list = {}
        for _, filter in pairs(filters) do if type(filter) == "function" then list[#list + 1] = filter end end
        filters = list
    end
    local args = { ... }
    local count = select("#", ...)
    for _, filter in ipairs(filters) do
        local results = { pcall(filter, _G.DEFAULT_CHAT_FRAME, event, unpack(args, 1, count)) }
        if results[1] then
            if results[2] then return true end
            if results[3] ~= nil then
                args = { unpack(results, 3, count + 2) }
            end
        end
    end
    return false, unpack(args, 1, count)
end

function Chat:Listen(callback)
    if type(callback) == "function" then self.listeners[#self.listeners + 1] = callback end
end

function Chat:Notify(what, line)
    for _, callback in ipairs(self.listeners) do pcall(callback, what, line) end
end

function Chat:Add(line)
    local lines = self.lines
    self.nextId = self.nextId + 1
    line.id = self.nextId
    lines[#lines + 1] = line
    while #lines > self.limit do table.remove(lines, 1) end
    self:Notify("LINE", line)
end

function Chat:Clear()
    self.lines = {}
    self:Notify("RESET")
end

function Chat:Find(id)
    for index = #self.lines, 1, -1 do
        if self.lines[index].id == id then return self.lines[index] end
    end
end

-- One CHAT_MSG_* event. Returns the stored line, or nil and why.
function Chat:Receive(event, ...)
    local chatType = type(event) == "string" and event:match("^CHAT_MSG_(.+)$")
    if not chatType or (chatType ~= "CHANNEL" and not Tabs():TypeGroups()[chatType]) then return nil, "IGNORED" end
    -- During a boss the game hides chat from addons: say so once, keep nothing.
    local text, sender = ...
    if Locked() or not Readable(text) or not Readable(sender) then
        if not self.lockdown then
            self.lockdown = true
            self:Notify("LOCKDOWN", true)
        end
        return nil, "LOCKDOWN"
    end
    if self.lockdown then
        self.lockdown = false
        self:Notify("LOCKDOWN", false)
    end
    local args = { Filtered(event, ...) }
    if args[1] then return nil, "FILTERED" end
    local language, channelName, flags, channelIndex, channelBase, lineID, guid, bnSenderID
    text, sender, language, channelName, flags = args[2], args[3], args[4], args[5], args[7]
    channelIndex, channelBase, lineID, guid, bnSenderID = args[9], args[10], args[12], args[13], args[14]
    if type(text) ~= "string" then return nil, "EMPTY" end
    local line = {
        chatType = chatType, text = text,
        sender = type(sender) == "string" and sender or nil,
        language = type(language) == "string" and language ~= "" and language or nil,
        channelIndex = tonumber(channelIndex), channelBase = type(channelBase) == "string" and channelBase ~= "" and channelBase or nil,
        channelName = type(channelName) == "string" and channelName ~= "" and channelName or nil,
        flags = type(flags) == "string" and flags or nil,
        lineID = tonumber(lineID), guid = type(guid) == "string" and guid or nil, bnSenderID = tonumber(bnSenderID),
        time = type(_G.time) == "function" and _G.time() or 0,
    }
    line.whisper = Tabs():IsWhisper(line)
    self:Add(line)
    return line
end

-- Does this tab show this line? No tab: everything.
function Chat:Shows(tab, line)
    if tab == nil then return true end
    return Tabs():Shows(tab, line)
end

-- The lines of one tab, oldest first; with a search, only those whose text holds it.
function Chat:Lines(tab, query)
    local shown = {}
    local Copy = MS.JourneyChatCopy
    local needle = type(query) == "string" and query ~= "" and Copy and Copy:Fold(query) or nil
    for _, line in ipairs(self.lines) do
        if self:Shows(tab, line) and (not needle or (not line.separator
            and Copy:Fold(Copy:Plain(self:Format(line))):find(needle, 1, true))) then
            shown[#shown + 1] = line
        end
    end
    return shown
end

-- The colour the player set for this kind of message in the game.
function Chat:Color(line)
    if line.separator then return .55, .5, .42 end
    local key = line.chatType == "CHANNEL" and line.channelIndex and ("CHANNEL" .. line.channelIndex) or line.chatType
    local info = type(_G.ChatTypeInfo) == "table" and (_G.ChatTypeInfo[key] or _G.ChatTypeInfo[line.chatType])
    if type(info) == "table" and type(info.r) == "number" then return info.r, info.g, info.b end
    return 1, 1, 1
end

local function ClassColored(name, guid)
    if not guid or type(_G.GetPlayerInfoByGUID) ~= "function" then return name end
    local ok, _, class = pcall(_G.GetPlayerInfoByGUID, guid)
    if not ok or type(class) ~= "string" then return name end
    local color
    if type(_G.C_ClassColor) == "table" and type(_G.C_ClassColor.GetClassColor) == "function" then
        local found, value = pcall(_G.C_ClassColor.GetClassColor, class)
        color = found and value or nil
    end
    if color and type(color.WrapTextInColorCode) == "function" then return color:WrapTextInColorCode(name) end
    local raid = type(_G.RAID_CLASS_COLORS) == "table" and _G.RAID_CLASS_COLORS[class]
    if raid and type(raid.colorStr) == "string" then return "|c" .. raid.colorStr .. name .. "|r" end
    return name
end

local function Short(name)
    if type(_G.Ambiguate) == "function" then
        local ok, short = pcall(_G.Ambiguate, name, "none")
        if ok and type(short) == "string" then return short end
    end
    return name
end

local function Creature(chatType)
    return chatType:find("^MONSTER_") ~= nil or chatType:find("^RAID_BOSS_") ~= nil
end

-- The clickable name: the game's own link, so a click opens its usual menu. Creatures have no
-- menu: their name stays plain.
function Chat:SenderLink(line)
    local name = line.sender
    if not name or name == "" then return "" end
    if Creature(line.chatType) then return name end
    if BATTLE_NET[line.chatType] then
        return string.format("|HBNplayer:%s:%s:%s:%s:%s|h[%s]|h", name, tostring(line.bnSenderID or 0),
            tostring(line.lineID or 0), line.chatType, name, name)
    end
    return string.format("|Hplayer:%s:%s|h[%s]|h", name, tostring(line.lineID or 0), ClassColored(Short(name), line.guid))
end

local function Wording(chatType)
    local wording = _G["CHAT_" .. chatType .. "_GET"]
    return type(wording) == "string" and wording or nil
end

-- string.format that never breaks a line: a text with a stray % stays as it was.
local function Fill(pattern, ...)
    local ok, result = pcall(string.format, pattern, ...)
    return ok and result or nil
end

-- The message as the game's chat would write it, without the time.
function Chat:Body(line)
    local L = MS.L
    if line.separator then return L.CHAT_HISTORY_BEFORE end
    local mode = MS.BroadcastMode
    -- Streamer mode: a whisper shows neither who nor what.
    if line.whisper and mode and mode:IsOn() then
        return OUTGOING[line.chatType] and L.CHAT_WHISPER_HIDDEN_OUT or L.CHAT_WHISPER_HIDDEN_IN
    end
    local chatType, text = line.chatType, line.text
    if line.language and type(_G.GetDefaultLanguage) == "function" then
        local ok, default = pcall(_G.GetDefaultLanguage)
        if not ok or line.language ~= default then text = "[" .. line.language .. "] " .. text end
    end
    if PLAIN[chatType] then return text end
    if chatType == "CHANNEL_NOTICE" or chatType == "CHANNEL_NOTICE_USER" then
        -- text is a notice word (YOU_JOINED...); the game has a sentence for each.
        local sentence = _G["CHAT_" .. text .. "_NOTICE"]
        local filled = type(sentence) == "string" and Fill(sentence, line.channelIndex or 0, line.channelBase or line.channelName or "", line.sender or "")
        return filled or text
    end
    if chatType == "BN_INLINE_TOAST_ALERT" then
        local sentence = _G["BN_INLINE_TOAST_" .. text]
        return type(sentence) == "string" and Fill(sentence, line.sender or "") or text
    end
    if chatType == "IGNORED" and type(_G.CHAT_IGNORED) == "string" then
        return Fill(_G.CHAT_IGNORED, line.sender or "") or text
    end
    local who = self:SenderLink(line)
    if NAME_IN_TEXT[chatType] and text:find("%s", 1, true) then
        local filled = Fill(text, who)
        if filled then return filled end
    end
    if chatType == "CHANNEL" then
        local channel = line.channelIndex and line.channelBase
            and string.format("|Hchannel:channel:%d|h[%d. %s]|h ", line.channelIndex, line.channelIndex, line.channelBase) or ""
        return channel .. who .. ": " .. text
    end
    local wording = Wording(chatType)
    if wording then return (Fill(wording, who) or who .. ": ") .. text end
    if who ~= "" then return who .. ": " .. text end
    return text
end

local function Time(line)
    local settings = MS.JourneySettings
    if settings and settings:Get("chatShowTime") == true and type(_G.date) == "function" then
        return _G.date("%H:%M", line.time)
    end
end

-- The line as text, with the time if the player wants it (for copying and searching too).
function Chat:Format(line)
    local body = self:Body(line)
    local time = not line.separator and Time(line)
    if time then return time .. " " .. body end
    return body
end

-- The line as the panel draws it: the time (or a dot) copies the line, addresses are links.
local MARK = "|cff8a7a5c%s|r"

function Chat:Display(line)
    local Copy = MS.JourneyChatCopy
    if line.separator or not Copy then return self:Format(line) end
    local body = Copy:Decorate(self:Body(line))
    local mark = Copy:LineLink(line.id or 0, string.format(MARK, Time(line) or "•"))
    return mark .. " " .. body
end

-- The last line of a tab, for the collapsed panel.
function Chat:Latest(tab)
    for index = #self.lines, 1, -1 do
        local line = self.lines[index]
        if not line.separator and self:Shows(tab, line) then return line end
    end
end

-- Plain text of the last lines of a tab (or of a search), for the copy box.
function Chat:CopyText(tab, query, count)
    local Copy = MS.JourneyChatCopy
    local lines = self:Lines(tab, query)
    local first = math.max(1, #lines - (count or Copy.tabLines) + 1)
    local out = {}
    for index = first, #lines do out[#out + 1] = Copy:Plain(self:Format(lines[index])) end
    return table.concat(out, "\n")
end

function Chat:Start()
    if self.active then return end
    self.active = true
    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:SetScript("OnEvent", function(_, event, ...) Chat:Receive(event, ...) end)
    end
    self:Restore()
    for _, chatType in ipairs(Tabs():ChatTypes()) do
        pcall(self.eventFrame.RegisterEvent, self.eventFrame, "CHAT_MSG_" .. chatType)
    end
end

function Chat:Stop()
    self.active = false
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
end

-- History kept across /reload -----------------------------------------------------------------

local SAVED_FIELDS = { "chatType", "text", "sender", "language", "channelIndex", "channelBase", "channelName",
    "flags", "lineID", "guid", "bnSenderID", "time" }

local function Keeping()
    local settings = MS.JourneySettings
    return settings ~= nil and settings:Get("chatKeepHistory") == true
end

local function Character()
    if type(_G.UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(_G.UnitGUID, "player")
    return ok and Readable(guid) and type(guid) == "string" and guid or nil
end

local function HistoryStore(create)
    local db = MS.Database and MS.Database.Get and MS.Database:Get()
    if type(db) ~= "table" then return nil end
    db.journey = type(db.journey) == "table" and db.journey or {}
    local store = db.journey.chatHistory
    if type(store) ~= "table" or type(store.characters) ~= "table" then
        if not create then return nil end
        store = { version = 1, characters = {} }
        db.journey.chatHistory = store
    end
    return store
end

-- Puts this character's saved lines back, once per session, before anything new.
function Chat:Restore()
    if self.restored then return end
    self.restored = true
    if not Keeping() then return end
    local store, guid = HistoryStore(false), Character()
    local saved = store and guid and store.characters[guid]
    if type(saved) ~= "table" or type(saved.lines) ~= "table" or #saved.lines == 0 then return end
    local restored = {}
    for _, fields in ipairs(saved.lines) do
        if type(fields) == "table" and type(fields.chatType) == "string" and type(fields.text) == "string" then
            local line = {}
            for _, key in ipairs(SAVED_FIELDS) do line[key] = fields[key] end
            self.nextId = self.nextId + 1
            line.id = self.nextId
            line.whisper = Tabs():IsWhisper(line)
            restored[#restored + 1] = line
        end
    end
    if #restored == 0 then return end
    self.nextId = self.nextId + 1
    restored[#restored + 1] = { separator = true, id = self.nextId, chatType = "SEPARATOR", time = 0 }
    for _, line in ipairs(self.lines) do restored[#restored + 1] = line end
    while #restored > self.limit do table.remove(restored, 1) end
    self.lines = restored
    self:Notify("RESET")
end

-- Writes this character's last lines into the saved data (at logout and /reload).
function Chat:Save()
    if not Keeping() then return false end
    -- Never write over the saved lines with an empty session (the panel never opened).
    if not self.restored and #self.lines == 0 then return false end
    local guid = Character()
    local store = guid and HistoryStore(true)
    if not store then return false end
    local kept = {}
    local first = math.max(1, #self.lines - self.keep + 1)
    for index = first, #self.lines do
        local line = self.lines[index]
        if not line.separator then
            local fields, readable = {}, true
            for _, key in ipairs(SAVED_FIELDS) do
                if not Readable(line[key]) then readable = false end
                fields[key] = line[key]
            end
            if readable then kept[#kept + 1] = fields end
        end
    end
    local now = type(_G.time) == "function" and _G.time() or 0
    store.characters[guid] = { saved = now, lines = kept }
    -- Characters not played for a month are forgotten.
    for other, entry in pairs(store.characters) do
        if type(entry) ~= "table" or (now > 0 and type(entry.saved) == "number" and now - entry.saved > self.keepDays * 86400) then
            store.characters[other] = nil
        end
    end
    return true
end

-- Forgets every saved line, and empties the panel.
function Chat:ClearHistory()
    local db = MS.Database and MS.Database.Get and MS.Database:Get()
    if type(db) == "table" and type(db.journey) == "table" then db.journey.chatHistory = nil end
    self:Clear()
end

if MS.JourneySettings and MS.JourneySettings.Listen then
    MS.JourneySettings:Listen(function(key, value)
        -- Turning the setting off forgets what was saved; the panel keeps this session's lines.
        if key == "chatKeepHistory" and value ~= true then
            local db = MS.Database and MS.Database.Get and MS.Database:Get()
            if type(db) == "table" and type(db.journey) == "table" then db.journey.chatHistory = nil end
        end
    end)
end

if type(_G.CreateFrame) == "function" then
    local logout = CreateFrame("Frame")
    logout:SetScript("OnEvent", function() pcall(Chat.Save, Chat) end)
    pcall(logout.RegisterEvent, logout, "PLAYER_LOGOUT")
end

if MS.BroadcastMode then MS.BroadcastMode:Listen(function() Chat:Notify("REDRAW") end) end
