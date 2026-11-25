local MS = _G.MS
MS.Ink = MS.Ink or {}
-- L'Encre des Royaumes in the game: keep tales, follow them, reveal what is found. Runs as one
-- component of the active experiences (same lifecycle, combat rules and window), with its own
-- SavedVariable. Addon-only: no Companion; only Courier.lua talks to another player.
local A = MS.Active
local I = MS.Ink
I.pending, I.retrySeconds = {}, 5

-- Journal codes (whitelisted fields, as every Active code): counts and states only, never a
-- title, a text, an answer or a place.
do
    local TEXT, NUM = "text", "number"
    local codes = A.Diagnostics.codes
    codes.INK_READY = { store = TEXT, tales = NUM }
    codes.INK_KEPT = { origin = TEXT, result = TEXT, pages = NUM, mode = TEXT }
    codes.INK_FORGOTTEN = {}
    codes.INK_PAGE_FOUND = { via = TEXT, result = TEXT, found = NUM, pages = NUM }
    codes.INK_ANSWER_WRONG = {}
    codes.INK_WATCH = { reason = TEXT, places = NUM }
    codes.INK_DEED = { kind = TEXT, source = TEXT, result = TEXT }
    codes.INK_DRAFT = { action = TEXT, result = TEXT }
    codes.INK_SEALED = { result = TEXT, pages = NUM, try = "boolean" }
end

function I:Ready()
    return self.initialized == true and not self.Store.readOnly and self.bucket ~= nil
end

function I:OnLogin()
    local key, now = A.identity and A.identity.key, A.Now()
    local root = self.Store:Initialize(_G.HearthsideInkDB, key)
    _G.HearthsideInkDB = root
    self.bucket = not self.Store.readOnly and key and self.Store:Character(key, now) or nil
    self.initialized = true
    A:Log("INK_READY", { store = self.Store.status, tales = self.Store:Count() })
    if self.Watch then self.Watch:Refresh("LOGIN") end
end

function I:OnCombat(inCombat)
    if not inCombat then self:Pump() end
end

function I:Entry(id) return self.Store.root and self.Store.root.tales[id] or nil end

function I:ProgressOf(id) return self.bucket and self.bucket.progress[id] or nil end

