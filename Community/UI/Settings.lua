local MS = _G.MS
MS.Community = MS.Community or {}
-- Two switches in Journey's "Experimental features" section. Familiar names follow the
-- Community switch; peer features stay a tester command (/ms community flag peerFeatures).
local C = MS.Community
local Settings = MS.JourneySettings
if not (Settings and Settings.AddExternalToggle) then return end

Settings:AddExternalToggle({ id = "communityEnabled", label = MS.L.COMMUNITY_SETTING_ENABLED, hint = MS.L.COMMUNITY_SETTING_ENABLED_HINT,
    get = function() return C.initialized == true and not C.Store.readOnly and C.Flags:Raw("communityEnabled") == true end,
    set = function(value) if C.initialized then C:SetFlag("communityEnabled", value) end end })

Settings:AddExternalToggle({ id = "groupingAssist", label = MS.L.COMMUNITY_SETTING_ASSIST, hint = MS.L.COMMUNITY_SETTING_ASSIST_HINT,
    -- Needs Community: greyed with its reason instead of a switch that silently does nothing.
    blocked = function()
        if not (C.initialized == true and not C.Store.readOnly and C.Flags:Raw("communityEnabled") == true) then
            return MS.L.COMMUNITY_SETTING_NEEDS_COMMUNITY
        end
    end,
    get = function() return C.initialized == true and not C.Store.readOnly and C.Flags:Raw("groupingAssist") == true end,
    set = function(value) if C.initialized then C:SetFlag("groupingAssist", value) end end })
