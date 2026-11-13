local MS = _G.MS
MS.JourneyContextPanel = { selectedContext = { type = "EMPTY" }, dirty = true, refreshCount = 0,
    descriptionSupport = "UNAVAILABLE_SAFE_API" }
local Panel = MS.JourneyContextPanel
local Style = MS.JourneyUIStyle

local function State(quest)
    local key = ({ IN_PROGRESS = "JOURNEY_MAP_STATE_IN_PROGRESS", READY_TO_TURN_IN = "JOURNEY_CONTEXT_READY",
        AVAILABLE = "JOURNEY_MAP_STATE_AVAILABLE" })[quest.state]
    return MS.L[key or "JOURNEY_QUEST_DETAILS"]
end

local function ActionButton(parent, action)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(210, 28)
    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetAllPoints(button)
    Style:Color(button.background, "paperInset")
    button.rule = button:CreateTexture(nil, "BORDER")
    button.rule:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT")
    button.rule:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT")
    button.rule:SetHeight(1); Style:Color(button.rule, "paperAccent")
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.label:SetPoint("CENTER", button, "CENTER")
    Style:Body(button.label, "BODY")
    Style:Text(button.label, "ink")
    button:SetScript("OnClick", action)
    Style:Action(button, button.label, true)
    return button
end

function Panel:Create(parent)
    if self.frame then return end
    self.frame = CreateFrame("ScrollFrame", nil, parent)
    self.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -6)
    self.frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 6)
    self.content = CreateFrame("Frame", nil, self.frame)
    self.content:SetSize(1, 1)
    self.frame:SetScrollChild(self.content)
    self.readingPaper = self.content:CreateTexture(nil, "BACKGROUND")
    Style:PageMaterial(self.readingPaper, "PAPER")
    self.readingEdge = self.content:CreateTexture(nil, "BORDER")
    Style:Color(self.readingEdge, "borderMuted")
    self.objectivePaper = self.content:CreateTexture(nil, "BACKGROUND")
    Style:Color(self.objectivePaper, "paper")
    self.frame:EnableMouseWheel(true)
    self.frame:SetScript("OnMouseWheel", function(frame, delta)
        local maximum = math.max(0, self.content:GetHeight() - frame:GetHeight())
        frame:SetVerticalScroll(math.max(0, math.min(maximum, frame:GetVerticalScroll() - delta * 36)))
    end)
    self.title = self.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.stateIcon = self.content:CreateTexture(nil, "ARTWORK")
    self.stateIcon:SetSize(18, 18)
    self.meta = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.progressLabel = self.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.progressTrack = self.content:CreateTexture(nil, "ARTWORK")
    self.progressFill = self.content:CreateTexture(nil, "OVERLAY")
    self.section = self.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.body = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.loreSection = self.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.loreBody = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.questAction = ActionButton(self.content, function() Panel:OpenQuestDestination() end)
    -- Offered by a quest action provider (Community quest social actions), hidden otherwise.
    self.socialAction = ActionButton(self.content, function() Panel:RunSocialAction() end)
    self.socialAction:Hide()
    -- On the map, a zone opens as a short summary; this link unfolds or folds the whole text.
    self.zoneToggle = CreateFrame("Button", nil, self.content)
    self.zoneToggle.label = self.zoneToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.zoneToggle.label:SetPoint("LEFT", self.zoneToggle, "LEFT")
    Style:Body(self.zoneToggle.label, "SMALL")
    Style:Link(self.zoneToggle, self.zoneToggle.label, true)
    self.zoneToggle:SetScript("OnClick", function() Panel:ToggleZone() end)
    self.zoneToggle:Hide()
    Style:Heading(self.title, "TITLE", "ink")
    Style:Metadata(self.meta)
    Style:Body(self.progressLabel, "SECTION")
    Style:Body(self.section, "SECTION")
    Style:Body(self.body, "BODY")
    Style:Body(self.loreSection, "SECTION")
    Style:Body(self.loreBody, "BODY")
    for _, label in ipairs({ self.title, self.body, self.loreBody }) do Style:Text(label, "ink"); label:SetJustifyH("LEFT") end
    for _, label in ipairs({ self.meta, self.progressLabel, self.section, self.loreSection }) do
        Style:Text(label, "inkSecondary"); label:SetJustifyH("LEFT")
    end
    self.body:SetJustifyV("TOP")
    self.title:SetPoint("TOPLEFT", self.content, "TOPLEFT", 9, -9)
    self.meta:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -8)
    Style:Color(self.progressTrack, "paperInset")
    self.progressTrack:SetHeight(6)
    Style:Color(self.progressFill, "bronze")
    self.progressFill:SetHeight(6)
    self.progressFill:SetPoint("TOPLEFT", self.progressTrack, "TOPLEFT")
