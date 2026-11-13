local MS = _G.MS

-- A strip under the tabs for a friend's evening. Dormant: nothing calls SetFriend yet, and
-- without a friend the band has no height and nothing is drawn.
MS.JourneyMentorBand = { friend = nil }
local Band = MS.JourneyMentorBand

local HEIGHT = 36
local SEPARATOR = " · "

function Band:IsActive()
    return self.friend ~= nil
end

function Band:Height(view)
    if not self.friend or view == "SETTINGS" then return 0 end
    return HEIGHT
end

local function Relayout()
    local Journey = MS.JourneyWorkspace
    if Journey and Journey.header and Journey.LayoutView then Journey:LayoutView(Journey.view) end
    local bar = MS.JourneyStatusBar
    if bar and bar.frame and bar.RenderText then bar:RenderText() end
end

function Band:Shares(questID)
    local shared = self.friend and self.friend.sharedQuests
    if type(shared) ~= "table" then return false end
    for _, id in ipairs(shared) do
        if id == questID then return true end
    end
    return false
end

function Band:FriendName()
    return self.friend and self.friend.name or nil
end

function Band:FriendPosition()
    local friend = self.friend
    if not friend or friend.away or not friend.mapID or not friend.x or not friend.y then return nil end
    return friend.mapID, friend.x, friend.y
end

-- The two views follow the friend; each guard keeps files that load without them working.
local function RefreshViews()
    local journal = MS.QuestJournal
    if journal then
        if journal.visible and journal.Refresh then
            -- Refresh returns early unless dirty
            journal.dirty = true
            journal:Refresh()
        elseif journal.Invalidate then journal:Invalidate() end
    end
    local map = MS.MapView
    if map and map.active then
        if map.RenderSidebar then map:RenderSidebar() end
        if map.UpdateFriendPin then map:UpdateFriendPin() end
    end
end

function Band:SetFriend(model)
    if type(model) ~= "table" then return self:Clear() end
    local previous = self.friend
    local isNew = not previous or previous.name ~= model.name
    local shared
    if type(model.sharedQuests) == "table" then
        shared = {}
        for _, id in ipairs(model.sharedQuests) do shared[#shared + 1] = id end
    end
    self.friend = { name = model.name, level = model.level, zone = model.zone, line = model.line,
        away = model.away == true, sharedQuests = shared, mapID = model.mapID, x = model.x, y = model.y }
    -- Only a new friend moves the map; updates leave the player's navigation alone.
    if isNew and model.mapID and MS.MapView and MS.MapView.Navigate then MS.MapView:Navigate(model.mapID) end
    self:Refresh()
    Relayout()
    RefreshViews()
end

function Band:Clear()
    self.friend = nil
    if self.frame then self.frame:Hide() end
    Relayout()
    RefreshViews()
end

function Band:Create(parent)
    if self.frame then return end
    local Style = MS.JourneyUIStyle
    self.frame = CreateFrame("Frame", nil, parent)
    self.background = self.frame:CreateTexture(nil, "BACKGROUND")
    self.background:SetAllPoints(self.frame)
    Style:Color(self.background, "backgroundPanel")
    self.rule = self.frame:CreateTexture(nil, "ARTWORK")
    self.rule:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 5, 0)
    self.rule:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -5, 0)
    self.rule:SetHeight(1)
    Style:Color(self.rule, "borderMuted")
    local function Label(color)
        local label = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        Style:Body(label, "SECONDARY", color)
        label:SetJustifyH("LEFT"); label:SetJustifyV("MIDDLE")
        label:SetWordWrap(false); label:SetMaxLines(1)
        return label
    end
    self.name, self.meta, self.line = Label("textPrimary"), Label("textSecondary"), Label("textSecondary")
    self.close = CreateFrame("Button", nil, self.frame)
    self.close.label = self.close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Style:Body(self.close.label, "SECONDARY", "gold")
    self.close.label:SetAllPoints(self.close); self.close.label:SetJustifyH("RIGHT")
    self.close.label:SetWordWrap(false); self.close.label:SetMaxLines(1)
    Style:Link(self.close, self.close.label)
    self.close:SetScript("OnClick", function() Band:Clear() end)
    self.frame:Hide()
end

local function Width(label)
    local measured = label.GetStringWidth and label:GetStringWidth()
    return type(measured) == "number" and math.ceil(measured) + 2 or 1
end

-- rect is the strip LayoutView freed; an empty strip (no friend, SETTINGS) hides the band.
function Band:Layout(rect)
    if not self.frame then return end
    if not self.friend or not rect or rect.height <= 0 then self.frame:Hide(); return end
    local pad = MS.JourneyUIStyle.space.md
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    self.frame:SetSize(rect.width, rect.height)
    self.frame:Show()
    self:Refresh()
    local height = math.max(1, rect.height - 4)
    local closeWidth = math.min(Width(self.close.label) + 4, math.max(1, rect.width / 4))
    self.close:ClearAllPoints(); self.close:SetPoint("RIGHT", self.frame, "RIGHT", -pad, 0)
    self.close:SetSize(closeWidth, height)
    local nameWidth = math.min(Width(self.name), math.max(1, rect.width / 4))
    self.name:ClearAllPoints(); self.name:SetPoint("LEFT", self.frame, "LEFT", pad, 0)
    self.name:SetSize(nameWidth, height)
    local metaWidth = math.min(Width(self.meta), math.max(1, rect.width / 3))
    self.meta:ClearAllPoints(); self.meta:SetPoint("LEFT", self.name, "RIGHT", pad, 0)
    self.meta:SetSize(metaWidth, height)
    self.line:ClearAllPoints()
    self.line:SetPoint("LEFT", self.meta, "RIGHT", pad * 2, 0)
    self.line:SetPoint("RIGHT", self.close, "LEFT", -pad * 2, 0)
    self.line:SetHeight(height)
end

function Band:Refresh()
    if not self.frame or not self.friend then return end
    local friend = self.friend
    local meta = {}
    if type(friend.level) == "number" then meta[#meta + 1] = string.format(MS.L.JOURNEY_MENTOR_LEVEL, friend.level) end
    -- Streamer mode: the friend's name and where they are stay out of sight.
    local mode = MS.BroadcastMode
    local hidden = mode ~= nil and mode:IsOn()
    if not hidden and type(friend.zone) == "string" and friend.zone ~= "" then meta[#meta + 1] = friend.zone end
    local name = hidden and mode:Person(friend.name) or tostring(friend.name or "")
    self.name:SetText(name)
    self.meta:SetText(table.concat(meta, SEPARATOR))
    self.close.label:SetText(MS.L.JOURNEY_MENTOR_CLOSE)
    self.line:SetText(friend.away and string.format(MS.L.JOURNEY_MENTOR_AWAY, name)
        or tostring(friend.line or ""))
    MS.JourneyUIStyle:Text(self.line, friend.away and "muted" or "textSecondary")
end

if MS.BroadcastMode then
    MS.BroadcastMode:Listen(function()
        pcall(Band.Refresh, Band)
        local map = MS.MapView
        if map and map.active and map.UpdateFriendPin then pcall(map.UpdateFriendPin, map) end
    end)
end
