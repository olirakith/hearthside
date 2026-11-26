local MS = _G.MS

-- "My characters" in the Inventory tab: one line per character as it was at its last logout.
-- Columns on a wide list; on a narrow one each character takes a short card. Read only, except
-- forgetting a character, which asks for a second right click.
MS.JourneyRosterView = { rows = {}, WIDE = 640, ARM = 5 }
local RosterView = MS.JourneyRosterView
local COLUMNS = { { "name", .26 }, { "where", .20 }, { "money", .15, "RIGHT" }, { "rest", .15 }, { "bags", .08, "RIGHT" }, { "craft", .16 } }

local function Label(parent, style, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    MS.JourneyUIStyle:Apply(label, style); MS.JourneyUIStyle:Text(label, color)
    label:SetJustifyH("LEFT"); label:SetJustifyV("TOP")
    return label
end

local function Now() return type(_G.time) == "function" and time() or 0 end

local function Hex(class)
    local color = type(_G.RAID_CLASS_COLORS) == "table" and class and _G.RAID_CLASS_COLORS[class]
    if type(color) ~= "table" or type(color.r) ~= "number" then return nil end
    return string.format("ff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
end

local function ClassName(record)
    local names = record.sex == 3 and _G.LOCALIZED_CLASS_NAMES_FEMALE or _G.LOCALIZED_CLASS_NAMES_MALE
    local name = type(names) == "table" and record.class and names[record.class]
    return type(name) == "string" and name or nil
end

function RosterView:Seen(record, now)
    if record.current then return MS.L.JOURNEY_ROSTER_PLAYING end
    local view = MS.JourneyProgressionView
    if view and view.RecentDate then
        local ok, text = pcall(view.RecentDate, view, record.seen, now)
        if ok and type(text) == "string" then return text end
    end
    return ""
end

function RosterView:Money(money)
    local bar = MS.JourneyStatusBar
    if type(money) ~= "number" or not bar or not bar.MoneyText then return MS.L.JOURNEY_UNKNOWN end
    return bar:MoneyText(money)
end

-- Rested experience as a share of the level, and how much of the 150 % cap it fills.
function RosterView:Rest(record)
    if type(record.xpMax) ~= "number" or record.xpMax <= 0 then return nil end
    local rested = record.rested or 0
    local text = string.format(MS.L.JOURNEY_ROSTER_REST, math.floor(rested * 100 / record.xpMax))
    if record.resting then text = text .. " · " .. MS.L.JOURNEY_ROSTER_INN end
    return text, math.min(1, rested / (record.xpMax * 1.5))
end

local function Wait(seconds)
    if seconds >= 3600 then return string.format(MS.L.JOURNEY_ROSTER_HOURS, math.ceil(seconds / 3600)) end
    return string.format(MS.L.JOURNEY_ROSTER_MINUTES, math.max(1, math.ceil(seconds / 60)))
end

-- What the professions say: cooldowns ready now first, else ranks and the next cooldown.
function RosterView:Crafts(record, now)
    local ready, ranks, soon = {}, {}, nil
    for _, profession in ipairs(record.professions or {}) do
        local rank = profession.rank and (profession.name .. " " .. profession.rank) or profession.name
        ranks[#ranks + 1] = rank
        for _, cooldown in ipairs(profession.cooldowns or {}) do
            if cooldown.readyAt <= now then
                ready[#ready + 1] = string.format(MS.L.JOURNEY_ROSTER_READY, cooldown.name)
            elseif not soon or cooldown.readyAt < soon.readyAt then
                soon = cooldown
            end
        end
    end
    local list = table.concat(ranks, " · ")
    if #ready > 0 then return table.concat(ready, " · "), list, true end
    if soon then return list, string.format(MS.L.JOURNEY_ROSTER_SOON, soon.name, Wait(soon.readyAt - now)), false end
    return #ranks > 0 and list or "", nil, false
end

-- Everything a row shows, as text: the view only places it.
function RosterView:Describe(record, now)
    local class, hex = ClassName(record), Hex(record.class)
    local name = hex and ("|c" .. hex .. record.name .. "|r") or record.name
    local meta = {}
    if class then meta[#meta + 1] = class end
    meta[#meta + 1] = string.format(MS.L.JOURNEY_ROSTER_LEVEL, record.level)
    local seen = self:Seen(record, now)
    if seen ~= "" then meta[#meta + 1] = seen end
    local rest, fill = self:Rest(record)
    local craft, craftNote, ready = self:Crafts(record, now)
    local bags = record.bagFree and record.bagTotal and string.format(MS.L.JOURNEY_ROSTER_BAGS, record.bagFree, record.bagTotal) or ""
    return { name = name, meta = table.concat(meta, " · "), where = record.zone or "", whereNote = record.subzone or "",
        money = self:Money(record.money), rest = rest or "", fill = fill, bags = bags, mail = record.mail == true,
        craft = craft, craftNote = craftNote, ready = ready }
end

function RosterView:Row(view, index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, view.content)
    row.mine = row:CreateTexture(nil, "BACKGROUND"); row.mine:SetAllPoints(row)
    MS.JourneyUIStyle:Color(row.mine, "parchmentDark")
    row.accent = row:CreateTexture(nil, "BORDER")
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT"); row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
    row.accent:SetWidth(3); MS.JourneyUIStyle:Color(row.accent, "borderActive")
    row.rule = row:CreateTexture(nil, "ARTWORK"); MS.JourneyUIStyle:Color(row.rule, "borderMuted")
    row.name = Label(row, "BODY", "textPrimary")
    row.meta = Label(row, "SMALL", "textSecondary")
    row.where = Label(row, "BODY", "textPrimary")
    row.whereNote = Label(row, "SMALL", "textSecondary")
    row.money = Label(row, "BODY", "textPrimary")
    row.rest = Label(row, "SMALL", "textSecondary")
    row.barBack = row:CreateTexture(nil, "ARTWORK"); MS.JourneyUIStyle:Color(row.barBack, "backgroundDeep")
    row.bar = row:CreateTexture(nil, "OVERLAY"); row.bar:SetColorTexture(.37, .55, .88, 1)
    row.bags = Label(row, "BODY", "textPrimary")
    row.mail = Label(row, "SMALL", "gold")
    row.craft = Label(row, "BODY", "textPrimary")
    row.craftNote = Label(row, "SMALL", "textSecondary")
    row:RegisterForClicks("RightButtonUp")
    row:SetScript("OnClick", function(frame) RosterView:Forget(frame) end)
    self.rows[index] = row
    return row
end

-- A first right click asks, a second one within a few seconds forgets the character.
function RosterView:Forget(row)
    if not row.key or row.current then return end
    if self.armed == row.key and Now() - (self.armedAt or 0) <= self.ARM then
        self.armed = nil
        MS.JourneyRoster:Forget(row.key)
    else
        self.armed, self.armedAt = row.key, Now()
    end
    MS.InventoryView.dirty = true
    MS.InventoryView:Refresh()
end

local function Put(label, row, x, y, width, text, justify)
    label:ClearAllPoints(); label:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
    label:SetWidth(math.max(1, width)); label:SetJustifyH(justify or "LEFT")
    label:SetText(text or ""); label:SetShown(text ~= nil and text ~= "")
    return (text ~= nil and text ~= "") and math.max(14, label:GetStringHeight() or 0) or 0
end

function RosterView:PlaceRow(view, index, record, y, width, wide, now)
    local row, info = self:Row(view, index), self:Describe(record, now)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, -y)
    row:SetWidth(width)
    row.key, row.current = record.key, record.current
    row.mine:SetShown(record.current == true); row.accent:SetShown(record.current == true)
    local meta = self.armed == record.key and MS.L.JOURNEY_ROSTER_FORGET_CONFIRM or info.meta
    MS.JourneyUIStyle:Text(row.meta, self.armed == record.key and "warning" or "textSecondary")
    MS.JourneyUIStyle:Text(row.craft, info.ready and "success" or "textPrimary")
    local height, pad = 0, 8
    if wide then
        local x, gap, cells = pad, 10, {}
        for _, column in ipairs(COLUMNS) do
            cells[column[1]] = { x, math.floor((width - pad * 2) * column[2]) - gap, column[3] }
            x = x + math.floor((width - pad * 2) * column[2])
        end
        local function Cell(key, label, note, noteText, text)
            local c = cells[key]
            local h = Put(label, row, c[1], 6, c[2], text, c[3])
            if note then h = h + Put(note, row, c[1], 8 + h, c[2], noteText, c[3]) end
            height = math.max(height, h)
        end
        Cell("name", row.name, row.meta, meta, info.name)
        Cell("where", row.where, row.whereNote, info.whereNote, info.where)
        Cell("money", row.money, nil, nil, info.money)
        Cell("bags", row.bags, row.mail, info.mail and MS.L.JOURNEY_ROSTER_MAIL or nil, info.bags)
        Cell("craft", row.craft, row.craftNote, info.craftNote, info.craft)
        local c = cells.rest
        row.barBack:SetShown(info.fill ~= nil); row.bar:SetShown(info.fill ~= nil and info.fill > 0)
        if info.fill then
            row.barBack:ClearAllPoints(); row.barBack:SetPoint("TOPLEFT", row, "TOPLEFT", c[1], -10)
            row.barBack:SetSize(c[2], 6)
            row.bar:ClearAllPoints(); row.bar:SetPoint("TOPLEFT", row.barBack, "TOPLEFT")
            row.bar:SetSize(math.max(1, c[2] * info.fill), 6)
        end
        height = math.max(height, 22 + Put(row.rest, row, c[1], 22, c[2], info.rest))
    else
        -- A card: name and gold, then who and when, then the rest in one line.
        local moneyWidth = math.min(150, math.floor(width * .4))
        local top = Put(row.name, row, pad, 6, width - moneyWidth - pad * 3, info.name)
        Put(row.money, row, width - moneyWidth - pad, 6, moneyWidth, info.money, "RIGHT")
        top = top + Put(row.meta, row, pad, 8 + top, width - pad * 2, meta)
        local parts = {}
        local rest = info.rest ~= "" and (MS.L.JOURNEY_ROSTER_COLUMN_REST .. " " .. info.rest) or ""
        local bags = info.bags ~= "" and (MS.L.JOURNEY_ROSTER_COLUMN_BAGS .. " " .. info.bags) or ""
        for _, part in ipairs({ info.where, rest, bags, info.mail and MS.L.JOURNEY_ROSTER_MAIL or "", info.craft }) do
            if part ~= "" then parts[#parts + 1] = part end
        end
        height = top + 2 + Put(row.where, row, pad, 10 + top, width - pad * 2, table.concat(parts, " · "))
        for _, key in ipairs({ "whereNote", "rest", "bags", "mail", "craft", "craftNote", "barBack", "bar" }) do row[key]:Hide() end
    end
    height = height + 14
    row:SetHeight(height)
    row.rule:ClearAllPoints(); row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.rule:SetSize(width, 1)
    row:Show()
    return y + height + 2
end

-- The headings of the columns, made once on the inventory's content.
function RosterView:Headings(view, y, width)
    self.heads = self.heads or {}
    local x, pad = 8, 8
    for index, column in ipairs(COLUMNS) do
        local label = self.heads[index] or Label(view.content, "SMALL", "gold")
        self.heads[index] = label
        local share = math.floor((width - pad * 2) * column[2])
        Put(label, view.content, x, y, share - 10, MS.L["JOURNEY_ROSTER_COLUMN_" .. column[1]:upper()], column[3])
        x = x + share
    end
    return y + 22
end

function RosterView:Hide()
    for _, row in ipairs(self.rows) do row:Hide() end
    for _, label in ipairs(self.heads or {}) do label:Hide() end
    if self.note then self.note:Hide() end
    if self.total then self.total:Hide() end
end

-- Draws the list in the inventory's scrolled content and returns the height used.
function RosterView:Place(view, y, width, showTotal)
    self:Hide()
    local list, now = MS.JourneyRoster:List(), Now()
    local wide = width >= self.WIDE
    self.note = self.note or Label(view.content, "SMALL", "textSecondary")
    self.total = self.total or Label(view.content, "BODY", "textPrimary")
    if showTotal and #list > 1 then
        y = y + Put(self.total, view.content, 8, y, width - 16, string.format(MS.L.JOURNEY_ROSTER_TOTAL, self:Money(MS.JourneyRoster:Total()))) + 12
    end
    if wide and #list > 0 then y = self:Headings(view, y, width) end
    for index, record in ipairs(list) do y = self:PlaceRow(view, index, record, y, width, wide, now) end
    self.count, self.wide = #list, wide
    return y + 8 + Put(self.note, view.content, 8, y + 8, width - 16, MS.L.JOURNEY_ROSTER_NOTE) + 12
end

-- The right card of the wide inventory: all the gold, what is ready, who has mail waiting.
function RosterView:Summary()
    local list, now, ready, mail = MS.JourneyRoster:List(), Now(), {}, {}
    for _, record in ipairs(list) do
        for _, profession in ipairs(record.professions or {}) do
            for _, cooldown in ipairs(profession.cooldowns or {}) do
                if cooldown.readyAt <= now then ready[#ready + 1] = cooldown.name .. " (" .. record.name .. ")" end
            end
        end
        if record.mail then mail[#mail + 1] = record.name end
    end
    local lines = { string.format(MS.L.JOURNEY_ROSTER_TOTAL, self:Money(MS.JourneyRoster:Total())) }
    if #ready > 0 then lines[#lines + 1] = string.format(MS.L.JOURNEY_ROSTER_SUMMARY_READY, table.concat(ready, ", ")) end
    if #mail > 0 then lines[#lines + 1] = string.format(MS.L.JOURNEY_ROSTER_SUMMARY_MAIL, table.concat(mail, ", ")) end
    return table.concat(lines, "\n\n")
end
