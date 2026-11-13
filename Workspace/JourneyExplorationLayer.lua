local MS = _G.MS

MS.JourneyExplorationLayer = {}
local Layer = MS.JourneyExplorationLayer

function Layer:Create(canvas)
	return setmetatable({
		canvas = canvas,
		textures = {},
		status = {
			supported = false,
			textureCount = 0,
			source = "UNAVAILABLE",
			error = "none",
			shape = "UNAVAILABLE",
		},
	}, { __index = self })
end

function Layer:Render(mapID, art)
	for _, texture in ipairs(self.textures) do
		texture:Hide()
	end
	local status = self.status
	status.textureCount, status.error, status.shape = 0, "none", "UNAVAILABLE"
	local api = _G.C_MapExplorationInfo
	local getter = type(api) == "table" and api.GetExploredMapTextures
	status.supported = type(getter) == "function"
	status.source = status.supported and "C_MapExplorationInfo.GetExploredMapTextures" or "UNAVAILABLE"
	if not status.supported or not art or not art.layer or type(mapID) ~= "number" then
		return status
	end
	local ok, overlays = pcall(getter, mapID)
	if not ok then
		status.error = string.sub(tostring(overlays), 1, 120)
		return status
	end
	if type(overlays) ~= "table" then
		status.error = "OVERLAY_DATA_UNAVAILABLE"
		return status
	end
	local artWidth, artHeight = art.layer.layerWidth, art.layer.layerHeight
	local tileWidth, tileHeight = art.layer.tileWidth, art.layer.tileHeight
	if type(artWidth) ~= "number" or type(artHeight) ~= "number" or artWidth <= 0 or artHeight <= 0 then
		status.error = "INVALID_ART_DIMENSIONS"
		return status
	end
	if type(tileWidth) ~= "number" or type(tileHeight) ~= "number" or tileWidth <= 0 or tileHeight <= 0 then
		status.error = "INVALID_ART_TILE_DIMENSIONS"
		return status
	end
	local function FileDimension(pixelSize, fullSize)
		if pixelSize == fullSize then
			return fullSize
		end
		local size = 16
		while size < pixelSize do
			size = size * 2
		end
		return size
	end
	local canvasWidth, canvasHeight = self.canvas:GetWidth(), self.canvas:GetHeight()
	local count = 0
	for overlayIndex = 1, math.min(#overlays, 64) do
		local overlay = overlays[overlayIndex]
		if type(overlay) == "table" then
			local width, height = overlay.textureWidth, overlay.textureHeight
			local offsetX, offsetY = overlay.offsetX, overlay.offsetY
			local files = overlay.fileDataIDs
			if status.shape == "UNAVAILABLE" then
				status.shape = string.format(
					"fileDataIDs=%s,textureWidth=%s,textureHeight=%s,offsetX=%s,offsetY=%s",
					type(files),
					type(width),
					type(height),
					type(offsetX),
					type(offsetY)
				)
			end
			if
				-- Blizzard keeps these overlays hidden until mouseover; displaying them would reveal extra art.
				overlay.isShownByMouseOver ~= true
				and type(width) == "number"
				and width > 0
				and type(height) == "number"
				and height > 0
				and type(offsetX) == "number"
				and type(offsetY) == "number"
				and type(files) == "table"
			then
				local columns, rows = math.ceil(width / tileWidth), math.ceil(height / tileHeight)
				if columns * rows <= 128 and #files >= columns * rows then
					for row = 0, rows - 1 do
						for column = 0, columns - 1 do
							if count >= 128 then
								break
							end
							local file = files[row * columns + column + 1]
							if type(file) == "number" and file > 0 then
								local texture = self.textures[count + 1]
								if not texture then
									texture = self.canvas:CreateTexture(nil, "ARTWORK", nil, 2)
									self.textures[count + 1] = texture
								end
								local applied = pcall(texture.SetTexture, texture, file)
								if applied then
									local pixelWidth = math.min(tileWidth, width - column * tileWidth)
									local pixelHeight = math.min(tileHeight, height - row * tileHeight)
									texture:ClearAllPoints()
									texture:SetPoint(
										"TOPLEFT",
										self.canvas,
										"TOPLEFT",
										(offsetX + column * tileWidth) / artWidth * canvasWidth,
										-(offsetY + row * tileHeight) / artHeight * canvasHeight
									)
									texture:SetSize(
										pixelWidth / artWidth * canvasWidth,
										pixelHeight / artHeight * canvasHeight
									)
									texture:SetTexCoord(
										0,
										pixelWidth / FileDimension(pixelWidth, tileWidth),
										0,
										pixelHeight / FileDimension(pixelHeight, tileHeight)
									)
									texture:Show()
									count = count + 1
								end
							end
						end
						if count >= 128 then
							break
						end
					end
				end
			end
		end
		if count >= 128 then
			break
		end
	end
	status.textureCount = count
	return status
end
