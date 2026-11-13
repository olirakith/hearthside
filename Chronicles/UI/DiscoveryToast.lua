local MS = _G.MS
MS.ChroniclesDiscoveryToast = { duration = 7, pollInterval = .5 }
local Toast = MS.ChroniclesDiscoveryToast

local function Shown(frame)
    return frame and frame:IsShown() or false
end

local function InCombat()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() or false
end

local function SensitiveScreen()
    return Shown(_G.CinematicFrame) or Shown(_G.MovieFrame) or Shown(_G.QuestFrame)
end

local function OtherNotification()
    return Shown(_G.AlertFrame) or Shown(_G.StaticPopup1) or Shown(_G.StaticPopup2)
        or Shown(_G.StaticPopup3) or Shown(_G.StaticPopup4)
        or (MS.JourneyCardArbiter ~= nil and MS.JourneyCardArbiter:Blocks("CHRONICLES"))
end

local function Label(parent, style, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    MS.JourneyUIStyle:Apply(label, style)
    MS.JourneyUIStyle:Text(label, color)
    label:SetJustifyH("LEFT")
    return label
end

function Toast:OnLogin()
    self:Delay(2)
end

function Toast:Delay(seconds)
    local ok, now = pcall(_G.time)
    if ok then self.notBefore = math.max(self.notBefore or 0, now + seconds) end
end

function Toast:Create(parent)
    if self.frame then return end
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetSize(316, 122)
    self.frame:SetFrameStrata("DIALOG")
    self.background = self.frame:CreateTexture(nil, "BACKGROUND")
    self.background:SetAllPoints(self.frame)
    MS.JourneyUIStyle:Color(self.background, "backgroundDeep")
    self.rule = self.frame:CreateTexture(nil, "ARTWORK")
    self.rule:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 12, -12)
    self.rule:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -12, -12)
    self.rule:SetHeight(2)
    MS.JourneyUIStyle:Color(self.rule, "bronze")
    self.heading = Label(self.frame, "SMALL", "gold")
    self.heading:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -22)
    self.heading:SetWidth(284)
    self.title = Label(self.frame, "HEADING", "textPrimary")
    self.title:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -46)
    self.title:SetWidth(284)
    self.detail = Label(self.frame, "SMALL", "textSecondary")
    self.detail:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -73)
    self.detail:SetWidth(284)
    self.action = CreateFrame("Button", nil, self.frame)
    self.action:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -16, 8)
    self.action:SetSize(105, 24)
    self.action.label = Label(self.action, "BODY", "gold")
    self.action.label:SetAllPoints(self.action)
    self.action.label:SetJustifyH("RIGHT")
    self.action.label:SetText(MS.L.CHRONICLES_DISCOVER_ACTION)
    self.action:SetScript("OnClick", function() Toast:Open() end)
    self.frame:Hide()
    -- A hidden frame receives no OnUpdate. Keep queue polling on a separate,
    -- mouse-transparent child of the Workspace while Journey is visible.
    self.pilot = CreateFrame("Frame", nil, parent)
    self.pilot:SetAllPoints(parent)
    self.pilot:EnableMouse(false)
    self.pilot:SetScript("OnUpdate", function(_, elapsed) Toast:Tick(elapsed) end)
    self.pilot:Show()
end

function Toast:Layout()
    if not self.frame or not MS.Workspace.layout then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPRIGHT", MS.Workspace.frame, "TOPRIGHT", -28, -88)
end

function Toast:Dismiss()
    if not self.visible then return end
    local queue = MS.Chronicles.notificationQueue
    if queue and self.batchID then queue:AcknowledgeBatch(self.batchID) end
    self.visible, self.batchID, self.chronicleID, self.regionID = false, nil, nil, nil
    self.frame:Hide()
end

function Toast:Open()
    local id, regionID = self.chronicleID, self.regionID
    self:Dismiss()
    if MS.JourneyWorkspace and MS.JourneyWorkspace.active then
        local opened = MS.JourneyWorkspace:SelectView("CHRONICLES")
        if opened and id then MS.ChroniclesView:OpenChronicle(id) end
        if opened and regionID then MS.ChroniclesView:OpenRegion(regionID) end
    end
end

function Toast:Present(batch, now)
    local chosen, chronicle, regionID
    local rank = { LOW = 1, NORMAL = 2, IMPORTANT = 3 }
    for _, event in ipairs(batch.events) do
        local item = event.type == "CHRONICLE_DISCOVERED"
            and MS.Chronicles:GetChronicle(event.contentID) or nil
        local region = event.type == "RUMOR_DISCOVERED"
            and MS.Chronicles:GetRumorRegion(event.contentID)
            or event.type == "REGION_VISITED"
                and MS.Chronicles:GetVisitedRegion(event.contentID) or nil
        if (item or region) and (not chosen
            or rank[event.priority] > rank[chosen.priority]) then
            chosen, chronicle, regionID = event, item, region
        end
    end
    if not chosen then
        MS.Chronicles.notificationQueue:AcknowledgeBatch(batch.batchID)
        return
    end
    self.chronicleID = chronicle and chosen.contentID or nil
    self.regionID = regionID
    self.heading:SetText(chronicle and MS.L.CHRONICLES_DISCOVERED
        or chosen.type == "RUMOR_DISCOVERED" and MS.L.CHRONICLES_RUMOR_DISCOVERED
        or MS.L.CHRONICLES_REGION_VISITED)
    self.title:SetText(chronicle and chronicle.title
        or chosen.type == "REGION_VISITED" and MS.Chronicles:GetRegionName(chosen.contentID)
        or MS.L.CHRONICLES_NEW_RUMOR)
    self.detail:SetText(chronicle and MS.Chronicles:GetRegionName(chronicle.region)
        or MS.L.CHRONICLES_GRIMOIRE)
    self.batchID, self.visible, self.shownFor = batch.batchID, true, 0
    self.lastPresentedAt = now
    self.frame:SetAlpha(1)
    self.frame:Show()
end

function Toast:Tick(elapsed)
    if self.visible then
        if not MS.JourneyWorkspace or not MS.JourneyWorkspace.active
            or not MS.Workspace.frame:IsShown() or InCombat()
            or SensitiveScreen() or OtherNotification() then self:Dismiss(); return end
        self.shownFor = self.shownFor + elapsed
        if self.shownFor > self.duration - 1 then
            self.frame:SetAlpha(math.max(0, self.duration - self.shownFor))
        end
        if self.shownFor >= self.duration then self:Dismiss() end
        return
    end
    self.poll = (self.poll or 0) + elapsed
    if self.poll < self.pollInterval then return end
    self.poll = 0
    if not MS.JourneyWorkspace or not MS.JourneyWorkspace.active
        or not MS.Chronicles or not MS.Chronicles.available then return end
    local queue = MS.Chronicles.notificationQueue
    if not queue then return end
    local now = type(_G.time) == "function" and _G.time() or nil
    if not now then return end
    local context = {
        inCombat = InCombat(),
        loading = not MS.Workspace.frame:IsShown() or now < (self.notBefore or 0),
        sensitiveScreen = SensitiveScreen(),
        anotherNotificationVisible = OtherNotification(),
        lastPresentedAt = self.lastPresentedAt,
    }
    local batch = queue:PeekBatch(context, now)
    if batch.status == "READY" then
        local ok = pcall(self.Present, self, batch, now)
        if not ok then
            self.visible, self.batchID, self.chronicleID, self.regionID = false, nil, nil, nil
            self.frame:Hide()
        end
    end
end
