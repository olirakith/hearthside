local MS = _G.MS
MS.Ink = MS.Ink or {}
-- The quill's workshop: drafts, pages placed where the author stands, sealing and trying a tale.
-- Drafts are account-wide; a sealed tale goes on the shelf as WRITTEN, a new version each time.
local A = MS.Active
local I = MS.Ink
local Workshop = {}
I.Workshop = Workshop

local function Drafts() return I.Store.root and I.Store.root.drafts or {} end

function Workshop:Draft(id) return Drafts()[id] end

function Workshop:List()
    local list = {}
    for _, draft in pairs(Drafts()) do list[#list + 1] = draft end
    table.sort(list, function(a, b)
        if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
        return a.id < b.id
    end)
    return list
end

function Workshop:Touch(draft) draft.updatedAt = A.Now() or draft.updatedAt end

local function NewId()
    local random = A.random or math.random
    for _ = 1, 16 do
        local id = MS.Community.Bytes.RandomHex(8, random)
        if not I:Entry(id) and not Drafts()[id] then return id end
    end
end

-- Returns the new draft, or nil and NOT_READY | FULL | LOCKED.
function Workshop:New()
    if not I:Ready() then return nil, "NOT_READY" end
    local author = A.SealBook:IdentityName(A.identity)
    local id = NewId()
    if not author or not id then return nil, "NOT_READY" end
    local draft, reason = I.Store:AddDraft(I.Draft.New(id, author, A.Now()))
    A:Log("INK_DRAFT", { action = "NEW", result = draft and "OK" or reason })
    return draft, reason
end

-- The draft of a tale written on this account: the one being edited, or a new one from the tale.
function Workshop:Edit(id)
    if not I:Ready() then return nil, "NOT_READY" end
    local entry = I:Entry(id)
    local current = Drafts()[id]
    if current and (not entry or current.baseVersion >= entry.tale.version) then return current end
    if not entry or entry.origin ~= "WRITTEN" then return nil, "NOT_WRITTEN" end
    local draft = I.Draft.FromTale(entry.tale, current, A.Now())
    if not draft then return nil, "INVALID" end
    local kept, reason = I.Store:AddDraft(draft)
    A:Log("INK_DRAFT", { action = "EDIT", result = kept and "OK" or reason })
    return kept, reason
end

function Workshop:Discard(id)
    local ok = I.Store:RemoveDraft(id)
    if ok then A:Log("INK_DRAFT", { action = "DISCARD", result = "OK" }) end
    return ok
end

-- Places a PLACE page (or an EMOTE page that has to be done somewhere) where the author stands. Returns true and the zone name, or nil and
-- UNSETTLED | NO_POSITION | COMBAT | TAXI | DEAD.
function Workshop:PlaceHere(draft, page)
    if page.trigger.kind ~= "PLACE" and page.trigger.kind ~= "EMOTE" then return nil, "NO_POSITION" end
    local sample = A.Position:Sample()
    if sample.settled ~= true then return nil, "UNSETTLED" end
    if sample.combat ~= false then return nil, "COMBAT" end
    if sample.taxi == true then return nil, "TAXI" end
    if sample.dead ~= false then return nil, "DEAD" end
    if not sample.mapID or not sample.x or not sample.width or sample.width <= 0 then return nil, "NO_POSITION" end
    page.trigger.mapID, page.trigger.x, page.trigger.y = sample.mapID, sample.x, sample.y
    page.trigger.radius = page.trigger.radius or I.Tale.defaultRadius
    self:Touch(draft)
    return true, A.Position:MapName(sample.mapID)
end

-- The author's target becomes the creature of this page. Returns true, or nil and NONE | HIDDEN |
-- PLAYER | FRIENDLY (nothing to kill there).
function Workshop:TakeTarget(draft, page)
    if A.Bool(A.Call(_G.UnitExists, "target")) ~= true then return nil, "NONE" end
    local guid = A.Call(_G.UnitGUID, "target")
    local name = I.Tale.Line((A.Call(_G.UnitName, "target")), I.Tale.nameBytes)
    if type(guid) ~= "string" or not name then return nil, "HIDDEN" end
    local npcID = I.Deeds.Creature(guid)
    if not npcID then return nil, "PLAYER" end
    if page.trigger.kind == "KILL" and A.Bool(A.Call(_G.UnitCanAttack, "player", "target")) == false then return nil, "FRIENDLY" end
    page.trigger.npcID, page.trigger.name = npcID, name
    self:Touch(draft)
    return true
end

-- An EMOTE page that can be done to anyone, anywhere again.
function Workshop:ClearDeed(draft, page)
    local trigger = page.trigger
    trigger.npcID, trigger.name, trigger.mapID, trigger.x, trigger.y, trigger.radius = nil, nil, nil, nil, nil, nil
    self:Touch(draft)
end

-- Seals the draft: a new version of the tale on the shelf. try = start it again from the prologue
-- for this character and open it. Returns the tale and its seal, or nil, a reason and a page number.
function Workshop:Seal(draft, try)
    if not I:Ready() then return nil, "NOT_READY" end
    local entry = I:Entry(draft.id)
    -- A version sealed elsewhere on the account is never overwritten by an older draft.
    if entry and entry.tale.version > draft.baseVersion then draft.baseVersion = entry.tale.version end
    local tale, reason, index = I.Draft.ToTale(draft, A.Now())
    if not tale then
        A:Log("INK_SEALED", { result = reason, pages = #draft.pages })
        return nil, reason, index
    end
    local kept, status = I:Keep(tale, "WRITTEN")
    A:Log("INK_SEALED", { result = kept and status or tostring(status), pages = #tale.pages, try = try == true })
    if not kept then return nil, status end
    draft.baseVersion = tale.version
    if not draft.createdAt then draft.createdAt = tale.createdAt end
    self:Touch(draft)
    if try then
        I.bucket.progress[tale.id] = I.Progress.New(tale, A.Now())
        for position = #I.pending, 1, -1 do if I.pending[position].id == tale.id then table.remove(I.pending, position) end end
        if I.Watch then I.Watch:Refresh("TRY") end
    end
    return tale, I.Codec.Encode(tale)
end
