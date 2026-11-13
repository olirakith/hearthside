local MS = _G.MS

-- Contrat en direct: a large view over Journey's content area, made to be read on a stream.
-- Before the signature it shows three Contrats for the chat to vote on (A, B, C), revealed one
-- click at a time, and the poll text to copy. While a Contrat runs: the clock and the rules. At
-- the end: the verdict, and the Generique only when the streamer clicks. It reads the Contrat and
-- signs through the same calls as the Contrat window; nothing is sent anywhere.
MS.JourneyLiveView = {}
local Live = MS.JourneyLiveView

local LETTERS = { "A", "B", "C" }
-- Stamps on paper need dark ink: the screen's success and warning colours are made for dark
-- backgrounds.
local INK = {
    success = { .17, .36, .12 }, critical = { .58, .16, .1 }, warning = { .55, .33, .06 },
    textSecondary = { .33, .26, .17 }, textPrimary = { .17, .127, .079 },
}

local function A() return MS.Active end
local function Style() return MS.JourneyUIStyle end
local function L() return MS.L end

function Live:IsOpen() return self.frame ~= nil and self.frame:IsShown() end

-- Text a little larger than Journey's own, never under one and a half times its body size.
function Live:Factor(rect)
    local fit = math.min(rect.width / 1000, rect.height / 560)
    return math.max(1.5, math.min(2.4, fit))
end

