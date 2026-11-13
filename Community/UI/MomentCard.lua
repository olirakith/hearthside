local MS = _G.MS
MS.Community = MS.Community or {}
-- One small card on the Journey workspace (second screen) for the few Community moments:
-- a farewell, a familiar name, a ready question. Never on the game screen, never in combat,
-- one at a time. Non-secure frames only.
local C = MS.Community
-- margin/top: where the card sits on WORKSPACE (below the Chronicles discovery toast).
local Card = { width = 320, margin = 28, top = 224, priority = { FAREWELL = 3, ASK = 2, FAMILIAR = 1, ASK_READY = 0 },
    -- Community's own moments say they are experimental; quest social cards do not repeat it
    -- (the setting already says so).
    experimentalKinds = { FAREWELL = true, FAMILIAR = true } }
C.MomentCard = Card

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event) Card:OnCombat(event == "PLAYER_REGEN_DISABLED") end)

local function Number(value) return type(value) == "number" and value == value and value or nil end

local function Label(parent, token, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if MS.JourneyUIStyle then MS.JourneyUIStyle:Apply(label, token); MS.JourneyUIStyle:Text(label, color) end
    -- A firm shadow keeps every line crisp on the card's dark surface.
    if type(label.SetShadowOffset) == "function" then label:SetShadowOffset(1, -1) end
    if type(label.SetShadowColor) == "function" then label:SetShadowColor(0, 0, 0, .95) end
    label:SetJustifyH("LEFT")
    return label
end

local function Button(parent, token)
    local button = CreateFrame("Button", nil, parent)
    button.label = Label(button, token, "gold")
    button.label:SetAllPoints(button)
    button.label:SetJustifyH("RIGHT")
    return button
end

function Card:Surface()
    local workspace = MS.Workspace
    local journey = MS.JourneyWorkspace
    if not workspace or not workspace.frame or not workspace.frame:IsShown() then return nil end
    if journey and journey.active == false then return nil end
    return workspace.frame
end

function Card:Available()
    if type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() then return false, "COMBAT" end
    -- Streamer mode: a moment card names another player, so none opens.
    if MS.BroadcastMode and MS.BroadcastMode:IsOn() then return false, "BROADCAST" end
    if not self:Surface() then return false, "NO_SURFACE" end
    return true
end

-- Above Journey, not an alarm: darker body, gold edge, a soft shadow and a faint warm halo
-- behind it (plain textures from Journey's style, no Blizzard frame or template).
function Card:Create(parent)
    if self.frame then
        if self.frame:GetParent() ~= parent then self.frame:SetParent(parent) end
        return
    end
    local style = MS.JourneyUIStyle
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(self.width, 128)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    self.reach = style and style.Elevate and style:Elevate(frame, 4, true) or 0
    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetAllPoints(frame)
    frame.background = frame:CreateTexture(nil, "BORDER")
    frame.background:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.rule = frame:CreateTexture(nil, "ARTWORK")
    frame.rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    frame.rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -10)
    frame.rule:SetHeight(2)
    if style then
        style:Color(frame.border, "borderActive")
        style:Color(frame.background, "overlay")
        style:Color(frame.rule, "gold")
    end
    frame.heading = Label(frame, "SMALL", "gold")
    frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -20)
    frame.heading:SetWidth(self.width - 120)
    frame.tag = Label(frame, "SMALL", "textSecondary")
    frame.tag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -20)
    frame.tag:SetJustifyH("RIGHT")
    frame.tag:SetText(MS.L.COMMUNITY_EXPERIMENTAL_TAG)
    frame.title = Label(frame, "HEADING", "textBright")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
    frame.title:SetWidth(self.width - 32)
    frame.body = Label(frame, "BODY", "textSecondary")
    frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -66)
    frame.body:SetWidth(self.width - 32)
    frame.close = Button(frame, "BODY")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -14)
    frame.close:SetSize(20, 20)
    frame.close.label:SetText("×")
    frame.close:SetScript("OnClick", function() Card:Close("PLAYER") end)
    -- The action is a framed button, so the one thing to do reads as such.
    frame.primary = Button(frame, "BODY")
    frame.primary:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    frame.primary:SetSize(240, 26)
    if style and style.Action then
        frame.primary.label:SetJustifyH("CENTER")
        style:Action(frame.primary, frame.primary.label)
    end
    frame.primary:SetScript("OnClick", function() Card:Primary() end)
    frame:Hide()
    self.frame = frame
end

-- Text first, then room for the action; the button fits its words.
function Card:Fit(withAction)
    local frame = self.frame
    local body = Number(frame.body:GetStringHeight()) or 14
    if withAction then
        local words = Number(frame.primary.label:GetStringWidth()) or 200
        frame.primary:SetWidth(math.max(120, math.min(self.width - 32, math.ceil(words) + 32)))
    end
    frame:SetHeight(math.max(96, math.ceil(66 + body + (withAction and 54 or 18))))
end

