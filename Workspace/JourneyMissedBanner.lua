local MS = _G.MS

-- "What I missed": a band under the tabs after an absence (away, flying, a fight) or at login,
-- when something happened meanwhile. JourneyMissed counts; this module listens and shows. Sender
-- names stay in memory only and are hidden in streamer mode. Nothing is sent to anyone.
MS.JourneyMissedBanner = { HEIGHT = 30, TAXI_CHECKS = { .5, 2 } }
local Banner = MS.JourneyMissedBanner
local Missed = MS.JourneyMissed

local EVENTS = { "PLAYER_FLAGS_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "UPDATE_PENDING_MAIL", "CHAT_MSG_SYSTEM" }

local function Now() return type(_G.time) == "function" and time() or 0 end
local function Hidden(value) return type(_G.issecretvalue) == "function" and issecretvalue(value) end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end
local function Enabled() return MS.JourneySettings:Get("showMissedBanner") ~= false end

-- The game's own sentence for a sale ("A buyer has been found for your auction of %s."), as a pattern.
function Banner:SalePattern()
    if self.salePattern == nil then
        local text = _G.ERR_AUCTION_SOLD_S
        self.salePattern = type(text) == "string" and ("^" .. text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", ".+") .. "$") or false
    end
    return self.salePattern or nil
end

function Banner:Away(reason, on)
    local was = Missed:IsAway()
    Missed:SetAway(reason, on, Now())
    local away = Missed:IsAway()
    if away and not was then self.awaySince = Now() end
    if was and not away then self:Back() end
end

-- Back from an absence: what was counted, and profession cooldowns that came due meanwhile.
function Banner:Back()
    local since, now = self.awaySince, Now()
    self.awaySince = nil
    if since and now - since >= Missed.MIN_AWAY then
        self:AddReady(Missed.Cooldowns(self:Records(), since, now))
    end
    self:Update()
end

function Banner:Records()
    local roster = MS.JourneyRoster
    local ok, list = false, nil
    if roster then ok, list = pcall(roster.List, roster) end
    return ok and type(list) == "table" and list or {}
end

function Banner:AddReady(list)
    if #list == 0 then return end
    self.ready = self.ready or {}
    for _, cooldown in ipairs(list) do self.ready[#self.ready + 1] = cooldown end
end

-- At login: cooldowns ready since this character was last seen, mail waiting on the others.
function Banner:Login(lastSeen)
    local records, now = self:Records(), Now()
    if type(lastSeen) == "number" then self:AddReady(Missed.Cooldowns(records, lastSeen, now)) end
    -- Mail on the others only at a real login, not after a /reload.
    local fresh = type(lastSeen) ~= "number" or now - lastSeen > 600
    for _, record in ipairs(fresh and records or {}) do
        if not record.current and record.mail then
            self.mailOn = self.mailOn or {}
            self.mailOn[#self.mailOn + 1] = record.name
        end
    end
    if self.ready or self.mailOn then self.login = true end
    self:Update()
end

function Banner:OnEvent(event, a, b)
    if event == "PLAYER_FLAGS_CHANGED" then
        if a == nil or a == "player" then
            local afk = Call(_G.UnitIsAFK, "player")
            self:Away("AFK", not Hidden(afk) and afk == true)
        end
    elseif event == "PLAYER_CONTROL_LOST" then
        -- The flight starts a moment after control is lost.
        local timer = _G.C_Timer
        for _, delay in ipairs(self.TAXI_CHECKS) do
            if type(timer) == "table" and type(timer.After) == "function" then timer.After(delay, function() Banner:CheckTaxi() end) end
        end
    elseif event == "PLAYER_CONTROL_GAINED" then
        self:CheckTaxi()
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:Away("COMBAT", true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:Away("COMBAT", false)
        self:Update()
    elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
        local who = not Hidden(b) and type(b) == "string" and b or nil
        if event == "CHAT_MSG_BN_WHISPER" then who = nil end -- a Battle.net sender is an ID, not a name
        Missed:Count("WHISPER", Now(), who and (who:match("^([^%-]+)") or who) or nil)
    elseif event == "UPDATE_PENDING_MAIL" then
        local new = Call(_G.HasNewMail) == true
        if new and not self.hadMail then Missed:Count("MAIL", Now()) end
        self.hadMail = new
    elseif event == "CHAT_MSG_SYSTEM" then
        local pattern = not Hidden(a) and type(a) == "string" and self:SalePattern()
        if pattern and a:find(pattern) then Missed:Count("SALE", Now()) end
    end
end

function Banner:CheckTaxi()
    self:Away("TAXI", Call(_G.UnitOnTaxi, "player") == true)
end

local function Plural(count, one, many) return string.format(count == 1 and MS.L[one] or MS.L[many], count) end

local function Duration(seconds)
    return string.format(MS.L.MISSED_MINUTES, math.max(1, math.floor((seconds or 0) / 60 + .5)))
end

-- The sentence of the band, and the names behind "whispers" for the tooltip.
function Banner:Text()
    local digest, parts = Missed:Pending(), {}
    local mode = MS.BroadcastMode
    if digest and mode and mode:IsOn() then digest = Missed:Hide(digest) end
    local head
    if digest then
        head = string.format(MS.L["MISSED_WHEN_" .. (digest.reason or "AFK")], Duration(digest.till - digest.since))
        local counts = digest.counts
        if counts.WHISPER then parts[#parts + 1] = Plural(counts.WHISPER, "MISSED_WHISPER", "MISSED_WHISPERS") end
        if counts.MAIL then parts[#parts + 1] = Plural(counts.MAIL, "MISSED_MAIL", "MISSED_MAILS") end
        if counts.SALE then parts[#parts + 1] = Plural(counts.SALE, "MISSED_SALE", "MISSED_SALES") end
    elseif self.login then
        head = MS.L.MISSED_WHEN_LOGIN
    elseif self.ready then
        head = MS.L.MISSED_WHEN_AWAY
    end
    for _, cooldown in ipairs(self.ready or {}) do
        local mine = cooldown.character == Call(_G.UnitName, "player")
        parts[#parts + 1] = mine and string.format(MS.L.MISSED_READY, cooldown.name)
            or string.format(MS.L.MISSED_READY_ON, cooldown.name, cooldown.character)
    end
    for _, name in ipairs(self.mailOn or {}) do parts[#parts + 1] = string.format(MS.L.MISSED_MAIL_ON, name) end
    if not head or #parts == 0 then return nil end
    return head .. " " .. table.concat(parts, " · "), digest and digest.senders or {}
end

function Banner:Height(view)
    if view == "SETTINGS" or not self.text then return 0 end
    return self.HEIGHT
end

function Banner:Create(parent)
    if self.frame then return end
    local Style = MS.JourneyUIStyle
    local frame = CreateFrame("Button", nil, parent)
    frame.background = frame:CreateTexture(nil, "BACKGROUND"); frame.background:SetAllPoints(frame)
    Style:Color(frame.background, "backgroundRaised")
    frame.rule = frame:CreateTexture(nil, "ARTWORK")
    frame.rule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 5, 0); frame.rule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 0)
    frame.rule:SetHeight(1); Style:Color(frame.rule, "borderMuted")
    frame.close = CreateFrame("Button", nil, frame)
    frame.close:SetSize(28, self.HEIGHT); frame.close:SetPoint("RIGHT", frame, "RIGHT", -Style.space.sm, 0)
    frame.close.label = frame.close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Style:Body(frame.close.label, "SECONDARY", "textSecondary"); frame.close.label:SetPoint("CENTER", frame.close, "CENTER")
    frame.close.label:SetText("×")
    Style:Link(frame.close, frame.close.label)
    frame.close:SetScript("OnClick", function() Banner:Dismiss() end)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Style:Body(frame.text, "SECONDARY", "textPrimary")
    frame.text:SetJustifyH("LEFT"); frame.text:SetWordWrap(false); frame.text:SetMaxLines(1)
    frame.text:SetPoint("LEFT", frame, "LEFT", Style.space.md, 0)
    frame.text:SetPoint("RIGHT", frame.close, "LEFT", -Style.space.sm, 0)
    -- A click opens the Journey chat when whispers are part of the news.
    frame:SetScript("OnClick", function() Banner:OpenChat() end)
    frame:SetScript("OnEnter", function(owner) Banner:ShowTooltip(owner) end)
    frame:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    frame:Hide()
    self.frame = frame
end

function Banner:OpenChat()
    local digest, chat = Missed:Pending(), MS.JourneyChatView
    if not digest or not digest.counts.WHISPER or not chat or not chat.shown then return end
    chat:SetCollapsed(false)
end

function Banner:ShowTooltip(owner)
    local tip, senders = _G.GameTooltip, self.senders or {}
    if not tip or #senders == 0 then return end
    tip:SetOwner(owner, "ANCHOR_BOTTOM")
    tip:SetText(string.format(MS.L.MISSED_FROM, table.concat(senders, ", ")), 1, .82, 0, 1, true)
    tip:Show()
end

function Banner:Dismiss()
    Missed:Dismiss()
    self.ready, self.mailOn, self.login = nil, nil, nil
    self:Update()
end

-- Recomputes the sentence; the views are laid out again when the band appears or goes.
function Banner:Update()
    local text, senders
    if Enabled() and not Missed:IsAway() and Call(_G.InCombatLockdown) ~= true then text, senders = self:Text() end
    local changed = (text == nil) ~= (self.text == nil)
    self.text, self.senders = text, senders
    if self.frame and text then self.frame.text:SetText(text) end
    if changed then
        local Journey = MS.JourneyWorkspace
        if Journey and Journey.header and Journey.view then Journey:LayoutView(Journey.view) end
    end
    return text
end

function Banner:Layout(rect)
    if not self.frame then return end
    if not rect or rect.height <= 0 then self.frame:Hide(); return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", MS.Workspace.frame, "BOTTOMLEFT", rect.x, rect.y)
    self.frame:SetSize(rect.width, rect.height)
    if self.text then self.frame.text:SetText(self.text) end
    self.frame:Show()
end

-- Once, from the Journey startup, before the character list saves this login.
function Banner:Start()
    if self.events then return end
    local store = MS.Database and MS.Database:Get()
    local roster = store and type(store.journey) == "table" and store.journey.roster
    local identity = MS.JourneyCharacterIdentity and MS.JourneyCharacterIdentity:Resolve()
    local mine = type(roster) == "table" and type(roster.characters) == "table" and type(identity) == "table"
        and roster.characters[identity.key]
    self.hadMail = Call(_G.HasNewMail) == true
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, ...) Banner:OnEvent(event, ...) end)
    for _, event in ipairs(EVENTS) do pcall(self.events.RegisterEvent, self.events, event) end
    MS.JourneySettings:Listen(function(key) if key == "showMissedBanner" or key == "broadcastMode" then Banner:Update() end end)
    self:Login(type(mine) == "table" and mine.seen or nil)
end

MS.JourneySettings:AddExternalToggle({ id = "showMissedBanner", label = MS.L.JOURNEY_SETTING_showMissedBanner,
    hint = MS.L.JOURNEY_SETTINGS_MISSED_HINT,
    get = function() return Enabled() end,
    set = function(value) MS.JourneySettings:Set("showMissedBanner", value == true) end })
