local MS = _G.MS
MS.Ink = MS.Ink or {}
-- The tales on the Journey map: what Chart allows, drawn on the map canvas. Areas (a circle to
-- search, a place's radius) are sized in the world and zoom with the map; pins keep their size on
-- screen. A band of words under them says what the map cannot show (a hunt's page, the author's
-- view). Drawn when the map shows or a tale changes: no timer.
local I = MS.Ink
local T = I.Theme

local function L() return MS.L end

local Layer = { pinSize = 22, minArea = 14, maxChips = 3, areas = {}, pins = {}, chips = {} }
I.MapLayer = Layer
Layer.blot = "Interface\\AddOns\\" .. (MS.addonName or "Hearthside") .. "\\Media\\InkBlot"
Layer.level = "PIN_FRAME_LEVEL_HEARTHSIDE_INK"

-- kind -> area colour and alpha.
local AREA = {
    SEARCH = { "gold", .42 }, GOAL = { "goldBright", .30 }, AUTHOR = { "wax", .34 }, AUTHOR_SELECTED = { "wax", .55 },
}

local function Tooltip(button)
    local tip, lines = _G.GameTooltip, button.lines
    if not tip or type(tip.SetOwner) ~= "function" or not lines or not lines[1] then return end
    tip:SetOwner(button, "ANCHOR_RIGHT")
    tip:SetText(lines[1], .94, .78, .43)
    for index = 2, #lines do tip:AddLine(lines[index], .95, .92, .84, true) end
    tip:Show()
end

local function HideTooltip()
    local tip = _G.GameTooltip
    if tip and type(tip.Hide) == "function" then tip:Hide() end
end

-- A click leads to the book, or back to the workshop for the author's own places.
local function Open(button)
    local mark = button.mark
    if not mark then return end
    if mark.kind == "AUTHOR" then I:OpenTab("WORKSHOP", mark.id, mark.key) else I:OpenTab("BOOK", mark.id) end
end

local function Wire(button)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", HideTooltip)
    button:SetScript("OnHide", HideTooltip)
    button:SetScript("OnClick", Open)
end

function Layer:Area(index)
    local area = self.areas[index]
    if not area then
        area = CreateFrame("Button", nil, self.layer)
        area.blot = area:CreateTexture(nil, "ARTWORK")
        area.blot:SetAllPoints(area)
        area.blot:SetTexture(self.blot)
        Wire(area)
        self.areas[index] = area
    end
    return area
end

function Layer:Pin(index)
    local pin = self.pins[index]
    if not pin then
        pin = CreateFrame("Button", nil, self.layer)
        pin:SetSize(self.pinSize, self.pinSize)
        pin.rim = T.Disc(pin, self.pinSize, "onGold", "BORDER")
        pin.rim:SetPoint("CENTER", pin, "CENTER")
        pin.disc = T.Disc(pin, self.pinSize - 4, "wax", "ARTWORK")
        pin.disc:SetPoint("CENTER", pin, "CENTER")
        pin.check = pin:CreateTexture(nil, "OVERLAY")
        pin.check:SetTexture(T.check)
        pin.check:SetSize(self.pinSize - 6, self.pinSize - 6)
        pin.check:SetPoint("CENTER", pin, "CENTER")
        pin.dot = T.Disc(pin, 6, "onGold", "OVERLAY")
        pin.dot:SetPoint("CENTER", pin, "CENTER")
        pin.label = T.Text(pin, "UI_BOLD", 11, "waxText", "CENTER")
        pin.label:SetPoint("CENTER", pin, "CENTER", 0, 0)
        if type(pin.label.SetWordWrap) == "function" then pin.label:SetWordWrap(false) end
        Wire(pin)
        self.pins[index] = pin
    end
    return pin
end

function Layer:Chip(index)
    local chip = self.chips[index]
    if not chip then
        chip = CreateFrame("Button", nil, self.band)
        chip:SetHeight(26)
        chip.edge = T.Fill(chip, "gold", "BACKGROUND", .7)
        chip.back = chip:CreateTexture(nil, "BORDER")
        chip.back:SetPoint("TOPLEFT", chip, "TOPLEFT", 1, -1)
        chip.back:SetPoint("BOTTOMRIGHT", chip, "BOTTOMRIGHT", -1, 1)
        T.Color(chip.back, "shellDeep", .92)
        chip.label = T.Text(chip, "UI", 13, "text")
        chip.label:SetPoint("LEFT", chip, "LEFT", 10, 0)
        if type(chip.label.SetWordWrap) == "function" then chip.label:SetWordWrap(false) end
        chip:SetScript("OnClick", Open)
        self.chips[index] = chip
    end
    return chip
end

local function Title(text) return type(text) == "string" and text ~= "" and text or L().INK_UNTITLED end

-- What a mark says when hovered. Never more than its mode allows.
function Layer.Lines(mark, draft)
    local page = mark.page
    if mark.kind == "AUTHOR" then
        return { Title(draft and draft.title), string.format(L().INK_MAP_AUTHOR_PAGE, mark.number, Title(page.title)),
            string.format(L().INK_RADIUS, page.trigger.radius), L().INK_MAP_CLICK_WORKSHOP }
    end
    local lines = { mark.tale.title }
    if mark.kind == "FOUND" then
        lines[2] = string.format(L().INK_MAP_FOUND, page.title)
    elseif mark.kind == "SEARCH" then
        lines[2] = L().INK_MAP_SEARCH
    else
        lines[2] = string.format(L().INK_MAP_GOAL, page.title)
    end
    if mark.kind ~= "FOUND" and type(page.hint) == "string" and page.hint ~= "" then lines[#lines + 1] = page.hint end
    lines[#lines + 1] = L().INK_MAP_CLICK_BOOK
    return lines
end

function Layer:Attach(map)
    if self.map then return end
    local levels = map:GetPinFrameLevelsManager()
    levels:InsertFrameLevelAbove(self.level, "PIN_FRAME_LEVEL_JOURNEY_TRACE")
    local canvas = map:GetCanvas()
    local layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints(canvas)
    layer:SetFrameLevel(levels:GetValidFrameLevel(self.level))
    layer:SetScript("OnShow", function() Layer:Draw() end)
    -- Words stay on the map's frame: they do not zoom or pan with it.
    local band = CreateFrame("Frame", nil, map)
    band:SetPoint("BOTTOMLEFT", map, "BOTTOMLEFT", 10, 10)
    band:SetSize(1, 1)
    band:SetFrameLevel((map:GetFrameLevel() or 0) + 200)
    self.map, self.layer, self.band = map, layer, band
    local provider = _G.CreateFromMixins(_G.MapCanvasDataProviderMixin)
    function provider:RefreshAllData() Layer:Draw() end
    function provider:OnCanvasSizeChanged() Layer:Draw() end
    function provider:OnCanvasScaleChanged() Layer:Draw() end
    map:AddDataProvider(provider)
    self.provider = provider
end

-- A tale or a draft changed: redraw now when the map is on screen, else when it shows again.
function Layer:Changed()
    if not self.layer then return end
    if self.layer:IsVisible() then self:Draw() else self.dirty = true end
end

function Layer:Draw()
    local map, layer = self.map, self.layer
    if not map then return end
    self.dirty = false
    local shown = map:GetMapID()
    local width, height = layer:GetWidth() or 0, layer:GetHeight() or 0
    local scale = map:GetCanvasScale()
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    local marks, hints, author, draft = {}, {}, {}, nil
    if width > 0 and height > 0 then
        marks, hints = I.Chart:Marks(shown)
        author, draft = I.Chart:AuthorMarks(shown)
    end
    local areas, pins = 0, 0
    local function Place(mark)
        local lines = Layer.Lines(mark, draft)
        if mark.kind ~= "FOUND" then
            areas = areas + 1
            local area = self:Area(areas)
            local style = AREA[mark.selected and "AUTHOR_SELECTED" or mark.kind]
            local color = T.colors[style[1]]
            area.blot:SetVertexColor(color[1], color[2], color[3], style[2])
            local size = math.max(mark.radiusX and mark.radiusX * width * 2 or 0, self.minArea * 2 / scale)
            area:SetSize(size, size)
            area:ClearAllPoints()
            area:SetPoint("CENTER", layer, "TOPLEFT", mark.x * width, -mark.y * height)
            -- Only a search circle is a target of its own; a place has its pin.
            area:EnableMouse(mark.kind == "SEARCH")
            area.mark, area.lines = mark, lines
            area:Show()
        end
        if mark.kind ~= "SEARCH" then
            pins = pins + 1
            local pin = self:Pin(pins)
            pin:SetScale(1 / scale)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", layer, "TOPLEFT", mark.x * width * scale, -mark.y * height * scale)
            local found, goal = mark.kind == "FOUND", mark.kind == "GOAL"
            T.Color(pin.disc, goal and "goldBright" or "wax")
            pin.check:SetShown(found)
            pin.dot:SetShown(goal)
            pin.label:SetShown(mark.kind == "AUTHOR")
            pin.label:SetText(mark.number and tostring(mark.number) or "")
            pin.mark, pin.lines = mark, lines
            pin:Show()
        end
    end
    for _, mark in ipairs(marks) do Place(mark) end
    for _, mark in ipairs(author) do Place(mark) end
    for index = areas + 1, #self.areas do self.areas[index]:Hide() end
    for index = pins + 1, #self.pins do self.pins[index]:Hide() end
    self.areaCount, self.pinCount = areas, pins

    -- The band: the author's view first, then hunts whose page hides on this map.
    local words = {}
    if draft and #author > 0 then
        words[1] = { text = string.format(L().INK_MAP_AUTHOR, Title(draft.title), #author),
            mark = { kind = "AUTHOR", id = draft.id, key = author[1].key } }
    end
    for _, hint in ipairs(hints) do
        words[#words + 1] = { text = string.format(L().INK_MAP_HINT, hint.tale.title), mark = { kind = "HINT", id = hint.id } }
    end
    local y, limit = 0, math.max(120, (map:GetWidth() or 0) - 20)
    for index = 1, math.min(#words, self.maxChips) do
        local chip = self:Chip(index)
        chip.label:SetText(words[index].text)
        chip.mark = words[index].mark
        chip:SetWidth(math.min(limit, (chip.label:GetStringWidth() or 0) + 20))
        chip.label:SetWidth(chip:GetWidth() - 20)
        chip:ClearAllPoints()
        chip:SetPoint("BOTTOMLEFT", self.band, "BOTTOMLEFT", 0, y)
        chip:Show()
        y = y + 30
    end
    for index = math.min(#words, self.maxChips) + 1, #self.chips do self.chips[index]:Hide() end
    self.chipCount = math.min(#words, self.maxChips)
end
