local MS = _G.MS

-- Which edition this copy of the addon is. The public release keeps the streamer features
-- (streamer mode, the Contrat's live view) switched off and out of sight; a separate streamer
-- build turns `streamer` on. Saved settings are never erased: an off feature only reads as off.
MS.Edition = { streamer = false }
local Edition = MS.Edition

-- Settings that only exist in the streamer edition.
Edition.STREAMER_SETTINGS = { broadcastMode = true, contractLive = true }

function Edition:Streamer()
    return self.streamer == true
end

-- False when this setting belongs to a feature the edition leaves out.
function Edition:Allows(key)
    return not (self.STREAMER_SETTINGS[key] and not self:Streamer())
end
