local MS = _G.MS
MS.Active = MS.Active or {}
-- The one Journey window for the active experiences. It exists only while the player uses it
-- (or while a Contrat sheet is shown), never in combat: a fight hides it and the end of the fight
-- brings it back as it was.
local A = MS.Active
local Kit = A.Kit
local Panel = { width = 520, height = 500, views = {}, order = {} }
A.Panel = Panel

function Panel:RegisterView(name, view)
    self.views[name] = view
    self.order[#self.order + 1] = name
end

function Panel:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "HearthsideActivePanel", _G.UIParent)
    frame:SetSize(self.width, self.height)
    Kit.Zoom(frame)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:Hide()
    local style = MS.JourneyUIStyle
    self.reach = style and style.Elevate and style:Elevate(frame, 4, true) or 0
    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetAllPoints(frame)
    Kit.Fill(frame.border, "borderActive")
    frame.background = frame:CreateTexture(nil, "BORDER")
    frame.background:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    Kit.Fill(frame.background, "overlay")
    frame.title = Kit.Label(frame, "HEADING", "gold")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -18)
    frame.title:SetWidth(self.width - 120)
    frame.back = Kit.Button(frame, 92, 22, function() Panel:Show("HOME") end)
    frame.back:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -44, -14)
    frame.back:SetLabel(MS.L.ACTIVE_BACK)
    frame.close = CreateFrame("Button", nil, frame)
    frame.close:SetSize(24, 24)
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -12)
    frame.close.label = Kit.Label(frame.close, "HEADING", "gold", "CENTER")
    frame.close.label:SetAllPoints(frame.close)
    frame.close.label:SetText("×")
    frame.close:SetScript("OnClick", function() Panel:Close("PLAYER") end)
    frame.rule = Kit.Rule(frame, "gold")
    frame.rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -46)
    frame.rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -46)
    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -58)
    frame.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 16)
    frame.content:SetSize(self.width - 40, self.height - 74)
    -- Esc closes it like any game window.
    if type(_G.UISpecialFrames) == "table" then table.insert(_G.UISpecialFrames, "HearthsideActivePanel") end
    frame:SetScript("OnHide", function() Panel:OnHidden() end)
    frame:SetScript("OnUpdate", function(_, elapsed) Panel:OnUpdate(elapsed) end)
    self.frame = frame
    return frame
end

function Panel:Place()
    local host, kind = Kit:Host()
    local frame = self.frame
    if frame:GetParent() ~= host then frame:SetParent(host) end
    frame:SetFrameStrata("DIALOG")
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", host, "CENTER", 0, 0)
    self.surface = kind
end

function Panel:IsShown() return self.frame ~= nil and self.frame:IsShown() end

-- kind: PANEL (the player opened it) or RESULT (a Contrat sheet that appears by itself).
function Panel:Open(view, kind)
    if not A:Ready() then A:Say("ACTIVE_NOT_READY"); return false end
    kind = kind or "PANEL"
    -- Never shown during a fight, even when the window already holds its slot (hidden by the
    -- fight): it stays suspended and comes back on its own when the fight ends.
    if A.Bool(A.Call(_G.InCombatLockdown)) ~= false then
        A:Log("CARD_REFUSED", { kind = kind, reason = "COMBAT" })
        if kind == "PANEL" then A:Say("ACTIVE_COMBAT") end
        if self.suspended and view then self.current = view end
        return false, "COMBAT"
    end
    if not self.token or self.token.kind ~= kind then
        -- The window changes role (a sheet the player now browses): free our own slot first.
        local previous = self.token
        self.token = nil
        if previous then MS.JourneyCardArbiter:Release(previous) end
        local token, reason = MS.JourneyCardArbiter:Acquire(kind, function() Panel:Close("REPLACED") end)
        if not token then
            A:Log("CARD_REFUSED", { kind = kind, reason = reason })
            if kind == "PANEL" and reason == "COMBAT" then A:Say("ACTIVE_COMBAT") end
            if previous and self.frame then self.frame:Hide() end
            return false, reason
        end
        self.token = token
        A:Log("CARD_SHOWN", { kind = kind, surface = select(2, Kit:Host()) })
    end
    self:Create()
    self:Place()
    self.suspended = false
    self.frame:Show()
    self:Show(view or "HOME")
    return true
end

function Panel:Show(name)
    local view = self.views[name]
    if not view or not self.frame then return end
    for _, other in pairs(self.views) do if other.container then other.container:Hide() end end
    if not view.container then
        view.container = CreateFrame("Frame", nil, self.frame.content)
        view.container:SetAllPoints(self.frame.content)
        view.container:SetSize(self.frame.content:GetWidth(), self.frame.content:GetHeight())
        view:Build(view.container, self.width - 40)
    end
    self.current = name
    self.frame.title:SetText(view.Title and view:Title() or "")
    self.frame.back:SetShown(name ~= "HOME")
    view.container:Show()
    Kit.FadeIn(view.container, .15)
    if view.Refresh then view:Refresh() end
end

-- Something a view shows has changed (a seal, a rule): refresh if it is on screen.
function Panel:Changed(what)
    if not self:IsShown() or not self.current then return end
    local view = self.views[self.current]
    if view and view.Refresh and (not view.topic or view.topic == what or self.current == "HOME") then view:Refresh() end