end

function Panel:Layout(width, height, mode)
    if not self.frame then return end
    local readingWidth, inset
    self.content:SetWidth(math.max(1, width - 18))
    if mode == "PAGE" then readingWidth, inset = Style:QuestReadingColumn(self.content:GetWidth())
    else readingWidth, inset = math.max(1, width - 40), 9 end
    self.readingWidth, self.readingInset = readingWidth, inset
    Style:Heading(self.title, mode == "PAGE" and "PAGE_TITLE" or "TITLE", "ink")
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", self.content, "TOPLEFT", inset, mode == "PAGE" and -42 or -9)
    self.title:SetWidth(math.max(1, mode == "NOTE" and width - 58 or readingWidth))
    for _, label in ipairs({ self.meta, self.progressLabel, self.section, self.body, self.loreSection, self.loreBody }) do
        label:SetWidth(math.max(1, readingWidth))
    end
    self.questAction:SetWidth(math.max(1, math.min(210, readingWidth)))
    self.socialAction:SetWidth(math.max(1, math.min(210, readingWidth)))
    self.meta:SetWidth(math.max(1, readingWidth))
    self.progressTrack:SetWidth(math.max(1, readingWidth))
    if self.width ~= width or self.height ~= height or self.mode ~= mode
        or self.textScale ~= MS.JourneySettings:Get("textScale") then
        self.width, self.height, self.mode, self.textScale, self.dirty =
            width, height, mode, MS.JourneySettings:Get("textScale"), true
    end
    self:Refresh()
end

function Panel:Mount(parent)
    if not self.frame or not parent then return end
    self.frame:SetParent(parent)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -6)
    self.frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 6)
end

function Panel:Present(kind, title, lines, questID, mapID, meta, percent, objectiveCount, lore)
    local body = table.concat(lines, "\n")
    local signature = table.concat({ kind, tostring(questID or ""), tostring(mapID or ""), title, body, meta or "", tostring(percent or ""), tostring(objectiveCount or 0), lore or "" }, "\031")
    self.selectedContext = { type = kind, questID = questID, mapID = mapID }
    if signature ~= self.signature then
        self.signature, self.titleText, self.bodyText, self.metaText, self.percent, self.objectiveCount, self.loreText, self.dirty =
            signature, title, body, meta, percent, objectiveCount or 0, lore, true
        if self.frame then self.frame:SetVerticalScroll(0) end
    end
    if MS.MapView and MS.MapView.RefreshSelection then MS.MapView:RefreshSelection() end
    if MS.QuestJournal and MS.QuestJournal.RefreshSelection then MS.QuestJournal:RefreshSelection() end
    self:Refresh()
end

-- A zone on the map reads as a summary until the player unfolds it.
function Panel:IsCompactZone()
    return self.selectedContext.type == "ZONE" and self.zoneExpanded ~= true
end

-- Title, summary and link: measured once drawn, estimated before.
function Panel:CompactHeight()
    return self.compactMeasured or math.floor(136 * MS.JourneySettings:Get("textScale") + .5)
end

function Panel:ToggleZone()
    self.zoneExpanded = not self.zoneExpanded
    self.dirty = true
    if self.frame then self.frame:SetVerticalScroll(0) end
    if MS.MapView and MS.MapView.active then MS.MapView:LayoutRightColumn() else self:Refresh() end
end

