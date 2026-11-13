local MS = _G.MS

-- Pixel handshake with the Companion: READY heartbeat and LEAVING.
-- CONTROL carries presence/lifecycle only and stays active
-- in combat. Exit intents come from post-hooks only:
-- Blizzard behaviour is never replaced, blocked or delayed.
local PH = {
    MAGIC = 0xA7, VERSION = 1, CHANNEL_CONTROL = 0x00,
    TYPE_READY = 0x01, TYPE_LEAVING = 0x02,
    REASON = { UNKNOWN = 0, RELOAD = 1, LOGOUT = 2, QUIT = 3, FORCE_QUIT = 4 },
    COLUMNS = 48, ROWS = 1, CELL_SIZE = 1,
    -- A lit channel stays dark enough to go unnoticed. The Companion calibrates
    -- on the cells and needs a spread of 64 out of 255: this gives 102.
    CELL_LEVEL = 0.4,
    HEARTBEAT = 0.25,
    -- A hooked exit intent that neither a countdown event nor the UI teardown
    -- confirms within this delay (e.g. a refused logout) returns to READY.
    INTENT_GUARD = 5,
    -- CAMP countdown length when its dialog definition is unavailable, and the
    -- tolerance used to recognise its expiry (see OnCancelLogout).
    CAMP_TIMEOUT_DEFAULT = 20,
    CAMP_EXPIRY_TOLERANCE = 0.25,
    -- WoW's root coordinate space is 768 units tall at effective scale 1.
    UI_ROOT_HEIGHT = 768,
}
MS.PixelHandshake = PH

local REASON = PH.REASON
local CANCELLABLE = { [REASON.LOGOUT] = true, [REASON.QUIT] = true }
local floor = math.floor

-- Pure encoder: no WoW API, testable outside the client. ---------------------

-- Bitwise XOR of two non-negative integers below 2^16, in plain arithmetic so
-- the encoder does not depend on a `bit` library.
local function Xor16(a, b)
    local result, place = 0, 1
    for _ = 1, 16 do
        local x, y = a % 2, b % 2
        if x ~= y then result = result + place end
        a, b, place = (a - x) / 2, (b - y) / 2, place * 2
    end
    return result
end

-- CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF, no reflection, no xorout).
function PH.Crc16(bytes)
    local crc = 0xFFFF
    for i = 1, #bytes do
        crc = Xor16(crc, bytes[i] * 256)
        for _ = 1, 8 do
            if crc >= 0x8000 then
                crc = Xor16((crc * 2) % 0x10000, 0x1021)
            else
                crc = (crc * 2) % 0x10000
            end
        end
    end
    return crc
end

local function Split16(value)
    return floor(value / 256), value % 256
end

-- The 13 packet bytes: magic, version, ui_epoch, sequence, channel, type,
-- flags (STATE), length 1, payload, CRC (big-endian).
function PH.EncodePacket(epoch, sequence, messageType, payload)
    local epochHigh, epochLow = Split16(epoch)
    local sequenceHigh, sequenceLow = Split16(sequence)
    local bytes = { PH.MAGIC, PH.VERSION, epochHigh, epochLow, sequenceHigh, sequenceLow,
        PH.CHANNEL_CONTROL, messageType, 0x00, 0x01, payload }
    bytes[12], bytes[13] = Split16(PH.Crc16(bytes))
    return bytes
end

