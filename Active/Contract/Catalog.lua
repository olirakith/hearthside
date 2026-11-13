local MS = _G.MS
MS.Active = MS.Active or {}
-- Contrat cards. Pure data. Each card declares what Journey can arbitrate:
--   OBSERVED  Journey watches a fact (fact) through a capability; it can say ROMPU on its own.
--   HONOR     a promise between players; Journey records it, never judges it.
-- Wording rule: a card says exactly what is observed ("never open the auction house"), never
-- something broader ("no auction house trade") that Journey could not see.
local Catalog = {}
MS.Active.ContractCatalog = Catalog

Catalog.cards = {
    ZERO_DEATH = { mode = "OBSERVED", scopes = { SOLO = true, GROUP = true }, fact = "DEATH",
        capabilities = { SOLO = { "PlayerDeath" }, GROUP = { "PlayerDeath", "PartyDeath" } } },
    TIME_LIMIT = { mode = "OBSERVED", scopes = { SOLO = true, GROUP = true }, fact = "TIME",
        capabilities = { SOLO = { "ServerTime" }, GROUP = { "ServerTime" } } },
    NO_FLIGHT = { mode = "OBSERVED", scopes = { SOLO = true }, fact = "TAXI", capabilities = { SOLO = { "Taxi" } } },
    ON_FOOT = { mode = "OBSERVED", scopes = { SOLO = true }, fact = "MOUNT", minLevel = 20, capabilities = { SOLO = { "Mount" } } },
    NO_AUCTION = { mode = "OBSERVED", scopes = { SOLO = true }, fact = "AUCTION", capabilities = { SOLO = { "AuctionHouse" } } },
    LONE_WOLF = { mode = "OBSERVED", scopes = { SOLO = true }, fact = "GROUP_JOINED", capabilities = { SOLO = { "GroupRoster" } } },
    NOBODY_LEAVES = { mode = "OBSERVED", scopes = { GROUP = true }, fact = "MEMBER_LEFT", capabilities = { GROUP = { "GroupRoster" } } },
    NO_HEARTH = { mode = "HONOR", scopes = { SOLO = true } },
    NO_FOOD = { mode = "HONOR", scopes = { SOLO = true, GROUP = true } },
    NO_POTION = { mode = "HONOR", scopes = { SOLO = true, GROUP = true } },
    LOWEST_LEADS = { mode = "HONOR", scopes = { GROUP = true } },
}
-- Stable display and draw order.
Catalog.order = { "ZERO_DEATH", "TIME_LIMIT", "NO_FLIGHT", "ON_FOOT", "NO_AUCTION", "LONE_WOLF", "NOBODY_LEAVES",
    "NO_HEARTH", "NO_FOOD", "NO_POTION", "LOWEST_LEADS" }

-- Time limit (seconds): a dungeon run, or one level at the player's level (a rough curve:
-- low levels are quick, higher ones take an evening).
function Catalog.TimeLimit(mode, level)
    if mode == "GROUP" then return 90 * 60 end
    level = type(level) == "number" and level or 1
    if level < 10 then return 30 * 60 elseif level < 20 then return 60 * 60
    elseif level < 30 then return 90 * 60 elseif level < 40 then return 120 * 60 end
    return 180 * 60
end

function Catalog.Get(id) return Catalog.cards[id] end

function Catalog.Capabilities(id, mode)
    local card = Catalog.cards[id]
    return card and card.capabilities and card.capabilities[mode] or {}
end
