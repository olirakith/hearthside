local MS = _G.MS
MS.JourneyInventoryData = { active = false, supported = false, trackedLimit = 20,
    items = {}, bags = {}, owned = {}, finds = {}, pending = {}, requested = {},
    usedSlots = 0, totalSlots = 0, freeSlots = 0, itemCount = 0,
    questItemCount = 0, lastBagEvent = "none" }
local Data = MS.JourneyInventoryData

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q end
end
local function ValidID(id) return type(id) == "number" and id > 0 and id < 2147483647 and id % 1 == 0 end
local function ValidTarget(value)
    return type(value) == "number" and value > 0 and value < 2147483647 and value % 1 == 0
end
local function Key()
    return MS.JourneyCharacterIdentity:Resolve().key
end
local function Count(id, bank)
    return Call(C_Item and C_Item.GetItemCount, id, bank == true, false, false, false)
end

function Data:Bind(db)
    if not db then db = MS.Database:Get() end
    db.journey = type(db.journey) == "table" and db.journey or {}
    local root = type(db.journey.inventory) == "table" and db.journey.inventory or {}
    root.characters = type(root.characters) == "table" and root.characters or {}
    db.journey.inventory = root
    self.identityMigration = MS.JourneyCharacterIdentity:MigrateCharacters(root.characters,
        MS.JourneyCharacterIdentity:Resolve())
    MS.JourneyCharacterIdentity:WarnConflict("INVENTORY", self.identityMigration)
    if self.identityMigration.status == "CONFLICT" then self.tracked = {}; self.characterKey = nil; return end
    local key = Key()
    if not key then self.tracked = {}; self.characterKey = nil; return end
    local character = type(root.characters[key]) == "table" and root.characters[key] or {}
    local source = type(character.trackedItems) == "table" and character.trackedItems or {}
    local clean, count = {}, 0
    for rawID, entry in pairs(source) do
        local id = tonumber(rawID)
        if ValidID(id) and type(entry) == "table" and count < self.trackedLimit then
            clean[id] = { trackedAt = type(entry.trackedAt) == "number" and entry.trackedAt or 0 }
            if ValidTarget(entry.targetCount) then clean[id].targetCount = entry.targetCount end
            count = count + 1
        end
    end
    character.trackedItems = clean
    root.characters[key] = character
    self.tracked, self.characterKey = clean, key
end
function Data:TrackedCount()
    local count = 0
    for _ in pairs(self.tracked or {}) do count = count + 1 end
    return count
end
function Data:Track(id)
    if not ValidID(id) then return nil, "INVALID_ITEM" end
    if not self.tracked then self:Bind() end
    if self.tracked[id] then return true end
    if self:TrackedCount() >= self.trackedLimit then return nil, "LIMIT" end
    self.tracked[id] = { trackedAt = type(time) == "function" and time() or 0 }
    self:EnsureItem(id)
    self:Changed()
    return true
end
function Data:SetTarget(id, target)
    if not self.tracked or not self.tracked[id] then return nil, "NOT_TRACKED" end
    if target ~= nil and not ValidTarget(target) then return nil, "INVALID_TARGET" end
    self.tracked[id].targetCount = target
    self:Changed()
    return true
end
function Data:Untrack(id)
    if not self.tracked or not self.tracked[id] then return nil end
    self.tracked[id] = nil
    self:Changed()
    return true
end
function Data:Changed()
    if MS.InventoryView then MS.InventoryView:ScheduleRefresh() end
end

function Data:Classify(item)
    local class = item.classID
    local enum = Enum and Enum.ItemClass or {}
    if item.isQuestItem or class == (enum.Questitem or 12) then return "QUEST" end
    if class == (enum.Recipe or 9) then return "RECIPE" end
    if class == (enum.Consumable or 0) then return "CONSUMABLE" end
    if item.isCraftingReagent or class == (enum.Reagent or 5) or class == (enum.Tradegoods or 7) then return "CRAFTING" end
    if class == (enum.Weapon or 2) or class == (enum.Armor or 4) then return "EQUIPMENT" end
    return "OTHER"
