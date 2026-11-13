local MS = _G.MS

MS.WorkspaceDebugOverlay = {}

local REGION_ORDER = { "header", "main", "side", "bottom" }
local REGION_COLORS = {
    header = { 0.20, 0.55, 0.95, 0.32 }, main = { 0.18, 0.78, 0.44, 0.25 },
    side = { 0.95, 0.60, 0.18, 0.30 }, bottom = { 0.70, 0.32, 0.90, 0.30 },
}

local function HasMethods(object, methods)
    if not object then return false end
    for _, method in ipairs(methods) do
        if type(object[method]) ~= "function" then return false end
    end
    return true
end

function MS.WorkspaceDebugOverlay:Create(parent)
    if self.frame then return true end
    if type(CreateFrame) ~= "function" or not HasMethods(parent, { "CreateTexture" }) then return nil, "ERROR_WORKSPACE_CREATE" end
    local created, overlay = pcall(CreateFrame, "Frame", nil, parent)
    if not created or not HasMethods(overlay, { "SetAllPoints", "Hide" }) then return nil, "ERROR_WORKSPACE_CREATE" end
    local regions = {}
    for _, name in ipairs(REGION_ORDER) do
        local region = CreateFrame("Frame", nil, overlay)
        local texture = region:CreateTexture(nil, "ARTWORK")
        local color = REGION_COLORS[name]
        texture:SetAllPoints(region)
        texture:SetColorTexture(color[1], color[2], color[3], color[4])
        local label = region:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER", region, "CENTER", 0, 0)
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        regions[name] = { frame = region, label = label }
    end
    overlay:SetAllPoints(parent)
    overlay:Hide()
    self.frame, self.regions = overlay, regions
    return true
end

function MS.WorkspaceDebugOverlay:Update(layout)
    if not self.frame or type(layout) ~= "table" then return end
    for _, name in ipairs(REGION_ORDER) do
        local definition, region = layout[name], self.regions[name]
        region.frame:ClearAllPoints()
        region.frame:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", definition.x, definition.y)
        region.frame:SetSize(definition.width, definition.height)
        region.label:SetText(string.format(MS.L.DEBUG_REGION_DIMENSIONS,
            MS.L["REGION_" .. string.upper(name)], definition.width, definition.height))
    end
end

function MS.WorkspaceDebugOverlay:SetShown(shown)
    if not self.frame then return end
    if shown then self.frame:Show() else self.frame:Hide() end
end
