local MS = _G.MS

MS.ChroniclesWoWFactAdapter = {}
local Adapter = MS.ChroniclesWoWFactAdapter

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

function Adapter:ZoneFacts(registry)
    local map = type(_G.C_Map) == "table" and _G.C_Map or nil
    if not map or type(map.GetBestMapForUnit) ~= "function" then return {} end
    local mapID = Read(map.GetBestMapForUnit, "player")
    if type(mapID) ~= "number" then return {} end
    local current, seen = mapID, {}
    for _ = 1, 8 do
        if seen[current] then break end
        seen[current] = true
        local region = registry:GetRegionByMapID(current)
        if region then
            local facts = { { type = "ENTER_ZONE", region = region } }
            -- A distinct child map ID is a stable identifier. Localized subzone
            -- text is deliberately never used as a discovery key.
            if current ~= mapID then
                facts[#facts + 1] = { type = "ENTER_SUBZONE", region = region,
                    subzone = "map." .. tostring(mapID) }
            end
            return facts
        end
        local info = Read(map.GetMapInfo, current)
        if type(info) ~= "table" or type(info.parentMapID) ~= "number" then break end
        current = info.parentMapID
    end
    return {}
end

function Adapter:FactsForEvent(event, registry, ...)
    if event == "PLAYER_LOGIN" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
        return self:ZoneFacts(registry)
    elseif event == "PLAYER_LEVEL_UP" then
        local level = ...
        if type(level) == "number" and level > 0 then return { { type = "LEVEL_REACHED", level = level } } end
    elseif event == "QUEST_TURNED_IN" then
        local questID = ...
        if type(questID) == "number" and questID > 0 then
            return { { type = "QUEST_COMPLETED", questID = questID } }
        end
    end
    return {}
end

function Adapter:LoginLevelFact()
    local level = Read(_G.UnitLevel, "player")
    if type(level) == "number" and level > 0 then return { type = "LEVEL_REACHED", level = level } end
end
