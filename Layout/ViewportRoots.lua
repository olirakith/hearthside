local MS = _G.MS

-- UIParent = GAME viewport roots (VIEWPORT mode).
-- SPAN_ROOT: parentless frame anchored to the screen. It is the only geometry
-- reference for the full physical WoW window once UIParent no longer spans it.
-- WORKSPACE_ROOT: parented to UIParent for lifecycle (scale, Alt+Z, movies,
-- fullscreen panels) but anchored to SPAN_ROOT, never to UIParent's edges.
MS.ViewportRoots = {}
local Roots = MS.ViewportRoots

local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function Read(frame, method)
    if not frame or type(frame[method]) ~= "function" then return end
    local ok, a, b, c, d = pcall(frame[method], frame)
    if ok then return a, b, c, d end
end

function Roots:EnsureSpanRoot()
    if self.span then return self.span end
    if type(CreateFrame) ~= "function" then return nil end
    -- Same parentless screen anchoring as the runtime-validated PixelHandshake.
    local span = CreateFrame("Frame", "HearthsideSpanRoot", nil)
    span:SetFrameStrata("BACKGROUND")
    span:SetPoint("TOPLEFT")
    span:SetPoint("BOTTOMRIGHT")
    if type(span.EnableMouse) == "function" then span:EnableMouse(false) end
    -- Shown but empty: a resolved rect, nothing drawn, no mouse capture.
    span:Show()
    self.span = span
    return span
end

-- Full window size expressed in UIParent UI units, independent of UIParent's rect.
function Roots:GetSpanSize()
    local span = self:EnsureSpanRoot()
    local width, height = Read(span, "GetWidth"), Read(span, "GetHeight")
    local scale, uiScale = Read(span, "GetEffectiveScale"), Read(UIParent, "GetEffectiveScale")
    if not (Finite(width) and Finite(height) and Finite(scale) and Finite(uiScale))
        or width <= 0 or height <= 0 or scale <= 0 or uiScale <= 0 then return nil end
    local factor = scale / uiScale
    return width * factor, height * factor
end

function Roots:EnsureWorkspaceRoot()
    if self.workspace then return self.workspace end
    if type(CreateFrame) ~= "function" or not UIParent then return nil end
    local span = self:EnsureSpanRoot()
    if not span then return nil end
    local root = CreateFrame("Frame", "HearthsideWorkspaceRoot", UIParent)
    root:SetFrameStrata("LOW")
    root:Hide()
    self.workspace = root
    return root
end

-- rect: WORKSPACE in UIParent UI units, bottom-left origin of the physical window.
-- Offsets are in the receiving frame's units; WORKSPACE_ROOT inherits UIParent's scale.
function Roots:PlaceWorkspace(rect)
    local root = self:EnsureWorkspaceRoot()
    if not root or not MS.Rect:IsValid(rect) then return nil, "ERROR_WORKSPACE_ROOT" end
    local ok = pcall(function()
        root:ClearAllPoints()
        root:SetPoint("BOTTOMLEFT", self.span, "BOTTOMLEFT", rect.x, rect.y)
        root:SetSize(rect.width, rect.height)
        root:Show()
    end)
    if not ok then return nil, "ERROR_WORKSPACE_ROOT" end
    self.workspaceRect = rect
    return root
end

-- Another addon hides UIParent for a moment: the root waits on SPAN_ROOT, with
-- the same place and the same effective scale.
function Roots:DetachWorkspace()
    local root, span = self.workspace, self.span
    if not root or not span or self.workspaceDetached then return end
    local scale, uiScale = Read(span, "GetEffectiveScale"), Read(UIParent, "GetEffectiveScale")
    if not (Finite(scale) and Finite(uiScale)) or scale <= 0 or uiScale <= 0 then return end
    if pcall(function()
        root:SetParent(span)
        root:SetScale(uiScale / scale)
        root:SetFrameStrata("LOW")
    end) then self.workspaceDetached = true end
end

function Roots:AttachWorkspace()
    local root = self.workspace
    if not root or not self.workspaceDetached then return end
    self.workspaceDetached = nil
    pcall(function()
        root:SetParent(UIParent)
        root:SetScale(1)
        root:SetFrameStrata("LOW")
    end)
end

function Roots:HideWorkspace()
    self:AttachWorkspace()
    if self.workspace then pcall(self.workspace.Hide, self.workspace) end
    self.workspaceRect = nil
    return true
end

function Roots:GetStatus()
    local width, height = self:GetSpanSize()
    local root = self.workspace
    local x, y, w, h = Read(root, "GetRect")
    return { spanWidth = width, spanHeight = height,
        workspaceShown = Read(root, "IsShown") == true, workspaceVisible = Read(root, "IsVisible") == true,
        workspaceRect = x and { x = x, y = y, width = w, height = h } or nil,
        workspaceParent = root and Read(root, "GetParent") == UIParent and "UIParent" or tostring(root and Read(root, "GetParent")),
        workspaceAnchor = "SPAN_ROOT" }
end
