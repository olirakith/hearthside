local MS = _G.MS

-- The bosses beaten during this visit of a dungeon, from what the game announces while the player
-- is there. Kept in the saved data, so a reload or a disconnection does not lose them.
MS.JourneyDungeonRun = { SAME_KILL = 120, KEEP = { party = 30 * 60, raid = 24 * 3600 } }
local Run = MS.JourneyDungeonRun
local Dungeons = MS.JourneyDungeons

local function Now() return type(_G.time) == "function" and time() or 0 end
local function Me() return type(_G.UnitGUID) == "function" and UnitGUID("player") or nil end
-- The client writes a curly apostrophe, the table a straight one.
local function Plain(name) return type(name) == "string" and (name:gsub("\226\128\153", "'")) or nil end
local function Hidden(value) return type(_G.issecretvalue) == "function" and issecretvalue(value) end

local function Store()
    local db = MS.Database and MS.Database:Get()
    return db and type(db.journey) == "table" and db.journey or nil
end

-- The visit in progress, if it is of this dungeon and by this character.
function Run:Get(dungeon)
    local store = Store()
    local run = store and store.dungeonRun
    if type(run) ~= "table" or type(run.kills) ~= "table" or not dungeon then return nil end
    if run.id ~= dungeon.id or run.who ~= Me() then return nil end
    return run
end

function Run:Drop()
    local store = Store()
    if store then store.dungeonRun = nil end
end

function Run:Record(encounterID, name)
    if Hidden(encounterID) or Hidden(name) then return end
    local dungeon, store = Dungeons:Current(), Store()
    if not dungeon or not store or type(encounterID) ~= "number" then return end
    local run, now = self:Get(dungeon), Now()
    local before = run and run.kills[encounterID]
    if before and math.abs(now - before.at) < self.SAME_KILL then return end -- announced twice
    -- A boss beaten again is a new visit.
    if not run or before then
        run = { id = dungeon.id, name = dungeon.name, who = Me(), raid = dungeon.raid, kills = {} }
        store.dungeonRun = run
    end
    run.at = now
    run.kills[encounterID] = { at = now, name = type(name) == "string" and name or nil }
    local map = MS.MapView
    if map and map.active and map.RenderSidebar then pcall(map.RenderSidebar, map) end
end

-- On the way in: a visit of another dungeon, or one left too long ago, is over.
function Run:Enter()
    local dungeon, store = Dungeons:Current(), Store()
    local run = store and store.dungeonRun
    if not dungeon or type(run) ~= "table" then return end
    if not self:Get(dungeon) or Now() - (run.at or 0) > (run.raid and self.KEEP.raid or self.KEEP.party) then self:Drop() end
end

-- On the way out, by the door, a reload or a disconnection: the visit stays open from now on.
function Run:Leave()
    local run = self:Get(Dungeons:Current())
    if run then run.at = Now() end
end

-- The game's own words for "this dungeon has been reset".
function Run:OnSystemMessage(text)
    if Hidden(text) or type(text) ~= "string" then return end
    local store = Store()
    local run = store and store.dungeonRun
    local format = _G.INSTANCE_RESET_SUCCESS
    if type(run) ~= "table" or type(run.name) ~= "string" or type(format) ~= "string" then return end
    if text == format:gsub("%%s", (run.name:gsub("%%", "%%%%"))) then self:Drop() end
end

-- The list to show: { id, name, beaten }, the known encounters then any other the game announced.
function Run:Bosses(dungeon)
    local run = self:Get(dungeon)
    local kills, list, used, done = run and run.kills or {}, {}, {}, 0
    local french = type(_G.GetLocale) == "function" and GetLocale() == "frFR"
    local function Beaten(id, english, name)
        if kills[id] then return id end
        for other, kill in pairs(kills) do -- another ID for the same encounter
            local known = Plain(kill.name)
            if known and (known == english or known == name) then return other end
        end
    end
    for _, boss in ipairs(MS.JourneyDungeonBosses and MS.JourneyDungeonBosses[dungeon.id] or {}) do
        local name = french and boss[3] or boss[2]
        local kill = Beaten(boss[1], boss[2], name)
        if kill then used[kill] = true; done = done + 1; name = kills[kill].name or name end
        list[#list + 1] = { id = boss[1], name = name, beaten = kill ~= nil }
    end
    local others = {}
    for id, kill in pairs(kills) do
        if not used[id] and kill.name then others[#others + 1] = { id = id, name = kill.name, beaten = true } end
    end
    table.sort(others, function(a, b) return a.id < b.id end)
    for _, boss in ipairs(others) do list[#list + 1] = boss; done = done + 1 end
    return list, done
end

Run.events = CreateFrame("Frame")
for _, event in ipairs({ "ENCOUNTER_END", "BOSS_KILL", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "CHAT_MSG_SYSTEM" }) do
    pcall(Run.events.RegisterEvent, Run.events, event)
end
Run.events:SetScript("OnEvent", function(_, event, id, name, _, _, success)
    if event == "ENCOUNTER_END" then
        if not Hidden(success) and success == 1 then Run:Record(id, name) end
    elseif event == "BOSS_KILL" then
        Run:Record(id, name)
    elseif event == "PLAYER_ENTERING_WORLD" then
        Run:Enter()
    elseif event == "PLAYER_LEAVING_WORLD" then
        Run:Leave()
    else
        Run:OnSystemMessage(id)
    end
end)
