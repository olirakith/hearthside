local MS = _G.MS

-- Streamer mode: one switch, and Journey shows nothing that exposes another player, a seal code,
-- the gold or the hearthstone inn. Display only: the data never changes. Only Journey is
-- concerned; the game's chat, nameplates and other addons stay as they are.
-- Views ask at render time and redraw on Listen(); none keeps a masked text.
MS.BroadcastMode = { listeners = {} }
local Mode = MS.BroadcastMode
local KEY = "broadcastMode"

local function Settings() return MS.JourneySettings end

function Mode:IsOn()
    local settings = Settings()
    return settings ~= nil and settings:Get(KEY) == true
end

function Mode:Set(on)
    local settings = Settings()
    if settings then settings:Set(KEY, on == true) end
end

function Mode:Toggle()
    self:Set(not self:IsOn())
    return self:IsOn()
end

-- callback(on): called after every change.
function Mode:Listen(callback)
    if type(callback) == "function" then self.listeners[#self.listeners + 1] = callback end
end

function Mode:Notify()
    local on = self:IsOn()
    for _, callback in ipairs(self.listeners) do pcall(callback, on) end
end

-- Another player's name, or the masked mark.
function Mode:Person(name)
    if not self:IsOn() then return name end
    return MS.L.BROADCAST_HIDDEN
end

-- Several names joined, or how many they are.
function Mode:People(names, separator)
    names = type(names) == "table" and names or {}
    if not self:IsOn() then return table.concat(names, separator or ", ") end
    if #names <= 1 then return MS.L.BROADCAST_HIDDEN end
    return string.format(MS.L.BROADCAST_COMPANIONS, #names)
end

-- An edit box whose text must not show (a code, a name being typed). The text stays in the box,
-- so Ctrl+A then Ctrl+C still copies it: only its colour turns clear.
function Mode:Conceal(box, on)
    if type(box) ~= "table" or type(box.SetTextColor) ~= "function" then return end
    on = on == nil and self:IsOn() or on == true
    local saved = rawget(box, "ajBroadcastColor")
    if on and not saved then
        local r, g, b, a = 1, 1, 1, 1
        if type(box.GetTextColor) == "function" then r, g, b, a = box:GetTextColor() end
        box.ajBroadcastColor = { r or 1, g or 1, b or 1, a or 1 }
        box:SetTextColor(r or 1, g or 1, b or 1, 0)
    elseif not on and saved then
        local color = saved
        box.ajBroadcastColor = nil
        box:SetTextColor(color[1], color[2], color[3], color[4])
    end
end

-- A field the player types a name or a code into: shown as stars while streaming.
function Mode:Password(box)
    if type(box) == "table" and type(box.SetPassword) == "function" then box:SetPassword(self:IsOn()) end
end

if MS.JourneySettings then
    MS.JourneySettings:Listen(function(key) if key == KEY then Mode:Notify() end end)
end

_G.BINDING_NAME_HEARTHSIDE_TOGGLE_BROADCAST = MS.L.BINDING_NAME_HEARTHSIDE_TOGGLE_BROADCAST

-- Key binding (Bindings.xml) and /journey diffusion.
function _G.Hearthside_ToggleBroadcast()
    if MS.Edition and not MS.Edition:Streamer() then return end
    local on = Mode:Toggle()
    if MS.Diagnostics then MS.Diagnostics:Print(MS.L[on and "BROADCAST_ON" or "BROADCAST_OFF"]) end
end
