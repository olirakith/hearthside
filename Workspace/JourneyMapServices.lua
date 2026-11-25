local MS = _G.MS

-- Nearest useful NPCs (repair, flight master, inn, trainer, bank, auction house) and mailbox on a map, from QuestieDB when the
-- player has it. Pure data: no frame, no event, no visible string. The index is built once,
-- outside combat, on first use; the faction is applied at query time. Mailboxes are objects and
-- need a second, longer pass: it runs in small steps after the first one.
local S = { KINDS = { "REPAIR", "FLIGHT", "INN", "TRAINER", "BANK", "AUCTION" }, stats = {}, mailboxStep = 400, listeners = {} }
MS.JourneyMapServices = S

-- Kind -> name of the flag in lib.Enum.npcFlags.
local FLAG_NAMES = { REPAIR = "REPAIR", FLIGHT = "FLIGHT_MASTER", INN = "INNKEEPER", TRAINER = "TRAINER",
    BANK = "BANKER", AUCTION = "AUCTIONEER" }
local FACTION_LETTER = { Alliance = "A", Horde = "H" }

-- Bit test without 32-bit operations, as in JourneyQuestieOffers.
local function HasBit(mask, bit)
    if type(mask) ~= "number" or type(bit) ~= "number" or bit <= 0 then return false end
    return mask % (bit * 2) >= bit
end

local function Combat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() or false
end

local function Friendly(entry, faction)
    local letter = FACTION_LETTER[faction]
    if not letter or type(entry.friendly) ~= "string" then return true end
    return entry.friendly:find(letter, 1, true) ~= nil
end

-- Zone maps are three wide for two high: a gap in x weighs more than the same gap in y.
local function Gap(entry, x, y)
    local dx, dy = (entry.x - x) * 1.5, entry.y - y
    return dx * dx + dy * dy
end

function S:Flags(lib)
    local flags = lib.Enum and lib.Enum.npcFlags
    if type(flags) ~= "table" then return nil end
    local bits, any = {}, false
    for kind, name in pairs(FLAG_NAMES) do
        if type(flags[name]) == "number" then bits[kind] = flags[name]; any = true end
    end
    return any and bits or nil
end

