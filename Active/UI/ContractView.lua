local MS = _G.MS
MS.Active = MS.Active or {}
-- Contrat: draw three cards (or choose them) and sign; then the rules, live. Opening the view
-- already shows a draw, so starting takes one click.
local A = MS.Active
local Kit = A.Kit
local View = { topic = "CONTRACT", mode = "SOLO", tiles = {}, rules = {}, picks = {} }
A.ContractView = View

function View:Title() return MS.L.CONTRACT_NAME end

local function T() return A.ContractText end

-- Kit.Label forces a dark shadow; on paper the ink must stay clean, and Kit.Paint resets it.
local function PaperLabel(parent, token, color, justify)
    local label = Kit.Label(parent, token, color, justify)
    Kit.Paint(label, color)
    return label
end

-- A state on paper is a stamp: light state colors are unreadable as text there.
local function Stamp(fill, label, color)
    local honor = color == "textSecondary"
    Kit.Fill(fill, honor and "paperAccent" or color)
    Kit.Paint(label, honor and "paperSelected" or "ink")
end

-- A drawn card: hovering offers to remove it, a click removes it.
local function Tile(parent, width, onClick)
    local tile = CreateFrame("Button", nil, parent)
    tile:SetSize(width, 150)
    tile.border = tile:CreateTexture(nil, "BACKGROUND")
    tile.border:SetAllPoints(tile)
    Kit.Fill(tile.border, "gold")
    tile.back = tile:CreateTexture(nil, "BORDER")
    tile.back:SetPoint("TOPLEFT", tile, "TOPLEFT", 2, -2)
    tile.back:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -2, 2)
    Kit.Fill(tile.back, "paperRaised")
    tile.tag = PaperLabel(tile, "SMALL", "paperAccent")
    tile.tag:SetPoint("TOPLEFT", tile, "TOPLEFT", 10, -10)
    tile.tag:SetWidth(width - 20)
    tile.title = PaperLabel(tile, "ITEM_TITLE", "ink")
    tile.title:SetPoint("TOPLEFT", tile, "TOPLEFT", 10, -30)
    tile.title:SetWidth(width - 20)
    tile.desc = PaperLabel(tile, "SECONDARY", "inkSecondary")
    tile.desc:SetPoint("TOPLEFT", tile, "TOPLEFT", 10, -76)
    tile.desc:SetWidth(width - 20)
    tile.mark = PaperLabel(tile, "SMALL", "paperAccent")
    tile.mark:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 10, 10)
    tile:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
    Kit.Reactive(tile, function(self)
        Kit.Fill(self.back, self.pressed and "paperInset" or self.hovered and "paperSelected" or "paperRaised")
        self.mark:SetText(self.hovered and MS.L.CONTRACT_REMOVE_MARK or MS.L.CONTRACT_KEPT_MARK)
    end)
    tile.mark:SetText(MS.L.CONTRACT_KEPT_MARK)
    return tile
end

-- A mode tab: text only, a gold 3 px underline when active.
local function Tab(parent, width, onClick)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(width, 26)
    tab.label = Kit.Label(tab, "BODY", "muted", "CENTER")
    tab.label:SetPoint("LEFT", tab, "LEFT", 4, 0)
    tab.label:SetPoint("RIGHT", tab, "RIGHT", -4, 0)
    tab.underline = tab:CreateTexture(nil, "ARTWORK")
    tab.underline:SetHeight(3)
    tab.underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
    tab.underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
    Kit.Fill(tab.underline, "gold")
    tab.underline:Hide()
    tab:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
    local function Paint(self)
        self.underline:SetShown(self.selected == true)
        Kit.Paint(self.label, self.selected and "textBright" or self.hovered and "textPrimary" or "muted")
    end
    Kit.Reactive(tab, Paint)
    function tab:SetLabel(text) self.label:SetText(text or "") end
    function tab:SetSelected(selected)
        self.selected = selected == true
        Paint(self)
    end
    return tab
end

