local MS = _G.MS

-- Region coordinates are UI units local to the Workspace frame. (0, 0) is its bottom-left.
MS.WorkspaceLayout = {}

local WIDE_ASPECT_RATIO = 1.75
local PORTRAIT_ASPECT_RATIO = 0.90

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

local function MakeRect(x, y, width, height)
    return { x = x, y = y, width = width, height = height }
end

function MS.WorkspaceLayout:SelectClass(workspaceRect, metrics)
    local pxX = metrics and metrics.pixelsPerUiX or 1
    local pxY = metrics and metrics.pixelsPerUiY or 1
    local aspectRatio = (workspaceRect.width * pxX) / (workspaceRect.height * pxY)
    if aspectRatio >= WIDE_ASPECT_RATIO then
        return "WIDE", aspectRatio
    elseif aspectRatio < PORTRAIT_ASPECT_RATIO then
        return "PORTRAIT", aspectRatio
    end
    return "STANDARD", aspectRatio
end

function MS.WorkspaceLayout:Validate(layout, workspaceRect)
    if type(layout) ~= "table" or not MS.Rect:IsValid(workspaceRect) then return nil, "ERROR_WORKSPACE_LAYOUT" end
    local names = { "header", "main", "side", "bottom" }
    for _, name in ipairs(names) do
        local region = layout[name]
        if not MS.Rect:IsValid(region) or region.x < 0 or region.y < 0
            or region.x + region.width > workspaceRect.width
            or region.y + region.height > workspaceRect.height then
            return nil, "ERROR_WORKSPACE_LAYOUT"
        end
    end
    for first = 1, #names - 1 do
        for second = first + 1, #names do
            if MS.Rect:Intersects(layout[names[first]], layout[names[second]]) then
                return nil, "ERROR_WORKSPACE_LAYOUT"
            end
        end
    end
    return true
end

function MS.WorkspaceLayout:Calculate(workspaceRect)
    if not MS.Rect:IsValid(workspaceRect) then return nil, "ERROR_WORKSPACE_LAYOUT" end
    local metrics = MS.Transform and MS.Transform:GetMetrics()
    if not metrics then return nil, "ERROR_WORKSPACE_LAYOUT" end
    local pxX, pxY = metrics.pixelsPerUiX, metrics.pixelsPerUiY
    local layoutClass, aspectRatio = self:SelectClass(workspaceRect, metrics)
    local shortestPixels = math.min(workspaceRect.width * pxX, workspaceRect.height * pxY)
    local padding = Clamp(shortestPixels * 0.025, 12, 32) / pxX
    local gap = Clamp(shortestPixels * 0.02, 8, 24) / pxX
    local verticalPadding = Clamp(shortestPixels * 0.025, 12, 32) / pxY
    local verticalGap = Clamp(shortestPixels * 0.02, 8, 24) / pxY
    local innerWidth = workspaceRect.width - (padding * 2)
    local innerHeight = workspaceRect.height - (verticalPadding * 2)
    local headerHeight = Clamp(innerHeight * pxY * 0.09, 36, 76) / pxY
    local bottomHeight = Clamp(innerHeight * pxY * 0.08, 32, 68) / pxY
    local contentHeight = innerHeight - headerHeight - bottomHeight - (verticalGap * 2)
    if innerWidth <= 0 or contentHeight <= 0 then return nil, "ERROR_WORKSPACE_LAYOUT" end

    local contentY = verticalPadding + bottomHeight + verticalGap
    local layout = {
        class = layoutClass, aspectRatio = aspectRatio, padding = padding, gap = gap,
        header = MakeRect(padding, verticalPadding + innerHeight - headerHeight, innerWidth, headerHeight),
        bottom = MakeRect(padding, verticalPadding, innerWidth, bottomHeight),
    }
    if layoutClass == "PORTRAIT" then
        local sideHeight = Clamp(contentHeight * pxY * 0.28, 96, 240) / pxY
        local mainHeight = contentHeight - sideHeight - verticalGap
        if mainHeight <= 0 then return nil, "ERROR_WORKSPACE_LAYOUT" end
        layout.side = MakeRect(padding, contentY, innerWidth, sideHeight)
        layout.main = MakeRect(padding, contentY + sideHeight + verticalGap, innerWidth, mainHeight)
    else
        local sideFraction = layoutClass == "WIDE" and 0.26 or 0.30
        local sideWidth = Clamp(innerWidth * pxX * sideFraction, 180, 420) / pxX
        local mainWidth = innerWidth - sideWidth - gap
        if mainWidth <= 0 then return nil, "ERROR_WORKSPACE_LAYOUT" end
        layout.main = MakeRect(padding, contentY, mainWidth, contentHeight)
        layout.side = MakeRect(padding + mainWidth + gap, contentY, sideWidth, contentHeight)
    end
    local valid, errorMessage = self:Validate(layout, workspaceRect)
    if not valid then return nil, errorMessage end
    return layout
end

function MS.WorkspaceLayout:GetThresholds()
    return { wide = WIDE_ASPECT_RATIO, portrait = PORTRAIT_ASPECT_RATIO }
end
