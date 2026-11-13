local MS = _G.MS

MS.Rect = {}

function MS.Rect:IsValid(rect)
    return type(rect) == "table"
        and type(rect.x) == "number"
        and type(rect.y) == "number"
        and type(rect.width) == "number" and rect.width > 0
        and type(rect.height) == "number" and rect.height > 0
end

function MS.Rect:IsInside(rect, width, height)
    return self:IsValid(rect)
        and rect.x >= 0 and rect.y >= 0
        and rect.x + rect.width <= width
        and rect.y + rect.height <= height
end

function MS.Rect:Intersects(first, second)
    return first.x < second.x + second.width
        and second.x < first.x + first.width
        and first.y < second.y + second.height
        and second.y < first.y + first.height
end

function MS.Rect:ToString(rect)
    if not self:IsValid(rect) then
        return MS.L.RECT_UNSET
    end
    return string.format("x=%.2f, y=%.2f, width=%.2f, height=%.2f", rect.x, rect.y, rect.width, rect.height)
end
