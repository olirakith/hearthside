local MS = _G.MS

-- Short, sober motion for the Parcours. All of it is decoration: a panel that never animates must
-- look complete. One shared OnUpdate driver, attached only while something moves. Arrive, Rays and
-- Tint take turns; a turn that waited more than QUEUE_AGE seconds is dropped. With reduced motion
-- nothing moves: values land at once and a new line keeps a still mark until Clear.
MS.JourneyMotion = { QUEUE_AGE = 5, MARK_SHOWN = 2, MARK_FADE = 1, SLIDE = 6, SLIDE_SECONDS = .15,
    COUNT_SECONDS = .25, BAR_SECONDS = .4, RAYS_SECONDS = .9, TINT_SECONDS = .6, TINT_ALPHA = .35,
    tracks = {}, queue = {}, busy = false,
    marks = setmetatable({}, { __mode = "k" }), slides = setmetatable({}, { __mode = "k" }),
    bursts = setmetatable({}, { __mode = "k" }), washes = setmetatable({}, { __mode = "k" }) }
local Motion = MS.JourneyMotion
local Settings = MS.JourneySettings

local BURST = "Interface\\Cooldown\\star4"

local function Hidden(value) return type(_G.issecretvalue) == "function" and issecretvalue(value) == true end
local function Number(value) return not Hidden(value) and type(value) == "number" and value == value end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end
local function Now() return Call(_G.GetTime) or 0 end
local function Ease(p) return 1 - (1 - p) ^ 3 end
local function Gold()
    local color = MS.JourneyUIStyle and MS.JourneyUIStyle.colors and MS.JourneyUIStyle.colors.gold
    if type(color) == "table" then return color[1], color[2], color[3] end
    return .93, .73, .39
end

function Motion:Reduced()
    return Settings ~= nil and Settings:Get("reducedMotion") == true
end

-- Driver -------------------------------------------------------------------------------------------

function Motion:Attach()
    if not self.driver then
        local ok, frame = pcall(CreateFrame, "Frame")
        if not ok or not frame then return false end
        self.driver = frame
    end
    if not self.attached then
        self.attached = true
        self.driver:SetScript("OnUpdate", function(_, elapsed) Motion:Step(elapsed) end)
    end
    return true
end

function Motion:Detach()
    if self.driver and self.attached then self.driver:SetScript("OnUpdate", nil) end
    self.attached = false
end

-- finish: jump to the last frame first (stop), rather than leave it where it is (replaced).
function Motion:Drop(track, finish)
    if track.removed then return end
    track.removed = true
    for index = #self.tracks, 1, -1 do
        if self.tracks[index] == track then table.remove(self.tracks, index) end
    end
    if finish and track.step then pcall(track.step, 1) end
    if track.done then pcall(track.done) end
end