function Panel:Clear()
    self.questRecord = nil
    self.zoneExpanded = false
    self:Present("EMPTY", "", {}, nil, nil, "")
    if MS.MapView and MS.MapView.active then
        self:Sync(MS.MapView.quests, MS.JourneyMapData:Info(MS.MapView.mapID))
    end
end

function Panel:MapAction()
    local quest = self.questRecord
    if not quest then return nil end
    local function exact(poi)
        return type(poi) == "table" and poi.confidence == "HIGH" and type(poi.mapID) == "number"
            and type(poi.x) == "number" and poi.x >= 0 and poi.x <= 1
            and type(poi.y) == "number" and poi.y >= 0 and poi.y <= 1
            and MS.JourneyMapData:Info(poi.mapID) and MS.JourneyMapData:Art(poi.mapID)
    end
    if exact(quest.turnInPOI) then return "POINT", quest.turnInPOI.mapID end
    for _, poi in ipairs(quest.objectivePOIs or {}) do if exact(poi) then return "POINT", poi.mapID end end
    if exact(quest.availablePOI) then return "POINT", quest.availablePOI.mapID end
    -- Zone-only target: the trusted zone only (never raw mapID). Never a coordinate.
    local zone = MS.JourneyQuestData:TrustedZone(quest)
    if zone and MS.JourneyMapData:Art(zone) then return "REGION", zone end
end

function Panel:QuestMapID()
    local _, mapID = self:MapAction()
    return mapID
end

function Panel:OpenQuestDestination()
    if self.selectedContext.type ~= "QUEST" or not self.questRecord then return nil end
    local quest = self.questRecord
    if MS.JourneyWorkspace.view == "QUESTS" then
        local mapID = self:QuestMapID()
        if not mapID or not MS.MapView:Navigate(mapID) then return nil end
        self:SelectQuest(quest)
        return MS.JourneyWorkspace:SelectView("MAP")
    elseif MS.JourneyWorkspace.view == "MAP" then
        if not (MS.JourneyQuestData.latestByID or {})[quest.questID] then return nil end
        local opened = MS.JourneyWorkspace:SelectView("QUESTS")
        if opened then MS.QuestJournal:RevealSelectedQuest() end
        return opened
    end
end

