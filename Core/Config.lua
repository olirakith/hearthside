local MS = _G.MS

MS.Config = {
    version = 1,
    -- Chronicles is on hold: no tab, no setting, nothing runs. Its code and each player's saved
    -- discoveries stay in place, so setting this to false brings everything back.
    chroniclesPaused = true,
}

local function Finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function ValidRect(rect)
    return type(rect) == "table"
        and Finite(rect.x) and Finite(rect.y)
        and Finite(rect.width) and Finite(rect.height)
        and rect.width > 0 and rect.height > 0
end

function MS.Config:GetLayout()
    local generated = MS.GeneratedLayout
    if generated == nil then return nil, "MISSING", "ERROR_GENERATED_MISSING" end
    if type(generated) ~= "table" or generated.schemaVersion ~= 1
        or type(generated.span) ~= "table"
        or not Finite(generated.span.width) or generated.span.width <= 0
        or not Finite(generated.span.height) or generated.span.height <= 0
        or not ValidRect(generated.game) or not ValidRect(generated.workspace)
        or not MS.Rect:IsInside(generated.game, generated.span.width, generated.span.height)
        or not MS.Rect:IsInside(generated.workspace, generated.span.width, generated.span.height)
        or MS.Rect:Intersects(generated.game, generated.workspace) then
        return nil, "INVALID", "ERROR_GENERATED_LAYOUT"
    end
    return generated, "COMPANION_GENERATED"
end
