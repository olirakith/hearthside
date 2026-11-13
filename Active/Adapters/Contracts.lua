local MS = _G.MS
MS.Active = MS.Active or {}
-- Contrat in the game: turns what the client lets Journey read into facts for the engine.
-- Events wake it up; a one-second poll covers what an event could miss. Every unreadable value
-- becomes "unknown" (a gap for the rules that depended on it), never "nothing happened".
local A = MS.Active
local K = { interval = 1, roster = {} }
A.Contracts = K

local function Engine() return A.ContractEngine end
local function Bool(fn, ...) return A.Bool(A.Call(fn, ...)) end

function K:Current()
    return A:Ready() and A.bucket and A.bucket.contract or nil
end

function K:History()
    return A.bucket and A.bucket.history or {}
end

-- The latest finished sheet the player has not closed yet.
function K:Unseen()
    local latest = self:History()[1]
    if latest and not latest.seen then return latest end
end

function K:Level() local level = A.Call(_G.UnitLevel, "player"); return type(level) == "number" and level or nil end
function K:XP() local xp = A.Call(_G.UnitXP, "player"); return type(xp) == "number" and xp or nil end

-- Group members Journey can name honestly: a readable GUID and name, read now. nil when the
-- party size itself cannot be read: an unknown roster is never an empty one.
function K:Members()
    local members, count = {}, A.Call(_G.GetNumSubgroupMembers)
    if type(count) ~= "number" or count < 0 then return nil end
    for index = 1, math.min(count, 4) do
        local unit = "party" .. index
        local guid, name = A.Call(_G.UnitGUID, unit), A.Call(_G.UnitName, unit)
        if type(guid) == "string" and type(name) == "string" and name ~= "" then
            members[#members + 1] = { unit = unit, guid = guid, name = name }
        else
            members[#members + 1] = { unit = unit }
        end
    end
    return members
end

-- Start and stop the poll with the contract.
function K:Sync()
    local active = self:Current()
    if active and not self.ticker and _G.C_Timer then
        self.ticker = C_Timer.NewTicker(self.interval, function() K:Tick() end)
    elseif not active and self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    if A.Panel then A.Panel:Changed("CONTRACT") end
    if MS.JourneyContractBand then MS.JourneyContractBand:Refresh() end
end

function K:Apply(changes)
    for _, change in ipairs(changes or {}) do
        A:Log("CONTRACT_RULE_STATE", { card = change.card, state = change.status, reason = change.reason })
        if change.status == "BROKEN" and A.Toast then A.Toast:Rule(change.card, "BROKEN") end
    end
    if changes and #changes > 0 and A.Panel then A.Panel:Changed("CONTRACT") end
end

function K:Fact(fact)
    local contract = self:Current()
    if not contract then return end
    self:Apply(Engine():Fact(contract, fact))
end

-- Start ---------------------------------------------------------------------------------------

-- The level cap, when the game says it (nil otherwise: nothing is refused on a guess).
function K:MaxLevel()
    local max = A.Call(_G.GetMaxPlayerLevel)
    return type(max) == "number" and max > 0 and max or nil
end

function K:InDungeon() return Bool(_G.IsInInstance) end

function K:Context(mode)
    local inGroup = Bool(_G.IsInGroup)
    local level, max = self:Level(), self:MaxLevel()
    return { level = level, xp = self:XP(), inGroup = inGroup, caps = A.caps, mode = mode, inInstance = self:InDungeon(),
        maxLevel = level and max and level >= max or false }
end

-- Why a mode cannot be signed right now (nil when it can). A dungeon Contrat starts at the
-- signature, so it is signed inside: nothing on the road there can break it.
function K:Refusal(mode, context)
    if mode == "GROUP" and context.inGroup ~= true then return "NOT_IN_GROUP" end
    if mode == "GROUP" and context.inInstance ~= true then return "NOT_IN_DUNGEON" end
    if mode == "SOLO" and not context.level then return "NO_LEVEL" end
    if mode == "SOLO" and context.maxLevel then return "MAX_LEVEL" end
end

-- The cards a mode can offer right now (the draw and the choose list use the same pool).
function K:Pool(mode)
    local context = self:Context(mode)
    local pool = {}
    for _, id in ipairs(Engine():Pool(mode, A.caps, context.level)) do
        -- Loup solitaire means nothing for a player already grouped (or whose group is unknown).
        if id ~= "LONE_WOLF" or context.inGroup == false then pool[#pool + 1] = id end
    end
    return pool, context
end

-- The default draw only deals cards Journey can actually keep: a card on trial (never seen
-- working on this build) can still be chosen by hand, with its warning.
function K:Draw(mode)
    local all, context = self:Pool(mode)
    local pool = {}
    for _, id in ipairs(all) do
        if not Engine():OnTrial(id, mode, A.caps) then pool[#pool + 1] = id end
    end
    local cards = Engine():Draw(pool, mode, context.level, A.random or math.random)
    A:Log("CONTRACT_CREATED", { mode = mode, source = "DRAW", cards = self.CardList(cards) })
    return cards
end

-- Three Contrats for the live view's vote, from the same pool as a single draw.
function K:DrawOptions(mode, count)
    local all, context = self:Pool(mode)
    -- Cards on trial only when the proven ones cannot make the Contrats differ.
    local pool, trial = {}, {}
    for _, id in ipairs(all) do
        if Engine():OnTrial(id, mode, A.caps) then trial[#trial + 1] = id else pool[#pool + 1] = id end
    end
    local options = Engine():DrawOptions(pool, mode, context.level, A.random or math.random, count or 3, trial)
    A:Log("CONTRACT_CREATED", { mode = mode, source = "POLL", cards = #options })
    return options
end

function K.CardList(cards)
    local ids = {}
    for _, card in ipairs(cards or {}) do ids[#ids + 1] = type(card) == "table" and card.id or card end
    return table.concat(ids, ",")
end

function K:Start(mode, cards, source)
    if not A:Ready() or not A.bucket then return nil, "NOT_READY" end
    if self:Current() then return nil, "ALREADY_RUNNING" end
    -- A Contrat starts alive: a ghost would carry a death it never had the chance to avoid.
    if A.Bool(A.Call(_G.UnitIsDeadOrGhost, "player")) == true then return nil, "DEAD" end
    local pool, context = self:Pool(mode)
    local refusal = self:Refusal(mode, context)
    if refusal then return nil, refusal end
    local allowed = {}
    for _, id in ipairs(pool) do allowed[id] = true end
    for _, card in ipairs(cards or {}) do
        if not allowed[type(card) == "table" and card.id or card] then return nil, "CARD" end
    end
    local names = {}
    if mode == "GROUP" then
        for _, member in ipairs(self:Members() or {}) do if member.name then names[#names + 1] = member.name end end
    end
    local inInstance = Bool(_G.IsInInstance)
    local instance = inInstance == true and A.Call(_G.GetInstanceInfo) or nil
    local random = A.random or math.random
    local contract, reason = Engine():Start({ mode = mode, source = source, cards = cards, caps = A.caps, level = context.level,
        xp = context.xp, inGroup = context.inGroup, instance = type(instance) == "string" and instance or nil, names = names,
        id = string.format("%04x%04x", random(0, 65535), random(0, 65535)), now = A.Now() })
    if not contract then return nil, reason end
    if source == "CHOOSE" then A:Log("CONTRACT_CREATED", { mode = mode, source = "CHOOSE", cards = self.CardList(cards) }) end
    -- The group already read these very rules before the signature: that was the start line.
    if mode == "GROUP" and self.proposal and self.proposal == self.CardList(contract.cards) then contract.announced.start = true end
    self.proposal = nil
    A.bucket.contract = contract
    if A.Call(_G.GetServerTime) then A:Prove("ServerTime", "SERVER_TIME_READ") end
    self:ResetRoster()
    self.wasInInstance = inInstance == true
    A:Log("CONTRACT_STARTED", { mode = mode, cards = self.CardList(contract.cards), group = #names })
    self:Sync()
    return contract
end

-- Watching ------------------------------------------------------------------------------------

-- The party as it is now, by GUID (names only for the sheet). Unreadable members are kept as
-- unknown so that a silence is never taken for "still there".
function K:ResetRoster()
    self.roster, self.aliveSeen = {}, {}
    for _, member in ipairs(self:Members() or {}) do
        if member.guid then self.roster[member.guid] = member.name end
    end
end

function K:WatchParty(contract)
    if contract.mode ~= "GROUP" then return end
    local members = self:Members()
    if not members then
        -- The party could not be read: keep the last roster, prove nothing, lose coverage.
        self:Fact({ type = "GAP", scope = "party", reason = "MEMBER_UNREADABLE" })
        return
    end
    local present, unknown = {}, false
    for _, member in ipairs(members) do
        if member.guid then
            present[member.guid] = true
            if not self.roster[member.guid] then
                self.roster[member.guid] = member.name
                local names = contract.group.names
                if #names < Engine().nameLimit then names[#names + 1] = member.name end
            end
            local connected = Bool(_G.UnitIsConnected, member.unit)
            local dead = Bool(_G.UnitIsDeadOrGhost, member.unit)
            if dead == false then self.aliveSeen[member.guid] = true end
            if connected ~= true then
                -- Disconnected, or a connection state the game would not show: not watched.
                self:Fact({ type = "GAP", scope = "party", reason = connected == false and "DISCONNECTED" or "MEMBER_UNREADABLE" })
            elseif dead == true and not self.aliveSeen[member.guid] then
                -- Dead since before Journey could watch them (contract start, reload, join):
                -- not a death of this contract, but not something Journey saw either.
                self:Fact({ type = "GAP", scope = "party", reason = "DEAD_WHEN_SEEN" })
            elseif dead == true then
                local feign
                if type(_G.UnitIsFeignDeath) == "function" then feign = Bool(_G.UnitIsFeignDeath, member.unit) end
                if feign == false then
                    A:Prove("PartyDeath", "PARTY_DEAD_READ")
                    self:Fact({ type = "DEATH", scope = "party", who = member.name, reason = "PARTY_DEAD", at = A.Now() })
                elseif feign == nil then
                    -- A hunter playing dead looks the same without the API to tell them apart.
                    self:Fact({ type = "UNREADABLE", card = "ZERO_DEATH", reason = "FEIGN_UNKNOWN" })
                end
            elseif dead == nil then
                self:Fact({ type = "UNREADABLE", card = "ZERO_DEATH", reason = "SECRET" })
            end
        else
            unknown = true
        end
    end
    if unknown then self:Fact({ type = "GAP", scope = "party", reason = "MEMBER_UNREADABLE" }) end
    for guid, name in pairs(self.roster) do
        if not present[guid] and not unknown then
            self.roster[guid] = nil
            A:Prove("GroupRoster", "MEMBER_LEFT")
            self:Fact({ type = "MEMBER_LEFT", scope = "party", who = name, reason = "MEMBER_LEFT", at = A.Now() })
        end
    end
end

function K:Tick()
    local contract = self:Current()
    if not contract then self:Sync(); return end
    if not A.Position:Settled() then return end
    self:Observe(contract)
    if self:Lost(contract) then self:Finish("ENDED"); return end
    self:CheckGoal(contract)
    self:CheckInstance(contract)
    if MS.JourneyContractBand then MS.JourneyContractBand:Refresh() end
end

-- A solo Contrat cannot be won back once a rule is broken, so it ends there. A dungeon run goes on:
-- the group is still playing, and the player closes it.
function K:Lost(contract)
    if contract.mode ~= "SOLO" then return false end
    for _, rule in pairs(contract.rules) do
        if rule.status == "BROKEN" then return true end
    end
    return false
end

-- One reading of every watched rule: the poll, and once more right before any verdict.
function K:Observe(contract)
    local now = A.Now()
    self:Apply(Engine():Tick(contract, now))
    local dead = Bool(_G.UnitIsDeadOrGhost, "player")
    if dead == true then
        A:Prove("PlayerDeath", "PLAYER_DEAD_READ")
        self:Fact({ type = "DEATH", scope = "player", reason = "PLAYER_DEAD", at = now })
    elseif dead == nil and contract.rules.ZERO_DEATH then
        self:Fact({ type = "UNREADABLE", card = "ZERO_DEATH", reason = "UNREADABLE" })
    end
    local taxi = Bool(_G.UnitOnTaxi, "player")
    if contract.rules.NO_FLIGHT then
        if taxi == true then A:Prove("Taxi", "ON_TAXI_READ"); self:Fact({ type = "TAXI", reason = "ON_TAXI", at = now })
        elseif taxi == nil then self:Fact({ type = "UNREADABLE", card = "NO_FLIGHT", reason = "UNREADABLE" }) end
    end
    if contract.rules.ON_FOOT and taxi ~= true then
        local mounted = Bool(_G.IsMounted)
        if mounted == true then A:Prove("Mount", "MOUNTED_READ"); self:Fact({ type = "MOUNT", reason = "MOUNTED", at = now })
        elseif mounted == nil then self:Fact({ type = "UNREADABLE", card = "ON_FOOT", reason = "UNREADABLE" }) end
    end
    if contract.rules.LONE_WOLF then
        local grouped = Bool(_G.IsInGroup)
        if grouped == true then A:Prove("GroupRoster", "GROUP_JOINED"); self:Fact({ type = "GROUP_JOINED", reason = "GROUPED", at = now })
        elseif grouped == nil then self:Fact({ type = "UNREADABLE", card = "LONE_WOLF", reason = "UNREADABLE" }) end
    end
    self:WatchParty(contract)
end

function K:CheckGoal(contract)
    local level = self:Level()
    if Engine():GoalReached(contract, level) then self:Finish("GOAL") end
end

-- Leaving the dungeon after having been inside asks once whether the run is over; Journey
-- never decides it on its own (leaving proves neither a win nor a wipe).
function K:CheckInstance(contract)
    if contract.mode ~= "GROUP" then return end
    local inside = Bool(_G.IsInInstance)
    if inside == true then
        if not contract.goal.instance then
            local name = A.Call(_G.GetInstanceInfo)
            if type(name) == "string" and name ~= "" then contract.goal.instance = A.Text.CleanLine(name, 64) end
        end
        self.wasInInstance = true
    elseif inside == false and self.wasInInstance then
        self.wasInInstance = false
        if A.Toast then A.Toast:Prompt() end
    end
end

-- Events --------------------------------------------------------------------------------------

function K:OnEvent(event, ...)
    -- Evidence is gathered with or without a contract: a death or the auction house, seen as it
    -- happens, proves the capability on this build (nothing about it is stored but the proof).
    if event == "PLAYER_DEAD" and Bool(_G.UnitIsDeadOrGhost, "player") == true then A:Prove("PlayerDeath", "PLAYER_DEAD_EVENT") end
    if event == "AUCTION_HOUSE_SHOW" then A:Prove("AuctionHouse", "AUCTION_HOUSE_SHOW") end
    local contract = self:Current()
    if not contract then return end
    if event == "PLAYER_DEAD" then
        self:Fact({ type = "DEATH", scope = "player", reason = "PLAYER_DEAD", at = A.Now() })
    elseif event == "AUCTION_HOUSE_SHOW" then
        self:Fact({ type = "AUCTION", reason = "AUCTION_OPENED", at = A.Now() })
    elseif event == "PLAYER_LEVEL_UP" then
        local level = self:Level()
        if level and contract.goal.from and level > contract.goal.from then A:Prove("LevelUp", "PLAYER_LEVEL_UP") end
        self:CheckGoal(contract)
    elseif event == "PLAYER_XP_UPDATE" then
        self:CheckGoal(contract)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
        local unit = A.Readable((...))
        if event == "GROUP_ROSTER_UPDATE" or (type(unit) == "string" and unit:find("^party%d$")) then self:WatchParty(contract) end
        if event == "GROUP_ROSTER_UPDATE" and contract.rules.LONE_WOLF and Bool(_G.IsInGroup) == true then
            A:Prove("GroupRoster", "GROUP_JOINED")
            self:Fact({ type = "GROUP_JOINED", reason = "GROUPED", at = A.Now() })
        end
    end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_DEAD", "AUCTION_HOUSE_SHOW", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "GROUP_ROSTER_UPDATE",
    "UNIT_HEALTH", "UNIT_FLAGS" }) do
    -- Forever may lack an event on some builds: registration never breaks load.
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    if not A.initialized then return end
    local ok, failure = pcall(K.OnEvent, K, event, ...)
    if not ok then A:Log("COMPONENT_ERROR", { component = "Contracts", phase = event, reason = tostring(failure) }) end
end)

-- Lifecycle -----------------------------------------------------------------------------------

-- reloading: the game confirmed a /reload (anything else is a new login: a logout, a disconnect
-- or a crash).
function K:OnLogin(_, reloading)
    -- Reading the server clock is the whole proof the time card needs.
    if type(A.Call(_G.GetServerTime)) == "number" then A:Prove("ServerTime", "SERVER_TIME_READ") end
    local contract = self:Current()
    if contract then
        local changes = Engine():Resume(contract, { level = self:Level(), xp = self:XP(),
            dead = Bool(_G.UnitIsDeadOrGhost, "player"), at = A.Now(), reload = reloading == true })
        for _, change in ipairs(changes) do
            if change.status == "UNCERTAIN" then
                A:Log("CONTRACT_INTERRUPTED", { reason = change.reason, scope = change.card })
            end
        end
        self:Apply(changes)
        self:ResetRoster()
        self.wasInInstance = Bool(_G.IsInInstance) == true
    end
    self:Sync()
    -- A sheet the player never closed comes back.
    if self:Unseen() and A.Sheet then A.Sheet:Queue() end
end

function K:OnLogout()
    local contract = self:Current()
    if contract then
        Engine():Snapshot(contract, { level = self:Level(), xp = self:XP(),
            alive = A.Bool(A.Call(_G.UnitIsDeadOrGhost, "player")) == false and true or nil, at = A.Now() })
    end
end

-- outcome: GOAL | ENDED | ABANDONED
function K:Finish(outcome)
    local contract = self:Current()
    if not contract or self.finishing then return nil end
    -- Every rule is read one last time at the moment the contract ends (the clock included): an
    -- event-driven end (level up) must not outrun the poll.
    self.finishing = true
    local ok, failure = pcall(self.Observe, self, contract)
    self.finishing = false
    if not ok then A:Log("COMPONENT_ERROR", { component = "Contracts", phase = "FINAL_OBSERVE", reason = tostring(failure) }) end
    local result = Engine():Finish(contract, outcome, A.Now(), A.caps, { name = A.identity.firstName, level = self:Level() })
    A:Log("CONTRACT_COMPLETED", { mode = contract.mode, outcome = outcome, verdict = result.verdict, duration = result.duration })
    local counts = result.counts
    A:Log("CONTRACT_RESULT_GENERATED", { verdict = result.verdict, kept = counts.KEPT, broken = counts.BROKEN + counts.DECLARED_BROKEN,
        unverifiable = counts.UNVERIFIABLE, honor = counts.HONOR })
    Engine():Archive(A.bucket, contract)
    self:Sync()
    if A.Sheet then A.Sheet:Queue() end
    return result
end

function K:Declare(result, id, broken)
    if Engine():Declare(result, id, broken) then
        A:Log("CONTRACT_RULE_STATE", { card = id, state = broken and "DECLARED_BROKEN" or "HONOR", reason = "PLAYER" })
        return true
    end
end

-- Announce ------------------------------------------------------------------------------------

-- At most one start line and one result line per contract, prepared in the chat box.
-- A group Contrat is put to the group before it is signed: the rules, prepared in the group chat
-- line (never sent). Signing those same rules afterwards counts it as the start line.
function K:Propose(cards)
    if self:Current() then return false, "ALREADY" end
    local prefix = A.Chat:GroupPrefix()
    if not prefix then A:Log("CONTRACT_ANNOUNCED", { phase = "PROPOSAL", result = "NOT_IN_GROUP" }); return false, "NOT_IN_GROUP" end
    local key = self.CardList(cards)
    if key == "" then return false, "NO_TEXT" end
    if self.proposal == key then return false, "ALREADY" end
    local ok, reason = A.Chat:Prefill(prefix, A.ContractText:ProposalLine(cards, "GROUP"))
    A:Log("CONTRACT_ANNOUNCED", { phase = "PROPOSAL", result = ok and "PREFILLED" or reason })
    if ok then self.proposal = key end
    return ok, reason
end

function K:Announce(phase, result)
    local contract = self:Current()
    local prefix = ""
    local mode = phase == "START" and contract and contract.mode or result and result.mode
    if mode == "GROUP" then
        prefix = A.Chat:GroupPrefix()
        if not prefix then A:Log("CONTRACT_ANNOUNCED", { phase = phase, result = "NOT_IN_GROUP" }); return false, "NOT_IN_GROUP" end
    end
    local text
    if phase == "START" then
        if not contract or contract.announced.start then return false, "ALREADY" end
        text = A.ContractText:StartLine(contract)
    else
        if not result or result.announced then return false, "ALREADY" end
        text = A.ContractText:ResultLine(result, A.Chat.limit - #prefix)
    end
    local ok, reason = A.Chat:Prefill(prefix, text)
    A:Log("CONTRACT_ANNOUNCED", { phase = phase, result = ok and "PREFILLED" or reason })
    if ok then
        if phase == "START" then contract.announced.start = true else result.announced = true end
    end
    return ok, reason
end

A:Register("Contracts", K)
