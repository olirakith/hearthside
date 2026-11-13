local MS = _G.MS

MS.Transform = {}

function MS.Transform:GetMetrics()
    local reportedPhysicalWidth, reportedPhysicalHeight
    if GetPhysicalScreenSize then
        reportedPhysicalWidth, reportedPhysicalHeight = GetPhysicalScreenSize()
    end
    local screenWidth, screenHeight
    if GetScreenWidth and GetScreenHeight then
        screenWidth, screenHeight = GetScreenWidth(), GetScreenHeight()
    end
    local uiWidth, uiHeight = UIParent:GetWidth(), UIParent:GetHeight()
    -- VIEWPORT: UIParent may be the GAME viewport; SPAN_ROOT measures the window.
    if MS.ViewportRoots then
        local spanWidth, spanHeight = MS.ViewportRoots:GetSpanSize()
        if spanWidth then uiWidth, uiHeight = spanWidth, spanHeight end
    end
    local effectiveScale = UIParent:GetEffectiveScale()
    if uiWidth <= 0 or uiHeight <= 0 or not effectiveScale or effectiveScale <= 0 then
        return nil
    end
    local estimatedPhysicalWidth = uiWidth * effectiveScale
    local estimatedPhysicalHeight = uiHeight * effectiveScale
    local physicalWidth, physicalHeight, physicalSource
    if reportedPhysicalWidth and reportedPhysicalHeight then
        physicalWidth, physicalHeight, physicalSource = reportedPhysicalWidth, reportedPhysicalHeight, "reported"
    elseif estimatedPhysicalWidth > 0 and estimatedPhysicalHeight > 0 then
        physicalWidth, physicalHeight, physicalSource = estimatedPhysicalWidth, estimatedPhysicalHeight, "estimated"
    elseif screenWidth and screenHeight then
        physicalWidth, physicalHeight, physicalSource = screenWidth, screenHeight, "screen"
    else
        return nil
    end
    return {
        physicalWidth = physicalWidth,
        physicalHeight = physicalHeight,
        physicalSource = physicalSource,
        reportedPhysicalWidth = reportedPhysicalWidth,
        reportedPhysicalHeight = reportedPhysicalHeight,
        screenWidth = screenWidth,
        screenHeight = screenHeight,
        uiWidth = uiWidth,
        uiHeight = uiHeight,
        effectiveScale = effectiveScale,
        estimatedPhysicalWidth = estimatedPhysicalWidth,
        estimatedPhysicalHeight = estimatedPhysicalHeight,
        pixelsPerUiX = physicalWidth / uiWidth,
        pixelsPerUiY = physicalHeight / uiHeight,
    }
end

function MS.Transform:RectToUI(rect, metrics)
    return {
        x = rect.x / metrics.pixelsPerUiX,
        y = rect.y / metrics.pixelsPerUiY,
        width = rect.width / metrics.pixelsPerUiX,
        height = rect.height / metrics.pixelsPerUiY,
    }
end

function MS.Transform:RectToFrameOffsets(rect, relativeFrame, receivingFrame)
    local relativeEffectiveScale = relativeFrame:GetEffectiveScale()
    local receivingEffectiveScale = receivingFrame:GetEffectiveScale()
    if not relativeEffectiveScale or relativeEffectiveScale <= 0
        or not receivingEffectiveScale or receivingEffectiveScale <= 0 then
        return nil
    end

    local factor = relativeEffectiveScale / receivingEffectiveScale
    return {
        x = rect.x * factor,
        y = rect.y * factor,
        width = rect.width * factor,
        height = rect.height * factor,
        factor = factor,
    }
end

function MS.Transform:FrameRectToUI(rect, frame, uiParent)
    local frameEffectiveScale = frame:GetEffectiveScale()
    local uiParentEffectiveScale = uiParent:GetEffectiveScale()
    if not frameEffectiveScale or frameEffectiveScale <= 0
        or not uiParentEffectiveScale or uiParentEffectiveScale <= 0 then
        return nil
    end

    local factor = frameEffectiveScale / uiParentEffectiveScale
    return {
        x = rect.x * factor,
        y = rect.y * factor,
        width = rect.width * factor,
        height = rect.height * factor,
    }
end

function MS.Transform:UIRectToPhysical(rect, metrics)
    return {
        x = rect.x * metrics.pixelsPerUiX,
        y = rect.y * metrics.pixelsPerUiY,
        width = rect.width * metrics.pixelsPerUiX,
        height = rect.height * metrics.pixelsPerUiY,
    }
end