end
function Data:EnsureItem(id)
    if not ValidID(id) then return nil end
    local item = self.items[id] or { id = id, count = 0 }
    self.items[id] = item
    local cached = Call(C_Item and C_Item.IsItemDataCachedByID, id)
    local name = Call(C_Item and C_Item.GetItemNameByID, id)
    local icon = Call(C_Item and C_Item.GetItemIconByID, id)
    if name then item.name = name end
    if icon then item.icon = icon end
    local _, _, _, equipLoc, instantIcon, classID, subclassID =
        Call(C_Item and C_Item.GetItemInfoInstant, id)
    item.classID, item.subclassID = classID or item.classID, subclassID or item.subclassID
    item.equipLoc, item.icon = equipLoc or item.equipLoc, item.icon or instantIcon
    if cached ~= false then
        local fullName, _, quality, _, _, _, _, _, fullEquip, texture, sellPrice,
            fullClass, fullSubclass, _, _, _, reagent = Call(C_Item and C_Item.GetItemInfo, id)
        item.name, item.quality = fullName or item.name, quality or item.quality
        item.equipLoc, item.icon = fullEquip or item.equipLoc, texture or item.icon
        item.classID, item.subclassID = fullClass or item.classID, fullSubclass or item.subclassID
        item.sellPrice, item.isCraftingReagent = sellPrice, reagent
    end
    if cached == false and not self.requested[id] then
        self.requested[id], self.pending[id] = true, true
        Call(C_Item and C_Item.RequestLoadItemDataByID, id)
    elseif cached then self.pending[id] = nil end
    item.category = self:Classify(item)
    return item
end

-- Complete snapshots only: an unreadable carried bag must not turn into a fictitious loss.
function Data:Scan()
    if not self.supported then return nil end
    local items, bags, total, free = {}, {}, 0, 0
    for bag = 0, 4 do
        local slots = Call(C_Container.GetContainerNumSlots, bag)
        local empty = Call(C_Container.GetContainerNumFreeSlots, bag)
        if type(slots) ~= "number" or type(empty) ~= "number"
            or slots < 0 or empty < 0 or empty > slots then return nil end
        total, free = total + slots, free + empty
        local observedEmpty = 0
        for slot = 1, slots do
            local info = Call(C_Container.GetContainerItemInfo, bag, slot)
            if info then
                if type(info) ~= "table" or not ValidID(info.itemID)
                    or type(info.stackCount) ~= "number" or info.stackCount <= 0 then return nil end
                local id = info.itemID
                bags[id] = (bags[id] or 0) + info.stackCount
                local item = items[id]
                if not item then
                    item = { id = id, count = 0, bag = bag, slot = slot,
                        name = info.itemName, icon = info.iconFileID, quality = info.quality,
                        hasNoValue = info.hasNoValue }
                    items[id] = item
                end
                item.count = item.count + info.stackCount
                local quest = Call(C_Container.GetContainerItemQuestInfo, bag, slot)
                if type(quest) == "table" and quest.isQuestItem then item.isQuestItem = true end
            else observedEmpty = observedEmpty + 1 end
        end
        if observedEmpty ~= empty then return nil end
    end
    self.snapshotCount = (self.snapshotCount or 0) + 1
    return { items = items, bags = bags, total = total, free = free }
end
local function Copy(map)
    local result = {}
    for id, value in pairs(map or {}) do result[id] = value end
    return result
end
function Data:Owned(id)
    local value = Count(id, true)
    if type(value) == "number" then return value end
    return self.owned[id]
end
function Data:Bags(id)
    local value = Count(id, false)
    if type(value) == "number" then return value end
    return self.bags[id] or 0
end
function Data:SnapshotOwned(bags, previous)
    local result = {}
    for id in pairs(bags or {}) do result[id] = self:Owned(id) end
    for id in pairs(previous or {}) do result[id] = self:Owned(id) end
    for id in pairs(self.tracked or {}) do result[id] = self:Owned(id) end
    return result
