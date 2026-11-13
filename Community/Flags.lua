local MS = _G.MS
MS.Community = MS.Community or {}
-- Account-wide feature flags. Pure: bound to a table owned by Community.Store.
local Flags = { version = 1, root = nil }
MS.Community.Flags = Flags

Flags.order = { "communityEnabled", "encounterMemories", "familiarNames", "groupingAssist", "peerFeatures" }
-- Community is opt-in: it keeps names of other players, enabling it is a player gesture.
Flags.defaults = { communityEnabled = false, encounterMemories = true, familiarNames = true,
    groupingAssist = false, peerFeatures = false }

function Flags:Sanitize(raw)
    raw = type(raw) == "table" and raw or {}
    local flags = { version = self.version }
    for _, name in ipairs(self.order) do
        if type(raw[name]) == "boolean" then flags[name] = raw[name] else flags[name] = self.defaults[name] end
    end
    return flags
end

function Flags:Bind(flags)
    self.root = flags
end

function Flags:Raw(name)
    if self.defaults[name] == nil then return nil end
    local root = self.root
    if root and type(root[name]) == "boolean" then return root[name] end
    return self.defaults[name]
end

-- Effective state: every sub-feature requires the master switch.
function Flags:IsOn(name)
    if self.defaults[name] == nil or not self:Raw("communityEnabled") then return false end
    return self:Raw(name) == true
end

function Flags:Set(name, value)
    if self.defaults[name] == nil or type(value) ~= "boolean" or not self.root then return false end
    self.root[name] = value
    return true
end

function Flags:Snapshot()
    local result = {}
    for _, name in ipairs(self.order) do result[name] = { raw = self:Raw(name), effective = self:IsOn(name) } end
    result.communityEnabled.effective = self:Raw("communityEnabled")
    return result
end
