local MS = _G.MS
MS.TooltipBridge = { active = false, strategy = "JOURNEY_DEDICATED", reanchorCount = 0 }
local Bridge = MS.TooltipBridge
function Bridge:GetWorkspaceTooltip()
    if not self.tooltip and type(CreateFrame) == "function" and UIParent then
        self.tooltip = CreateFrame("GameTooltip", "JourneyWorkspaceTooltip", UIParent, "GameTooltipTemplate")
    end
    return self.tooltip
end
function Bridge:PrepareWorkspaceTooltip(owner)
    local tooltip, anchor = self:GetWorkspaceTooltip(), MS.Workspace and MS.Workspace.frame
    if not tooltip or not anchor then return end
    tooltip:SetOwner(owner, "ANCHOR_NONE")
    tooltip:ClearAllPoints()
    tooltip:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -8, 8)
    return tooltip
end
function Bridge:Enable()
    self.active = true
    self:GetWorkspaceTooltip()
    return true
end
function Bridge:Restore()
    self.active = false
    if self.tooltip then self.tooltip:Hide() end
    return true
end
function Bridge:GetStatus()
    return { active = self.active, strategy = self.strategy, containment = "VIEWPORT_CLAMP",
        reanchorCount = 0, continuousAdjust = false }
end
