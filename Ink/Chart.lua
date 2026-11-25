local MS = _G.MS
MS.Ink = MS.Ink or {}
-- What the tales followed put on a map, and nothing more than each mode allows:
--   NOTES: a blurred circle to search in, never centred on the page.
--   HUNT:  no mark, only a word that a page hides on this map.
--   QUEST: the place itself, as a quest objective.
-- Pages already found are marked where they were found. An author sees the places of the draft
-- open in the workshop. Read on demand; nothing is stored.
local A = MS.Active
local I = MS.Ink
-- A search circle is at least `search` yards wide and `searchFactor` radii; its centre drifts from
-- the page by at most `drift` of that, so the page is inside but not in the middle.
local Chart = { search = 90, searchFactor = 6, drift = .55, frames = {} }
I.Chart = Chart

-- How a map sits in the world: origin, the two axes in yards, and the yards of one map unit.
-- false when the client cannot say.
function Chart.Frame(mapID)
    local frame = Chart.frames[mapID]
    if frame ~= nil then return frame or nil end
    local origin, right, down = I.Watch.World(mapID, 0, 0), I.Watch.World(mapID, 1, 0), I.Watch.World(mapID, 0, 1)
    frame = false
    if origin and right and down and origin.continent == right.continent and origin.continent == down.continent then
        local ux, uy, vx, vy = right.x - origin.x, right.y - origin.y, down.x - origin.x, down.y - origin.y
        local det = ux * vy - uy * vx
        if det ~= 0 then
            frame = { continent = origin.continent, ox = origin.x, oy = origin.y, ux = ux, uy = uy, vx = vx, vy = vy,
                det = det, width = math.sqrt(ux * ux + uy * uy), height = math.sqrt(vx * vx + vy * vy) }
        end
    end
    Chart.frames[mapID] = frame
    return frame or nil
end

-- Yards across and down a map, or nil.
function Chart.Yards(mapID)
    local map = _G.C_Map
    local width, height = A.Call(type(map) == "table" and map.GetMapWorldSize or nil, mapID)
    if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then return width, height end
    local frame = Chart.Frame(mapID)
    if frame then return frame.width, frame.height end
end

-- Where a point of one map falls on another map of the same continent. nil when it is outside
-- the map shown, or when the client cannot place it.
function Chart.Project(mapID, x, y, shown)
    if mapID == shown then return x, y end
    local frame, world = Chart.Frame(shown), I.Watch.World(mapID, x, y)
    if not frame or not world or world.continent ~= frame.continent then return nil end
    local dx, dy = world.x - frame.ox, world.y - frame.oy
    local px, py = (dx * frame.vy - dy * frame.vx) / frame.det, (frame.ux * dy - frame.uy * dx) / frame.det
    if px < 0 or px > 1 or py < 0 or py > 1 then return nil end
    return px, py
end

-- Two steady numbers in [0, 1) from a tale and a page: the same circle every time, for everyone.
function Chart.Dice(id, key)
    local hash = 5381
    local text = tostring(id) .. ":" .. tostring(key)
    for index = 1, #text do hash = (hash * 33 + text:byte(index)) % 4294967296 end
    local first = (hash % 65536) / 65536
    local second = (math.floor(hash / 65536) % 65536) / 65536
    return first, second
end

local function Clamp(value) return math.max(0, math.min(1, value)) end

-- A reader's marks on the map shown, and the tales that only say "a page hides here".
-- mark = { kind = FOUND | SEARCH | GOAL, id, key, x, y, radiusX, radiusY, tale, page }
-- radiusX / radiusY are map fractions (nil when the map's size is unknown).
function Chart:Marks(shown)
    local marks, hints = {}, {}
    if type(shown) ~= "number" or not I:Ready() then return marks, hints end
    local width, height = Chart.Yards(shown)
    for _, following in ipairs(I:Following()) do
        local tale, progress = following.tale, following.progress
        local open, hinted = {}, false
        for _, page in ipairs(I.Progress.Open(tale, progress)) do open[page.key] = true end
        for _, page in ipairs(tale.pages) do
            local trigger = page.trigger
            local found = progress.found[page.key] ~= nil
            if trigger.kind == "PLACE" and (found or open[page.key]) then
                local x, y = Chart.Project(trigger.mapID, trigger.x, trigger.y, shown)
                if x then
                    local mark = { id = following.id, key = page.key, tale = tale, page = page, x = x, y = y }
                    if found then
                        mark.kind = "FOUND"
                    elseif tale.mode == "QUEST" then
                        mark.kind = "GOAL"
                        if width then mark.radiusX, mark.radiusY = trigger.radius / width, trigger.radius / height end
                    elseif tale.mode == "NOTES" and width then
                        mark.kind = "SEARCH"
                        local yards = math.max(self.search, trigger.radius * self.searchFactor)
                        local turn, reach = Chart.Dice(following.id, page.key)
                        local angle, away = turn * 2 * math.pi, math.sqrt(reach) * self.drift * yards
                        mark.x, mark.y = Clamp(x + math.cos(angle) * away / width), Clamp(y + math.sin(angle) * away / height)
                        mark.radiusX, mark.radiusY = yards / width, yards / height
                    else
                        mark = nil
                        if not hinted then
                            hinted = true
                            hints[#hints + 1] = { id = following.id, tale = tale }
                        end
                    end
                    if mark then marks[#marks + 1] = mark end
                end
            end
        end
    end
    return marks, hints
end

-- The draft open in the workshop, for its author: every place, exactly, with its radius.
-- Returns the marks and the draft (nil when the workshop is not open on a draft).
function Chart:AuthorMarks(shown)
    local marks = {}
    local Tab, Atelier = I.Tab, I.Atelier
    if type(shown) ~= "number" or not Tab or Tab.mode ~= "WORKSHOP" or not Atelier or not Atelier.draftId then return marks, nil end
    local draft = I.Workshop:Draft(Atelier.draftId)
    if not draft then return marks, nil end
    local width, height = Chart.Yards(shown)
    for index, page in ipairs(draft.pages) do
        local trigger = page.trigger
        if trigger.kind == "PLACE" and type(trigger.mapID) == "number" and type(trigger.x) == "number" then
            local x, y = Chart.Project(trigger.mapID, trigger.x, trigger.y, shown)
            if x then
                local mark = { kind = "AUTHOR", id = draft.id, key = page.key, page = page, number = index, x = x, y = y,
                    selected = page.key == Atelier.selected }
                if width then mark.radiusX, mark.radiusY = trigger.radius / width, trigger.radius / height end
                marks[#marks + 1] = mark
            end
        end
    end
    return marks, draft
end
