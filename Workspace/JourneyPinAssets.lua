local MS = _G.MS

MS.JourneyPinAssets = { resolved = false, assets = {} }
local Assets = MS.JourneyPinAssets

-- These are candidates from Blizzard's map legend/POI UI, not assumed Forever assets.
local CANDIDATES = {
	AVAILABLE = { "QuestNormal", "UI-QuestPoi-QuestBang" },
	IN_PROGRESS = { "Quest-In-Progress-Icon-yellow", "UI-QuestPoi-QuestNumber" },
	IN_PROGRESS_BASE = { "UI-QuestPoi-QuestNumber" },
	READY_TO_TURN_IN = { "UI-QuestPoi-QuestBangTurnIn", "UI-QuestIcon-TurnIn-Normal" },
	PLAYER = { "UI-WorldMapArrow" },
	SELECTED_GLOW = { "UI-QuestPoi-OuterGlow" },
}

local function AtlasInfo(name)
	local api = type(_G.C_Texture) == "table" and C_Texture or nil
	if api and type(api.GetAtlasExists) == "function" then
		local ok, exists = pcall(api.GetAtlasExists, name)
		if ok and exists == false then
			return nil
		end
	end
	for _, fn in ipairs({ api and api.GetAtlasInfo or false, _G.GetAtlasInfo or false }) do
		if type(fn) == "function" then
			local ok, info = pcall(fn, name)
			if ok and type(info) == "table" then
				return info
			end
		end
	end
end

function Assets:Resolve()
	if self.resolved then
		return
	end
	self.resolved = true
	for kind, candidates in pairs(CANDIDATES) do
		local asset =
			{ type = "JOURNEY_TEXTURE_FALLBACK", value = "COLOR_TEXTURE", source = "JOURNEY", validated = true }
		for _, name in ipairs(candidates) do
			local info = AtlasInfo(name)
			if info then
				asset = {
					type = "ATLAS",
					value = name,
					source = "CLIENT_ATLAS_INFO",
					validated = true,
					fileID = type(info.file) == "number" and info.file
						or type(info.fileID) == "number" and info.fileID
						or nil,
				}
				break
			end
		end
		self.assets[kind] = asset
	end
end

function Assets:Apply(texture, kind, color)
	self:Resolve()
	local asset = self.assets[kind] or self.assets.IN_PROGRESS
	if asset.type == "ATLAS" and type(texture.SetAtlas) == "function" then
		local ok = pcall(texture.SetAtlas, texture, asset.value, false)
		if ok then
			if type(texture.SetRotation) == "function" then
				pcall(texture.SetRotation, texture, 0)
			end
			return "NATIVE_ATLAS"
		end
	end
	if type(asset.fileID) == "number" and type(texture.SetTexture) == "function" then
		local ok = pcall(texture.SetTexture, texture, asset.fileID)
		if ok then
			if type(texture.SetRotation) == "function" then
				pcall(texture.SetRotation, texture, 0)
			end
			return "NATIVE_FILE_ID"
		end
	end
	texture:SetColorTexture(color[1], color[2], color[3], 1)
	if type(texture.SetRotation) == "function" then
		pcall(texture.SetRotation, texture, math.pi / 4)
	end
	return "JOURNEY_TEXTURE_FALLBACK"
end

function Assets:GetStatus()
	-- /ms report reads only cached primitive values.
	return self.assets
end
