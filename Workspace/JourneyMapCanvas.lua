local MS = _G.MS

-- The Journey map surface: a Blizzard map canvas of our own, built the way the zone map (Shift+M)
-- builds its frame, plus the quest pins of the world map. WorldMapFrame is never touched. If it
-- cannot be built, the older Journey map stays. `/aj carte` switches between the two and reports.
MS.JourneyMapCanvas = { lines = {}, enabled = true }
local Canvas = MS.JourneyMapCanvas

-- Blizzard's template has neither the scroll container nor the border frame its OnLoad needs,
-- hence the manual assembly.
local REQUIRED = { "Blizzard_MapCanvas", "Blizzard_SharedMapDataProviders", "Blizzard_BattlefieldMap" }
local QUEST_PINS = { QuestPinTemplate = true, QuestOfferPinTemplate = true }
local LEVEL_ABOVE_JOURNEY = 30

function Canvas:Note(text) self.lines[#self.lines + 1] = text end

function Canvas:Load()
    local load = _G.C_AddOns and _G.C_AddOns.LoadAddOn
    if type(load) ~= "function" then self:Note("load unavailable"); return end
    for _, name in ipairs(REQUIRED) do
        local ok, loaded, reason = pcall(load, name)
        self:Note(string.format("load %s ok=%s loaded=%s reason=%s", name, tostring(ok), tostring(loaded),
            tostring(reason)))
    end
end

local function PinQuestID(pin) return pin.GetQuestID and pin:GetQuestID() or pin.questID end

-- A left click keeps its native meaning (super track) and also opens the quest in Journey's panel.
-- A right click opens the Journey quest menu, or goes up a map when it has nothing to offer.
-- Hovering marks the list row.
local function WireQuestPin(pin)
    if pin.journeyWired then return end
    pin.journeyWired = true
    local nativeClick = pin.OnMouseClickAction
    pin.ShouldMouseButtonBePassthrough = function() return false end
    -- A QuestieDB offer is not a quest of the log: our tooltip replaces the native one after it,
    -- no native action, cleared on release.
    local nativeReleased = pin.OnReleased
    pin:HookScript("OnEnter", function(self)
        if self.journeyQuestie and MS.JourneyQuestieOffers then MS.JourneyQuestieOffers:ShowTooltip(self) end
    end)
    pin.OnReleased = function(self, ...)
        self.journeyQuestie = nil
        if nativeReleased then return nativeReleased(self, ...) end
    end
    pin:HookScript("OnEnter", function(self) MS.MapView:HoverQuest(PinQuestID(self)) end)
    pin:HookScript("OnLeave", function() MS.MapView:HoverQuest(nil) end)
    pin.OnMouseClickAction = function(self, button, ...)
        if self.journeyQuestie then return end
        local quest = MS.MapView:QuestFromPin(PinQuestID(self))
        if button == "RightButton" then
            if not MS.MapView:OpenQuestMenu(quest, "MAP_PIN") then MS.MapView:GoToParent() end
            return
        end
        if nativeClick then nativeClick(self, button, ...) end
        MS.MapView:SelectQuest(quest)
    end
    pin:CheckMouseButtonPassthrough("RightButton")
end

local function OnCanvasClick(map, button, x, y)
    if button == "LeftButton" and MS.JourneyContextPanel then
        local info = _G.C_Map.GetMapInfoAtPosition(map:GetMapID(), x, y)
        if not info or info.mapID == map:GetMapID() then MS.JourneyContextPanel:Clear() end
    end
    return false
end

function Canvas:AddQuestLayer(frame)
    local levels = frame:GetPinFrameLevelsManager()
    levels:InsertFrameLevelAbove("PIN_FRAME_LEVEL_QUEST_BLOB", "PIN_FRAME_LEVEL_FOG_OF_WAR")
    local below = "PIN_FRAME_LEVEL_GROUP_MEMBER"
    levels:InsertFrameLevelBelow("PIN_FRAME_LEVEL_QUEST_OFFER", below, _G.QuestOfferDataProviderMixin.PIN_LEVEL_RANGE)
    levels:InsertFrameLevelBelow("PIN_FRAME_LEVEL_QUEST_PING", below)
    levels:InsertFrameLevelBelow("PIN_FRAME_LEVEL_ACTIVE_QUEST", below, _G.C_QuestLog.GetMaxNumQuests())
    levels:InsertFrameLevelBelow("PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST", below)
    local acquire = frame.AcquirePin
    frame.AcquirePin = function(map, template, ...)
        local pin = acquire(map, template, ...)
        if QUEST_PINS[template] then WireQuestPin(pin) end
        return pin
    end
    for _, name in ipairs({ "QuestBlobDataProviderMixin", "QuestOfferDataProviderMixin", "QuestDataProviderMixin" }) do
        local provider = _G.CreateFromMixins(_G[name])
        if name == "QuestOfferDataProviderMixin" then self:AddQuestieOffers(provider) end
        frame:AddDataProvider(provider)
    end
end

-- Experiment: QuestieDB offers join Blizzard's, on this canvas only, when the player has QuestieDB.
function Canvas:AddQuestieOffers(provider)
    local native = provider.GetAllQuestOffersForMap
    provider.GetAllQuestOffersForMap = function(self, mapID)
        local offers = native(self, mapID)
        if MS.JourneyQuestieOffers then pcall(MS.JourneyQuestieOffers.AddOffers, MS.JourneyQuestieOffers, offers, mapID) end
        return offers
    end
    self.offers = provider
end

-- A map changed by a click on the canvas takes Journey with it: breadcrumb, quest list, mode.
function Canvas:AddJourneyLink(frame)
    local link = _G.CreateFromMixins(_G.MapCanvasDataProviderMixin)
    function link:GetPinTemplate() return "QuestOfferPinTemplate" end
    function link:OnMapChanged()
        local mapID = self:GetMap():GetMapID()
        if mapID ~= MS.MapView.mapID then MS.MapView:Navigate(mapID) end
    end
    frame:AddDataProvider(link)
    frame:AddCanvasClickHandler(OnCanvasClick)
    self.link = link
end

function Canvas:Build(parent)
    local frame = CreateFrame("Frame", nil, parent)
    -- Born hidden like the template: a pin hidden on a shown canvas runs OnHide before it is set up.
    frame:Hide()
    _G.Mixin(frame, _G.MapCanvasMixin)
    CreateFrame("ScrollFrame", nil, frame, "MapCanvasFrameScrollContainerTemplate")
    frame.ScrollContainer:ClearAllPoints()
    frame.ScrollContainer:SetAllPoints(frame)
    frame.BorderFrame = CreateFrame("Frame", nil, frame)
    frame.BorderFrame:SetAllPoints(frame)
    frame:OnLoad()
    frame:SetShouldZoomInOnClick(false)
    frame:SetShouldPanOnClick(false)
    frame:SetShouldNavigateOnClick(true)
    frame:SetShouldZoomInstantly(true)
    _G.BattlefieldMapMixin.AddStandardDataProviders(frame)
    self:AddQuestLayer(frame)
    MS.JourneyTrace:Attach(frame)
    self:AddJourneyLink(frame)
    for _, script in ipairs({ "OnUpdate", "OnShow", "OnHide", "OnEvent" }) do
        frame:SetScript(script, frame[script])
    end
    frame:HookScript("OnUpdate", function() self:LiftTooltip(frame:IsMouseOver()) end)
    frame:HookScript("OnHide", function() self:LiftTooltip(false) end)
    return frame
end

function Canvas:LiftTooltip(lifted)
    if MS.ViewportTooltipClamp then MS.ViewportTooltipClamp:SetLifted(lifted) end
end

function Canvas:Create()
    local view = MS.MapView
    self:Load()
    for _, name in ipairs({ "MapCanvasMixin", "BattlefieldMapMixin", "QuestDataProviderMixin" }) do
        self:Note(string.format("%s present=%s", name, tostring(_G[name] ~= nil)))
        if not _G[name] then return false end
    end
    local ok, result = pcall(self.Build, self, view.mapPanel)
    if not ok then self:Note("build error " .. tostring(result)); return false end
    result:SetAllPoints(view.canvas)
    result:SetFrameLevel(view.canvas:GetFrameLevel() + LEVEL_ABOVE_JOURNEY)
    self.frame = result
    return true
end

-- Loading Blizzard's map addons waits for the end of a fight: the older map serves until then.
function Canvas:Attach()
    if self.frame then return true end
    if self.failed then return false end
    if _G.InCombatLockdown and _G.InCombatLockdown() then self:Note("waits for the end of combat"); return false end
    if self:Create() then return true end
    self.failed = true
    return false
end

function Canvas:Sync(mapID)
    local view = MS.MapView
    local useCanvas = self.enabled and mapID ~= nil and self:Attach()
    if useCanvas then
        local ok, err = pcall(function()
            self.frame:SetMapID(mapID)
            self.frame:Show()
        end)
        if not ok then
            self:Note("show error " .. tostring(err))
            self.failed, useCanvas = true, false
        end
    end
    if not useCanvas and self.frame then self.frame:Hide() end
    if MS.JourneyQuestPoiNotice then MS.JourneyQuestPoiNotice:Update() end
    if useCanvas then view.canvas:Hide() else view.canvas:Show() end
    view.status.mapRenderer = useCanvas and "BLIZZARD_CANVAS" or "JOURNEY_FALLBACK"
end

function Canvas:Highlight(questID)
    local manager = _G.POIButtonHighlightManager
    if not manager or not self.frame or not self.frame:IsVisible() then return end
    if questID then manager:SetHighlight(questID) else manager:ClearHighlight() end
end

-- Shows on the map the quest picked in the list: the native ping for a quest in progress, the same
-- ping on the pin of a quest to pick up. A quest without a pin here simply pings nothing.
function Canvas:Ping(questID)
    if not self.frame or not self.frame:IsVisible() then return end
    _G.EventRegistry:TriggerEvent("MapCanvas.PingQuestID", questID)
    pcall(self.link.PingPin, self.link, "questID", questID, "PIN_FRAME_LEVEL_QUEST_PING", 2)
end

function Canvas:Report()
    local frame = self.frame
    self:Note(string.format("enabled=%s failed=%s renderer=%s", tostring(self.enabled), tostring(self.failed == true),
        tostring(MS.MapView.status.mapRenderer)))
    if frame then
        self:Note(string.format("shown=%s map=%s size=%sx%s", tostring(frame:IsShown()), tostring(frame:GetMapID()),
            tostring(frame:GetWidth()), tostring(frame:GetHeight())))
        local ok, err = pcall(function()
            for template in pairs(frame.pinPools) do
                local count = 0
                for _ in frame:EnumeratePinsByTemplate(template) do count = count + 1 end
                self:Note(string.format("pins %s=%d", tostring(template), count))
            end
        end)
        if not ok then self:Note("pins error " .. tostring(err)) end
    end
    return table.concat(self.lines, "\n")
end

function Canvas:Toggle()
    self.lines = {}
    self.enabled = not self.enabled
    self:Sync(MS.MapView.mapID)
    return self:Report()
end
