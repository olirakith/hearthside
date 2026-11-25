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
    -- A view may say where back leads (a tale goes back to the shelf); otherwise home.
    frame.back = Kit.Button(frame, 92, 22, function()
        local view = Panel.current and Panel.views[Panel.current]
        Panel:Show(view and view.back or "HOME")
    end)
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
    -- The title stops 10 px before whatever sits to its right: back button (left edge at
    -- width-136) when shown, otherwise the previous width.
    local titleWidth = name ~= "HOME" and (self.width - 166) or (self.width - 120)
    self.frame.title:SetWidth(titleWidth)
    if type(self.frame.title.SetMaxLines) == "function" then self.frame.title:SetMaxLines(1) end
    self.frame.titleWidth = titleWidth
    self.frame.backShown = name ~= "HOME"
    view.container:Show()
    Kit.FadeIn(view.container, .15)
    if view.Refresh then view:Refresh() end
end

-- Something a view shows has changed (a seal, a rule): refresh if it is on screen.
function Panel:Changed(what)
    if MS.JourneyHomeButton then MS.JourneyHomeButton:Refresh() end
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
    if MS.JourneyHomeButton then MS.JourneyHomeButton:Refresh() end -- a sheet or seal just read
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

-- A home card: an illustrated tile, the experience's name, its promise, where it stands and the
-- one thing it opens. Drawn with L'Encre's theme (fonts, parchment colours) when it is loaded.
Home.art = {
    SEAL = { { .17, .29, .37, 1 }, { .10, .15, .21, 1 }, "Interface\\Icons\\INV_Misc_Spyglass_02" },
    CONTRACT = { { .31, .19, .17, 1 }, { .16, .11, .11, 1 }, "Interface\\Icons\\INV_Scroll_05" },
    INK = { { .27, .23, .15, 1 }, { .13, .11, .08, 1 }, "Interface\\Icons\\INV_Misc_Book_09" },
}

local function Entry(parent, width, onClick, kind)
    local T = MS.Ink and MS.Ink.Theme
    if not T then
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
        button.open = Kit.Label(button, "SECONDARY", "gold", "RIGHT")
        button.open:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -14, 10)
        button.open:SetText(MS.L.ACTIVE_HOME_OPEN)
        return button
    end
    local art, height = Home.art[kind], 112
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button.edge = T.Fill(button, "lineSoft", "BACKGROUND")
    button.back = button:CreateTexture(nil, "BORDER")
    button.back:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.back:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    T.Color(button.back, "raised")
    -- The tile: a dusk gradient behind the experience's emblem.
    button.tile = button:CreateTexture(nil, "ARTWORK")
    button.tile:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.tile:SetSize(height - 2, height - 2)
    button.tile:SetColorTexture(1, 1, 1, 1)
    local top, bottom = art[1], art[2]
    local shaded = type(_G.CreateColor) == "function" and pcall(button.tile.SetGradient, button.tile, "VERTICAL",
        _G.CreateColor(bottom[1], bottom[2], bottom[3], 1), _G.CreateColor(top[1], top[2], top[3], 1))
    if not shaded then T.Color(button.tile, top) end
    button.emblem = T.Icon(button, 54, art[3])
    button.emblem:SetPoint("CENTER", button.tile, "CENTER")
    button.frameEdge = button:CreateTexture(nil, "OVERLAY")
    button.frameEdge:SetPoint("TOPLEFT", button.tile, "TOPRIGHT")
    button.frameEdge:SetPoint("BOTTOMLEFT", button.tile, "BOTTOMRIGHT")
    button.frameEdge:SetWidth(1)
    T.Color(button.frameEdge, "lineSoft")
    local x, inner = height + 14, width - height - 28
    button.title = T.Text(button, "TITLE", 15, "goldBright")
    button.title:SetPoint("TOPLEFT", button, "TOPLEFT", x, -12)
    button.title:SetWidth(inner)
    button.body = T.Text(button, "UI", 14, "textSoft")
    button.body:SetPoint("TOPLEFT", button, "TOPLEFT", x, -34)
    button.body:SetWidth(inner)
    if type(button.body.SetMaxLines) == "function" then button.body:SetMaxLines(2) end
    button.status = T.Text(button, "UI_BOLD", 13, "text")
    button.status:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", x, 12)
    button.status:SetWidth(inner - 90)
    if type(button.status.SetWordWrap) == "function" then button.status:SetWordWrap(false) end
    button.pips = T.Pips(button)
    button.pips:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", x, 32)
    button.pips:Hide()
    button.open = T.Text(button, "UI_BOLD", 13, "gold", "RIGHT")
    button.open:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -14, 12)
    button.open:SetText(MS.L.ACTIVE_HOME_OPEN)
    button.hovered, button.featured = false, false
    local function Paint(self)
        T.Color(self.back, self.hovered and "selected" or "raised")
        T.Color(self.edge, (self.hovered or self.featured) and "gold" or "lineSoft")
        T.TextColor(self.open, self.hovered and "goldBright" or "gold")
    end
    button:SetScript("OnEnter", function(self) self.hovered = true; Paint(self) end)
    button:SetScript("OnLeave", function(self) self.hovered = false; Paint(self) end)
    button:SetScript("OnHide", function(self) self.hovered = false; Paint(self) end)
    button:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
    -- Something is under way: a gold edge says this is where the player left off.
    function button:SetFeatured(value) self.featured = value == true; Paint(self) end
    Paint(button)
    return button
