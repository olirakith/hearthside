local MS = _G.MS

-- The player's route of the session, drawn on the Journey map. It is recorded on every map of the
-- hierarchy (zone, continent), so it reads the same at any zoom level, and it survives /reload:
-- only a new login starts it over.
MS.JourneyTrace = { maps = {}, chains = {} }
local Trace = MS.JourneyTrace

local VERSION = 1
local SAMPLE_SECONDS = 3
-- In map fractions: below MIN_STEP the player has not moved, above MAX_STEP it was no walk (hearth, portal).
local MIN_STEP = .004
local MAX_STEP = .05
local MAX_POINTS = 800
local THICKNESS = 3
local INK = { .55, .1, .07, .85 }

local function Round(value) return math.floor(value * 10000 + .5) / 10000 end

function Trace:Enabled() return MS.JourneySettings:Get("showTravelTrace") ~= false end

function Trace:Begin(isInitialLogin)
    local db = _G.MultiScreenForeverDB
    if type(db) ~= "table" then return end
    db.journey = type(db.journey) == "table" and db.journey or {}
    local saved = db.journey.trace
    if isInitialLogin or type(saved) ~= "table" or saved.version ~= VERSION or type(saved.maps) ~= "table" then
        saved = { version = VERSION, maps = {} }
        db.journey.trace = saved
    end
    self.maps, self.gap = saved.maps, true
    if not self.ticker then
        self.ticker = _G.C_Timer.NewTicker(SAMPLE_SECONDS, function() Trace:Sample() end)
    end
    self:Draw()
end

function Trace:Add(mapID, x, y)
    local entry = self.maps[mapID]
    if not entry then
        entry = { count = 0, segments = {} }
        self.maps[mapID] = entry
    end
    local segment = entry.segments[#entry.segments]
    local size = segment and #segment or 0
    local split = self.gap or size == 0
    if size > 0 then
        local dx, dy = x - segment[size - 1], y - segment[size]
        local step = math.sqrt(dx * dx + dy * dy)
        if step < MIN_STEP then return false end
        split = split or step > MAX_STEP
    end
    if split then
        segment = {}
        entry.segments[#entry.segments + 1] = segment
    end
    segment[#segment + 1] = Round(x)
    segment[#segment + 1] = Round(y)
    entry.count = entry.count + 1
    if entry.count > MAX_POINTS then
        local oldest = entry.segments[1]
        table.remove(oldest, 1)
        table.remove(oldest, 1)
        if #oldest == 0 then table.remove(entry.segments, 1) end
        entry.count = entry.count - 1
    end
    return true
end

function Trace:Chain(mapID)
    local chain = self.chains[mapID]
    if not chain then
        chain = MS.JourneyMapData:Hierarchy(mapID)
        self.chains[mapID] = chain
    end
    return chain
end

function Trace:Sample()
    if not self:Enabled() then return end
    local Data = MS.JourneyMapData
    local playerMap = Data:PlayerMapID()
    local added, shown, positioned = false, self.map and self.map:GetMapID(), false
    for _, info in ipairs(playerMap and self:Chain(playerMap) or {}) do
        local x, y = Data:PlayerPosition(info.mapID)
        if x then
            positioned = true
            if self:Add(info.mapID, x, y) and info.mapID == shown then added = true end
        end
    end
    -- An instance or a loading screen has no position: what follows starts a new stretch.
    self.gap = not positioned
    if added then self:Draw() end
end

function Trace:Attach(map)
    local levels = map:GetPinFrameLevelsManager()
    levels:InsertFrameLevelAbove("PIN_FRAME_LEVEL_JOURNEY_TRACE", "PIN_FRAME_LEVEL_QUEST_BLOB")
    local layer = CreateFrame("Frame", nil, map:GetCanvas())
    layer:SetAllPoints(map:GetCanvas())
    layer:SetFrameLevel(levels:GetValidFrameLevel("PIN_FRAME_LEVEL_JOURNEY_TRACE"))
    self.map, self.layer, self.lines = map, layer, {}
    local provider = _G.CreateFromMixins(_G.MapCanvasDataProviderMixin)
    function provider:RefreshAllData() Trace:Draw() end
    function provider:OnCanvasSizeChanged() Trace:Draw() end
    function provider:OnCanvasScaleChanged() Trace:ApplyThickness() end
    map:AddDataProvider(provider)
end

function Trace:ApplyThickness()
    if not self.map then return end
    -- The layer zooms with the map: the line keeps its width on screen.
    local thickness = THICKNESS / self.map:GetCanvasScale()
    for _, line in ipairs(self.lines) do line:SetThickness(thickness) end
end

function Trace:Line(index)
    local line = self.lines[index]
    if not line then
        line = self.layer:CreateLine(nil, "ARTWORK")
        line:SetColorTexture(INK[1], INK[2], INK[3], INK[4])
        line:SetThickness(THICKNESS / self.map:GetCanvasScale())
        self.lines[index] = line
    end
    return line
end

function Trace:Draw()
    local map, layer = self.map, self.layer
    if not map then return end
    local used = 0
    local entry = self:Enabled() and self.maps[map:GetMapID()]
    local width, height = layer:GetWidth(), layer:GetHeight()
    for _, segment in ipairs(entry and entry.segments or {}) do
        for index = 3, #segment, 2 do
            used = used + 1
            local line = self:Line(used)
            line:SetStartPoint("TOPLEFT", layer, segment[index - 2] * width, -segment[index - 1] * height)
            line:SetEndPoint("TOPLEFT", layer, segment[index] * width, -segment[index + 1] * height)
            line:Show()
        end
    end
    for index = used + 1, #self.lines do self.lines[index]:Hide() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, _, isInitialLogin) Trace:Begin(isInitialLogin) end)