-- A choose-list row: paper with ink text and a checked box when picked; dimmed when the three
-- slots are taken (View:Toggle already ignores a fourth pick).
local function Option(parent, width, onClick)
    local option = CreateFrame("Button", nil, parent)
    option:SetSize(width, 22)
    option.edge = option:CreateTexture(nil, "BACKGROUND")
    option.edge:SetAllPoints(option)
    option.back = option:CreateTexture(nil, "BORDER")
    option.back:SetPoint("TOPLEFT", option, "TOPLEFT", 1, -1)
    option.back:SetPoint("BOTTOMRIGHT", option, "BOTTOMRIGHT", -1, 1)
    option.box = option:CreateTexture(nil, "ARTWORK")
    option.box:SetSize(12, 12)
    option.box:SetPoint("LEFT", option, "LEFT", 6, 0)
    option.check = option:CreateTexture(nil, "OVERLAY")
    option.check:SetSize(6, 6)
    option.check:SetPoint("CENTER", option.box, "CENTER", 0, 0)
    option.label = Kit.Label(option, "SECONDARY", "textPrimary")
    option.label:SetPoint("LEFT", option, "LEFT", 24, 0)
    option.label:SetWidth(width - 150)
    option.tag = Kit.Label(option, "SMALL", "paperAccent", "RIGHT")
    option.tag:SetPoint("RIGHT", option, "RIGHT", -6, 0)
    option.tag:SetWidth(116)
    option:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
    function option:SetLabel(text) self.label:SetText(text or "") end
    function option:SetTag(text) self.tag:SetText(text or "") end
    local function Paint(self)
        local hovered = self.hovered == true and self.locked ~= true
        Kit.Fill(self.edge, (self.selected or hovered) and "gold" or "borderMuted")
        Kit.Fill(self.back, self.selected and (hovered and "paperSelected" or "paperRaised")
            or hovered and "backgroundRaised" or "backgroundPanel")
        Kit.Fill(self.box, self.selected and "ink" or "borderMuted")
        Kit.Fill(self.check, self.selected and "paperAccent" or "backgroundPanel")
        self.check:SetShown(self.selected)
        Kit.Paint(self.label, self.selected and "ink" or "textPrimary")
        Kit.Paint(self.tag, self.selected and "paperAccent" or "muted")
    end
    Kit.Reactive(option, Paint)
    function option:SetSelected(selected)
        self.selected = selected == true
        Paint(self)
    end
    function option:SetLocked(locked)
        self.locked = locked == true
        self:SetAlpha(self.locked and .45 or 1)
        Paint(self)
    end
    option:SetSelected(false)
    return option
end

