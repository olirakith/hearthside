local MS = _G.MS

-- Private-alpha support view. Readers use existing caches; no audits, writes,
-- layout-name disclosure, saved log or native geometry discovery.
MS.PlayerDiagnostic = { schema = 2, limitationsVersion = 2, capacity = 20,
    entries = {}, head = 1, count = 0, transitions = {}, hooks = {} }
local D = MS.PlayerDiagnostic
-- Accepted limitations, outside the health policy.
D.acceptedLimitations = { SCREEN_API_SURFACES = "ACCEPTED (tooltips/popups may cross GAME's edge)",
    LEGACY_MINIMAL = "ACCEPTED (unsupported topologies keep the full-span HUD)" }
local runtimeStates = { ACTIVE=true, DISABLED=true, ENABLING=true, RESTORING=true, FAILED=true }
local modes = { VIEWPORT=true, LEGACY=true, UNRESOLVED=true }
local viewportStates = { APPLIED=true, NATIVE=true, RESTORE_FAILED=true }
local migrationStates = { NEEDED=true, COMPLETED=true, NOT_NEEDED=true, NOT_APPLICABLE=true, UNKNOWN=true }
local reasons = {}
for code in string.gmatch([[ELIGIBLE_TOPOLOGY PLAYER_DISABLED TOPOLOGY_GAME_NOT_ORIGIN_FULL_HEIGHT
    TOPOLOGY_WORKSPACE_NOT_RIGHT NO_GENERATED_LAYOUT UI_SCALE_NOT_SETTLED PLAN_SCALE_INCOHERENT
    SPAN_NOT_ACTIVE AUTO_ENABLE_DISABLED COMBAT RESTORE_NOT_EXACT
    ERROR_GENERATED_MISSING ERROR_GENERATED_LAYOUT DISPLAY_SIZE_CHANGED UI_SCALE_CHANGED
    ERROR_CONFIG ERROR_METRICS ERROR_VIEWPORT_APPLY ERROR_UIPARENT_VIEWPORT ERROR_GAMEUI_CLOSURE
    ERROR_JOURNEY_CREATE GAME_ANCHOR_UNAVAILABLE]], "%S+") do reasons[code] = true end
