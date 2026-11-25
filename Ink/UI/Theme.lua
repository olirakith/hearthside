local MS = _G.MS
MS.Ink = MS.Ink or {}
-- The look of L'Encre (and of the Hearthside home cards): three bundled fonts (SIL OFL, see
-- Media/Fonts), a dark shell for lists and controls, parchment for what is read and written, and
-- a handful of widgets built from plain textures. No Blizzard template, nothing protected.
local A = MS.Active
local I = MS.Ink
local Theme = {}
I.Theme = Theme

Theme.fontPath = "Interface\\AddOns\\" .. (MS.addonName or "Hearthside") .. "\\Media\\Fonts\\"
Theme.faces = {
    TITLE = "Cinzel-Bold.ttf",
    UI = "AlegreyaSans-Regular.ttf",
    UI_BOLD = "AlegreyaSans-Bold.ttf",
    INK = "IMFellEnglish-Regular.ttf",
    INK_ITALIC = "IMFellEnglish-Italic.ttf",
}
-- Tokens: one table, so the whole look can move together.
Theme.colors = {
    shell = { .086, .071, .055, 1 }, shellDeep = { .063, .052, .040, 1 }, raised = { .145, .118, .090, 1 },
    selected = { .200, .163, .120, 1 }, line = { .290, .235, .170, 1 }, lineSoft = { .200, .165, .122, 1 },
    text = { .953, .918, .839, 1 }, textSoft = { .800, .757, .690, 1 }, muted = { .640, .600, .545, 1 },
    gold = { .847, .651, .290, 1 }, goldBright = { .941, .776, .431, 1 }, onGold = { .102, .078, .039, 1 },
    warning = { .878, .627, .498, 1 }, success = { .561, .753, .627, 1 },
    paper = { .937, .894, .800, 1 }, paperDeep = { .898, .847, .741, 1 }, paperLine = { .804, .733, .596, 1 },
    paperField = { 1, 1, 1, .32 }, ink = { .169, .129, .094, 1 }, inkSoft = { .420, .353, .271, 1 },
    wax = { .620, .231, .173, 1 }, waxText = { .965, .863, .804, 1 },
    track = { .180, .150, .115, 1 },
}
-- Mode chips: background, text.
Theme.modes = {
    NOTES = { { .110, .160, .160, 1 }, { .663, .839, .796, 1 }, "Interface\\Icons\\INV_Misc_Note_01" },
    HUNT = { { .170, .149, .098, 1 }, { .902, .761, .478, 1 }, "Interface\\Icons\\INV_Misc_Map_01" },
    QUEST = { { .172, .125, .153, 1 }, { .906, .714, .757, 1 }, "Interface\\Icons\\INV_Scroll_03" },
}
Theme.kinds = {
    PLACE = { { .561, .753, .706, 1 }, "Interface\\Icons\\INV_Misc_Map_01" },
    ANSWER = { { .788, .655, .890, 1 }, "Interface\\Icons\\INV_Misc_QuestionMark" },
    ITEM = { { .902, .761, .478, 1 }, "Interface\\Icons\\INV_Misc_Bag_08" },
    NPC = { { .663, .839, .796, 1 }, "Interface\\Icons\\INV_Letter_15" },
    EMOTE = { { .906, .714, .757, 1 }, "Interface\\Icons\\Spell_Holy_PrayerOfHealing" },
    KILL = { { .878, .627, .498, 1 }, "Interface\\Icons\\INV_Sword_04" },
}
Theme.grain = "Interface\\AddOns\\" .. (MS.addonName or "Hearthside") .. "\\Media\\JourneyGrain"
Theme.halo = "Interface\\AddOns\\" .. (MS.addonName or "Hearthside") .. "\\Media\\JourneySelectedHalo"
Theme.round = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
Theme.check = "Interface\\Buttons\\UI-CheckBox-Check"

local function C(token) return Theme.colors[token] or token end

function Theme.Color(texture, token, alpha)
    local color = type(token) == "table" and token or C(token)
    if not texture or type(color) ~= "table" then return end
    texture:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
end

function Theme.TextColor(label, token)
    local color = type(token) == "table" and token or C(token)
    if label and type(color) == "table" then label:SetTextColor(color[1], color[2], color[3]) end
end

