local MS = _G.MS

-- Copying from the Discussion panel (Docs/journey/CHAT-FILTRES-FICHE.md): plain text of a line,
-- web addresses made clickable, and one read-only box where the player presses Ctrl+C. The game
-- cannot open a browser or write the clipboard: the box only selects the text.
MS.JourneyChatCopy = { tabLines = 200, height = 190 }
local Copy = MS.JourneyChatCopy

-- Our own links in the panel. The panel handles them itself; the game never sees them.
Copy.PREFIX = "addon:Hearthside:"

function Copy:LineLink(id, text)
    return string.format("|H%scopy:%d|h%s|h", self.PREFIX, id, text)
end

-- "copy", 12 / "url", "https://..." / nil for a link that is not ours.
function Copy:Parse(link)
    if type(link) ~= "string" or link:sub(1, #self.PREFIX) ~= self.PREFIX then return nil end
    local rest = link:sub(#self.PREFIX + 1)
    local id = rest:match("^copy:(%d+)$")
    if id then return "copy", tonumber(id) end
    local url = rest:match("^url:(.+)$")
    if url then return "url", url end
    return nil
end

-- The text as a person reads it: no colours, icons or codes; a link becomes its own text.
function Copy:Plain(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    -- Battle.net names are protected strings the game only draws: they cannot be copied.
    text = text:gsub("|K.-|k", "")
    text = text:gsub("|n", " "):gsub("||", "|")
    return text
end

-- Search: lower case, common accents folded, so "competence" finds "Compétence".
local FOLD = {
    ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a", ["Á"] = "a",
    ["ç"] = "c", ["Ç"] = "c",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["î"] = "i", ["ï"] = "i", ["í"] = "i", ["Î"] = "i", ["Ï"] = "i", ["Í"] = "i",
    ["ô"] = "o", ["ö"] = "o", ["ó"] = "o", ["Ô"] = "o", ["Ö"] = "o", ["Ó"] = "o",
    ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u", ["Ú"] = "u",
    ["ñ"] = "n", ["Ñ"] = "n", ["œ"] = "oe", ["Œ"] = "oe", ["ß"] = "ss",
}

function Copy:Fold(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("[\195\197][\128-\191]", FOLD)
    return string.lower(text)
end

-- Web addresses -----------------------------------------------------------------------------

local URL_COLOR = "|cff6fb7e8"
local TRAILING = "[%.,;:!%?%)%]'\"]+$"

local function Wrap(url)
    local tail = url:match(TRAILING) or ""
    if tail ~= "" then url = url:sub(1, #url - #tail) end
    if #url < 5 then return url .. tail end
    return string.format("%s|H%surl:%s|h[%s]|h|r%s", URL_COLOR, Copy.PREFIX, url, url, tail)
end

-- Wraps addresses in plain text only: never inside the game's own links or codes.
local function DecoratePlain(text)
    -- www. first, then full addresses; a placeholder keeps the second pass off the first's output.
    local found = {}
    local function keep(url)
        found[#found + 1] = Wrap(url)
        return "\001" .. #found .. "\002"
    end
    text = text:gsub("https?://[%w%-%._~:/%?#@!%$&'%*%+,;=%%]+", keep)
    text = text:gsub("%f[%w]www%.[%w%-]+%.[%w%-%._~:/%?#@!%$&'%*%+,;=%%]+", keep)
    return (text:gsub("\001(%d+)\002", function(index) return found[tonumber(index)] end))
end

function Copy:Decorate(text)
    if type(text) ~= "string" or not (text:find("://", 1, true) or text:find("www.", 1, true)) then return text end
    local out, position = {}, 1
    -- Split around |H...|h...|h links and |c...|r colour runs are left as they are: only the
    -- link spans are skipped, so an address in coloured text still becomes a link.
    while true do
        local start, finish = text:find("|H.-|h.-|h", position)
        if not start then break end
        out[#out + 1] = DecoratePlain(text:sub(position, start - 1))
        out[#out + 1] = text:sub(start, finish)
        position = finish + 1
    end
    out[#out + 1] = DecoratePlain(text:sub(position))
    return table.concat(out)
end

-- The copy box -------------------------------------------------------------------------------

local function Style() return MS.JourneyUIStyle end

function Copy:Create(parent)
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", nil, parent)
    frame:EnableMouse(true)
    frame:Hide()
    self.frame = frame
    frame.edge = frame:CreateTexture(nil, "BACKGROUND")
    frame.edge:SetAllPoints(frame)
    Style():Color(frame.edge, "borderActive")
    frame.fill = frame:CreateTexture(nil, "BORDER")
    frame.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    Style():Material(frame.fill, "backgroundDeep")
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Style():Body(frame.title, "SECONDARY", "gold")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -10)
    frame.title:SetJustifyH("LEFT")
    frame.close = CreateFrame("Button", nil, frame)
    frame.close.label = frame.close:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Style():Body(frame.close.label, "SECONDARY", "textPrimary")
    frame.close.label:SetPoint("CENTER", frame.close, "CENTER")
    Style():Action(frame.close, frame.close.label)
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -6)
    frame.close:SetScript("OnClick", function() Copy:Close() end)

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -34)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(owner, delta)
        local range = owner:GetVerticalScrollRange() or 0
        owner:SetVerticalScroll(math.max(0, math.min(range, owner:GetVerticalScroll() - delta * 40)))
    end)
    frame.scroll = scroll
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlight)
    box:SetWidth(400)
    box:SetScript("OnEscapePressed", function() Copy:Close() end)
    -- Read-only: whatever the player types puts the text back, selected.
    box:SetScript("OnTextChanged", function(owner, user)
        if user and owner:GetText() ~= Copy.text then
            owner:SetText(Copy.text or "")
            owner:HighlightText()
        end
    end)
    box:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local top, view = scroll:GetVerticalScroll(), scroll:GetHeight()
        y = -(y or 0)
        if y < top then scroll:SetVerticalScroll(y)
        elseif y + (height or 0) > top + view then scroll:SetVerticalScroll(y + (height or 0) - view) end
    end)
    scroll:SetScrollChild(box)
    frame.box = box
    return frame
end

-- Opens the box over the panel with this text selected.
function Copy:Open(text, anchor)
    local parent = anchor and anchor:GetParent() or (MS.Workspace and MS.Workspace.frame)
    if not parent then return false end
    local frame = self:Create(parent)
    self.text = type(text) == "string" and text or ""
    local L = MS.L
    frame.title:SetText(L.CHAT_COPY_TITLE)
    frame.close.label:SetText(L.CHAT_COPY_CLOSE)
    frame.close:SetSize(math.max(72, (frame.close.label:GetStringWidth() or 50) + 24), 22)
    frame:ClearAllPoints()
    if anchor then
        frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 12, 6)
        frame:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -12, 6)
    else
        frame:SetPoint("CENTER", parent, "CENTER")
        frame:SetWidth(600)
    end
    frame:SetHeight(self.height)
    frame:SetFrameStrata("DIALOG")
    frame:Show()
    local width = math.max(100, (frame:GetWidth() or 600) - 28)
    frame.box:SetWidth(width)
    frame.box:SetText(self.text)
    frame.scroll:SetVerticalScroll(0)
    frame.box:SetFocus()
    frame.box:HighlightText()
    return true
end

function Copy:Close()
    if not self.frame then return end
    self.frame.box:ClearFocus()
    self.frame:Hide()
end

function Copy:IsOpen() return self.frame ~= nil and self.frame:IsShown() end
