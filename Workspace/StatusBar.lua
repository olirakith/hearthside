local MS = _G.MS

MS.JourneyStatusBar = { active = false, bagFree = nil, bagTotal = nil }
local Bar = MS.JourneyStatusBar

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

-- Native localized slot names (client globals); short enough for the footer.
local SLOT_NAMES = { "HEADSLOT", "NECKSLOT", "SHOULDERSLOT", "SHIRTSLOT", "CHESTSLOT", "WAISTSLOT",
    "LEGSSLOT", "FEETSLOT", "WRISTSLOT", "HANDSSLOT", "FINGER0SLOT", "FINGER1SLOT", "TRINKET0SLOT",
    "TRINKET1SLOT", "BACKSLOT", "MAINHANDSLOT", "SECONDARYHANDSLOT", "RANGEDSLOT", "TABARDSLOT" }
local SHORT_IDENTITY_BYTES = 18
local COIN_ICONS = {
    gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
local CELL_EXTRA = 16

function Bar:Create(parent)
    if self.frame then return end
    self.frame = CreateFrame("Frame", nil, parent)
    self.background = self.frame:CreateTexture(nil, "BACKGROUND")
    self.background:SetAllPoints(self.frame)
    MS.JourneyUIStyle:Color(self.background, "backgroundDeep")
    self.rule = self.frame:CreateTexture(nil, "ARTWORK")
    self.rule:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 5, 0)
    self.rule:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -5, 0)
    self.rule:SetHeight(1)
    MS.JourneyUIStyle:Color(self.rule, "borderMuted")
    self.text = self.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    MS.JourneyUIStyle:Body(self.text, "SMALL", "textSecondary")
    MS.JourneyUIStyle:Text(self.text, "textSecondary")
    self.text:SetPoint("CENTER", self.frame, "CENTER")
    self.text:SetJustifyH("LEFT")
    self.text:SetWordWrap(false); self.text:SetMaxLines(1)
    self.eventLink = CreateFrame("Button", nil, self.frame)
    self.eventLink.label = self.eventLink:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    MS.JourneyUIStyle:Body(self.eventLink.label, "SMALL", "gold")
    self.eventLink.label:SetAllPoints(self.eventLink); self.eventLink.label:SetJustifyH("LEFT")
    self.eventLink.label:SetWordWrap(false); self.eventLink.label:SetMaxLines(1)
    MS.JourneyUIStyle:Link(self.eventLink, self.eventLink.label)
    self.eventLink:SetScript("OnClick", function()
        local journal = MS.JourneySessionJournal
        journal.expanded, journal.dirty = not journal.expanded, true
        MS.JourneyWorkspace:LayoutView(MS.JourneyWorkspace.view)
    end)
    self.frame:EnableMouse(true)
    self.frame:SetScript("OnEnter", function()
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self.frame, "ANCHOR_TOP")
            GameTooltip:AddLine(self.fullText or self.text:GetText(), 1, 1, 1, true)
            if self.durabilityLink then
                GameTooltip:AddLine(string.format(MS.L.JOURNEY_UI_DURABILITY_TOOLTIP,
                    self.durabilityLink, self.durabilityPercentText or ""), 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)
    self.frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

function Bar:Layout(rect)
    local frame = self.frame
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    frame:SetSize(rect.width, rect.height)
    self.fallbackRect = rect
    self:PlaceForView()
    self:Refresh()
end


function Bar:PlaceForView()
    if not self.frame or not self.fallbackRect then return end
    local rect = self.fallbackRect
    self.placement = "FOOTER"
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    self.frame:SetSize(rect.width, rect.height)
    self.eventLink:ClearAllPoints(); self.eventLink:SetPoint("LEFT", self.frame, "LEFT", 12, 0)
    local eventWidth = math.max(1, math.min(380, rect.width * .28))
    self.eventLink:SetSize(eventWidth, math.max(1, rect.height - 4))
    self.eventLink.label:SetWidth(eventWidth)
    self.text:ClearAllPoints(); self.text:SetPoint("RIGHT", self.frame, "RIGHT", -12, 0)
    self.text:SetJustifyH("RIGHT"); self.text:SetJustifyV("MIDDLE")
    self.text:SetWidth(math.max(1, rect.width - eventWidth - 36))
    self.text:SetHeight(math.max(1, rect.height - 4))
    self:RenderText()
