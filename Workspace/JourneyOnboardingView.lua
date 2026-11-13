local MS = _G.MS
MS.JourneyOnboardingView = {}
local V = MS.JourneyOnboardingView
local function Signal(code)
    if MS.DiagnosticSnapshots then MS.DiagnosticSnapshots:Signal("onboarding", code) end
end
local function Label(parent, token, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    MS.JourneyUIStyle:Apply(label, token or "BODY")
    MS.JourneyUIStyle:Text(label, color or "textPrimary")
    label:SetJustifyH("LEFT"); label:SetJustifyV("TOP")
    return label
end
local function Button(parent, text, action)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(text); button:SetScript("OnClick", action)
    return button
end
function V:Close()
    MS.JourneyOnboarding.sessionClosed = true
    if self.frame then self.frame:Hide() end
end
function V:Create()
    if self.frame then return end
    local panel = CreateFrame("Frame", "HearthsideOnboarding", UIParent)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "HearthsideOnboarding") end
    self.frame = panel; panel:Hide(); panel:SetFrameStrata("FULLSCREEN_DIALOG"); panel:SetFrameLevel(200); panel:EnableMouse(true)
    panel:SetScript("OnHide", function()
        MS.JourneyOnboarding.sessionClosed = true
        Signal("VIEW_HIDDEN")
    end)
    local background = panel:CreateTexture(nil, "BACKGROUND"); background:SetAllPoints(panel)
    MS.JourneyUIStyle:Color(background, "backgroundDeep")
    self.scroll = CreateFrame("ScrollFrame", nil, panel)
    self.content = CreateFrame("Frame", nil, self.scroll); self.content:SetSize(1, 1)
    self.scroll:SetScrollChild(self.content); self.scroll:EnableMouseWheel(true)
    self.scroll:SetScript("OnMouseWheel", function(scroll, delta)
        local maximum = math.max(0, V.content:GetHeight() - scroll:GetHeight())
        scroll:SetVerticalScroll(math.max(0, math.min(maximum, scroll:GetVerticalScroll() - delta * 40)))
    end)
    self.title = Label(self.content, "TITLE", "gold")
    self.stage = Label(self.content, "SECONDARY", "textSecondary")
    self.body = Label(self.content)
    self.display = Label(self.content, "SECONDARY")
    self.hint = Label(self.content, "SECONDARY", "warning")
    self.primary = Button(self.content, "", function() V:Primary() end)
    self.reload = Button(self.content, MS.L.ONBOARD_RELOAD, function() MS.JourneyOnboarding:ReloadInterface() end)
    self.window = Button(self.content, MS.L.ONBOARD_WINDOW, function()
        V:Close()
        MS.JourneyWindow:Open()
    end)
    self.diagnostic = Button(self.content, MS.L.ONBOARD_DIAGNOSTIC, function() MS.JourneyOnboarding:OpenDiagnostic() end)
    self.close = Button(self.content, MS.L.ONBOARD_LATER, function() V:Close() end)
end
function V:Primary()
    local O = MS.JourneyOnboarding
    local state = O:Refresh()
    if state == "NEVER_STARTED" then O:Begin()
    elseif state == "DISPLAY_REQUIRED" or state == "LAYOUT_MIGRATION" then O:RetryDisplay()
    elseif O:Finish() then self:Close() end
end
local STAGES = { NEVER_STARTED = "WELCOME", DISPLAY_REQUIRED = "DISPLAY", LAYOUT_MIGRATION = "LAYOUT", READY = "READY" }
function V:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local O, L = MS.JourneyOnboarding, MS.L
    local state, e = O.saved.state, O.evidence
    self.title:SetText(L.ONBOARD_TITLE)
    local stage = STAGES[state] or "WELCOME"
    self.renderedState, self.renderedStage = state, stage
    self.stage:SetText(L[(e.existingUser and "ONBOARD_EXISTING_STAGE_" or "ONBOARD_STAGE_") .. stage])
    local body = L["ONBOARD_BODY_" .. state]
    if state == "LAYOUT_MIGRATION" then body = string.format(body, e.layoutName or "Azeroth Journey") end
    self.body:SetText(body)
    local function Status(ready) return ready and L.ONBOARD_STATUS_READY or L.ONBOARD_STATUS_WAITING end
    self.display:SetText(string.format(L.ONBOARD_DISPLAY_STATUS, Status(e.layoutReady), Status(e.gameReady), Status(e.workspaceReady)))
    local hint = e.combat and L.ONBOARD_COMBAT or e.editing and L.ONBOARD_WAIT
        or state == "DISPLAY_REQUIRED" and (not e.layoutReady and L.ONBOARD_CONFIG_MISSING
            or not e.spanMatches and L.ONBOARD_SPAN_MISSING or L.ONBOARD_DISPLAY_BLOCKED) or ""
    self.hint:SetText(hint)
    local primary = state == "NEVER_STARTED" and L.ONBOARD_BEGIN or state == "READY" and L.ONBOARD_PLAY or L.ONBOARD_RECHECK
    self.primary:SetText(primary)
    self.primary:SetEnabled(not e.combat)
    self.reload:SetShown(state == "DISPLAY_REQUIRED")
    self.reload:SetEnabled(e.canReload == true)
    self.window:SetShown(MS.JourneyWindow ~= nil and (state == "NEVER_STARTED" or state == "DISPLAY_REQUIRED"))
    self.window:SetEnabled(MS.JourneyWindow ~= nil and MS.JourneyWindow:Available() == true)
    self.close:SetText(stage == "READY" and L.ONBOARD_CLOSE or L.ONBOARD_LATER)
    self:Layout()