end
function Data:Apply(scan, allowFinds)
    if not scan then self.lastScanState = "INCOMPLETE"; return end
    self.lastScanState = "COMPLETE"
    local oldBags, oldOwned = self.bags, self.owned
    local owned = self:SnapshotOwned(scan.bags, oldBags)
    local ids = {}
    for id in pairs(oldBags) do ids[id] = true end
    for id in pairs(scan.bags) do ids[id] = true end
    self.lastOwnedDelta = 0
    self.lastDiffItemCount, self.lastPositiveDeltaCount, self.lastNegativeDeltaCount = 0, 0, 0
    self.lastCandidateItemID, self.lastCandidateBagsBefore = nil, nil
    self.lastCandidateBagsAfter, self.lastCandidateOwnedBefore = nil, nil
    self.lastCandidateOwnedAfter = nil
    self.lastCandidateDecision, self.lastCandidateReason = "NONE", "NO_CHANGE"
    if self.baseline then
        for id in pairs(ids) do
            local beforeBags, afterBags = oldBags[id] or 0, scan.bags[id] or 0
            local beforeOwned = oldOwned[id]
            -- An item absent from the old bag snapshot starts at zero; an item
            -- already present with an unreadable owned count remains unknown.
            if beforeOwned == nil and oldBags[id] == nil then beforeOwned = 0 end
            local afterOwned = owned[id]
            local bagDelta = afterBags - beforeBags
            local ownedDelta = type(afterOwned) == "number"
                and type(beforeOwned) == "number" and afterOwned - beforeOwned or nil
            if bagDelta ~= 0 or (ownedDelta and ownedDelta ~= 0) then
                self.lastDiffItemCount = self.lastDiffItemCount + 1
                if ownedDelta and ownedDelta > 0 then
                    self.lastPositiveDeltaCount = self.lastPositiveDeltaCount + 1
                elseif ownedDelta and ownedDelta < 0 then
                    self.lastNegativeDeltaCount = self.lastNegativeDeltaCount + 1
                end
                local decision, reason = "SKIPPED", "NON_POSITIVE"
                if not allowFinds then reason = "SUPPRESSED_CONTEXT"
                elseif not ownedDelta then reason = "OWNED_UNAVAILABLE"
                elseif bagDelta > 0 and ownedDelta > 0 and ownedDelta == bagDelta then
                    self.finds[id] = (self.finds[id] or 0) + ownedDelta
                    self.lastFindingItemID = id
                    decision, reason = "RECORDED", "MATCHED_POSITIVE_DELTA"
                elseif bagDelta > 0 and ownedDelta > 0 then reason = "BAG_OWNED_MISMATCH" end
                if not self.lastCandidateItemID or decision == "RECORDED" then
                    self.lastCandidateItemID = id
                    self.lastCandidateBagsBefore, self.lastCandidateBagsAfter = beforeBags, afterBags
                    self.lastCandidateOwnedBefore, self.lastCandidateOwnedAfter = beforeOwned, afterOwned
                    self.lastCandidateDecision, self.lastCandidateReason = decision, reason
                end
            end
            if ownedDelta and ownedDelta ~= 0 then self.lastOwnedDelta = ownedDelta end
        end
    end
    self.bags, self.owned, self.items = scan.bags, owned, scan.items
    self.totalSlots, self.freeSlots = scan.total, scan.free
    self.usedSlots = scan.total - scan.free
    self.itemCount, self.questItemCount = 0, 0
    for id, item in pairs(self.items) do
        self.itemCount = self.itemCount + 1
        self:EnsureItem(id)
        if item.category == "QUEST" then self.questItemCount = self.questItemCount + 1 end
    end
    for id in pairs(self.tracked or {}) do self:EnsureItem(id) end
    self.baseline = true
    self:Changed()
