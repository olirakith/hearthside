local MS = _G.MS

-- Under the tabs: the running Contrat, or else the way in to Sur mes pas and Contrat, which
-- would otherwise take a slash command. When those are unavailable the band has no height.
MS.JourneyContractBand = {}
local Band = MS.JourneyContractBand

local HEIGHT = 30

local function Current()
    local contracts = MS.Active and MS.Active.Contracts
    return contracts and contracts:Current() or nil
end

local function Mode()
    if Current() then return "RUNNING" end
    local active = MS.Active
    return active and active:Ready() and "IDLE" or nil
end

function Band:Height(view)
    if view == "SETTINGS" or not Mode() then return 0 end
    return HEIGHT
end

function Band:Create(parent)
    if self.frame then return end
    local Style = MS.JourneyUIStyle
    local frame = CreateFrame("Button", nil, parent)
    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints(frame)
    Style:Color(frame.background, "backgroundPanel")
    frame.rule = frame:CreateTexture(nil, "ARTWORK")
    frame.rule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 5, 0)
    frame.rule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 0)
    frame.rule:SetHeight(1)
    Style:Color(frame.rule, "borderMuted")
    local function Label(color, justify)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        Style:Body(label, "SECONDARY", color)
        label:SetJustifyH(justify); label:SetWordWrap(false); label:SetMaxLines(1)
        return label
    end
    frame.link = Label("gold", "RIGHT")
    frame.link:SetPoint("RIGHT", frame, "RIGHT", -Style.space.md, 0)
    -- The live view, for a stream: its own link beside the band's.
    frame.live = CreateFrame("Button", nil, frame)
    frame.live:SetHeight(HEIGHT)
    frame.live.label = frame.live:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Style:Body(frame.live.label, "SECONDARY", "gold")
    frame.live.label:SetPoint("RIGHT", frame.live, "RIGHT", 0, 0)
    frame.live.label:SetText(MS.L.CONTRACT_LIVE)
    frame.live:SetPoint("RIGHT", frame.link, "LEFT", -Style.space.md, 0)
    frame.live:SetWidth(120)
    Style:Link(frame.live, frame.live.label)
    frame.live:SetScript("OnClick", function() if MS.JourneyLiveView then MS.JourneyLiveView:Open() end end)
    frame.text = Label("textPrimary", "LEFT")
    frame.text:SetPoint("LEFT", frame, "LEFT", Style.space.md, 0)
    Style:Link(frame, frame.link)
    frame:SetScript("OnClick", function()
        local panel = MS.Active and MS.Active.Panel
        if panel then panel:Open(Current() and "CONTRACT" or "HOME") end
    end)
    frame:Hide()
    self.frame = frame
    self:ShowLive()
end

-- The live link only when the streamer turned the setting on; the text takes its room otherwise.
function Band:ShowLive()
    local frame = self.frame
    if not frame then return end
    local live = MS.JourneyLiveView ~= nil and MS.JourneyLiveView:Enabled()
    frame.live:SetShown(live)
    frame.text:ClearAllPoints()
    frame.text:SetPoint("LEFT", frame, "LEFT", MS.JourneyUIStyle.space.md, 0)
    frame.text:SetPoint("RIGHT", live and frame.live or frame.link, "LEFT", -MS.JourneyUIStyle.space.md, 0)
end

function Band:Text(contract)
    local A, L = MS.Active, MS.L
    local elapsed = A.ContractEngine:Elapsed(contract, A.Now())
    local limit = A.ContractEngine:Param(contract, "TIME_LIMIT")
    local clock
    if limit and type(elapsed) == "number" then
        clock = string.format(L.CONTRACT_BAND_LEFT, A.ContractText:Duration(math.max(0, limit - elapsed)))
    else
        clock = string.format(L.CONTRACT_BAND_SINCE, A.ContractText:Duration(elapsed))
    end
    return string.format(L.CONTRACT_BAND, A.ContractText:ContractTitle(contract.goal), clock)
end

-- rect is the strip LayoutView freed; an empty strip hides the band.
function Band:Layout(rect)
    if not self.frame then return end
    if not rect or rect.height <= 0 then self.frame:Hide(); return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    self.frame:SetSize(rect.width, rect.height)
    self.frame:Show()
    self:Refresh()
end

-- The way in stays quieter than a running Contrat.
function Band:Dress(mode)
    local L, frame = MS.L, self.frame
    local running = mode == "RUNNING"
    MS.JourneyUIStyle:Text(frame.text, running and "textPrimary" or "textSecondary")
    frame.link:SetText(running and L.CONTRACT_BAND_OPEN or L.ACTIVE_HOME_OPEN)
    if not running then frame.text:SetText(string.format(L.ACTIVE_BAND_IDLE, L.SEAL_NAME, L.CONTRACT_NAME)) end
end

-- Every second while a Contrat runs, and when one starts or ends.
function Band:Refresh()
    if not self.frame then return end
    local contract = Current()
    if contract then self.frame.text:SetText(self:Text(contract)) end
    local mode = Mode()
    if self.mode == mode then return end
    self.mode = mode
    self:Dress(mode)
    local Journey = MS.JourneyWorkspace
    if Journey and Journey.header and Journey.view then Journey:LayoutView(Journey.view) end
    local bar = MS.JourneyStatusBar
    if bar and bar.frame and bar.RenderText then bar:RenderText() end
end
