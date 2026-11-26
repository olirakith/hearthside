local MS = _G.MS

-- Faces for the Parcours: round creature portraits, an on-demand boss viewer and the player's model.
-- On this client a model set from a unit reads display ID 0, so a creature's look is found from its
-- npcID through one offscreen PlayerModel (ClearModel, SetCreature, wait for the load, GetDisplayInfo)
-- and kept account-wide. Everything here is decoration: a portrait that never resolves shows an icon.
MS.JourneyFaces = { CAP = 600, POLL = .25, TIMEOUT = 3, SPACING = .25, RETRY = 300, STAGE_WAIT = .5,
    TURN_SECONDS = 5, TURN_FROM = -.5, TURN_TO = .5, CHEER_SECONDS = 2.5, HERO_FACING = .35,
    queue = {}, pending = {}, failed = {}, heroes = setmetatable({}, { __mode = "k" }) }
local Faces = MS.JourneyFaces

local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function Hidden(value) return type(_G.issecretvalue) == "function" and issecretvalue(value) == true end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end
local function Now() return Call(_G.GetTime) or 0 end
local function Setting(key) return MS.JourneySettings and MS.JourneySettings:Get(key) end
local function Reduced() return Setting("reducedMotion") == true end
local function Timer(delay, fn)
    local timer = _G.C_Timer
    if type(timer) ~= "table" or type(timer.After) ~= "function" then return false end
    return (pcall(timer.After, delay, fn))
end
local function Color(token, fallback)
    local style = MS.JourneyUIStyle
    local color = style and style.colors and style.colors[token]
    if type(color) == "table" then return color[1], color[2], color[3] end
    return fallback[1], fallback[2], fallback[3]
end

-- A positive whole number that is not secret: an npcID or a display ID.
local function ValidId(value)
    if Hidden(value) then return nil end
    value = tonumber(value)
    if not value or value ~= value or value <= 0 or value >= 2147483648 or value ~= math.floor(value) then return nil end
    return value
end
Faces.ValidId = ValidId

