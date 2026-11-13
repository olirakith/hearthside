local MS = _G.MS

-- "Who is it?" from Journey's chat menu. Forever refuses a Who search started by an addon, even
-- from a click (taint.log 2026-11-13: SendWho blocked); one typed by the player goes through.
-- Out of combat the menu sends it through an action button (JourneyContextMenu); otherwise it
-- writes the search in the game's edit box and the player presses Enter. The game answers with
-- its own system lines, which Journey's chat shows.
MS.JourneyWho = {}
local Who = MS.JourneyWho

local function Opener()
    local util = _G.ChatFrameUtil
    if type(util) == "table" and type(util.OpenChat) == "function" then return util.OpenChat end
    if type(_G.ChatFrame_OpenChat) == "function" then return _G.ChatFrame_OpenChat end
end

function Who:Available() return Opener() ~= nil end

-- The whole name: the Who search matches inside names, and more than one answer opens the game's
-- window on the game screen; one answer comes as a chat line. Forever's chat gives "Pat Chnote",
-- which the search takes as it is (measured 2026-11-13); elsewhere "Ana-Realm" keeps "Ana".
function Who.Command(name)
    local slash = type(_G.SLASH_WHO1) == "string" and _G.SLASH_WHO1 or "/who"
    return string.format('%s n-"%s"', slash, name:match("^([^%-]+)") or name)
end

function Who:Ask(name)
    local open = Opener()
    if type(name) ~= "string" or name == "" or not open then return false end
    self.lastCommand = Who.Command(name)
    local ok, failure = pcall(open, self.lastCommand, _G.DEFAULT_CHAT_FRAME)
    if not ok then self.lastError = tostring(failure) end
    return ok
end
