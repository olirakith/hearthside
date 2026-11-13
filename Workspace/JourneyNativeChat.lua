local MS = _G.MS

-- The game's chat while Journey shows it on the second screen: its windows, tabs and buttons are
-- hidden (Hide, never transparency: a transparent frame would still catch clicks in the world)
-- and its edit box is moved into Journey's panel. Every change is noted and Restore puts back
-- exactly what Journey changed, nothing else: a chat another addon hid (OneForAll) stays hidden.
-- Nothing survives a /reload: the game rebuilds its chat. No hook on Blizzard code.
MS.JourneyNativeChat = { changed = nil }
local Native = MS.JourneyNativeChat

-- Blizzard's own chat pieces. Other addons' buttons are never touched.
local SHARED = { "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }

-- The numbered windows, plus those Blizzard made since (a whisper opened in its own window):
-- CHAT_FRAMES lists every chat window by name.
function Native:Frames()
    local frames, seen = {}, {}
    local function Add(name)
        for _, suffix in ipairs({ "", "Tab", "ButtonFrame" }) do
            local frame = _G[name .. suffix]
            if type(frame) == "table" and not seen[frame] then
                seen[frame] = true
                frames[#frames + 1] = frame
            end
        end
    end
    local count = tonumber(_G.NUM_CHAT_WINDOWS) or 10
    for index = 1, count do Add("ChatFrame" .. index) end
    if type(_G.CHAT_FRAMES) == "table" then
        for _, name in pairs(_G.CHAT_FRAMES) do
            if type(name) == "string" then Add(name) end
        end
    end
    for _, name in ipairs(SHARED) do
        local frame = _G[name]
        if type(frame) == "table" then frames[#frames + 1] = frame end
    end
    return frames
end

function Native:EditBox()
    local chat = _G.DEFAULT_CHAT_FRAME
    local box = chat and chat.editBox or _G.ChatFrame1EditBox
    return type(box) == "table" and box or nil
end

function Native:IsConcealed() return self.changed ~= nil end

-- Hides what is shown now; returns how many frames Journey has hidden in all. Called again while
-- the panel shows: Blizzard shows its chat windows again after each loading screen (entering a
-- dungeon: UPDATE_CHAT_WINDOWS), and a whisper may open a new window.
function Native:Conceal()
    local changed = self.changed or { hidden = {} }
    self.changed = changed
    local known = {}
    for _, frame in ipairs(changed.hidden) do known[frame] = true end
    for _, frame in ipairs(self:Frames()) do
        local ok, shown = pcall(frame.IsShown, frame)
        if ok and shown and pcall(frame.Hide, frame) and not known[frame] then
            known[frame] = true
            changed.hidden[#changed.hidden + 1] = frame
        end
    end
    return #changed.hidden
end

-- Places the edit box along the bottom of host (Journey's panel). The original anchors are
-- noted the first time only, so placing it again after a resize keeps the true original.
function Native:Dock(host, left, bottom, right)
    local box = self:EditBox()
    if not box or not host then return false end
    local changed = self.changed or { hidden = {} }
    self.changed = changed
    if not changed.edit then
        local points = {}
        local count = type(box.GetNumPoints) == "function" and box:GetNumPoints() or 0
        for index = 1, count do points[index] = { box:GetPoint(index) } end
        changed.edit = { box = box, points = points, width = box:GetWidth(), height = box:GetHeight() }
    end
    box:ClearAllPoints()
    box:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", left or 0, bottom or 0)
    box:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(right or 0), bottom or 0)
    return true
end

-- Has Blizzard moved the edit box away (chat settings, font size, Edit Mode)? Journey puts it
-- back the next time the panel opens it.
function Native:Docked(host)
    local box = self:EditBox()
    if not box or not self.changed or not self.changed.edit then return false end
    local ok, _, relative = pcall(box.GetPoint, box, 1)
    return ok and relative == host
end

function Native:Restore()
    local changed = self.changed
    if not changed then return 0 end
    self.changed = nil
    local restored = 0
    for _, frame in ipairs(changed.hidden) do
        local ok, shown = pcall(frame.IsShown, frame)
        if ok and not shown and pcall(frame.Show, frame) then restored = restored + 1 end
    end
    local edit = changed.edit
    if edit then
        local box = edit.box
        pcall(box.ClearAllPoints, box)
        for _, point in ipairs(edit.points) do pcall(box.SetPoint, box, unpack(point)) end
        if #edit.points < 2 then
            pcall(box.SetWidth, box, edit.width)
            pcall(box.SetHeight, box, edit.height)
        end
    end
    return restored
end
