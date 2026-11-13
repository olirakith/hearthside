local MS = _G.MS
MS.Active = MS.Active or {}
-- The small Sur mes pas scene: the surface dims, a wax seal appears and breaks, the words come.
-- Never in combat (a fight hides it; it comes back after). One seal at a time; a seal opened
-- while something else holds the stage waits for its turn, across reloads (seen = false).
local A = MS.Active
local Kit = A.Kit
-- Streamer mode (Workspace/BroadcastMode.lua): another player's name stays out of sight.
local function Person(name) return MS.BroadcastMode and MS.BroadcastMode:Person(name) or name end
local Reveal = { queue = {}, duration = 2.8, width = 440 }
A.Reveal = Reveal

local WAX, WAX_DARK, CRACK = { .55, .09, .07, 1 }, { .36, .05, .04, 1 }, { .10, .02, .02, 1 }

-- Words arrive from the first letter on; a client without the gradient shows them with the card.
local function Unroll(label, letters)
    if type(label.SetAlphaGradient) == "function" then pcall(label.SetAlphaGradient, label, letters, 24) end
end

local function Rect(parent, layer, width, height, color)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetSize(width, height)
    texture:SetColorTexture(color[1], color[2], color[3], color[4])
    return texture
end

function Reveal:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "HearthsideSealReveal", _G.UIParent)
    Kit.Zoom(frame)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:Hide()
    frame.dim = frame:CreateTexture(nil, "BACKGROUND")
    frame.dim:SetAllPoints(frame)
    frame.dim:SetColorTexture(0, 0, 0, .55)
    -- The seal: a block of wax in two halves that slide apart (plain colour, no asset).
    frame.seal = CreateFrame("Frame", nil, frame)
    frame.seal:SetSize(120, 120)
    frame.seal:SetPoint("CENTER", frame, "CENTER", 0, 40)
    frame.left = Rect(frame.seal, "ARTWORK", 44, 88, WAX)
    frame.right = Rect(frame.seal, "ARTWORK", 44, 88, WAX_DARK)
    frame.crack = Rect(frame.seal, "OVERLAY", 2, 88, CRACK)
    frame.crack:SetPoint("CENTER", frame.seal, "CENTER", 0, 0)
    frame.mark = Kit.Label(frame.seal, "PAGE_TITLE", "gold", "CENTER")
    frame.mark:SetPoint("CENTER", frame.seal, "CENTER", 0, 0)
    frame.mark:SetText(MS.L.SEAL_MARK)
    -- The card with the words.
    local card = CreateFrame("Frame", nil, frame)
    card:SetSize(self.width, 220)
    card:SetPoint("CENTER", frame, "CENTER", 0, 0)
    local style = MS.JourneyUIStyle
    if style and style.Elevate then style:Elevate(card, 4, true) end
    card.border = card:CreateTexture(nil, "BACKGROUND")
    card.border:SetAllPoints(card)
    Kit.Fill(card.border, "gold")
    card.back = card:CreateTexture(nil, "BORDER")
    card.back:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
    card.back:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -1, 1)
    Kit.Fill(card.back, "overlay")
    card.heading = Kit.Label(card, "SMALL", "gold")
    card.heading:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -18)
    card.heading:SetText(MS.L.SEAL_REVEAL_HEADING)
    card.from = Kit.Label(card, "SECONDARY", "textSecondary")
    card.from:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -40)
    card.from:SetWidth(self.width - 40)
    card.words = Kit.Label(card, "BODY_LARGE", "textBright")
    card.words:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -82)
    card.words:SetWidth(self.width - 40)
    card.place = Kit.Label(card, "SECONDARY", "muted")
    card.place:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 20, 54)
    card.place:SetWidth(self.width - 40)
    card.reply = Kit.Button(card, 180, 28, function() Reveal:Reply() end)
    card.reply:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 20, 16)
    card.close = Kit.Button(card, 120, 28, function() Reveal:Close("PLAYER") end)
    card.close:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -20, 16)
    card.close:SetLabel(MS.L.ACTIVE_CLOSE)
    frame.card = card
    if type(_G.UISpecialFrames) == "table" then table.insert(_G.UISpecialFrames, "HearthsideSealReveal") end
    -- Esc hides the scene itself; a host that goes away (the workspace closing) hides only its
    -- parent: the seal then waits and comes back on the game screen, still unread.
    frame:SetScript("OnHide", function(self)
        if Reveal.combatHiding then return end
        Reveal:Close(self:IsShown() and "HOST" or "ESCAPE")
    end)
    frame:SetScript("OnUpdate", function(_, elapsed) Reveal:Animate(elapsed) end)
    self.frame = frame
    return frame
