local MS = _G.MS

MS.Diagnostics = {}

local WORLD_FRAME_TOLERANCE_PIXELS = 1
local reportWindow

function MS.Diagnostics:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff" .. MS.L.PRODUCT_SHORT_NAME .. ":|r " .. (message or (MS.L and MS.L.ERROR_CONFIG) or ""))
end

local function GetReportWindow()
    if reportWindow then return reportWindow end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetSize(math.max(240, math.min(700, UIParent:GetWidth() - 40)),
        math.max(180, math.min(500, UIParent:GetHeight() - 40)))
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:EnableMouse(true)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0.04, 0.04, 0.04, 0.96)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -12)
    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(70, 24)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -10)
    close:SetText(MS.L.REPORT_CLOSE)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame:SetScript("OnHide", function()
        if frame.editBox then frame.editBox:ClearFocus(); frame.editBox:SetText("") end
    end)
    local instruction = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instruction:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -38)
    instruction:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -38)
    instruction:SetJustifyH("LEFT")
    instruction:Hide()
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -42)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 12)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject(ChatFontNormal)
    edit:SetPoint("TOPLEFT", scroll, "TOPLEFT")
    edit:SetWidth(math.max(1, scroll:GetWidth() - 8))
    edit:SetHeight(math.max(1, scroll:GetHeight()))
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() frame:Hide() end)
    edit:SetScript("OnKeyDown", function(self, key)
        if key == "A" and type(IsControlKeyDown) == "function" and IsControlKeyDown() then
            self:HighlightText(0, string.len(self:GetText() or ""))
        end
    end)
    edit:SetScript("OnTextChanged", function(self)
        local ok, height = pcall(self.GetTextHeight, self)
        self:SetHeight(math.max(scroll:GetHeight(), ok and height or 0, 1) + 20)
    end)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnSizeChanged", function(self)
        edit:SetWidth(math.max(1, self:GetWidth() - 8))
    end)
    frame.title, frame.editBox, frame.scroll, frame.instruction = title, edit, scroll, instruction
    frame:Hide()
    reportWindow = frame
    return frame
end

function MS.Diagnostics:IsCopyableReportShown(kind)
    return reportWindow and reportWindow:IsShown()
        and (not kind or reportWindow.reportKind == kind) or false
end

function MS.Diagnostics:HideCopyableReport(kind)
    if reportWindow and (not kind or reportWindow.reportKind == kind) then
        reportWindow:Hide()
        reportWindow.editBox:SetText("")
    end
end

function MS.Diagnostics:RefreshCopyableReportPlacement()
    if not reportWindow then return end
    local gameUI = MS.GameUI
    local active = MS.Runtime and MS.Runtime.enabled and gameUI and gameUI.frame
        and gameUI:GetRegion()
    local anchor = active and gameUI.frame or UIParent
    local width = active and active.width or UIParent:GetWidth()
    local height = active and active.height or UIParent:GetHeight()
    reportWindow:SetSize(math.max(1, math.min(700, width - 40, width * 0.88)),
        math.max(1, math.min(500, height - 40, height * 0.88)))
    reportWindow:ClearAllPoints()
    reportWindow:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    reportWindow.editBox:SetWidth(math.max(1, reportWindow.scroll:GetWidth() - 8))
end

-- concealed: the body stays in the box (Ctrl+A, Ctrl+C) but is drawn clear (streamer mode).
function MS.Diagnostics:ShowCopyableReport(title, body, kind, instruction, concealed)
    local frame = GetReportWindow()
    if MS.BroadcastMode then MS.BroadcastMode:Conceal(frame.editBox, concealed == true) end
    self:RefreshCopyableReportPlacement()
    frame.reportKind = kind
    frame.title:SetText(title)
    frame.instruction:SetText(instruction or "")
    frame.instruction:SetShown(instruction ~= nil)
    frame.scroll:ClearAllPoints()
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, instruction and -70 or -42)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 12)
    frame:Show()
    frame.editBox:SetWidth(math.max(1, frame.scroll:GetWidth() - 8))
    frame.editBox:SetText(body)
    frame.scroll:SetVerticalScroll(0)
    frame.editBox:SetFocus()
    if instruction then frame.editBox:HighlightText(0, string.len(body)) end
