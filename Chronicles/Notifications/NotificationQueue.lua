local MS = _G.MS

MS.ChroniclesNotificationQueue = { MAX_PENDING = 128, COOLDOWN_SECONDS = 9 }
local Queue = MS.ChroniclesNotificationQueue
Queue.__index = Queue

local TYPES = {
    RUMOR_DISCOVERED = { prefix = "rumor:", priority = "LOW" },
    CHRONICLE_DISCOVERED = { prefix = "chronicle:", priority = "NORMAL" },
    REGION_VISITED = { prefix = "region-visited:", priority = "IMPORTANT" },
}
local RANK = { LOW = 1, NORMAL = 2, IMPORTANT = 3 }
local FIELDS = { eventID = true, type = true, contentID = true,
    priority = true, createdAt = true, batchID = true }

local function ValidTime(value)
    return type(value) == "number" and value > 0 and value < math.huge
        and value == math.floor(value)
end

local function ValidEvent(event)
    if type(event) ~= "table" then return false end
    for key in pairs(event) do if not FIELDS[key] then return false end end
    local spec = TYPES[event.type]
    return spec ~= nil and type(event.contentID) == "string" and event.contentID ~= ""
        and event.eventID == spec.prefix .. event.contentID
        and event.priority == spec.priority and ValidTime(event.createdAt)
        and type(event.batchID) == "string" and event.batchID ~= ""
end

local function ValidList(list, allowDuplicates)
    if type(list) ~= "table" then return false end
    local length, seen = 0, {}
    for key, event in pairs(list) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key)
            or not ValidEvent(event) or seen[event.eventID] and not allowDuplicates then return false end
        length = length + 1
        seen[event.eventID] = true
    end
    for index = 1, length do if list[index] == nil then return false end end
    return true, seen
end

local function CopyEvent(event)
    return { eventID = event.eventID, type = event.type,
        contentID = event.contentID, priority = event.priority,
        createdAt = event.createdAt, batchID = event.batchID }
end

local function Before(a, ai, b, bi)
    if RANK[a.priority] ~= RANK[b.priority] then
        return RANK[a.priority] > RANK[b.priority] end
    if a.createdAt ~= b.createdAt then return a.createdAt < b.createdAt end
    return ai < bi
end

local function OldestEvictionIndex(list)
    local chosen
    for index, event in ipairs(list) do
        if not chosen or RANK[event.priority] < RANK[list[chosen].priority]
            or RANK[event.priority] == RANK[list[chosen].priority]
                and (event.createdAt < list[chosen].createdAt
                    or event.createdAt == list[chosen].createdAt and index < chosen) then
            chosen = index
        end
    end
    return chosen
end

function Queue:New(store, characterKey)
    return setmetatable({ store = store, characterKey = characterKey }, self)
end

function Queue:Read()
    if type(self.store) ~= "table" or type(self.store.GetCharacterState) ~= "function" then return nil end
    local ok, state = pcall(self.store.GetCharacterState, self.store, self.characterKey)
    if not ok or type(state) ~= "table" then return nil end
    local valid = ValidList(state.notifications)
    if not valid then return nil end
    return state.notifications, state
end

function Queue:Count()
    local list = self:Read()
    return list and #list or nil
end

function Queue:Contains(eventID)
    local list = self:Read()
    if not list then return nil end
    for _, event in ipairs(list) do if event.eventID == eventID then return true end end
    return false
end

function Queue:Enqueue(event)
    if event == nil then return { status = "INVALID_EVENT", added = {}, evicted = {} } end
    return self:EnqueueBatch({ event })
end

