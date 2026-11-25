local MS = _G.MS
MS.Ink = MS.Ink or {}
-- What finds a page by itself: a place reached, an item carried. The place watcher only runs
-- while an open page waits for a place, reads the position once a second and stores none of it.
-- Answers come from the reading view (Ink:Answer).
local A = MS.Active
local I = MS.Ink
-- Twice a second, one sample inside is enough: the settle window after loading already keeps
-- stale positions out, and a runner crosses a small circle in a second or two.
local W = { interval = .5, streak = 1, counts = {} }
I.Watch = W

-- Open pages of one kind, in every tale followed.
local function OpenPages(kind)
    local found = {}
    for _, following in ipairs(I:Following()) do
        for _, page in ipairs(I.Progress.Open(following.tale, following.progress)) do
            if page.trigger.kind == kind then found[#found + 1] = { id = following.id, page = page } end
        end
    end
    return found
end

W.OpenPages = OpenPages

-- Carried, but asked for at another hour or level: time passing is what opens it.
local function WaitingItems()
    for _, open in ipairs(OpenPages("ITEM")) do if open.page.when then return true end end
    return false
end

function W:Refresh(reason)
    local places = OpenPages("PLACE")
    local needed = #places > 0 or WaitingItems()
    if reason then A:Log("INK_WATCH", { reason = reason, places = #places }) end
    if needed and not self.ticker and _G.C_Timer then
        self.ticker = C_Timer.NewTicker(self.interval, function() W:Tick() end)
    elseif not needed and self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    self:CheckItems()
end

-- One sample against one place: NEAR | FAR | OTHER_MAP | UNSETTLED | NO_POSITION | NO_DISTANCE |
-- COMBAT | DEAD | TAXI. Indoors counts (measured on Forever: Ironforge gives a position).
-- World yards of a map point: { continent, x, y }, or nil when the client cannot say.
function W.World(mapID, x, y)
    local map, vector = _G.C_Map, _G.CreateVector2D
    if type(map) ~= "table" or type(map.GetWorldPosFromMapPos) ~= "function" or type(vector) ~= "function" then return nil end
    local ok, point = pcall(vector, x, y)
    if not ok or not point then return nil end
    local continent, world = A.Call(map.GetWorldPosFromMapPos, mapID, point)
    if not continent or type(world) ~= "table" then return nil end
    local wx, wy
    if type(world.GetXY) == "function" then wx, wy = A.Call(world.GetXY, world) else wx, wy = world.x, world.y end
    if type(wx) ~= "number" or type(wy) ~= "number" then return nil end
    return { continent = continent, x = wx, y = wy }
end

-- Yards between the player and a place. On the same map, from the map size; on another map (the
-- game switches to a district or a sub-map while walking), through world positions.
function W.Distance(trigger, sample)
    if sample.mapID == trigger.mapID and type(sample.width) == "number" and type(sample.height) == "number"
        and sample.width > 0 and sample.height > 0 then
        local dx, dy = (sample.x - trigger.x) * sample.width, (sample.y - trigger.y) * sample.height
        return math.sqrt(dx * dx + dy * dy)
    end
    local here, there = W.World(sample.mapID, sample.x, sample.y), W.World(trigger.mapID, trigger.x, trigger.y)
    if here and there and here.continent == there.continent then
        return math.sqrt((here.x - there.x) ^ 2 + (here.y - there.y) ^ 2)
    end
end

function W.Classify(trigger, sample)
    if type(sample) ~= "table" or sample.settled ~= true then return "UNSETTLED" end
    if type(sample.mapID) ~= "number" then return "NO_POSITION" end
    if type(sample.x) ~= "number" or type(sample.y) ~= "number" then return "NO_POSITION" end
    local distance = W.Distance(trigger, sample)
    if not distance then return sample.mapID ~= trigger.mapID and "OTHER_MAP" or "NO_DISTANCE" end
    if distance > trigger.radius then return "FAR" end
    if sample.combat ~= false then return "COMBAT" end
    if sample.dead ~= false then return "DEAD" end
    if sample.taxi == true then return "TAXI" end
    return "NEAR"
end

function W:Tick()
    if not I:Ready() then return end
    if WaitingItems() then self:CheckItems() end
    local candidates = OpenPages("PLACE")
    if #candidates == 0 then
        self.counts = {}
        return
    end
    local sample = A.Position:Sample()
    for _, open in ipairs(candidates) do
        local slot = open.id .. ":" .. open.page.key
        if W.Classify(open.page.trigger, sample) == "NEAR" then
            self.counts[slot] = (self.counts[slot] or 0) + 1
            if self.counts[slot] >= self.streak then
                self.counts = {}
                if I:Found(open.id, open.page.key, "PLACE") then return end
            end
        else
            self.counts[slot] = 0
        end
    end
end

local function ItemCount(itemID)
    local api = type(_G.C_Item) == "table" and _G.C_Item.GetItemCount or _G.GetItemCount
    local count = A.Call(api, itemID)
    return type(count) == "number" and count or 0
end

function W:CheckItems()
    if not I:Ready() then return end
    for _, open in ipairs(OpenPages("ITEM")) do
        if ItemCount(open.page.trigger.itemID) >= open.page.trigger.count then
            -- A page that waits for something else leaves the others their turn.
            if I:Found(open.id, open.page.key, "ITEM") then return end -- Found refreshes the watcher, which checks the next page.
        end
    end
end

-- For the author testing a tale written on this account: where each open place page stands from
-- here. Never offered for a kept tale (it would give the hunt away).
function W:Probe()
    local lines, sample = {}, A.Position:Sample()
    for _, following in ipairs(I:Following()) do
        local entry = I:Entry(following.id)
        if entry and entry.origin == "WRITTEN" then
            for _, page in ipairs(I.Progress.Open(following.tale, following.progress)) do
                local trigger = page.trigger
                if trigger.kind == "PLACE" then
                    local result = W.Classify(trigger, sample)
                    local distance = sample.x and sample.mapID and W.Distance(trigger, sample)
                    lines[#lines + 1] = string.format(MS.L.INK_PROBE_LINE, page.title, result,
                        distance and string.format("%.0f", distance) or "?", trigger.radius)
                end
            end
        end
    end
    if #lines == 0 then lines[1] = MS.L.INK_PROBE_NONE end
    return lines
end

-- How warm the ink is for a place page: CLOSE | WARM | COLD, or nil when the game cannot say.
-- A word only, never a distance or a direction.
W.close, W.warm = 25, 80
function W.Proximity(trigger, sample)
    sample = sample or A.Position:Sample()
    if type(sample) ~= "table" or sample.settled ~= true or type(sample.x) ~= "number" or type(sample.mapID) ~= "number" then return nil end
    local distance = W.Distance(trigger, sample)
    if not distance then return nil end
    if distance <= math.max(W.close, trigger.radius * 2.5) then return "CLOSE" end
    if distance <= math.max(W.warm, trigger.radius * 6) then return "WARM" end
    return "COLD"
end

-- How many of an item the player carries, for the reading view ("3/5").
function W.Carried(itemID) return ItemCount(itemID) end

function W:OnEnteringWorld() self.counts = {} end
function W:OnCombat() self.counts = {} end

local events = CreateFrame("Frame")
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" then
        if I:Ready() then W:CheckItems() end
    else
        W.counts = {}
    end
end)

A:Register("InkWatch", W)