function S:BuildIndex()
    if self.index then return self.index end
    if Combat() then return nil, "COMBAT" end
    local offers = MS.JourneyQuestieOffers
    local lib, reason = offers and offers:Library()
    if not lib then self.reason = reason or "ABSENT"; return nil, self.reason end
    local bits = self:Flags(lib)
    if not bits then self.reason = "FLAGS"; return nil, "FLAGS" end
    local areaToUi = offers:AreaToUiMap(lib)
    if not areaToUi then self.reason = "ZONES"; return nil, "ZONES" end
    local started = type(debugprofilestop) == "function" and debugprofilestop() or nil
    local Npc, index, count = lib.Npc, {}, 0
    local okIds, ids = pcall(Npc.GetAllIds)
    for _, npcID in ipairs(okIds and type(ids) == "table" and ids or {}) do
        local okFlags, mask = pcall(Npc.Get, npcID, "npcFlags")
        if okFlags and type(mask) == "number" and mask > 0 then
            local kinds = {}
            for _, kind in ipairs(self.KINDS) do
                if bits[kind] and HasBit(mask, bits[kind]) then kinds[#kinds + 1] = kind end
            end
            local okSpawns, spawns = pcall(Npc.Get, npcID, "spawns")
            if #kinds > 0 and okSpawns and type(spawns) == "table" then
                local okFriend, friendly = pcall(Npc.Get, npcID, "friendlyToFaction")
                friendly = okFriend and type(friendly) == "string" and friendly or nil
                local kept = false
                for areaID, points in pairs(spawns) do
                    local uiMapID = areaToUi[areaID]
                    if uiMapID and type(points) == "table" then
                        for _, point in ipairs(points) do
                            if type(point[1]) == "number" and type(point[2]) == "number" and point[1] >= 0 then
                                local list = index[uiMapID] or {}
                                index[uiMapID] = list
                                for _, kind in ipairs(kinds) do
                                    list[#list + 1] = { npcID = npcID, kind = kind, friendly = friendly,
                                        x = point[1] / 100, y = point[2] / 100 }
                                end
                                kept = true
                            end
                        end
                    end
                end
                if kept then count = count + 1 end
            end
        end
    end
    self.index, self.lib, self.reason, self.stats.npcs = index, lib, nil, count
    self.stats.buildMs = started and type(debugprofilestop) == "function" and (debugprofilestop() - started) or nil
    self:IndexMailboxes(index, areaToUi)
    return index
end

-- Mailboxes -------------------------------------------------------------------------------------
-- Their base name is English whatever the client's language; the faction comes from the object's
-- faction template when it is a city's (others are for everyone).
local MAILBOX, MAILBOX_FACTION = "Mailbox", {
    [12] = "A", [55] = "A", [57] = "A", [80] = "A", [84] = "A",
    [29] = "H", [68] = "H", [71] = "H", [83] = "H", [104] = "H", [105] = "H", [126] = "H",
}

function S:Listen(callback) self.listeners[#self.listeners + 1] = callback end

local function AddMailbox(index, areaToUi, Object, objectID)
    local ok, spawns = pcall(Object.Get, objectID, "spawns")
    if not ok or type(spawns) ~= "table" then return 0 end
    local okFaction, template = pcall(Object.Get, objectID, "factionID")
    local friendly = okFaction and MAILBOX_FACTION[template] or nil
    local count = 0
    for areaID, points in pairs(spawns) do
        local uiMapID = areaToUi[areaID]
        for _, point in ipairs(uiMapID and type(points) == "table" and points or {}) do
            if type(point[1]) == "number" and type(point[2]) == "number" and point[1] >= 0 then
                local list = index[uiMapID] or {}
                index[uiMapID] = list
                list[#list + 1] = { kind = "MAILBOX", friendly = friendly, x = point[1] / 100, y = point[2] / 100 }
                count = count + 1
            end
        end
    end
    return count
end

function S:IndexMailboxes(index, areaToUi)
    local Object = self.lib.Object
    self.stats.mailboxes = nil
    if type(Object) ~= "table" or type(Object.GetAllIds) ~= "function" then return end
    local ok, ids = pcall(Object.GetAllIds)
    if not ok or type(ids) ~= "table" then return end
    local read = type(Object.GetRaw) == "function" and Object.GetRaw or Object.Get
    local at, count = 0, 0
    local function Step()
        if self.index ~= index then return end -- rebuilt meanwhile
        if Combat() then C_Timer.After(2, Step); return end
        for _ = 1, self.mailboxStep do
            at = at + 1
            local objectID = ids[at]
            if not objectID then
                self.stats.mailboxes = count
                for _, callback in ipairs(self.listeners) do pcall(callback) end
                return
            end
            local okName, name = pcall(read, objectID, "name")
            if okName and name == MAILBOX then count = count + AddMailbox(index, areaToUi, Object, objectID) end
        end
        C_Timer.After(0, Step)
    end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(.5, Step) end
end

-- faction: UnitFactionGroup token; nil falls back to the player's own.
local function Faction(faction)
    if faction then return faction end
    if type(UnitFactionGroup) ~= "function" then return nil end
    local ok, token = pcall(UnitFactionGroup, "player")
    return ok and token or nil
end

-- The era flags have one TRAINER bit for class and profession trainers alike: the player wants
-- their own class trainer, told apart by the NPC's sub name ("Shaman Trainer", or the localized
-- class name when the data carries one).
local function ClassWords(classToken)
    if type(classToken) ~= "string" or classToken == "" then
        if type(UnitClass) ~= "function" then return nil end
        local ok, _, token = pcall(UnitClass, "player")
        classToken = ok and token or nil
        if type(classToken) ~= "string" then return nil end
    end
    local words = { (classToken == "DEATHKNIGHT" and "death knight" or classToken:lower()) .. " trainer" }
    for _, names in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
        local name = type(names) == "table" and names[classToken]
        if type(name) == "string" and name ~= "" then words[#words + 1] = name:lower() end
    end
    return words
end

function S:ClassTrainer(npcID, words)
    self.subNames = self.subNames or {}
    local subName = self.subNames[npcID]
    if subName == nil then
        local ok, value = pcall(self.lib.Npc.Get, npcID, "subName")
        subName = ok and type(value) == "string" and value:lower() or false
        self.subNames[npcID] = subName
    end
    if not subName then return false end
    for _, word in ipairs(words) do
        if subName:find(word, 1, true) then return true end
    end
    return false
end

-- classToken: only for TRAINER; nil falls back to the player's own class.
function S:Nearest(mapID, x, y, kind, faction, classToken)
    local index = self:BuildIndex()
    local list = index and index[mapID]
    if not list or type(x) ~= "number" or type(y) ~= "number" then return nil end
    faction = Faction(faction)
    local words = kind == "TRAINER" and ClassWords(classToken)
    if kind == "TRAINER" and not words then return nil end
    local best, bestGap
    for _, entry in ipairs(list) do
        if entry.kind == kind and Friendly(entry, faction) and (not words or self:ClassTrainer(entry.npcID, words)) then
            local gap = Gap(entry, x, y)
            if not bestGap or gap < bestGap then best, bestGap = entry, gap end
        end
    end
    if not best then return nil end
    if not best.npcID then return { x = best.x, y = best.y } end
    local Npc = self.lib.Npc
    local _, name = pcall(Npc.Get, best.npcID, "name")
    local _, subName = pcall(Npc.Get, best.npcID, "subName")
    return { npcID = best.npcID, name = name, subName = subName, x = best.x, y = best.y }
end

-- The mailboxes of a map worth a pin: never two closer than "apart" (a share of the map's height;
-- the caller makes it smaller as the map zooms in). The one nearest to x, y is always kept, and
-- stands for its neighbours.
function S:Mailboxes(mapID, faction, apart, x, y)
    local index = self:BuildIndex()
    local boxes, nearest, nearestGap = {}, nil, nil
    faction = Faction(faction)
    for _, entry in ipairs(index and index[mapID] or {}) do
        if entry.kind == "MAILBOX" and Friendly(entry, faction) then
            boxes[#boxes + 1] = entry
            local gap = x and y and Gap(entry, x, y)
            if gap and (not nearestGap or gap < nearestGap) then nearest, nearestGap = entry, gap end
        end
    end
    local limit = (apart or 0) * (apart or 0)
    local function Free(list, entry)
        for _, other in ipairs(list) do
            if Gap(other, entry.x, entry.y) < limit then return false end
        end
        return true
    end
    -- The same choice wherever the player stands, then the nearest one in place of its neighbours:
    -- pins do not jump about while walking.
    local chosen, kept = {}, { nearest }
    for _, entry in ipairs(boxes) do
        if Free(chosen, entry) then
            chosen[#chosen + 1] = entry
            if entry ~= nearest and (not nearest or Gap(nearest, entry.x, entry.y) >= limit) then kept[#kept + 1] = entry end
        end
    end
    return kept
end

function S:List(mapID, faction)
    local counts = {}
    for _, kind in ipairs(self.KINDS) do counts[kind] = 0 end
    counts.MAILBOX = 0
    local index = self:BuildIndex()
    local list = index and index[mapID]
    if not list then return counts end
    faction = Faction(faction)
    for _, entry in ipairs(list) do
        if Friendly(entry, faction) then counts[entry.kind] = counts[entry.kind] + 1 end
    end
    return counts
end

function S:Report()
    local lib = MS.JourneyQuestieOffers and MS.JourneyQuestieOffers:Library()
    return table.concat({
        "library=" .. tostring(lib ~= nil),
        "reason=" .. tostring(self.reason),
        "npcs=" .. tostring(self.stats.npcs),
        "mailboxes=" .. tostring(self.stats.mailboxes),
        "buildMs=" .. (self.stats.buildMs and string.format("%.0f", self.stats.buildMs) or "-"),
    }, "\n")
end