function Live:Label(parent, token, color, justify, weight, onPaper)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label.onPaper = onPaper == true
    -- Ink on paper has no shadow; light text on the dark ground keeps the game's.
    if label.onPaper and label.SetShadowOffset then label:SetShadowOffset(0, 0) end
    label:SetJustifyH(justify or "LEFT")
    label:SetJustifyV("TOP")
    if label.SetWordWrap then label:SetWordWrap(true) end
    self.labels[#self.labels + 1] = { label = label, token = token, weight = weight or 1 }
    self:Ink(label, color)
    return label
end

function Live:Ink(label, color)
    local ink = INK[color]
    if label.onPaper and ink then label:SetTextColor(ink[1], ink[2], ink[3]); return end
    Style():Text(label, color or "textPrimary")
end

local function Fill(frame, token, alpha)
    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(frame)
    Style():Color(texture, token)
    if alpha then texture:SetAlpha(alpha) end
    return texture
end

-- A framed button with its own label, sized by Layout.
function Live:Button(parent, onClick, strong)
    local button = CreateFrame("Button", nil, parent)
    button.fill = Fill(button, strong and "gold" or "backgroundRaised", strong and 1 or .8)
    button.label = self:Label(button, "BODY", strong and "ink" or "gold", "CENTER")
    if strong then button.label:SetTextColor(.11, .08, .05) end
    button.label:SetPoint("LEFT", button, "LEFT", 8, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    button:SetScript("OnClick", function(self) if self.enabled ~= false and onClick then onClick(self) end end)
    button:SetScript("OnEnter", function(self) if self.enabled ~= false then self.fill:SetAlpha(strong and .85 or 1) end end)
    button:SetScript("OnLeave", function(self) self.fill:SetAlpha(strong and 1 or .8) end)
    function button:SetLabel(text) self.label:SetText(text or "") end
    function button:SetActive(on)
        self.enabled = on ~= false
        self:SetAlpha(self.enabled and 1 or .45)
    end
    return button
end

-- A paper card: three rule lines with a stamp each (used by every state).
function Live:Card(parent)
    local card = CreateFrame("Button", nil, parent)
    card.paper = Fill(card, "paperRaised")
    card.edge = CreateFrame("Frame", nil, card)
    card.edge:SetAllPoints(card)
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local line = card.edge:CreateTexture(nil, "OVERLAY")
        line:SetPoint(side[1], card, side[1]); line:SetPoint(side[2], card, side[2])
        if side[1] == "TOPLEFT" and side[2] == "BOTTOMLEFT" or side[1] == "TOPRIGHT" then line:SetWidth(4) else line:SetHeight(4) end
        Style():Color(line, "gold")
    end
    card.edge:Hide()
    card.letter = self:Label(card, "PAGE_TITLE", "textPrimary", "LEFT", 1.1, true)
    card.caption = self:Label(card, "BODY", "textSecondary", "LEFT", 1, true)
    card.rows = {}
    for index = 1, 3 do
        local row = {}
        row.title = self:Label(card, "TITLE", "textPrimary", "LEFT", 1, true)
        row.sub = self:Label(card, "SECONDARY", "textSecondary", "LEFT", 1, true)
        if row.sub.SetMaxLines then row.sub:SetMaxLines(2) end
        row.stamp = self:Label(card, "HEADING", "success", "RIGHT", 1.05, true)
        card.rows[index] = row
    end
    -- Face down: a dark back with the letter and the reveal button.
    card.back = CreateFrame("Frame", nil, card)
    card.back:SetAllPoints(card)
    Fill(card.back, "backgroundPanel")
    card.back.letter = self:Label(card.back, "PAGE_TITLE", "bronze", "CENTER", 2.2)
    card.back.note = self:Label(card.back, "BODY", "textSecondary", "CENTER")
    card.back.reveal = self:Button(card.back, function() Live:Reveal() end, true)
    card.back:Hide()
    return card
end

function Live:Create(parent)
    if self.frame then return end
    self.labels = {}
    local frame = CreateFrame("Frame", "HearthsideLiveView", parent)
    frame:EnableMouse(true)
    Fill(frame, "backgroundDeep")
    frame:Hide()
    frame:SetScript("OnHide", function() Live:OnHidden() end)
    frame:SetScript("OnUpdate", function(_, elapsed) Live:OnUpdate(elapsed) end)
    -- Esc leaves the view like any game window.
    if type(_G.UISpecialFrames) == "table" then table.insert(_G.UISpecialFrames, "HearthsideLiveView") end
    self.frame = frame
    self.badge = self:Label(frame, "SMALL", "gold", "LEFT")
    self.badge:SetText(L().CONTRACT_LIVE_BADGE)
    self.quit = self:Button(frame, function() Live:Close() end)
    self.quit:SetLabel(L().CONTRACT_LIVE_QUIT)
    self.title = self:Label(frame, "PAGE_TITLE", "gold", "LEFT", 1.2)
    self.subtitle = self:Label(frame, "TITLE", "textSecondary", "LEFT")
    self.cards = {}
    for index = 1, 3 do
        local card = self:Card(frame)
        card:SetScript("OnClick", function() Live:Pick(index) end)
        self.cards[index] = card
    end
    -- Poll text: a plain edit box the streamer selects and copies.
    self.pollHead = self:Label(frame, "SMALL", "gold")
    self.pollHead:SetText(L().CONTRACT_LIVE_POLL_HEAD)
    self.poll = CreateFrame("EditBox", nil, frame)
    self.poll:SetMultiLine(true)
    self.poll:SetAutoFocus(false)
    if self.poll.SetFontObject then self.poll:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlight) end
    self.poll.back = Fill(self.poll, "backgroundPanel")
    if self.poll.SetTextInsets then self.poll:SetTextInsets(10, 10, 8, 8) end
    self.labels[#self.labels + 1] = { label = self.poll, token = "BODY", weight = 1 }
    self.poll:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    -- Typing never changes what was drawn: the text comes back as it was.
    self.poll:SetScript("OnTextChanged", function(box, user) if user and Live.pollText then box:SetText(Live.pollText); box:HighlightText() end end)
    self.copy = self:Button(frame, function() Live:Copy() end)
    self.copy:SetLabel(L().CONTRACT_LIVE_COPY)
    self.redraw = self:Button(frame, function() Live:Draw() end)
    self.redraw:SetLabel(L().CONTRACT_LIVE_REDRAW)
    self.sign = self:Button(frame, function() Live:Sign() end, true)
    self.hint = self:Label(frame, "BODY", "textSecondary")
    -- Running: the clock on the left, the rules on the right.
    self.clock = self:Label(frame, "PAGE_TITLE", "textPrimary", "LEFT", 3.2)
    self.left = self:Label(frame, "TITLE", "gold")
    self.barBack = frame:CreateTexture(nil, "ARTWORK")
    Style():Color(self.barBack, "backgroundRaised")
    self.bar = frame:CreateTexture(nil, "OVERLAY")
    Style():Color(self.bar, "gold")
    self.level = self:Label(frame, "TITLE", "textPrimary")
    self.announce = self:Button(frame, function() Live:Announce() end)
    self.announce:SetLabel(L().CONTRACT_ANNOUNCE)
    -- Result: the score and the three actions.
    self.score = self:Label(frame, "PAGE_TITLE", "gold", "CENTER", 2.6)
    self.credits = self:Button(frame, function() Live:Credits() end, true)
    self.credits:SetLabel(L().CONTRACT_LIVE_CREDITS)
    self.sheet = self:Button(frame, function() Live:OpenSheet() end)
    self.sheet:SetLabel(L().CONTRACT_LIVE_SHEET)
    self.again = self:Button(frame, function() Live:Again() end)
    self.again:SetLabel(L().CONTRACT_LIVE_NEW)
end

-- Journey hands over its content area on every layout, open or not.
function Live:Layout(rect)
    self.rect = rect
    if not self.frame or not rect then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    self.frame:SetSize(math.max(1, rect.width), math.max(1, rect.height))
    if self:IsOpen() then self:Render() end
end

-- Streamers only: the setting in Diffusion.
function Live:Enabled()
    local settings = MS.JourneySettings
    return settings ~= nil and settings:Get("contractLive") == true
end

function Live:Open()
    if not self:Enabled() then return false end
    local active = A()
    if not (active and active.Ready and active:Ready()) then
        if active and active.Say then active:Say("ACTIVE_NOT_READY") end
        return false
    end
    local Journey = MS.JourneyWorkspace
    if not self.frame and Journey and Journey.active and MS.Workspace.frame then self:Create(MS.Workspace.frame) end
    if not self.frame then return false end
    if active.Panel and active.Panel:IsShown() then active.Panel:Close("LIVE") end
    local parent = self.frame:GetParent() or MS.Workspace.frame
    local strata = parent.GetFrameStrata and parent:GetFrameStrata()
    self.frame:SetFrameStrata(type(strata) == "string" and strata or "MEDIUM")
    local level = parent.GetFrameLevel and parent:GetFrameLevel()
    self.frame:SetFrameLevel(math.min(9000, (type(level) == "number" and level or 1) + 200))
    if Journey and Journey.contentRect then self:Layout(Journey.contentRect) end
    self.frame:Show()
    self:Render()
    return true
end

function Live:Close()
    if self.frame and self.frame:IsShown() then self.frame:Hide() end
end

-- A result left on screen gets the usual ending once the view is gone.
function Live:OnHidden()
    local active = A()
    if self.creditsQueued or not active or not active.Contracts then return end
    if active.Contracts:Unseen() and active.Sheet then active.Sheet:Queue() end
end

function Live:State()
    local contracts = A().Contracts
    if contracts:Current() then return "RUNNING" end
    if contracts:Unseen() then return "RESULT" end
    return "OPTIONS"
end

-- Solo first; a group Contrat when the player stands in a dungeon with a group.
function Live:Mode()
    local contracts = A().Contracts
    for _, mode in ipairs({ "SOLO", "GROUP" }) do
        local _, context = contracts:Pool(mode)
        if not contracts:Refusal(mode, context) then return mode, context end
    end
    local _, context = contracts:Pool("SOLO")
    return nil, context, contracts:Refusal("SOLO", context)
end

function Live:Draw()
    if self.copied then return end
    local mode = self:Mode()
    self.mode = mode
    self.options = mode and A().Contracts:DrawOptions(mode, 3) or nil
    self.revealed, self.picked, self.copied = 0, nil, false
    self.pollText = self.options and A().ContractText:PollText(self.options) or nil
    self:Render()
end

function Live:Reveal()
    if not self.options or self.revealed >= #self.options then return end
    self.revealed = self.revealed + 1
    local kit = A().Kit
    if kit then kit.Play("CARD"); kit.FadeIn(self.cards[self.revealed], .35) end
    self:Render()
end

function Live:Copy()
    if not self.pollText or self.revealed < #(self.options or {}) then return end
    self.copied = true
    self.poll:SetText(self.pollText)
    self.poll:SetFocus()
    self.poll:HighlightText()
    self:Render()
end

function Live:Pick(index)
    if self:State() ~= "OPTIONS" or not self.options or index > self.revealed then return end
    self.picked = index
    self:Render()
end

function Live:Sign()
    if not self.picked or not self.options then return end
    local contract, reason = A().Contracts:Start(self.mode, self.options[self.picked], "DRAW")
    if not contract then
        self.feedback = L()["CONTRACT_REFUSED_" .. tostring(reason)] or L().CONTRACT_REFUSED_CARD
        self:Render()
        return
    end
    self.chosen = LETTERS[self.picked]
    self.options, self.feedback, self.creditsQueued = nil, nil, false
    if A().Kit then A().Kit.Play("SIGN") end
    self:Render()
end

function Live:Announce()
    local contracts = A().Contracts
    local ok, reason
    if contracts:Current() then ok, reason = contracts:Announce("START")
    else ok, reason = contracts:Announce("RESULT", contracts:Unseen()) end
    self.feedback = ok and L().CONTRACT_ANNOUNCE_READY or (L()["ACTIVE_CHAT_" .. tostring(reason)] or L().ACTIVE_CHAT_FAILED)
    self:Render()
end

function Live:Credits()
    local result = A().Contracts:Unseen()
    if not result or not A().Credits then return end
    self.creditsQueued = true
    A().Credits:Contract(result)
    self:Render()
end

function Live:OpenSheet()
    if A().Panel then A().Panel:Open("SHEET") end
end

-- The result is read: back to a fresh vote.
function Live:Again()
    local result = A().Contracts:Unseen()
    if result then result.seen = true end
    self.chosen, self.feedback, self.creditsQueued = nil, nil, false
    self:Draw()
end

function Live:OnUpdate(elapsed)
    self.tick = (self.tick or 0) + (elapsed or 0)
    if self.tick < 1 then return end
    self.tick = 0
    local state = self:State()
    if state == "RUNNING" or state ~= self.shown then self:Render() end
end

-- Called by the Contrat when something it shows has changed.
function Live:Refresh()
    if self:IsOpen() then self:Render() end
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local hours, minutes, rest = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
    if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, rest) end
    return string.format("%02d:%02d", minutes, rest)
end

function Live:Render()
    if not self.frame or not self.rect then return end
    local state = self:State()
    if state == "OPTIONS" and not self.options and self.shown ~= "OPTIONS" then
        self.shown = "OPTIONS"
        return self:Draw()
    end
    if state ~= "OPTIONS" then self.copied = false end
    self.shown = state
    local scale = self:Factor(self.rect) * (MS.JourneySettings:Get("textScale") or 1)
    for _, entry in ipairs(self.labels) do Style():ApplyAt(entry.label, entry.token, scale * entry.weight) end
    local options, running, result = state == "OPTIONS", state == "RUNNING", state == "RESULT"
    for _, item in ipairs({ self.pollHead, self.poll, self.copy, self.redraw, self.sign }) do item:SetShown(options) end
    for _, item in ipairs({ self.clock, self.left, self.barBack, self.bar, self.level }) do item:SetShown(running) end
    self.announce:SetShown(running or result)
    for _, item in ipairs({ self.score, self.credits, self.sheet, self.again }) do item:SetShown(result) end
    self:PlaceChrome(scale)
    if options then self:RenderOptions(scale)
    elseif running then self:RenderRunning(scale)
    else self:RenderResult(scale) end
end

function Live:PlaceChrome(scale)
    local frame, pad = self.frame, math.floor(18 * scale)
    self.quit:ClearAllPoints()
    self.quit:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad * .6)
    self.quit:SetSize(math.floor(150 * scale), math.floor(22 * scale))
    self.badge:ClearAllPoints()
    self.badge:SetPoint("RIGHT", self.quit, "LEFT", -pad, 0)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", frame, "TOPLEFT", pad * 1.6, -pad * 2.2)
    self.title:SetWidth(math.max(1, frame:GetWidth() - pad * 3.2))
    self.subtitle:ClearAllPoints()
    self.subtitle:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -pad * .4)
    self.subtitle:SetWidth(math.max(1, frame:GetWidth() - pad * 3.2))
    self.hint:ClearAllPoints()
    self.hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad * 1.6, pad)
    self.hint:SetWidth(math.max(1, frame:GetWidth() * .55))
    self.hint:SetJustifyH("LEFT")
