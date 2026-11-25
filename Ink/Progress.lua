local MS = _G.MS
MS.Ink = MS.Ink or {}
-- One character's way through one tale. Pure.
-- progress = { version, startedAt, found = { [pageKey] = timestamp }, finishedAt, finishedMap,
--              kills = { [pageKey] = count }? }
-- In a SEQUENCE tale only the first page not found yet is open; in a FREE tale every page is.
local Progress = {}
MS.Ink.Progress = Progress

local function Num(value) return type(value) == "number" and value == value and value >= 0 and value < 4294967296 end

function Progress.New(tale, now)
    return { version = tale.version, startedAt = now, found = {} }
end

-- Rebuilt against the stored tale: pages that no longer exist are forgotten.
function Progress.Sanitize(raw, tale)
    if type(raw) ~= "table" or type(tale) ~= "table" then return nil end
    local progress = { version = tale.version, startedAt = Num(raw.startedAt) and raw.startedAt or nil, found = {} }
    local found = type(raw.found) == "table" and raw.found or {}
    for _, page in ipairs(tale.pages) do
        if Num(found[page.key]) then progress.found[page.key] = found[page.key] end
    end
    for _, page in ipairs(tale.pages) do
        local count = type(raw.kills) == "table" and raw.kills[page.key]
        if page.trigger.kind == "KILL" and not progress.found[page.key] and Num(count) and count >= 1 then
            progress.kills = progress.kills or {}
            progress.kills[page.key] = math.min(math.floor(count), page.trigger.count)
        end
    end
    if Num(raw.finishedAt) and Progress.Complete(tale, progress) then
        progress.finishedAt = raw.finishedAt
        if Num(raw.finishedMap) then progress.finishedMap = raw.finishedMap end
    end
    return progress
end

function Progress.Count(tale, progress)
    local count = 0
    for _, page in ipairs(tale.pages) do if progress.found[page.key] then count = count + 1 end end
    return count
end

function Progress.Complete(tale, progress)
    return Progress.Count(tale, progress) == #tale.pages
end

-- The pages the player can find right now, in tale order.
function Progress.Open(tale, progress)
    local open = {}
    if progress.finishedAt then return open end
    for _, page in ipairs(tale.pages) do
        if not progress.found[page.key] then
            open[#open + 1] = page
            if tale.order == "SEQUENCE" then break end
        end
    end
    return open
end

function Progress.IsOpen(tale, progress, key)
    for _, page in ipairs(Progress.Open(tale, progress)) do if page.key == key then return true end end
    return false
end

function Progress.Kills(progress, key)
    return progress.kills and progress.kills[key] or 0
end

-- One more creature for an open KILL page. Returns the new count, or nil when the page is not open.
function Progress.Kill(tale, progress, key)
    local page = MS.Ink.Tale.Page(tale, key)
    if not page or page.trigger.kind ~= "KILL" or not Progress.IsOpen(tale, progress, key) then return nil end
    progress.kills = progress.kills or {}
    progress.kills[key] = math.min(Progress.Kills(progress, key) + 1, page.trigger.count)
    return progress.kills[key]
end

-- Marks a page found. Returns "FOUND", "FINISHED" (the last one) or nil when it was not open.
function Progress.Mark(tale, progress, key, now)
    if not Progress.IsOpen(tale, progress, key) then return nil end
    progress.found[key] = now or 0
    if progress.kills then progress.kills[key] = nil end
    if Progress.Complete(tale, progress) then
        progress.finishedAt = now or 0
        return "FINISHED"
    end
    return "FOUND"
end

-- Found pages in tale order (for reading again).
function Progress.FoundPages(tale, progress)
    local pages = {}
    for _, page in ipairs(tale.pages) do if progress.found[page.key] then pages[#pages + 1] = page end end
    return pages
end