-- Text follows the Journey text size, like every other Journey view.
local labels = setmetatable({}, { __mode = "k" })

local function Scale()
    local settings = MS.JourneySettings
    local value = settings and settings.Get and settings:Get("textScale")
    return type(value) == "number" and value or 1.1
end

-- The Hearthside window scales as a whole with the text size (Kit.Zoom): text drawn inside it
-- keeps the size it was drawn at, or it would grow twice.
local function InPanel(object)
    local panel = A.Panel and A.Panel.frame
    local node, depth = object, 0
    while panel and type(node) == "table" and depth < 16 do
        if node == panel then return true end
        local ok, parent = pcall(node.GetParent, node)
        node, depth = ok and parent or nil, depth + 1
    end
    return false
end

local function ApplyFont(object, face, size, fixed)
    local path = Theme.fontPath .. (Theme.faces[face] or Theme.faces.UI)
    local points = size * (fixed and (A.Kit and A.Kit.baseScale or 1.1) or Scale())
    local ok, result = pcall(object.SetFont, object, path, points, "")
    if not ok or result == false then
        -- The file did not load: the game's own font at the same size.
        local fallback = _G.GameFontNormal and _G.GameFontNormal.GetFont and _G.GameFontNormal:GetFont()
        if fallback then pcall(object.SetFont, object, fallback, points, "") end
    end
end

function Theme.SetFont(object, face, size)
    local spec = labels[object]
    local fixed = spec and spec[3]
    if fixed == nil then fixed = InPanel(object) end
    labels[object] = { face, size, fixed }
    ApplyFont(object, face, size, fixed)
end

-- A text: face (TITLE, UI, UI_BOLD, INK, INK_ITALIC), size in Journey points, colour token.
function Theme.Text(parent, face, size, color, justify)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Theme.SetFont(label, face, size)
    Theme.TextColor(label, color or "text")
    label:SetJustifyH(justify or "LEFT")
    if type(label.SetJustifyV) == "function" then label:SetJustifyV("TOP") end
    if type(label.SetWordWrap) == "function" then label:SetWordWrap(true) end
    -- Light text on the shell keeps a faint shadow; ink on paper has none.
    local paper = color == "ink" or color == "inkSoft" or color == "wax"
    if type(label.SetShadowOffset) == "function" then label:SetShadowOffset(paper and 0 or 1, paper and 0 or -1) end
    if type(label.SetShadowColor) == "function" then label:SetShadowColor(0, 0, 0, paper and 0 or .55) end
    if paper and type(label.SetSpacing) == "function" then label:SetSpacing(3) end
    return label
end

-- WoW can draw a text blank the first time an addon font file is used. Every face is touched
-- once at load, and Touch() draws every label again once the files are in.
Theme.warm = CreateFrame("Frame", nil, _G.UIParent)
Theme.warm:SetSize(1, 1)
Theme.warm:SetAlpha(0)
for face in pairs(Theme.faces) do
    local label = Theme.warm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pcall(label.SetFont, label, Theme.fontPath .. Theme.faces[face], 14, "")
    label:SetPoint("TOPLEFT", Theme.warm, "TOPLEFT")
    label:SetText("Aa Éé ‹ › · 0123")
end

function Theme.Touch()
    for object, spec in pairs(labels) do
        local text = object.GetText and object:GetText()
        ApplyFont(object, spec[1], spec[2], spec[3])
        if text and text ~= "" then object:SetText(""); object:SetText(text) end
    end
end

Theme.Scale = Scale

-- The height one line of this size takes on screen (font box plus the paper line spacing).
function Theme.LineHeight(size, paper)
    return math.floor(size * Scale() * 1.3 + (paper and 3 or 0) + .5)
end

-- At most this many lines (0: no limit); the rest ends on an ellipsis.
function Theme.MaxLines(label, lines)
    if type(label.SetMaxLines) == "function" then label:SetMaxLines(math.max(0, lines or 0)) end
end

-- The full width of a text, whatever room its label has.
function Theme.Width(label)
    if type(label.GetUnboundedStringWidth) == "function" then
        local ok, width = pcall(label.GetUnboundedStringWidth, label)
        if ok and type(width) == "number" then return width end
    end
    return label:GetStringWidth() or 0
end

function Theme.Rescale()
    for object, spec in pairs(labels) do if not spec[3] then ApplyFont(object, spec[1], spec[2], false) end end
