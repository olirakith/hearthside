local MS = _G.MS

-- The map key, when the player asks for it, opens the Journey map tab. Only the key changes hands,
-- through an override binding: WorldMapFrame is never touched, and overrides end with the UI load,
-- so a reload or a logout always gives the key back. They cannot change in a fight: a change waits.
local Key = { binding = "TOGGLEWORLDMAP", button = "HearthsideMapKey" }
MS.JourneyMapKey = Key

function Key:Wanted()
    return MS.JourneyWorkspace.active == true and MS.JourneySettings:Get("mapKeyOpensJourney") == true
end

function Key:Apply()
    if InCombatLockdown() then
        self.pending = true
        return false
    end
    self.pending = false
    local first, second
    if self:Wanted() then first, second = GetBindingKey(self.binding) end
    -- Setting an override fires UPDATE_BINDINGS: an unchanged state must stop there.
    if first == self.first and second == self.second then return true end
    ClearOverrideBindings(self.owner)
    if first then SetOverrideBindingClick(self.owner, false, first, self.button) end
    if second then SetOverrideBindingClick(self.owner, false, second, self.button) end
    self.first, self.second = first, second
    return true
end

Key.owner = CreateFrame("Button", Key.button)
Key.owner:SetScript("OnClick", function() MS.JourneyWorkspace:SelectView("MAP") end)
Key.owner:RegisterEvent("UPDATE_BINDINGS")
Key.owner:RegisterEvent("PLAYER_REGEN_ENABLED")
Key.owner:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_BINDINGS" or Key.pending then Key:Apply() end
end)

local Settings = MS.JourneySettings
Settings:Listen(function(key)
    if key == "mapKeyOpensJourney" then Key:Apply() end
end)
Settings:AddExternalToggle({ id = "mapKeyOpensJourney", label = MS.L.JOURNEY_SETTING_mapKeyOpensJourney,
    hint = MS.L.JOURNEY_SETTINGS_MAP_KEY_HINT,
    get = function() return Settings:Get("mapKeyOpensJourney") end,
    set = function(value) Settings:Set("mapKeyOpensJourney", value) end })
