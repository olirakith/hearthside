local MS = _G.MS
MS.Ink = MS.Ink or {}
-- /hearthside encre exemple: a three-page tale written around the player, to try L'Encre before
-- the writing workshop exists. Page 1 waits a few steps east, page 2 asks a riddle, page 3 wants
-- the hearthstone in the bags.
-- /hearthside encre banc: the sample plus a Quest tale and a Notes tale, so every mode can be
-- tried in the game (map layer, Quests section, Parcours line) without writing anything.
local A = MS.Active
local I = MS.Ink
local Demo = { offset = 12, radius = 10, hearthstone = 6948, questStep = 15, notesStep = 120, notesRadius = 15 }
I.Demo = Demo

local function NewId(random)
    for _ = 1, 16 do
        local id = MS.Community.Bytes.RandomHex(8, random)
        if not I:Entry(id) then return id end
    end
end

local function Clamp(value) return math.max(0, math.min(1, value)) end

-- The player's settled position, or nil after saying why.
local function Here()
    local sample = A.Position:Sample()
    if sample.settled ~= true or not sample.mapID or not sample.x or not sample.y
        or not sample.width or sample.width <= 0 or not sample.height or sample.height <= 0 then
        A:Say("INK_DEMO_NO_POSITION")
        return nil
    end
    return sample
end

-- A place trigger `east` and `south` yards away from the sample (negative = west / north).
local function Place(sample, east, south, radius)
    return { kind = "PLACE", mapID = sample.mapID, radius = radius,
        x = Clamp(sample.x + east / sample.width), y = Clamp(sample.y + south / sample.height) }
end