-- Pure placement from WORKSPACE's top-right corner: the usual offsets, pulled in so the card
-- with its shadow and halo (reach) stays whole inside the bounds. nil when it cannot fit.
function Card.Place(width, height, reach, boundsWidth, boundsHeight, right, top)
    local edge = reach + 8
    if width + 2 * edge > boundsWidth or height + 2 * edge > boundsHeight then return nil end
    return math.max(edge, math.min(right, boundsWidth - width - edge)), math.max(edge, math.min(top, boundsHeight - height - edge))
end

-- Top-right of WORKSPACE, the card, its shadow and its halo always whole inside it.
-- Returns false (nothing moved) when WORKSPACE is too small for it.
function Card:Layout()
    local frame = self.frame
    if not frame then return false end
    local parent, reach, height = frame:GetParent(), self.reach or 0, Number(frame:GetHeight()) or 0
    local right, top = self.Place(self.width, height, reach, Number(parent:GetWidth()) or math.huge,
        Number(parent:GetHeight()) or math.huge, self.margin, self.top)
    if not right then return false end
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -right, -top)
    self.placement = { right = right, top = top, width = self.width, height = height, reach = reach }
    return true
end

-- spec: kind, heading, title, lines, primary = { label, action }, duration, onClose(reason)
function Card:Show(spec)
    local ok, reason = self:Available()
    if not ok then return false, reason end
    -- A Journey card that matters more (a seal opening, a Contrat sheet) keeps the stage.
    if MS.JourneyCardArbiter and MS.JourneyCardArbiter:Blocks("COMMUNITY") then return false, "ARBITER" end
    if self.spec then
        -- Only a strictly more important moment replaces the visible one.
        if (self.priority[spec.kind] or 0) <= (self.priority[self.spec.kind] or 0) then return false, "BUSY" end
    end
    local surface = self:Surface()
    self:Create(surface)
    -- A WORKSPACE too narrow or short even for the smallest card: refused before anything
    -- visible changes (a card never spills into GAME).
    if not self.Place(self.width, 96, self.reach or 0, Number(surface:GetWidth()) or math.huge,
        Number(surface:GetHeight()) or math.huge, self.margin, self.top) then return false, "NO_SPACE" end
    if self.spec then self:Close("REPLACED") end
    local frame = self.frame
    frame.heading:SetText(spec.heading)
    frame.tag:SetShown(self.experimentalKinds[spec.kind] == true)
    frame.title:SetText(spec.title)
    frame.body:SetText(table.concat(spec.lines or {}, "\n"))
    frame.primary:SetShown(spec.primary ~= nil)
    frame.primary.label:SetText(spec.primary and spec.primary.label or "")
    self:Fit(spec.primary ~= nil)
    if not self:Layout() then
        frame:Hide()
        return false, "NO_SPACE"
    end
    self.spec = spec
    frame:Show()
    self:Arm(spec.duration or 30, "TIMEOUT")
    return true
end

local function Uptime()
    local now = type(_G.GetTime) == "function" and _G.GetTime()
    return type(now) == "number" and now or 0
end

-- The display time only runs while the card can be seen: combat pauses it.
function Card:Arm(seconds, reason)
    if self.timer then self.timer:Cancel(); self.timer = nil end
    self.expiry = reason
    if self.suspended then self.remaining = seconds; return end
    self.deadline, self.remaining = Uptime() + seconds, nil
    self.timer = C_Timer.NewTimer(seconds, function() Card:Close(reason) end)
end

function Card:OnCombat(inCombat)
    if not self.spec or not self.frame then return end
    if inCombat then
        if self.suspended then return end
        self.suspended = true
        self.frame:Hide()
        if self.timer then self.timer:Cancel(); self.timer = nil end
        self.remaining = math.max(0, (self.deadline or 0) - Uptime())
    elseif self.suspended then
        self.suspended = false
        -- A Journey card took the stage meanwhile: this moment does not come back over it.
        if MS.JourneyCardArbiter and MS.JourneyCardArbiter:Blocks("COMMUNITY") then self:Close("ARBITER"); return end
        local surface = self:Surface()
        if not surface then self:Close("NO_SURFACE"); return end
        self.frame:Show()
        self:Arm(math.max(self.remaining or 0, 1), self.expiry or "TIMEOUT")
    end
end

function Card:IsShowing(kind)
    return self.spec ~= nil and (kind == nil or self.spec.kind == kind)
end

function Card:Primary()
    local spec = self.spec
    if not spec or self.suspended or not self:Available() then return end
    if spec.primary and spec.primary.action then spec.primary.action() end
end

-- Replaces the body after an action (e.g. "kept") and closes shortly after.
function Card:Confirm(text, seconds, after)
    if not self.spec or not self.frame then return end
    self.frame.body:SetText(text)
    self.frame.primary:Hide()
    self.spec.onClose = after
    self:Arm(seconds or 4, "CONFIRMED")
end

function Card:Close(reason)
    local spec = self.spec
    self.spec, self.suspended, self.remaining = nil, false, nil
    if self.timer then self.timer:Cancel(); self.timer = nil end
    if self.frame then self.frame:Hide() end
    if spec and spec.onClose then pcall(spec.onClose, reason) end
end

-- Streamer mode turned on while a card is up: it leaves at once.
if MS.BroadcastMode then
    MS.BroadcastMode:Listen(function(on) if on and Card.spec then Card:Close("BROADCAST") end end)
end
