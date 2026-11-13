local MS = _G.MS
MS.Active = MS.Active or {}
-- Lifecycle and wiring for the active experiences (Sur mes pas, Contrat). Addon-only: no
-- Companion, no network, no second screen required. Journey appears in the game only when it has
-- something to show; on a WORKSPACE it uses it, with the same behaviour.
local A = MS.Active

-- Forever can hand addons "secret" values: any inaccessible value is treated as absent before it
-- is compared, stored or used as a key.
function A.Readable(value)
    if value == nil then return nil end
    local check = _G.canaccessvalue
    if type(check) == "function" then
        local ok, accessible = pcall(check, value)
        if not ok or not accessible then return nil end
    end
    return value
end

-- pcall(fn, ...) with every return value filtered through Readable (up to four).
function A.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    local R = A.Readable
    return R(a), R(b), R(c), R(d)
end

-- A readable boolean, or nil when the game did not give one.
function A.Bool(value)
    if value == true or value == false then return value end
    return nil
end

function A.Now()
    local value = A.Call(_G.GetServerTime)
    if type(value) ~= "number" then value = A.Call(_G.time) end
    return type(value) == "number" and value or nil
end

function A.Uptime()
    local value = A.Call(_G.GetTime)
    return type(value) == "number" and value or 0
end

function A:Log(code, fields)
    if self.Diagnostics and self.Diagnostics.root then self.Diagnostics:Log(code, fields) end
end

function A:Say(key, ...)
    local text = MS.L[key]
    if text and select("#", ...) > 0 then text = string.format(text, ...) end
    if text and MS.Diagnostics and MS.Diagnostics.Print then MS.Diagnostics:Print(text) end
end

local function ClientBuild()
    local _, build = A.Call(_G.GetBuildInfo)
    if type(build) == "number" then build = tostring(build) end
    return type(build) == "string" and build ~= "" and #build <= 32 and build or nil
end

-- Evidence holds for one client build; a new build starts unverified again. Without a known build
-- or a writable store it lasts for this session only.
function A:BindEvidence()
    local root, build = not self.Store.readOnly and self.Store.root or nil, ClientBuild()
    local evidence = root and build and root.evidence
    if not evidence or evidence.build ~= build then
        evidence = { build = build }
        if root and build then root.evidence = evidence end
    end
    self.evidence, self.build = evidence, build
end

function A:Evaluate(reason)
    self.caps = self.Capabilities:Evaluate(self.Capabilities:Probe(_G), self.evidence)
    self:Log("CAPABILITY_STATE", { reason = reason, caps = self.Capabilities:Text(self.caps) })
end

-- A capability just seen working on this build becomes READY (never from UNAVAILABLE).
function A:Prove(name, code)
    local evidence = self.evidence
    if not evidence or evidence[name] or not self.caps or self.caps[name] ~= "UNVERIFIED" then return false end
    evidence[name] = true
    self.caps[name] = "READY"
    self:Log("CAPABILITY_PROVEN", { capability = name, evidence = code })
    return true
end

function A:Ready()
    return self.initialized == true and not self.Store.readOnly
end

function A:Initialize()
    self.identity = MS.JourneyCharacterIdentity:Resolve()
    local now = A.Now()
    local root = self.Store:Initialize(_G.AzerothJourneyActiveDB, self.identity.key, now)
    _G.AzerothJourneyActiveDB = root
    if not self.Store.readOnly then
        self.Diagnostics:Bind(root.diagnostics, function() return A.Now() or 0 end)
        self.bucket = self.identity.key and self.Store:Character(self.identity.key, now) or nil
    end
    self:BindEvidence()
    self:Evaluate("LOGIN")
    self.initialized = true
end