end

-- One rule line on a card: title, small line, and the stamp.
function Live:FillRow(row, title, sub, stamp, color)
    row.title:SetText(title or ""); row.sub:SetText(sub or ""); row.stamp:SetText(stamp or "")
    self:Ink(row.stamp, color or "textSecondary")
end

-- stamp: "RIGHT" beside each rule (running), "BELOW" under the one rule (result), nil (vote).
function Live:PlaceCard(card, x, y, w, h, scale, rows, stamp)
    -- A one-rule card (running, result) keeps tighter margins than a card of the vote.
    local pad = math.floor((rows == 1 and 9 or 14) * scale)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
    card:SetSize(math.max(1, w), math.max(1, h))
    card.letter:ClearAllPoints()
    card.letter:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -pad * .7)
    card.caption:ClearAllPoints()
    card.caption:SetPoint("LEFT", card.letter, "RIGHT", pad * .6, 0)
    local top = pad + (card.letter:IsShown() and math.floor(card.letter:GetStringHeight() + pad * .2) or 0)
    local stampWidth = stamp == "RIGHT" and math.floor(w * .3) or 0
    local rowTop = top
    for index, row in ipairs(card.rows) do
        local shown = index <= rows
        row.title:SetShown(shown); row.sub:SetShown(shown); row.stamp:SetShown(shown)
        row.title:ClearAllPoints()
        if index == 1 then row.title:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -rowTop)
        else row.title:SetPoint("TOPLEFT", card.rows[index - 1].sub, "BOTTOMLEFT", 0, -pad * .45) end
        row.title:SetWidth(math.max(1, w - pad * 2 - stampWidth))
        row.sub:ClearAllPoints(); row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
        row.sub:SetWidth(math.max(1, w - pad * 2 - stampWidth))
        row.stamp:ClearAllPoints()
        if stamp == "BELOW" then
            row.stamp:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", pad, pad)
            row.stamp:SetWidth(math.max(1, w - pad * 2)); row.stamp:SetJustifyH("LEFT")
        else
            row.stamp:SetPoint("TOPRIGHT", card, "TOPRIGHT", -pad, -rowTop)
            row.stamp:SetWidth(math.max(1, stampWidth)); row.stamp:SetJustifyH("RIGHT")
        end
    end
    card.back.letter:ClearAllPoints(); card.back.letter:SetPoint("CENTER", card.back, "CENTER", 0, h * .14)
    card.back.note:ClearAllPoints(); card.back.note:SetPoint("TOP", card.back.letter, "BOTTOM", 0, -pad)
    card.back.note:SetWidth(math.max(1, w - pad * 2))
    card.back.reveal:ClearAllPoints(); card.back.reveal:SetPoint("TOP", card.back.note, "BOTTOM", 0, -pad)
    card.back.reveal:SetSize(math.min(w - pad * 2, math.floor(170 * scale)), math.floor(28 * scale))