-- The 48 grid cells (index 1 = cell 0): calibration 0..7, sync 5,2, tag,
-- packet bits MSB first (3 per cell, 1 pad bit), tag copy, padding.
function PH.EncodeCells(packet, tag)
    local cells = { 0, 1, 2, 3, 4, 5, 6, 7, 5, 2, tag % 8 }
    local bits = {}
    for i = 1, 13 do
        for shift = 7, 0, -1 do
            bits[#bits + 1] = floor(packet[i] / 2 ^ shift) % 2
        end
    end
    bits[105] = 0
    for cell = 0, 34 do
        local bit = cell * 3
        cells[12 + cell] = bits[bit + 1] * 4 + bits[bit + 2] * 2 + bits[bit + 3]
    end
    cells[47], cells[48] = tag % 8, 0
    return cells
end

-- Cell value to RGB (value = R*4 + G*2 + B, channels 0 or 1).
function PH.CellColor(value)
    return floor(value / 4) % 2, floor(value / 2) % 2, value % 2
end

-- Emitter state machine: no WoW API; rendering is attached by Start. ----------

PH.epoch, PH.sequence, PH.tag = nil, 0, 0
PH.message, PH.reason, PH.intentDeadline = nil, nil, nil
PH.clock, PH.sinceEmit = 0, 0

-- One ui_epoch per UI load; sequence and tag restart with it.
function PH:NewEpoch(epoch)
    self.epoch = epoch % 65536
    self.sequence, self.tag = 0, 0
end

-- Emit the next frame of the current message. Returns its cells, or nil while
-- silent (before READY).
function PH:Emit()
    if not self.message or not self.epoch then return nil end
    self.sequence = (self.sequence + 1) % 65536
    self.tag = (self.tag + 1) % 8
    local payload = self.message == PH.TYPE_LEAVING and self.reason or 0
    local cells = PH.EncodeCells(PH.EncodePacket(self.epoch, self.sequence, self.message, payload), self.tag)
    self.sinceEmit = 0
    if self.textures then self:Render(cells) end
    return cells
end

function PH:SetReady()
    if self.message == PH.TYPE_LEAVING then return end
    self.message, self.reason = PH.TYPE_READY, nil
    self:Emit()
end

-- LEAVING is a state republished at the heartbeat until teardown or cancel.
-- The latest known reason wins; UNKNOWN never replaces a known reason.
-- `confirmed` (countdown event or teardown) disarms the intent guard.
function PH:SetLeaving(reason, confirmed)
    local current = self.message == PH.TYPE_LEAVING and self.reason or nil
    if not (current and reason == REASON.UNKNOWN) then self.reason = reason end
    self.message = PH.TYPE_LEAVING
    if confirmed then
        self.intentDeadline = nil
    elseif not current then
        self.intentDeadline = self.clock + PH.INTENT_GUARD
    end
    self:Emit()
end

-- LOGOUT_CANCEL: a cancellable exit (logout or quit countdown) returns to READY.
function PH:Cancel()
    if self.message == PH.TYPE_LEAVING and CANCELLABLE[self.reason] then
        self.message, self.reason, self.intentDeadline = PH.TYPE_READY, nil, nil
        self.campingStarted = nil
        self:Emit()
    end
end

function PH:Now()
    return type(GetTime) == "function" and GetTime() or self.clock
end

-- Duration of the CAMP (logout) countdown dialog, read-only from its definition.
function PH:CampTimeout()
    local dialogs = type(StaticPopupDialogs) == "table" and StaticPopupDialogs or nil
    local camp = dialogs and type(dialogs.CAMP) == "table" and dialogs.CAMP or nil
    return camp and tonumber(camp.timeout) or PH.CAMP_TIMEOUT_DEFAULT
end

-- PLAYER_CAMPING: the logout countdown started.
function PH:StartCamping()
    self.campingStarted = self:Now()
    self:SetLeaving(REASON.LOGOUT, true)
end

-- CancelLogout post-hook. When the CAMP countdown expires, StaticPopup calls its
-- OnCancel ("timeout"), which calls CancelLogout right before the logout
-- completes: that call is not a user cancel and must not return to READY.
function PH:OnCancelLogout()
    local started = self.campingStarted
    if started and self:Now() - started >= self:CampTimeout() - PH.CAMP_EXPIRY_TOLERANCE then
        return
    end
    self:Cancel()
end

-- Advance time; emits the heartbeat every HEARTBEAT seconds.
function PH:Tick(elapsed)
    self.clock = self.clock + elapsed
    if self.intentDeadline and self.clock >= self.intentDeadline then
        self.message, self.reason, self.intentDeadline = PH.TYPE_READY, nil, nil
        self:Emit()
        return
    end
    self.sinceEmit = self.sinceEmit + elapsed
    if self.sinceEmit >= PH.HEARTBEAT then self:Emit() end
end

-- Rendering and WoW wiring. --------------------------------------------------

function PH:Render(cells)
    for index = 1, #cells do
        local red, green, blue = PH.CellColor(cells[index])
        local level = PH.CELL_LEVEL
        self.textures[index]:SetColorTexture(red * level, green * level, blue * level, 1)
    end
    self:UpdateVisibility()
end

function PH:UpdateVisibility()
    if self.frame then
        self.frame:SetShown(self.message ~= nil and self.scaled == true and not self.screenshot)
    end
end

-- 1 UI unit = 1 physical pixel: a parentless frame scaled by 768 / height.
function PH:UpdateScale()
    if not self.frame then return end
    local ok, _, height = pcall(GetPhysicalScreenSize)
    self.scaled = ok and type(height) == "number" and height > 0
    if self.scaled then self.frame:SetScale(PH.UI_ROOT_HEIGHT / height) end
    self:UpdateVisibility()
end

function PH:SetScreenshot(active)
    self.screenshot = active
    self:UpdateVisibility()
end

function PH:CreateDisplay()
    -- No parent: independent of UIParent scale and of Alt+Z.
    local frame = CreateFrame("Frame", nil, nil)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetSize(PH.COLUMNS * PH.CELL_SIZE, PH.ROWS * PH.CELL_SIZE)
    frame:SetPoint("TOPLEFT")
    frame:Hide()
    local textures = {}
    for index = 0, PH.COLUMNS * PH.ROWS - 1 do
        local texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetSize(PH.CELL_SIZE, PH.CELL_SIZE)
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", (index % PH.COLUMNS) * PH.CELL_SIZE,
            -floor(index / PH.COLUMNS) * PH.CELL_SIZE)
        textures[index + 1] = texture
    end
    -- OnUpdate runs only while shown: no heartbeat before READY or during a screenshot.
    frame:SetScript("OnUpdate", function(_, elapsed) PH:Tick(elapsed) end)
    self.frame, self.textures = frame, textures
    self:UpdateScale()