end

function Bar:RenderText()
    if not self.text then return end
    local width = self.fallbackRect and self.fallbackRect.width or 1600
    local scale = MS.JourneySettings:Get("textScale")
    local effective = width / scale
    self.responsiveMode = effective >= 1600 and "LARGE" or effective >= 1000 and "BALANCED" or "REDUCED"
    local bags = self.bagText or ""
    if self.responsiveMode ~= "LARGE" and type(self.bagFree) == "number" then
        bags = string.format(MS.L[self.bagFree == 1 and "JOURNEY_UI_BAGS_COMPACT_ONE" or "JOURNEY_UI_BAGS_COMPACT"], self.bagFree, self.bagTotal)
    end
    local parts = { bags, self:DurabilityPart(), self.moneyText or "" }
    if self.responsiveMode == "LARGE" then parts[#parts + 1] = self.hearthText or "" end
    -- The Mentor band owns the evening: no XP / session text while it is up.
    local band = MS.JourneyMentorBand
    local mentor = band and band:IsActive() or false
    self.muted = mentor
    local session = not mentor and self.sessionText or ""
    if self.responsiveMode ~= "REDUCED" then parts[#parts + 1] = session end
    local full = {}
    for _, part in ipairs({ self.capacityText or "", self.travelText or "", session }) do
        if part ~= "" then full[#full + 1] = part end
    end
    self.fullText = table.concat(full, "  ·  ")
    local function join()
        local visible = {}
        for _, part in ipairs(parts) do if part ~= "" then visible[#visible + 1] = part end end
        return table.concat(visible, "  ·  ")
    end
    self.text:SetText(join())
    -- Lower-priority values remain in the tooltip; never wrap into the event.
    if type(self.text.GetStringWidth) == "function" then
        local measured = self.text:GetStringWidth()
        -- A cell gap is wider than the dot it replaces.
        while type(measured) == "number" and measured + (#parts - 1) * CELL_EXTRA > self.text:GetWidth() and #parts > 1 do
            table.remove(parts); self.text:SetText(join()); measured = self.text:GetStringWidth()
        end
    end
    self:RenderCells(parts)
    local journal = MS.JourneySessionJournal
    self.eventLink.label:SetText(journal and journal.latestText and journal.latestText ~= "" and journal.latestText
        or MS.L.JOURNEY_SESSION_JOURNAL_COMPACT)
end

-- One FontString per surviving part, chained right to left with a 1 px separator
-- between neighbours. self.text stays hidden as the joined string / width measure.
function Bar:RenderCells(parts)
    self.cells, self.separators = self.cells or {}, self.separators or {}
    local Style = MS.JourneyUIStyle
    local pad = Style.space.md
    local height = math.max(1, (self.fallbackRect and self.fallbackRect.height or 20) - 8)
    local shown, previous = 0, nil
    -- Chained from the right edge, so the last part is placed first and bags read first.
    for index = #parts, 1, -1 do
        local part = parts[index]
        if part ~= "" then
            shown = shown + 1
            local cell = self.cells[shown]
            if not cell then
                cell = self.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                Style:Body(cell, "SMALL", "textSecondary")
                Style:Text(cell, "textSecondary")
                cell:SetJustifyH("RIGHT"); cell:SetJustifyV("MIDDLE")
                cell:SetWordWrap(false); cell:SetMaxLines(1)
                self.cells[shown] = cell
            end
            cell:SetText(part)
            Style:Text(cell, self.muted and "muted" or "textSecondary")
            cell:ClearAllPoints()
            if previous then
                local sep = self.separators[shown - 1]
                if not sep then
                    sep = self.frame:CreateTexture(nil, "ARTWORK")
                    sep:SetWidth(1)
                    Style:Color(sep, "borderMuted")
                    self.separators[shown - 1] = sep
                end
                sep:ClearAllPoints(); sep:SetPoint("RIGHT", previous, "LEFT", -pad, 0)
                sep:SetHeight(height); sep:Show()
                cell:SetPoint("RIGHT", sep, "LEFT", -pad, 0)
            else
                cell:SetPoint("RIGHT", self.frame, "RIGHT", -pad, 0)
            end
            -- Measured unbounded: a reused cell keeps its old width, and a longer text measured
            -- inside it comes back truncated ("6...", "2 po...").
            local width = type(cell.GetUnboundedStringWidth) == "function" and cell:GetUnboundedStringWidth()
            if type(width) ~= "number" or width <= 0 then
                cell:SetWidth(0)
                width = type(cell.GetStringWidth) == "function" and cell:GetStringWidth()
            end
            cell:SetWidth(type(width) == "number" and width > 0 and math.ceil(width) or 1)
            cell:SetHeight(height); cell:Show()
            previous = cell
        end
    end
    for i = shown + 1, #self.cells do self.cells[i]:Hide() end
    for i = math.max(shown, 1), #self.separators do self.separators[i]:Hide() end
    self.text:Hide()
end

function Bar:RefreshSession()
    local info = MS.JourneySession and MS.JourneySession:GetSummary()
    self.sessionText = nil
    if info then
        local duration = math.max(0, math.floor(info.duration or 0))
        local stamp = string.format("%02d:%02d", math.floor(duration / 3600), math.floor(duration / 60) % 60)
        local percent = info.xpMax and info.xpMax > 0 and math.floor((info.xp or 0) * 100 / info.xpMax) or 0
        self.sessionText = string.format(MS.L.JOURNEY_HEADER_SESSION_XP, stamp, percent)
    end
    self:RenderText()
end

function Bar:MoneyText(money)
    if type(money) ~= "number" or money < 0 then return MS.L.JOURNEY_UNKNOWN end
    money = math.floor(money)
    local native = Call(_G.GetCoinTextureString, money)
    if type(native) == "string" and (native:find("|T", 1, true) or native:find("|A", 1, true)) then return native end
    -- Forever gives no textured string: the coin icons are drawn here, as the bags show them.
    local parts, gold, silver, copper = {}, math.floor(money / 10000), math.floor(money / 100) % 100, money % 100
    for _, unit in ipairs({ { gold, COIN_ICONS.gold }, { silver, COIN_ICONS.silver }, { copper, COIN_ICONS.copper } }) do
        if unit[1] > 0 then parts[#parts + 1] = unit[1] .. unit[2] end
    end
    return #parts > 0 and table.concat(parts, " ") or "0" .. COIN_ICONS.copper
end

function Bar:MinimumDurability()
    local lowest, lowestSlot
    for slot = 1, 19 do
        local current, maximum = Call(_G.GetInventoryItemDurability, slot)
        if type(current) == "number" and type(maximum) == "number" and maximum > 0 then
            local percent = math.max(0, math.min(100, current * 100 / maximum))
            if not lowest or percent < lowest then lowest, lowestSlot = percent, slot end
        end
    end
    return lowest, lowestSlot
end

-- Identity of the slot that already holds the minimum; no extra durability scan.
function Bar:DurabilityIdentity(slot)
    if type(slot) ~= "number" then return nil, nil, nil end
    local icon = Call(_G.GetInventoryItemTexture, "player", slot)
    local link = Call(_G.GetInventoryItemLink, "player", slot)
    local name = SLOT_NAMES[slot] and _G[SLOT_NAMES[slot]]
    if type(name) ~= "string" or name == "" or #name > SHORT_IDENTITY_BYTES then name = nil end
    if not (type(icon) == "number" and icon > 0 or type(icon) == "string" and icon ~= "") then icon = nil end
    if type(link) ~= "string" or link == "" then link = nil end
    return icon, name, link
end

-- Always named, as testers did not recognise an item icon alone: LARGE "Durability <icon> slot %";
-- BALANCED "Durability <icon> %"; REDUCED or no identity "Durability %".
function Bar:DurabilityPart()
    local percent = self.durabilityPercentText
    if not percent then return self.durabilityText or "" end
    local icon = self.durabilityIcon and string.format("|T%s:0|t", tostring(self.durabilityIcon))
    if self.responsiveMode == "LARGE" and self.durabilityName then
        return string.format(MS.L.JOURNEY_UI_DURABILITY, string.format(MS.L.JOURNEY_UI_DURABILITY_ITEM,
            icon and icon .. " " .. self.durabilityName or self.durabilityName, percent))
    end
    if self.responsiveMode ~= "REDUCED" and icon then
        return string.format(MS.L.JOURNEY_UI_DURABILITY, string.format(MS.L.JOURNEY_UI_DURABILITY_ITEM, icon, percent))
    end
    return self.durabilityText or ""
end

function Bar:Refresh()
    local container = type(C_Container) == "table" and C_Container or nil
    local slots = container and container.GetContainerNumSlots or _G.GetContainerNumSlots
    local free = container and container.GetContainerNumFreeSlots or _G.GetContainerNumFreeSlots
    self.bagFree, self.bagTotal = nil, nil
    if type(slots) == "function" and type(free) == "function" then
        local freeCount, totalCount = 0, 0
        for bag = 0, 4 do
            local total, empty = Call(slots, bag), Call(free, bag)
            if type(total) ~= "number" or type(empty) ~= "number" then freeCount = nil; break end
            totalCount, freeCount = totalCount + total, freeCount + empty
        end
        if freeCount then self.bagFree, self.bagTotal = freeCount, totalCount end
    end
    local durability, slot = self:MinimumDurability()
    self.durabilityPercent, self.durabilitySlot = durability, slot
    self.durabilityIcon, self.durabilityName, self.durabilityLink = self:DurabilityIdentity(slot)
    self.durabilityState = durability and (durability == 0 and "critical" or durability < 25 and "warning" or "textSecondary") or "textSecondary"
    local durabilityText = durability and string.format("%d%%", math.floor(durability)) or MS.L.JOURNEY_UNKNOWN
    if durability and durability < 25 then
        local c = MS.JourneyUIStyle.colors[self.durabilityState]
        durabilityText = string.format("|cff%02x%02x%02x%s|r", math.floor(c[1]*255), math.floor(c[2]*255), math.floor(c[3]*255), durabilityText)
    end
    self.bagText = type(self.bagFree) == "number" and string.format(
        MS.L[self.bagFree == 1 and "JOURNEY_UI_BAGS_ONE" or "JOURNEY_UI_BAGS"],
        self.bagFree, self.bagTotal) or MS.L.JOURNEY_UI_BAGS_UNKNOWN
    self.durabilityText = string.format(MS.L.JOURNEY_UI_DURABILITY, durabilityText)
    self.durabilityPercentText = durability and durabilityText or nil
    -- Streamer mode: the gold and the hearthstone inn are the player's own business.
    local hidden = MS.BroadcastMode ~= nil and MS.BroadcastMode:IsOn()
    self.moneyText = hidden and "" or self:MoneyText(Call(_G.GetMoney))
    self.hearthText = hidden and "" or string.format(MS.L.JOURNEY_UI_HEARTH, Call(_G.GetBindLocation) or MS.L.JOURNEY_UNKNOWN)
    self.capacityText = self.bagText .. "  ·  " .. self.durabilityText
    self.travelText = hidden and "" or self.moneyText .. "  ·  " .. self.hearthText
    self:RefreshSession()
end

function Bar:Start()
    if self.active then return end
    self.active = true
    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:SetScript("OnEvent", function() Bar:Refresh() end)
    end
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "BAG_UPDATE", "PLAYER_MONEY",
        "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "HEARTHSTONE_BOUND" }) do
        pcall(self.eventFrame.RegisterEvent, self.eventFrame, event)
    end
    self:Refresh()
end

function Bar:Stop()
    self.active = false
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
end

if MS.BroadcastMode then
    MS.BroadcastMode:Listen(function()
        if Bar.active then pcall(Bar.Refresh, Bar) end
    end)
end