-- Every kept tale with this character's progress: unfinished first, then most recently kept.
function I:Entries()
    local list = {}
    for id, entry in pairs(self.Store.root and self.Store.root.tales or {}) do
        list[#list + 1] = { id = id, entry = entry, progress = self:ProgressOf(id) }
    end
    table.sort(list, function(a, b)
        local doneA, doneB = a.progress and a.progress.finishedAt ~= nil, b.progress and b.progress.finishedAt ~= nil
        if doneA ~= doneB then return not doneA end
        if a.entry.keptAt ~= b.entry.keptAt then return a.entry.keptAt > b.entry.keptAt end
        return a.id < b.id
    end)
    return list
end

-- Tales this character is following: kept, started and not finished.
function I:Following()
    local list = {}
    if not self:Ready() then return list end
    for id, progress in pairs(self.bucket.progress) do
        local entry = self:Entry(id)
        if entry and not progress.finishedAt then list[#list + 1] = { id = id, tale = entry.tale, progress = progress } end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function I:Begin(id)
    local entry = self:Entry(id)
    if not entry or not self:Ready() then return nil end
    if not self.bucket.progress[id] then self.bucket.progress[id] = self.Progress.New(entry.tale, A.Now()) end
    return self.bucket.progress[id]
end

-- Every surface that shows a tale. Hidden Journey views only note that they are stale.
local function Changed()
    if A.Panel then A.Panel:Changed("INK") end
    if I.Tab then I.Tab:Changed() end
    if I.MapLayer then I.MapLayer:Changed() end
    local journal, parcours = MS.QuestJournal, MS.JourneyProgressionView
    if journal and journal.Invalidate then
        journal:Invalidate()
        journal:Refresh()
    end
    if parcours and parcours.Invalidate then parcours:Invalidate() end
end

-- The playable zone the character stands in, as Parcours names its chapters (nil if unknown).
local function Zone()
    local data = MS.JourneyMapData
    local ok, zone = pcall(function() return data and data.PlayerZone and data:PlayerZone() end)
    if ok and type(zone) == "number" then return zone end
    return A.Position and A.Position:MapID() or nil
end

-- Keeps a tale (WRITTEN here or KEPT from a seal) and starts it for this character.
-- from: the character who gave it in the game. Returns the entry and NEW | UPDATED, or nil and a reason.
function I:Keep(tale, origin, from)
    if not self:Ready() then return nil, "NOT_READY" end
    local entry, status = self.Store:Keep(tale, origin, A.Now(), from)
    A:Log("INK_KEPT", { origin = origin, result = status, pages = #tale.pages, mode = tale.mode })
    if not entry then return nil, status end
    self:Begin(tale.id)
    if self.Watch then self.Watch:Refresh("KEEP") end
    Changed()
    return entry, status
end

function I:Import(text)
    if not self:Ready() then return nil, "NOT_READY" end
    local tale, reason = self.Codec.Decode(text, A.Now())
    if not tale then
        A:Log("INK_KEPT", { origin = "KEPT", result = reason })
        return nil, reason
    end
    return self:Keep(tale, "KEPT")
end

function I:Seal(id)
    local entry = self:Entry(id)
    return entry and self.Codec.Encode(entry.tale) or nil
end

function I:Forget(id)
    if not self:Ready() or not self.Store:Forget(id) then return false end
    for index = #self.pending, 1, -1 do if self.pending[index].id == id then table.remove(self.pending, index) end end
    A:Log("INK_FORGOTTEN", {})
    if self.Watch then self.Watch:Refresh() end
    Changed()
    return true
end

-- A page found by its trigger (via: its kind). Returns FOUND | FINISHED, or nil (and WAIT when
-- something else is asked first: an hour, a level).
function I:Found(id, key, via)
    local entry, progress = self:Entry(id), self:ProgressOf(id)
    if not entry or not progress then return nil end
    local page = self.Tale.Page(entry.tale, key)
    if page and self.Waiting(page) then return nil, "WAIT" end
    local result = self.Progress.Mark(entry.tale, progress, key, A.Now())
    if not result then return nil end
    -- Where the tale ended, for the character's own Parcours. Kept with the progress only.
    if result == "FINISHED" then progress.finishedMap = Zone() end
    A:Log("INK_PAGE_FOUND", { via = via, result = result, found = self.Progress.Count(entry.tale, progress),
        pages = #entry.tale.pages })
    self.pending[#self.pending + 1] = { id = id, key = key, result = result }
    if self.Watch then self.Watch:Refresh() end
    self:Pump()
    Changed()
    return result
end

-- HOUR | LEVEL: what a page asks besides its trigger, right now; nil when nothing.
function I.Waiting(page)
    if not page.when then return nil end
    return I.Tale.Waiting(page.when, (A.Call(_G.GetGameTime)), (A.Call(_G.UnitLevel, "player")))
end

-- One creature fallen for an open KILL page. Returns the count, or nil.
function I:Kill(id, key)
    local entry, progress = self:Entry(id), self:ProgressOf(id)
    local page = entry and progress and self.Tale.Page(entry.tale, key)
    if not page or self.Waiting(page) then return nil end
    local count = self.Progress.Kill(entry.tale, progress, key)
    if not count then return nil end
    if count >= page.trigger.count then self:Found(id, key, "KILL") else Changed() end
    return count
end

-- Parcours: the tales this character finished in a region, the latest first, three at most.
I.laurel = "|TInterface\\Icons\\INV_Misc_Book_09:14:14:0:0:64:64:5:59:5:59|t "
function I:ChapterLines(mapID)
    local lines, finished = {}, {}
    if not self:Ready() or type(mapID) ~= "number" then return lines end
    local data = MS.JourneyMapData
    local function Region(id) return data and data.RelationZone and data:RelationZone(id) or id end
    local region = Region(mapID)
    for id, progress in pairs(self.bucket.progress) do
        local entry = self:Entry(id)
        if entry and progress.finishedAt and type(progress.finishedMap) == "number" and Region(progress.finishedMap) == region then
            finished[#finished + 1] = { id = id, at = progress.finishedAt, tale = entry.tale }
        end
    end
    table.sort(finished, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return a.id < b.id
    end)
    for index = 1, math.min(3, #finished) do
        local tale = finished[index].tale
        lines[index] = self.laurel .. string.format(MS.L.INK_PARCOURS_FINISHED, tale.title, tale.author)
    end
    return lines
end

-- What the player typed for an ANSWER page. Returns FOUND | FINISHED, or nil and WRONG | CLOSED | WAIT.
function I:Answer(id, key, typed)
    local entry, progress = self:Entry(id), self:ProgressOf(id)
    if not entry or not progress or not self.Progress.IsOpen(entry.tale, progress, key) then return nil, "CLOSED" end
    local page = self.Tale.Page(entry.tale, key)
    if not page or page.trigger.kind ~= "ANSWER" then return nil, "CLOSED" end
    local hash = self.Tale.AnswerHash(id, key, typed)
    for _, accepted in ipairs(page.trigger.hashes) do
        if hash == accepted then return self:Found(id, key, "ANSWER") end
    end
    A:Log("INK_ANSWER_WRONG", {})
    return nil, "WRONG"
end

-- Shows the oldest found page waiting to be read. Never in a fight; a busy stage is asked again.
function I:Pump()
    local next = self.pending[1]
    if not next then return end
    -- The book already shows this tale: it turns to the page in place.
    local Tab, Book = self.Tab, self.Book
    if Tab and Tab.visible and Tab.mode == "BOOK" and Book and Book.taleId == next.id then
        table.remove(self.pending, 1)
        Book:Open(next.id, next.key, next.result)
        Tab:Refresh()
        return self:Pump()
    end
    if not A.Panel or not self.FoundCard then return end
    if A.Bool(A.Call(_G.InCombatLockdown)) ~= false then return end
    self.FoundCard:Focus(next.id, next.key, next.result)
    local shown = A.Panel:IsShown() and A.Panel.current
    local ok = shown and (A.Panel:Show("INK_FOUND") or true) or A.Panel:Open("INK_FOUND", "RESULT")
    if ok then
        table.remove(self.pending, 1)
        return
    end
    if not self.retry and _G.C_Timer then
        self.retry = C_Timer.NewTimer(self.retrySeconds, function()
            I.retry = nil
            I:Pump()
        end)
    end
end

-- /hearthside encre [exemple | <seal>]
A.commands.encre = function(_, rest)
    if not I:Ready() then A:Say("INK_NOT_READY"); return end
    local word = string.lower(string.match(rest or "", "^(%S*)") or "")
    if word == "exemple" or word == "sample" then
        if I.Demo then I.Demo:Create() end
    elseif word == "banc" or word == "bench" then
        if I.Demo then I.Demo:Bench() end
    elseif word == "sonde" or word == "probe" then
        for _, line in ipairs(I.Watch:Probe()) do MS.Diagnostics:Print(line) end
    elseif I.Codec.Find(rest) then
        local entry, reason = I:Import(rest)
        if entry then A:Say("INK_IMPORT_" .. reason, entry.tale.title) else A:Say("INK_IMPORT_" .. reason) end
    elseif not I:OpenTab("SHELF") then
        A:Say("INK_NO_JOURNEY")
    end
end
A.commands.ink = A.commands.encre

A:Register("Ink", I)
