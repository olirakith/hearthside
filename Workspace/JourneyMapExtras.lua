local MS = _G.MS

-- Comfort marks on the Journey map canvas: the nearest services, dungeon entrances, the player's
-- own marker, and a line of coordinates (you, the cursor, the distance between both). Pins keep
-- their size on screen. Drawn when the map changes or a setting/marker changes; a light ticker
-- follows the cursor and the player while the map is on screen. WorldFrame is never touched.
MS.JourneyMapExtras = { pins = {}, pinSize = 20 }
local Extras = MS.JourneyMapExtras
local L = function() return MS.L end

Extras.level = "PIN_FRAME_LEVEL_HEARTHSIDE_EXTRAS"
-- The game's own map and minimap icons; "fallback" is drawn when a client lacks one of them.
local TRACKING, GOSSIP = "Interface\\Minimap\\Tracking\\", "Interface\\GossipFrame\\"
Extras.icons = {
    DUNGEON = { atlas = "dungeon", fallback = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", size = 32, fallbackSize = 20 },
    RAID = { atlas = "raid", fallback = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", size = 34, fallbackSize = 20 },
    REPAIR = { file = TRACKING .. "Repair", fallback = GOSSIP .. "VendorGossipIcon" },
    FLIGHT = { file = TRACKING .. "FlightMaster", fallback = GOSSIP .. "TaxiGossipIcon" },
    INN = { file = TRACKING .. "Innkeeper", fallback = GOSSIP .. "BinderGossipIcon" },
    TRAINER = { file = TRACKING .. "Class", fallback = GOSSIP .. "TrainerGossipIcon" },
    BANK = { file = TRACKING .. "Banker", fallback = GOSSIP .. "BankerGossipIcon" },
    AUCTION = { file = TRACKING .. "Auctioneer", fallback = GOSSIP .. "VendorGossipIcon" },
    MAILBOX = { file = TRACKING .. "Mailbox", fallback = "Interface\\Icons\\INV_Letter_15", size = 16, fallbackSize = 16 },
    MARKER = { atlas = "Waypoint-MapPin-Tracked", fallback = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", size = 28, fallbackSize = 22 },
    -- Guild and friends (JourneyFellows): a dot tinted to the class, a badge for a zone's people.
    FELLOW = { atlas = "WhiteCircle-RaidBlips", file = "Interface\\WorldMap\\WorldMapPartyIcon", fallback = "Interface\\WorldMap\\WorldMapPartyIcon", size = 13, fallbackSize = 16 },
    FELLOWS = { atlas = "socialqueuing-icon-group", fallback = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", size = 22, fallbackSize = 20 },
}
local WHITE = { 1, 1, 1 }
local SERVICE_ORDER = { "REPAIR", "FLIGHT", "INN", "TRAINER", "BANK", "AUCTION" }
local TICK = .1

local function Wanted(kind) return MS.JourneySettings:Get("mapIcon" .. kind) ~= false end

local function PlayerAt(mapID)
    local map = _G.C_Map
    if not mapID or type(map) ~= "table" or type(map.GetPlayerMapPosition) ~= "function" then return nil end
    local ok, spot = pcall(map.GetPlayerMapPosition, mapID, "player")
    if not ok or type(spot) ~= "table" or type(spot.GetXY) ~= "function" then return nil end
    local x, y = spot:GetXY()
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
    return x, y
end

local function Faction()
    local ok, faction = pcall(_G.UnitFactionGroup, "player")
    return ok and faction or nil
end

local function ShowTooltip(pin)
    local tip, lines = _G.GameTooltip, pin.lines
    if not tip or not lines or not lines[1] then return end
    tip:SetOwner(pin, "ANCHOR_RIGHT")
    tip:SetText(lines[1], 1, .82, 0)
    for index = 2, #lines do tip:AddLine(lines[index], .9, .9, .9, true) end
    tip:Show()
end

local function HideTooltip() if _G.GameTooltip then _G.GameTooltip:Hide() end end

Extras.mailboxApart = 80 -- pixels on screen

local function HasAtlas(name)
    local api = _G.C_Texture
    if type(api) ~= "table" or type(api.GetAtlasInfo) ~= "function" then return false end
    local ok, info = pcall(api.GetAtlasInfo, name)
    return ok and type(info) == "table"
end

local function HasFile(path)
    if type(_G.GetFileIDFromPath) ~= "function" then return true end
    local ok, id = pcall(_G.GetFileIDFromPath, path)
    return not ok or (type(id) == "number" and id ~= 0)
end

-- What a kind of mark is drawn with on this client, decided once: { atlas | file, size }.
function Extras:Look(kind)
    self.looks = self.looks or {}
    if not self.looks[kind] then
        local icon = self.icons[kind]
        local look = { size = icon.size or self.pinSize }
        if icon.atlas and HasAtlas(icon.atlas) then
            look.atlas = icon.atlas
        elseif icon.file and HasFile(icon.file) then
            look.file = icon.file
        else
            look.file, look.size = icon.fallback, icon.fallbackSize or self.pinSize
        end
        self.looks[kind] = look
    end
    return self.looks[kind]
end

-- Pins are reused: a texture keeps the cut of its last atlas unless it is given back.
function Extras:PaintIcon(texture, kind)
    local look = self:Look(kind)
    if not (look.atlas and pcall(texture.SetAtlas, texture, look.atlas, false)) then
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetTexture(look.file or self.icons[kind].fallback)
    end
    return look
end

function Extras:Paint(pin, kind)
    local look = self:PaintIcon(pin.icon, kind)
    pin:SetSize(look.size, look.size)
end

function Extras:Pin(index)
    local pin = self.pins[index]
    if not pin then
        pin = CreateFrame("Button", nil, self.layer)
        pin:SetSize(self.pinSize, self.pinSize)
        pin.icon = pin:CreateTexture(nil, "ARTWORK")
        pin.icon:SetAllPoints(pin)
        pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        pin:SetScript("OnEnter", ShowTooltip)
        pin:SetScript("OnLeave", HideTooltip)
        pin:SetScript("OnHide", HideTooltip)
        -- Ctrl+right click on the marker removes it; a left click on an entrance shows its dungeon.
        pin:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                if self.doors and #self.doors > 0 then MS.JourneyDungeonMap:Prepare(self.doors) end
            elseif self.kind == "MARKER" and IsControlKeyDown() then
                MS.JourneyMarker:Clear()
            end
        end)
        self.pins[index] = pin
    end
    return pin
end

-- Ctrl+right click on the map places the marker; anything else keeps its usual meaning.
local function OnCanvasClick(map, button, x, y)
    if button ~= "RightButton" or not IsControlKeyDown() or not MS.JourneyMarker then return false end
    return MS.JourneyMarker:Set(map:GetMapID(), x, y, time()) == true
end

function Extras:Attach(map)
    if self.map then return end
    local levels = map:GetPinFrameLevelsManager()
    levels:InsertFrameLevelAbove(self.level, "PIN_FRAME_LEVEL_JOURNEY_TRACE")
    local canvas = map:GetCanvas()
    local layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints(canvas)
    layer:SetFrameLevel(levels:GetValidFrameLevel(self.level))
    -- The coordinates line stays on the map frame, bottom right: it does not zoom or pan.
    local info = CreateFrame("Frame", nil, map)
    info:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", -10, 8)
    info:SetSize(1, 1)
    info:SetFrameLevel((map:GetFrameLevel() or 0) + 200)
    info.text = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info.text:SetPoint("BOTTOMRIGHT", info, "BOTTOMRIGHT")
    info.text:SetJustifyH("RIGHT")
    info.shade = info:CreateTexture(nil, "BACKGROUND")
    info.shade:SetColorTexture(0, 0, 0, .55)
    info.shade:SetPoint("TOPLEFT", info.text, "TOPLEFT", -6, 4)
    info.shade:SetPoint("BOTTOMRIGHT", info.text, "BOTTOMRIGHT", 6, -4)
    info.elapsed = 0
    info:SetScript("OnUpdate", function(_, elapsed) Extras:Tick(elapsed) end)
    self.map, self.layer, self.info = map, layer, info
    local provider = _G.CreateFromMixins(_G.MapCanvasDataProviderMixin)
    function provider:RefreshAllData() Extras:Draw() end
    function provider:OnCanvasSizeChanged() Extras:Draw() end
    function provider:OnCanvasScaleChanged() Extras:Draw() end
    map:AddDataProvider(provider)
    map:AddCanvasClickHandler(OnCanvasClick, 10)
    if MS.JourneyMarker then MS.JourneyMarker:Listen(function() Extras:Draw() end) end
    MS.JourneySettings:Listen(function(key)
        if type(key) == "string" and key:find("^mapIcon") then Extras:Draw() end
    end)
    if MS.JourneyMapServices and MS.JourneyMapServices.Listen then
        MS.JourneyMapServices:Listen(function() Extras:Draw() end)
    end
    self.provider = provider
end

-- The marks of the shown map, in drawing order: entrances, services, then the marker on top.
function Extras:Marks(mapID, px, py, height)
    local marks = {}
    if (Wanted("DUNGEON") or Wanted("RAID")) and MS.JourneyMapEntrances then
        local ok, list = pcall(MS.JourneyMapEntrances.ForMap, MS.JourneyMapEntrances, mapID)
        for _, entry in ipairs(ok and type(list) == "table" and list or {}) do
            local look = entry.raid and "RAID" or "DUNGEON"
            if Wanted(look) then
                -- One pin per spot: several instances behind one door are listed under the first.
                local lines = { entry.name or L().JOURNEY_MAP_ENTRANCE }
                for index = 2, type(entry.names) == "table" and #entry.names or 0 do lines[#lines + 1] = entry.names[index] end
                lines[#lines + 1] = entry.raid and L().JOURNEY_MAP_ENTRANCE_RAID or L().JOURNEY_MAP_ENTRANCE
                local doors = MS.JourneyDungeons and MS.JourneyDungeonMap and MS.JourneyDungeons:Behind(entry) or {}
                if #doors > 0 then lines[#lines + 1] = L().JOURNEY_DUNGEON_PREPARE end
                marks[#marks + 1] = { kind = "ENTRANCE", look = look, x = entry.x, y = entry.y, lines = lines, doors = doors }
            end
        end
    end
    if MS.JourneyMapServices then
        -- A city has dozens of mailboxes: more of them appear as the map is zoomed in.
        local okBoxes, boxes
        if Wanted("MAILBOX") then
            okBoxes, boxes = pcall(MS.JourneyMapServices.Mailboxes, MS.JourneyMapServices, mapID, Faction(),
                self.mailboxApart / (height or 600), px, py)
        end
        for _, box in ipairs(okBoxes and type(boxes) == "table" and boxes or {}) do
            marks[#marks + 1] = { kind = "MAILBOX", look = "MAILBOX", x = box.x, y = box.y, lines = { L().JOURNEY_MAP_SERVICE_MAILBOX } }
        end
        -- Nearest to the player on this map, else to the middle of the map.
        local fromX, fromY, faction = px or .5, py or .5, Faction()
        for _, kind in ipairs(SERVICE_ORDER) do
            local ok, found
            if Wanted(kind) then
                ok, found = pcall(MS.JourneyMapServices.Nearest, MS.JourneyMapServices, mapID, fromX, fromY, kind, faction)
            end
            if ok and type(found) == "table" then
                -- The service first: a repairer's own title reads "Heavy Armor Merchant".
                local lines = { L()["JOURNEY_MAP_SERVICE_" .. kind] }
                if type(found.name) == "string" and found.name ~= "" then lines[#lines + 1] = found.name end
                if type(found.subName) == "string" and found.subName ~= "" then lines[#lines + 1] = found.subName end
                marks[#marks + 1] = { kind = kind, look = kind, x = found.x, y = found.y, lines = lines }
            end
        end
    end
    if MS.JourneyFellows then
        local ok, list = pcall(MS.JourneyFellows.Marks, MS.JourneyFellows, mapID)
        for _, mark in ipairs(ok and type(list) == "table" and list or {}) do
            mark.look = mark.kind
            marks[#marks + 1] = mark
        end
    end
    local marker = MS.JourneyMarker and MS.JourneyMarker:Get()
    if marker and marker.mapID == mapID then
        marks[#marks + 1] = { kind = "MARKER", look = "MARKER", x = marker.x, y = marker.y,
            lines = { L().JOURNEY_MAP_MARKER, Extras.Coords(marker.x, marker.y), L().JOURNEY_MAP_MARKER_CLEAR } }
    end
    -- Every mark says how far it is from the player, when the player stands on this map.
    for _, mark in ipairs(marks) do
        local away = px and not mark.plain and MS.JourneyMapDistance and MS.JourneyMapDistance:Format(mapID, px, py, mark.x, mark.y)
        if away then table.insert(mark.lines, 2, away) end
    end
    return marks
end

function Extras.Coords(x, y)
    return MS.JourneyMapDistance and MS.JourneyMapDistance.Coords(x, y) or string.format("%.1f, %.1f", x * 100, y * 100)
end

function Extras:Draw()
    local map, layer = self.map, self.layer
    if not map then return end
    local mapID = map:GetMapID()
    local width, height = layer:GetWidth() or 0, layer:GetHeight() or 0
    local scale = map:GetCanvasScale()
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    local px, py = PlayerAt(mapID)
    self.drawnFrom = px and { px, py } or nil
    local marks = (mapID and width > 0 and height > 0) and self:Marks(mapID, px, py, height * scale) or {}
    for index, mark in ipairs(marks) do
        local pin = self:Pin(index)
        pin:SetScale(1 / scale)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", layer, "TOPLEFT", mark.x * width * scale, -mark.y * height * scale)
        self:Paint(pin, mark.look)
        pin.icon:SetVertexColor(unpack(mark.color or WHITE))
        if mark.count or pin.count then
            pin.count = pin.count or pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            pin.count:ClearAllPoints()
            pin.count:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", 3, -2)
            pin.count:SetText(mark.count and mark.count > 1 and tostring(mark.count) or "")
        end
        pin.kind, pin.lines, pin.doors = mark.kind, mark.lines, mark.doors
        pin:Show()
    end
    for index = #marks + 1, #self.pins do self.pins[index]:Hide() end
    self.pinCount = #marks
    self.fellowsDrawn = MS.JourneyFellows and MS.JourneyFellows.version
    self:Line()
end

-- "Levels 1-10 · You 42.3, 67.9 · Cursor 51.0, 40.2 · 230 yd north-east", or the marker hint.
function Extras:Line()
    local map, info = self.map, self.info
    if not map or not info then return end
    local mapID, parts = map:GetMapID(), {}
    local low, high
    if MS.JourneyMapEntrances then low, high = MS.JourneyMapEntrances.ZoneLevels(mapID) end
    if low and high and high > 0 then parts[#parts + 1] = string.format(L().JOURNEY_MAP_LEVELS, low, high) end
    local px, py = PlayerAt(mapID)
    if px then parts[#parts + 1] = string.format(L().JOURNEY_MAP_YOU, Extras.Coords(px, py)) end
    local over = map.ScrollContainer and map.ScrollContainer:IsMouseOver()
    if over and type(map.GetNormalizedCursorPosition) == "function" then
        local cx, cy = map:GetNormalizedCursorPosition()
        if type(cx) == "number" and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
            parts[#parts + 1] = string.format(L().JOURNEY_MAP_CURSOR, Extras.Coords(cx, cy))
            local away = px and MS.JourneyMapDistance and MS.JourneyMapDistance:Format(mapID, px, py, cx, cy)
            if away then parts[#parts + 1] = away end
        end
    end
    if over and not (MS.JourneyMarker and MS.JourneyMarker:Get()) then parts[#parts + 1] = L().JOURNEY_MAP_MARKER_HINT end
    info.text:SetText(table.concat(parts, "  ·  "))
    info:SetShown(#parts > 0)
    info.shade:SetShown(#parts > 0)
end

-- Ten times a second while the map is shown: the line follows the cursor; the services are
-- looked up again once the player has moved a little.
function Extras:Tick(elapsed)
    local info = self.info
    info.elapsed = info.elapsed + (elapsed or 0)
    if info.elapsed < TICK then return end
    info.elapsed = 0
    self:Line()
    local mapID = self.map:GetMapID()
    local px, py = PlayerAt(mapID)
    local from = self.drawnFrom
    local fellows = MS.JourneyFellows
    if fellows then fellows:AskGuild() end
    if (px == nil) ~= (from == nil) or (px and (math.abs(px - from[1]) + math.abs(py - from[2]) > .02))
        or (fellows and fellows.version ~= self.fellowsDrawn) then
        self:Draw()
    end
end

local Settings = MS.JourneySettings
-- The Settings page switches a whole group; the map's own menu (JourneyMapFilter) one kind at a time.
local function Group(id, kinds, label, hint)
    Settings:AddExternalToggle({ id = id, label = label, hint = hint,
        get = function()
            for _, kind in ipairs(kinds) do
                if Wanted(kind) then return true end
            end
            return false
        end,
        set = function(value)
            for _, kind in ipairs(kinds) do Settings:Set("mapIcon" .. kind, value) end
        end })
end
Group("showMapServices", { "REPAIR", "FLIGHT", "INN", "TRAINER", "BANK", "AUCTION", "MAILBOX" },
    MS.L.JOURNEY_SETTING_showMapServices, MS.L.JOURNEY_SETTINGS_MAP_SERVICES_HINT)
Group("showMapEntrances", { "DUNGEON", "RAID" }, MS.L.JOURNEY_SETTING_showMapEntrances, MS.L.JOURNEY_SETTINGS_MAP_ENTRANCES_HINT)