for code in string.gmatch("PIXEL_NOT_READY PIXEL_SCALE_UNAVAILABLE PIXEL_EMITTER_HIDDEN PIXEL_STATE_UNAVAILABLE", "%S+") do reasons[code]=true end
local function Enum(value, allowed) return allowed[value] and value or "UNKNOWN" end
local function Number(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge and value or nil
end
local function Reason(value)
    if value == nil then return nil end
    -- Only declared codes survive. Never echo exception text or suffixes (which
    -- may contain paths, frame names, layout names or arbitrary provider data).
    local code = type(value) == "string" and string.match(value, "^([A-Z_]+)")
    return reasons[code] and code or "DETAIL_OMITTED"
end
local function Dimensions(rect)
    local w, h = rect and Number(rect.width), rect and Number(rect.height)
    return w and h and string.format("%.0f x %.0f", w, h) or "unknown"
end
local function Version(value)
    return type(value) == "string" and #value <= 48
        and string.match(value, "^%d+%.%d+%.%d+[%w%.%-]*$") and value or "unknown"
end
local function Yes(value) return value == nil and "unknown" or value and "yes" or "no" end

function D:GetVersions()
    local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local buildID = metadata and metadata(MS.addonName, "X-BuildIdentifier")
    -- Optional release metadata only; the current release does not ship this.
    if type(buildID) ~= "string" or #buildID > 120
        or not string.match(buildID, "^%d+%.%d+%.%d+%-alpha[%w%.%-]*%-%x+%-%x+$") then buildID = "unavailable" end
    local _, build, _, interface
    if type(GetBuildInfo) == "function" then _, build, _, interface = GetBuildInfo() end
    return { addon = Version(MS.Product and MS.Product.addonVersion), companion = "unknown-version",
        protocol = Number(MS.PixelHandshake and MS.PixelHandshake.VERSION),
        build = type(build) == "string" and string.match(build, "^%d+$") and build or "unknown",
        interface = Number(interface), buildID = buildID }
end

local function Integer(value, maximum)
    value=Number(value)
    return value and value >= 0 and value <= maximum and value == math.floor(value) and value or nil
end
function D:ReadPixelTransport()
    local ph=MS.PixelHandshake or {}
    local columns,rows,cell=Integer(ph.COLUMNS,8192),Integer(ph.ROWS,8192),Integer(ph.CELL_SIZE,8192)
    local geometry=columns and rows and cell and columns > 0 and rows > 0 and cell > 0
    local shown
    if ph.frame and type(ph.frame.IsShown)=="function" then
        local ok,value=pcall(ph.frame.IsShown,ph.frame)
        if ok and type(value)=="boolean" then shown=value end
    end
    local message=ph.message ~= nil and ph.message == ph.TYPE_READY and "READY"
        or ph.message ~= nil and ph.message == ph.TYPE_LEAVING and "LEAVING" or "UNKNOWN"
    local state=shown == false and "HIDDEN" or shown == true and message or "UNKNOWN"
    local epoch,sequence,protocol=Integer(ph.epoch,65535),Integer(ph.sequence,65535),Integer(ph.VERSION,255)
    local scaled,suppression
    if type(ph.scaled)=="boolean" then scaled=ph.scaled end
    if type(ph.screenshot)=="boolean" then suppression=ph.screenshot elseif ph.screenshot == nil then suppression=false end
    local reason
    if not ph.started or message == "UNKNOWN" then reason="PIXEL_NOT_READY"
    elseif ph.scaled == false then reason="PIXEL_SCALE_UNAVAILABLE"
    elseif ph.scaled ~= true or not geometry or epoch == nil or sequence == nil or protocol == nil or protocol < 1 or shown == nil then reason="PIXEL_STATE_UNAVAILABLE"
    elseif not shown and ph.screenshot ~= true then reason="PIXEL_EMITTER_HIDDEN" end
    return { state=state, message=message, protocol=protocol, epoch=epoch, sequence=sequence,
        grid=geometry and string.format("%dx%d",columns,rows) or "unknown", cell=geometry and cell or nil,
        configuredRegion=geometry and string.format("%dx%d",columns*cell,rows*cell) or "unknown",
        physicalRegion=geometry and ph.scaled == true and string.format("%dx%d",columns*cell,rows*cell) or "unknown",
        scaled=scaled, suppression=suppression,
        -- scaled is the emitter's physical-height scaling admission flag, not
        -- independent measurement certification. Generated/Layout has geometry
        -- only, with no existing inbound Companion reader-state field.
        certification="UNKNOWN", reader="UNKNOWN", reason=reason }
end

function D:Read()
    local runtime = MS.Runtime or {}
    local layout, _, layoutError
    if MS.Config then layout, _, layoutError = MS.Config:GetLayout() end
    local contract = MS.GameSurfaceContract and MS.GameSurfaceContract:Get()
    local safety = contract and contract.safety
    local mode, viewport, watch = MS.UIParentMode or {}, MS.UIParentViewport or {}, MS.EditModeWatch or {}
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    local data = { runtime=Enum(runtime.state, runtimeStates), operational=runtime.enabled == true,
        migrationConflict=loaded and loaded("MultiScreen_Forever") == true or false, pixel=self:ReadPixelTransport(),
        runtimeReason=Reason(runtime.invalidatedReason or runtime.lastEnableError),
        layoutValid=layout ~= nil, layoutReason=Reason(layoutError), span=Dimensions(layout and layout.span),
        game=Dimensions(layout and layout.game), workspace=Dimensions(layout and layout.workspace),
        contract={ ready=contract ~= nil, valid=safety and safety.validTopology == true and safety.anchorMatches == true or false,
            topology=safety and safety.validTopology == true or false,
            generation=Number(contract and contract.generation) },
        mode={ mode=Enum(mode.mode, modes), reason=Reason(mode.reason), viewport=Enum(viewport.state, viewportStates),
            waitingForScale=runtime.waitingForScale == true },
        edit={ editing=watch.editing == true, migration=Enum(watch.state, migrationStates) } }
    return data
end

-- Pure health policy. Accepted limitations never participate here.
function D:Health(data)
    if data.migrationConflict then return "ERROR", "PLAYER_DIAG_MIGRATION" end
    if not data.layoutValid or not data.contract.ready or not data.contract.valid then return "ERROR", "PLAYER_DIAG_GAME_INVALID" end
    if data.runtime == "FAILED" or data.runtimeReason or data.mode.viewport == "RESTORE_FAILED" then return "ERROR", "PLAYER_DIAG_UNSAFE" end
    if not data.operational then return "DEGRADED", "PLAYER_DIAG_INACTIVE" end
    if data.edit.migration == "NEEDED" then return "DEGRADED", "PLAYER_DIAG_PROFILE" end
    if data.pixel.reason then return "DEGRADED", data.pixel.reason == "PIXEL_SCALE_UNAVAILABLE" and "PLAYER_DIAG_PIXEL_SCALE"
        or data.pixel.reason == "PIXEL_EMITTER_HIDDEN" and "PLAYER_DIAG_PIXEL_HIDDEN" or "PLAYER_DIAG_PIXEL_UNAVAILABLE" end
    return "OK"
end

local categories = { Runtime=true, GAME=true, Mode=true, EditMode=true, Recovery=true, Combat=true, Health=true, Migration=true, PixelTransport=true }
local events = { ACTIVE=true, DISABLED=true, ENABLING=true, RESTORING=true, FAILED=true, UNKNOWN=true,
    READY=true, INVALID=true, CHANGED=true, RECOVERED=true, PENDING=true, START=true, END=true,
    OK=true, DEGRADED=true, ERROR=true, CONFLICT=true, CLEAR=true, LEAVING=true, HIDDEN=true,
    VIEWPORT=true, LEGACY=true, UNRESOLVED=true, NEEDED=true, COMPLETED=true, NOT_NEEDED=true, NOT_APPLICABLE=true }
local function Now() return type(GetTime) == "function" and Number(GetTime()) or 0 end
function D:Record(category, event, reason)
    if not categories[category] or not events[event] then return end
    reason = Reason(reason)
    local signature = event .. ":" .. (reason or "")
    if self.transitions[category] == signature then return end
    self.transitions[category] = signature
    self.started = self.started or Now()
    local item = { at=math.max(0, Now()-self.started), category=category, event=event, reason=reason }
    local index = (self.head + self.count - 1) % self.capacity + 1
    if self.count == self.capacity then index=self.head; self.head=self.head % self.capacity + 1
    else self.count=self.count+1 end
    self.entries[index] = item
end
function D:GetEvents()
    local result = {}
    for offset=0,self.count-1 do
        local item=self.entries[(self.head+offset-1)%self.capacity+1]
        result[#result+1]={ at=item.at, category=item.category, event=item.event, reason=item.reason }
    end
    return result
end
function D:Capture()
    local data=self:Read()
    self:Record("Runtime", data.runtime, data.runtimeReason)
    if self.gameGeneration ~= data.contract.generation or self.gameValid ~= data.contract.valid then
        local gameState = data.contract.valid and "READY" or "INVALID"
        if self.gameGeneration and data.contract.valid then gameState="CHANGED" end
        -- A new generation is meaningful even when the preceding event was CHANGED.
        self.transitions.GAME=nil
        self:Record("GAME", gameState, data.layoutReason)
    end
    self.gameValid=data.contract.valid
    self.gameGeneration=data.contract.generation
    self:Record("Mode", data.mode.mode, data.mode.reason)
    self:Record("EditMode", data.edit.migration)
    self:Record("Migration", data.migrationConflict and "CONFLICT" or "CLEAR")
    self:Record("PixelTransport", data.pixel.state, data.pixel.reason)
    local status, reason=self:Health(data)
    self:Record("Health", status)
    if status ~= self.status or reason ~= self.reason then
        self.status,self.reason=status,reason
        if MS.JourneySettings and MS.JourneySettings.RefreshDiagnostic then MS.JourneySettings:RefreshDiagnostic() end
    end
    if MS.DiagnosticSnapshots then MS.DiagnosticSnapshots:Signal("surfaces","CAPTURE") end
    return data,status,reason
end

function D:BuildReport()
    local data,status,reason=self:Capture()
    local v=self:GetVersions()
    local L=MS.L
    local lines={ L.PLAYER_DIAG_REPORT_TITLE, "Schema: " .. self.schema, "", "Status: " .. status }
    if reason then lines[#lines+1]=L[reason] end
    local function Section(name) lines[#lines+1]=""; lines[#lines+1]=L[name] end
    Section("PLAYER_DIAG_VERSIONS")
    lines[#lines+1]="Product: " .. L.PRODUCT_NAME
    lines[#lines+1]="Addon: " .. v.addon
    lines[#lines+1]="Companion: " .. v.companion .. " (" .. L.PLAYER_DIAG_PRESENCE_UNKNOWN .. ")"
    lines[#lines+1]="Protocol: " .. (v.protocol or "unknown")
    lines[#lines+1]="WoW build/interface: " .. v.build .. "/" .. (v.interface or "unknown")
    lines[#lines+1]="Release: " .. v.addon .. "; BuildIdentifier: " .. v.buildID
    lines[#lines+1]="Runtime: " .. data.runtime .. (data.runtimeReason and " (" .. data.runtimeReason .. ")" or "")
    if data.migrationConflict then lines[#lines+1]="Migration: CONFLICT" end
    local pixel=data.pixel
    lines[#lines+1]=""
    lines[#lines+1]=string.format(L.PLAYER_DIAG_PIXEL_SUMMARY,pixel.state,pixel.protocol or "unknown",
        pixel.physicalRegion,pixel.cell or "unknown",pixel.sequence or "unknown")
    lines[#lines+1]=string.format(L.PLAYER_DIAG_PIXEL_DETAIL,pixel.grid,pixel.epoch or "unknown",pixel.configuredRegion,
        Yes(pixel.scaled),pixel.certification,Yes(pixel.suppression),pixel.reader)
    if pixel.reason then lines[#lines+1]="Reason: " .. pixel.reason end
    Section("PLAYER_DIAG_DISPLAY")
    lines[#lines+1]="Span: " .. data.span .. "; GAME: " .. data.game .. "; WORKSPACE: " .. data.workspace
    lines[#lines+1]="Topology valid: " .. Yes(data.layoutValid and data.contract.topology)
    Section("PLAYER_DIAG_CONTRACT")
    lines[#lines+1]="Generation: " .. (data.contract.generation or "unknown")
    lines[#lines+1]="Ready: " .. Yes(data.contract.ready) .. "; valid: " .. Yes(data.contract.valid)
    if not data.contract.valid then lines[#lines+1]="Reason: " .. (data.layoutReason or "GAME_ANCHOR_UNAVAILABLE") end
    Section("PLAYER_DIAG_MODE")
    lines[#lines+1]="Mode: " .. data.mode.mode .. (data.mode.reason and " (" .. data.mode.reason .. ")" or "")
        .. "; UIParent: " .. data.mode.viewport .. "; waitingForScale: " .. Yes(data.mode.waitingForScale)
    Section("PLAYER_DIAG_EDIT")
    lines[#lines+1]="Editing: " .. Yes(data.edit.editing) .. "; layout migration: " .. data.edit.migration
    Section("PLAYER_DIAG_LIMITATIONS")
    lines[#lines+1]="Accepted limitations v" .. self.limitationsVersion
    for _, key in ipairs({"PLAYER_DIAG_LIMIT_SCREEN_API", "PLAYER_DIAG_LIMIT_COMPAT"}) do lines[#lines+1]="- " .. L[key] end
    Section("PLAYER_DIAG_EVENTS")
    for _, item in ipairs(self:GetEvents()) do
        lines[#lines+1]=string.format("+%.1fs %s %s%s", item.at, item.category, item.event, item.reason and " (" .. item.reason .. ")" or "")
    end
    return table.concat(lines,"\n")
end
function D:Open()
    MS.Diagnostics:ShowCopyableReport(MS.L.PLAYER_DIAG_TITLE, self:BuildReport(), "PLAYER_DIAGNOSTIC", MS.L.PLAYER_DIAG_COPY_HINT)
end

function D:ScheduleCapture()
    if self.captureScheduled then return end
    if C_Timer and type(C_Timer.After) == "function" then
        self.captureScheduled=true
        local scheduled=pcall(C_Timer.After,0,function()
            self.captureScheduled=false
            pcall(self.Capture,self)
        end)
        if scheduled then return end
        self.captureScheduled=false
    end
    self:Capture()
end

-- Posthooks on Journey's own tables only.
function D:Install()
    if type(hooksecurefunc) ~= "function" then return end
    local function Hook(object, method, callback)
        if not object or type(object[method]) ~= "function" then return end
        self.hooks[object]=self.hooks[object] or {}
        if self.hooks[object][method] then return end
        self.hooks[object][method]=pcall(hooksecurefunc,object,method,function(...)
            -- Support instrumentation must never break an owner/recovery callback.
            pcall(callback or self.ScheduleCapture,self,...)
        end)
    end
    for _, method in ipairs({"CompleteEnable","QueueRestore","FailEnable","RequestFailSafeDisable"}) do Hook(MS.Runtime,method) end
    Hook(MS.GameSurfaceContract,"Refresh")
    Hook(MS.UIParentViewport,"Apply")
    Hook(MS.UIParentViewport,"Restore")
    Hook(MS.EditModeWatch,"Refresh")
    Hook(MS.Recovery,"Restore",function(self)
        self:Record("Recovery", MS.Recovery.pending and "PENDING" or MS.Runtime.state == "DISABLED" and "RECOVERED" or "FAILED")
        self:ScheduleCapture()
    end)
end
if type(CreateFrame) == "function" then
    local frame=CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_LOGIN","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED",
        "PLAYER_ENTERING_WORLD","LOADING_SCREEN_DISABLED","PLAYER_CAMPING","PLAYER_QUITING","LOGOUT_CANCEL","PLAYER_LOGOUT",
        "DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED","SCREENSHOT_STARTED","SCREENSHOT_SUCCEEDED","SCREENSHOT_FAILED"}) do pcall(frame.RegisterEvent,frame,event) end
    frame:SetScript("OnEvent",function(_,event)
        D:Install()
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            D:Record("Combat",event == "PLAYER_REGEN_DISABLED" and "START" or "END")
        end
        pcall(D.ScheduleCapture,D)
    end)
    D.frame=frame
end
D:Install()
