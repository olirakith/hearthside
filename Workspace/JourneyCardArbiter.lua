local MS = _G.MS
-- One Journey card at a time, never in combat. Journey's own surfaces ask before showing:
--   PANEL   a window the player opened (always wins, never counted)
--   REVEAL  a Sur mes pas seal opening
--   RESULT  a Contrat end sheet
--   PROMPT  a Contrat question ("is the dungeon over?")
--   OFFER   a Sur mes pas code received by whisper: keep it or not
--   NEAR    "the seal feels close" (Sur mes pas)
--   RULE    a Contrat rule changing state
-- Spontaneous kinds (PROMPT, NEAR, RULE) have a cooldown after any card and a per-session quota that
-- survives /reload (the state lives in AzerothJourneyActiveDB.arbiter; a new login resets it).
-- Older card owners (Community moment card, Chronicles toast) are not rewritten: they are read as
-- foreign cards and ask Blocks() before showing or coming back. Journey's own automatic cards wait
-- for a foreign card to leave; the window the player opens dismisses it (Yield).
local Arbiter = {
    priority = { PANEL = 100, REVEAL = 90, RESULT = 80, PROMPT = 60, OFFER = 58, NEAR = 55, RULE = 50, COMMUNITY = 40, CHRONICLES = 30 },
    spontaneous = { PROMPT = true, NEAR = true, RULE = true },
    quota = { PROMPT = 6, NEAR = 6, RULE = 12 },
    cooldown = 12,
}
MS.JourneyCardArbiter = Arbiter

local function Clock() return Arbiter.clock and Arbiter.clock() or 0 end

local function InCombat()
    local check = _G.InCombatLockdown
    if type(check) ~= "function" then return false end
    local ok, value = pcall(check)
    -- Unknown is treated as combat: a card never risks appearing during a fight.
    return not ok or value ~= false
end

-- root: AzerothJourneyActiveDB.arbiter (or nil: session memory only). initial: a fresh login.
function Arbiter:Bind(root, clock, initial)
    self.clock = clock
    root = type(root) == "table" and root or {}
    if initial or type(root.counts) ~= "table" then root.counts = {} end
    local counts = {}
    for kind, count in pairs(root.counts) do
        if self.spontaneous[kind] and type(count) == "number" and count >= 0 and count <= 2 ^ 31 - 1 then counts[kind] = math.floor(count) end
    end
    root.counts = counts
    -- A finite moment no later than now (math.huge, NaN or a future time would freeze the cooldown).
    local lastAt, now = root.lastAt, clock and clock()
    if initial or type(lastAt) ~= "number" or not (lastAt >= 0) or type(now) ~= "number" or lastAt > now then root.lastAt = nil end
    self.root = root
    return root
end

-- Cards Journey shows through other modules, read as they are.
function Arbiter:Foreign()
    local card = MS.Community and MS.Community.MomentCard
    if card and card.IsShowing and card:IsShowing() then return "COMMUNITY" end
    local toast = MS.ChroniclesDiscoveryToast
    if toast and toast.visible then return "CHRONICLES" end
end

function Arbiter:Visible()
    if self.current then return self.current.kind end
    return self:Foreign()
end

-- May a card of this kind appear now? Returns true, or false and COMBAT | BUSY | COOLDOWN | QUOTA.
function Arbiter:Allow(kind)
    local priority = self.priority[kind]
    if not priority then return false, "UNKNOWN" end
    if InCombat() then return false, "COMBAT" end
    local visible = self:Visible()
    if not self.current and visible and kind ~= "PANEL" then return false, "BUSY" end
    if visible and visible ~= kind and (self.priority[visible] or 0) >= priority then return false, "BUSY" end
    if visible == kind and self.current and kind ~= "PANEL" then return false, "BUSY" end
    if self.spontaneous[kind] then
        local root = self.root or {}
        if type(root.lastAt) == "number" and Clock() - root.lastAt < self.cooldown then return false, "COOLDOWN" end
        if ((root.counts or {})[kind] or 0) >= (self.quota[kind] or 0) then return false, "QUOTA" end
    end
    return true
end

-- Takes the single slot. onReplaced(reason) is called if a more important card takes it.
-- Returns a token, or nil and the refusal reason.
function Arbiter:Acquire(kind, onReplaced)
    local ok, reason = self:Allow(kind)
    if not ok then return nil, reason end
    local previous = self.current
    if previous then
        self.current = nil
        if previous.onReplaced then pcall(previous.onReplaced, "REPLACED") end
    end
    local token = { kind = kind, onReplaced = onReplaced }
    self.current = token
    self:Yield()
    if self.spontaneous[kind] and self.root then
        self.root.counts[kind] = math.min((self.root.counts[kind] or 0) + 1, 2 ^ 31 - 1)
    end
    return token
end

-- A foreign card still on screen steps aside for the card that just took the slot.
function Arbiter:Yield()
    local foreign = self:Foreign()
    if foreign == "COMMUNITY" then
        local card = MS.Community.MomentCard
        if card.Close then pcall(card.Close, card, "ARBITER") end
    elseif foreign == "CHRONICLES" then
        local toast = MS.ChroniclesDiscoveryToast
        if toast.Dismiss then pcall(toast.Dismiss, toast) end
    end
end

function Arbiter:Release(token)
    if not token or self.current ~= token then return end
    self.current = nil
    if self.root then self.root.lastAt = Clock() end
end

-- For the older card owners: is a Journey card at least as important as theirs visible?
function Arbiter:Blocks(kind)
    local current = self.current
    return current ~= nil and (self.priority[current.kind] or 0) >= (self.priority[kind] or 0)
end
