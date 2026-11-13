local MS = _G.MS
local Style = MS.JourneyUIStyle
Style.version = 4
Style.space = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32, xxxl = 48 }
Style.spacingScale = { 4, 8, 12, 16, 24, 32, 48 }
-- Five steps only: page 30, chapter 24, item 17, body and sections 14, metadata 12.
Style.sizes.PAGE_TITLE, Style.sizes.SECTION, Style.sizes.HEADING = 30, 14, 14
Style.sizes.ITEM_TITLE, Style.sizes.BODY_LARGE, Style.sizes.BODY = 17, 14, 14
Style.sizes.SECONDARY, Style.sizes.SMALL = 12, 12
Style.typography = { page = "PAGE_TITLE", section = "SECTION", item = "ITEM_TITLE", body = "BODY", metadata = "SECONDARY" }

function Style:Text(label, token)
    local color = self.colors[token]
    if not label or not color then return end
    label:SetTextColor(color[1], color[2], color[3])
    local paper = token == "ink" or token == "inkSecondary" or token == "paperAccent"
    if type(label.SetShadowOffset) == "function" then label:SetShadowOffset(paper and 0 or 1, paper and 0 or -1) end
    if type(label.SetShadowColor) == "function" then label:SetShadowColor(0, 0, 0, paper and 0 or .6) end
end
-- Paper uses opaque surfaces and ink; shell text has its own lighter palette.
Style.colors.paper = { .82, .73, .56, 1 }
Style.colors.paperRaised = { .90, .82, .66, 1 }
Style.colors.paperInset = { .78, .68, .51, 1 }
Style.colors.paperSelected = { .96, .88, .71, 1 }
Style.colors.paperAccent = { .36, .24, .12, 1 }
Style.colors.ink = { .105, .075, .045, 1 }
Style.colors.inkSecondary = { .26, .20, .13, 1 }
Style.colors.textSecondary = { .86, .78, .65, 1 }
Style.colors.muted = { .75, .72, .65, 1 }
Style.sizes.CHAPTER_TITLE = 24
Style.completionTexture = "Interface\\Buttons\\UI-CheckBox-Check"
Style.headingTokens = { PAGE_TITLE = true, TITLE = true, CHAPTER_TITLE = true }
local titleFont = _G.QuestTitleFont
if titleFont and type(titleFont.GetFont) == "function" then Style.headingFont = titleFont:GetFont() end

function Style:Heading(label, token, color)
    label:SetFontObject(_G.QuestTitleFont or _G.GameFontNormal)
    self:Apply(label, token or "TITLE")
    self:Text(label, color or "ink")
end

function Style:Body(label, token, color)
    label:SetFontObject(_G.GameFontNormal)
    self:Apply(label, token or "BODY")
    self:Text(label, color or "ink")
    if type(label.SetSpacing) == "function" then label:SetSpacing(2) end
end

function Style:Metadata(label, color)
    self:Body(label, "SECONDARY", color or "inkSecondary")
end

-- Material rule: the dark shell holds navigation and lists, paper holds what is read.
Style.grainTexture = "Interface\\AddOns\\" .. (MS.addonName or "Hearthside") .. "\\Media\\JourneyGrain"
Style.grainSize = 128

-- A colour multiplied over a tiled grain, so a surface stops reading as a flat fill.
function Style:Material(texture, token)
    self:Color(texture, token)
    local color = self.colors[token]
    if not texture or not color or type(texture.SetVertexColor) ~= "function" then return end
    local ok, result = pcall(texture.SetTexture, texture, self.grainTexture, "REPEAT", "REPEAT")
    if not ok or result == false then return end
    if type(texture.SetHorizTile) == "function" then texture:SetHorizTile(true) end
    if type(texture.SetVertTile) == "function" then texture:SetVertTile(true) end
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

function Style:PageMaterial(texture, material)
    self:Material(texture, material == "PAPER" and "paperRaised" or "backgroundDeep")
    texture:SetAlpha(1)
