local MS = _G.MS
MS.Community = MS.Community or {}
-- Lifecycle and wiring only. Each component owns its events and must Stop cleanly:
-- a disabled flag or a missing capability leaves no observer, card or traffic behind.
local C = MS.Community
C.components, C.componentOrder, C.started = C.components or {}, C.componentOrder or {}, C.started or {}

function C:Register(name, component)
    if not self.components[name] then self.componentOrder[#self.componentOrder + 1] = name end
    self.components[name] = component
end

-- Forever can hand addons "secret" values. Any inaccessible value is treated as absent,
-- before it is compared, parsed, used as a key or stored.
function C.Readable(value)
    if value == nil then return nil end
    local check = _G.canaccessvalue
    if type(check) == "function" then
        local ok, accessible = pcall(check, value)
        if not ok or not accessible then return nil end
    end
    return value
end

-- pcall(fn, ...) with every return value filtered through Readable (up to eight).
function C.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if not ok then return nil end
    local R = C.Readable
    return R(a), R(b), R(c), R(d), R(e), R(f), R(g), R(h)
end

local function Now()
    local ok, value = pcall(_G.time)
    return ok and type(value) == "number" and value or 0
end
C.Now = Now

function C:Log(code, fields)
    if self.Diagnostics and self.Diagnostics.Log then self.Diagnostics:Log(code, fields) end
end

function C:Initialize()
    self.identity = MS.JourneyCharacterIdentity:Resolve()
    local root = self.Store:Initialize(_G.AzerothJourneyCommunityDB, self.identity.key)
    _G.AzerothJourneyCommunityDB = root
    self.Flags:Bind(not self.Store.readOnly and root.flags or nil)
    if self.Diagnostics and not self.Store.readOnly then self.Diagnostics:Bind(root.diagnostics, Now, self.random) end
    self.bucket = self.identity.key and self.Store:Character(self.identity.key, Now()) or nil
    self:BindEvidence()
    self.initialized = true
    -- COMPLETE diagnostics must expire on time even when nothing else is logged.
    if not self.expiryTicker and _G.C_Timer then
        self.expiryTicker = C_Timer.NewTicker(60, function() if C.Diagnostics.root then C.Diagnostics:CheckExpiry() end end)
    end
    self:Log("COMMUNITY_SESSION_START", { store = self.Store.status, version = MS.Product and MS.Product.addonVersion,
        enabled = self.Flags:Raw("communityEnabled"), character = self.identity.key })
    self:Apply("LOGIN")
end

-- The client build runtime evidence belongs to, or nil when the client cannot say.
local function ClientBuild()
    local _, build = C.Call(_G.GetBuildInfo)
    if type(build) == "number" then build = tostring(build) end
    return type(build) == "string" and build ~= "" and #build <= 32 and build or nil
end

-- Evidence holds for one client build: a new build starts unverified again. Without a known
-- build or a writable store it lasts for this session only.
function C:BindEvidence()
    local root, build = not self.Store.readOnly and self.Store.root or nil, ClientBuild()
    local evidence = root and build and root.evidence
    if not evidence or evidence.build ~= build then
        evidence = { build = build }
        if root and build then root.evidence = evidence end
    end
    self.evidence = evidence
end

-- A capability just seen working becomes READY. Only Capabilities.provable ones, only from
-- UNVERIFIED (never from a missing API or a disabled one), once per build.
function C:Prove(name, code)
    local evidence = self.evidence
    if not evidence or not self.Capabilities.provable[name] or evidence[name] then return false end
    if not self.caps or self.caps[name] ~= "UNVERIFIED" then return false end
    evidence[name] = true
    self:Log("CAPABILITY_PROVEN", { capability = name, evidence = code })
    self:Apply("EVIDENCE")
    return true
end

function C:Context()
    return { community = self, bucket = self.bucket, identity = self.identity, now = Now }
end

function C:Apply(reason)
    if not self.initialized then return end
    local socialBefore = self:IsRunning("AssistTriggers")
    self.caps = self.Capabilities:Evaluate(self.Capabilities:Probe(_G), self.Flags, self.bucket ~= nil, self.evidence)
    self:Log("CAPABILITY_STATE", { reason = reason, caps = self.caps })
    for _, name in ipairs(self.componentOrder) do
        local component = self.components[name]
        local wanted = self.Capabilities:Feature(component.feature, self.caps, self.Flags)
        -- A pending failed stop is retried first, whatever the component is wanted for next.
        if self.started[name] == "STOP_FAILED" then
            local ok, failure = pcall(component.Stop, component, "RETRY")
            if ok then self.started[name] = nil
            else self:Log("COMPONENT_ERROR", { component = name, phase = "STOP", reason = tostring(failure) }) end
        end
        if self.started[name] == "STOP_FAILED" then
            -- Still not stopped: never start it again on top of itself.
        elseif wanted and not self.started[name] then
            local ok, failure = pcall(component.Start, component, self:Context())
            if ok and failure ~= false then
                self.started[name] = true
            else
                -- A partial start may have registered events or timers: always clean up.
                self:Log("COMPONENT_ERROR", { component = name, phase = "START", reason = tostring(failure) })
                local stopped, stopFailure = pcall(component.Stop, component, "START_FAILED")
                self.started[name] = not stopped and "STOP_FAILED" or nil
                if not stopped then self:Log("COMPONENT_ERROR", { component = name, phase = "STOP", reason = tostring(stopFailure) }) end
            end
        elseif not wanted and self.started[name] then
            local ok, failure = pcall(component.Stop, component, reason)
            -- A failed stop stays marked so the next Apply retries it.
            self.started[name] = not ok and "STOP_FAILED" or nil
            if not ok then self:Log("COMPONENT_ERROR", { component = name, phase = "STOP", reason = tostring(failure) }) end
        end
    end
    -- The quest page shows or drops its social action (and an open menu closes) only when the
    -- feature actually starts or stops.
    if self.QuestSocial and self:IsRunning("AssistTriggers") ~= socialBefore then self.QuestSocial:Changed() end
end

function C:StopAll(reason)
    local socialBefore = self:IsRunning("AssistTriggers")
    for index = #self.componentOrder, 1, -1 do
        local name = self.componentOrder[index]
        if self.started[name] then
            local component = self.components[name]
            local ok, failure = pcall(component.Stop, component, reason)
            -- A failed stop stays marked so the next Apply retries it.
            self.started[name] = not ok and "STOP_FAILED" or nil
            if not ok then self:Log("COMPONENT_ERROR", { component = name, phase = "STOP", reason = tostring(failure) }) end
        end
    end
    if self.QuestSocial and socialBefore then self.QuestSocial:Changed() end
end

function C:IsRunning(name) return self.started[name] == true end
function C:IsStopPending(name) return self.started[name] == "STOP_FAILED" end

function C:SetFlag(name, value)
    if self.Store.readOnly or not self.Flags:Set(name, value) then return false end
    self:Log("FLAG_CHANGED", { flag = name, value = value })
    self:Apply("FLAG_" .. name)
    if MS.JourneySettings and MS.JourneySettings.MarkExternalDirty then MS.JourneySettings:MarkExternalDirty() end
    -- Parcours adds or removes its Community lines right away.
    if self.OnMemoriesChanged then self:OnMemoriesChanged() end
    return true
end

local function Say(key, ...)
    local text = MS.L[key]
    if text and select("#", ...) > 0 then text = string.format(text, ...) end
    if MS.Diagnostics and MS.Diagnostics.Print then MS.Diagnostics:Print(text) end
end
C.Say = Say

function C:StatusLines()
    local L, lines = MS.L, {}
    lines[#lines + 1] = string.format(L.COMMUNITY_STATUS_STORE, self.Store.status or "UNKNOWN")
    lines[#lines + 1] = L.COMMUNITY_STATUS_FLAGS
    for _, name in ipairs(self.Flags.order) do
        lines[#lines + 1] = string.format("  %s = %s", name, tostring(self.Flags:IsOn(name)))
    end
    lines[#lines + 1] = L.COMMUNITY_STATUS_CAPABILITIES
    for _, name in ipairs(self.Capabilities.order) do
        lines[#lines + 1] = string.format("  %s %s", name, self.caps and self.caps[name] or "UNKNOWN")
    end
    lines[#lines + 1] = L.COMMUNITY_STATUS_COMPONENTS
    for _, name in ipairs(self.componentOrder) do
        lines[#lines + 1] = string.format("  %s %s", name, self.started[name] and "RUNNING" or "STOPPED")
    end
    return lines
end

C.commands = C.commands or {}
function C:Command(message)
    if not self.initialized then Say("COMMUNITY_NOT_READY"); return end
    local word, rest = string.match(message or "", "^[ \t]*([^ \t]*)[ \t]*(.-)[ \t]*$")
    word = string.lower(word or "")
    if word == "on" or word == "off" then
        if self:SetFlag("communityEnabled", word == "on") then
            Say(word == "on" and "COMMUNITY_ENABLED" or "COMMUNITY_DISABLED")
        else Say("COMMUNITY_STORE_LOCKED") end
    elseif word == "flag" then
        local name, value = string.match(rest, "^([^ \t]+)[ \t]+([^ \t]+)$")
        if name and self.Flags.defaults[name] ~= nil and (value == "on" or value == "off")
            and self:SetFlag(name, value == "on") then
            Say("COMMUNITY_FLAG_SET", name, value)
        else Say("COMMUNITY_FLAG_HELP") end
    elseif word == "status" or word == "" then
        MS.Diagnostics:ShowCopyableReport(MS.L.COMMUNITY_STATUS_TITLE, table.concat(self:StatusLines(), "\n"), "COMMUNITY_STATUS")
    elseif self.commands[word] then
        self.commands[word](self, rest)
    else
        Say("COMMUNITY_HELP")
    end
end

function C:ExportHeader()
    local lines = { "addon " .. tostring(MS.Product and MS.Product.addonVersion) }
    local ok, version, build, _, interface = pcall(_G.GetBuildInfo)
    if ok then lines[#lines + 1] = string.format("client %s %s %s", tostring(version), tostring(build), tostring(interface)) end
    local okLocale, locale = pcall(_G.GetLocale)
    lines[#lines + 1] = "locale " .. tostring(okLocale and locale)
    lines[#lines + 1] = "store " .. tostring(self.Store.status)
    local flags = {}
    for _, name in ipairs(self.Flags.order) do flags[#flags + 1] = name .. "=" .. tostring(self.Flags:IsOn(name)) end
    lines[#lines + 1] = "flags " .. table.concat(flags, ",")
    local caps = {}
    for _, name in ipairs(self.Capabilities.order) do caps[#caps + 1] = name .. "=" .. tostring(self.caps and self.caps[name]) end
    lines[#lines + 1] = "caps " .. table.concat(caps, ",")
    local proven = {}
    for _, name in ipairs(self.Capabilities.order) do if self.evidence and self.evidence[name] then proven[#proven + 1] = name end end
    lines[#lines + 1] = string.format("evidence build=%s %s", tostring(self.evidence and self.evidence.build), table.concat(proven, ","))
    local running = {}
    for _, name in ipairs(self.componentOrder) do running[#running + 1] = name .. "=" .. (self.started[name] and "RUNNING" or "STOPPED") end
    lines[#lines + 1] = "components " .. table.concat(running, ",")
    return lines
end

C.commands.diag = function(self, rest)
    local D = self.Diagnostics
    local sub, value = string.match(rest or "", "^([^ \t]*)[ \t]*([^ \t]*)")
    if sub == "complete" and (value == "on" or value == "off") then
        if D:SetComplete(value == "on") then
            Say(value == "on" and "COMMUNITY_DIAG_COMPLETE_ON" or "COMMUNITY_DIAG_COMPLETE_OFF")
        else Say("COMMUNITY_STORE_LOCKED") end
    elseif sub == "reset" then
        if D:Reset() then Say("COMMUNITY_DIAG_RESET") end
    elseif sub == "" then
        MS.Diagnostics:ShowCopyableReport(MS.L.COMMUNITY_DIAG_TITLE, D:Export(self:ExportHeader()), "COMMUNITY_DIAG",
            MS.L.COMMUNITY_DIAG_INSTRUCTION)
    else Say("COMMUNITY_DIAG_HELP") end
end

-- Forget this character's Community memories and peer ledger (flags and journal stay).
C.commands.forget = function(self, rest)
    if rest ~= "confirm" then Say("COMMUNITY_FORGET_CONFIRM"); return end
    if not self.identity then return end
    self:StopAll("FORGET")
    -- No component may keep a reference to the old bucket: refuse while a stop is still pending.
    for _, name in ipairs(self.componentOrder) do
        if self.started[name] == "STOP_FAILED" then
            self:Log("COMPONENT_ERROR", { component = name, phase = "FORGET", reason = "STOP_PENDING" })
            self:Apply("FORGET_ABORTED")
            Say("COMMUNITY_FORGET_FAILED")
            return
        end
    end
    if self.Store:Forget(self.identity.key) then
        self.bucket = self.Store:Character(self.identity.key, Now())
        self:Log("MEMORY_FORGOTTEN", { scope = "CHARACTER" })
        self:Apply("FORGET")
        if self.OnMemoriesChanged then self:OnMemoriesChanged() end
        Say("COMMUNITY_FORGOTTEN")
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local ok, failure = pcall(C.Initialize, C)
        if not ok then C.initialized = false; C.initError = tostring(failure) end
    elseif event == "PLAYER_LOGOUT" then
        C:StopAll("LOGOUT")
        if C.Diagnostics.root then C.Diagnostics:CheckExpiry() end
    end
end)