end

-- Streamer mode changed: the open view redraws with or without names and codes.
function Panel:BroadcastChanged()
    if not self:IsShown() or not self.current then return end
    local view = self.views[self.current]
    if view and view.Refresh then pcall(view.Refresh, view) end
end

function Panel:OnUpdate(elapsed)
    self.clock = (self.clock or 0) + (elapsed or 0)
    if self.clock < 1 then return end
    self.clock = 0
    local view = self.current and self.views[self.current]
    if view and view.Tick then view:Tick() end
end

function Panel:Close(reason)
    self.closing = reason or "PLAYER"
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:OnHidden() end
end

function Panel:OnHidden()
    if self.combatHiding then return end
    local view = self.current and self.views[self.current]
    local reason = self.closing or "ESCAPE"
    if view and view.Closed then pcall(view.Closed, view, reason) end
    self.closing, self.suspended = nil, false
    if self.token then
        local token = self.token
        self.token = nil
        MS.JourneyCardArbiter:Release(token)
    end
    -- Whatever waited for the stage (a seal, a sheet) may come now; not while the arbiter is
    -- handing the slot to a more important card.
    if reason ~= "REPLACED" then
        if A.Reveal then A.Reveal:Pump() end
        if A.Sheet then A.Sheet:Pump() end
    end
end

function Panel:OnCombat(inCombat)
    if not self.frame then return end
    if inCombat and self.frame:IsShown() then
        self.combatHiding, self.suspended = true, true
        if _G.GetCurrentKeyBoardFocus and A.Call(_G.GetCurrentKeyBoardFocus) then
            local focus = A.Call(_G.GetCurrentKeyBoardFocus)
            if type(focus) == "table" and focus.ClearFocus then pcall(focus.ClearFocus, focus) end
        end
        self.frame:Hide()
        self.combatHiding = false
    elseif not inCombat and self.suspended and self.token then
        self.suspended = false
        self:Place()
        self.frame:Show()
        if self.current then self:Show(self.current) end
    end
end

A:Register("Panel", Panel)

-- HOME ----------------------------------------------------------------------------------------
local Home = { topic = "HOME" }

function Home:Title() return MS.L.ACTIVE_TITLE end

local function Entry(parent, width, onClick)
    local button = Kit.Button(parent, width, 92, onClick)
    button.label:Hide()
    button.title = Kit.Label(button, "ITEM_TITLE", "gold")
    button.title:SetPoint("TOPLEFT", button, "TOPLEFT", 14, -12)
    button.body = Kit.Label(button, "BODY", "textSecondary")
    button.body:SetPoint("TOPLEFT", button, "TOPLEFT", 14, -36)
    button.body:SetWidth(width - 28)
    button.status = Kit.Label(button, "SECONDARY", "textPrimary")
    button.status:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 14, 10)
    button.status:SetWidth(width - 120)
    -- The whole card opens its view; this says so.
    button.open = Kit.Label(button, "SECONDARY", "gold", "RIGHT")
    button.open:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -14, 10)
    button.open:SetText(MS.L.ACTIVE_HOME_OPEN)
    return button
end

function Home:Build(container, width)
    self.intro = Kit.Label(container, "BODY", "textSecondary")
    self.intro:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -4)
    self.intro:SetWidth(width)
    self.intro:SetText(MS.L.ACTIVE_HOME_INTRO)
    self.seal = Entry(container, width, function() Panel:Show("SEAL") end)
    self.seal:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -48)
    self.seal.title:SetText(MS.L.SEAL_NAME)
    self.seal.body:SetText(MS.L.SEAL_PROMISE)
    self.contract = Entry(container, width, function() Panel:Show("CONTRACT") end)
    self.contract:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -156)
    self.contract.title:SetText(MS.L.CONTRACT_NAME)
    self.contract.body:SetText(MS.L.CONTRACT_PROMISE)
    self.hint = Kit.Label(container, "SECONDARY", "muted")
    self.hint:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 4)
    self.hint:SetWidth(width)
    self.hint:SetText(MS.L.ACTIVE_HOME_HINT)
end

function Home:Refresh()
    local waiting = #A.Seals:Armed()
    self.seal.status:SetText(waiting > 0 and string.format(MS.L.SEAL_WAITING_COUNT, waiting) or MS.L.SEAL_NONE_WAITING)
    local contract, T = A.Contracts:Current(), A.ContractText
    if contract then
        self.contract.status:SetText(string.format(MS.L.CONTRACT_RUNNING_STATUS, T:ContractTitle(contract.goal),
            T:Duration(A.ContractEngine:Elapsed(contract, A.Now()))))
    else
        local last = A.Contracts:History()[1]
        self.contract.status:SetText(last and string.format(MS.L.CONTRACT_LAST_STATUS, (T:Verdict(last.verdict)), T:ContractTitle(last.context))
            or MS.L.CONTRACT_NONE)
    end
end

Panel:RegisterView("HOME", Home)

if MS.BroadcastMode then MS.BroadcastMode:Listen(function() Panel:BroadcastChanged() end) end
