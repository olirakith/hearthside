local MS = _G.MS
MS.Ink = MS.Ink or {}
-- Two cards of the Hearthside window: sharing a tale (give it to a player in the game, or copy its
-- seal), and the question asked to the player it is given to.
local A = MS.Active
local I = MS.Ink
local T = I.Theme
local Panel = A.Panel
local Courier = I.Courier

local function L() return MS.L end
local function Person(name) return MS.BroadcastMode and MS.BroadcastMode:Person(name) or name end

-- Sharing ----------------------------------------------------------------------------------------
local Give = { topic = "INK", back = "HOME" }
I.GiveCard = Give

function Give:Title() return L().INK_GIVE_TITLE end

function Give:Focus(id) self.taleId, self.notice = id, nil end

function Give:Build(container, width)
    self.width = width
    self.heading = T.Text(container, "TITLE", 20, "text")
    self.heading:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -6)
    self.heading:SetWidth(width)
    T.MaxLines(self.heading, 2)
    self.help = T.Text(container, "UI", 15, "textSoft")
    self.help:SetPoint("TOPLEFT", self.heading, "BOTTOMLEFT", 0, -10)
    self.help:SetWidth(width)
    self.help:SetText(L().INK_GIVE_HELP)
    self.name = T.Line(container, "UI", 16, 80, L().INK_GIVE_NAME_HINT, function() Give.notice = nil; Give:Refresh() end)
    self.name:SetPoint("TOPLEFT", self.help, "BOTTOMLEFT", 0, -18)
    self.name:SetScript("OnEnterPressed", function() Give:Send() end)
    self.friends = T.Button(container, "SECONDARY", L().SEAL_FRIENDS, function() Give:Friends() end, 90, 32)
    self.friends:SetPoint("LEFT", self.name, "RIGHT", 10, 0)
    self.send = T.Button(container, "PRIMARY", L().INK_GIVE_SEND, function() Give:Send() end, 180, 36)
    self.send:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -16)
    self.cancel = T.Button(container, "GHOST", L().INK_GIVE_CANCEL, function() Courier:Cancel() end, 120, 36)
    self.cancel:SetPoint("LEFT", self.send, "RIGHT", 10, 0)
    self.status = T.Text(container, "UI", 15, "gold")
    self.status:SetPoint("TOPLEFT", self.send, "BOTTOMLEFT", 0, -14)
    self.status:SetWidth(width)
    self.copyHelp = T.Text(container, "UI", 14, "muted")
    self.copyHelp:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 50)
    self.copyHelp:SetWidth(width)
    self.copyHelp:SetText(L().INK_GIVE_COPY_HELP)
    self.copy = T.Button(container, "SECONDARY", L().INK_SHARE_ACTION, function() Give:Copy() end, 170, 36)
    self.copy:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 4)
end

function Give:Friends()
    local actions, mode = {}, MS.BroadcastMode
    local hidden = mode and mode:IsOn()
    for index, friend in ipairs(A.Seals:Friends()) do
        local shown = hidden and string.format(L().BROADCAST_FRIEND_N, index) or friend.name
        actions[#actions + 1] = { label = friend.online and string.format(L().SEAL_FRIEND_ONLINE, shown) or shown,
            run = function() Give.name:SetValue(friend.name); Give.notice = nil; Give:Refresh() end }
    end
    MS.JourneyContextMenu:Open({ owner = "INK_FRIENDS", title = L().SEAL_FRIENDS_TITLE, actions = actions })
end

function Give:Send()
    if Courier:Busy() then return end
    self.name:ClearFocus()
    local ok, reason = Courier:Offer(self.taleId, self.name:GetText())
    self.notice = not ok and L()["INK_GIVE_" .. reason] or nil
    self:Refresh()
end

