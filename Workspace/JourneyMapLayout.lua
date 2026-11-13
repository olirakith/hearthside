-- Pure geometry for the Journey Map tab. No frames, no WoW API: arithmetic only.
-- THREE needs a really wide screen: a 1080p screen with the chat open is wide but not roomy.
local MS = _G.MS
local Layout = {
    TOP = 44, BOTTOM = 18, GAP = 12, STRIP = 40,
    COLUMN_MIN = 260, COLUMN_MAX = 640, COLUMN_SHARE = 0.3, READING_MAX = 420,
    COMPACT_CARD = 92, THREE_RATIO = 2.2, THREE_MIN_WIDTH = 2400, STACK_MIN_WIDTH = 900,
}
MS.JourneyMapLayout = Layout

local floor, min, max = math.floor, math.min, math.max
local function clamp(v, lo, hi) return max(lo, min(hi, v)) end

-- Floored rect, never negative, clipped to the region.
local function rect(W, H, x, y, w, h)
    x = clamp(floor(x), 0, W)
    y = clamp(floor(y), 0, H)
    return { x = x, y = y, w = clamp(floor(w), 0, W - x), h = clamp(floor(h), 0, H - y) }
end

-- Card height for a column of height colH; the list keeps at least 120*s.
local function cardHeight(card, colH, s)
    local h
    if card == "ZONE" then h = Layout.COMPACT_CARD * s
    elseif card == "QUEST" then h = min(0.44 * colH, 330 * s)
    else return 0 end
    return max(0, min(h, colH - Layout.GAP - 120 * s))
end

local function cardModeOf(card)
    if card == "QUEST" then return "FULL" end
    if card == "ZONE" then return "COMPACT" end
    return "HIDDEN"
end

function Layout:Compute(input)
    local W, H = floor(input.width or 0), floor(input.height or 0)
    local s = clamp(input.scale or 1, 0.8, 1.2)
    local aspect = input.aspect or (1000 / 700)
    local card = input.card
    local GAP, TOP = self.GAP, self.TOP
    local avail = max(0, H - TOP - self.BOTTOM)
    local strip = floor(self.STRIP * s)
    local colMin = self.COLUMN_MIN * s

    local mode = "ROW"
    if W / max(H, 1) > self.THREE_RATIO and W >= self.THREE_MIN_WIDTH then mode = "THREE"
    elseif W < H or W < self.STACK_MIN_WIDTH then mode = "STACK" end

    local plan = { mode = mode, cardMode = cardModeOf(card) }
    local cw = floor(max(0, avail - strip) * aspect)
    local ch

    -- canvas size is fixed per mode; this places map panel, canvas and strip.
    local function placeMap(px, py, pw, ph, cwid, chei)
        cwid, chei = floor(cwid), floor(chei)
        plan.map = rect(W, H, px, py, pw, ph)
        local m = plan.map
        local cx = m.x + floor((m.w - cwid) / 2)
        plan.canvas = rect(W, H, cx, m.y, cwid, chei)
        plan.strip = rect(W, H, plan.canvas.x, plan.canvas.y + plan.canvas.h, plan.canvas.w, strip)
    end

    if mode == "ROW" then
        -- The column depends on the width only: folding the chat must not narrow the journal.
        local colW = clamp(W * self.COLUMN_SHARE, colMin, self.COLUMN_MAX)
        cw = min(cw, W - GAP * 3 - colW)
        ch = cw / aspect
        placeMap(GAP, TOP, W - GAP * 3 - colW, avail, cw, ch)
        local colX = W - GAP - colW
        local cardH = cardHeight(card, avail, s)
        if cardH > 0 then
            plan.card = rect(W, H, colX, TOP + avail - cardH, colW, cardH)
            plan.list = rect(W, H, colX, TOP, colW, avail - cardH - GAP)
        else
            plan.list = rect(W, H, colX, TOP, colW, avail)
        end
        plan.column = { x = colX, w = colW }
    elseif mode == "THREE" then
        local listW = clamp(W * 0.2, colMin, self.READING_MAX)
        local cardW = self.READING_MAX
        cw = min(cw, W - listW - cardW - GAP * 2)
        ch = cw / aspect
        cw = floor(cw)
        local x0 = max(0, floor((W - (cw + listW + cardW + GAP * 2)) / 2))
        placeMap(x0, TOP, cw, avail, cw, ch)
        plan.list = rect(W, H, x0 + cw + GAP, TOP, listW, avail)
        if card == "QUEST" then
            plan.card = rect(W, H, x0 + cw + listW + GAP * 2, TOP, cardW, avail)
        elseif card == "ZONE" then
            plan.card = rect(W, H, x0 + cw + listW + GAP * 2, TOP, cardW, self.COMPACT_CARD * s)
        end
    else
        cw = W - GAP * 2
        ch = cw / aspect
        if ch > 0.45 * avail then
            ch = 0.45 * avail
            cw = ch * aspect
        end
        placeMap(GAP, TOP, W - GAP * 2, floor(ch) + strip, cw, ch)
        local y0 = plan.map.y + plan.map.h + GAP
        local remH = max(0, H - self.BOTTOM - y0)
        if W >= self.STACK_MIN_WIDTH and card then
            local cardW = min(self.READING_MAX, 0.42 * W)
            local cardH = card == "ZONE" and self.COMPACT_CARD * s or remH
            plan.card = rect(W, H, W - GAP - cardW, y0, cardW, cardH)
            plan.list = rect(W, H, GAP, y0, W - GAP * 3 - cardW, remH)
        else
            local cardH = cardHeight(card, remH, s)
            if cardH > 0 then
                plan.card = rect(W, H, GAP, y0 + remH - cardH, W - GAP * 2, cardH)
                plan.list = rect(W, H, GAP, y0, W - GAP * 2, remH - cardH - GAP)
            else
                plan.list = rect(W, H, GAP, y0, W - GAP * 2, remH)
            end
        end
    end
    return plan
end
