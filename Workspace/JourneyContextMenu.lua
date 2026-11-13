local MS = _G.MS
-- One right-click menu for Journey surfaces (quests today; memories, places, familiar names
-- later). It imitates the native menu ergonomics without using Blizzard menus: a non-secure
-- frame on the WORKSPACE frame, clamped inside it, one at a time, closed by a choice, a click
-- elsewhere, Esc or the workspace going away. Nothing is saved; a reload leaves nothing behind.
MS.JourneyContextMenu = { minWidth = 184, maxWidth = 320, itemHeight = 24, titleHeight = 24, padding = 6,
    margin = 8, maxItems = 8, frameName = "HearthsideContextMenu" }
local Menu = MS.JourneyContextMenu

-- Pure placement in WORKSPACE-local coordinates (origin bottom-left, y up). The menu's top-left
-- corner opens at the cursor, flips left or up when it would cross an edge, then is clamped so
-- the whole menu stays inside the bounds. Returns nil when the menu cannot fit at all.
function Menu.Place(x, y, width, height, boundsWidth, boundsHeight, margin)
    margin = margin or 0
    if width > boundsWidth - 2 * margin or height > boundsHeight - 2 * margin then return nil end
    local left, top = x + 2, y - 2
    if left + width > boundsWidth - margin then left = x - width - 2 end
    if top - height < margin then top = y + height + 2 end
    left = math.max(margin, math.min(left, boundsWidth - margin - width))
    top = math.min(boundsHeight - margin, math.max(top, margin + height))
    return left, top
end

local function Number(value) return type(value) == "number" and value == value and value or nil end

function Menu:Surface()
    local workspace = MS.Workspace
    local journey = MS.JourneyWorkspace
    if not workspace or not workspace.frame or not workspace.frame:IsShown() then return nil end
    if journey and journey.active == false then return nil end
    return workspace.frame
end

-- Cursor in the surface's own coordinates, or nil when the client cannot say.
function Menu:CursorPoint(surface)
    if type(_G.GetCursorPosition) ~= "function" then return nil end
    local ok, x, y = pcall(_G.GetCursorPosition)
    local scale = Number(surface:GetEffectiveScale())
    local left, bottom = Number(surface:GetLeft()), Number(surface:GetBottom())
    x, y = ok and Number(x), ok and Number(y)
    if not x or not y or not scale or scale <= 0 or not left or not bottom then return nil end
    return x / scale - left, y / scale - bottom
end

local function Style() return MS.JourneyUIStyle end

local function Shadow(label)
    if type(label.SetShadowOffset) == "function" then label:SetShadowOffset(1, -1) end
    if type(label.SetShadowColor) == "function" then label:SetShadowColor(0, 0, 0, .9) end
end

local function Label(parent, token, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local style = Style()
    if style then style:Body(label, token, color) end
    Shadow(label)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end

-- Hover: a raised row, a gold mark on its left edge and gold words.
local function Paint(item, hovered)
    item.hover:SetShown(hovered)
    item.accent:SetShown(hovered)
    local style = Style()
    if style then style:Text(item.label, hovered and "gold" or "textPrimary") end
    Shadow(item.label)
end

function Menu:Create(surface)
    if self.frame then
        if self.frame:GetParent() ~= surface then
            self.frame:SetParent(surface)
            self.catcher:SetParent(surface)
            self.catcher:SetAllPoints(surface)
        end
        return
    end
    local frame = CreateFrame("Frame", self.frameName, surface)
    frame:Hide()
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    -- Esc closes the menu the way it closes native panels (same mechanism as onboarding).
    if type(_G.UISpecialFrames) == "table" then table.insert(_G.UISpecialFrames, self.frameName) end
    local style = Style()
    -- Distinct from the page under it but quieter than the moment card: shadow, no halo.
    self.reach = style and style.Elevate and style:Elevate(frame, 3, false) or 0
    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetAllPoints(frame)
    frame.background = frame:CreateTexture(nil, "BORDER")
    frame.background:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.title = Label(frame, "SMALL", "textSecondary")
    frame.rule = frame:CreateTexture(nil, "ARTWORK")
    frame.rule:SetHeight(1)
    if style then
        style:Color(frame.border, "borderActive")
        style:Color(frame.background, "overlay")
        style:Color(frame.rule, "borderMuted")
    end
    frame:SetScript("OnHide", function() Menu:Close("HIDDEN") end)
    frame.items = {}
    self.frame = frame
    -- Fallback when the client has no GLOBAL_MOUSE_DOWN: a transparent WORKSPACE-wide catcher
    -- under the menu. It swallows that one click; the GAME side then cannot close the menu.
    self.catcher = CreateFrame("Button", nil, surface)
    self.catcher:Hide()
    self.catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    self.catcher:SetAllPoints(surface)
    self.catcher:RegisterForClicks("AnyDown")
    self.catcher:SetScript("OnClick", function() Menu:Close("OUTSIDE") end)
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event) Menu:OnEvent(event) end)
end