-- One motion per object and kind: a new one replaces the old.
function Motion:Track(object, kind, seconds, step, done)
    for _, track in ipairs(self.tracks) do
        if track.object == object and track.kind == kind then self:Drop(track, false); break end
    end
    local track = { object = object, kind = kind, seconds = seconds, time = 0, step = step, done = done }
    if not self:Attach() then
        if step then pcall(step, 1) end
        if done then pcall(done) end
        return
    end
    self.tracks[#self.tracks + 1] = track
    if step then pcall(step, 0) end
end

function Motion:Step(elapsed)
    elapsed = Number(elapsed) and math.max(0, elapsed) or 0
    local current = {}
    for index, track in ipairs(self.tracks) do current[index] = track end
    for _, track in ipairs(current) do
        if not track.removed then
            track.time = track.time + elapsed
            local p = math.min(1, track.time / track.seconds)
            if track.step then pcall(track.step, p) end
            if p >= 1 then self:Drop(track, false) end
        end
    end
    if #self.tracks == 0 then self:Detach() end
end

-- Turns for Arrive, Rays and Tint. start() returns true once it placed a track that calls Next.
function Motion:Exclusive(object, start)
    if self.busy then
        self.queue[#self.queue + 1] = { at = Now(), object = object, start = start }
        return
    end
    self.busy = true
    local ok, placed = pcall(start)
    if not ok or not placed then self:Next() end
end

function Motion:Next()
    self.busy = false
    local now = Now()
    while #self.queue > 0 do
        local item = table.remove(self.queue, 1)
        if now - item.at <= self.QUEUE_AGE then
            self.busy = true
            local ok, placed = pcall(item.start)
            if ok and placed then return end
            self.busy = false
        end
    end
end

local function NextTurn() Motion:Next() end

-- Pieces drawn on the animated frames, made once per frame ----------------------------------------

local function Mark(frame, r, g, b)
    local mark = Motion.marks[frame]
    if not mark then
        mark = frame:CreateTexture(nil, "OVERLAY")
        mark:SetWidth(3)
        mark:SetPoint("TOPLEFT", frame, "TOPLEFT", -10, 0)
        mark:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -10, 0)
        Motion.marks[frame] = mark
    end
    if not Number(r) or not Number(g) or not Number(b) then r, g, b = Gold() end
    mark:SetColorTexture(r, g, b, 1)
    mark:SetAlpha(1)
    mark:Show()
    return mark
end

-- A slide from the left by an AnimationGroup: it never touches the frame's anchors.
local function Slide(frame)
    local group = Motion.slides[frame]
    if group == nil then
        local ok, made = pcall(function()
            local g = frame:CreateAnimationGroup()
            local jump = g:CreateAnimation("Translation")
            jump:SetOffset(-Motion.SLIDE, 0); jump:SetDuration(0); jump:SetOrder(1)
            local back = g:CreateAnimation("Translation")
            back:SetOffset(Motion.SLIDE, 0); back:SetDuration(Motion.SLIDE_SECONDS); back:SetOrder(2)
            pcall(back.SetSmoothing, back, "OUT")
            return g
        end)
        group = ok and made or false
        Motion.slides[frame] = group
    end
    if group then pcall(group.Stop, group); pcall(group.Play, group) end
end

local function Burst(anchor)
    local burst = Motion.bursts[anchor]
    if burst == nil then
        local owner = type(anchor.CreateTexture) == "function" and anchor or Call(anchor.GetParent, anchor)
        burst = false
        if owner then
            burst = owner:CreateTexture(nil, "OVERLAY", nil, 7)
            burst:SetTexture(BURST)
            pcall(burst.SetBlendMode, burst, "ADD")
            burst:SetVertexColor(1, .8, .3)
            burst:SetPoint("CENTER", anchor, "CENTER", 0, 0)
            burst:Hide()
        end
        Motion.bursts[anchor] = burst
    end
    return burst or nil
end

local function Wash(frame)
    local wash = Motion.washes[frame]
    if not wash then
        wash = frame:CreateTexture(nil, "BACKGROUND", nil, 7)
        wash:SetAllPoints(frame)
        wash:Hide()
        Motion.washes[frame] = wash
    end
    return wash
end

-- Public helpers -----------------------------------------------------------------------------------

function Motion:Arrive(frame, r, g, b)
    if not frame then return end
    if self:Reduced() then
        local mark = Mark(frame, r, g, b)
        for _, track in ipairs(self.tracks) do
            if track.object == mark then self:Drop(track, false); break end
        end
        return
    end
    self:Exclusive(frame, function()
        local mark = Mark(frame, r, g, b)
        local shown, fade = self.MARK_SHOWN, self.MARK_FADE
        self:Track(mark, "mark", shown + fade, function(p)
            local t = p * (shown + fade)
            mark:SetAlpha(t <= shown and 1 or math.max(0, 1 - (t - shown) / fade))
            if p >= 1 then mark:Hide() end
        end)
        Slide(frame)
        self:Track(frame, "arrive", self.SLIDE_SECONDS, nil, NextTurn)
        return true
    end)
end

function Motion:Count(fontString, from, to, formatter)
    if not fontString or Hidden(to) then return end
    local format = type(formatter) == "function" and formatter or tostring
    local function Show(value)
        local ok, text = pcall(format, value)
        if ok and text ~= nil then fontString:SetText(text) end
    end
    if self:Reduced() or not Number(from) or not Number(to) or from == to then
        for _, track in ipairs(self.tracks) do
            if track.object == fontString and track.kind == "count" then self:Drop(track, false); break end
        end
        Show(to)
        return
    end
    self:Track(fontString, "count", self.COUNT_SECONDS, function(p)
        Show(p >= 1 and to or math.floor(from + (to - from) * Ease(p) + .5))
    end)
end

function Motion:Bar(fill, spark, fraction, width)
    if not fill then return end
    fraction = Number(fraction) and math.max(0, math.min(1, fraction)) or 0
    width = Number(width) and math.max(0, width) or 0
    -- A zero width would let the texture fall back to its own size.
    local target = math.max(.001, fraction * width)
    local start = Call(fill.GetWidth, fill)
    if spark then
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
    end
    if self:Reduced() or not Number(start) then
        fill:SetWidth(target)
        if spark then spark:SetAlpha(0) end
        return
    end
    local seconds = self.BAR_SECONDS
    -- Width moves in the first half; the spark rides along, then fades in the second.
    self:Track(fill, "bar", seconds * 2, function(p)
        local q = math.min(1, p * 2)
        fill:SetWidth(math.max(.001, start + (target - start) * Ease(q)))
        if spark then spark:SetAlpha(p <= .5 and 1 or math.max(0, (1 - p) * 2)) end
    end)
end

function Motion:Rays(anchor)
    if not anchor or self:Reduced() then return end
    self:Exclusive(anchor, function()
        local burst = Burst(anchor)
        if not burst then return false end
        local height = Call(anchor.GetHeight, anchor)
        local base = math.max(64, Number(height) and height * 2 or 0)
        burst:Show()
        self:Track(burst, "rays", self.RAYS_SECONDS, function(p)
            local size = base * (.3 + 1.1 * Ease(p))
            burst:SetSize(size, size)
            pcall(burst.SetRotation, burst, -2.1 * p)
            burst:SetAlpha(p < .15 and p / .15 or p < .5 and 1 or math.max(0, (1 - p) / .5))
            if p >= 1 then burst:Hide() end
        end, NextTurn)
        return true
    end)
end

function Motion:Tint(frame, r, g, b)
    if not frame or self:Reduced() then return end
    self:Exclusive(frame, function()
        local wash = Wash(frame)
        if not Number(r) or not Number(g) or not Number(b) then r, g, b = .75, .22, .2 end
        wash:SetColorTexture(r, g, b, 1)
        wash:Show()
        self:Track(wash, "tint", self.TINT_SECONDS, function(p)
            wash:SetAlpha(self.TINT_ALPHA * (1 - p))
            if p >= 1 then wash:Hide() end
        end, NextTurn)
        return true
    end)
end

-- Removes what Arrive left on one frame, including a still mark.
function Motion:Clear(frame)
    if not frame then return end
    for index = #self.queue, 1, -1 do
        if self.queue[index].object == frame then table.remove(self.queue, index) end
    end
    local mark = self.marks[frame]
    local current = {}
    for index, track in ipairs(self.tracks) do current[index] = track end
    for _, track in ipairs(current) do
        if track.object == frame or (mark and track.object == mark) then self:Drop(track, true) end
    end
    if mark then mark:Hide() end
    local group = self.slides[frame]
    if group then pcall(group.Stop, group) end
    if #self.tracks == 0 then self:Detach() end
end

-- When the view hides: every motion lands on its last frame, waiting turns are dropped.
function Motion:StopAll()
    self.queue = {}
    local current = self.tracks
    self.tracks = {}
    for _, track in ipairs(current) do
        track.removed = true
        if track.step then pcall(track.step, 1) end
    end
    self.busy = false
    for _, group in pairs(self.slides) do
        if group then pcall(group.Stop, group) end
    end
    self:Detach()
end

if Settings then
    if Settings.defaults.reducedMotion == nil then Settings.defaults.reducedMotion = false end
    if Settings.defaults.showModels == nil then Settings.defaults.showModels = true end
    Settings:Listen(function(key, value)
        if key == "reducedMotion" and value == true then Motion:StopAll() end
    end)
    Settings:AddExternalToggle({ id = "reducedMotion", label = MS.L.JOURNEY_SETTING_reducedMotion,
        hint = MS.L.JOURNEY_SETTINGS_REDUCED_MOTION_HINT,
        get = function() return Settings:Get("reducedMotion") == true end,
        set = function(value) Settings:Set("reducedMotion", value == true) end })
    Settings:AddExternalToggle({ id = "showModels", label = MS.L.JOURNEY_SETTING_showModels,
        hint = MS.L.JOURNEY_SETTINGS_SHOW_MODELS_HINT,
        get = function() return Settings:Get("showModels") ~= false end,
        set = function(value) Settings:Set("showModels", value == true) end })
end
