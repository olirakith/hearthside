local MS = _G.MS

-- The Discussion panel's tabs (Docs/journey/CHAT-FILTRES-FICHE.md). Each tab is a name, a set of
-- the game's message groups (SAY, LOOT, SKILL...) and a set of channels kept by name. Tabs are
-- shared by every character of the account; the first one is copied once from the game's main
-- chat window. Lines are sorted at render time, so changing a tab reshapes its whole history.
MS.JourneyChatTabs = { max = 8, nameLength = 24, listeners = {} }
local Tabs = MS.JourneyChatTabs

local VERSION = 1

-- The groups the editor shows, by section, with the game's own names. Groups the client knows
-- but that are not listed here go to OTHER.
Tabs.SECTIONS = {
    { key = "TALK", groups = { "SAY", "EMOTE", "YELL", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
        "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "WHISPER", "BN_WHISPER" } },
    { key = "CREATURES", groups = { "MONSTER_SAY", "MONSTER_EMOTE", "MONSTER_YELL", "MONSTER_WHISPER",
        "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER" } },
    { key = "REWARDS", groups = { "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "SKILL", "LOOT",
        "CURRENCY", "MONEY", "TRADESKILLS", "OPENING", "PET_INFO", "COMBAT_MISC_INFO" } },
    { key = "SYSTEM", groups = { "SYSTEM", "ERRORS", "IGNORED", "CHANNEL", "ACHIEVEMENT", "GUILD_ACHIEVEMENT",
        "BN_INLINE_TOAST_ALERT", "TARGETICONS", "BG_HORDE", "BG_ALLIANCE", "BG_NEUTRAL" } },
}

-- The game's events per group, used when the client has no ChatTypeGroup table.
local FALLBACK = {
    SAY = { "SAY" }, EMOTE = { "EMOTE", "TEXT_EMOTE" }, YELL = { "YELL" },
    PARTY = { "PARTY" }, PARTY_LEADER = { "PARTY_LEADER" }, RAID = { "RAID" }, RAID_LEADER = { "RAID_LEADER" },
    RAID_WARNING = { "RAID_WARNING" }, INSTANCE_CHAT = { "INSTANCE_CHAT" }, INSTANCE_CHAT_LEADER = { "INSTANCE_CHAT_LEADER" },
    GUILD = { "GUILD" }, OFFICER = { "OFFICER" },
    WHISPER = { "WHISPER", "WHISPER_INFORM", "AFK", "DND" }, BN_WHISPER = { "BN_WHISPER", "BN_WHISPER_INFORM" },
    MONSTER_SAY = { "MONSTER_SAY" }, MONSTER_EMOTE = { "MONSTER_EMOTE" }, MONSTER_YELL = { "MONSTER_YELL" },
    MONSTER_WHISPER = { "MONSTER_WHISPER" }, MONSTER_BOSS_EMOTE = { "RAID_BOSS_EMOTE" },
    MONSTER_BOSS_WHISPER = { "RAID_BOSS_WHISPER" },
    COMBAT_XP_GAIN = { "COMBAT_XP_GAIN" }, COMBAT_HONOR_GAIN = { "COMBAT_HONOR_GAIN" },
    COMBAT_FACTION_CHANGE = { "COMBAT_FACTION_CHANGE" }, SKILL = { "SKILL" }, LOOT = { "LOOT" },
    CURRENCY = { "CURRENCY" }, MONEY = { "MONEY" }, TRADESKILLS = { "TRADESKILLS" }, OPENING = { "OPENING" },
    PET_INFO = { "PET_INFO" }, COMBAT_MISC_INFO = { "COMBAT_MISC_INFO" },
    SYSTEM = { "SYSTEM" }, ERRORS = { "RESTRICTED", "FILTERED" }, IGNORED = { "IGNORED" },
    CHANNEL = { "CHANNEL_JOIN", "CHANNEL_LEAVE", "CHANNEL_NOTICE", "CHANNEL_NOTICE_USER", "CHANNEL_LIST" },
    ACHIEVEMENT = { "ACHIEVEMENT" }, GUILD_ACHIEVEMENT = { "GUILD_ACHIEVEMENT" },
    BN_INLINE_TOAST_ALERT = { "BN_INLINE_TOAST_ALERT" }, TARGETICONS = { "TARGETICONS" },
    BG_HORDE = { "BG_SYSTEM_HORDE" }, BG_ALLIANCE = { "BG_SYSTEM_ALLIANCE" }, BG_NEUTRAL = { "BG_SYSTEM_NEUTRAL" },
}

local WHISPER_GROUPS = { WHISPER = true, BN_WHISPER = true }

-- The default tabs; GENERAL is replaced by the game's main window when it can be read.
local DEFAULTS = {
    { key = "GENERAL", allChannels = true, groups = {
        "SAY", "EMOTE", "YELL", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT",
        "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "WHISPER", "BN_WHISPER",
        "MONSTER_SAY", "MONSTER_EMOTE", "MONSTER_YELL", "MONSTER_WHISPER", "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER",
        "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "SKILL", "LOOT", "CURRENCY", "MONEY",
        "TRADESKILLS", "OPENING", "PET_INFO", "COMBAT_MISC_INFO",
        "SYSTEM", "ERRORS", "IGNORED", "CHANNEL", "ACHIEVEMENT", "GUILD_ACHIEVEMENT", "BN_INLINE_TOAST_ALERT",
        "TARGETICONS", "BG_HORDE", "BG_ALLIANCE", "BG_NEUTRAL" } },
    { key = "GROUP", groups = { "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT",
        "INSTANCE_CHAT_LEADER" } },
    { key = "GUILD", groups = { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT" } },
    { key = "WHISPER", groups = { "WHISPER", "BN_WHISPER" } },
    { key = "CHANNEL", allChannels = true, groups = {} },
}

local function Copy(list)
    local copy = {}
    for index, value in ipairs(list or {}) do copy[index] = value end
    return copy
end

local function Lower(text)
    return type(text) == "string" and string.lower(text) or nil
end

-- Groups -> events (without CHAT_MSG_), from the game when it can say, else our own table.
function Tabs:GroupEvents()
    if self.groupEvents then return self.groupEvents end
    local result = {}
    local source = _G.ChatTypeGroup
    if type(source) == "table" then
        for group, events in pairs(source) do
            if type(group) == "string" and type(events) == "table" then
                local list = {}
                for _, event in pairs(events) do
                    local chatType = type(event) == "string" and event:match("^CHAT_MSG_(.+)$")
                    -- CHAT_MSG_CHANNEL is a channel's own talk: it follows the channel list.
                    if chatType and chatType ~= "CHANNEL" then list[#list + 1] = chatType end
                end
                if #list > 0 then table.sort(list); result[group] = list end
            end
        end
    end
    if next(result) == nil then
        for group, list in pairs(FALLBACK) do result[group] = Copy(list) end
    end
    self.groupEvents = result
    return result
end

-- Chat type -> the groups it belongs to.
function Tabs:TypeGroups()
    if self.typeGroups then return self.typeGroups end
    local result = {}
    for group, list in pairs(self:GroupEvents()) do
        for _, chatType in ipairs(list) do
            result[chatType] = result[chatType] or {}
            table.insert(result[chatType], group)
        end
    end
    self.typeGroups = result
    return result
end

-- Every chat type Journey listens to, CHANNEL included.
function Tabs:ChatTypes()
    local types = { "CHANNEL" }
    for chatType in pairs(self:TypeGroups()) do types[#types + 1] = chatType end
    table.sort(types)
    return types
end

-- Groups the client knows that no section lists.
function Tabs:OtherGroups()
    local listed = {}
    for _, section in ipairs(self.SECTIONS) do
        for _, group in ipairs(section.groups) do listed[group] = true end
    end
    local others = {}
    for group in pairs(self:GroupEvents()) do
        if not listed[group] then others[#others + 1] = group end
    end
    table.sort(others)
    return others
end

function Tabs:Known(group)
    return self:GroupEvents()[group] ~= nil
end

-- A group's name in the editor: ours, then the game's, then the raw name.
function Tabs:GroupLabel(group)
    local own = MS.L["CHAT_GROUP_" .. group]
    if type(own) == "string" and own ~= "" and own ~= "CHAT_GROUP_" .. group then return own end
    local game = _G[group]
    if type(game) == "string" and game ~= "" then return game end
    return (group:gsub("_", " "):lower():gsub("^%l", string.upper))
end

-- Storage --------------------------------------------------------------------------------

local function Store()
    local db = MS.Database and MS.Database.Get and MS.Database:Get()
    if type(db) ~= "table" then return nil end
    db.journey = type(db.journey) == "table" and db.journey or {}
    return db.journey
end

local function Clean(tab)
    if type(tab) ~= "table" then return nil end
    local clean = {
        key = type(tab.key) == "string" and tab.key or nil,
        name = type(tab.name) == "string" and tab.name ~= "" and tab.name:sub(1, Tabs.nameLength) or nil,
        allChannels = tab.allChannels == true,
        groups = {}, channels = {},
    }
    for _, group in ipairs(type(tab.groups) == "table" and tab.groups or {}) do
        if type(group) == "string" then clean.groups[#clean.groups + 1] = group end
    end
    for _, channel in ipairs(type(tab.channels) == "table" and tab.channels or {}) do
        if type(channel) == "string" and channel ~= "" then clean.channels[#clean.channels + 1] = channel end
    end
    return clean
end

function Tabs:Defaults()
    local list = {}
    for index, tab in ipairs(DEFAULTS) do list[index] = Clean(tab) end
    return list
end

-- The game's main chat window, as one tab: its groups and channels, or nil if unreadable.
function Tabs:FromGame()
    local frame = _G.ChatFrame1
    if type(frame) ~= "table" and type(frame) ~= "userdata" then return nil end
    local ok, types = pcall(function() return frame.messageTypeList end)
    if not ok or type(types) ~= "table" or #types == 0 then return nil end
    local tab = { groups = {}, channels = {} }
    for _, group in ipairs(types) do
        if type(group) == "string" then tab.groups[#tab.groups + 1] = group end
    end
    local found, channels = pcall(function() return frame.channelList end)
    if found and type(channels) == "table" then
        for _, channel in ipairs(channels) do
            if type(channel) == "string" and channel ~= "" then tab.channels[#tab.channels + 1] = channel end
        end
    end
    if #tab.groups == 0 then return nil end
    return tab
end

-- Loads the tabs, creating the defaults (and copying the game's window) the first time.
function Tabs:Load()
    local store = Store()
    if not store then
        self.list = self.list or self:Defaults()
        return self.list
    end
    local saved = store.chatTabs
    if type(saved) ~= "table" or type(saved.list) ~= "table" or #saved.list == 0 then
        saved = { version = VERSION, list = self:Defaults(), imported = false }
        store.chatTabs = saved
    end
    local list = {}
    for _, tab in ipairs(saved.list) do
        local clean = Clean(tab)
        if clean and #list < self.max then list[#list + 1] = clean end
    end
    if #list == 0 then list = self:Defaults() end
    saved.list, saved.version = list, VERSION
    self.saved, self.list = saved, list
    self:Index()
    return list
end

-- Copies the game's main window into the first tab, once (call before the game's chat hides).
function Tabs:ImportOnce()
    self:Load()
    if not self.saved or self.saved.imported == true then return false end
    local game = self:FromGame()
    if not game then return false end
    self.saved.imported = true
    local first = self.list[1]
    first.groups, first.channels, first.allChannels = game.groups, game.channels, false
    self:Changed()
    return true
end

function Tabs:List()
    -- Loaded again once the saved data exists (a call before the database would keep defaults).
    if not self.list or (not self.saved and Store()) then self:Load() end
    return self.list
end

function Tabs:Get(index)
    return self:List()[index]
end

function Tabs:Count() return #self:List() end

function Tabs:Name(tab)
    if type(tab) ~= "table" then return "" end
    if tab.name then return tab.name end
    if tab.key then return MS.L["CHAT_TAB_" .. tab.key] or tab.key end
    return MS.L.CHAT_TAB_NEW
end

-- Lookup sets, rebuilt after every change.
function Tabs:Index()
    for _, tab in ipairs(self.list or {}) do
        tab.groupSet, tab.channelSet = {}, {}
        for _, group in ipairs(tab.groups) do tab.groupSet[group] = true end
        for _, channel in ipairs(tab.channels) do tab.channelSet[Lower(channel)] = true end
    end
end

function Tabs:Listen(callback)
    if type(callback) == "function" then self.listeners[#self.listeners + 1] = callback end
end

function Tabs:Changed()
    self:Index()
    -- groupSet/channelSet are rebuilt at load: keep them out of the saved copy.
    if self.saved then
        local saved = {}
        for index, tab in ipairs(self.list) do saved[index] = Clean(tab) end
        self.saved.list = saved
        -- The live list keeps its lookup sets; the saved one is plain data.
        self.list = saved
        self:Index()
    end
    for _, callback in ipairs(self.listeners) do pcall(callback) end
end

-- Does this tab show this line?
function Tabs:Shows(tab, line)
    if type(tab) ~= "table" or type(line) ~= "table" then return true end
    if line.separator then return true end
    if not tab.groupSet then self:Index() end
    if line.chatType == "CHANNEL" then
        return tab.allChannels == true or (tab.channelSet and tab.channelSet[Lower(line.channelBase) or ""] == true)
    end
    for _, group in ipairs(self:TypeGroups()[line.chatType] or {}) do
        if tab.groupSet[group] then return true end
    end
    return false
end

-- Whispers land in this tab (for the unread mark).
function Tabs:ShowsWhispers(tab)
    if type(tab) ~= "table" then return false end
    for group in pairs(WHISPER_GROUPS) do
        for _, own in ipairs(tab.groups) do if own == group then return true end end
    end
    return false
end

function Tabs:IsWhisper(line)
    for _, group in ipairs(self:TypeGroups()[line and line.chatType] or {}) do
        if WHISPER_GROUPS[group] then return true end
    end
    return false
end

-- Editing ------------------------------------------------------------------------------

function Tabs:Add()
    local list = self:List()
    if #list >= self.max then return nil end
    list[#list + 1] = { groups = {}, channels = {}, allChannels = false }
    self:Changed()
    return #self.list
end

function Tabs:Remove(index)
    local list = self:List()
    if #list <= 1 or not list[index] then return false end
    table.remove(list, index)
    self:Changed()
    return true
end

function Tabs:Move(index, delta)
    local list = self:List()
    local target = index + delta
    if not list[index] or not list[target] then return index end
    list[index], list[target] = list[target], list[index]
    self:Changed()
    return target
end

function Tabs:Rename(index, name)
    local tab = self:Get(index)
    if not tab then return false end
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    -- No codes in a tab name: it is drawn as plain text.
    name = name:gsub("|", "")
    tab.name = name ~= "" and name:sub(1, self.nameLength) or nil
    if tab.name and tab.key and tab.name == (MS.L["CHAT_TAB_" .. tab.key] or "") then tab.name = nil end
    self:Changed()
    return true
end

local function Toggle(list, value, on)
    for index, own in ipairs(list) do
        if own == value then
            if not on then table.remove(list, index) end
            return
        end
    end
    if on then list[#list + 1] = value end
end

function Tabs:SetGroup(index, group, on)
    local tab = self:Get(index)
    if not tab or type(group) ~= "string" then return false end
    Toggle(tab.groups, group, on == true)
    self:Changed()
    return true
end

function Tabs:SetChannel(index, channel, on)
    local tab = self:Get(index)
    if not tab or type(channel) ~= "string" or channel == "" then return false end
    for position, own in ipairs(tab.channels) do
        if Lower(own) == Lower(channel) then
            if not on then table.remove(tab.channels, position) end
            self:Changed()
            return true
        end
    end
    if on then tab.channels[#tab.channels + 1] = channel end
    self:Changed()
    return true
end

function Tabs:SetAllChannels(index, on)
    local tab = self:Get(index)
    if not tab then return false end
    tab.allChannels = on == true
    self:Changed()
    return true
end

-- Copies the game's main window into one tab.
function Tabs:CopyGame(index)
    local tab, game = self:Get(index), self:FromGame()
    if not tab or not game then return false end
    tab.groups, tab.channels, tab.allChannels = game.groups, game.channels, false
    self:Changed()
    return true
end

function Tabs:Reset()
    self:List()
    self.list = self:Defaults()
    if self.saved then self.saved.imported = false end
    self:Changed()
    -- The first tab follows the game's window again when it can be read.
    local game = self:FromGame()
    if game then
        self.list[1].groups, self.list[1].channels, self.list[1].allChannels = game.groups, game.channels, false
        if self.saved then self.saved.imported = true end
        self:Changed()
    end
    return true
end

-- Channels worth offering in the editor: the game's window, the joined ones, the tab's own.
function Tabs:KnownChannels(index)
    local seen, list = {}, {}
    local function add(name)
        if type(name) ~= "string" or name == "" or seen[Lower(name)] then return end
        seen[Lower(name)] = true
        list[#list + 1] = name
    end
    local game = self:FromGame()
    for _, name in ipairs(game and game.channels or {}) do add(name) end
    if type(_G.GetChannelList) == "function" then
        local ok, values = pcall(function() return { _G.GetChannelList() } end)
        -- id, name, disabled, ...
        if ok then for position = 2, #values, 3 do add(values[position]) end end
    end
    local tab = self:Get(index)
    for _, name in ipairs(tab and tab.channels or {}) do add(name) end
    return list
end