local function InCombat()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
end

-- An action may carry a slash command the game refuses from addon code (/who on Forever). Out
-- of combat, an invisible action button lies over its row and runs the command as the player's
-- own on the click. InsecureActionButtonTemplate is the addon variant: not protected, so it can
-- sit inside the menu like any row. In combat (actions refused) the row's run() is used.
function Menu:ActionButton()
    if self.actionButton ~= nil then return self.actionButton or nil end
    local ok, button = pcall(CreateFrame, "Button", nil, self.frame, "InsecureActionButtonTemplate")
    if not ok or not button then
        self.actionButton, self.actionState = false, "NO_TEMPLATE"
        return nil
    end
    button:Hide()
    button:SetAttribute("type", "macro")
    button:HookScript("OnEnter", function() if Menu.actionItem then Paint(Menu.actionItem, true) end end)
    button:HookScript("OnLeave", function() if Menu.actionItem then Paint(Menu.actionItem, false) end end)
    button:SetScript("PostClick", function() Menu:Close("SELECTED") end)
    -- Combat coming: close before the command could be refused.
    self.combatGuard = CreateFrame("Frame")
    self.combatGuard:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.combatGuard:SetScript("OnEvent", function() Menu:Close("COMBAT") end)
    self.actionButton = button
    return button
end

function Menu:PlaceAction(item, macro)
    if InCombat() then self.actionState = "COMBAT"; return false end
    local button = self:ActionButton()
    if not button then return false end
    -- The game runs action buttons on press or on release, as the player set it.
    local onDown = type(_G.GetCVarBool) == "function" and _G.GetCVarBool("ActionButtonUseKeyDown") == true
    button:RegisterForClicks(onDown and "LeftButtonDown" or "LeftButtonUp")
    button:SetAttribute("macrotext", macro)
    button:ClearAllPoints()
    button:SetAllPoints(item)
    button:SetFrameLevel((Number(item:GetFrameLevel()) or 1) + 5)
    button:Show()
    self.actionItem, self.actionState = item, onDown and "PLACED_DOWN" or "PLACED_UP"
    return true
end

function Menu:HideAction()
    local button = self.actionButton
    self.actionItem = nil
    if not button then return end
    button:Hide()
    button:SetAttribute("macrotext", nil)
end

function Menu:Item(index)
    local item = self.frame.items[index]
    if item then return item end
    item = CreateFrame("Button", nil, self.frame)
    item:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    item.hover = item:CreateTexture(nil, "ARTWORK")
    item.hover:SetAllPoints(item)
    item.hover:Hide()
    item.accent = item:CreateTexture(nil, "ARTWORK", nil, 1)
    item.accent:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
    item.accent:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, 0)
    item.accent:SetWidth(2)
    item.accent:Hide()
    item.label = Label(item, "BODY", "textPrimary")
    item.label:SetPoint("LEFT", item, "LEFT", 10, 0)
    item.label:SetPoint("RIGHT", item, "RIGHT", -10, 0)
    local style = Style()
    if style then style:Color(item.hover, "overlayHover"); style:Color(item.accent, "gold") end
    item:SetScript("OnEnter", function(button) Paint(button, true) end)
    item:SetScript("OnLeave", function(button) Paint(button, false) end)
    item:SetScript("OnClick", function(button) Menu:Choose(button.index) end)
    self.frame.items[index] = item
    return item
end

