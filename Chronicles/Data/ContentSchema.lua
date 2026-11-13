local MS = _G.MS

local function Set(values)
    local result = {}
    for _, value in ipairs(values) do result[value] = true end
    return result
end

MS.ChroniclesContentSchema = {
    CONTENT_SCHEMA_VERSION = 1,
    KINDS = { "regions", "chronicles", "rumors", "collections", "seals" },
    PACK_SOURCES = Set({ "OFFICIAL", "COMMUNITY_CURATED", "COMMUNITY_PACK" }),
    TIMELINES = Set({ "classic_forever" }),
    CONTENT_STATUSES = Set({ "DRAFT", "SUBMITTED", "LORE_REVIEW", "EDITORIAL_REVIEW",
        "TECHNICAL_VALIDATION", "VALIDATED", "PUBLISHED", "NEEDS_CHANGES", "REJECTED",
        "ARCHIVED", "RETIRED" }),
    LOCALE_STATUSES = Set({ "DRAFT", "REVIEW", "PUBLISHED", "MISSING" }),
    LOCALES = Set({ "frFR", "enUS" }),
    FORMATS = Set({ "NOTE", "CHRONICLE", "DOSSIER" }),
    CHRONICLE_TYPES = Set({ "PLACE", "CHARACTER", "FACTION", "EVENT", "QUEST_STORY",
        "LORE", "DISCOVERY" }),
    TRIGGERS = Set({ "FIRST_ENTER_ZONE", "FIRST_ENTER_SUBZONE", "MAP_FULLY_EXPLORED",
        "QUEST_COMPLETED", "QUEST_SET_COMPLETED", "LEVEL_REACHED" }),
    SPOILERS = Set({ "DISCOVERY_SAFE" }),
    COLLECTION_KINDS = Set({ "EXPLORATION", "NARRATIVE", "FREE" }),
    ORDERINGS = Set({ "ORDERED", "UNORDERED" }),
    REVEALS = Set({ "HIDDEN", "AFTER_FIRST_ENTRY", "ALWAYS" }),
    EXACT_TOTALS = Set({ "NEVER", "AFTER_FIRST_ENTRY", "AFTER_REGION_EXPLORED", "ALWAYS" }),
    SOURCE_TYPES = Set({ "OFFICIAL_GAME", "OFFICIAL_BOOK", "OFFICIAL_SITE",
        "SECONDARY_REFERENCE", "OTHER" }),
}