end

local Settings = MS.JourneySettings
if Settings and Settings.Listen then Settings:Listen(function(key) if key == "textScale" then Theme.Rescale() end end) end

-- Surfaces -------------------------------------------------------------------------------------
function Theme.Fill(parent, token, layer, alpha)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints(parent)
    Theme.Color(texture, token, alpha)
    return texture
end

-- A colour multiplied over the Journey grain, so a surface does not read as a flat fill.
function Theme.Grain(texture, token)
    local color = C(token)
    Theme.Color(texture, token)
    local ok, result = pcall(texture.SetTexture, texture, Theme.grain, "REPEAT", "REPEAT")
    if not ok or result == false then return end
    if type(texture.SetHorizTile) == "function" then texture:SetHorizTile(true) end
    if type(texture.SetVertTile) == "function" then texture:SetVertTile(true) end
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

-- A soft shade inside an edge (a page's spine, a vignette). Flat when gradients are missing.
function Theme.Shade(parent, side, depth, token, alpha)
    local texture = parent:CreateTexture(nil, "BORDER")
    local horizontal = side == "LEFT" or side == "RIGHT"
    texture:SetPoint(side == "RIGHT" and "TOPRIGHT" or side == "BOTTOM" and "BOTTOMLEFT" or "TOPLEFT", parent)
    if horizontal then
        texture:SetPoint(side == "RIGHT" and "BOTTOMRIGHT" or "BOTTOMLEFT", parent)
        texture:SetWidth(depth)
    else
        texture:SetPoint(side == "BOTTOM" and "BOTTOMRIGHT" or "TOPRIGHT", parent)
        texture:SetHeight(depth)
    end
    local color = C(token or "inkSoft")
    texture:SetColorTexture(1, 1, 1, 1)
    local strong, clear = { color[1], color[2], color[3], alpha or .22 }, { color[1], color[2], color[3], 0 }
    local from, to = strong, clear
    if side == "RIGHT" or side == "TOP" then from, to = clear, strong end
    local done = false
    if type(_G.CreateColor) == "function" then
        done = pcall(texture.SetGradient, texture, horizontal and "HORIZONTAL" or "VERTICAL",
            _G.CreateColor(unpack(from)), _G.CreateColor(unpack(to)))
    end
    if not done and type(texture.SetGradientAlpha) == "function" then
        done = pcall(texture.SetGradientAlpha, texture, horizontal and "HORIZONTAL" or "VERTICAL",
            from[1], from[2], from[3], from[4], to[1], to[2], to[3], to[4])
    end
    if not done then texture:SetColorTexture(color[1], color[2], color[3], (alpha or .22) / 3) end
    return texture
end

-- A panel with a 1 px edge.
function Theme.Box(parent, fill, edge)
    local frame = CreateFrame("Frame", nil, parent)
    frame.edge = Theme.Fill(frame, edge or "line", "BACKGROUND")
    frame.back = frame:CreateTexture(nil, "BORDER")
    frame.back:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.back:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    Theme.Color(frame.back, fill or "raised")
    return frame
end

-- A sheet of parchment, shaded at its edges. spine: "LEFT" / "RIGHT" for a book's inner fold.
function Theme.Parchment(parent, spine)
    local frame = CreateFrame("Frame", nil, parent)
    frame.paper = frame:CreateTexture(nil, "BACKGROUND")
    frame.paper:SetAllPoints(frame)
    Theme.Grain(frame.paper, "paper")
    for _, side in ipairs({ "LEFT", "RIGHT", "TOP", "BOTTOM" }) do
        frame["shade" .. side] = Theme.Shade(frame, side, side == spine and 36 or 18, "inkSoft", side == spine and .38 or .16)
    end
    return frame
end

-- A round mark (a wax seal, a dot): a mask when the client has one, else a small square.
function Theme.Disc(parent, size, token, layer)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetSize(size, size)
    Theme.Color(texture, token)
    if type(parent.CreateMaskTexture) == "function" and type(texture.AddMaskTexture) == "function" then
        local mask = parent:CreateMaskTexture()
        local ok = mask and pcall(mask.SetTexture, mask, Theme.round, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        if ok then
            mask:SetAllPoints(texture)
            pcall(texture.AddMaskTexture, texture, mask)
        end
    end
    return texture
end

function Theme.Icon(parent, size, path)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetTexture(path)
    icon:SetTexCoord(.08, .92, .08, .92)
    return icon
end

-- Buttons ----------------------------------------------------------------------------------------
-- kind: PRIMARY (gold), SECONDARY (outlined), GHOST (text only), DASHED (an "add" slot),
-- PAPER (outlined on parchment).
local palette = {
    PRIMARY = { "gold", "goldBright", "gold", "onGold", "onGold" },
    SECONDARY = { "shell", "raised", "line", "text", "text" },
    GHOST = { nil, "raised", nil, "textSoft", "text" },
    DASHED = { nil, "raised", "lineSoft", "textSoft", "text" },
    PAPER = { "paperDeep", "paper", "paperLine", "ink", "ink" },
}

local function PaintButton(button)
    local p = palette[button.kind] or palette.SECONDARY
    local enabled = button.disabled ~= true
    local lit = enabled and (button.hovered or button.selected)
    local fill = lit and p[2] or p[1]
    button.back:SetShown(fill ~= nil)
    if fill then Theme.Color(button.back, fill) end
    button.edge:SetShown(p[3] ~= nil)
    if p[3] then Theme.Color(button.edge, button.selected and "gold" or p[3]) end
    Theme.TextColor(button.label, lit and p[5] or p[4])
    button:SetAlpha(enabled and 1 or .45)
end

function Theme.Button(parent, kind, text, onClick, width, height)
    local button = CreateFrame("Button", nil, parent)
    button.kind = kind or "SECONDARY"
    button.hovered, button.selected, button.disabled = false, false, false
    button:SetSize(width or 120, height or 30)
    button.edge = Theme.Fill(button, "line", "BACKGROUND")
    button.back = button:CreateTexture(nil, "BORDER")
    button.back:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.back:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.label = Theme.Text(button, button.kind == "PRIMARY" and "UI_BOLD" or "UI", 14, "text", "CENTER")
    button.label:SetPoint("LEFT", button, "LEFT", 8, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    if type(button.label.SetJustifyV) == "function" then button.label:SetJustifyV("MIDDLE") end
    button.label:SetText(text or "")
    button:SetScript("OnEnter", function(self) self.hovered = true; PaintButton(self) end)
    button:SetScript("OnLeave", function(self) self.hovered = false; PaintButton(self) end)
    button:SetScript("OnHide", function(self) self.hovered = false; PaintButton(self) end)
    button:SetScript("OnClick", function(self) if self.disabled ~= true and onClick then onClick(self) end end)
    function button:SetLabel(value) self.label:SetText(value or "") end
    function button:SetSelected(value) self.selected = value == true; PaintButton(self) end
    function button:SetActive(value) self.disabled = value == false; PaintButton(self) end
    -- Width from the label, within bounds.
    function button:Fit(minimum, maximum)
        local width = (self.label:GetStringWidth() or 0) + 32
        self:SetWidth(math.max(minimum or 60, math.min(maximum or 400, width)))
        return self:GetWidth()
    end
    PaintButton(button)
    return button
end

-- A button that asks once before acting.
function Theme.Confirm(parent, kind, text, confirm, act, width, height)
    local button
    button = Theme.Button(parent, kind, text, function()
        if button.armed then
            button:Reset()
            act()
        else
            button.armed = true
            button:SetLabel(confirm)
        end
    end, width, height)
    function button:Reset() self.armed = false; self:SetLabel(text) end
    button.armed = false
    return button
end

-- Small pieces ------------------------------------------------------------------------------------
function Theme.Chip(parent)
    local chip = CreateFrame("Frame", nil, parent)
    chip:SetHeight(20)
    chip.back = Theme.Fill(chip, "raised")
    chip.label = Theme.Text(chip, "UI", 12, "textSoft", "CENTER")
    chip.label:SetPoint("CENTER", chip, "CENTER", 0, 0)
    if type(chip.label.SetWordWrap) == "function" then chip.label:SetWordWrap(false) end
    function chip:Set(text, back, fore)
        self.label:SetWidth(0)
        self.label:SetText(text or "")
        self.back:SetShown(back ~= false)
        self.plain = back == false
        if back then Theme.Color(self.back, back) end
        Theme.TextColor(self.label, fore or "textSoft")
        self:SetWidth(Theme.Width(self.label) + (self.plain and 4 or 18))
        self:SetShown(text ~= nil and text ~= "")
        return self:GetWidth()
    end
    return chip
end

-- Places chips in a row from anchor, left to right; returns the width used. With a limit, a chip
-- that would cross it is shortened (plain text, when enough is left to read) or left out.
function Theme.Row(items, anchor, x, y, gap, limit)
    local left = x
    for _, item in ipairs(items) do
        if item:IsShown() and limit and left + item:GetWidth() > limit then
            local room = limit - left
            if item.plain and item.label and room >= 60 then
                item:SetWidth(room)
                item.label:SetWidth(room - 4)
            else
                item:Hide()
            end
        end
        if item:IsShown() then
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", anchor, "TOPLEFT", left, y)
            left = left + item:GetWidth() + (gap or 6)
        end
    end
    return left - x
end

-- Choices side by side in a dark rail; onPick(value).
function Theme.Segmented(parent, options, onPick)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(32)
    frame.back = Theme.Fill(frame, "shellDeep")
    frame.buttons = {}
    for index, option in ipairs(options) do
        local button = CreateFrame("Button", nil, frame)
        button.value = option.value
        button.back = Theme.Fill(button, "selected")
        button.label = Theme.Text(button, "UI", 13, "muted", "CENTER")
        button.label:SetAllPoints(button)
        if type(button.label.SetJustifyV) == "function" then button.label:SetJustifyV("MIDDLE") end
        button.label:SetText(option.label)
        button:SetScript("OnClick", function() if onPick then onPick(option.value) end end)
        frame.buttons[index] = button
    end
    function frame:Select(value)
        self.value = value
        for _, button in ipairs(self.buttons) do
            local on = button.value == value
            button.back:SetShown(on)
            Theme.TextColor(button.label, on and "goldBright" or "muted")
            Theme.SetFont(button.label, on and "UI_BOLD" or "UI", 13)
        end
    end
    function frame:Lay(width)
        self:SetWidth(width)
        local each = (width - 6) / #self.buttons
        for index, button in ipairs(self.buttons) do
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", self, "TOPLEFT", 3 + (index - 1) * each, -3)
            button:SetSize(each, 26)
        end
    end
    return frame
end

-- An on / off switch; onToggle(newValue).
function Theme.Switch(parent, onToggle)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(38, 20)
    button.track = Theme.Fill(button, "track")
    button.knob = button:CreateTexture(nil, "ARTWORK")
    button.knob:SetSize(14, 14)
    button:SetScript("OnClick", function(self) if onToggle then onToggle(not self.on) end end)
    function button:Set(on)
        self.on = on == true
        Theme.Color(self.track, self.on and "gold" or "track")
        Theme.Color(self.knob, self.on and "onGold" or "muted")
        self.knob:ClearAllPoints()
        self.knob:SetPoint(self.on and "RIGHT" or "LEFT", self, self.on and "RIGHT" or "LEFT", self.on and -3 or 3, 0)
    end
    button:Set(false)
    return button
end

-- Progress as short bars: found (gold), current (dim gold), the rest (track).
function Theme.Pips(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(6)
    frame.bars = {}
    function frame:Set(found, total, current, width)
        total = math.max(1, math.min(30, total or 1))
        width = width or self:GetWidth()
        local gap = total > 12 and 2 or 5
        local each = math.max(2, (width - gap * (total - 1)) / total)
        for index = 1, math.max(total, #self.bars) do
            local bar = self.bars[index]
            if not bar and index <= total then
                bar = self:CreateTexture(nil, "ARTWORK")
                self.bars[index] = bar
            end
            if bar then
                bar:SetShown(index <= total)
                if index <= total then
                    bar:ClearAllPoints()
                    bar:SetPoint("TOPLEFT", self, "TOPLEFT", (index - 1) * (each + gap), 0)
                    bar:SetSize(each, 6)
                    Theme.Color(bar, index <= found and "gold" or (current and index == found + 1) and { .45, .36, .20, 1 } or "track")
                end
            end
        end
        self:SetWidth(width)
    end
    return frame
end

-- Underlined tabs; onPick(value).
function Theme.Tabs(parent, items, onPick)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(30)
    frame.rule = frame:CreateTexture(nil, "BACKGROUND")
    frame.rule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
    frame.rule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    frame.rule:SetHeight(1)
    Theme.Color(frame.rule, "lineSoft")
    frame.buttons = {}
    local x = 0
    for index, item in ipairs(items) do
        local button = CreateFrame("Button", nil, frame)
        button.value = item.value
        button.label = Theme.Text(button, "UI", 14, "muted", "CENTER")
        button.label:SetPoint("TOP", button, "TOP", 0, -4)
        button.label:SetText(item.label)
        button.under = button:CreateTexture(nil, "ARTWORK")
        button.under:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT")
        button.under:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT")
        button.under:SetHeight(2)
        Theme.Color(button.under, "gold")
        local width = (button.label:GetStringWidth() or 40) + 4
        button:SetSize(width, 30)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
        x = x + width + 22
        button:SetScript("OnClick", function() if onPick then onPick(item.value) end end)
        frame.buttons[index] = button
    end
    function frame:Select(value)
        self.value = value
        for _, button in ipairs(self.buttons) do
            local on = button.value == value
            button.under:SetShown(on)
            Theme.TextColor(button.label, on and "text" or "muted")
        end
    end
    function frame:Lay(width)
        self:SetWidth(width)
        local total = 0
        for _, button in ipairs(self.buttons) do
            button:SetWidth(Theme.Width(button.label) + 4)
            total = total + button:GetWidth()
        end
        local gap = math.max(6, math.min(22, math.floor((width - total) / math.max(1, #self.buttons - 1))))
        local left = 0
        for _, button in ipairs(self.buttons) do
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", self, "TOPLEFT", left, 0)
            left = left + button:GetWidth() + gap
        end
    end
    return frame
end

-- A thin mark on the right edge of a list or a text that scrolls: where the view stands.
function Theme.Thumb(parent)
    local thumb = parent:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(2)
    Theme.Color(thumb, "gold")
    thumb:Hide()
    -- first: rows (or pixels) above the view; shown: in the view; total: in all.
    function thumb:Set(anchor, height, first, shown, total, inset)
        if total <= shown or height <= 0 then self:Hide(); return end
        local size = math.max(12, math.floor(height * shown / total))
        local travel = (height - size) * math.max(0, math.min(1, first / (total - shown)))
        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", inset or 0, -math.floor(travel))
        self:SetHeight(size)
        self:Show()
    end
    return thumb
end

-- A list row: icon square, title, chips, a value on the right. Selected rows are raised with a
-- gold edge on the left.
function Theme.ListRow(parent, height)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(height or 64)
    row.hovered, row.selected = false, false
    row.back = Theme.Fill(row, "raised")
    row.mark = row:CreateTexture(nil, "BORDER")
    row.mark:SetPoint("TOPLEFT", row, "TOPLEFT")
    row.mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
    row.mark:SetWidth(2)
    Theme.Color(row.mark, "gold")
    row.tile = row:CreateTexture(nil, "BORDER")
    row.tile:SetSize(42, 42)
    row.tile:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.icon = Theme.Icon(row, 30, nil)
    row.icon:SetPoint("CENTER", row.tile, "CENTER")
    row.title = Theme.Text(row, "TITLE", 14, "text")
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 66, -12)
    if type(row.title.SetWordWrap) == "function" then row.title:SetWordWrap(false) end
    row.value = Theme.Text(row, "UI", 13, "gold", "RIGHT")
    row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -13)
    row.chips = { Theme.Chip(row), Theme.Chip(row), Theme.Chip(row) }
    local function Paint(self)
        local on = self.selected or self.hovered
        self.back:SetShown(on == true)
        Theme.Color(self.back, self.selected and "selected" or "raised")
        self.mark:SetShown(self.selected == true)
    end
    row:SetScript("OnEnter", function(self) self.hovered = true; Paint(self) end)
    row:SetScript("OnLeave", function(self) self.hovered = false; Paint(self) end)
    row:SetScript("OnHide", function(self) self.hovered = false; Paint(self) end)
    function row:SetSelected(value) self.selected = value == true; Paint(self) end
    function row:Lay(width)
        self:SetWidth(width)
        self.title:SetWidth(math.max(40, width - 66 - 12 - (self.value:GetStringWidth() or 0) - 12))
        Theme.Row(self.chips, self, 66, -36, 6, width - 12)
    end
    Paint(row)
    return row
end

-- Text fields ---------------------------------------------------------------------------------------
-- One line. onChange(text) on each keystroke of the player. paper: drawn on parchment.
function Theme.Line(parent, face, size, maxLetters, hint, onChange, paper)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetHeight(size + 16)
    box:SetAutoFocus(false)
    if maxLetters and type(box.SetMaxLetters) == "function" then box:SetMaxLetters(maxLetters) end
    Theme.SetFont(box, face, size)
    Theme.TextColor(box, paper and "ink" or "text")
    if type(box.SetTextInsets) == "function" then box:SetTextInsets(0, 0, 0, 0) end
    box.rule = box:CreateTexture(nil, "BORDER")
    box.rule:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT")
    box.rule:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT")
    box.rule:SetHeight(1)
    Theme.Color(box.rule, paper and "paperLine" or "line")
    box.placeholder = Theme.Text(box, face, size, paper and "inkSoft" or "muted")
    box.placeholder:SetPoint("LEFT", box, "LEFT", 0, 0)
    box.placeholder:SetText(hint or "")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) Theme.Color(self.rule, "gold") end)
    box:SetScript("OnEditFocusLost", function(self) Theme.Color(self.rule, paper and "paperLine" or "line") end)
    box:SetScript("OnTextChanged", function(self, user)
        self.placeholder:SetShown(self:GetText() == "")
        if user and onChange then onChange(self:GetText()) end
    end)
    function box:SetValue(text)
        self:SetText(text or "")
        self.placeholder:SetShown((text or "") == "")
    end
    return box
end

-- Several lines in a scrolling inset (on parchment: a light field; on the shell: a dark one).
function Theme.Multi(parent, face, size, maxLetters, hint, onChange, paper)
    local holder = CreateFrame("Frame", nil, parent)
    holder.edge = Theme.Fill(holder, paper and "paperLine" or "line", "BACKGROUND")
    holder.back = holder:CreateTexture(nil, "BORDER")
    holder.back:SetPoint("TOPLEFT", holder, "TOPLEFT", 1, -1)
    holder.back:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -1, 1)
    Theme.Color(holder.back, paper and "paperDeep" or "shellDeep")
    local scroll = CreateFrame("ScrollFrame", nil, holder)
    scroll:SetPoint("TOPLEFT", holder, "TOPLEFT", 10, -7)
    scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -10, 7)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(owner, delta)
        local range = owner:GetVerticalScrollRange() or 0
        owner:SetVerticalScroll(math.max(0, math.min(range, owner:GetVerticalScroll() - delta * 30)))
    end)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(maxLetters)
    Theme.SetFont(box, face, size)
    Theme.TextColor(box, paper and "ink" or "text")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnCursorChanged", function(_, _, y, _, lineHeight)
        local top, view = scroll:GetVerticalScroll(), scroll:GetHeight()
        y = -(y or 0)
        if y < top then scroll:SetVerticalScroll(y)
        elseif y + (lineHeight or 0) > top + view then scroll:SetVerticalScroll(y + (lineHeight or 0) - view) end
    end)
    box:SetScript("OnEditFocusGained", function() Theme.Color(holder.edge, "gold") end)
    box:SetScript("OnEditFocusLost", function() Theme.Color(holder.edge, paper and "paperLine" or "line") end)
    scroll:SetScrollChild(box)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() box:SetFocus() end)
    holder.placeholder = Theme.Text(holder, face, size, paper and "inkSoft" or "muted")
    holder.placeholder:SetPoint("TOPLEFT", holder, "TOPLEFT", 10, -8)
    holder.placeholder:SetText(hint or "")
    box:SetScript("OnTextChanged", function(self, user)
        holder.placeholder:SetShown(self:GetText() == "")
        if user and onChange then onChange(self:GetText()) end
    end)
    holder.box, holder.scroll = box, scroll
    function holder:SetValue(text)
        box:SetText(text or "")
        self.placeholder:SetShown((text or "") == "")
    end
    function holder:GetValue() return box:GetText() end
    function holder:Lay(width, height)
        self:SetSize(width, height)
        scroll:SetSize(width - 20, height - 14)
        box:SetWidth(width - 20)
        self.placeholder:SetWidth(width - 20)
    end
    return holder
end