end

-- A soft shadow and a bronze edge around target, drawn on owner because target may clip.
-- Target must be opaque: these are plain rectangles under it.
function Style:Rim(owner, target)
    local sublevel = 1
    local function Layer(extent, drop, color, alpha)
        local texture = owner:CreateTexture(nil, "BACKGROUND", nil, sublevel)
        sublevel = sublevel + 1
        texture:SetPoint("TOPLEFT", target, "TOPLEFT", -extent, extent - drop)
        texture:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", extent, -extent - drop)
        texture:SetColorTexture(color[1], color[2], color[3], alpha)
    end
    for step = 4, 1, -1 do Layer(step * 2 + 2, 2, { 0, 0, 0 }, .16) end
    Layer(2, 0, self.colors.borderActive, 1)
    Layer(1, 0, { 0, 0, 0 }, .85)
end

function Style:PaperInset(parent)
    local ok, frame = pcall(CreateFrame, "Frame", nil, parent, "BackdropTemplate")
    if not ok then frame = CreateFrame("Frame", nil, parent) end
    if type(frame.SetBackdrop) == "function" then
        frame:SetBackdrop({ bgFile = self.grainTexture, tile = true, tileSize = self.grainSize,
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        frame:SetBackdropColor(unpack(self.colors.paperRaised))
        frame:SetBackdropBorderColor(unpack(self.colors.borderMuted))
    else
        frame.paper = frame:CreateTexture(nil, "BACKGROUND"); frame.paper:SetAllPoints(frame)
        self:PageMaterial(frame.paper, "PAPER")
    end
    return frame
end

-- Same geometry as the paper inset; only the index material changes.
function Style:DarkInset(parent)
    local frame = self:PaperInset(parent)
    if type(frame.SetBackdropColor) == "function" then
        frame:SetBackdropColor(unpack(self.colors.backgroundDeep))
    elseif frame.paper then self:PageMaterial(frame.paper, "DARK") end
    return frame
end

function Style:PaperCloseButton(parent, action)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(22, 22)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.label:SetAllPoints(button); button.label:SetJustifyH("CENTER")
    self:Body(button.label, "BODY", "ink")
    button.label:SetText(MS.L.JOURNEY_CLOSE_NOTE)
    button.accessibleLabel = MS.L.ONBOARD_CLOSE
    self:Action(button, button.label, true)
    button:SetScript("OnClick", action)
    return button
end

function Style:Separator(texture, native)
    if self.dividerResolved ~= true then
        self.dividerResolved = true
        local api = _G.C_Texture and C_Texture.GetAtlasInfo
        if type(api) == "function" then
            local ok, info = pcall(api, "common-framedivider")
            self.dividerAvailable = ok and type(info) == "table"
        end
    end
    if native and self.dividerAvailable and type(texture.SetAtlas) == "function" then
        local ok, result = pcall(texture.SetAtlas, texture, "common-framedivider", false)
        if ok and result ~= false then return "NATIVE_ATLAS" end
    end
    self:Color(texture, "borderMuted")
    return "COLOR_RULE"
end

function Style:TabState(button, active, hovered, secondary)
    self:Color(button.background, "backgroundRaised")
    button.background:SetAlpha(button.pressed == true and .4 or active and .26 or hovered and .18 or 0)
    self:Text(button.label, active and "gold" or hovered and "textPrimary" or secondary and "muted" or "textSecondary")
    button.rule:SetShown(active or hovered == true)
    button.rule:SetAlpha(active and 1 or .45)
end

function Style:CloseButton(parent, action)
    local ok, button = pcall(CreateFrame, "Button", nil, parent, "UIPanelCloseButton")
    if not ok then
        button = CreateFrame("Button", nil, parent)
        button:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        button:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        button:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    end
    button:SetSize(22, 22); button:SetScript("OnClick", action)
    return button
end

function Style:QuestStateGlyph(texture, state, color)
    color = color or (self.questStates[state] or self.questStates.UNKNOWN).color
    if state == "COMPLETE_OBJECTIVES" then
        local ok, result = pcall(texture.SetTexture, texture, self.completionTexture)
        if ok and result ~= false then
            if type(texture.SetRotation) == "function" then texture:SetRotation(0) end
            return "NATIVE_COMPLETION_FILE"
        end
    end
    if state == "UNKNOWN" or state == "COMPLETE_OBJECTIVES" or not self.questStates[state] then
        texture:SetColorTexture(color[1], color[2], color[3], 1)
        if type(texture.SetRotation) == "function" then texture:SetRotation(math.pi / 4) end
        return "JOURNEY_TEXTURE_FALLBACK"
    end
    return MS.JourneyPinAssets:Apply(texture, state, color)
end

-- Completed objectives retain localized completion text even if the native file is absent.
function Style:CompletedObjective(text)
    return "|T" .. self.completionTexture .. ":14:14|t " .. text
end

function Style:ReadingColumn(width)
    local available = math.max(1, width - 32)
    local reading = math.min(available, math.max(560, math.min(760, width * .86)))
    return reading, math.max(0, (width - reading) / 2)
end

function Style:ChapterMarker(label, index)
    local value, parts = math.max(1, math.floor(index)), {}
    for _, pair in ipairs({ {1000,"M"}, {900,"CM"}, {500,"D"}, {400,"CD"}, {100,"C"}, {90,"XC"},
        {50,"L"}, {40,"XL"}, {10,"X"}, {9,"IX"}, {5,"V"}, {4,"IV"}, {1,"I"} }) do
        while value >= pair[1] do parts[#parts + 1] = pair[2]; value = value - pair[1] end
    end
    self:Heading(label, "SECTION", "inkSecondary")
    label:SetText(table.concat(parts))
end

function Style:PaperSelection(background, accent, title, metadata, selected)
    self:Color(background, "paperSelected"); background:SetAlpha(1)
    self:Color(accent, "paperAccent"); accent:SetAlpha(1)
    background:SetShown(selected == true); accent:SetShown(selected == true)
    self:Text(title, "ink"); self:Text(metadata, "inkSecondary")
end

function Style:QuestReadingColumn(width)
    local reading = math.min(math.max(1, width - 48), 640)
    return reading, math.max(0, (width - reading) / 2)
end

function Style:DarkSelection(background, accent, title, metadata, selected)
    self:Color(background, "backgroundRaised"); background:SetAlpha(1); background:SetShown(selected)
    self:Color(accent, "borderActive"); accent:SetShown(selected)
    if title then self:Text(title, "textPrimary") end
    if metadata then self:Text(metadata, "textSecondary") end
end

function Style:DifficultyColor(level)
    if type(GetQuestDifficultyColor) == "function" then
        local ok, color = pcall(GetQuestDifficultyColor, level)
        if ok and type(color) == "table" and type(color.r) == "number"
            and type(color.g) == "number" and type(color.b) == "number" then return color.r, color.g, color.b end
    end
    local player = 1
    if type(UnitLevel) == "function" then
        local ok, value = pcall(UnitLevel, "player")
        if ok and type(value) == "number" and value > 0 then player = value end
    end
    local difference = level - player
    if difference >= 5 then return 1, .1, .1 end
    if difference >= 3 then return 1, .5, .25 end
    if difference >= -2 then return 1, 1, 0 end
    local greenRange
    if type(GetQuestGreenRange) == "function" then
        local ok, value = pcall(GetQuestGreenRange)
        if ok and type(value) == "number" then greenRange = value end
    end
    greenRange = greenRange or (player <= 5 and 5 or player <= 39 and math.floor(player / 10) + 5
        or player <= 59 and math.floor(player / 5) + 1 or 9)
    if -difference <= greenRange then return .25, .75, .25 end
    return .5, .5, .5
end

function Style:QuestLevel(label, level)
    local valid = type(level) == "number" and level > 0
    label:SetShown(valid)
    if not valid then label:SetText(""); return end
    label:SetText(string.format(MS.L.JOURNEY_QUEST_LEVEL_BRACKET, level))
    label:SetTextColor(self:DifficultyColor(level))
end

local function Region(value)
    return type(value) == "table" or type(value) == "userdata"
end

function Style:Link(button, label, paper)
    local normal = paper and "paperAccent" or "gold"
    self:Text(label, normal)
    if not Region(button.linkUnderline) then
        button.linkUnderline = button:CreateTexture(nil, "ARTWORK")
        button.linkUnderline:SetPoint("BOTTOMLEFT", label, "BOTTOMLEFT", 0, -2)
        button.linkUnderline:SetHeight(1)
    end
    self:Color(button.linkUnderline, normal); button.linkUnderline:Hide()
    button:SetScript("OnEnter", function()
        self:Text(label, paper and "ink" or "textPrimary")
        local ok, width = pcall(label.GetStringWidth, label)
        button.linkUnderline:SetWidth(math.max(1, math.min(label:GetWidth(), ok and type(width) == "number" and width or label:GetWidth())))
        button.linkUnderline:Show()
    end)
    button:SetScript("OnLeave", function() self:Text(label, normal); button.linkUnderline:Hide() end)
end

function Style:Action(button, label, paper)
    local background = Region(button.background) and button.background or Region(button.back) and button.back
    if not background then background = button:CreateTexture(nil, "BORDER"); button.background = background end
    if not Region(button.actionBorder) then
        button.actionBorder = button:CreateTexture(nil, "BACKGROUND")
        button.actionBorder:SetAllPoints(button)
    end
    self:Color(button.actionBorder, paper and "paperAccent" or "borderActive")
    background:ClearAllPoints()
    background:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    background:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    if type(background.SetDrawLayer) == "function" then background:SetDrawLayer("BORDER") end
    local function paint()
        local enabled = button.actionDisabled ~= true
        if type(button.IsEnabled) == "function" and button:IsEnabled() == false then enabled = false end
        button:SetAlpha(enabled and 1 or .45)
        self:Color(background, paper and (button.actionPressed == true and "paperInset" or button.actionHovered == true and "paperSelected" or "paperRaised")
            or (button.actionPressed == true and "backgroundDeep" or button.actionHovered == true and "backgroundRaised" or "backgroundPanel"))
        background:SetAlpha(1)
        if not paper then
            local lit = button.selected == true or (enabled and button.actionHovered == true)
            self:Color(button.actionBorder, lit and "gold" or "borderActive")
        end
        self:Text(label, paper and "ink" or (enabled and button.actionHovered == true and "textBright" or "textPrimary"))
    end
    button:SetScript("OnEnter", function() button.actionHovered = true; paint() end)
    button:SetScript("OnLeave", function() button.actionHovered, button.actionPressed = false, false; paint() end)
    button:SetScript("OnMouseDown", function() button.actionPressed = true; paint() end)
    button:SetScript("OnMouseUp", function() button.actionPressed = false; paint() end)
    button:SetScript("OnDisable", paint); button:SetScript("OnEnable", paint)
    paint()
end

-- The one reaction of clickable rows: hover lights, pressed deepens, hiding clears both,
-- since a clicked row can vanish under the mouse. Needs row.hover; row.inert turns it off.
function Style:RowState(row)
    local lit = row.inert ~= true and (row.rowHovered == true or row.rowPressed == true)
    row.hover:SetShown(lit)
    row.hover:SetAlpha(row.rowPressed == true and 1 or .75)
end

function Style:ReactiveRow(row, enter, leave)
    self:Color(row.hover, "backgroundRaised")
    local function Set(hovered, pressed)
        row.rowHovered, row.rowPressed = hovered, pressed
        self:RowState(row)
    end
    local function Hidden(frame)
        local wasHovered = row.rowHovered == true
        Set(false, false)
        if wasHovered and leave then leave(frame) end
    end
    row:SetScript("OnEnter", function(frame) Set(true, false); if enter then enter(frame) end end)
    row:SetScript("OnLeave", function(frame) Set(false, false); if leave then leave(frame) end end)
    row:SetScript("OnMouseDown", function() Set(row.rowHovered == true, true) end)
    row:SetScript("OnMouseUp", function() Set(row.rowHovered == true, false) end)
    row:SetScript("OnHide", Hidden)
    self:RowState(row)
end

-- One sleeping driver for short motions. In a fight nothing moves: the last step comes at once.
local tweens, tweenDriver = {}, nil

local function StepTweens(driver, elapsed)
    local running = false
    for key, tween in pairs(tweens) do
        tween.time = tween.time + (elapsed or 0)
        local progress = math.min(1, tween.time / tween.duration)
        tween.step(progress)
        if progress >= 1 then tweens[key] = nil else running = true end
    end
    if not running then driver:Hide() end
end

function Style:Tween(key, seconds, step)
    local fighting = type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown()
    if fighting or type(CreateFrame) ~= "function" then
        tweens[key] = nil; step(1); return
    end
    if not tweenDriver then
        tweenDriver = CreateFrame("Frame")
        tweenDriver:SetScript("OnUpdate", StepTweens)
    end
    tweens[key] = { time = 0, duration = seconds, step = step }
    step(0)
    tweenDriver:Show()
end

function Style:FadeIn(frame, seconds)
    self:Tween(frame, seconds or .15, function(progress) frame:SetAlpha(progress) end)
end

-- Shared row facts, not a general component system.
function Style:QuestRowState(icon, levelLabel, state, level)
    self:QuestStateGlyph(icon, state or "UNKNOWN")
    self:QuestLevel(levelLabel, level)
end

Style.colors.critical = { .95, .48, .38, 1 }
Style.sizes.CHAPTER_MARKER = 30
Style.headingTokens.CHAPTER_MARKER = true

-- Floating surfaces (moment card, context menu) sit on Journey's own dark shell: they need a
-- darker body, a brighter edge and something under them to read as "above" it.
Style.colors.overlay = { .045, .036, .026, .97 }
Style.colors.overlayHover = { .29, .215, .12, .95 }
Style.colors.textBright = { 1, .94, .79, 1 }
Style.colors.glow = { 1, .76, .36, 1 }

-- Shadow: stacked translucent rectangles behind the frame, each a little larger and lower, so
-- their overlap fades outwards. Halo (optional): two faint warm rectangles hugging the edge.
-- Plain colour textures only, created once per frame. Returns how far they reach outside the
-- frame, so the caller can keep that margin inside WORKSPACE.
Style.elevation = { step = 2, drop = 2, shadowAlpha = .11, halo = { { 4, .09 }, { 2, .2 } } }
Style.elevated = setmetatable({}, { __mode = "k" })
function Style:Elevate(frame, steps, halo)
    if self.elevated[frame] then return self.elevated[frame].reach end
    local spec, layers, sublevel = self.elevation, {}, -8
    local function Layer(extent, drop, color, alpha)
        local texture = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel)
        sublevel = sublevel + 1
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", -extent, extent - drop)
        texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", extent, -extent - drop)
        texture:SetColorTexture(color[1], color[2], color[3], alpha)
        layers[#layers + 1] = texture
    end
    local reach = 0
    for index = steps, 1, -1 do
        Layer(index * spec.step, spec.drop, { 0, 0, 0 }, spec.shadowAlpha)
        reach = math.max(reach, index * spec.step + spec.drop)
    end
    if halo then
        for _, ring in ipairs(spec.halo) do
            Layer(ring[1], 0, self.colors.glow, ring[2])
            reach = math.max(reach, ring[1])
        end
    end
    self.elevated[frame] = { layers = layers, reach = reach }
    return reach
end
