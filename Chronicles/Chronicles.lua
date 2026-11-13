local MS = _G.MS

MS.Chronicles = { available = false, storeStatus = "UNINITIALIZED" }
local Chronicles = MS.Chronicles
local events

function Chronicles:Initialize(characterKey)
    self.available, self.characterKey, self.discoveryEngine, self.registry = false, nil, nil, nil
    self.regionEngine, self.rumorEngine, self.notificationQueue = nil, nil, nil
    self.collectionSealEngine = nil
    self.contentReport = nil
    local ok, status, key, state = pcall(function()
        local store = MS.ChroniclesStore
        local result = store:Initialize()
        if result ~= "READY" and result ~= "FIRST_RUN" then return result end
        if store.identityMigration and store.identityMigration.status == "CONFLICT" then
            return "CHARACTER_IDENTITY_CONFLICT"
        end
        local resolved = characterKey or store:ResolveCharacterKey()
        if not resolved then return result end
        local characterState = store:EnsureCharacterState(resolved)
        if MS.ChroniclesRegistry then
            local registry = MS.ChroniclesRegistry:New()
            if MS.ChroniclesElwynnPilotPack then
                self.contentReport = registry:RegisterPack(MS.ChroniclesElwynnPilotPack)
                if not self.contentReport.ok then return "INVALID" end
            end
            local trigger = MS.ChroniclesTriggerEngine
            local engine = MS.ChroniclesDiscoveryEngine
            local adapter = MS.ChroniclesWoWFactAdapter
            if not trigger or not engine or not adapter then return "INVALID" end
            self.registry = registry
            self.discoveryEngine = engine:New(registry, store, trigger, resolved)
            if MS.ChroniclesCollectionSealEngine then
                self.collectionSealEngine = MS.ChroniclesCollectionSealEngine:New(registry, store, resolved)
            end
            if MS.ChroniclesRegionState and MS.ChroniclesRegionEngine and MS.ChroniclesRumorEngine then
                self.regionEngine = MS.ChroniclesRegionEngine:New(registry, store,
                    MS.ChroniclesRegionState, resolved)
                self.rumorEngine = MS.ChroniclesRumorEngine:New(registry, store, trigger,
                    MS.ChroniclesRegionState, resolved)
            end
            if MS.ChroniclesNotificationQueue and MS.ChroniclesPresentationEvents then
                self.notificationQueue = MS.ChroniclesNotificationQueue:New(store, resolved)
                -- Validate before clearing stale presentation, before login facts.
                -- Invalid queues stay intact and cannot disable progression.
                if self.notificationQueue:Count() == nil then
                    self.notificationStatus = "UNAVAILABLE"
                else
                    self.notificationStatus = self.notificationQueue:ClearPresentationQueue()
                        and "READY" or "UNAVAILABLE"
                end
            end
        end
        return store:GetStatus(), resolved, characterState
    end)
    self.storeStatus = ok and status or "INVALID"
    if ok and state then
        self.available, self.characterKey = true, key
        if MS.JourneyWorkspace and MS.JourneyWorkspace.RefreshChroniclesAttention then
            MS.JourneyWorkspace:RefreshChroniclesAttention()
        end
    end
    return self.available
end