end

function Live:RenderOptions(scale)
    local T, Lc = A().ContractText, L()
    local frame, pad = self.frame, math.floor(18 * scale)
    local width, height = frame:GetWidth(), frame:GetHeight()
    self.title:SetText(Lc.CONTRACT_LIVE_POLL_TITLE)
    local mode, context, refusal = self:Mode()
    local level = context and context.level
    if mode == "SOLO" and type(level) == "number" then
        self.subtitle:SetText(string.format(Lc.CONTRACT_LIVE_SUBTITLE, level, level + 1))
    elseif mode == "GROUP" then
        self.subtitle:SetText(string.format(Lc.CONTRACT_LIVE_SUBTITLE_GROUP, Lc.CONTRACT_TITLE_DUNGEON))
    else
        self.subtitle:SetText(Lc["CONTRACT_REFUSED_" .. tostring(refusal)] or Lc.CONTRACT_REFUSED_CARD)
    end
    local top = pad * 2.2 + self.title:GetStringHeight() + self.subtitle:GetStringHeight() + pad * 1.4
    local bottomBand = math.floor(74 * scale)
    local gap = pad * 1.4
    local cardWidth = math.floor((width - pad * 3.2 - gap * 2) / 3)
    local cardHeight = math.max(60, height - top - bottomBand - pad * 2)
    for index, card in ipairs(self.cards) do
        local cards = self.options and self.options[index]
        card:SetShown(cards ~= nil)
        if cards then
            self:PlaceCard(card, pad * 1.6 + (index - 1) * (cardWidth + gap), top, cardWidth, cardHeight, scale, 3)
            local open = index <= self.revealed
            card.back:SetShown(not open)
            card.edge:SetShown(self.picked == index)
            card.letter:SetShown(true)
            card.letter:SetText(LETTERS[index])
            card.caption:SetText(string.format(Lc.CONTRACT_LIVE_OPTION, LETTERS[index]))
            for slot, row in ipairs(card.rows) do
                local entry = cards[slot]
                if entry then
                    -- The title and what kind of rule it is: the descriptions do not fit three to a card.
                    self:FillRow(row, T:Title(entry.id, entry.param), T:ModeTag(entry.id, self.mode, A().caps), "")
                else
                    self:FillRow(row, "", "", "")
                end
            end
            card.back.letter:SetText(LETTERS[index])
            card.back.note:SetText(Lc.CONTRACT_LIVE_HIDDEN)
            card.back.reveal:SetShown(index == self.revealed + 1)
            card.back.reveal:SetLabel(string.format(Lc.CONTRACT_LIVE_REVEAL, LETTERS[index]))
        end
    end
    -- The poll band.
    local bandTop = top + cardHeight + pad * 1.2
    local sideWidth = math.floor(width * .3)
    local boxWidth = width - pad * 3.2 - sideWidth - gap
    self.pollHead:ClearAllPoints()
    self.pollHead:SetPoint("TOPLEFT", frame, "TOPLEFT", pad * 1.6, -bandTop)
    self.poll:ClearAllPoints()
    self.poll:SetPoint("TOPLEFT", self.pollHead, "BOTTOMLEFT", 0, -6)
    self.poll:SetSize(math.max(1, boxWidth), math.max(1, bottomBand - pad * 1.4))
    local all = self.options ~= nil and self.revealed >= #self.options
    local want = all and self.pollText or ""
    if self.poll:GetText() ~= want then self.poll:SetText(want) end
    local buttonHeight = math.floor(26 * scale)
    self.copy:ClearAllPoints()
    self.copy:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad * 1.6, -bandTop)
    self.copy:SetSize(sideWidth, buttonHeight)
    self.copy:SetActive(all)
    self.redraw:ClearAllPoints()
    self.redraw:SetPoint("TOPRIGHT", self.copy, "BOTTOMRIGHT", 0, -8)
    self.redraw:SetSize(math.floor((sideWidth - 8) / 2), buttonHeight)
    self.redraw:SetActive(mode ~= nil and not self.copied)
    self.sign:ClearAllPoints()
    self.sign:SetPoint("TOPRIGHT", self.redraw, "TOPLEFT", -8, 0)
    self.sign:SetSize(math.floor((sideWidth - 8) / 2), buttonHeight)
    self.sign:SetLabel(self.picked and string.format(Lc.CONTRACT_LIVE_SIGN, LETTERS[self.picked]) or Lc.CONTRACT_LIVE_PICK)
    self.sign:SetActive(self.picked ~= nil)
    self.hint:ClearAllPoints()
    self.hint:SetPoint("TOPRIGHT", self.redraw, "BOTTOMRIGHT", 0, -8)
    self.hint:SetWidth(sideWidth)
    self.hint:SetJustifyH("LEFT")
    self.hint:SetText(self.feedback or (self.copied and Lc.CONTRACT_LIVE_COPIED or Lc.CONTRACT_LIVE_COPY_HINT))