function Queue:EnqueueBatch(events)
    local list, state = self:Read()
    if not list then return { status = "UNAVAILABLE", added = {}, evicted = {} } end
    local valid = ValidList(events, true)
    if not valid then return { status = "INVALID_EVENT", added = {}, evicted = {} } end
    local nextList, seen, added, evicted = {}, {}, {}, {}
    for _, event in ipairs(list) do
        nextList[#nextList + 1] = event
        seen[event.eventID] = true
    end
    for _, event in ipairs(events) do
        if not seen[event.eventID] then
            nextList[#nextList + 1] = CopyEvent(event)
            added[#added + 1] = event.eventID
            seen[event.eventID] = true
        end
    end
    while #nextList > self.MAX_PENDING do
        local index = OldestEvictionIndex(nextList)
        evicted[#evicted + 1] = table.remove(nextList, index).eventID
    end
    if #added > 0 then state.notifications = nextList end
    return { status = "READY", added = added, evicted = evicted }
end

local function Eligibility(context, now, cooldown)
    if type(context) ~= "table" then return "INVALID_CONTEXT" end
    if context.inCombat then return "COMBAT" end
    if context.loading then return "LOADING" end
    if context.sensitiveScreen then return "SENSITIVE_SCREEN" end
    if context.anotherNotificationVisible then return "BUSY" end
    if not ValidTime(now) then return "INVALID_CONTEXT" end
    local last = context.lastPresentedAt
    if last ~= nil and not ValidTime(last) then return "INVALID_CONTEXT" end
    if last and now < last + cooldown then return "COOLDOWN" end
end

function Queue:PeekNext(context, now)
    local list = self:Read()
    if not list then return { status = "UNAVAILABLE" } end
    if #list == 0 then return { status = "EMPTY" } end
    local reason = Eligibility(context, now, self.COOLDOWN_SECONDS)
    if reason then return { status = "BLOCKED", reason = reason } end
    local selected = 1
    for index = 2, #list do
        if Before(list[index], index, list[selected], selected) then selected = index end
    end
    return { status = "READY", event = CopyEvent(list[selected]) }
end

function Queue:PeekBatch(context, now)
    local list = self:Read()
    if not list then return { status = "UNAVAILABLE" } end
    if #list == 0 then return { status = "EMPTY" } end
    local reason = Eligibility(context, now, self.COOLDOWN_SECONDS)
    if reason then return { status = "BLOCKED", reason = reason } end
    local groups, order = {}, {}
    for index, event in ipairs(list) do
        local group = groups[event.batchID]
        if not group then
            group = { batchID = event.batchID, events = {}, priority = event.priority,
                createdAt = event.createdAt, firstIndex = index }
            groups[event.batchID] = group
            order[#order + 1] = group
        end
        group.events[#group.events + 1] = CopyEvent(event)
        if RANK[event.priority] > RANK[group.priority] then group.priority = event.priority end
        if event.createdAt < group.createdAt then group.createdAt = event.createdAt end
    end
    local selected = order[1]
    for index = 2, #order do
        local candidate = order[index]
        if Before(candidate, candidate.firstIndex, selected, selected.firstIndex) then
            selected = candidate
        end
    end
    return { status = "READY", batchID = selected.batchID,
        events = selected.events, priority = selected.priority }
end

local function RemoveMatching(self, predicate)
    local list, state = self:Read()
    if not list then return nil end
    local nextList, removed = {}, 0
    for _, event in ipairs(list) do
        if predicate(event) then removed = removed + 1
        else nextList[#nextList + 1] = event end
    end
    if removed > 0 then state.notifications = nextList end
    return removed
end

function Queue:Acknowledge(eventID)
    if type(eventID) ~= "string" or eventID == "" then return nil end
    return RemoveMatching(self, function(event) return event.eventID == eventID end)
end

function Queue:AcknowledgeBatch(batchID)
    if type(batchID) ~= "string" or batchID == "" then return nil end
    return RemoveMatching(self, function(event) return event.batchID == batchID end)
end

function Queue:PruneOlderThan(cutoff)
    if not ValidTime(cutoff) then return nil end
    return RemoveMatching(self, function(event) return event.createdAt < cutoff end)
end

function Queue:ClearPresentationQueue()
    return RemoveMatching(self, function() return true end)
end