end

function Home:Build(container, width)
    local themed = MS.Ink and MS.Ink.Theme
    local step = themed and 122 or 108
    self.intro = Kit.Label(container, "BODY", "textSecondary")
    self.intro:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -4)
    self.intro:SetWidth(width)
    self.intro:SetText(MS.L.ACTIVE_HOME_INTRO)
    self.seal = Entry(container, width, function() Panel:Show("SEAL") end, "SEAL")
    self.seal:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -40)
    self.seal.title:SetText(MS.L.SEAL_NAME)
    self.seal.body:SetText(MS.L.SEAL_PROMISE)
    self.contract = Entry(container, width, function() Panel:Show("CONTRACT") end, "CONTRACT")
    self.contract:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -40 - step)
    self.contract.title:SetText(MS.L.CONTRACT_NAME)
    self.contract.body:SetText(MS.L.CONTRACT_PROMISE)
    if MS.Ink and MS.Ink.Tab then
        self.ink = Entry(container, width, function()
            if MS.Ink:OpenTab("SHELF") then Panel:Close("PLAYER") else A:Say("INK_NO_JOURNEY") end
        end, "INK")
        self.ink:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -40 - step * 2)
        self.ink.title:SetText(MS.L.INK_NAME)
        self.ink.body:SetText(MS.L.INK_PROMISE)
    end
    self.hint = Kit.Label(container, "SECONDARY", "muted")
    self.hint:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    self.hint:SetWidth(width)
    self.hint:SetText(MS.L.ACTIVE_HOME_HINT)
end

function Home:Refresh()
    local waiting = #A.Seals:Armed()
    self.seal.status:SetText(waiting > 0 and string.format(MS.L.SEAL_WAITING_COUNT, waiting) or MS.L.SEAL_NONE_WAITING)
    if self.seal.SetFeatured then self.seal:SetFeatured(waiting > 0) end
    local contract, T = A.Contracts:Current(), A.ContractText
    if contract then
        self.contract.status:SetText(string.format(MS.L.CONTRACT_RUNNING_STATUS, T:ContractTitle(contract.goal),
            T:Duration(A.ContractEngine:Elapsed(contract, A.Now()))))
    else
        local last = A.Contracts:History()[1]
        self.contract.status:SetText(last and string.format(MS.L.CONTRACT_LAST_STATUS, (T:Verdict(last.verdict)), T:ContractTitle(last.context))
            or MS.L.CONTRACT_NONE)
    end
    if self.contract.SetFeatured then self.contract:SetFeatured(contract ~= nil) end
    if self.ink then
        local following = MS.Ink:Following()
        self.ink.status:SetText(#following > 0 and string.format(MS.L.INK_FOLLOWING_COUNT, #following) or MS.L.INK_NONE_FOLLOWING)
        if self.ink.SetFeatured then
            self.ink:SetFeatured(#following > 0)
            -- The first tale followed: its pages as short bars above the status.
            local first = following[1]
            self.ink.pips:SetShown(first ~= nil)
            if first then
                self.ink.pips:Set(MS.Ink.Progress.Count(first.tale, first.progress), #first.tale.pages, true, 150)
            end
        end
    end
end

Panel:RegisterView("HOME", Home)

if MS.BroadcastMode then MS.BroadcastMode:Listen(function() Panel:BroadcastChanged() end) end