end

function Live:RenderRunning(scale)
    local active, Lc = A(), L()
    local T, Engine = active.ContractText, active.ContractEngine
    local contract = active.Contracts:Current()
    local frame, pad = self.frame, math.floor(18 * scale)
    local width, height = frame:GetWidth(), frame:GetHeight()
    self.title:SetText(self.chosen and string.format(Lc.CONTRACT_LIVE_CHOSEN, self.chosen) or T:ContractTitle(contract.goal))
    self.subtitle:SetText("")
    local elapsed = Engine:Elapsed(contract, active.Now()) or 0
    local limit = Engine:Param(contract, "TIME_LIMIT")
    self.clock:SetText(Clock(elapsed))
    local leftWidth = math.floor(width * .36)
    local top = pad * 2.2 + self.title:GetStringHeight() + pad
    self.clock:ClearAllPoints(); self.clock:SetPoint("TOPLEFT", frame, "TOPLEFT", pad * 1.6, -top)
    self.clock:SetWidth(leftWidth)
    self.left:ClearAllPoints(); self.left:SetPoint("TOPLEFT", self.clock, "BOTTOMLEFT", 0, -pad * .6)
    self.left:SetWidth(leftWidth)
    self.barBack:ClearAllPoints(); self.barBack:SetPoint("TOPLEFT", self.left, "BOTTOMLEFT", 0, -pad * .6)
    self.barBack:SetSize(leftWidth, math.floor(6 * scale))
    if limit then
        self.left:SetText(string.format(Lc.CONTRACT_LIVE_LEFT, T:Duration(math.max(0, limit - elapsed)), T:Limit(limit)))
        local share = math.max(0, math.min(1, elapsed / limit))
        self.bar:ClearAllPoints(); self.bar:SetPoint("TOPLEFT", self.barBack, "TOPLEFT")
        self.bar:SetSize(math.max(1, leftWidth * share), math.floor(6 * scale))
    else
        self.left:SetText("")
    end
    self.barBack:SetShown(limit ~= nil); self.bar:SetShown(limit ~= nil)
    self.level:ClearAllPoints(); self.level:SetPoint("TOPLEFT", self.barBack, "BOTTOMLEFT", 0, -pad * 1.2)
    self.level:SetWidth(leftWidth)
    local goal = contract.goal
    self.level:SetText(goal.kind == "LEVEL" and string.format(Lc.CONTRACT_LIVE_LEVEL, goal.from or 0, goal.target or 0) or (goal.instance or ""))
    -- The rules: one card per rule, stacked.
    local rulesX = pad * 1.6 + leftWidth + pad * 2
    local rulesWidth = width - rulesX - pad * 1.6
    local buttonHeight = math.floor(26 * scale)
    local available = height - top - pad * 2 - buttonHeight - pad
    local count = #contract.cards
    local cardGap = math.floor(pad * .6)
    local rowHeight = math.floor((available - (count - 1) * cardGap) / math.max(1, count))
    for index, card in ipairs(self.cards) do
        local entry = contract.cards[index]
        card:SetShown(entry ~= nil)
        if entry then
            card.back:Hide(); card.edge:Hide(); card.letter:Hide(); card.caption:SetText("")
            self:PlaceCard(card, rulesX, top + (index - 1) * (rowHeight + cardGap), rulesWidth, rowHeight, scale, 1, "RIGHT")
            local rule = contract.rules[entry.id] or {}
            local stamp, color = T:LiveState(rule, Engine:OnTrial(entry.id, contract.mode, active.caps))
            local sub = T:Reason(rule.reason, rule.who) or (rule.status == "HONOR" and Lc.CONTRACT_LIVE_HONOR_LATER) or T:Description(entry.id, contract.mode)
            if rule.status == "BROKEN" and type(rule.at) == "number" then sub = sub .. " · " .. Clock(rule.at - contract.startedAt) end
            self:FillRow(card.rows[1], T:Title(entry.id, entry.param), sub, stamp, color)

        end
    end
    self.announce:ClearAllPoints()
    self.announce:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad * 1.6, pad)
    self.announce:SetLabel(Lc.CONTRACT_ANNOUNCE)
    self.announce:SetSize(math.floor(150 * scale), buttonHeight)
    self.announce:SetActive(not contract.announced.start)
    self.hint:SetText(self.feedback or "")