end

-- seal: an OPENED record. again: the player asked to read it again (shown even if seen).
function Reveal:Queue(seal, again)
    for _, queued in ipairs(self.queue) do if queued.seal == seal then return end end
    self.queue[#self.queue + 1] = { seal = seal, again = again == true }
    if again and A.Panel:IsShown() then A.Panel:Close("REVEAL") end
    self:Pump()
end

function Reveal:Pump()
    if self.current or #self.queue == 0 then return end
    if A.Panel.suspended then return self:Retry() end
    local entry = self.queue[1]
    local token, reason = MS.JourneyCardArbiter:Acquire("REVEAL", function() Reveal:Close("REPLACED") end)
    if not token then
        A:Log("CARD_REFUSED", { kind = "REVEAL", reason = reason })
        return self:Retry()
    end
    table.remove(self.queue, 1)
    self.token, self.current, self.again = token, entry.seal, entry.again
    self:Present(entry.seal)
end

function Reveal:Retry()
    if self.retry or not _G.C_Timer then return end
    self.retry = C_Timer.NewTicker(2, function()
        if Reveal.current or #Reveal.queue == 0 then Reveal.retry:Cancel(); Reveal.retry = nil; return end
        Reveal:Pump()
    end)
end

function Reveal:Present(seal)
    local frame = self:Create()
    local host, surface = Kit:Host()
    if frame:GetParent() ~= host then frame:SetParent(host) end
    frame:SetFrameStrata("DIALOG")
    frame:ClearAllPoints()
    frame:SetAllPoints(host)
    local L, card = MS.L, frame.card
    local sealed = Kit.Date(seal.createdAt)
    if seal.kind == "NEXT" then
        card.from:SetText(string.format(L.SEAL_REVEAL_FROM_SELF, seal.author:match("^[^%-]+") or seal.author, sealed))
    else
        card.from:SetText(string.format(L.SEAL_REVEAL_FROM, Person(seal.author:match("^[^%-]+") or seal.author), sealed))
    end
    card.words:SetText(string.format(L.SEAL_REVEAL_WORDS, seal.text))
    card.place:SetText(string.format(L.SEAL_REVEAL_PLACE, A.Position:MapName(seal.mapID) or L.SEAL_SOMEWHERE, Kit.Date(seal.openedAt)))
    -- Reply: to the author (a prepared whisper) or, for a note from one's own character, a new
    -- note left right here.
    card.reply:SetLabel(seal.kind == "NEXT" and L.SEAL_REPLY_HERE or L.SEAL_REPLY)
    card.reply:SetShown(seal.kind == "NEXT" or seal.origin == "IMPORTED")
    self.elapsed, self.cracked = 0, false
    self.lettersPerSecond = math.max(60, #card.words:GetText() / 1.1)
    Unroll(card.words, 0)
    frame.seal:SetShown(true)
    card:SetAlpha(0)
    frame:Show()
    self:Animate(0)
    A:Log("CARD_SHOWN", { kind = "REVEAL", surface = surface })
end

-- Three beats. The wax rises (0 .. 0.7 s), it cracks then parts (0.7 .. 1.4 s), the card comes
-- and the words arrive letter by letter (1.3 .. 2.8 s).
function Reveal:Animate(elapsed)
    local frame = self.frame
    if not frame or not frame:IsShown() or not self.elapsed then return end
    self.elapsed = self.elapsed + (elapsed or 0)
    local t = self.elapsed
    local grow = math.min(1, t / .7)
    grow = 1 - (1 - grow) ^ 2
    local crack = math.max(0, math.min(1, (t - .7) / .25))
    local part = math.max(0, math.min(1, (t - .95) / .45))
    frame.seal:ClearAllPoints()
    frame.seal:SetPoint("CENTER", frame, "CENTER", 0, 40 - (1 - grow) * 24)
    frame.crack:SetShown(crack > 0 and part == 0)
    if crack > 0 and not self.cracked then
        self.cracked = true
        Kit.Play("CRACK")
    end
    frame.crack:SetHeight(math.max(1, 88 * crack))
    frame.left:ClearAllPoints()
    frame.left:SetPoint("CENTER", frame.seal, "CENTER", -22 - part * 60, 0)
    frame.right:ClearAllPoints()
    frame.right:SetPoint("CENTER", frame.seal, "CENTER", 22 + part * 60, 0)
    frame.seal:SetAlpha(grow * (1 - part))
    frame.card:SetAlpha(math.max(0, math.min(1, (t - 1.3) / .4)))
    Unroll(frame.card.words, math.floor(math.max(0, t - 1.6) * self.lettersPerSecond))
    if t >= self.duration then
        frame.seal:SetShown(false)
        frame.card:SetAlpha(1)
        Unroll(frame.card.words, 1024)
        self.elapsed = nil
    end
end

function Reveal:Reply()
    local seal = self.current
    if not seal then return end
    if seal.kind == "NEXT" then
        self:Close("PLAYER")
        A.SealView.kind, A.SealView.tab = "NEXT", "WRITE"
        A.Panel:Open("SEAL")
        return
    end
    local ok, reason = A.Seals:Reply(seal)
    self.frame.card.place:SetText(ok and MS.L.SEAL_REPLY_READY or (MS.L["ACTIVE_CHAT_" .. tostring(reason)] or MS.L.ACTIVE_CHAT_FAILED))
end

function Reveal:Close(reason)
    local seal = self.current
    -- Only a player who saw it closes it for good; a fight, a replacement or a reload bring it back.
    if seal and (reason == "PLAYER" or reason == "ESCAPE") then A.Seals:MarkSeen(seal) end
    if seal and (reason == "REPLACED" or reason == "HOST") then table.insert(self.queue, 1, { seal = seal }) end
    local closing = reason == "PLAYER" and seal and seal.origin == "IMPORTED" and not self.again
    self.current = nil
    if self.frame and self.frame:IsShown() then
        self.combatHiding = true
        self.frame:Hide()
        self.combatHiding = false
    end
    if self.token then
        local token = self.token
        self.token = nil
        MS.JourneyCardArbiter:Release(token)
    end
    -- A seal from someone else gets its Generique once; one's own characters only get the scene.
    if closing and A.Credits then A.Credits:Seal(seal) end
    if reason ~= "REPLACED" then self:Pump() end
end

function Reveal:OnCombat(inCombat)
    if inCombat and self.current then
        local seal = self.current
        self:Close("COMBAT")
        table.insert(self.queue, 1, { seal = seal })
    elseif not inCombat then
        self:Pump()
    end
end

A:Register("Reveal", Reveal)

-- TOAST: a Contrat rule changing state, or one question ------------------------------------------
local Toast = { duration = 6, width = 360 }
A.Toast = Toast

function Toast:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, _G.UIParent)
    frame:SetSize(self.width, 64)
    Kit.Zoom(frame)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:Hide()
    local style = MS.JourneyUIStyle
    if style and style.Elevate then style:Elevate(frame, 3, false) end
    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetAllPoints(frame)
    Kit.Fill(frame.border, "borderActive")
    frame.back = frame:CreateTexture(nil, "BORDER")
    frame.back:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.back:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    Kit.Fill(frame.back, "overlay")
    frame.heading = Kit.Label(frame, "SMALL", "gold")
    frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -10)
    frame.text = Kit.Label(frame, "BODY", "textBright")
    frame.text:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -30)
    frame.text:SetWidth(self.width - 28)
    frame.yes = Kit.Button(frame, 110, 24, function() Toast:Answer(true) end)
    frame.yes:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 10)
    frame.no = Kit.Button(frame, 110, 24, function() Toast:Answer(false) end)
    frame.no:SetPoint("RIGHT", frame.yes, "LEFT", -8, 0)
    frame:SetScript("OnUpdate", function(_, elapsed) Toast:Tick(elapsed) end)
    self.frame = frame
    return frame