end
function V:Layout()
    if not self.frame then return end
    local e = MS.JourneyOnboarding.evidence or {}
    local parent = e.displayReady and MS.Workspace.frame or UIParent
    local width = math.max(1, math.min(580, parent:GetWidth() - 32))
    local height = math.max(1, math.min(650, parent:GetHeight() - 32))
    self.frame:ClearAllPoints(); self.frame:SetPoint("CENTER", parent, "CENTER"); self.frame:SetSize(width, height)
    self.scroll:ClearAllPoints(); self.scroll:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -16)
    self.scroll:SetSize(math.max(1, width - 32), math.max(1, height - 32))
    local inner = math.max(1, width - 48)
    self.content:SetWidth(inner)
    local y = 0
    local function Text(label)
        label:ClearAllPoints(); label:SetPoint("TOPLEFT", V.content, "TOPLEFT", 8, -y); label:SetWidth(math.max(1, inner - 16))
        y = y + math.max(18, label:GetStringHeight()) + 14
    end
    local function Action(widget, h)
        if not widget:IsShown() then return end
        widget:ClearAllPoints(); widget:SetPoint("TOPLEFT", V.content, "TOPLEFT", 8, -y); widget:SetSize(math.max(1, inner - 16), h)
        y = y + h + 10
    end
    Text(self.title); Text(self.stage); Text(self.body); Text(self.display)
    if self.hint:GetText() ~= "" then Text(self.hint) end
    Action(self.primary, 36); Action(self.reload, 32); Action(self.window, 32); Action(self.diagnostic, 32); Action(self.close, 28)
    self.content:SetHeight(y)
    local maximum = math.max(0, y - self.scroll:GetHeight())
    self.scroll:SetVerticalScroll(math.min(maximum, self.scroll:GetVerticalScroll()))
end
function V:Open()
    self:Create(); self.frame:Show(); self.scroll:SetVerticalScroll(0); self:Refresh()
    Signal("VIEW_SHOWN")
end

-- Called only by the player's native Settings entry buttons.
function V:LeaveNativeSettings()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
    if type(HideUIPanel) ~= "function" then return end
    for _, name in ipairs({ "SettingsPanel", "InterfaceOptionsFrame" }) do
        local panel = _G[name]
        if panel and panel:IsShown() then pcall(HideUIPanel, panel) end
    end
end

-- An entry outside WORKSPACE is necessary when display preparation has failed.
function V:RegisterSettings()
    if self.categoryRegistered then return end
    if not self.settingsCanvas then
        local canvas = CreateFrame("Frame", nil, UIParent); canvas:Hide(); canvas.name = MS.L.ONBOARD_TITLE
        local title = Label(canvas, "TITLE", "gold"); title:SetPoint("TOPLEFT", canvas, "TOPLEFT", 24, -24)
        title:SetText(MS.L.ONBOARD_TITLE)
        local body = Label(canvas); body:SetPoint("TOPLEFT", canvas, "TOPLEFT", 24, -65); body:SetWidth(500)
        body:SetText(MS.L.ONBOARD_SETTINGS_HINT)
        local setup = Button(canvas, MS.L.ONBOARD_OPEN, function() V:LeaveNativeSettings(); MS.JourneyOnboarding:Open() end)
        self.settingsSetup = setup
        setup:SetPoint("TOPLEFT", canvas, "TOPLEFT", 24, -150); setup:SetSize(320, 36)
        local diagnostic = Button(canvas, MS.L.ONBOARD_DIAGNOSTIC, function() V:LeaveNativeSettings(); MS.JourneyOnboarding:OpenDiagnostic() end)
        self.settingsDiagnostic = diagnostic
        diagnostic:SetPoint("TOPLEFT", canvas, "TOPLEFT", 24, -200); diagnostic:SetSize(320, 36)
        self.settingsCanvas = canvas
    end
    local settings = _G.Settings
    if settings and type(settings.RegisterCanvasLayoutCategory) == "function" and type(settings.RegisterAddOnCategory) == "function" then
        if not self.category then
            local ok, category = pcall(settings.RegisterCanvasLayoutCategory, self.settingsCanvas, MS.L.ONBOARD_TITLE)
            if ok then self.category = category end
        end
        if self.category then self.categoryRegistered = pcall(settings.RegisterAddOnCategory, self.category) end
    elseif type(InterfaceOptions_AddCategory) == "function" then
        self.categoryRegistered = pcall(InterfaceOptions_AddCategory, self.settingsCanvas)
    end
end
if MS.JourneySettings then MS.JourneySettings:Listen(function(key)
    if key == "textScale" then V:Refresh() end
end) end