-- The saved cache, cleaned once per table: bad keys or values from an old or corrupt file are dropped.
function Faces:Store()
    local db = MS.Database and Call(MS.Database.Get, MS.Database)
    local store
    if type(db) == "table" then
        db.journey = type(db.journey) == "table" and db.journey or {}
        if type(db.journey.faces) ~= "table" then db.journey.faces = {} end
        store = db.journey.faces
    else
        self.memory = self.memory or {}
        store = self.memory
    end
    if self.bound ~= store then
        local count, bad = 0, {}
        for key, value in pairs(store) do
            if ValidId(key) ~= key or not ValidId(value) then bad[#bad + 1] = key else count = count + 1 end
        end
        for _, key in ipairs(bad) do store[key] = nil end
        self.bound, self.count = store, count
    end
    return store
end

function Faces:Get(npcID)
    npcID = ValidId(npcID)
    if not npcID then return nil end
    return self:Store()[npcID]
end

function Faces:Remember(npcID, displayID)
    local store = self:Store()
    if store[npcID] == nil then
        self.count = self.count + 1
        -- Over the cap, any other entry goes: a forgotten face is simply looked up again.
        if self.count > self.CAP then
            for key in pairs(store) do
                if key ~= npcID then store[key] = nil; self.count = self.count - 1; break end
            end
        end
    end
    store[npcID] = displayID
end

function Faces:NpcFromUnit(unit)
    local guid = Call(_G.UnitGUID, unit)
    if Hidden(guid) or type(guid) ~= "string" then return nil end
    local parts = {}
    for part in guid:gmatch("[^%-]+") do parts[#parts + 1] = part end
    if parts[1] ~= "Creature" and parts[1] ~= "Vehicle" then return nil end
    return ValidId(parts[6])
end

-- The offscreen model that turns npcIDs into display IDs. It stays shown at zero alpha: a hidden
-- model may never load.
function Faces:Model()
    if self.model == nil then
        local ok, model = pcall(CreateFrame, "PlayerModel", nil, _G.UIParent)
        if ok and model then
            pcall(model.SetSize, model, 64, 64)
            pcall(model.SetPoint, model, "BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 0, 0)
            pcall(model.SetAlpha, model, 0)
            pcall(model.SetScript, model, "OnModelLoaded", function()
                local current = Faces.current
                if current then Faces:Check(current.serial, false) end
            end)
            self.model = model
        else
            self.model = false
        end
    end
    return self.model or nil
end

function Faces:Resolve(npcID, callback)
    local done = type(callback) == "function" and callback or function() end
    npcID = ValidId(npcID)
    if not npcID then pcall(done, nil); return end
    local cached = self:Get(npcID)
    if cached then pcall(done, cached); return end
    local failedAt = self.failed[npcID]
    if failedAt and Now() - failedAt < self.RETRY then pcall(done, nil); return end
    local waiting = self.pending[npcID]
    if waiting then waiting[#waiting + 1] = done; return end
    self.pending[npcID] = { done }
    self.queue[#self.queue + 1] = npcID
    self:Pump()
end

-- One creature at a time, at most four starts per second.
function Faces:Pump()
    if self.current or self.waking or #self.queue == 0 then return end
    local wait = self.lastStart and self.SPACING - (Now() - self.lastStart) or 0
    if wait > 0 then
        self.waking = Timer(wait, function() Faces.waking = nil; Faces:Pump() end)
        if self.waking then return end
    end
    self.serial = (self.serial or 0) + 1
    self.current = { npcID = table.remove(self.queue, 1), serial = self.serial, waited = 0 }
    self.lastStart = Now()
    local model = self:Model()
    -- Clear first: a creature not loaded yet can leave the previous one on the frame.
    if not model or not pcall(model.ClearModel, model) or not pcall(model.SetCreature, model, self.current.npcID) then
        return self:Finish(nil)
    end
    self:Poll(self.serial)
end

function Faces:Poll(serial)
    if not Timer(self.POLL, function() Faces:Check(serial, true) end) then self:Finish(nil) end
end

function Faces:Check(serial, polled)
    local current = self.current
    if not current or current.serial ~= serial then return end
    local model = self.model
    local displayID = model and ValidId(Call(model.GetDisplayInfo, model))
    if displayID then return self:Finish(displayID) end
    if not polled then return end
    current.waited = current.waited + self.POLL
    if current.waited >= self.TIMEOUT then return self:Finish(nil) end
    self:Poll(serial)
end

function Faces:Finish(displayID)
    local current = self.current
    self.current = nil
    if not current then return end
    local npcID = current.npcID
    if displayID then self:Remember(npcID, displayID); self.failed[npcID] = nil
    else self.failed[npcID] = Now() end
    local callbacks = self.pending[npcID] or {}
    self.pending[npcID] = nil
    for _, callback in ipairs(callbacks) do pcall(callback, displayID) end
    self:Pump()
end

function Faces:GetStatus()
    self:Store()
    return { cached = self.count, queued = #self.queue, busy = self.current ~= nil }
end

-- Round portrait ---------------------------------------------------------------------------------

local Portrait = {}
Portrait.__index = Portrait

local function ShowIcon(portrait, texture)
    local face = portrait.face
    pcall(face.SetTexture, face, texture or FALLBACK_ICON)
    -- Crop the icon's own border so the round mask shows only the picture.
    pcall(face.SetTexCoord, face, .08, .92, .08, .92)
end

local function ShowDisplay(portrait, displayID)
    displayID = ValidId(displayID)
    if not displayID or type(_G.SetPortraitTextureFromCreatureDisplayID) ~= "function" then return false end
    local face = portrait.face
    pcall(face.SetTexCoord, face, 0, 1, 0, 1)
    return (pcall(SetPortraitTextureFromCreatureDisplayID, face, displayID))
end

local function ResizePortrait(portrait, size)
    portrait.frame:SetSize(size + 4, size + 4)
    portrait.back:SetSize(size, size)
    portrait.face:SetSize(size, size)
end

function Portrait:SetNPC(npcID)
    self.serial = self.serial + 1
    local serial = self.serial
    if ShowDisplay(self, Faces:Get(npcID)) then return end
    ShowIcon(self)
    if not ValidId(npcID) then return end
    Faces:Resolve(npcID, function(displayID)
        if self.serial == serial and displayID then ShowDisplay(self, displayID) end
    end)
end

function Portrait:SetDisplay(displayID)
    self.serial = self.serial + 1
    if not ShowDisplay(self, displayID) then ShowIcon(self) end
end

function Portrait:SetUnit(unit)
    self.serial = self.serial + 1
    local exists = Call(_G.UnitExists, unit)
    local face = self.face
    if not Hidden(exists) and exists == true then
        pcall(face.SetTexCoord, face, 0, 1, 0, 1)
        if pcall(_G.SetPortraitTexture, face, unit) then return end
    end
    ShowIcon(self)
end

function Portrait:SetIcon(texture)
    self.serial = self.serial + 1
    ShowIcon(self, texture)
end

function Portrait:SetBeaten(beaten)
    beaten = beaten == true
    pcall(self.face.SetDesaturated, self.face, beaten)
    self.frame:SetAlpha(beaten and .45 or 1)
end

function Portrait:SetRing(r, g, b)
    self.ring:SetVertexColor(r or 1, g or 1, b or 1, 1)
end

-- Back to the plain fallback icon; a pending lookup is forgotten.
function Portrait:Clear()
    self.serial = self.serial + 1
    self:SetBeaten(false)
    ShowIcon(self)
end

function Faces:NewPortrait(parent, size)
    size = tonumber(size) or 32
    local frame = CreateFrame("Frame", nil, parent)
    -- The ring is a coloured disc behind a dark disc behind the masked face.
    local ring = frame:CreateTexture(nil, "BACKGROUND")
    ring:SetAllPoints(frame)
    ring:SetTexture(MASK)
    local back = frame:CreateTexture(nil, "BORDER")
    back:SetPoint("CENTER", frame, "CENTER", 0, 0)
    back:SetTexture(MASK)
    back:SetVertexColor(Color("backgroundDeep", { .13, .105, .078 }))
    local face = frame:CreateTexture(nil, "ARTWORK")
    face:SetPoint("CENTER", frame, "CENTER", 0, 0)
    pcall(face.SetMask, face, MASK)
    local portrait = setmetatable({ frame = frame, ring = ring, back = back, face = face, serial = 0 }, Portrait)
    ResizePortrait(portrait, size)
    portrait:SetRing(Color("borderActive", { .76, .59, .32 }))
    portrait:Clear()
    return portrait
end

-- Boss viewer --------------------------------------------------------------------------------------

local Stage = {}
Stage.__index = Stage

function Stage:SetDisplay(displayID)
    self:Stop()
    displayID = ValidId(displayID)
    self.display, self.framed = displayID, false
    self.loadSerial = self.loadSerial + 1
    local model = self.frame
    if not displayID then return false end
    -- Unseen until loaded and framed: no previous creature, no badly framed model.
    model:SetAlpha(0)
    pcall(model.ClearModel, model)
    if not pcall(model.SetDisplayInfo, model, displayID) then return false end
    local serial = self.loadSerial
    Timer(Faces.STAGE_WAIT, function() self:Loaded(serial) end)
    return true
end

function Stage:Loaded(serial)
    if serial ~= self.loadSerial or self.framed or not self.display then return end
    self.framed = true
    local model = self.frame
    pcall(model.SetPortraitZoom, model, 0)
    pcall(model.SetCamDistanceScale, model, 1)
    pcall(model.SetPosition, model, 0, 0, 0)
    model:SetAlpha(1)
    if Reduced() or Call(model.IsVisible, model) ~= true then
        pcall(model.SetFacing, model, 0)
        return
    end
    self:Turn()
end

-- A slow half turn, eased, then still.
function Stage:Turn()
    local model, spent = self.frame, 0
    local from, to, seconds = Faces.TURN_FROM, Faces.TURN_TO, Faces.TURN_SECONDS
    pcall(model.SetFacing, model, from)
    model:SetScript("OnUpdate", function(_, elapsed)
        spent = spent + (tonumber(elapsed) or 0)
        local p = math.min(1, spent / seconds)
        pcall(model.SetFacing, model, from + (to - from) * p * p * (3 - 2 * p))
        if p >= 1 then self:Stop() end
    end)
end

function Stage:Stop()
    self.frame:SetScript("OnUpdate", nil)
end

function Faces:NewStage(parent)
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, parent)
    if not ok or not model then model = CreateFrame("Frame", nil, parent) end
    local stage = setmetatable({ frame = model, loadSerial = 0 }, Stage)
    pcall(model.SetScript, model, "OnModelLoaded", function() stage:Loaded(stage.loadSerial) end)
    if type(model.HookScript) == "function" then model:HookScript("OnHide", function() stage:Stop() end)
    else model:SetScript("OnHide", function() stage:Stop() end) end
    return stage
end

-- The player's model -------------------------------------------------------------------------------

local Hero = {}
Hero.__index = Hero

function Hero:Refresh()
    local model = self.model
    local shown = model and Setting("showModels") ~= false and pcall(model.SetUnit, model, "player")
    if shown then
        self.portrait.frame:Hide()
        model:Show()
        pcall(model.SetFacing, model, Faces.HERO_FACING)
        pcall(model.SetAnimation, model, 0)
    else
        if model then model:Hide() end
        self.portrait.frame:Show()
        self.portrait:SetUnit("player")
    end
    self.modelShown = shown and true or false
    self:Ghost(self.ghost)
end

function Hero:Cheer()
    local model = self.model
    if not self.modelShown then return false end
    local ok, has = pcall(model.HasAnimation, model, 68)
    if not ok or Hidden(has) or has ~= true then return false end
    pcall(model.SetAnimation, model, 68)
    self.cheerSerial = self.cheerSerial + 1
    local serial = self.cheerSerial
    Timer(Faces.CHEER_SECONDS, function()
        if self.cheerSerial == serial then pcall(model.SetAnimation, model, 0) end
    end)
    return true
end

function Hero:Ghost(on)
    self.ghost = on == true
    self.frame:SetAlpha(self.ghost and .55 or 1)
    self.chill:SetShown(self.ghost)
    pcall(self.portrait.face.SetDesaturated, self.portrait.face, self.ghost)
end

function Faces:NewHero(parent)
    local frame = CreateFrame("Frame", nil, parent)
    local hero = setmetatable({ frame = frame, ghost = false, cheerSerial = 0 }, Hero)
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, frame)
    if ok and model then
        model:SetAllPoints(frame)
        hero.model = model
    end
    hero.portrait = self:NewPortrait(frame, 56)
    hero.portrait.frame:SetPoint("CENTER", frame, "CENTER", 0, 0)
    hero.portrait:SetRing(Color("gold", { .93, .73, .39 }))
    -- Above the model: a frame's own textures would draw under its child model.
    local cover = CreateFrame("Frame", nil, frame)
    cover:SetAllPoints(frame)
    cover:SetFrameLevel(frame:GetFrameLevel() + 5)
    hero.chill = cover:CreateTexture(nil, "OVERLAY")
    hero.chill:SetAllPoints(cover)
    hero.chill:SetColorTexture(.55, .72, .95, .22)
    pcall(hero.chill.SetBlendMode, hero.chill, "ADD")
    hero.chill:Hide()
    frame:SetScript("OnShow", function() hero:Refresh() end)
    frame:SetScript("OnSizeChanged", function(_, width, height)
        width, height = tonumber(width) or 0, tonumber(height) or 0
        ResizePortrait(hero.portrait, math.max(16, math.min(width, height) - 8))
    end)
    self.heroes[hero] = true
    hero:Refresh()
    return hero
end

if MS.JourneySettings then
    MS.JourneySettings:Listen(function(key)
        if key ~= "showModels" then return end
        for hero in pairs(Faces.heroes) do hero:Refresh() end
    end)
end