-- Components own their events; every call is protected so one failure never breaks the others.
A.components = A.components or {}
function A:Register(name, component) self.components[#self.components + 1] = { name = name, component = component } end

function A:Dispatch(method, ...)
    for _, entry in ipairs(self.components) do
        local fn = entry.component[method]
        if type(fn) == "function" then
            local ok, failure = pcall(fn, entry.component, ...)
            if not ok then self:Log("COMPONENT_ERROR", { component = entry.name, phase = method, reason = tostring(failure) }) end
        end
    end
end

function A:OnEnteringWorld(initial, reloading)
    if not self.initialized then return end
    if not self.sessionBound then
        self.sessionBound = true
        -- A fresh login starts a new card session; a /reload keeps its quota.
        local fresh = initial == true and reloading ~= true
        MS.JourneyCardArbiter:Bind(not self.Store.readOnly and self.Store.root.arbiter or nil, function() return A.Now() or 0 end, fresh)
        self:Log("ACTIVE_SESSION_START", { store = self.Store.status, version = MS.Product and MS.Product.addonVersion,
            build = self.build, initial = fresh })
        -- Continuity is granted only to a /reload the game explicitly confirms.
        self:Dispatch("OnLogin", fresh, A.Bool(A.Readable(reloading)) == true)
    end
    self:Dispatch("OnEnteringWorld", initial, reloading)
end

-- Slash commands ---------------------------------------------------------------------------
A.commands = A.commands or {}

function A:Command(message)
    local word, rest = string.match(message or "", "^[ \t]*([^ \t]*)[ \t]*(.-)[ \t]*$")
    word = string.lower(word or "")
    -- The Journey window does not depend on the Active store: it works when the rest is refused.
    if word == "fenetre" or word == "window" then
        if MS.JourneyWindow then MS.JourneyWindow:Toggle() end
        return
    end
    -- Streamer mode is a display switch: it works when the rest is refused, and in combat.
    if (word == "diffusion" or word == "streamer") and MS.Edition and MS.Edition:Streamer() then
        _G.Hearthside_ToggleBroadcast()
        return
    end
    if not self.initialized then self:Say("ACTIVE_NOT_READY"); return end
    if self.Store.readOnly then self:Say("ACTIVE_STORE_LOCKED"); return end
    local handler = self.commands[word]
    if handler then handler(self, rest)
    else self:Say(MS.Edition and MS.Edition:Streamer() and "ACTIVE_HELP_STREAMER" or "ACTIVE_HELP") end
end

local function Open(view) return function() if A.Panel then A.Panel:Open(view) end end end
A.commands[""] = Open("HOME")
A.commands.pas = Open("SEAL")
A.commands.steps = Open("SEAL")
A.commands.contrat = Open("CONTRACT")
A.commands.contract = Open("CONTRACT")
A.commands.help = function(self) self:Say(MS.Edition and MS.Edition:Streamer() and "ACTIVE_HELP_STREAMER" or "ACTIVE_HELP") end
A.commands.aide = A.commands.help
A.commands.code = function(self, rest)
    if self.Seals then self.Seals:ImportFromText(rest, "COMMAND") end
end

function A:ExportHeader()
    local lines = { "addon " .. tostring(MS.Product and MS.Product.addonVersion) }
    local version, build, _, interface = A.Call(_G.GetBuildInfo)
    lines[#lines + 1] = string.format("client %s %s %s", tostring(version), tostring(build), tostring(interface))
    lines[#lines + 1] = "locale " .. tostring(A.Call(_G.GetLocale))
    lines[#lines + 1] = "store " .. tostring(self.Store.status)
    lines[#lines + 1] = "caps " .. self.Capabilities:Text(self.caps)
    local proven = {}
    for _, name in ipairs(self.Capabilities.order) do if self.evidence and self.evidence[name] then proven[#proven + 1] = name end end
    lines[#lines + 1] = string.format("evidence build=%s %s", tostring(self.evidence and self.evidence.build), table.concat(proven, ","))
    return lines
end

A.commands.diag = function(self, rest)
    if rest == "reset" then
        if self.Diagnostics:Reset() then self:Say("ACTIVE_DIAG_RESET") end
        return
    end
    MS.Diagnostics:ShowCopyableReport(MS.L.ACTIVE_DIAG_TITLE, self.Diagnostics:Export(self:ExportHeader()), "ACTIVE_DIAG",
        MS.L.ACTIVE_DIAG_INSTRUCTION)
end

A.commands.sonde = function(self)
    if self.Probe then
        MS.Diagnostics:ShowCopyableReport(MS.L.ACTIVE_PROBE_TITLE, table.concat(self.Probe:Lines(), "\n"), "ACTIVE_PROBE",
            MS.L.ACTIVE_DIAG_INSTRUCTION)
    end
end
A.commands.probe = A.commands.sonde

A.commands.carte = function()
    if MS.JourneyMapCanvas then
        MS.Diagnostics:ShowCopyableReport(MS.L.ACTIVE_PROBE_TITLE, MS.JourneyMapCanvas:Toggle(), "ACTIVE_MAP_CANVAS",
            MS.L.ACTIVE_DIAG_INSTRUCTION)
    end
end

A.commands.questiedb = function()
    if MS.JourneyQuestieOffers then
        MS.Diagnostics:ShowCopyableReport(MS.L.ACTIVE_PROBE_TITLE, MS.JourneyQuestieOffers:Report(), "ACTIVE_QUESTIE_OFFERS",
            MS.L.ACTIVE_DIAG_INSTRUCTION)
    end
end

SLASH_AZEROTHJOURNEYACTIVE1 = "/aj"
SLASH_AZEROTHJOURNEYACTIVE2 = "/journey"
SLASH_AZEROTHJOURNEYACTIVE3 = "/hearthside"
SlashCmdList.AZEROTHJOURNEYACTIVE = function(message) A:Command(message) end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        local ok, failure = pcall(A.Initialize, A)
        if not ok then A.initialized = false; A.initError = tostring(failure) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        A:OnEnteringWorld(...)
    elseif event == "PLAYER_LOGOUT" then
        if A.initialized then A:Dispatch("OnLogout") end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if A.initialized then A:Dispatch("OnCombat", event == "PLAYER_REGEN_DISABLED") end
    end
end)