end

function Live:RenderResult(scale)
    local active, Lc = A(), L()
    local T = active.ContractText
    local result = active.Contracts:Unseen()
    local frame, pad = self.frame, math.floor(18 * scale)
    local width, height = frame:GetWidth(), frame:GetHeight()
    self.title:SetText(string.format(Lc.CONTRACT_LIVE_RESULT_HEAD, T:ContractTitle(result.context), T:Duration(result.duration)))
    self.subtitle:SetText("")
    local kept, total = 0, #result.rules
    for _, rule in ipairs(result.rules) do if rule.verdict == "KEPT" then kept = kept + 1 end end
    self.score:SetText(string.format(Lc.CONTRACT_LIVE_SCORE, kept, total))
    local top = pad * 2.2 + self.title:GetStringHeight() + pad
    self.score:ClearAllPoints(); self.score:SetPoint("TOP", frame, "TOP", 0, -top)
    self.score:SetWidth(width - pad * 3.2)
    local cardsTop = top + self.score:GetStringHeight() + pad * 1.4
    local gap = pad * 1.4
    local cardWidth = math.floor((width - pad * 3.2 - gap * 2) / 3)
    local buttonHeight = math.floor(28 * scale)
    local cardHeight = math.max(60, math.min(math.floor(130 * scale), height - cardsTop - buttonHeight - pad * 4))
    for index, card in ipairs(self.cards) do
        local rule = result.rules[index]
        card:SetShown(rule ~= nil)
        if rule then
            card.back:Hide(); card.edge:Hide(); card.letter:Hide(); card.caption:SetText("")
            self:PlaceCard(card, pad * 1.6 + (index - 1) * (cardWidth + gap), cardsTop, cardWidth, cardHeight, scale, 1, "BELOW")
            local stamp, color = T:Verdict(rule.verdict)
            if not INK[color] then color = "textSecondary" end
            self:FillRow(card.rows[1], T:Title(rule.card, rule.param), "", stamp, color)
        end
    end
    self.hint:ClearAllPoints()
    self.hint:SetPoint("TOP", frame, "TOP", 0, -(cardsTop + cardHeight + pad))
    self.hint:SetWidth(width - pad * 3.2)
    self.hint:SetJustifyH("CENTER")
    local actionsTop = cardsTop + cardHeight + pad * 2 + self.hint:GetStringHeight()
    local wide = math.floor(190 * scale)
    self.credits:ClearAllPoints(); self.credits:SetPoint("TOPRIGHT", frame, "TOP", -4, -actionsTop)
    self.credits:SetSize(wide, buttonHeight)
    self.announce:ClearAllPoints(); self.announce:SetPoint("TOPLEFT", frame, "TOP", 4, -actionsTop)
    self.announce:SetSize(wide, buttonHeight)
    self.announce:SetLabel(Lc.CONTRACT_ANNOUNCE_RESULT_ACTION)
    self.announce:SetActive(not result.announced)
    self.sheet:ClearAllPoints(); self.sheet:SetPoint("TOPRIGHT", self.credits, "BOTTOMRIGHT", 0, -8)
    self.sheet:SetSize(wide, buttonHeight)
    self.again:ClearAllPoints(); self.again:SetPoint("TOPLEFT", self.announce, "BOTTOMLEFT", 0, -8)
    self.again:SetSize(wide, buttonHeight)
    self.credits:SetActive(not self.creditsQueued)
    self.hint:SetText(self.feedback or Lc.CONTRACT_LIVE_HINT_RESULT)
end
