local MS = _G.MS

-- The plan of the dungeon the player is in, in place of the map while Journey follows the player.
-- Reading another map (breadcrumb, right click) leaves the plan; "Dungeon plan" brings it back.
-- The client gives no position inside, so the player picks the floor. An entrance clicked on the map
-- shows the same plan from outside, to prepare the visit.
MS.JourneyDungeonMap = { floors = {}, buttons = {}, doors = {}, tiles = {} }
local Plan = MS.JourneyDungeonMap
local Dungeons = MS.JourneyDungeons
local BUTTON_HEIGHT, BUTTON_GAP, EDGE = 26, 4, 10

local function Fill(frame, r, g, b, alpha)
    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(frame)
    texture:SetColorTexture(r, g, b, alpha)
    return texture
end

local function Text(parent, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetWordWrap(true)
    return label
end

-- True once for each way in or out. The first look only remembers where the player is.
function Plan:Check()
    local current = Dungeons:Current()
    local id = current and current.id or 0
    local moved = self.seen ~= nil and self.seen ~= id
    self.seen = id
    return moved
end

-- The dungeon whose plan stands in place of the map, if any.
function Plan:Dungeon()
    if self.preview then return self.preview.list[self.preview.index] end
    if MS.MapView.mode ~= "FOLLOW_PLAYER" then return nil end
    return Dungeons:Current()
end

-- The map to keep under the plan: the zone of the entrance, else where the player was last seen.
function Plan:ZoneMap()
    local dungeon = Dungeons:Current()
    if not dungeon then return nil end
    for _, id in ipairs({ dungeon.zone or 0, MS.MapView.mapID or 0, MS.MapView.savedMapID or 0 }) do
        if id > 0 and MS.JourneyMapData:Info(id) then return id end
    end
end

-- Reading, like any map the player chose: it ends with another map, or where it began.
function Plan:Prepare(list)
    local view = MS.MapView
    if not list or #list == 0 or not view.mapID then return end
    self.preview = { list = list, index = 1, mapID = view.mapID, mode = view.mode }
    view:SetMode("MANUAL_MAP")
    self:Redraw()
end

function Plan:Pick(index)
    if not self.preview or not self.preview.list[index] then return end
    self.preview.index = index
    self:Redraw()
end

function Plan:Redraw()
    local view = MS.MapView
    if MS.JourneyMapCanvas then MS.JourneyMapCanvas:Sync(view.mapID) end
    view:RefreshBreadcrumb()
    view:RenderSidebar()
    view:RefreshZoneStrip()
end

function Plan:ClosePreview() self.preview = nil end

function Plan:Leave()
    local view, preview = MS.MapView, self.preview
    if preview then
        self:ClosePreview()
        if preview.mode == "FOLLOW_PLAYER" and not Dungeons:Current() then
            view:SetMode(preview.mode)
            if view:FollowPlayerMap("DUNGEON_PREVIEW_CLOSED", true) then return true end
        end
    end
    if view.mapID then return view:Navigate(view.mapID) end
end

function Plan:Build()
    local view = MS.MapView
    local frame = CreateFrame("Frame", nil, view.mapPanel)
    frame:SetAllPoints(view.canvas)
    frame:SetFrameLevel(view.canvas:GetFrameLevel() + 30)
    frame:Hide()
    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Plan:Leave() end
    end)
    frame:SetScript("OnSizeChanged", function() Plan:Fit() end)
    Fill(frame, .05, .04, .03, 1)
    frame.sheet = CreateFrame("Frame", nil, frame)
    for index = 1, Dungeons.TILES do
        self.tiles[index] = frame.sheet:CreateTexture(nil, "ARTWORK")
    end
    frame.probe = frame:CreateTexture(nil, "BACKGROUND")
    frame.probe:SetSize(1, 1)
    frame.probe:SetAlpha(0)
    frame.missing = Text(frame, "GameFontNormalLarge")
    frame.missing:SetPoint("CENTER", frame, "CENTER")
    frame.missing:SetJustifyH("CENTER")
    frame.hint = CreateFrame("Button", nil, frame)
    frame.hint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -EDGE, EDGE)
    frame.hint.shade = Fill(frame.hint, 0, 0, 0, .65)
    frame.hint.label = Text(frame.hint, "GameFontHighlight")
    frame.hint.label:SetPoint("CENTER", frame.hint, "CENTER")
    frame.hint:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame.hint:SetScript("OnEnter", function() frame.hint.shade:SetColorTexture(.25, .2, .12, .9) end)
    frame.hint:SetScript("OnLeave", function() frame.hint.shade:SetColorTexture(0, 0, 0, .65) end)
    frame.hint:SetScript("OnClick", function() Plan:Leave() end)
    self.frame = frame
end

-- The sheet keeps the art's shape, as large as the map allows.
function Plan:Fit()
    local frame = self.frame
    local width, height = frame:GetWidth() or 0, frame:GetHeight() or 0
    if width <= 0 or height <= 0 then return end
    local D = Dungeons
    local scale = math.min(width / D.WIDTH, height / D.HEIGHT)
    frame.sheet:ClearAllPoints()
    frame.sheet:SetPoint("CENTER", frame, "CENTER")
    frame.sheet:SetSize(D.WIDTH * scale, D.HEIGHT * scale)
    for index, tile in ipairs(self.tiles) do
        local column, row = (index - 1) % D.COLUMNS, math.floor((index - 1) / D.COLUMNS)
        local w, h = math.min(D.TILE, D.WIDTH - column * D.TILE), math.min(D.TILE, D.HEIGHT - row * D.TILE)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", frame.sheet, "TOPLEFT", column * D.TILE * scale, -row * D.TILE * scale)
        tile:SetSize(w * scale, h * scale)
        tile:SetTexCoord(0, w / D.TILE, 0, h / D.TILE)
    end
    frame.missing:SetWidth(width * .7)
    self:PlaceButtons()
