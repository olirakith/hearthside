local MS = _G.MS
MS.Ink = MS.Ink or {}
-- The card that rises when a page opens while the book is not on screen: the page on parchment,
-- and one way to the book. It uses the Hearthside window, so it never shows in a fight.
local A = MS.Active
local I = MS.Ink
local T = I.Theme
local Panel = A.Panel

local function L() return MS.L end

local Found = { topic = "INK", back = "HOME" }
I.FoundCard = Found

function Found:Title() return self.finished and L().INK_FOUND_FINISHED or L().INK_FOUND_TITLE end

function Found:Focus(id, key, result)
    self.taleId, self.key, self.finished = id, key, result == "FINISHED"
    if A.Kit then A.Kit.Play("CRACK") end
end

function Found:Build(container, width)
    local height = container:GetHeight() or 420
    self.sheet = T.Parchment(container)
    self.sheet:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -4)
    self.sheet:SetSize(width, height - 56)
    local sheet, inner = self.sheet, width - 56
    self.kicker = T.Text(sheet, "UI", 13, "inkSoft")
    self.kicker:SetPoint("TOPLEFT", sheet, "TOPLEFT", 28, -24)
    self.kicker:SetWidth(inner)
    self.heading = T.Text(sheet, "TITLE", 20, "ink")
    self.heading:SetPoint("TOPLEFT", self.kicker, "BOTTOMLEFT", 0, -10)
    self.heading:SetWidth(inner)
    self.body = T.Text(sheet, "INK", 16, "ink")
    self.body:SetPoint("TOPLEFT", self.heading, "BOTTOMLEFT", 0, -12)
    self.body:SetWidth(inner)
    if type(self.body.SetMaxLines) == "function" then self.body:SetMaxLines(8) end
    self.seal = T.Disc(sheet, 50, "wax")
    self.seal:SetPoint("BOTTOMRIGHT", sheet, "BOTTOMRIGHT", -24, 22)
    self.mark = sheet:CreateTexture(nil, "OVERLAY")
    self.mark:SetTexture(T.check)
    self.mark:SetSize(28, 28)
    self.mark:SetPoint("CENTER", self.seal, "CENTER")
    self.read = T.Button(container, "PRIMARY", L().INK_OPEN_BOOK, function() Found:Read() end, 200, 36)
    self.read:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 4)
    self.later = T.Button(container, "GHOST", L().INK_LATER, function() Panel:Close("PLAYER") end, 120, 36)
    self.later:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 4)
end

function Found:Read()
    local id, key = self.taleId, self.key
    Panel:Close("PLAYER")
    if id then I:OpenTab("BOOK", id, key, "FOUND") end
end

function Found:Refresh()
    local entry = self.taleId and I:Entry(self.taleId)
    if not entry then return Panel:Close("PLAYER") end
    local page = I.Tale.Page(entry.tale, self.key)
    self.kicker:SetText(entry.tale.title)
    self.heading:SetText(page and page.title or entry.tale.title)
    self.body:SetText(page and page.text or L().INK_PAGE_BLANK)
    self.read:Fit(160, 260)
    self.later:Fit(90, 200)
end

Panel:RegisterView("INK_FOUND", Found)