end

local EVENTS = {
    LOADING_SCREEN_DISABLED = function() PH:SetReady() end,
    PLAYER_ENTERING_WORLD = function() PH:SetReady() end,
    PLAYER_CAMPING = function() PH:StartCamping() end,
    PLAYER_QUITING = function() PH:SetLeaving(REASON.QUIT, true) end,
    LOGOUT_CANCEL = function() PH:Cancel() end,
    PLAYER_LOGOUT = function() PH:SetLeaving(REASON.UNKNOWN, true) end,
    DISPLAY_SIZE_CHANGED = function() PH:UpdateScale() end,
    UI_SCALE_CHANGED = function() PH:UpdateScale() end,
    SCREENSHOT_STARTED = function() PH:SetScreenshot(true) end,
    SCREENSHOT_SUCCEEDED = function() PH:SetScreenshot(false) end,
    SCREENSHOT_FAILED = function() PH:SetScreenshot(false) end,
}

local HOOKS = {
    { name = "Quit", action = function() PH:SetLeaving(REASON.QUIT, false) end },
    { name = "Logout", action = function() PH:SetLeaving(REASON.LOGOUT, false) end },
    { name = "ForceQuit", action = function() PH:SetLeaving(REASON.FORCE_QUIT, false) end },
    { name = "ReloadUI", action = function() PH:SetLeaving(REASON.RELOAD, false) end },
    -- The CAMP and QUIT countdown dialogs call CancelLogout on Cancel. On Forever,
    -- cancelling from the dialog was not seen through LOGOUT_CANCEL.
    { name = "CancelLogout", action = function() PH:OnCancelLogout() end },
}

-- Called once per UI load. `epoch` is injectable for tests.
function PH:Start(epoch)
    if self.started then return end
    self.started = true
    self:NewEpoch(epoch or math.random(0, 65535))
    self:CreateDisplay()
    local events = CreateFrame("Frame")
    -- Registration must never break loading if a client lacks an event.
    for event in pairs(EVENTS) do pcall(events.RegisterEvent, events, event) end
    events:SetScript("OnEvent", function(_, event) EVENTS[event]() end)
    self.hooks = {}
    if type(hooksecurefunc) == "function" then
        for _, hook in ipairs(HOOKS) do
            if type(_G[hook.name]) == "function" then
                self.hooks[hook.name] = pcall(hooksecurefunc, hook.name, hook.action)
            end
        end
        if type(C_UI) == "table" and type(C_UI.Reload) == "function" then
            self.hooks["C_UI.Reload"] = pcall(hooksecurefunc, C_UI, "Reload", function()
                PH:SetLeaving(REASON.RELOAD, false)
            end)
        end
    end
end
