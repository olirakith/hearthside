local MS = _G.MS

-- Pure helpers: points are map fractions (x right, y down).
local Distance = {}
MS.JourneyMapDistance = Distance

local NAMES = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local YARD_TO_METRE = 0.9144

local function WorldSize(mapID)
    local api = _G.C_Map
    if not mapID or type(api) ~= "table" or type(api.GetMapWorldSize) ~= "function" then return nil end
    local ok, w, h = pcall(api.GetMapWorldSize, mapID)
    if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
    return nil
end

local function Valid(...)
    for i = 1, select("#", ...) do
        if type((select(i, ...))) ~= "number" then return false end
    end
    return true
end

function Distance:Yards(mapID, x1, y1, x2, y2)
    if not Valid(x1, y1, x2, y2) then return nil end
    local w, h = WorldSize(mapID)
    if not w then return nil end
    local dx, dy = (x2 - x1) * w, (y2 - y1) * h
    return math.sqrt(dx * dx + dy * dy)
end

function Distance.Direction(x1, y1, x2, y2, width, height)
    if not Valid(x1, y1, x2, y2) or (x1 == x2 and y1 == y2) then return nil end
    local w = (type(width) == "number" and width > 0) and width or 1.5
    local h = (type(height) == "number" and height > 0) and height or 1
    local dx, dy = (x2 - x1) * w, (y1 - y2) * h -- dy > 0 means north
    local deg = math.deg(math.atan2(dx, dy))
    if deg < 0 then deg = deg + 360 end
    return NAMES[math.floor((deg + 22.5) / 45) % 8 + 1]
end

function Distance:Format(mapID, x1, y1, x2, y2)
    local yards = self:Yards(mapID, x1, y1, x2, y2)
    if not yards then return nil end
    local w, h = WorldSize(mapID)
    local dir = Distance.Direction(x1, y1, x2, y2, w, h)
    local L = MS.L
    if not dir or not L then return nil end
    local unit = L.JOURNEY_DISTANCE_UNIT
    local value = yards
    if unit == "m" then value = yards * YARD_TO_METRE end
    if value > 100 then value = math.floor(value / 10 + 0.5) * 10 else value = math.floor(value + 0.5) end
    return string.format(L.JOURNEY_DISTANCE_FORMAT, value, unit, L["JOURNEY_DIRECTION_" .. dir])
end

function Distance.Coords(x, y)
    if not Valid(x, y) then return nil end
    return string.format("%.1f, %.1f", x * 100, y * 100)
end