end

function MS.Diagnostics:Show()
    self:Print(MS.L.DIAG_HEADER)
    if not MS.Config or type(MS.Config.GetLayout) ~= "function" or not MS.Transform or not MS.Rect then
        self:Print(string.format(MS.L.INVALID_LAYOUT, MS.L.ERROR_CONFIG))
        return
    end

    local layout, source, layoutError = MS.Config:GetLayout()
    local metrics = MS.Transform:GetMetrics()
    self:Print(string.format(MS.L.DIAG_LAYOUT_SOURCE, source or MS.L.DIAG_UNAVAILABLE))
    local generated = MS.GeneratedLayout
    if source == "COMPANION_GENERATED" then
        local schema = type(generated) == "table" and generated.schemaVersion or nil
        local span = type(generated) == "table" and generated.span or nil
        local expected = type(span) == "table" and type(span.width) == "number"
            and type(span.height) == "number" and string.format("%s x %s", tostring(span.width), tostring(span.height))
            or MS.L.DIAG_UNAVAILABLE
        self:Print(string.format(MS.L.DIAG_GENERATED_SCHEMA, tostring(schema or MS.L.DIAG_UNAVAILABLE)))
        self:Print(string.format(MS.L.DIAG_EXPECTED_SPAN, expected))
        local matches = layout and metrics
            and metrics.reportedPhysicalWidth == span.width
            and metrics.reportedPhysicalHeight == span.height
        self:Print(string.format(MS.L.DIAG_LAYOUT_MATCH, matches and MS.L.DIAG_YES or MS.L.DIAG_NO))
    else
        self:Print(string.format(MS.L.DIAG_EXPECTED_SPAN, MS.L.DIAG_UNAVAILABLE))
        self:Print(string.format(MS.L.DIAG_LAYOUT_MATCH, MS.L.DIAG_NOT_APPLICABLE))
    end
    if metrics and metrics.reportedPhysicalWidth and metrics.reportedPhysicalHeight then
        self:Print(string.format(MS.L.DIAG_ACTUAL_SPAN,
            metrics.reportedPhysicalWidth, metrics.reportedPhysicalHeight))
    else
        self:Print(MS.L.DIAG_ACTUAL_SPAN_UNAVAILABLE)
    end
    if not layout then
        self:Print(string.format(MS.L.INVALID_LAYOUT, MS.L[layoutError] or MS.L.ERROR_CONFIG))
        return
    end
    if not metrics then
        self:Print(string.format(MS.L.INVALID_LAYOUT, MS.L.ERROR_METRICS))
        return
    end
    if metrics.reportedPhysicalWidth and metrics.reportedPhysicalHeight then
        self:Print(string.format(MS.L.DIAG_GET_PHYSICAL, metrics.reportedPhysicalWidth, metrics.reportedPhysicalHeight))
    else
        self:Print(MS.L.DIAG_GET_PHYSICAL_UNAVAILABLE)
    end
    self:Print(string.format(MS.L.DIAG_UIPARENT, metrics.uiWidth, metrics.uiHeight))
    self:Print(string.format(MS.L.DIAG_EFFECTIVE_SCALE, metrics.effectiveScale))
    self:Print(string.format(MS.L.DIAG_SCALE, metrics.pixelsPerUiX, metrics.pixelsPerUiY))
    self:Print(string.format(MS.L.DIAG_GAME_PHYSICAL, MS.Rect:ToString(layout.game)))
    self:ShowWorldFrame(MS.Rect:IsValid(layout.game) and layout.game or nil, metrics)
    self:ShowGameUI(layout, metrics)
    self:ShowWorkspace(layout, metrics)
end

