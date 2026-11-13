local MS = _G.MS
MS.Active = MS.Active or {}
-- The Generique: how Journey closes an experience. One line at a time on a dark screen, then the
-- actions. Shows only what the result or the seal already holds. Never in combat: a fight hides it
-- and it comes back after. An abandoned Contrat keeps its plain sheet.
local A = MS.Active
local Kit = A.Kit
local Credits = { queue = {}, width = 560, beat = 1.1, fade = .6, photoDelay = .2, photoGuard = 3 }
A.Credits = Credits

local function T() return A.ContractText end

function Credits:Wanted()
    local root = A.Store and A.Store.root
    return not (root and root.noCredits)
end

local function Names(result)
    local names, seen = {}, {}
    local function Add(name)
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    Add(result.character and result.character.name)
    -- Streamer mode: the player's own name stays, the companions become a count.
    local mode = MS.BroadcastMode
    if mode and mode:IsOn() then
        local group = result.group and result.group.names or {}
        if #group > 0 then names[#names + 1] = mode:People(group) end
        return table.concat(names, MS.L.CREDITS_NAME_SEPARATOR)
    end
    for _, name in ipairs(result.group and result.group.names or {}) do Add(name) end
    return table.concat(names, MS.L.CREDITS_NAME_SEPARATOR)
end