end
function Data:ReadBuyback()
    if type(GetNumBuybackItems) ~= "function" or type(GetBuybackItemLink) ~= "function" then return nil end
    local total = Call(GetNumBuybackItems)
    if type(total) ~= "number" then return nil end
    local result = {}
    for index = 1, total do
        local link = Call(GetBuybackItemLink, index)
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
        if not id then return nil end
        local _, _, _, amount = Call(GetBuybackItemInfo, index)
        result[id] = (result[id] or 0) + (type(amount) == "number" and amount or 1)
    end
    return result
end
function Data:ObserveBuyback()
    local current = self:ReadBuyback()
    if not current then self.buybackKnown = false; return end
    if self.buyback then
        for id, count in pairs(self.buyback) do
            if count > (current[id] or 0) then self.buybackRemoved[id] = true end
        end
    end
    self.buyback = current
end
function Data:OnEvent(event, id, success)
    if not self.active then return end
    if event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
        if ValidID(id) and success ~= false and self.pending[id] then
            self.pending[id] = nil; self:EnsureItem(id); self:Changed()
        end
        return
    end
    self.lastBagEvent = event
    if event == "MERCHANT_SHOW" then
        self.merchantOpen = true; self.merchantBaseline = Copy(self.bags)
        self.merchantOwned = Copy(self.owned); self.buybackRemoved = {}
        self.buyback = self:ReadBuyback(); self.buybackKnown = self.buyback ~= nil
        return
    end
    if event == "MERCHANT_UPDATE" then self:ObserveBuyback(); return end
    if event == "MERCHANT_CLOSED" then
        self.merchantOpen = false
        -- Merchant changes are reconciled only at the close boundary. Unknown buyback
        -- state or a removed buyback entry makes a positive delta ambiguous.
        local scan = self:Scan()
        if scan and self.merchantBaseline and self.buybackKnown then
            local currentOwned = self:SnapshotOwned(scan.bags, self.merchantBaseline)
            for itemID, count in pairs(scan.bags) do
                local bagDelta = count - (self.merchantBaseline[itemID] or 0)
                local beforeOwned = self.merchantOwned[itemID]
                if beforeOwned == nil and self.merchantBaseline[itemID] == nil then
                    beforeOwned = 0
                end
                local ownedDelta = type(currentOwned[itemID]) == "number"
                    and type(beforeOwned) == "number"
                    and currentOwned[itemID] - beforeOwned or 0
                if bagDelta > 0 and ownedDelta > 0 and bagDelta == ownedDelta
                    and not self.buybackRemoved[itemID] then
                    self.finds[itemID] = (self.finds[itemID] or 0) + ownedDelta
                    self.lastFindingItemID = itemID
                end
            end
        end
        self:Apply(scan, false)
        self.merchantBaseline, self.merchantOwned, self.buyback = nil, nil, nil
        self.merchantTail = true
        return
    end
    if event == "BANKFRAME_OPENED" then self.bankOpen = true; return end
    if event == "BANKFRAME_CLOSED" then
        self.bankOpen = false
        self:Apply(self:Scan(), false)
        self.bankTail = true
        return
    end
    if event == "BAG_UPDATE" then
        if type(id) == "number" and id >= 6 then self.bankBagChanged = true end
        return
    end
    if event ~= "BAG_UPDATE_DELAYED" then return end
    self.bagUpdateDelayedCount = (self.bagUpdateDelayedCount or 0) + 1
    if self.merchantOpen then self:ObserveBuyback() end
    local suppress = self.bankOpen or self.merchantOpen or self.bankTail or self.merchantTail
    local scan = self:Scan()
    self:Apply(scan, not suppress)
    if self.bankOpen and not self.bankBagChanged then
        -- The first deposit wave can expose a transient ownedCount. Keep the last
        -- stable progression until the bank container event or close arrives.
        for itemID, value in pairs(self.stableOwned or {}) do
            if type(value) == "number"
                and (self.bags[itemID] or 0) < (self.stableBags[itemID] or 0) then
                self.owned[itemID] = value
            end
        end
    else
        self.stableOwned, self.stableBags = Copy(self.owned), Copy(self.bags)
    end
    self.bankBagChanged = false
    self.bankTail, self.merchantTail = false, false