-- spec: { owner = "QUEST" | ..., title = optional text, actions = { { label, run } ... } }.
-- Returns true, or false and a reason ("NO_SURFACE", "NO_ACTIONS", "NO_SPACE").
function Menu:Open(spec)
    local actions = {}
    for _, action in ipairs(type(spec) == "table" and spec.actions or {}) do
        if type(action.label) == "string" and action.label ~= "" and type(action.run) == "function" and #actions < self.maxItems then
            actions[#actions + 1] = action
        end
    end
    if #actions == 0 then return false, "NO_ACTIONS" end
    local surface = self:Surface()
    if not surface then return false, "NO_SURFACE" end
    self:Close("REPLACED")
    self:Create(surface)
    local frame, pad = self.frame, self.padding
    local title = type(spec.title) == "string" and spec.title ~= "" and spec.title or nil
    frame.title:SetShown(title ~= nil)
    frame.rule:SetShown(title ~= nil)
    frame.title:SetText(title or "")
    local width = self.minWidth
    for index, action in ipairs(actions) do
        local item = self:Item(index)
        item.index = index
        item.label:SetText(action.label)
        Paint(item, false)
        width = math.max(width, (Number(item.label:GetStringWidth()) or 0) + 20 + pad * 2)
    end
    if title then width = math.max(width, math.min(self.maxWidth, (Number(frame.title:GetStringWidth()) or 0) + 20)) end
    width = math.min(self.maxWidth, math.ceil(width))
    local y = pad
    if title then
        frame.title:ClearAllPoints()
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", pad + 10, -y - 4)
        frame.title:SetWidth(width - pad * 2 - 20)
        y = y + self.titleHeight
        frame.rule:ClearAllPoints()
        frame.rule:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -y + 2)
        frame.rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -y + 2)
    end
    for index, item in ipairs(frame.items) do
        if index <= #actions then
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -y)
            item:SetSize(width - pad * 2, self.itemHeight)
            item:Show()
            y = y + self.itemHeight
        else
            item:Hide()
        end
    end
    local height = y + pad
    frame:SetSize(width, height)
    local boundsWidth, boundsHeight = Number(surface:GetWidth()) or width, Number(surface:GetHeight()) or height
    local x, cursorY = self:CursorPoint(surface)
    if not x then x, cursorY = boundsWidth / 2, boundsHeight / 2 end
    -- The shadow counts: it never spills out of WORKSPACE either.
    local left, top = self.Place(x, cursorY, width, height, boundsWidth, boundsHeight, math.max(self.margin, self.reach or 0))
    -- Never shown partly outside WORKSPACE: a menu that cannot fit does not open.
    if not left then return false, "NO_SPACE" end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", surface, "BOTTOMLEFT", left, top)
    self.spec, self.actions = spec, actions
    self.placement = { left = left, top = top, width = width, height = height, boundsWidth = boundsWidth, boundsHeight = boundsHeight }
    frame:Show()
    frame:Raise()
    self.actionUsed = false
    for index, action in ipairs(actions) do
        if type(action.macro) == "string" and action.macro ~= "" then
            self.actionUsed = self:PlaceAction(frame.items[index], action.macro)
            break
        end
    end
    -- A click anywhere else closes the menu (and still reaches what was clicked).
    self.outside = pcall(self.events.RegisterEvent, self.events, "GLOBAL_MOUSE_DOWN") and "GLOBAL_MOUSE_DOWN" or "CATCHER"
    if self.outside == "CATCHER" then
        self.catcher:SetFrameLevel(math.max(1, (Number(frame:GetFrameLevel()) or 2) - 1))
        self.catcher:Show()
    end
    self.opened = (self.opened or 0) + 1
    return true
end

function Menu:OnEvent(event)
    if event == "GLOBAL_MOUSE_DOWN" and self.spec and self.frame and not self.frame:IsMouseOver() then
        self:Close("OUTSIDE")
    end
end

function Menu:Choose(index)
    local action = self.actions and self.actions[index]
    if not action or not self.spec then return end
    -- Closed before the action runs: a failing action never leaves a menu behind.
    self:Close("SELECTED")
    local ok, failure = pcall(action.run)
    if not ok then self.lastError = tostring(failure) end
end

function Menu:Close(reason)
    if not self.spec then return end
    self.spec, self.actions, self.lastClose = nil, nil, reason
    self:HideAction()
    if self.events then self.events:UnregisterAllEvents() end
    if self.catcher then self.catcher:Hide() end
    if self.frame then self.frame:Hide() end
end

function Menu:IsOpen(owner)
    return self.spec ~= nil and (owner == nil or self.spec.owner == owner)
end

function Menu:GetStatus()
    return { open = self.spec ~= nil, owner = self.spec and self.spec.owner, items = self.actions and #self.actions or 0,
        outside = self.outside, lastClose = self.lastClose, opened = self.opened or 0, action = self.actionState }
end