-- What a finished Contrat says, line by line.
function Credits:ForContract(result)
    local L, context = MS.L, result.context
    local title
    if context.goal == "LEVEL" and context.from and context.target then
        title = string.format(L.CONTRACT_CONTEXT_SOLO, context.from, context.target)
    else
        title = context.instance or T():ContractTitle(context)
    end
    local together = #(result.group and result.group.names or {}) > 0
    local lines = { eyebrow = string.format(L.CREDITS_CONTRACT_EYEBROW, (T():Verdict(result.verdict))), title = title,
        sub = string.format(together and L.CREDITS_SUB_GROUP or L.CREDITS_SUB, Kit.Date(result.endedAt),
            T():Duration(result.duration)),
        rules = {}, names = Names(result) }
    for _, rule in ipairs(result.rules) do
        local stamp, color = T():Verdict(rule.verdict)
        lines.rules[#lines.rules + 1] = { title = T():Title(rule.card, rule.param), stamp = stamp, color = color }
    end
    return lines
end

-- What a seal from someone else says, once its words have been read.
function Credits:ForSeal(seal)
    local L = MS.L
    local days = A.SealBook.Days(seal.createdAt, seal.openedAt)
    local opened = Kit.Date(seal.openedAt)
    local sub = days == 0 and string.format(L.CREDITS_SEAL_SUB_TODAY, opened)
        or days == 1 and string.format(L.CREDITS_SEAL_SUB_DAY, opened)
        or string.format(L.CREDITS_SEAL_SUB, days, opened)
    local author = seal.author:match("^[^%-]+") or seal.author
    if MS.BroadcastMode then author = MS.BroadcastMode:Person(author) end
    local reader = A.identity and A.identity.firstName
    return { eyebrow = L.CREDITS_SEAL_EYEBROW, title = A.Position:MapName(seal.mapID) or L.SEAL_SOMEWHERE, sub = sub,
        quote = string.format(L.SEAL_ROW_OPENED, seal.text),
        names = reader and string.format(L.CREDITS_SEAL_FROM_TO, author, reader) or string.format(L.CREDITS_SEAL_FROM, author) }
end

local function Beat(parent, y, height)
    local beat = CreateFrame("Frame", nil, parent)
    beat:SetSize(Credits.width, height)
    beat:SetPoint("TOP", parent, "CENTER", 0, y)
    return beat
end

local function Line(beat, token, color, y)
    local label = Kit.Label(beat, token, color, "CENTER")
    label:SetPoint("TOP", beat, "TOP", 0, y)
    label:SetWidth(Credits.width)
    return label
end

function Credits:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "HearthsideCredits", _G.UIParent)
    Kit.Zoom(frame)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:Hide()
    frame.dim = frame:CreateTexture(nil, "BACKGROUND")
    frame.dim:SetAllPoints(frame)
    frame.dim:SetColorTexture(.03, .02, .01, .92)

    local head = Beat(frame, 190, 76)
    frame.eyebrow = Line(head, "SMALL", "gold", 0)
    frame.title = Line(head, "PAGE_TITLE", "textBright", -22)
    local sub = Beat(frame, 110, 24)
    frame.sub = Line(sub, "BODY", "textSecondary", 0)
    local body = Beat(frame, 70, 96)
    frame.quote = Line(body, "BODY_LARGE", "textBright", 0)
    frame.rows = {}
    for index = 1, 3 do
        local row = CreateFrame("Frame", nil, body)
        row:SetSize(440, 28)
        row:SetPoint("TOP", body, "TOP", 0, -(index - 1) * 30)
        row.title = Kit.Label(row, "BODY", "textPrimary")
        row.title:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.title:SetWidth(270)
        row.stamp = Kit.Label(row, "SMALL", "success", "RIGHT")
        row.stamp:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.stamp:SetWidth(160)
        frame.rows[index] = row
    end
    local names = Beat(frame, -40, 28)
    frame.names = Line(names, "BODY_LARGE", "textPrimary", 0)
    local sign = Beat(frame, -84, 20)
    frame.sign = Line(sign, "SMALL", "muted", 0)
    frame.sign:SetText(MS.L.CREDITS_SIGN)
    frame.beats = { head, sub, body, names, sign }

    local actions = CreateFrame("Frame", nil, frame)
    actions:SetSize(self.width, 134)
    actions:SetPoint("TOP", frame, "CENTER", 0, -130)
    frame.actions = actions
    frame.primary = Kit.Button(actions, 170, 30, function() Credits:Primary() end)
    frame.primary:SetPoint("TOP", actions, "TOP", -199, 0)
    frame.sheet = Kit.Button(actions, 130, 30, function() Credits:OpenSheet() end)
    frame.sheet:SetPoint("LEFT", frame.primary, "RIGHT", 8, 0)
    frame.sheet:SetLabel(MS.L.CREDITS_OPEN_SHEET)
    frame.poster = Kit.Button(actions, 130, 30, function() Credits:Poster() end)
    frame.poster:SetPoint("LEFT", frame.sheet, "RIGHT", 8, 0)
    frame.poster:SetLabel(MS.L.POSTER_CREATE)
    frame.close = Kit.Button(actions, 110, 30, function() Credits:Close("PLAYER") end)
    frame.close:SetPoint("LEFT", frame.poster, "RIGHT", 8, 0)
    frame.close:SetLabel(MS.L.ACTIVE_CLOSE)
    frame.photo = Kit.Button(actions, 170, 30, function() Credits:Photo() end)
    frame.photo:SetPoint("TOP", actions, "TOP", 0, -38)
    frame.photo:SetLabel(MS.L.POSTER_PHOTO)
    frame.feedback = Kit.Label(actions, "SECONDARY", "textSecondary", "CENTER")
    frame.feedback:SetPoint("TOP", actions, "TOP", 0, -76)
    frame.code = Kit.Input(actions, self.width, 2000)
    frame.code:SetPoint("TOP", actions, "TOP", 0, -100)
    frame.code:SetScript("OnTextChanged", function(box, user)
        if user and Credits.code then
            box:SetText(Credits.code)
            box:HighlightText()
        end
    end)
    frame.code:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
    frame.code:Hide()
    frame.feedback:SetWidth(self.width)

    if type(_G.UISpecialFrames) == "table" then table.insert(_G.UISpecialFrames, "HearthsideCredits") end
    -- As for the seal scene: Esc is the player's, a host going away only hides the parent.
    frame:SetScript("OnHide", function(self)
        if Credits.hiding or Credits.photo then return end
        Credits:Close(self:IsShown() and "HOST" or "ESCAPE")
    end)
    frame:RegisterEvent("SCREENSHOT_SUCCEEDED")
    frame:RegisterEvent("SCREENSHOT_FAILED")
    frame:SetScript("OnEvent", function(_, event) Credits:PhotoDone(event == "SCREENSHOT_SUCCEEDED") end)
    frame:SetScript("OnMouseDown", function() Credits:Skip() end)
    frame:SetScript("OnUpdate", function(_, elapsed) Credits:Animate(elapsed) end)
    self.frame = frame
    return frame
end

function Credits:Contract(result)
    self:Queue({ result = result })
end

function Credits:Seal(seal)
    if self:Wanted() then self:Queue({ seal = seal }) end
end