function MS.Diagnostics:ShowGameUI(configLayout, metrics)
    local region = MS.GameUI and MS.GameUI:GetRegion()
    if not region and MS.Rect:IsValid(configLayout.game) then
        region = MS.Transform:RectToUI(configLayout.game, metrics)
    end
    if region then
        self:Print(string.format(MS.L.DIAG_GAMEUI_REGION, MS.Rect:ToString(region)))
    else
        self:Print(MS.L.DIAG_GAMEUI_UNAVAILABLE)
    end
end

function MS.Diagnostics:ShowWorkspace(configLayout, metrics)
    local workspaceRect = configLayout.workspace
    if not MS.Rect:IsValid(workspaceRect) then return end
    local uiRect = MS.Transform:RectToUI(workspaceRect, metrics)
    local workspaceLayout = MS.Workspace and MS.Workspace:GetLayoutInfo()
    if not workspaceLayout then workspaceLayout = MS.WorkspaceLayout:Calculate(uiRect) end
    if not workspaceLayout then
        self:Print(MS.L.DIAG_WORKSPACE_UNAVAILABLE)
        return
    end
    self:Print(string.format(MS.L.DIAG_WORKSPACE_PHYSICAL, MS.Rect:ToString(workspaceRect)))
    self:Print(string.format(MS.L.DIAG_WORKSPACE_UI, MS.Rect:ToString(uiRect)))
    self:Print(string.format(MS.L.DIAG_WORKSPACE_CLASS, workspaceLayout.aspectRatio, workspaceLayout.class))
    for _, name in ipairs({ "header", "main", "side", "bottom" }) do
        self:Print(string.format(MS.L.DIAG_WORKSPACE_REGION,
            MS.L["REGION_" .. string.upper(name)], MS.Rect:ToString(workspaceLayout[name])))
    end
end

function MS.Diagnostics:ShowWorldFrame(expectedPhysicalRect, metrics)
    local left, bottom, rectWidth, rectHeight = WorldFrame:GetRect()
    local worldScale = WorldFrame:GetScale()
    local worldEffectiveScale = WorldFrame:GetEffectiveScale()
    self:Print(string.format(MS.L.DIAG_WORLDFRAME_SCALE, worldScale, worldEffectiveScale))

    if not left or not bottom or not rectWidth or not rectHeight then
        self:Print(MS.L.DIAG_WORLDFRAME_RECT_UNAVAILABLE)
        return
    end

    local actualFrameRect = { x = left, y = bottom, width = rectWidth, height = rectHeight }
    local actualUIRect = MS.Transform:FrameRectToUI(actualFrameRect, WorldFrame, UIParent)
    if not actualUIRect then
        self:Print(MS.L.DIAG_WORLDFRAME_PHYSICAL_UNAVAILABLE)
        return
    end
    local actualPhysicalRect = MS.Transform:UIRectToPhysical(actualUIRect, metrics)

    if not expectedPhysicalRect then
        self:Print(MS.L.DIAG_WORLDFRAME_EXPECTED_UNAVAILABLE)
        return
    end

    self:Print(string.format(MS.L.DIAG_WORLDFRAME_EXPECTED, MS.Rect:ToString(expectedPhysicalRect)))
    self:Print(string.format(MS.L.DIAG_WORLDFRAME_ACTUAL, MS.Rect:ToString(actualPhysicalRect)))
    local matches = math.abs(actualPhysicalRect.x - expectedPhysicalRect.x) <= WORLD_FRAME_TOLERANCE_PIXELS
        and math.abs(actualPhysicalRect.y - expectedPhysicalRect.y) <= WORLD_FRAME_TOLERANCE_PIXELS
        and math.abs(actualPhysicalRect.width - expectedPhysicalRect.width) <= WORLD_FRAME_TOLERANCE_PIXELS
        and math.abs(actualPhysicalRect.height - expectedPhysicalRect.height) <= WORLD_FRAME_TOLERANCE_PIXELS
    self:Print(string.format(MS.L.DIAG_WORLDFRAME_MATCH,
        matches and MS.L.DIAG_YES or MS.L.DIAG_NO))
end
