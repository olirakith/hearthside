-- MS and persisted global names are stable transition identifiers.
local addonName = ...
MS = MS or {}
MS.addonName = addonName or "Hearthside"
local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
MS.Product = { addonVersion = metadata and metadata(MS.addonName, "Version") or "UNKNOWN" }