end
function Data:Start()
    if self.active then return end
    self:Bind()
    self.supported = type(C_Container) == "table"
        and type(C_Container.GetContainerNumSlots) == "function"
        and type(C_Container.GetContainerNumFreeSlots) == "function"
        and type(C_Container.GetContainerItemInfo) == "function"
    self.items, self.bags, self.owned, self.finds = {}, {}, {}, {}
    self.pending, self.requested, self.baseline = {}, {}, false
    self.bankOpen, self.merchantOpen = false, false
    self.bankTail, self.merchantTail, self.bankBagChanged = false, false, false
    self.merchantBaseline, self.merchantOwned, self.buyback = nil, nil, nil
    self.buybackRemoved, self.buybackKnown = {}, false
    self.lastBagEvent = "none"
    self.bagUpdateDelayedCount, self.snapshotCount = 0, 0
    self.lastOwnedDelta, self.lastFindingItemID, self.lastScanState = 0, nil, "NOT_SCANNED"
    self.lastDiffItemCount, self.lastPositiveDeltaCount, self.lastNegativeDeltaCount = 0, 0, 0
    self.lastCandidateDecision, self.lastCandidateReason = "NONE", "NOT_SCANNED"
    self.active = true
    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:SetScript("OnEvent", function(_, event, ...) Data:OnEvent(event, ...) end)
    end
    self.registration = {}
    for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED",
        "BANKFRAME_CLOSED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE",
        "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }) do
        self.registration[event] = pcall(self.eventFrame.RegisterEvent, self.eventFrame, event)
    end
    self:Apply(self:Scan(), false)
    self.stableOwned, self.stableBags = Copy(self.owned), Copy(self.bags)
end
function Data:Stop()
    self.active = false
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
    self.registration = {}
end
function Data:ResetSession()
    if not self.active then return end
    self.finds = {}
    self.lastFindingItemID = nil
    self:Apply(self:Scan(), false)
end
function Data:GetStatus()
    local finds, pending = 0, 0
    for _, count in pairs(self.finds) do if count > 0 then finds = finds + 1 end end
    for _ in pairs(self.pending) do pending = pending + 1 end
    local registered = self.active and self.registration
        and self.registration.BAG_UPDATE_DELAYED == true or false
    if registered and self.eventFrame and type(self.eventFrame.IsEventRegistered) == "function" then
        local ok, actual = pcall(self.eventFrame.IsEventRegistered,
            self.eventFrame, "BAG_UPDATE_DELAYED")
        if ok and type(actual) == "boolean" then registered = actual end
    end
    return { usedSlots = self.usedSlots, totalSlots = self.totalSlots, freeSlots = self.freeSlots,
        itemCount = self.itemCount, questItemCount = self.questItemCount,
        trackedCount = self:TrackedCount(), sessionFindCount = finds,
        pendingItemDataCount = pending, lastBagEvent = self.lastBagEvent,
        merchantDeferred = self.merchantOpen == true,
        active = self.active, bagListenerRegistered = registered,
        bagUpdateDelayedCount = self.bagUpdateDelayedCount or 0,
        snapshotCount = self.snapshotCount or 0,
        lastOwnedDelta = self.lastOwnedDelta or 0,
        lastFindingItemID = self.lastFindingItemID,
        lastScanState = self.lastScanState,
        lastDiffItemCount = self.lastDiffItemCount or 0,
        lastPositiveDeltaCount = self.lastPositiveDeltaCount or 0,
        lastNegativeDeltaCount = self.lastNegativeDeltaCount or 0,
        lastCandidateItemID = self.lastCandidateItemID,
        lastCandidateBagsBefore = self.lastCandidateBagsBefore,
        lastCandidateBagsAfter = self.lastCandidateBagsAfter,
        lastCandidateOwnedBefore = self.lastCandidateOwnedBefore,
        lastCandidateOwnedAfter = self.lastCandidateOwnedAfter,
        lastCandidateDecision = self.lastCandidateDecision,
        lastCandidateReason = self.lastCandidateReason }
end
