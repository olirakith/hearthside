local MS = _G.MS

MS.LayoutEngine = {}

function MS.LayoutEngine:Build()
    local config = MS.Config
    if not config or type(config.GetLayout) ~= "function" or not MS.Rect or not MS.Transform then
        return nil, "ERROR_CONFIG"
    end

    local layout, source, layoutError = config:GetLayout()
    if not layout then return nil, layoutError or "ERROR_CONFIG" end

    local metrics = MS.Transform:GetMetrics()
    if not metrics then
        return nil, "ERROR_METRICS"
    end
    if source == "COMPANION_GENERATED"
        and (metrics.reportedPhysicalWidth ~= layout.span.width
            or metrics.reportedPhysicalHeight ~= layout.span.height) then
        return nil, "ERROR_GENERATED_SPAN_MISMATCH"
    end

    if not MS.Rect:IsInside(layout.game, metrics.physicalWidth, metrics.physicalHeight) then
        return nil, "ERROR_GAME_RECT"
    end
    if not MS.Rect:IsInside(layout.workspace, metrics.physicalWidth, metrics.physicalHeight) then
        return nil, "ERROR_WORKSPACE_RECT"
    end
    if MS.Rect:Intersects(layout.game, layout.workspace) then
        return nil, "ERROR_OVERLAP"
    end

    return {
        metrics = metrics,
        game = MS.Transform:RectToUI(layout.game, metrics),
        workspace = MS.Transform:RectToUI(layout.workspace, metrics),
        physicalGame = layout.game,
        physicalWorkspace = layout.workspace,
    }
end
