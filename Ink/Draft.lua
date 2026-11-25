local MS = _G.MS
MS.Ink = MS.Ink or {}
-- A tale being written: lenient while the author types, checked only when it is sealed. Pure.
-- Answers stay as typed (only the author's own SavedVariable holds them) and become salted
-- fingerprints in the sealed tale.
--
-- draft = { id, baseVersion (0 = never sealed), createdAt, updatedAt, author, title, mode, order,
--           intro, ending, pages = { { key, title, hint, text, trigger } } }
-- A page may also carry when, as a tale does.
-- trigger = { kind = "PLACE", mapID?, x?, y?, radius } | { kind = "ANSWER", answers (typed, "/"
--           between forms), hashes (kept from an earlier seal) } | { kind = "ITEM", itemID?, count }
--         | { kind = "NPC", npcID?, name? } | { kind = "KILL", npcID?, name?, count }
--         | { kind = "EMOTE", token, npcID?, name?, mapID?, x?, y?, radius? }
local Draft = { maxAnswerText = 200, defaultEmote = "WAVE" }
MS.Ink.Draft = Draft

local function Tale() return MS.Ink.Tale end
local function Num(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function Hex(value, length) return type(value) == "string" and #value == length and value:find("^%x+$") ~= nil end

-- Typed text kept as typed, only bounded (twice the sealed limit, so nothing is cut while editing).
local function Raw(value, maxBytes)
    if type(value) ~= "string" then return "" end
    return MS.Active.Text.Truncate(value, maxBytes * 2)
end

function Draft.New(id, author, now)
    return { id = id, baseVersion = 0, createdAt = now, updatedAt = now, author = author, title = "", mode = "NOTES",
        order = "SEQUENCE", intro = "", ending = "", pages = {} }
end

local function SanitizeTrigger(raw)
    local T = Tale()
    if type(raw) ~= "table" or not T.triggers[raw.kind] then return nil end
    if raw.kind == "PLACE" then
        local trigger = { kind = "PLACE", radius = T.defaultRadius }
        if Num(raw.radius) then trigger.radius = math.max(T.minRadius, math.min(T.maxRadius, math.floor(raw.radius))) end
        local placed = T.SanitizeTrigger(raw)
        if placed then trigger.mapID, trigger.x, trigger.y = placed.mapID, placed.x, placed.y end
        return trigger
    elseif raw.kind == "ANSWER" then
        local kept = T.SanitizeTrigger({ kind = "ANSWER", hashes = raw.hashes })
        return { kind = "ANSWER", answers = Raw(raw.answers, Draft.maxAnswerText), hashes = kept and kept.hashes or nil }
    elseif raw.kind == "EMOTE" then
        return T.SanitizeTrigger(raw) or { kind = "EMOTE", token = Draft.defaultEmote }
    elseif raw.kind == "NPC" or raw.kind == "KILL" then
        local whole = T.SanitizeTrigger(raw)
        if whole then return whole end
        local count = Num(raw.count) and math.max(1, math.min(T.maxKills, math.floor(raw.count))) or T.defaultKills
        return { kind = raw.kind, count = raw.kind == "KILL" and count or nil }
    else
        local trigger = { kind = "ITEM", count = 1 }
        if Num(raw.count) then trigger.count = math.max(1, math.min(T.maxItemCount, math.floor(raw.count))) end
        if Num(raw.itemID) and raw.itemID >= 1 and raw.itemID <= 4294967295 and raw.itemID % 1 == 0 then trigger.itemID = raw.itemID end
        return trigger
    end
end

function Draft.Sanitize(raw)
    local T = Tale()
    if type(raw) ~= "table" or not Hex(raw.id, 8) then return nil end
    local draft = {
        id = raw.id:lower(), baseVersion = Num(raw.baseVersion) and math.max(0, math.min(65534, math.floor(raw.baseVersion))) or 0,
        createdAt = Num(raw.createdAt) and raw.createdAt or nil, updatedAt = Num(raw.updatedAt) and raw.updatedAt or 0,
        author = T.Line(raw.author, T.authorBytes), title = Raw(raw.title, T.titleBytes),
        mode = T.modes[raw.mode] and raw.mode or "NOTES", order = T.orders[raw.order] and raw.order or "SEQUENCE",
        intro = Raw(raw.intro, T.introBytes), ending = Raw(raw.ending, T.introBytes), pages = {},
    }
    if not draft.author then return nil end
    local keys = {}
    for _, page in ipairs(type(raw.pages) == "table" and raw.pages or {}) do
        local trigger = type(page) == "table" and Hex(page.key, 4) and SanitizeTrigger(page.trigger)
        if trigger and not keys[page.key:lower()] and #draft.pages < T.maxPages then
            keys[page.key:lower()] = true
            draft.pages[#draft.pages + 1] = { key = page.key:lower(), title = Raw(page.title, T.titleBytes),
                hint = Raw(page.hint, T.hintBytes), text = Raw(page.text, T.textBytes), trigger = trigger,
                when = T.SanitizeWhen(page.when) }
        end
    end
    return draft
end

-- A draft to edit a sealed tale again. Answers typed in an earlier draft of the same page come
-- back; otherwise the sealed fingerprints are kept until new answers are typed.
function Draft.FromTale(tale, previous, now)
    local draft = Draft.New(tale.id, tale.author, now)
    draft.baseVersion, draft.createdAt = tale.version, tale.createdAt
    draft.title, draft.mode, draft.order = tale.title, tale.mode, tale.order
    draft.intro, draft.ending = tale.intro or "", tale.ending or ""
    local typed = {}
    for _, page in ipairs(type(previous) == "table" and previous.pages or {}) do
        if page.trigger.kind == "ANSWER" then typed[page.key] = page.trigger.answers end
    end
    for index, page in ipairs(tale.pages) do
        local trigger = {}
        for key, value in pairs(page.trigger) do trigger[key] = value end
        if trigger.kind == "ANSWER" then trigger.answers = typed[page.key] or "" end
        draft.pages[index] = { key = page.key, title = page.title, hint = page.hint or "", text = page.text or "", trigger = trigger,
            when = page.when }
    end
    return Draft.Sanitize(draft)
end

function Draft.Page(draft, key)
    for index, page in ipairs(draft.pages) do if page.key == key then return page, index end end
end

-- Adds an empty page with this kind of trigger. Returns the page, or nil when the tale is full.
function Draft.AddPage(draft, kind)
    if #draft.pages >= Tale().maxPages or not Tale().triggers[kind] then return nil end
    local highest = 0
    for _, page in ipairs(draft.pages) do highest = math.max(highest, tonumber(page.key, 16)) end
    if highest >= 65535 then return nil end
    local page = { key = string.format("%04x", highest + 1), title = "", hint = "", text = "",
        trigger = SanitizeTrigger({ kind = kind }) }
    draft.pages[#draft.pages + 1] = page
    return page
end

function Draft.Move(draft, key, delta)
    local _, index = Draft.Page(draft, key)
    local target = index and index + delta
    if not target or target < 1 or target > #draft.pages then return false end
    draft.pages[index], draft.pages[target] = draft.pages[target], draft.pages[index]
    return true
end

function Draft.Remove(draft, key)
    local _, index = Draft.Page(draft, key)
    if not index then return false end
    table.remove(draft.pages, index)
    return true
end

-- The forms an author typed for one answer: "sept / 7 / seven" gives three.
function Draft.Answers(text)
    local list = {}
    for part in (type(text) == "string" and text or ""):gmatch("[^/]+") do
        if Tale().NormalizeAnswer(part) and #list < Tale().maxAnswers then list[#list + 1] = part end
    end
    return list
end

-- The sealed tale, or nil, a reason (TITLE | NO_PAGES | PAGE_TITLE | PAGE_ANSWER | PAGE_PLACE |
-- PAGE_ITEM | PAGE_NPC | PAGE_KILL | INVALID) and the page number it concerns.
function Draft.ToTale(draft, now)
    local T = Tale()
    if not T.Line(draft.title, T.titleBytes) then return nil, "TITLE" end
    if #draft.pages == 0 then return nil, "NO_PAGES" end
    local raw = { id = draft.id, version = draft.baseVersion + 1, createdAt = draft.createdAt or now, author = draft.author,
        title = draft.title, mode = draft.mode, order = draft.order, intro = draft.intro, ending = draft.ending, pages = {} }
    for index, page in ipairs(draft.pages) do
        if not T.Line(page.title, T.titleBytes) then return nil, "PAGE_TITLE", index end
        local trigger = page.trigger
        if trigger.kind == "PLACE" then
            if not trigger.mapID then return nil, "PAGE_PLACE", index end
        elseif trigger.kind == "ITEM" then
            if not trigger.itemID then return nil, "PAGE_ITEM", index end
        elseif trigger.kind == "NPC" or trigger.kind == "KILL" then
            if not trigger.npcID then return nil, "PAGE_" .. trigger.kind, index end
        elseif trigger.kind == "ANSWER" then
            local hashes = {}
            for _, answer in ipairs(Draft.Answers(trigger.answers)) do hashes[#hashes + 1] = T.AnswerHash(draft.id, page.key, answer) end
            if #hashes == 0 then hashes = trigger.hashes or {} end
            if #hashes == 0 then return nil, "PAGE_ANSWER", index end
            trigger = { kind = "ANSWER", hashes = hashes }
        end
        raw.pages[index] = { key = page.key, title = page.title, hint = page.hint, text = page.text, trigger = trigger, when = page.when }
    end
    local tale = T.Sanitize(raw, true)
    if not tale then return nil, "INVALID" end
    return tale
end