end

function Plan:Button(row, index, click)
    local button = row[index]
    if button then return button end
    button = CreateFrame("Button", nil, self.frame)
    button:SetFrameLevel(self.frame:GetFrameLevel() + 10)
    button.shade = Fill(button, 0, 0, 0, .65)
    button.label = Text(button, "GameFontNormal")
    button.label:SetPoint("CENTER", button, "CENTER")
    button:SetScript("OnEnter", function() button.label:SetTextColor(1, 1, 1) end)
    button:SetScript("OnLeave", function() Plan:PaintButtons() end)
    button:SetScript("OnClick", function() click(index) end)
    row[index] = button
    return button
end

-- The dungeons behind one door first, then the floors; a row is wrapped on a small map.
function Plan:PlaceButtons()
    local y, room = EDGE, (self.frame:GetWidth() or 0) - EDGE
    for _, row in ipairs({ { self.doors, self.doorCount }, { self.buttons, self.floorCount } }) do
        local x = EDGE
        for index = 1, row[2] or 0 do
            local button = row[1][index]
            local width = button:GetWidth()
            if x > EDGE and x + width > room then x, y = EDGE, y + BUTTON_HEIGHT + BUTTON_GAP end
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
            x = x + width + BUTTON_GAP
        end
        if (row[2] or 0) > 0 then y = y + BUTTON_HEIGHT + BUTTON_GAP end
    end
end

local function PaintRow(buttons, current)
    for index, button in ipairs(buttons) do
        local on = index == current
        button.shade:SetColorTexture(on and .42 or 0, on and .31 or 0, on and .14 or 0, on and .95 or .65)
        button.label:SetTextColor(1, on and 1 or .82, on and 1 or 0)
    end
end

function Plan:PaintButtons()
    PaintRow(self.buttons, self.floor)
    PaintRow(self.doors, self.preview and self.preview.index)
end

function Plan:SetFloor(floor)
    local dungeon = self.drawn
    if not dungeon then return end
    self.floor = math.max(1, math.min(floor, dungeon.floors))
    self.floors[dungeon.id] = self.floor -- for this session, so leaving and coming back keeps it
    for index, tile in ipairs(self.tiles) do tile:SetTexture(Dungeons:Tile(dungeon, self.floor, index)) end
    self:PaintButtons()
end

function Plan:FillRow(row, count, name, click)
    for index = 1, count do
        local button = self:Button(row, index, click)
        button.label:SetText(name(index))
        button:SetSize((button.label:GetStringWidth() or 60) + 22, BUTTON_HEIGHT)
        button:Show()
    end
    for index = count + 1, #row do row[index]:Hide() end
end

function Plan:Draw(dungeon)
    if not self.frame then self:Build() end
    local frame = self.frame
    self.drawn = dungeon
    local art = Dungeons:HasArt(dungeon, frame.probe)
    MS.MapView.status.dungeonArt = art
    frame.sheet:SetShown(art)
    frame.missing:SetShown(not art)
    self.floorCount = art and dungeon.floors > 1 and dungeon.floors or 0
    self:FillRow(self.buttons, self.floorCount, function(index) return Dungeons:FloorName(dungeon, index) end,
        function(index) Plan:SetFloor(index) end)
    local list = self.preview and self.preview.list or {}
    self.doorCount = #list > 1 and #list or 0
    self:FillRow(self.doors, self.doorCount, function(index) return list[index].name end, function(index) Plan:Pick(index) end)
    if art then
        self:SetFloor(self.floors[dungeon.id] or 1)
    else
        frame.missing:SetText(dungeon.name .. "\n\n" .. MS.L.JOURNEY_DUNGEON_NO_PLAN)
    end
    local zone = MS.JourneyMapData:Info(MS.MapView.mapID)
    frame.hint:SetShown(zone ~= nil)
    if zone then
        frame.hint.label:SetText(MS.L.JOURNEY_DUNGEON_BACK:format(zone.name or ""))
        frame.hint:SetSize((frame.hint.label:GetStringWidth() or 120) + 22, BUTTON_HEIGHT)
    end
    self:PaintButtons()
    frame:Show()
    self:Fit()
end

-- Draws or removes the plan; tells the map whether it must stay hidden behind it.
function Plan:Sync()
    local view = MS.MapView
    if not view.mapPanel then return false end
    if self.preview and self.preview.mapID ~= view.mapID then self:ClosePreview() end
    local dungeon = self:Dungeon()
    local inside = Dungeons:Current()
    local shown = dungeon or inside
    view.status.dungeonID = shown and shown.id or nil
    if view.playerButton then
        view.playerButton.label:SetText(inside and MS.L.JOURNEY_DUNGEON_PLAN or MS.L.JOURNEY_MAP_PLAYER_MAP)
        local width = inside and 124 or 104
        view.playerButton:SetWidth(width)
        view.playerButton.label:SetWidth(width - 10)
    end
    if dungeon then
        self:Draw(dungeon)
        return true
    end
    self.drawn = nil
    if self.frame then self.frame:Hide() end
    return false
end
