local MS = _G.MS

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Forever may omit an event on some builds; registration must never break load.
pcall(events.RegisterEvent, events, "DISPLAY_SIZE_CHANGED")
pcall(events.RegisterEvent, events, "UI_SCALE_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        MS.Database:Initialize()
        MS.JourneySession:Initialize()
        if MS.JourneyInventoryData then MS.JourneyInventoryData:Start() end
    elseif event == "PLAYER_LOGOUT" then
        if MS.JourneyInventoryData then MS.JourneyInventoryData:Stop() end
        MS.Runtime:OnLogout()
    elseif event == "PLAYER_REGEN_ENABLED" then
        MS.Recovery:OnCombatEnded()
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        MS.Runtime:OnDisplayMetricsChanged(event)
    end
end)

SLASH_MULTISCREENFOREVER1 = "/ms"
SlashCmdList.MULTISCREENFOREVER = function(message)
    local command = string.lower(string.match(message or "", "^%s*(%S*)") or "")
    if command == "enable" then
        MS.Runtime:Enable()
    elseif command == "disable" then
        MS.Runtime:Disable()
    elseif command == "reset" then
        MS.Runtime:Reset()
    elseif command == "recover" then
        MS.Runtime:Recover()
    elseif command == "diag" then
        MS.Diagnostics:Show()
    elseif command == "report" then
        MS.Diagnostics:ShowMultiScreenReport()
    elseif command == "workspace-debug" then
        local enabled = MS.Workspace:ToggleDebug()
        MS.Diagnostics:Print(enabled and MS.L.WORKSPACE_DEBUG_ENABLED or MS.L.WORKSPACE_DEBUG_DISABLED)
    elseif command == "perf" then
        local detail = string.match(message or "", "^%s*%S+%s+(.+)$")
        if MS.PerformanceAudit then MS.PerformanceAudit:Run(detail)
        else MS.Diagnostics:Print(MS.L.DEV_ADDON_MISSING) end
    elseif command == "community" then
        MS.Community:Command(string.match(message or "", "^%s*%S+%s*(.-)$"))
    elseif command == "session" then
        local detail = string.lower(string.match(message or "", "^%s*%S+%s*(%S*)") or "")
        if detail == "new" then
            MS.JourneySession:New()
            MS.Diagnostics:Print(MS.L.JOURNEY_SESSION_NEW)
        else
            MS.Diagnostics:Print(MS.L.JOURNEY_SESSION_HELP)
        end
    else
        MS.Diagnostics:Print(MS.L.UNKNOWN_COMMAND)
    end
end

-- Pixel handshake: one ui_epoch per UI load; the module owns its events and hooks.
MS.PixelHandshake:Start()

MS.Diagnostics:Print(MS.L.ADDON_LOADED)