function Give:Copy()
    local seal = self.taleId and I:Seal(self.taleId)
    if not seal then return end
    Panel:Close("PLAYER")
    MS.Diagnostics:ShowCopyableReport(L().INK_SHARE_TITLE, seal, "INK_SEAL", string.format(L().INK_SHARE_INSTRUCTION, #seal))
end

-- What the last offer of this tale became, in one sentence.
function Give:Status()
    local out = Courier.outgoing
    if self.notice then return self.notice end
    if not out or (out.taleId ~= self.taleId and not Courier:Busy()) then return "" end
    if out.state == "DONE" then return string.format(L()["INK_GIVE_" .. out.reason], Person(out.target), out.title) end
    return string.format(L()["INK_GIVE_STATE_" .. out.state], Person(out.target))
end

function Give:Refresh()
    local entry = self.taleId and I:Entry(self.taleId)
    if not entry then return Panel:Show("HOME") end
    local mode, busy = MS.BroadcastMode, Courier:Busy()
    if mode then mode:Password(self.name) end
    local menu = MS.JourneyContextMenu
    local friends = menu ~= nil and menu:Surface() ~= nil and #A.Seals:Friends() > 0
    self.heading:SetText(entry.tale.title)
    self.friends:SetShown(friends)
    self.name:SetWidth(friends and self.width - 110 or self.width)
    self.send:SetActive(not busy)
    self.send:Fit(150, 260)
    self.friends:SetWidth(100)
    self.cancel:SetShown(busy)
    self.cancel:Fit(90, 180)
    self.copy:Fit(150, 260)
    self.status:SetText(self:Status())
end

Panel:RegisterView("INK_GIVE", Give)

-- The question ------------------------------------------------------------------------------------
local Offered = { topic = "INK", back = "HOME" }
I.OfferedCard = Offered

function Offered:Title() return L().INK_OFFERED_TITLE end

function Offered:Build(container, width)
    local height = container:GetHeight() or 420
    self.sheet = T.Parchment(container)
    self.sheet:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -4)
    self.sheet:SetSize(width, height - 56)
    local sheet, inner = self.sheet, width - 56
    self.kicker = T.Text(sheet, "UI", 14, "inkSoft")
    self.kicker:SetPoint("TOPLEFT", sheet, "TOPLEFT", 28, -24)
    self.kicker:SetWidth(inner)
    self.heading = T.Text(sheet, "TITLE", 22, "ink")
    self.heading:SetPoint("TOPLEFT", self.kicker, "BOTTOMLEFT", 0, -10)
    self.heading:SetWidth(inner)
    T.MaxLines(self.heading, 3)
    self.body = T.Text(sheet, "INK", 16, "ink")
    self.body:SetPoint("TOPLEFT", self.heading, "BOTTOMLEFT", 0, -12)
    self.body:SetWidth(inner)
    self.accept = T.Button(container, "PRIMARY", L().INK_OFFERED_ACCEPT, function() Offered:Answer(true) end, 160, 36)
    self.accept:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 4)
    self.refuse = T.Button(container, "GHOST", L().INK_OFFERED_REFUSE, function() Offered:Answer(false) end, 120, 36)
    self.refuse:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 4)
    self.read = T.Button(container, "PRIMARY", L().INK_OPEN_BOOK, function() Offered:Read() end, 200, 36)
    self.read:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 4)
    self.close = T.Button(container, "GHOST", L().INK_OFFERED_CLOSE, function() Panel:Close("PLAYER") end, 120, 36)
    self.close:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 4)
end

function Offered:Answer(yes)
    local offer = Courier.asking
    if yes then
        Courier:Accept(offer)
        return
    end
    Courier.asking = nil
    Courier:Decline(offer)
    if Panel:IsShown() and Panel.current == "INK_OFFERED" then Panel:Close("ANSWERED") end
end

function Offered:Read()
    local id = Courier.asking and Courier.asking.taleId
    Panel:Close("PLAYER")
    if id then I:OpenTab("BOOK", id) end
end

-- Closed by the player without a word: that is a no. Closed by anything else, it is asked again.
function Offered:Closed(reason)
    local offer = Courier.asking
    Courier.asking = nil
    if reason == "PLAYER" or reason == "ESCAPE" then Courier:Decline(offer) end
end

function Offered:Refresh()
    local offer = Courier.asking
    -- Taken back or expired before an answer: nothing to say any more.
    if not offer or (offer.state == "DONE" and not offer.result) or (offer.state == "ASKING" and not Courier:Find(offer.id)) then
        return Panel:Close("ANSWERED")
    end
    self.kicker:SetText(string.format(L().INK_OFFERED_BY, Person(offer.sender)))
    self.heading:SetText(offer.title)
    local asking, done = offer.state == "ASKING", offer.state == "DONE"
    local text = string.format(L().INK_OFFERED_BODY, L()["INK_MODE_" .. offer.mode], offer.pages)
    if done then
        text = offer.result == "FAILED" and L().INK_OFFER_FAILED or string.format(L()["INK_IMPORT_" .. offer.result], offer.title)
    elseif not asking then
        text = string.format(L().INK_OFFERED_ROUTE, math.floor(offer.have / offer.count * 100))
    end
    self.body:SetText(text)
    self.accept:SetShown(asking)
    self.refuse:SetShown(asking)
    self.read:SetShown(done and offer.kept == true)
    self.close:SetShown(not asking)
    self.read:Fit(150, 260)
    self.close:Fit(90, 200)
    self.accept:Fit(130, 240)
    self.refuse:Fit(90, 200)
end

Panel:RegisterView("INK_OFFERED", Offered)
