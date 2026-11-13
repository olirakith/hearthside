local MS = _G.MS
MS.Active = MS.Active or {}
-- Journey prepares a line in the native chat box; the player edits it, sends it or clears it.
-- Never SendChatMessage: the last gesture is always the player's. The text is never logged.
local A = MS.Active
local Chat = { limit = 255 }
A.Chat = Chat

-- A message the player has started is never overwritten (only tested for emptiness).
local function DraftPresent()
    local active = A.Call(_G.ChatEdit_GetActiveWindow)
    if type(active) ~= "table" or type(active.GetText) ~= "function" then return false end
    local text = A.Call(active.GetText, active)
    return type(text) == "string" and text:find("[^ \t]") ~= nil
end

-- prefix: "/p ", "/w Name-Realm " or "" (the player's current channel). The whole line, prefix
-- included, must fit the chat box. Returns true, or false and a reason.
function Chat:Prefill(prefix, text)
    local line = (prefix or "") .. (text or "")
    if text == nil or text == "" then return false, "NO_TEXT" end
    if #line > self.limit then return false, "TOO_LONG" end
    local open = _G.ChatFrame_OpenChat
    if type(open) ~= "function" then return false, "NATIVE_CHAT_UNAVAILABLE" end
    if DraftPresent() then return false, "DRAFT_PRESENT" end
    if not pcall(open, line) then return false, "NATIVE_CHAT_ERROR" end
    A:Prove("ChatPrefill", "PREFILL_OPENED")
    return true
end

-- The channel a group line goes to: the group the player is in, read now.
function Chat:GroupPrefix()
    if A.Bool(A.Call(_G.IsInRaid)) == true then return "/ra " end
    if A.Bool(A.Call(_G.IsInGroup)) == true then return "/p " end
    return nil
end
