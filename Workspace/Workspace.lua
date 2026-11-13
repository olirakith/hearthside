local MS = _G.MS

MS.Workspace = { debugEnabled = false }

local function HasMethods(object, methods)
    if not object then return false end
    for _, method in ipairs(methods) do
        if type(object[method]) ~= "function" then return false end
    end
    return true
end

-- Window: HIGH strata, movable, kept on screen. Otherwise LOW and fixed, as the engine expects.
local function ApplyWindowMode(frame, window)
    frame:SetFrameStrata(window and "HIGH" or "LOW")
    if type(frame.SetMovable) == "function" then frame:SetMovable(window) end
    if type(frame.SetClampedToScreen) == "function" then frame:SetClampedToScreen(window) end
end

function MS.Workspace:Create()
    if self.frame then return true end
    if type(CreateFrame) ~= "function" or not UIParent then return nil, "ERROR_WORKSPACE_CREATE" end
    local created, frame = pcall(CreateFrame, "Frame", nil, UIParent)
    if not created or not HasMethods(frame, { "SetFrameStrata", "Hide" }) then return nil, "ERROR_WORKSPACE_CREATE" end
    frame:SetFrameStrata("LOW")
    frame:Hide()
    self.frame = frame
    local overlayCreated, errorMessage = MS.WorkspaceDebugOverlay:Create(frame)
    if not overlayCreated then
        self.frame = nil
        return nil, errorMessage
    end
    return true
end

function MS.Workspace:CalculateLayout(workspaceRect)
    return MS.WorkspaceLayout:Calculate(workspaceRect)
end

function MS.Workspace:Show(engineLayout)
    local created, errorMessage = self:Create()
    if not created then return nil, errorMessage end
    if type(engineLayout) ~= "table" or type(engineLayout.workspace) ~= "table"
        or not HasMethods(self.frame, { "ClearAllPoints", "SetPoint", "SetSize", "Show" }) then
        return nil, "ERROR_WORKSPACE_SHOW"
    end
    local regions, layoutError = self:CalculateLayout(engineLayout.workspace)
    if not regions then return nil, layoutError end
    local rect = engineLayout.workspace
    -- Window mode (no Companion): a plain movable frame on UIParent, never on the span roots.
    local window = engineLayout.window == true
    -- VIEWPORT: WORKSPACE lives beside the GAME-sized UIParent, anchored to SPAN_ROOT.
    local root
    if not window and MS.UIParentMode and MS.UIParentMode:IsViewport() then
        local rootError
        root, rootError = MS.ViewportRoots:PlaceWorkspace(rect)
        if not root then return nil, rootError end
    end
    local shown = pcall(function()
        self.frame:ClearAllPoints()
        if root then
            self.frame:SetParent(root)
            self.frame:SetFrameStrata("LOW")
            self.frame:SetAllPoints(root)
            self.rootParented = true
        else
            if self.rootParented then
                self.frame:SetParent(UIParent)
                self.frame:SetFrameStrata("LOW")
                self.rootParented = nil
            end
            self.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rect.x, rect.y)
            self.frame:SetSize(rect.width, rect.height)
        end
        ApplyWindowMode(self.frame, window)
        self.windowMode = window or nil
        self.layout, self.uiRect, self.physicalRect = regions, rect, engineLayout.physicalWorkspace
        MS.WorkspaceDebugOverlay:Update(regions)
        MS.WorkspaceDebugOverlay:SetShown(self.debugEnabled)
        self.frame:Show()
    end)
    if not shown then return nil, "ERROR_WORKSPACE_SHOW" end
    return true
end

function MS.Workspace:GetRegion(name)
    if type(name) ~= "string" then return nil end
    local region = self.layout and self.layout[string.lower(name)]
    if not region then return nil end
    return { x = region.x, y = region.y, width = region.width, height = region.height }
end

function MS.Workspace:GetLayoutInfo()
    return self.layout, self.uiRect, self.physicalRect
end

function MS.Workspace:ToggleDebug()
    self.debugEnabled = not self.debugEnabled
    if self.frame then MS.WorkspaceDebugOverlay:SetShown(self.debugEnabled) end
    return self.debugEnabled
end

function MS.Workspace:Hide()
    if self.frame and type(self.frame.Hide) == "function" then
        local hidden = pcall(self.frame.Hide, self.frame)
        if not hidden then return nil, "ERROR_WORKSPACE_HIDE" end
    end
    if self.frame and self.windowMode then
        pcall(ApplyWindowMode, self.frame, false)
        self.windowMode = nil
    end
    if MS.ViewportRoots then MS.ViewportRoots:HideWorkspace() end
    return true
end
