local MS = _G.MS

-- GAME region anchor in UIParent UI units. The GAME contract cross-checks its
-- rectangle against the configured layout (anchorMatches).
MS.GameUI = {}

function MS.GameUI:Create()
    if self.frame then return true end
    if type(CreateFrame) ~= "function" or not UIParent then return nil, "ERROR_GAMEUI_CREATE" end
    local created, frame = pcall(CreateFrame, "Frame", nil, UIParent)
    if not created or not frame or type(frame.ClearAllPoints) ~= "function" or type(frame.SetPoint) ~= "function"
        or type(frame.SetSize) ~= "function" or type(frame.Hide) ~= "function" then
        return nil, "ERROR_GAMEUI_CREATE"
    end
    frame:Hide()
    self.frame = frame
    return true
end

function MS.GameUI:Prepare(layout)
    local region = type(layout) == "table" and layout.game
    if not MS.Rect:IsValid(region) then return nil, "ERROR_GAMEUI_REGION" end
    local created, errorMessage = self:Create()
    if not created then return nil, errorMessage end
    local prepared = pcall(function()
        self.frame:ClearAllPoints()
        self.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", region.x, region.y)
        self.frame:SetSize(region.width, region.height)
        self.region = region
        self.frame:Show()
    end)
    if not prepared then return nil, "ERROR_GAMEUI_REGION" end
    return true
end

function MS.GameUI:GetRegion()
    if not self.region then return nil end
    return { x = self.region.x, y = self.region.y, width = self.region.width, height = self.region.height }
end

function MS.GameUI:Hide()
    if self.frame and type(self.frame.Hide) == "function" then self.frame:Hide() end
end