end

-- question: true for the Contrat yes/no, or { yes, no, height } for other wording.
function Toast:Present(kind, heading, text, question)
    local token, reason = MS.JourneyCardArbiter:Acquire(kind, function() Toast:Close() end)
    if not token then
        A:Log("CARD_REFUSED", { kind = kind, reason = reason })
        return false
    end
    local frame = self:Create()
    local host, surface = Kit:Host()
    if frame:GetParent() ~= host then frame:SetParent(host) end
    frame:SetFrameStrata("DIALOG")
    frame:ClearAllPoints()
    frame:SetPoint("TOP", host, "TOP", 0, -120)
    frame.heading:SetText(heading)
    frame.text:SetText(text)
    frame.yes:SetShown(question ~= false)
    frame.no:SetShown(question ~= false)
    local wording = type(question) == "table" and question or {}
    if question then
        frame.yes:SetLabel(wording.yes or MS.L.CONTRACT_PROMPT_YES)
        frame.no:SetLabel(wording.no or MS.L.CONTRACT_PROMPT_NO)
    end
    frame:SetHeight(wording.height or (question and 92 or 64))
    self.token, self.kind, self.shownFor = token, kind, 0
    frame:Show()
    Kit.FadeIn(frame)
    A:Log("CARD_SHOWN", { kind = kind, surface = surface })
    return true