local function Answers(id, key, ...)
    local hashes = {}
    for _, answer in ipairs({ ... }) do hashes[#hashes + 1] = I.Tale.AnswerHash(id, key, answer) end
    return hashes
end

-- build(id, sample, L) returns the raw tale fields; the tale is kept as WRITTEN (followed at once).
local function Write(sample, build)
    local id = NewId(A.random or math.random)
    if not id then return nil end
    local L = MS.L
    local raw = build(id, sample, L)
    raw.id, raw.version, raw.createdAt = id, 1, A.Now()
    raw.author = MS.Active.SealBook:IdentityName(A.identity) or L.INK_UNKNOWN_AUTHOR
    local tale = I.Tale.Sanitize(raw, true)
    local entry, status = tale and I:Keep(tale, "WRITTEN")
    if not entry then
        A:Say("INK_IMPORT_" .. tostring(status or "INVALID"))
        return nil
    end
    return entry
end

local function Sample(id, sample, L)
    return {
        mode = "HUNT", order = "SEQUENCE",
        title = L.INK_DEMO_TITLE, intro = L.INK_DEMO_INTRO, ending = L.INK_DEMO_ENDING,
        pages = {
            { key = "0001", title = L.INK_DEMO_PAGE1_TITLE, hint = L.INK_DEMO_PAGE1_HINT, text = L.INK_DEMO_PAGE1_TEXT,
                trigger = Place(sample, Demo.offset, 0, Demo.radius) },
            { key = "0002", title = L.INK_DEMO_PAGE2_TITLE, hint = L.INK_DEMO_PAGE2_HINT, text = L.INK_DEMO_PAGE2_TEXT,
                trigger = { kind = "ANSWER", hashes = Answers(id, "0002", "7", "sept", "seven") } },
            { key = "0003", title = L.INK_DEMO_PAGE3_TITLE, hint = L.INK_DEMO_PAGE3_HINT, text = L.INK_DEMO_PAGE3_TEXT,
                trigger = { kind = "ITEM", itemID = Demo.hearthstone, count = 1 } },
        },
    }
end

-- Quest mode: exact places on the map, objectives in the Quests tab, a Parcours line at the end.
local function Quest(id, sample, L)
    local step = Demo.questStep
    return {
        mode = "QUEST", order = "SEQUENCE",
        title = L.INK_BENCH_QUEST_TITLE, intro = L.INK_BENCH_QUEST_INTRO, ending = L.INK_BENCH_QUEST_ENDING,
        pages = {
            { key = "0001", title = L.INK_BENCH_QUEST_PAGE1_TITLE, hint = L.INK_BENCH_QUEST_PAGE1_HINT,
                text = L.INK_BENCH_QUEST_PAGE1_TEXT, trigger = Place(sample, 0, -step, 8) },
            { key = "0002", title = L.INK_BENCH_QUEST_PAGE2_TITLE, hint = L.INK_BENCH_QUEST_PAGE2_HINT,
                text = L.INK_BENCH_QUEST_PAGE2_TEXT, trigger = Place(sample, step, -step, 8) },
            { key = "0003", title = L.INK_BENCH_QUEST_PAGE3_TITLE, hint = L.INK_BENCH_QUEST_PAGE3_HINT,
                text = L.INK_BENCH_QUEST_PAGE3_TEXT,
                trigger = { kind = "ANSWER", hashes = Answers(id, "0003", "rouge", "red") } },
        },
    }
end

-- Notes mode, free order: two notes far enough to draw blurred circles on the map.
local function Notes(_, sample, L)
    local far, radius = Demo.notesStep, Demo.notesRadius
    return {
        mode = "NOTES", order = "FREE",
        title = L.INK_BENCH_NOTES_TITLE, intro = L.INK_BENCH_NOTES_INTRO, ending = L.INK_BENCH_NOTES_ENDING,
        pages = {
            { key = "0001", title = L.INK_BENCH_NOTES_PAGE1_TITLE, hint = L.INK_BENCH_NOTES_PAGE1_HINT,
                text = L.INK_BENCH_NOTES_PAGE1_TEXT, trigger = Place(sample, -far, 0, radius) },
            { key = "0002", title = L.INK_BENCH_NOTES_PAGE2_TITLE, hint = L.INK_BENCH_NOTES_PAGE2_HINT,
                text = L.INK_BENCH_NOTES_PAGE2_TEXT, trigger = Place(sample, 0, far, radius) },
        },
    }
end

-- People, emotes, kills and conditions, in any order. The author's target is who to talk to (a
-- friend) or what to hunt (a foe); without one, only the emotes and the hour.
local function Deeds(id, sample, L)
    local hour = A.Call(_G.GetGameTime)
    hour = type(hour) == "number" and hour or 0
    local pages = {
        { key = "0001", title = L.INK_BENCH_DEEDS_PAGE1_TITLE, hint = L.INK_BENCH_DEEDS_PAGE1_HINT, text = L.INK_BENCH_DEEDS_TEXT,
            trigger = { kind = "EMOTE", token = "WAVE" } },
        { key = "0002", title = L.INK_BENCH_DEEDS_PAGE2_TITLE, hint = L.INK_BENCH_DEEDS_PAGE2_HINT, text = L.INK_BENCH_DEEDS_TEXT,
            trigger = { kind = "EMOTE", token = "BOW", mapID = sample.mapID, x = sample.x, y = sample.y, radius = 10 } },
        { key = "0003", title = L.INK_BENCH_DEEDS_PAGE3_TITLE, hint = L.INK_BENCH_DEEDS_PAGE3_HINT, text = L.INK_BENCH_DEEDS_TEXT,
            trigger = { kind = "ANSWER", hashes = Answers(id, "0003", "rouge", "red") }, when = { from = (hour + 1) % 24, to = hour } },
    }
    local npcID = I.Deeds.Creature((A.Call(_G.UnitGUID, "target")))
    local name = npcID and A.Call(_G.UnitName, "target")
    if type(name) == "string" then
        local foe = A.Bool(A.Call(_G.UnitCanAttack, "player", "target")) == true
        pages[4] = { key = "0004", title = foe and L.INK_BENCH_DEEDS_KILL_TITLE or L.INK_BENCH_DEEDS_NPC_TITLE,
            hint = foe and L.INK_BENCH_DEEDS_KILL_HINT or L.INK_BENCH_DEEDS_NPC_HINT, text = L.INK_BENCH_DEEDS_TEXT,
            trigger = { kind = foe and "KILL" or "NPC", npcID = npcID, name = name, count = 2 } }
    end
    return { mode = "QUEST", order = "FREE", title = L.INK_BENCH_DEEDS_TITLE, intro = L.INK_BENCH_DEEDS_INTRO,
        ending = L.INK_BENCH_DEEDS_ENDING, pages = pages }
end

function Demo:Create()
    local sample = Here()
    local entry = sample and Write(sample, Sample)
    if not entry then return nil end
    A:Say("INK_DEMO_CREATED")
    if I.OpenTab then I:OpenTab("BOOK", entry.tale.id) end
    return entry
end

-- Returns the four entries (sample, quest, notes, deeds), or nil when nothing could be written.
function Demo:Bench()
    local sample = Here()
    if not sample then return nil end
    local hunt, quest, notes = Write(sample, Sample), Write(sample, Quest), Write(sample, Notes)
    local deeds = Write(sample, Deeds)
    if not (hunt and quest and notes and deeds) then return nil end
    A:Say("INK_BENCH_CREATED")
    if I.OpenTab then I:OpenTab("SHELF") end
    return { hunt, quest, notes, deeds }
end