function Chronicles:ProcessFact(fact, context, now)
    if not self.available or not self.discoveryEngine then
        return { discovered = {}, status = "UNAVAILABLE" }
    end
    local rumors, regionChanged, regionVisited = {}, false, false
    if self.regionEngine and self.rumorEngine then
        if type(fact) == "table" and fact.type == "ENTER_ZONE" then
            local previous
            local characterState = MS.ChroniclesStore:GetCharacterState(self.characterKey)
            if characterState and type(characterState.regions) == "table" then
                previous = MS.ChroniclesRegionState:GetState(characterState.regions[fact.region])
            end
            local visit = self.regionEngine:MarkVisited(fact.region, now)
            if visit.status == "UNAVAILABLE" or visit.status == "INVALID_STATE" then
                self.available = false
                return { discovered = {}, rumors = {}, status = "UNAVAILABLE" }
            end
            regionChanged = visit.changed
            regionVisited = visit.status == "READY" and visit.changed
                and (previous == "UNKNOWN" or previous == "RUMORED")
        end
        local rumorResult = self.rumorEngine:ProcessFact(fact, context, now)
        if rumorResult.status == "UNAVAILABLE" then
            self.available = false
            return { discovered = {}, rumors = {}, status = "UNAVAILABLE" }
        end
        rumors = rumorResult.rumors
    end
    local result = self.discoveryEngine:ProcessFact(fact, context, now)
    if result.status == "UNAVAILABLE" then self.available = false end
    result.rumors, result.regionChanged = rumors, regionChanged
    result.regionVisited = regionVisited
    if result.status == "READY" and self.collectionSealEngine then
        local progression = self.collectionSealEngine:Reconcile(now)
        result.completed, result.unlocked = progression.completed, progression.unlocked
        result.collectionSealStatus = progression.status
    end
    if self.notificationQueue and MS.ChroniclesPresentationEvents then
        -- Presentation is best effort. A broken queue cannot roll back domain
        -- writes or turn off the discovery pipeline.
        local ok, queueResult = pcall(function()
            local presentation = MS.ChroniclesPresentationEvents:FromFactResult(fact, result, now)
            if #presentation == 0 then return { status = "READY", added = {} } end
            return self.notificationQueue:EnqueueBatch(presentation)
        end)
        self.notificationStatus = ok and queueResult and queueResult.status or "UNAVAILABLE"
    end
    if (result.discovered and #result.discovered > 0
        or result.completed and #result.completed > 0 or result.unlocked and #result.unlocked > 0)
        and MS.JourneyWorkspace
        and MS.JourneyWorkspace.RefreshChroniclesAttention then
        MS.JourneyWorkspace:RefreshChroniclesAttention(true)
    end
    return result
end

function Chronicles:GetCharacterState()
    return self.available and MS.ChroniclesStore:GetCharacterState(self.characterKey) or nil
end

function Chronicles:GetUnreadCount()
    return MS.ChroniclesReadModel:GetUnreadCount(self:GetCharacterState())
end

function Chronicles:GetUnreadChronicles()
    return MS.ChroniclesReadModel:GetUnreadChronicles(self:GetCharacterState(),
        self.registry, GetLocale())
end

function Chronicles:GetRegions()
    return MS.ChroniclesReadModel:GetRegions(self:GetCharacterState(),
        self.registry, GetLocale())
end

function Chronicles:GetChroniclesForRegion(id)
    return MS.ChroniclesReadModel:GetChroniclesForRegion(self:GetCharacterState(),
        self.registry, id, GetLocale())
end

function Chronicles:GetRegionSummary(id)
    return MS.ChroniclesReadModel:GetRegionSummary(self:GetCharacterState(), self.registry, id)
end

function Chronicles:GetCollectionsForRegion(id)
    return MS.ChroniclesReadModel:GetCollections(self:GetCharacterState(), self.registry, id, GetLocale())
end

function Chronicles:GetSealsForRegion(id)
    return MS.ChroniclesReadModel:GetSeals(self:GetCharacterState(), self.registry, id, GetLocale())
end

function Chronicles:GetRegionName(id)
    local region = self.registry and self.registry:GetRegion(id)
    if not region then return MS.L.CHRONICLES_UNKNOWN_REGION end
    local summary = self:GetRegionSummary(id)
    if not summary or not summary.revealName then return MS.L.CHRONICLES_UNKNOWN_REGION end
    return region.names[GetLocale()] or region.names.enUS or region.names.frFR
        or MS.L.CHRONICLES_UNKNOWN_REGION
end

function Chronicles:GetChronicle(id)
    return MS.ChroniclesReadModel:GetChronicle(self:GetCharacterState(),
        self.registry, id, GetLocale())
end

function Chronicles:GetRumorRegion(id)
    local state = self:GetCharacterState()
    local record = state and state.rumors and state.rumors[id]
    local rumor = self.registry and self.registry:GetRumor(id)
    if type(record) ~= "table" or not record.discoveredAt or not rumor then return nil end
    return self:GetRegionSummary(rumor.targetRegion) and rumor.targetRegion or nil
end

function Chronicles:GetVisitedRegion(id)
    local summary = self:GetRegionSummary(id)
    return summary and (summary.state == "VISITED" or summary.state == "EXPLORED")
        and id or nil
end

function Chronicles:MarkChronicleRead(id, now)
    if not self.available then return nil end
    return MS.ChroniclesStore:MarkChronicleRead(self.characterKey, id, now)
end

function Chronicles:OnEvent(event, ...)
    if (event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED")
        and MS.ChroniclesDiscoveryToast then MS.ChroniclesDiscoveryToast:Delay(2) end
    if event == "PLAYER_LOGIN" then
        if MS.Config and MS.Config.chroniclesPaused then self.storeStatus = "PAUSED"; return end
        if not self:Initialize() then return end
        if MS.ChroniclesDiscoveryToast then MS.ChroniclesDiscoveryToast:OnLogin() end
        if not self.discoveryEngine then return end
        for _, name in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP" }) do
            pcall(events.RegisterEvent, events, name)
        end
    end
    if not self.available or not self.discoveryEngine then return end
    local ok, facts = pcall(MS.ChroniclesWoWFactAdapter.FactsForEvent,
        MS.ChroniclesWoWFactAdapter, event, self.registry, ...)
    if not ok then self.available = false; return end
    if event == "PLAYER_LOGIN" then
        local level = MS.ChroniclesWoWFactAdapter:LoginLevelFact()
        if level then facts[#facts + 1] = level end
    end
    for _, fact in ipairs(facts) do
        local clockOK, now = pcall(_G.time)
        if not clockOK then self.available = false; return end
        self:ProcessFact(fact, nil, now)
    end
end

function Chronicles:GetDiagnostic()
    local store = MS.ChroniclesStore
    local ok, schemaVersion, state = pcall(function()
        return store:GetSchemaVersion(), self.characterKey and store:GetCharacterState(self.characterKey)
    end)
    return {
        storeStatus = self.storeStatus,
        schemaVersion = ok and schemaVersion or nil,
        characterKey = self.characterKey,
        identity = store.identity,
        identityMigration = store.identityMigration,
        characterStatePresent = ok and state ~= nil or false,
    }
end

events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, ...)
    Chronicles:OnEvent(event, ...)
end)
