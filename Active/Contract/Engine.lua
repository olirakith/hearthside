local MS = _G.MS
MS.Active = MS.Active or {}
-- Contrat domain. Pure: facts, clocks, capabilities and identities come from the adapters.
--
-- Truth policy:
--   ROMPU            a positive, readable violation was observed (it also proves the capability).
--   TENU             the capability is READY on this build, coverage never broke, the end came.
--   NON VERIFIABLE   anything else for an observed card: a gap, an unreadable value, a capability
--                    never seen working on this build. Never turned into ROMPU.
--   SUR L'HONNEUR    honor cards; the player may declare one broken ("ROMPU · déclaré").
local Engine = { schema = 1, historyLimit = 20, nameLimit = 4 }
MS.Active.ContractEngine = Engine

local function Num(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function Id(value) return type(value) == "string" and value:find("^%x%x%x%x%x%x%x%x$") ~= nil end
local function Catalog() return MS.Active.ContractCatalog end

Engine.modes = { SOLO = true, GROUP = true }
-- Facts that leave no trace once missed: a gap makes these cards uncertain.
Engine.gapScopes = {
    DEATH = { player = true, party = true, all = true },
    TAXI = { player = true, all = true }, MOUNT = { player = true, all = true }, AUCTION = { player = true, all = true },
    GROUP_JOINED = { player = true, all = true }, MEMBER_LEFT = { party = true, all = true },
}

local function Usable(caps, names)
    for _, name in ipairs(names) do
        if not MS.Active.Capabilities.Usable(caps and caps[name]) then return false end
    end
    return true
end

local function Ready(caps, names)
    for _, name in ipairs(names) do if not (caps and caps[name] == "READY") then return false end end
    return true
end

-- Cards this mode can use now: their capabilities are present, their level is reached.
function Engine:Pool(mode, caps, level)
    local pool = {}
    for _, id in ipairs(Catalog().order) do
        local card = Catalog().cards[id]
        if card.scopes[mode] and (not card.minLevel or (Num(level) and level >= card.minLevel))
            and (card.mode == "HONOR" or Usable(caps, Catalog().Capabilities(id, mode))) then
            pool[#pool + 1] = id
        end
    end
    return pool
end

-- "On trial": an observed card whose capabilities are not all READY on this build yet.
function Engine:OnTrial(id, mode, caps)
    local card = Catalog().cards[id]
    return card ~= nil and card.mode == "OBSERVED" and not Ready(caps, Catalog().Capabilities(id, mode))
end

local function Param(id, mode, level)
    if id == "TIME_LIMIT" then return Catalog().TimeLimit(mode, level) end
end

-- Three cards from a pool (Engine:Pool, possibly narrowed by the context): two observed and one
-- on honor when the pool allows it, otherwise whatever fits.
function Engine:Draw(pool, mode, level, random)
    local observed, honor = {}, {}
    for _, id in ipairs(pool) do
        if Catalog().cards[id].mode == "OBSERVED" then observed[#observed + 1] = id else honor[#honor + 1] = id end
    end
    local function Take(list)
        if #list == 0 then return nil end
        return table.remove(list, random(1, #list))
    end
    local picked = {}
    for _ = 1, 2 do picked[#picked + 1] = Take(observed) end
    picked[#picked + 1] = Take(honor)
    while #picked < 3 and (#observed > 0 or #honor > 0) do picked[#picked + 1] = Take(observed) or Take(honor) end
    -- Display order follows the catalog, so a re-draw of the same cards looks the same.
    local rank = {}
    for index, id in ipairs(Catalog().order) do rank[id] = index end
    table.sort(picked, function(a, b) return rank[a] < rank[b] end)
    local cards = {}
    for _, id in ipairs(picked) do cards[#cards + 1] = { id = id, param = Param(id, mode, level) } end
    return cards
end

-- Several Contrats side by side for a vote, each of two observed rules and one of honour like a
-- single draw. A card comes, in this order of preference: from the pool and in no earlier
-- Contrat; from `spare` (cards on trial) and in no earlier Contrat; from the pool again; from
-- `spare` again. So the Contrats differ whenever the catalogue allows, and never hold a card twice.
function Engine:DrawOptions(pool, mode, level, random, count, spare)
    local options, used, rank = {}, {}, {}
    for index, id in ipairs(Catalog().order) do rank[id] = index end
    local function Observed(id) return Catalog().cards[id].mode == "OBSERVED" end
    for _ = 1, count or 3 do
        local cards, held = {}, {}
        local function Take(kind)
            for _, source in ipairs({ { pool, false }, { spare or {}, false }, { pool, true }, { spare or {}, true } }) do
                local list = {}
                for _, id in ipairs(source[1]) do
                    if not held[id] and (source[2] or not used[id]) and (kind == nil or Observed(id) == kind) then list[#list + 1] = id end
                end
                if #list > 0 then
                    local id = list[random(1, #list)]
                    held[id] = true
                    cards[#cards + 1] = { id = id, param = Param(id, mode, level) }
                    return true
                end
            end
            return false
        end
        Take(true); Take(true); Take(false)
        while #cards < 3 and Take(nil) do end
        table.sort(cards, function(a, b) return rank[a.id] < rank[b.id] end)
        for id in pairs(held) do used[id] = true end
        options[#options + 1] = cards
    end
    return options
end

-- input: { mode, source = DRAW|CHOOSE, cards = { ids or {id=} }, caps, level, xp, inGroup,
--          instance (name or nil), names (group, honestly known), id, now }
-- Returns the ACTIVE contract or nil, reason.
function Engine:Start(input)
    if not self.modes[input.mode] then return nil, "MODE" end
    if not Num(input.now) then return nil, "NO_TIME" end
    if input.mode == "GROUP" and input.inGroup ~= true then return nil, "NOT_IN_GROUP" end
    if input.mode == "SOLO" and not Num(input.level) then return nil, "NO_LEVEL" end
    local allowed, seen, cards = {}, {}, {}
    for _, id in ipairs(self:Pool(input.mode, input.caps, input.level)) do allowed[id] = true end
    for _, entry in ipairs(input.cards or {}) do
        local id = type(entry) == "table" and entry.id or entry
        if not allowed[id] or seen[id] then return nil, "CARD" end
        seen[id] = true
        cards[#cards + 1] = { id = id, param = Param(id, input.mode, input.level) }
    end
    if #cards < 1 or #cards > 3 then return nil, "CARD_COUNT" end
    local contract = { schema = self.schema, id = input.id, mode = input.mode, source = input.source == "CHOOSE" and "CHOOSE" or "DRAW",
        state = "ACTIVE", startedAt = input.now, cards = cards, rules = {}, announced = {} }
    if input.mode == "SOLO" then
        contract.goal = { kind = "LEVEL", from = input.level, target = input.level + 1 }
    else
        contract.goal = { kind = "DUNGEON", instance = MS.Active.Text.CleanLine(input.instance, 64) }
    end
    contract.group = { names = {} }
    for _, name in ipairs(input.names or {}) do
        local clean = MS.Active.Text.CleanLine(name, 64)
        if #contract.group.names < self.nameLimit and clean then contract.group.names[#contract.group.names + 1] = clean end
    end
    for _, card in ipairs(cards) do
        contract.rules[card.id] = { status = Catalog().cards[card.id].mode == "HONOR" and "HONOR" or "WATCHING" }
    end
    contract.snapshot = { level = input.level, xp = input.xp, alive = true, at = input.now }
    return contract
end

local function Change(changes, id, status, reason)
    changes[#changes + 1] = { card = id, status = status, reason = reason }
end

-- fact: { type = DEATH|TAXI|MOUNT|AUCTION|GROUP_JOINED|MEMBER_LEFT, scope = player|party, who, at }
--     | { type = GAP, scope = player|party|all, reason }
--     | { type = UNREADABLE, card = id, reason }
-- Returns the list of rule changes (for diagnostics and the rule toast).
function Engine:Fact(contract, fact)
    local changes = {}
    if type(contract) ~= "table" or contract.state ~= "ACTIVE" or type(fact) ~= "table" then return changes end
    for _, card in ipairs(contract.cards) do
        local rule, def = contract.rules[card.id], Catalog().cards[card.id]
        if rule.status == "WATCHING" then
            if fact.type == def.fact then
                -- A solo contract judges the player only; a group one, the whole party.
                if def.fact ~= "DEATH" or contract.mode == "GROUP" or fact.scope == "player" then
                    rule.status, rule.reason, rule.at = "BROKEN", fact.reason or fact.type, fact.at
                    rule.who = MS.Active.Text.CleanLine(fact.who, 64)
                    Change(changes, card.id, "BROKEN", rule.reason)
                end
            elseif fact.type == "GAP" and self.gapScopes[def.fact] and self.gapScopes[def.fact][fact.scope] then
                if not rule.uncertain then
                    rule.uncertain = fact.reason or "GAP"
                    Change(changes, card.id, "UNCERTAIN", rule.uncertain)
                end
            elseif fact.type == "UNREADABLE" and fact.card == card.id and not rule.uncertain then
                rule.uncertain = fact.reason or "UNREADABLE"
                Change(changes, card.id, "UNCERTAIN", rule.uncertain)
            end
        end
    end
    return changes
end

-- Seconds since the start; a finished contract keeps its own end.
function Engine:Elapsed(contract, now)
    local finish = contract.endedAt or now
    if not Num(finish) or not Num(contract.startedAt) then return nil end
    return math.max(0, finish - contract.startedAt)
end

-- The clock card breaks as soon as the limit is passed, not only at the end.
function Engine:Tick(contract, now)
    local changes = {}
    if type(contract) ~= "table" or contract.state ~= "ACTIVE" then return changes end
    local rule = contract.rules.TIME_LIMIT
    if rule and rule.status == "WATCHING" then
        local limit, elapsed = self:Param(contract, "TIME_LIMIT"), self:Elapsed(contract, now)
        if limit and elapsed and elapsed > limit then
            rule.status, rule.reason, rule.at = "BROKEN", "TIME", now
            Change(changes, "TIME_LIMIT", "BROKEN", "TIME")
        end
    end
    return changes
end

function Engine:Param(contract, id)
    for _, card in ipairs(contract.cards) do if card.id == id then return card.param end end
end

-- The level goal is read from the level itself (READY on Forever), the event only wakes us.
function Engine:GoalReached(contract, level)
    return contract.state == "ACTIVE" and contract.goal.kind == "LEVEL" and Num(level) and level >= contract.goal.target
end

-- What Journey can last vouch for, written at every logout and reload.
function Engine:Snapshot(contract, observation)
    if type(contract) ~= "table" or contract.state ~= "ACTIVE" then return end
    contract.snapshot = { level = observation.level, xp = observation.xp, alive = observation.alive, at = observation.at }
end

-- A /reload is continuous coverage only when the snapshot was written by that very reload: the
-- loading screen lasts seconds and no gameplay action (mount, flight, trade, invite) can happen
-- in it; a death in it is still read at login. Anything longer is an interruption.
Engine.reloadWindow = 60

-- After a reload, a logout, a disconnect or a crash.
-- observation: { level, xp, dead (true|false|nil), at, reload (a /reload, not a new login) }
-- A death seen at login is a fact; anything Journey could not have watched is a gap.
function Engine:Resume(contract, observation)
    local changes = {}
    if type(contract) ~= "table" or contract.state ~= "ACTIVE" then return changes end
    local function Merge(list) for _, change in ipairs(list) do changes[#changes + 1] = change end end
    local snapshot = contract.snapshot
    if observation.dead == true and not (snapshot and snapshot.alive == false) then
        Merge(self:Fact(contract, { type = "DEATH", scope = "player", reason = "DEAD_AT_LOGIN", at = observation.at }))
    end
    if type(snapshot) ~= "table" or not Num(snapshot.level) then
        Merge(self:Fact(contract, { type = "GAP", scope = "all", reason = "NO_SNAPSHOT" }))
    elseif observation.level ~= snapshot.level or (Num(snapshot.xp) and observation.xp ~= snapshot.xp) then
        -- Progress Journey did not see (a crash after the last save, another addon client...).
        Merge(self:Fact(contract, { type = "GAP", scope = "all", reason = "UNOBSERVED_PROGRESS" }))
    elseif not (observation.reload == true and Num(snapshot.xp) and Num(observation.xp)
        and Num(snapshot.at) and Num(observation.at)
        and observation.at >= snapshot.at and observation.at - snapshot.at <= self.reloadWindow) then
        -- Logged out, disconnected, crashed, a stale snapshot or an XP Journey could not read on
        -- either side: same level does not prove that nothing happened meanwhile (a flight, a
        -- mount, a death and a resurrection).
        Merge(self:Fact(contract, { type = "GAP", scope = "all", reason = "INTERRUPTED" }))
    end
    if observation.dead == nil then Merge(self:Fact(contract, { type = "GAP", scope = "player", reason = "UNREADABLE" })) end
    -- The rest of the group was not watched during the reload: a party member may have died and
    -- been brought back, or the player resurrected by them.
    if contract.mode == "GROUP" then Merge(self:Fact(contract, { type = "GAP", scope = "all", reason = "RELOAD" })) end
    return changes
end

local function Verdict(contract, card, caps)
    local rule, def = contract.rules[card.id], Catalog().cards[card.id]
    if rule.status == "BROKEN" then return "BROKEN", rule.reason end
    if rule.status == "DECLARED_BROKEN" then return "DECLARED_BROKEN" end
    if rule.status == "HONOR" then return "HONOR" end
    if rule.uncertain then return "UNVERIFIABLE", rule.uncertain end
    if not Ready(caps, Catalog().Capabilities(card.id, contract.mode)) then return "UNVERIFIABLE", "UNPROVEN" end
    if def.fact == "TIME" then
        local limit, elapsed = card.param, Engine:Elapsed(contract)
        if not limit or not elapsed then return "UNVERIFIABLE", "NO_TIME" end
        if elapsed > limit then return "BROKEN", "TIME" end
    end
    return "KEPT"
end

-- Ends the contract. outcome: GOAL (level reached) | ENDED (a dungeon run closed, a solo rule broken) |
-- ABANDONED. Builds the end sheet (contract.result), locale-neutral so Journey Poster can use it.
function Engine:Finish(contract, outcome, now, caps, character)
    if type(contract) ~= "table" or contract.state ~= "ACTIVE" then return nil end
    contract.state, contract.endedAt, contract.outcome = "FINISHED", Num(now) and now or contract.startedAt, outcome
    local rules = {}
    for _, card in ipairs(contract.cards) do
        local verdict, reason = Verdict(contract, card, caps)
        local rule = contract.rules[card.id]
        rules[#rules + 1] = { card = card.id, mode = Catalog().cards[card.id].mode, param = card.param, verdict = verdict,
            reason = reason, who = rule.who }
    end
    local goal = contract.goal
    contract.result = { schema = self.schema, id = contract.id, mode = contract.mode, outcome = outcome,
        context = { goal = goal.kind, from = goal.from, target = goal.target, reached = outcome == "GOAL" or nil, instance = goal.instance },
        startedAt = contract.startedAt, endedAt = contract.endedAt, duration = self:Elapsed(contract),
        rules = rules, group = { names = contract.group and contract.group.names or {} },
        character = type(character) == "table" and { name = character.name, level = character.level } or nil }
    self:Judge(contract.result)
    return contract.result
end

-- Overall verdict from the rule verdicts (recomputed after a declaration). A contract is only
-- plainly KEPT when Journey saw every rule held; honor rules make it KEPT_HONOR (observed rules
-- held, the rest on honor) or HONOR (nothing observed at all).
function Engine:Judge(result)
    local counts = { KEPT = 0, BROKEN = 0, UNVERIFIABLE = 0, HONOR = 0, DECLARED_BROKEN = 0 }
    for _, rule in ipairs(result.rules) do counts[rule.verdict] = (counts[rule.verdict] or 0) + 1 end
    if result.outcome == "ABANDONED" then result.verdict = "ABANDONED"
    elseif counts.BROKEN + counts.DECLARED_BROKEN > 0 then result.verdict = "BROKEN"
    elseif counts.UNVERIFIABLE > 0 then result.verdict = "UNVERIFIABLE"
    elseif counts.HONOR > 0 then result.verdict = counts.KEPT > 0 and "KEPT_HONOR" or "HONOR"
    else result.verdict = "KEPT" end
    result.counts = counts
    return result.verdict
end

-- The player owns up to breaking an honor rule. It is recorded as declared, never observed;
-- a declaration can be withdrawn, an observation cannot.
function Engine:Declare(result, id, broken)
    for _, rule in ipairs(result.rules or {}) do
        if rule.card == id and rule.mode == "HONOR" then
            rule.verdict = broken and "DECLARED_BROKEN" or "HONOR"
            self:Judge(result)
            return true
        end
    end
    return false
end

-- SavedVariables validation ------------------------------------------------------------------

local RULE_STATUS = { WATCHING = true, BROKEN = true, HONOR = true }
local VERDICTS = { KEPT = true, BROKEN = true, UNVERIFIABLE = true, HONOR = true, DECLARED_BROKEN = true }
local OUTCOMES = { GOAL = true, ENDED = true, ABANDONED = true }

local function Short(value, limit)
    if type(value) ~= "string" or value == "" then return nil end
    return MS.Active.Text.CleanLine(value, limit)
end

local function Cards(raw, mode)
    if type(raw) ~= "table" or #raw < 1 or #raw > 3 then return nil end
    local cards, seen = {}, {}
    for _, card in ipairs(raw) do
        local def = type(card) == "table" and Catalog().cards[card.id]
        if not def or not def.scopes[mode] or seen[card.id] then return nil end
        seen[card.id] = true
        local param = card.param
        if card.id == "TIME_LIMIT" and not (Num(param) and param > 0) then return nil end
        cards[#cards + 1] = { id = card.id, param = card.id == "TIME_LIMIT" and param or nil }
    end
    return cards
end

local function Names(raw)
    local names = {}
    for _, name in ipairs(type(raw) == "table" and raw or {}) do
        local clean = Short(name, 64)
        if clean and #names < Engine.nameLimit then names[#names + 1] = clean end
    end
    return names
end

local function Goal(raw, mode)
    if type(raw) ~= "table" then return nil end
    if mode == "SOLO" and raw.kind == "LEVEL" and Num(raw.from) and Num(raw.target) and raw.target == raw.from + 1 then
        return { kind = "LEVEL", from = raw.from, target = raw.target }
    elseif mode == "GROUP" and raw.kind == "DUNGEON" then
        return { kind = "DUNGEON", instance = Short(raw.instance, 64) }
    end
end

-- A running contract. Anything that does not check out is dropped (nothing invented): the
-- player simply has no contract running.
function Engine:SanitizeContract(raw)
    if type(raw) ~= "table" or raw.schema ~= self.schema or raw.state ~= "ACTIVE" or not Id(raw.id)
        or not self.modes[raw.mode] or not Num(raw.startedAt) then return nil end
    local cards = Cards(raw.cards, raw.mode)
    local goal = Goal(raw.goal, raw.mode)
    if not cards or not goal or type(raw.rules) ~= "table" then return nil end
    local contract = { schema = self.schema, id = raw.id, mode = raw.mode, source = raw.source == "CHOOSE" and "CHOOSE" or "DRAW",
        state = "ACTIVE", startedAt = raw.startedAt, cards = cards, goal = goal, rules = {},
        group = { names = Names(type(raw.group) == "table" and raw.group.names) },
        announced = { start = type(raw.announced) == "table" and raw.announced.start == true or nil } }
    for _, card in ipairs(cards) do
        local rule, honor = raw.rules[card.id], Catalog().cards[card.id].mode == "HONOR"
        if type(rule) ~= "table" or not RULE_STATUS[rule.status] or (rule.status == "HONOR") ~= honor then return nil end
        contract.rules[card.id] = { status = rule.status, reason = Short(rule.reason, 24), at = Num(rule.at) and rule.at or nil,
            who = Short(rule.who, 64), uncertain = Short(rule.uncertain, 24) }
    end
    local snapshot = raw.snapshot
    if type(snapshot) == "table" and Num(snapshot.level) then
        contract.snapshot = { level = snapshot.level, xp = Num(snapshot.xp) and snapshot.xp or nil,
            alive = type(snapshot.alive) == "boolean" and snapshot.alive or nil, at = Num(snapshot.at) and snapshot.at or nil }
    end
    return contract
end

function Engine:SanitizeResult(raw)
    if type(raw) ~= "table" or raw.schema ~= self.schema or not Id(raw.id) or not self.modes[raw.mode]
        or not OUTCOMES[raw.outcome] or not Num(raw.startedAt) or not Num(raw.endedAt) or type(raw.rules) ~= "table" then return nil end
    local result = { schema = self.schema, id = raw.id, mode = raw.mode, outcome = raw.outcome, startedAt = raw.startedAt,
        endedAt = raw.endedAt, duration = math.max(0, raw.endedAt - raw.startedAt), rules = {},
        group = { names = Names(type(raw.group) == "table" and raw.group.names) }, announced = raw.announced == true or nil,
        seen = raw.seen == true or nil }
    local context = type(raw.context) == "table" and raw.context or {}
    if context.goal ~= "LEVEL" and context.goal ~= "DUNGEON" then return nil end
    result.context = { goal = context.goal, from = Num(context.from) and context.from or nil, target = Num(context.target) and context.target or nil,
        reached = context.reached == true or nil, instance = Short(context.instance, 64) }
    for index, rule in ipairs(raw.rules) do
        local def = type(rule) == "table" and Catalog().cards[rule.card]
        if index > 3 or not def or not VERDICTS[rule.verdict] or rule.mode ~= def.mode then return nil end
        if def.mode == "HONOR" and rule.verdict ~= "HONOR" and rule.verdict ~= "DECLARED_BROKEN" then return nil end
        if def.mode == "OBSERVED" and (rule.verdict == "HONOR" or rule.verdict == "DECLARED_BROKEN") then return nil end
        result.rules[#result.rules + 1] = { card = rule.card, mode = def.mode, param = Num(rule.param) and rule.param or nil,
            verdict = rule.verdict, reason = Short(rule.reason, 24), who = Short(rule.who, 64) }
    end
    if #result.rules < 1 then return nil end
    if type(raw.character) == "table" then
        result.character = { name = Short(raw.character.name, 64), level = Num(raw.character.level) and raw.character.level or nil }
    end
    self:Judge(result)
    return result
end

function Engine:SanitizeHistory(raw)
    local history = {}
    for _, entry in ipairs(type(raw) == "table" and raw or {}) do
        local result = self:SanitizeResult(entry)
        if result then history[#history + 1] = result end
    end
    table.sort(history, function(a, b) if a.endedAt ~= b.endedAt then return a.endedAt > b.endedAt end return a.id < b.id end)
    while #history > self.historyLimit do table.remove(history) end
    return history
end

-- Moves a finished contract's sheet into the bounded history (newest first).
function Engine:Archive(bucket, contract)
    if type(contract) ~= "table" or not contract.result then return end
    bucket.history = bucket.history or {}
    table.insert(bucket.history, 1, contract.result)
    while #bucket.history > self.historyLimit do table.remove(bucket.history) end
    if bucket.contract == contract then bucket.contract = nil end
end