end

function Toast:Near()
    return self:Present("NEAR", MS.L.SEAL_NAME, MS.L.SEAL_NEAR, false)
end

-- A code received by whisper. Stays until answered: a card that left on its own would lose it.
function Toast:Offer(offer)
    local L = MS.L
    local text = string.format(L.SEAL_OFFER, Person(offer.sender), A.Position:MapName(offer.mapID) or L.SEAL_SOMEWHERE)
    return self:Present("OFFER", L.SEAL_NAME, text, { yes = L.SEAL_OFFER_KEEP, no = L.SEAL_OFFER_IGNORE, height = 112 })
end

function Toast:Rule(card, status)
    local contract = A.Contracts:Current()
    local param = contract and A.ContractEngine:Param(contract, card)
    local text = string.format(MS.L.CONTRACT_TOAST_RULE, A.ContractText:Title(card, param), (A.ContractText:Verdict(status)))
    self:Present("RULE", MS.L.CONTRACT_NAME, text, false)
end

-- "The dungeon is behind you: end the Contrat?" Asked once per exit; never answered for the player.
function Toast:Prompt()
    if self:Present("PROMPT", MS.L.CONTRACT_NAME, MS.L.CONTRACT_PROMPT_DUNGEON_END, true) then
        self.pendingPrompt = false
        return
    end
    -- Busy, cooling down or in a fight: asked again a little later while the contract runs.
    self.pendingPrompt = true
    if not self.retry and _G.C_Timer then
        self.retry = C_Timer.NewTicker(5, function()
            if not Toast.pendingPrompt or not A.Contracts:Current() then
                Toast.pendingPrompt = false
                Toast.retry:Cancel(); Toast.retry = nil
                return
            end
            if not A.Contracts:Current() or A.Bool(A.Call(_G.InCombatLockdown)) == true then return end
            Toast:Prompt()
        end)
    end
end

function Toast:Answer(yes)
    local kind = self.kind
    self:Close()
    if kind == "OFFER" then A.SealOffers:Answer(yes)
    elseif yes then A.Contracts:Finish("ENDED") end
end

function Toast:Tick(elapsed)
    if not self.token or self.kind == "OFFER" then return end
    self.shownFor = self.shownFor + (elapsed or 0)
    local limit = self.kind == "PROMPT" and 30 or self.duration
    if self.shownFor >= limit then self:Close() end
end

function Toast:Close()
    if self.frame then self.frame:Hide() end
    if self.token then
        local token = self.token
        self.token = nil
        MS.JourneyCardArbiter:Release(token)
    end
end

function Toast:OnCombat(inCombat)
    if inCombat then self:Close()
    elseif self.pendingPrompt and A.Contracts:Current() then
        self:Prompt()
    end
end

A:Register("Toast", Toast)
