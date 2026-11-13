local MS = _G.MS

-- A sound when a whisper arrives (game or Battle.net), never for the player's own. The game's own
-- whisper sound is easy to miss, more so when Journey hides the game's chat. Game sounds only,
-- on the Master channel so it is heard with effects muted; one at most every two seconds.
-- Setting chatWhisperSound: 0 none, otherwise an index in sounds.
MS.JourneyWhisperSound = { gap = 2, last = nil,
    sounds = {
        { kit = "TELL_MESSAGE", id = 3081 },   -- the game's whisper sound
        { kit = "UI_BNET_TOAST", id = 18019 }, -- Battle.net toast
        { kit = "RAID_WARNING", id = 8959 },   -- raid warning
        { id = 416 },                          -- murloc
    } }
local Sound = MS.JourneyWhisperSound

local INCOMING = { CHAT_MSG_WHISPER = true, CHAT_MSG_BN_WHISPER = true }

local function Now() return type(_G.GetTime) == "function" and _G.GetTime() or 0 end

function Sound:Kit(choice)
    local sound = self.sounds[choice]
    if not sound then return nil end
    local named = sound.kit and type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT[sound.kit]
    return type(named) == "number" and named or sound.id
end

-- preview: the settings' buttons play it at once, whatever the gap.
function Sound:Play(choice, preview)
    local kit = self:Kit(choice)
    if not kit or type(_G.PlaySound) ~= "function" then return false end
    local now = Now()
    if not preview and self.last and now - self.last < self.gap then return false end
    self.last = now
    return pcall(_G.PlaySound, kit, "Master") == true
end

function Sound:OnEvent(event)
    if not INCOMING[event] then return end
    local settings = MS.JourneySettings
    local choice = settings and settings:Get("chatWhisperSound")
    if type(choice) == "number" and choice > 0 then self:Play(choice) end
end

function Sound:Start()
    if self.events or type(_G.CreateFrame) ~= "function" then return end
    self.events = _G.CreateFrame("Frame")
    for event in pairs(INCOMING) do self.events:RegisterEvent(event) end
    self.events:SetScript("OnEvent", function(_, event) Sound:OnEvent(event) end)
end

Sound:Start()