function Credits:Queue(entry)
    for _, queued in ipairs(self.queue) do
        if queued.result == entry.result and queued.seal == entry.seal then return end
    end
    self.queue[#self.queue + 1] = entry
    self.clearStage = true
    self:Pump()
end

function Credits:Pump()
    if self.current or #self.queue == 0 then return end
    if A.Bool(A.Call(_G.InCombatLockdown)) ~= false then return self:Retry() end
    -- The ending takes over a window left open, once; a window opened later is left alone.
    if self.clearStage then
        self.clearStage = false
        if A.Panel:IsShown() then A.Panel:Close("CREDITS") end
    end
    local entry = self.queue[1]
    local token, reason = MS.JourneyCardArbiter:Acquire("RESULT", function() Credits:Close("REPLACED") end)
    if not token then
        A:Log("CARD_REFUSED", { kind = "CREDITS", reason = reason })
        return self:Retry()
    end
    table.remove(self.queue, 1)
    self.token, self.current = token, entry
    self:Present(entry)
end

function Credits:Retry()
    if self.retry or not _G.C_Timer then return end
    self.retry = C_Timer.NewTicker(2, function()
        if Credits.current or #Credits.queue == 0 then Credits.retry:Cancel(); Credits.retry = nil; return end
        Credits:Pump()
    end)
end

function Credits:Present(entry)
    local frame = self:Create()
    local host, surface = Kit:Host()
    if frame:GetParent() ~= host then frame:SetParent(host) end
    frame:SetFrameStrata("DIALOG")
    frame:ClearAllPoints()
    frame:SetAllPoints(host)
    local L = MS.L
    local lines = entry.result and self:ForContract(entry.result) or self:ForSeal(entry.seal)
    frame.eyebrow:SetText(lines.eyebrow)
    frame.title:SetText(lines.title)
    frame.sub:SetText(lines.sub)
    frame.quote:SetText(lines.quote or "")
    frame.names:SetText(lines.names or "")
    for index, row in ipairs(frame.rows) do
        local rule = lines.rules and lines.rules[index]
        row:SetShown(rule ~= nil)
        if rule then
            row.title:SetText(rule.title)
            row.stamp:SetText(rule.stamp)
            Kit.Paint(row.stamp, rule.color)
        end
    end
    frame.primary:SetLabel(entry.result and L.CONTRACT_ANNOUNCE or L.SEAL_REPLY)
    frame.primary:SetEnabled(true)
    frame.primary.actionDisabled = false
    frame.sheet:SetShown(entry.result ~= nil)
    frame.poster:ClearAllPoints()
    frame.poster:SetPoint("LEFT", entry.result and frame.sheet or frame.primary, "RIGHT", 8, 0)
    frame.feedback:SetText(L.POSTER_PHOTO_HINT)
    Kit.Paint(frame.feedback, "textSecondary")
    self:ClearCode()
    self.elapsed = 0
    frame.actions:Hide()
    frame:Show()
    self:Animate(0)
    A:Log("CARD_SHOWN", { kind = "CREDITS", surface = surface })
end

-- One line after the other; the actions come last so nothing invisible can be clicked.
function Credits:Animate(elapsed)
    local frame = self.frame
    if not frame or not frame:IsShown() or not self.elapsed then return end
    self.elapsed = self.elapsed + (elapsed or 0)
    local t = self.elapsed
    for index, beat in ipairs(frame.beats) do
        beat:SetAlpha(math.max(0, math.min(1, (t - (index - 1) * self.beat) / self.fade)))
    end
    if t >= #frame.beats * self.beat then
        for _, beat in ipairs(frame.beats) do beat:SetAlpha(1) end
        frame.actions:Show()
        Kit.FadeIn(frame.actions)
        self.elapsed = nil
    end
end

-- A click anywhere: straight to the end, for whoever has seen it before.
function Credits:Skip()
    if self.elapsed then
        self.elapsed = #self.frame.beats * self.beat
        self:Animate(0)
    end
end

function Credits:Primary()
    local entry = self.current
    if not entry then return end
    local ok, reason
    if entry.result then
        ok, reason = A.Contracts:Announce("RESULT", entry.result)
    else
        ok, reason = A.Seals:Reply(entry.seal)
    end
    local L, frame = MS.L, self.frame
    frame.feedback:SetText(ok and (entry.result and L.CONTRACT_ANNOUNCE_READY or L.SEAL_REPLY_READY)
        or (L["ACTIVE_CHAT_" .. tostring(reason)] or L.ACTIVE_CHAT_FAILED))
    Kit.Paint(frame.feedback, ok and "success" or "warning")
    if ok then
        frame.primary:SetEnabled(false)
        frame.primary.actionDisabled = true
    end
end

-- The code the player carries to the Companion by hand: nothing is written anywhere.
function Credits:Poster()
    local entry = self.current
    if not entry then return end
    local ok, code = pcall(function()
        local Code = A.PosterCode
        return Code.Encode(entry.result and Code.ForContract(entry.result) or Code.ForSeal(entry.seal))
    end)
    local frame = self.frame
    if not ok then
        frame.feedback:SetText(MS.L.POSTER_FAILED)
        Kit.Paint(frame.feedback, "warning")
        return
    end
    self.code = code
    frame.feedback:SetText(MS.L.POSTER_COPY_HINT)
    Kit.Paint(frame.feedback, "textSecondary")
    frame.code:SetText(code)
    frame.code:Show()
    frame.code:SetFocus()
    frame.code:HighlightText()
end

-- Photo souvenir: Alt+Z for the time of one screenshot, kept in the game's Screenshots folder. The
-- Companion can then use it behind the poster. The interface always comes back: an answer from the
-- game, the guard timer or the Generique closing, whichever comes first.
function Credits:Photo()
    local frame = self.frame
    if not self.current or self.photo then return end
    if A.Bool(A.Call(_G.InCombatLockdown)) ~= false then
        frame.feedback:SetText(MS.L.POSTER_PHOTO_COMBAT)
        Kit.Paint(frame.feedback, "warning")
        return
    end
    local photo = {}
    self.photo = photo
    _G.SetUIVisibility(false)
    C_Timer.After(self.photoDelay, function()
        if Credits.photo == photo then _G.Screenshot() end
    end)
    C_Timer.After(self.photoGuard, function()
        if Credits.photo == photo then Credits:PhotoDone(false) end
    end)
end

function Credits:PhotoDone(taken)
    if not self.photo then return end
    self.photo = nil
    _G.SetUIVisibility(true)
    local frame = self.frame
    -- Esc while the interface was away: the Generique ends now that it can.
    if self.current and not frame:IsShown() then return self:Close("ESCAPE") end
    frame.feedback:SetText(taken and MS.L.POSTER_PHOTO_DONE or MS.L.POSTER_PHOTO_FAILED)
    Kit.Paint(frame.feedback, taken and "success" or "warning")
end

function Credits:ClearCode()
    self.code = nil
    local box = self.frame and self.frame.code
    if box then
        box:ClearFocus()
        box:SetText("")
        box:Hide()
    end
end

-- The plain sheet stays one click away: an honor rule is declared broken there.
function Credits:OpenSheet()
    self:Close("SHEET")
    A.Panel:Open("SHEET")
end

function Credits:Close(reason)
    self:PhotoDone(false)
    local entry = self.current
    -- Only a player who saw it closes it for good; a fight, a replacement or a reload bring it back.
    if entry and entry.result and (reason == "PLAYER" or reason == "ESCAPE") then entry.result.seen = true end
    if entry and (reason == "REPLACED" or reason == "HOST") then table.insert(self.queue, 1, entry) end
    self.current, self.elapsed = nil, nil
    self:ClearCode()
    if self.frame and self.frame:IsShown() then
        self.hiding = true
        self.frame:Hide()
        self.hiding = false
    end
    if self.token then
        local token = self.token
        self.token = nil
        MS.JourneyCardArbiter:Release(token)
    end
    if reason ~= "REPLACED" and reason ~= "SHEET" then self:Pump() end
end

function Credits:OnCombat(inCombat)
    if inCombat and self.current then
        local entry = self.current
        self:Close("COMBAT")
        table.insert(self.queue, 1, entry)
    elseif not inCombat then
        self:Pump()
    end
end

A:Register("Credits", Credits)

Kit.creditsToggle = { id = "activeCredits", label = MS.L.CREDITS_SETTING, hint = MS.L.CREDITS_SETTING_HINT,
    get = function() return Credits:Wanted() end,
    set = function(value)
        if A.Store and A.Store.root and not A.Store.readOnly then A.Store.root.noCredits = not value or nil end
    end }

local Settings = MS.JourneySettings
if Settings and Settings.AddExternalToggle then Settings:AddExternalToggle(Kit.creditsToggle) end