function View:Build(container, width)
    local L = MS.L
    self.width = width
    -- Setup (no contract running)
    local setup = CreateFrame("Frame", nil, container)
    setup:SetAllPoints(container)
    self.setup = setup
    self.modes = {
        SOLO = Tab(setup, 250, function() View:SetMode("SOLO") end),
        GROUP = Tab(setup, 222, function() View:SetMode("GROUP") end),
    }
    local tabRule = Kit.Rule(setup)
    tabRule:SetPoint("TOPLEFT", setup, "TOPLEFT", 0, -26)
    tabRule:SetPoint("TOPRIGHT", setup, "TOPRIGHT", 0, -26)
    self.modes.SOLO:SetLabel(L.CONTRACT_MODE_SOLO)
    self.modes.GROUP:SetLabel(L.CONTRACT_MODE_GROUP)
    self.modes.SOLO:SetPoint("TOPLEFT", setup, "TOPLEFT", 0, 0)
    self.modes.GROUP:SetPoint("LEFT", self.modes.SOLO, "RIGHT", 8, 0)
    self.context = Kit.Label(setup, "SECONDARY", "textSecondary")
    self.context:SetPoint("TOPLEFT", setup, "TOPLEFT", 0, -38)
    self.context:SetWidth(width - 280)
    self.count = Kit.Label(setup, "SECONDARY", "gold", "RIGHT")
    self.count:SetPoint("TOPRIGHT", setup, "TOPRIGHT", 0, -38)
    self.count:SetWidth(120)
    local third = math.floor((width - 16) / 3)
    for index = 1, 3 do
        local tile = Tile(setup, third, function(card) View:DropDrawn(card.cardId) end)
        tile:SetPoint("TOPLEFT", setup, "TOPLEFT", (index - 1) * (third + 8), -64)
        self.tiles[index] = tile
    end
    -- Choose list (replaces the tiles)
    self.choose = CreateFrame("Frame", nil, setup)
    self.choose:SetPoint("TOPLEFT", setup, "TOPLEFT", 0, -64)
    self.choose:SetSize(width, 230)
    self.options = {}
    for index = 1, 9 do
        local option = Option(self.choose, width, function(button) View:Toggle(button.cardId) end)
        option:SetPoint("TOPLEFT", self.choose, "TOPLEFT", 0, -(index - 1) * 24)
        self.options[index] = option
    end
    self.trialNote = Kit.Label(setup, "SECONDARY", "muted")
    self.trialNote:SetPoint("TOPLEFT", setup, "TOPLEFT", 0, -222)
    self.trialNote:SetWidth(width)
    self.redraw = Kit.Button(setup, 130, 30, function() View:Draw() end)
    self.redraw:SetPoint("BOTTOMLEFT", setup, "BOTTOMLEFT", 0, 34)
    self.redraw:SetLabel(L.CONTRACT_REDRAW)
    self.chooseButton = Kit.Button(setup, 130, 30, function() View:SetChoosing(not View.choosing) end)
    self.chooseButton:SetPoint("LEFT", self.redraw, "RIGHT", 8, 0)
    self.sign = Kit.Button(setup, 200, 30, function() View:Sign() end)
    self.sign:SetPoint("BOTTOMRIGHT", setup, "BOTTOMRIGHT", 0, 34)
    self.sign:SetLabel(L.CONTRACT_SIGN)
    -- Enabled, Sign is the one filled gold action with ink text.
    self.signFill = self.sign:CreateTexture(nil, "ARTWORK")
    self.signFill:SetPoint("TOPLEFT", self.sign, "TOPLEFT", 1, -1)
    self.signFill:SetPoint("BOTTOMRIGHT", self.sign, "BOTTOMRIGHT", -1, 1)
    Kit.Fill(self.signFill, "gold")
    self.sign:HookScript("OnEnter", function() Kit.Fill(View.signFill, "textBright") end)
    self.sign:HookScript("OnLeave", function() Kit.Fill(View.signFill, "gold") end)
    self.signInk = Kit.Label(self.sign, "BODY", "ink", "CENTER")
    self.signInk:SetPoint("LEFT", self.sign, "LEFT", 6, 0)
    self.signInk:SetPoint("RIGHT", self.sign, "RIGHT", -6, 0)
    -- What is about to be signed, in one line; in a group, the rules go to the group first.
    self.summary = Kit.Label(setup, "SECONDARY", "textPrimary")
    self.summary:SetPoint("BOTTOMLEFT", setup, "BOTTOMLEFT", 0, 74)
    self.summary:SetWidth(width - 210)
    self.propose = Kit.Button(setup, 200, 26, function() View:Propose() end)
    self.propose:SetPoint("BOTTOMRIGHT", setup, "BOTTOMRIGHT", 0, 70)
    self.propose:SetLabel(L.CONTRACT_PROPOSE)
    self.feedback = Kit.Label(setup, "SECONDARY", "warning")
    self.feedback:SetPoint("BOTTOMLEFT", setup, "BOTTOMLEFT", 0, 8)
    self.feedback:SetWidth(width)
    self.lastSheet = Kit.Button(setup, 130, 22, function() A.Panel:Show("SHEET") end)
    self.lastSheet:SetPoint("TOPRIGHT", setup, "TOPRIGHT", -128, -34)
    self.lastSheet:SetLabel(L.CONTRACT_LAST_SHEET)

    -- Running
    local running = CreateFrame("Frame", nil, container)
    running:SetAllPoints(container)
    self.running = running
    self.sheet = running:CreateTexture(nil, "BACKGROUND")
    self.sheet:SetPoint("TOPLEFT", running, "TOPLEFT", 0, 0)
    self.sheet:SetSize(width, 296)
    Kit.Fill(self.sheet, "paperRaised")
    self.runTitle = PaperLabel(running, "ITEM_TITLE", "ink")
    self.runTitle:SetPoint("TOPLEFT", running, "TOPLEFT", 10, -8)
    self.runTitle:SetWidth(width - 190)
    self.runInfo = PaperLabel(running, "SECONDARY", "inkSecondary")
    self.runInfo:SetPoint("TOPLEFT", running, "TOPLEFT", 10, -34)
    self.runInfo:SetWidth(width - 190)
    self.runClock = PaperLabel(running, "CHAPTER_TITLE", "paperAccent", "RIGHT")
    self.runClock:SetPoint("TOPRIGHT", running, "TOPRIGHT", -10, -8)
    self.runClock:SetWidth(170)
    self.runClockLabel = PaperLabel(running, "SECONDARY", "inkSecondary", "RIGHT")
    self.runClockLabel:SetPoint("TOPRIGHT", running, "TOPRIGHT", -10, -36)
    self.runClockLabel:SetWidth(170)
    for index = 1, 3 do
        local row = CreateFrame("Frame", nil, running)
        row:SetSize(width - 20, 64)
        row:SetPoint("TOPLEFT", running, "TOPLEFT", 10, -68 - (index - 1) * 70)
        row.title = PaperLabel(row, "BODY", "ink")
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
        row.title:SetWidth(width - 190)
        row.tag = PaperLabel(row, "SMALL", "paperAccent")
        row.tag:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -24)
        row.tag:SetWidth(width - 190)
        row.stamp = row:CreateTexture(nil, "ARTWORK")
        row.stamp:SetSize(124, 22)
        row.stamp:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -4)
        row.state = PaperLabel(row, "SMALL", "ink", "CENTER")
        row.state:SetPoint("LEFT", row.stamp, "LEFT", 2, 0)
        row.state:SetPoint("RIGHT", row.stamp, "RIGHT", -2, 0)
        row.reason = PaperLabel(row, "SECONDARY", "inkSecondary")
        row.reason:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -42)
        row.reason:SetWidth(width - 20)
        row.rule = Kit.Rule(row, "paperAccent")
        row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        self.rules[index] = row
    end
    self.signed = PaperLabel(running, "SECONDARY", "inkSecondary")
    self.signed:SetPoint("TOPLEFT", running, "TOPLEFT", 10, -274)
    self.signed:SetWidth(width - 20)
    self.runNote = Kit.Label(running, "SECONDARY", "muted")
    self.runNote:SetPoint("TOPLEFT", running, "TOPLEFT", 0, -302)
    self.runNote:SetWidth(width)
    local button = math.floor((width - 16) / 3)
    self.announce = Kit.Button(running, button, 30, function() View:Announce() end)
    self.announce:SetPoint("BOTTOMLEFT", running, "BOTTOMLEFT", 0, 34)
    self.announce:SetLabel(L.CONTRACT_ANNOUNCE)
    self.finish = Kit.Button(running, button, 30, function() View:FinishGroup() end)
    self.finish:SetPoint("LEFT", self.announce, "RIGHT", 8, 0)
    self.finish:SetLabel(L.CONTRACT_FINISH_DUNGEON)
    -- Abandon is quiet: text only, aligned right.
    self.abandon = CreateFrame("Button", nil, running)
    self.abandon:SetSize(button, 30)
    self.abandon:SetPoint("BOTTOMRIGHT", running, "BOTTOMRIGHT", 0, 34)
    self.abandon.label = Kit.Label(self.abandon, "BODY", "muted", "RIGHT")
    self.abandon.label:SetPoint("LEFT", self.abandon, "LEFT", 0, 0)
    self.abandon.label:SetPoint("RIGHT", self.abandon, "RIGHT", 0, 0)
    self.abandon:SetScript("OnClick", function() View:Abandon() end)
    Kit.Reactive(self.abandon, function(button) Kit.Paint(button.label, button.hovered and "textPrimary" or "muted") end)
    function self.abandon:SetLabel(text) self.label:SetText(text or "") end
    self.runFeedback = Kit.Label(running, "SECONDARY", "textSecondary")
    self.runFeedback:SetPoint("BOTTOMLEFT", running, "BOTTOMLEFT", 0, 8)
    self.runFeedback:SetWidth(width)