function Panel:SelectQuest(quest)
    if type(quest) ~= "table" then return self:Clear() end
    self.memoryDirty = nil
    self.questRecord = quest
    local meta = State(quest)
    if type(quest.level) == "number" and quest.level > 0 then
        meta = meta .. " · " .. string.format(MS.L.JOURNEY_CONTEXT_LEVEL, quest.level)
    end
    -- Same trusted place label as CARTE / QUÊTES; nothing is shown without a trusted zone.
    local contextMapID = quest.displayMapID or MS.JourneyQuestData:TrustedZone(quest)
    if contextMapID then
        meta = meta .. " · " .. MS.JourneyQuestData:DisplayPlaceName(quest)
    end
    local lines = {}
    local progress = quest.progress or {}
    for _, objective in ipairs(progress.objectives or {}) do
        local objectiveText = objective.text or ""
        if objective.type ~= "event" and type(objective.current) == "number" and type(objective.required) == "number"
            and not objectiveText:find("%d+%s*/%s*%d+") then
            objectiveText = string.format(MS.L.JOURNEY_CONTEXT_OBJECTIVE_COUNTS,
                objective.current, objective.required, objectiveText)
        end
        local line = string.format(objective.finished and MS.L.JOURNEY_CONTEXT_OBJECTIVE_DONE
            or MS.L.JOURNEY_CONTEXT_OBJECTIVE_OPEN, objectiveText)
        lines[#lines + 1] = objective.finished and Style:CompletedObjective(line) or line
    end
    local remembered = MS.JourneyMemory and MS.JourneyMemory:GetQuest(quest.questID)
    if remembered and MS.JourneyProgressionView then
        lines[#lines + 1] = string.format(MS.L.JOURNEY_MEMORY_QUEST_BEFORE,
            MS.JourneyProgressionView:DateLabel(remembered.lastTurnedInAt))
    end
    self:Present("QUEST", quest.title or MS.L.JOURNEY_QUEST_DETAILS, lines,
        quest.questID, contextMapID, meta, progress.percent,
        #(progress.objectives or {}), quest.description)
end

function Panel:IsLocalMap(mapInfo)
    if not mapInfo then return false end
    local types = _G.Enum and Enum.UIMapType or {}
    local kind = mapInfo.mapType
    if kind == (types.Zone or 3) or kind == (types.Dungeon or 4) then return true end
    return kind == (types.Micro or 5) and MS.JourneyMapData:LocalZone(mapInfo.mapID) ~= nil
end

function Panel:Sync(quests, mapInfo)
    self.memoryDirty = nil
    local context = self.selectedContext
    local mapID = mapInfo and mapInfo.mapID
    self.lastMapID = mapID
    if context.type == "QUEST" then
        local quest = quests and quests.byID and quests.byID[context.questID]
        if not quest then
            for _, pin in ipairs(quests and quests.pins or {}) do
                if pin.questID == context.questID then
                    quest = pin.quest or { questID = pin.questID, title = pin.title or MS.L.JOURNEY_QUEST_DETAILS,
                        state = pin.state, mapID = self.lastMapID, mapName = mapInfo and mapInfo.name }
                    break
                end
            end
        end
        if quest then self:SelectQuest(quest); return end
        self.questRecord = nil
    end
    if not self:IsLocalMap(mapInfo) then
        self.zoneQuests, self.zoneInfo = nil, nil
        return self:Present("EMPTY", "", {}, nil, nil, "")
    end
    local zoneID = MS.JourneyMapData:LocalZone(mapInfo.mapID)
    if zoneID then mapInfo = MS.JourneyMapData:Info(zoneID) end
    self.zoneQuests, self.zoneInfo = quests, mapInfo
    local lines, playerHere, summary = self:ZoneStory(mapInfo.mapID, quests)
    if self.lastZoneID ~= mapInfo.mapID then self.zoneExpanded, self.lastZoneID = false, mapInfo.mapID end
    self.zoneSummary = summary
    self:Present("ZONE", mapInfo.name, lines, nil, mapInfo.mapID, playerHere and MS.L.JOURNEY_ZONE_PLAYER_HERE or "")
end

-- The zone told as a few sentences: only what Journey remembers and the live quest log,
-- never counters, invented history or lore. Returns the lines, whether the player is here and
-- a one-line summary for the folded card.
function Panel:ZoneStory(zoneID, quests)
    local L, lines, summary = MS.L, {}, {}
    local function Add(key, value) lines[#lines + 1] = value and string.format(L[key], value) or L[key] end
    local memory = MS.JourneyMemory
    local data = memory and memory.data
    local playerHere = MS.JourneyMapData:PlayerZone() == zoneID
    if data then
        local remembered = memory:GetZone(zoneID)
        local open = data.openSession
        if not remembered then
            Add(playerHere and "JOURNEY_ZONE_DISCOVERING" or "JOURNEY_ZONE_NO_MEMORY")
        elseif playerHere and remembered.visits == 1 and open and remembered.firstVisitedAt >= open.startedAt then
            -- First arrival during this session: the opening of a chapter, nothing more to say yet.
            Add("JOURNEY_ZONE_NEW_REGION")
        else
            Add(playerHere and "JOURNEY_ZONE_KNOWN" or "JOURNEY_ZONE_TRAVELLED")
            if remembered.firstVisitedLevel then
                Add("JOURNEY_ZONE_FIRST_MEMORY_LEVEL", remembered.firstVisitedLevel)
                summary[#summary + 1] = string.format(L.JOURNEY_ZONE_SUMMARY_LEVEL, remembered.firstVisitedLevel)
            end
            -- While the player is here, lastVisitedAt is the current arrival, not a previous visit.
            local view = MS.JourneyProgressionView
            if not playerHere and view then
                local days = view:DaysSince(remembered.lastVisitedAt)
                if days == 0 then Add("JOURNEY_ZONE_LAST_TODAY")
                elseif days == 1 then Add("JOURNEY_ZONE_LAST_YESTERDAY")
                elseif days and days > 1 and days <= 30 then Add("JOURNEY_ZONE_LAST_DAYS", days)
                else
                    local label = view:DateLabel(remembered.lastVisitedAt)
                    if label ~= L.JOURNEY_MEMORY_DATE_UNKNOWN then Add("JOURNEY_ZONE_LAST_DATE", label) end
                end
            end
            if remembered.visits >= 2 then Add("JOURNEY_ZONE_VISITS", remembered.visits) end
        end
        local completed = memory:CompletedQuestCount(zoneID) or 0
        if completed == 1 then Add("JOURNEY_ZONE_COMPLETED_ONE")
        elseif completed > 1 then Add("JOURNEY_ZONE_COMPLETED_MANY", completed) end
    end
    -- Live quest log, classified by the same "ici" relation as CARTE and QUÊTES.
    if quests then
        local ready, waiting = 0, 0
        for _, quest in ipairs(quests.here or {}) do
            if quest.state == "READY_TO_TURN_IN" then ready = ready + 1
            elseif quest.state == "IN_PROGRESS" then waiting = waiting + 1 end
        end
        if ready == 1 then Add("JOURNEY_ZONE_READY_ONE") elseif ready > 1 then Add("JOURNEY_ZONE_READY_MANY", ready) end
        if waiting == 1 then Add("JOURNEY_ZONE_WAITING_ONE") elseif waiting > 1 then Add("JOURNEY_ZONE_WAITING_MANY", waiting) end
        if ready + waiting == 0 and playerHere then Add("JOURNEY_ZONE_NOTHING_HERE") end
        if ready > 0 then summary[#summary + 1] = string.format(L[ready == 1 and "JOURNEY_ZONE_SUMMARY_READY_ONE" or "JOURNEY_ZONE_SUMMARY_READY"], ready) end
        if waiting > 0 then summary[#summary + 1] = string.format(L[waiting == 1 and "JOURNEY_ZONE_SUMMARY_WAITING_ONE" or "JOURNEY_ZONE_SUMMARY_WAITING"], waiting) end
    end
    if #summary == 0 then summary[1] = lines[1] end
    return lines, playerHere, table.concat(summary, " · ")
end

function Panel:RefreshMemory()
    if not self.visible then self.memoryDirty = true; self.dirty = true; return end
    if self.selectedContext.type == "QUEST" and self.questRecord then self:SelectQuest(self.questRecord)
    elseif self.selectedContext.type == "ZONE" and self.zoneInfo then self:Sync(self.zoneQuests, self.zoneInfo) end
end

function Panel:SetVisible(visible)
    self.visible = visible == true
    if self.visible and self.memoryDirty then
        self.memoryDirty = nil
        self:RefreshMemory()
    end
    if self.visible then self:Refresh() end
end

function Panel:Refresh()
    if not self.visible or not self.frame or not self.dirty then return end
    self.title:SetText(self.titleText or "")
    self.meta:SetText(self.metaText or "")
    local hasQuest = self.selectedContext.type == "QUEST"
    local glyphInset = hasQuest and 24 or 0
    self.meta:ClearAllPoints(); self.meta:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", glyphInset, -8)
    self.meta:SetWidth(math.max(1, (self.readingWidth or 1) - glyphInset))
    self.stateIcon:SetShown(hasQuest)
    if hasQuest then
        self.stateIcon:ClearAllPoints(); self.stateIcon:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -8)
        Style:QuestStateGlyph(self.stateIcon, self.questRecord and self.questRecord.state or "UNKNOWN")
    end
    local folded = self.mode == "NOTE" and self:IsCompactZone()
    self.body:SetText(folded and (self.zoneSummary or "") or self.bodyText or "")
    local hasProgress = self.selectedContext.type == "QUEST" and type(self.percent) == "number"
        and self.percent > 0 and (self.objectiveCount or 0) > 0
    self.progressLabel:SetShown(hasProgress)
    self.progressTrack:SetShown(hasProgress); self.progressFill:SetShown(hasProgress)
    if hasProgress then
        self.progressLabel:SetText(MS.L.JOURNEY_CONTEXT_PROGRESS .. "  " ..
            string.format(MS.L.JOURNEY_CONTEXT_PERCENT, math.floor(self.percent + .5)))
        self.progressFill:SetWidth(math.max(1, self.progressTrack:GetWidth() *
            math.max(0, math.min(100, self.percent)) / 100))
        self.progressLabel:ClearAllPoints()
        self.progressLabel:SetPoint("TOPLEFT", self.meta, "BOTTOMLEFT", -glyphInset, -16)
        self.progressTrack:ClearAllPoints()
        self.progressTrack:SetPoint("TOPLEFT", self.progressLabel, "BOTTOMLEFT", 0, -8)
    end
    local hasBody = self.bodyText and self.bodyText ~= ""
    local hasObjectives = self.selectedContext.type == "QUEST" and (self.objectiveCount or 0) > 0
    self.body:SetShown(hasBody)
    self.section:SetShown(hasObjectives)
    self.section:SetText(hasObjectives and MS.L.JOURNEY_CONTEXT_OBJECTIVES or "")
    self.section:ClearAllPoints()
    self.section:SetPoint("TOPLEFT", hasProgress and self.progressTrack or self.meta,
        "BOTTOMLEFT", hasProgress and 0 or -glyphInset, -16)
    self.body:ClearAllPoints()
    self.body:SetPoint("TOPLEFT", hasObjectives and self.section or hasProgress and self.progressTrack or self.meta,
        "BOTTOMLEFT", (hasObjectives or hasProgress) and 0 or -glyphInset, hasObjectives and -8 or -16)
    local hasLore = self.mode == "PAGE" and self.selectedContext.type == "QUEST"
        and type(self.loreText) == "string" and self.loreText ~= ""
    self.loreSection:SetShown(hasLore); self.loreBody:SetShown(hasLore)
    if hasLore then
        self.loreSection:SetText(MS.L.JOURNEY_QUEST_NARRATIVE)
        self.loreBody:SetText(self.loreText)
        self.loreSection:ClearAllPoints()
        self.loreSection:SetPoint("TOPLEFT", hasBody and self.body or hasProgress and self.progressTrack or self.meta,
            "BOTTOMLEFT", 0, -24)
        self.loreBody:ClearAllPoints()
        self.loreBody:SetPoint("TOPLEFT", self.loreSection, "BOTTOMLEFT", 0, -8)
    end
    local titleHeight, metaHeight, bodyHeight = self.title:GetStringHeight(), self.meta:GetStringHeight(), self.body:GetStringHeight()
    titleHeight = type(titleHeight) == "number" and titleHeight or 40
    metaHeight = type(metaHeight) == "number" and metaHeight or 20
    bodyHeight = type(bodyHeight) == "number" and bodyHeight or 40
    local loreHeight = hasLore and self.loreBody:GetStringHeight() or 0
    loreHeight = type(loreHeight) == "number" and loreHeight or 0
    self.content:SetHeight(math.max(1, titleHeight + metaHeight + bodyHeight +
        (hasProgress and 48 or 0) + (hasObjectives and 32 or 0) +
        (hasLore and loreHeight + 50 or 0) + (self.mode == "PAGE" and 90 or 46)))
    local view = MS.JourneyWorkspace.view
    local hasAction = self.selectedContext.type == "QUEST" and
        ((view == "QUESTS" and self:QuestMapID() ~= nil) or
        (view == "MAP" and (MS.JourneyQuestData.latestByID or {})[self.selectedContext.questID] ~= nil))
    self.questAction:SetShown(hasAction)
    self.mapActionKind = nil
    if hasAction then
        local action = self:MapAction()
        -- One player-facing label; POINT vs REGION stays an internal targeting decision.
        self.mapActionKind = action
        self.questAction.label:SetText(MS.L[view == "QUESTS" and "JOURNEY_QUEST_SHOW_MAP" or "JOURNEY_QUEST_OPEN_JOURNAL"])
        self.questAction:ClearAllPoints()
        self.questAction:SetPoint("TOPLEFT", hasLore and self.loreBody or hasBody and self.body or
            hasProgress and self.progressTrack or self.meta, "BOTTOMLEFT", (hasLore or hasBody or hasProgress) and 0 or -glyphInset, -16)
        self.content:SetHeight(self.content:GetHeight() + 46)
    end
    local social = hasQuest and self.questRecord and MS.JourneyQuestActions
        and MS.JourneyQuestActions:DetailAction(self.questRecord) or nil
    self.socialActionSpec = social
    self.socialAction:SetShown(social ~= nil)
    if social then
        self.socialAction.label:SetText(social.label)
        self.socialAction:ClearAllPoints()
        if hasAction then
            self.socialAction:SetPoint("TOPLEFT", self.questAction, "BOTTOMLEFT", 0, -8)
            self.content:SetHeight(self.content:GetHeight() + 36)
        else
            self.socialAction:SetPoint("TOPLEFT", hasLore and self.loreBody or hasBody and self.body or
                hasProgress and self.progressTrack or self.meta, "BOTTOMLEFT", (hasLore or hasBody or hasProgress) and 0 or -glyphInset, -16)
            self.content:SetHeight(self.content:GetHeight() + 46)
        end
    end
    local zoneLink = self.mode == "NOTE" and self.selectedContext.type == "ZONE"
    self.zoneToggle:SetShown(zoneLink)
    if zoneLink then
        self.zoneToggle.label:SetText(MS.L[folded and "JOURNEY_ZONE_READ" or "JOURNEY_ZONE_FOLD"])
        local width = self.zoneToggle.label:GetStringWidth()
        self.zoneToggle:SetSize(math.max(40, (type(width) == "number" and width or 120) + 4), 20)
        self.zoneToggle:ClearAllPoints()
        self.zoneToggle:SetPoint("TOPLEFT", hasBody and self.body or self.meta, "BOTTOMLEFT", 0, -6)
        self.content:SetHeight(self.content:GetHeight() + 10)
        if folded then
            local function Height(label, fallback)
                local value = label:GetStringHeight()
                return type(value) == "number" and value > 0 and value or fallback
            end
            -- Same offsets as the anchors above, plus the frame's 6-unit insets.
            self.compactMeasured = math.ceil(9 + Height(self.title, 22) + 8 + Height(self.meta, 14) + 16
                + Height(self.body, 16) + 6 + 20 + 10 + 12)
        end
    end
    local page = self.mode == "PAGE" and hasQuest
    self.readingPaper:SetShown(page); self.readingEdge:SetShown(page)
    if page then
        self.readingPaper:ClearAllPoints()
        local padding = math.min(16, self.readingInset)
        self.readingPaper:SetPoint("TOPLEFT", self.content, "TOPLEFT", self.readingInset - padding, -18)
        self.readingPaper:SetSize(self.readingWidth + padding * 2, math.max(1, self.content:GetHeight() - 18))
        self.readingEdge:ClearAllPoints()
        self.readingEdge:SetPoint("TOPLEFT", self.readingPaper, "TOPLEFT")
        self.readingEdge:SetSize(2, self.readingPaper:GetHeight())
    end
    self.objectivePaper:SetShown(page and hasObjectives)
    if page and hasObjectives then
        self.objectivePaper:ClearAllPoints()
        local padding = math.min(10, self.readingInset)
        self.objectivePaper:SetPoint("TOPLEFT", self.section, "TOPLEFT", -padding, 8)
        self.objectivePaper:SetSize(self.readingWidth + padding * 2, bodyHeight + (self.section:GetStringHeight() or 20) + 24)
    end
    self.questAction:SetWidth(math.min(210, self.readingWidth or 210))
    self.socialAction:SetWidth(math.min(210, self.readingWidth or 210))
    self.refreshCount, self.dirty = self.refreshCount + 1, false
end

function Panel:RunSocialAction()
    local action = self.socialActionSpec
    if not action or self.selectedContext.type ~= "QUEST" then return nil end
    return action.run()
end

function Panel:GetStatus()
    return { type = self.selectedContext.type, questID = self.selectedContext.questID,
        refreshCount = self.refreshCount, descriptionSupport = MS.JourneyQuestData.descriptionSupport or self.descriptionSupport }
end