end

function View:SetMode(mode)
    if self.mode == mode and self.cards then return end
    self.mode = mode
    self.choosing, self.picks = false, {}
    self:Draw()
end

-- Group needs a group, inside the dungeon; solo needs a readable level below the cap.
function View:Available(mode)
    local _, context = A.Contracts:Pool(mode)
    local refusal = A.Contracts:Refusal(mode, context)
    return refusal == nil, refusal, context
end

function View:Draw()
    self.choosing = false
    local ok = self:Available(self.mode)
    self.cards = ok and A.Contracts:Draw(self.mode) or {}
    self.feedback:SetText("")
    self:Refresh()
    for _, tile in ipairs(self.tiles) do Kit.FadeIn(tile) end
end

function View:SetChoosing(choosing)
    self.choosing = choosing
    self.picks = {}
    if choosing then for _, card in ipairs(self.cards or {}) do self.picks[#self.picks + 1] = card.id end end
    self:Refresh()
    Kit.FadeIn(choosing and self.choose or self.tiles[1])
    if not choosing then Kit.FadeIn(self.tiles[2]); Kit.FadeIn(self.tiles[3]) end
end

-- Removing a drawn card makes the Contract a chosen one: the list opens with the other two kept.
function View:DropDrawn(id)
    if not id then return end
    self:SetChoosing(true)
    self:Toggle(id)
end

function View:Toggle(id)
    if not id then return end
    for index, picked in ipairs(self.picks) do
        if picked == id then
            table.remove(self.picks, index)
            Kit.Play("CARD")
            self:Refresh()
            return
        end
    end
    if #self.picks < 3 then
        self.picks[#self.picks + 1] = id
        Kit.Play("CARD")
    end
    self:Refresh()
end

function View:Selection()
    if not self.choosing then return self.cards or {}, "DRAW" end
    local cards = {}
    for _, id in ipairs(self.picks) do cards[#cards + 1] = { id = id } end
    return cards, "CHOOSE"
end

function View:Sign()
    local cards, source = self:Selection()
    local contract, reason = A.Contracts:Start(self.mode, cards, source)
    if not contract then
        self.feedback:SetText(MS.L["CONTRACT_REFUSED_" .. tostring(reason)] or MS.L.CONTRACT_REFUSED_CARD)
        return
    end
    self.cards, self.choosing, self.picks = nil, false, {}
    self.abandonArmed, self.finishArmed = false, false
    Kit.Play("SIGN")
    self:Refresh()
    Kit.FadeIn(self.running, .25)
end

function View:Propose()
    local cards = self:Selection()
    local ok, reason = A.Contracts:Propose(cards)
    self.feedback:SetText(ok and MS.L.CONTRACT_PROPOSE_READY or (MS.L["ACTIVE_CHAT_" .. tostring(reason)] or MS.L.ACTIVE_CHAT_FAILED))
    Kit.Paint(self.feedback, ok and "success" or "warning")
    self:Refresh()
end

-- Ending a dungeon Contrat asks twice, like abandoning: the rules still running are judged on
-- what was seen.
function View:FinishGroup()
    if not self.finishArmed then
        self.finishArmed = true
        self.finish:SetLabel(MS.L.CONTRACT_FINISH_CONFIRM)
        return
    end
    self.finishArmed = false
    A.Contracts:Finish("ENDED")
end

function View:Announce()
    local ok, reason = A.Contracts:Announce("START")
    self.runFeedback:SetText(ok and MS.L.CONTRACT_ANNOUNCE_READY or (MS.L["ACTIVE_CHAT_" .. tostring(reason)] or MS.L.ACTIVE_CHAT_FAILED))
    Kit.Paint(self.runFeedback, ok and "success" or "warning")
    self:Refresh()
end

-- Abandoning asks twice (the second click confirms).
function View:Abandon()
    if not self.abandonArmed then
        self.abandonArmed = true
        self.abandon:SetLabel(MS.L.CONTRACT_ABANDON_CONFIRM)
        return
    end
    self.abandonArmed = false
    A.Contracts:Finish("ABANDONED")
end

function View:Refresh()
    local contract = A.Contracts:Current()
    self.setup:SetShown(contract == nil)
    self.running:SetShown(contract ~= nil)
    if contract then self:RefreshRunning(contract) else self:RefreshSetup() end
end

function View:RefreshSetup()
    local L = MS.L
    for mode, button in pairs(self.modes) do button:SetSelected(mode == self.mode) end
    local ok, reason, context = self:Available(self.mode)
    if ok and not self.cards then self.cards = A.Contracts:Draw(self.mode) end
    if not ok then
        self.context:SetText(L["CONTRACT_REFUSED_" .. reason])
        Kit.Paint(self.context, "warning")
    elseif self.mode == "SOLO" then
        self.context:SetText(string.format(L.CONTRACT_CONTEXT_SOLO, context.level, context.level + 1))
        Kit.Paint(self.context, "textSecondary")
    else
        local members = A.Contracts:Members()
        self.context:SetText(members and string.format(L.CONTRACT_CONTEXT_GROUP, #members + 1) or L.CONTRACT_MODE_GROUP)
        Kit.Paint(self.context, "textSecondary")
    end
    local selected = self:Selection()
    self.count:SetText(string.format(L.CONTRACT_RULE_COUNT, #selected))
    Kit.Paint(self.count, #selected >= 3 and "success" or "gold")
    local trial = false
    for index, tile in ipairs(self.tiles) do
        local card = ok and not self.choosing and self.cards[index] or nil
        tile:SetShown(card ~= nil)
        if card then
            tile.cardId = card.id
            tile.tag:SetText(T():ModeTag(card.id, self.mode, A.caps))
            tile.title:SetText(T():Title(card.id, card.param))
            tile.desc:SetText(T():Description(card.id, self.mode))
            trial = trial or A.ContractEngine:OnTrial(card.id, self.mode, A.caps)
        end
    end
    self.choose:SetShown(ok and self.choosing)
    if ok and self.choosing then
        local pool = A.Contracts:Pool(self.mode)
        for index, option in ipairs(self.options) do
            local id = pool[index]
            option:SetShown(id ~= nil)
            if id then
                option.cardId = id
                local picked = false
                for _, pick in ipairs(self.picks) do if pick == id then picked = true end end
                option:SetLabel(T():Title(id, MS.Active.ContractCatalog.TimeLimit(self.mode, context.level)))
                option:SetTag(T():ModeTag(id, self.mode, A.caps))
                option:SetSelected(picked)
                option:SetLocked(not picked and #self.picks >= 3)
                if picked then trial = trial or A.ContractEngine:OnTrial(id, self.mode, A.caps) end
            end
        end
    end
    self.trialNote:SetText(trial and L.CONTRACT_TRIAL_NOTE or "")
    self.trialNote:ClearAllPoints()
    self.trialNote:SetPoint("TOPLEFT", self.setup, "TOPLEFT", 0, self.choosing and -284 or -222)
    self.chooseButton:SetLabel(self.choosing and L.CONTRACT_BACK_TO_DRAW or L.CONTRACT_CHOOSE)
    self.redraw:SetShown(ok and not self.choosing)
    self.chooseButton:SetShown(ok)
    local selection = self:Selection()
    local count = #selection
    self.sign:SetEnabled(ok and count >= 1)
    self.sign.actionDisabled = not (ok and count >= 1)
    local signable = ok and count >= 1
    self.signFill:SetShown(signable)
    self.signInk:SetText(signable and L.CONTRACT_SIGN or "")
    self.sign:SetLabel(signable and "" or L.CONTRACT_SIGN)
    self.summary:SetText(ok and count >= 1 and string.format(L.CONTRACT_SIGN_SUMMARY, T():Summary(selection, self.mode, context.level)) or "")
    local proposed = A.Contracts.proposal ~= nil and A.Contracts.proposal == A.Contracts.CardList(selection)
    self.propose:SetShown(ok and self.mode == "GROUP")
    self.propose:SetEnabled(count >= 1 and not proposed)
    self.propose.actionDisabled = count < 1 or proposed
    self.propose:SetLabel(proposed and L.CONTRACT_PROPOSED or L.CONTRACT_PROPOSE)
    self.lastSheet:SetShown(A.Contracts:History()[1] ~= nil)
end

function View:RefreshRunning(contract)
    local L = MS.L
    self.runTitle:SetText(T():ContractTitle(contract.goal))
    self:RefreshClock(contract)
    local trial = false
    for index, row in ipairs(self.rules) do
        local card = contract.cards[index]
        row:SetShown(card ~= nil)
        if card then
            local rule = contract.rules[card.id]
            row.title:SetText(T():Title(card.id, card.param))
            row.tag:SetText(T():ModeTag(card.id, contract.mode, A.caps))
            local onTrial = rule.status == "WATCHING" and not rule.uncertain and A.ContractEngine:OnTrial(card.id, contract.mode, A.caps)
            local text, color = T():LiveState(rule, onTrial)
            row.state:SetText(text)
            Stamp(row.stamp, row.state, color)
            local reason = T():Reason(rule.status == "BROKEN" and rule.reason or rule.uncertain, rule.who)
            -- NON VÉRIFIABLE is final for this Contrat: said once, under its cause.
            if reason and rule.status ~= "BROKEN" and rule.uncertain then reason = reason .. " " .. L.CONTRACT_UNVERIFIABLE_FINAL end
            row.reason:SetText(reason or T():Description(card.id, contract.mode))
            trial = trial or onTrial
        end
    end
    self.runNote:SetText(trial and L.CONTRACT_TRIAL_NOTE or "")
    local name = A.Call(_G.UnitName, "player")
    self.signed:SetText(type(name) == "string" and name ~= "" and string.format(L.CONTRACT_SIGNED_BY, name) or "")
    self.announce:SetEnabled(not contract.announced.start)
    self.announce.actionDisabled = contract.announced.start == true
    self.announce:SetLabel(contract.announced.start and L.CONTRACT_ANNOUNCED or L.CONTRACT_ANNOUNCE)
    self.finish:SetShown(contract.mode == "GROUP")
    if not self.finishArmed then self.finish:SetLabel(L.CONTRACT_FINISH_DUNGEON) end
    if not self.abandonArmed then self.abandon:SetLabel(L.CONTRACT_ABANDON) end
end

-- "Dans le donjon · depuis 12 min" / "Hors du donjon…": a dungeon Contrat keeps running outside
-- (a repair, a corpse run) until the player ends it.
function View:RefreshClock(contract)
    local L, key = MS.L, "CONTRACT_RUNNING_SOLO"
    if contract.mode == "GROUP" then
        local inside = A.Contracts:InDungeon()
        key = inside == true and "CONTRACT_RUNNING_GROUP" or inside == false and "CONTRACT_RUNNING_GROUP_OUT" or "CONTRACT_RUNNING_GROUP_UNKNOWN"
    end
    local elapsed = A.ContractEngine:Elapsed(contract, A.Now())
    self.runInfo:SetText(string.format(L[key], T():Duration(elapsed)))
    local limit
    for _, card in ipairs(contract.cards) do
        if card.id == "TIME_LIMIT" and type(card.param) == "number" then limit = card.param end
    end
    if limit and type(elapsed) == "number" then
        self.runClock:SetText(T():Duration(math.max(0, limit - elapsed)))
        self.runClockLabel:SetText(L.CONTRACT_REMAINING)
    else
        self.runClock:SetText("")
        self.runClockLabel:SetText("")
    end
end

-- The running clock moves once a second.
function View:Tick()
    local contract = A.Contracts:Current()
    if contract and self.running:IsShown() then self:RefreshClock(contract) end
end

function View:Closed()
    self.abandonArmed, self.finishArmed = false, false
    self.runFeedback:SetText("")
end

A.Panel:RegisterView("CONTRACT", View)

-- SHEET: the end of a Contrat ------------------------------------------------------------------
local Sheet = { topic = "CONTRACT", rows = {} }
A.Sheet = Sheet

function Sheet:Title() return MS.L.CONTRACT_SHEET_HEADING end

function Sheet:Build(container, width)
    -- The signed Contrat, closed: the same paper as while it ran, each verdict a stamp.
    self.paper = container:CreateTexture(nil, "BACKGROUND")
    self.paper:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    self.paper:SetSize(width, 312)
    Kit.Fill(self.paper, "paperRaised")
    self.title = PaperLabel(container, "CHAPTER_TITLE", "ink")
    self.title:SetPoint("TOPLEFT", container, "TOPLEFT", 10, -10)
    self.title:SetWidth(width - 230)
    self.title:SetWordWrap(false)
    self.verdictFill = container:CreateTexture(nil, "ARTWORK")
    self.verdictFill:SetSize(200, 28)
    self.verdictFill:SetPoint("TOPRIGHT", container, "TOPRIGHT", -10, -10)
    self.verdict = PaperLabel(container, "BODY", "ink", "CENTER")
    self.verdict:SetPoint("LEFT", self.verdictFill, "LEFT", 2, 0)
    self.verdict:SetPoint("RIGHT", self.verdictFill, "RIGHT", -2, 0)
    self.context = PaperLabel(container, "SECONDARY", "inkSecondary")
    self.context:SetPoint("TOPLEFT", container, "TOPLEFT", 10, -44)
    self.context:SetWidth(width - 20)
    for index = 1, 3 do
        local row = CreateFrame("Frame", nil, container)
        row:SetSize(width - 20, 62)
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 10, -68 - (index - 1) * 66)
        row.title = PaperLabel(row, "BODY", "ink")
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
        row.title:SetWidth(width - 180)
        row.stampFill = row:CreateTexture(nil, "ARTWORK")
        row.stampFill:SetSize(150, 22)
        row.stampFill:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -4)
        row.stamp = PaperLabel(row, "SMALL", "ink", "CENTER")
        row.stamp:SetPoint("LEFT", row.stampFill, "LEFT", 2, 0)
        row.stamp:SetPoint("RIGHT", row.stampFill, "RIGHT", -2, 0)
        row.reason = PaperLabel(row, "SECONDARY", "inkSecondary")
        row.reason:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -26)
        row.reason:SetWidth(width - 160)
        row.declare = Kit.Button(row, 130, 22, function() Sheet:Declare(row.card) end, true)
        row.declare:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -32)
        row.rule = Kit.Rule(row, "paperAccent")
        row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        self.rows[index] = row
    end
    self.group = PaperLabel(container, "SECONDARY", "inkSecondary")
    self.group:SetPoint("TOPLEFT", container, "TOPLEFT", 10, -268)
    self.group:SetWidth(width - 20)
    self.signed = PaperLabel(container, "SECONDARY", "inkSecondary")
    self.signed:SetPoint("TOPLEFT", container, "TOPLEFT", 10, -288)
    self.signed:SetWidth(width - 20)
    -- The announce label is the longest: it takes its width from the two others.
    local button = math.floor((width - 16) / 3) - 12
    self.announce = Kit.Button(container, width - 16 - button * 2, 30, function() Sheet:Announce() end)
    self.announce:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 34)
    self.announce:SetLabel(MS.L.CONTRACT_ANNOUNCE_RESULT_ACTION)
    self.again = Kit.Button(container, button, 30, function() Sheet:Seen(); A.ContractView.cards = nil; A.Panel:Show("CONTRACT") end)
    self.again:SetPoint("LEFT", self.announce, "RIGHT", 8, 0)
    self.again:SetLabel(MS.L.CONTRACT_AGAIN)
    self.close = Kit.Button(container, button, 30, function() A.Panel:Close("PLAYER") end)
    self.close:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 34)
    self.close:SetLabel(MS.L.ACTIVE_CLOSE)
    self.feedback = Kit.Label(container, "SECONDARY", "textSecondary")
    self.feedback:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 8)
    self.feedback:SetWidth(width)
end

function Sheet:Result() return A.Contracts:History()[1] end

function Sheet:Refresh()
    local result, L = self:Result(), MS.L
    if not result then A.Panel:Show("CONTRACT"); return end
    self.title:SetText(T():ContractTitle(result.context))
    local verdict, color = T():Verdict(result.verdict)
    self.verdict:SetText(verdict)
    Stamp(self.verdictFill, self.verdict, color)
    local context
    if result.context.goal == "LEVEL" then
        context = string.format(result.context.reached and L.CONTRACT_SHEET_LEVEL_REACHED or L.CONTRACT_SHEET_LEVEL_NOT_REACHED,
            result.context.from or 0, result.context.target or 0)
    else
        context = L.CONTRACT_SHEET_DUNGEON
    end
    self.context:SetText(string.format(L.CONTRACT_SHEET_CONTEXT, context, Kit.Date(result.endedAt), T():Duration(result.duration)))
    for index, row in ipairs(self.rows) do
        local rule = result.rules[index]
        row:SetShown(rule ~= nil)
        if rule then
            row.card = rule.card
            row.title:SetText(T():Title(rule.card, rule.param))
            local stamp, stampColor = T():Verdict(rule.verdict)
            row.stamp:SetText(stamp)
            Stamp(row.stampFill, row.stamp, stampColor)
            row.reason:SetText(T():Reason(rule.reason, rule.who) or (rule.mode == "HONOR" and L.CONTRACT_HONOR_NOTE or ""))
            row.declare:SetShown(rule.mode == "HONOR")
            row.declare:SetLabel(rule.verdict == "DECLARED_BROKEN" and L.CONTRACT_DECLARE_UNDO or L.CONTRACT_DECLARE)
        end
    end
    local names = result.group and result.group.names or {}
    local listed = MS.BroadcastMode and MS.BroadcastMode:People(names) or table.concat(names, ", ")
    self.group:SetText(#names > 0 and string.format(L.CONTRACT_SHEET_WITH, listed) or "")
    local signer = result.character and result.character.name
    self.signed:SetText(type(signer) == "string" and signer ~= "" and string.format(L.CONTRACT_SIGNED_BY, signer) or "")
    self.announce:SetEnabled(not result.announced)
    self.announce.actionDisabled = result.announced == true
end

function Sheet:Declare(id)
    local result = self:Result()
    if not result then return end
    for _, rule in ipairs(result.rules) do
        if rule.card == id then A.Contracts:Declare(result, id, rule.verdict ~= "DECLARED_BROKEN") end
    end
    self:Refresh()
end

function Sheet:Announce()
    local ok, reason = A.Contracts:Announce("RESULT", self:Result())
    self.feedback:SetText(ok and MS.L.CONTRACT_ANNOUNCE_READY or (MS.L["ACTIVE_CHAT_" .. tostring(reason)] or MS.L.ACTIVE_CHAT_FAILED))
    Kit.Paint(self.feedback, ok and "success" or "warning")
    self:Refresh()
end

function Sheet:Seen()
    local result = self:Result()
    if result then result.seen = true end
end

function Sheet:Closed()
    self:Seen()
    self.feedback:SetText("")
end

-- A finished contract shows its sheet: in the open window if there is one, otherwise as a card of
-- its own when the arbiter allows (never in combat).
function Sheet:Queue()
    self.pending = true
    self:Pump()
end

function Sheet:Pump()
    local result = A.Contracts:Unseen()
    if not self.pending or not result then self.pending = false; return end
    -- The live view shows the verdict itself; the Generique waits for the streamer's click.
    local live = MS.JourneyLiveView
    if live and live:IsOpen() then self.pending = false; live:Refresh(); return end
    -- A Contrat that ran to its end gets its Generique; the sheet stays one click away from it.
    if result.outcome ~= "ABANDONED" and A.Credits and A.Credits:Wanted() then
        self.pending = false
        A.Credits:Contract(result)
        return
    end
    -- The window is hidden by a fight: it comes back by itself, with the sheet.
    if A.Panel.suspended then A.Panel.current = "SHEET"; self.pending = false; return end
    if A.Panel:IsShown() then
        self.pending = false
        A.Panel:Show("SHEET")
        return
    end
    if A.Panel:Open("SHEET", "RESULT") then self.pending = false
    elseif not self.retry and _G.C_Timer then
        self.retry = C_Timer.NewTicker(2, function()
            if not Sheet.pending then Sheet.retry:Cancel(); Sheet.retry = nil; return end
            Sheet:Pump()
        end)
    end
end

A.Panel:RegisterView("SHEET", Sheet)
