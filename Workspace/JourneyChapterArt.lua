local MS = _G.MS
MS.JourneyChapterArt = {}
local Art = MS.JourneyChapterArt

local function Number(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function Positive(value)
    return Number(value) and value > 0
end
local function Usable(value)
    return Positive(value) or type(value) == "string" and value ~= ""
end
local function FileSize(size, tileSize)
    if size == tileSize then return tileSize end
    local result = 16
    while result < size do result = result * 2 end
    return result
end

-- Retain Stormwind's validated central native crop; it does not need exploration data.
local function NativeSnapshot(art, source)
    local columns, rows = art.columns, art.rows
    if not Positive(columns) or not Positive(rows) or columns % 1 ~= 0 or rows % 1 ~= 0 or columns * rows > 128 then return nil end
    local layer = type(art.layer) == "table" and art.layer or {}
    local width, height = layer.tileWidth, layer.tileHeight
    if not Positive(width) or not Positive(height) or type(art.textures) ~= "table" then return nil end
    local textures, selected = art.textures, {}
    local row, left = math.floor((rows + 1) / 2), math.max(1, math.floor(columns / 2))
    local index = (row - 1) * columns + left
    if columns >= 2 and Usable(textures[index]) and Usable(textures[index + 1]) then
        selected = { textures[index], textures[index + 1] }
    else
        local best, distance
        for i = 1, math.min(#textures, columns * rows) do
            local x, y = (i - 1) % columns + 1, math.floor((i - 1) / columns) + 1
            local d = (x - (columns + 1) / 2) ^ 2 + (y - (rows + 1) / 2) ^ 2
            if Usable(textures[i]) and (not distance or d < distance) then best, distance = textures[i], d end
        end
        if best then selected[1] = best end
    end
    if #selected == 0 then return nil end
    local tiles = {}
    for i, file in ipairs(selected) do
        tiles[i] = { file = file, x = (i - 1) * width, y = 0, width = width, height = height,
            fileWidth = width, fileHeight = height, kind = "BASE", sublevel = 1 }
    end
    return { source = source, tiles = tiles, rect = { x = 0, y = 0, width = width * #tiles, height = height } }
end

function Art:Capture(mapID)
    if not Positive(mapID) or mapID % 1 ~= 0 then return nil end
    local ok, art = pcall(MS.JourneyMapData.Art, MS.JourneyMapData, mapID)
    if not ok or type(art) ~= "table" then return nil end
    if mapID == 1453 then return NativeSnapshot(art, "NATIVE_CITY") end
    local layer = type(art.layer) == "table" and art.layer or {}
    local tw, th, lw, lh = layer.tileWidth, layer.tileHeight, layer.layerWidth, layer.layerHeight
    if not Positive(tw) or not Positive(th) or not Positive(lw) or not Positive(lh) then
        return NativeSnapshot(art, "NATIVE_FALLBACK")
    end
    local columns, rows = math.ceil(lw / tw), math.ceil(lh / th)
    if columns * rows > 128 or type(art.textures) ~= "table" then return nil end
    local snapshot = { source = "BASE_ONLY", tiles = {}, baseCount = 0, overlayCount = 0,
        rect = { x = 0, y = 0, width = lw, height = lh }, fallback = NativeSnapshot(art, "NATIVE_FALLBACK") }
    for r = 0, rows - 1 do
        for c = 0, columns - 1 do
            local file = art.textures[r * columns + c + 1]
            if Usable(file) then
                snapshot.tiles[#snapshot.tiles + 1] = { file = file, x = c * tw, y = r * th,
                    width = math.min(tw, lw - c * tw), height = math.min(th, lh - r * th),
                    fileWidth = tw, fileHeight = th, kind = "BASE", sublevel = 1 }
                snapshot.baseCount = snapshot.baseCount + 1
            end
        end
    end
    if snapshot.baseCount == 0 then return nil end
    local api = _G.C_MapExplorationInfo
    local getter = type(api) == "table" and api.GetExploredMapTextures
    if type(getter) ~= "function" then return snapshot end
    local success, overlays = pcall(getter, mapID)
    if not success or type(overlays) ~= "table" then return snapshot end
    local envelope
    for i, overlay in ipairs(overlays) do
        if type(overlay) == "table" and overlay.isShownByMouseOver ~= true then
            local w, h, x, y = overlay.textureWidth, overlay.textureHeight, overlay.offsetX, overlay.offsetY
            local files = overlay.fileDataIDs
            if Positive(w) and Positive(h) and Number(x) and Number(y) and type(files) == "table" then
                local nc, nr = math.ceil(w / tw), math.ceil(h / th)
                local usable = nc * nr <= 128 and #files >= nc * nr
                for index = 1, usable and nc * nr or 0 do
                    if not Usable(files[index]) then usable = false; break end
                end
                -- Eligibility and crop use placed image extents, never hitRect or a minimum size.
                local left, right, top, bottom = math.max(0, x), math.min(lw, x + w), math.max(0, y), math.min(lh, y + h)
                if usable and right > left and bottom > top then
                    for r = 0, nr - 1 do
                        for c = 0, nc - 1 do
                            local pw, ph = math.min(tw, w - c * tw), math.min(th, h - r * th)
                            snapshot.tiles[#snapshot.tiles + 1] = { file = files[r * nc + c + 1], x = x + c * tw, y = y + r * th,
                                width = pw, height = ph, fileWidth = FileSize(pw, tw), fileHeight = FileSize(ph, th),
                                kind = "OVERLAY", overlay = i, sublevel = overlay.isDrawOnTopLayer == true and 3 or 2 }
                        end
                    end
                    snapshot.overlayCount = snapshot.overlayCount + 1
                    envelope = envelope or { left = left, right = right, top = top, bottom = bottom }
                    envelope.left, envelope.right = math.min(envelope.left, left), math.max(envelope.right, right)
                    envelope.top, envelope.bottom = math.min(envelope.top, top), math.max(envelope.bottom, bottom)
                end
            end
        end
    end
    if envelope then snapshot.source, snapshot.exploredBounds = "BASE_EXPLORATION", envelope end
    return snapshot
end

function Art:Crop(snapshot, width, height)
    local rect, envelope = snapshot.rect, snapshot.exploredBounds
    local aspect = width / height
    local cropWidth, cropHeight, cx, cy
    if envelope then
        cropWidth = math.max(envelope.right - envelope.left, (envelope.bottom - envelope.top) * aspect)
        cropHeight = cropWidth / aspect
        local fit = math.min(1, rect.width / cropWidth, rect.height / cropHeight)
        cropWidth, cropHeight = cropWidth * fit, cropHeight * fit
        cx, cy = (envelope.left + envelope.right) / 2, (envelope.top + envelope.bottom) / 2
    else
        cropWidth = math.min(rect.width, rect.height * aspect)
        cropHeight = cropWidth / aspect
        cx, cy = rect.x + rect.width / 2, rect.y + rect.height / 2
    end
    return { x = math.max(rect.x, math.min(rect.x + rect.width - cropWidth, cx - cropWidth / 2)),
        y = math.max(rect.y, math.min(rect.y + rect.height - cropHeight, cy - cropHeight / 2)),
        width = cropWidth, height = cropHeight }
end

-- Base and overlays share one uniform source-pixel transform. Clipping adjusts UVs
-- including padded overlay files, so map features and tile seams never stretch.
function Art:Project(snapshot, width, height)
    local crop = self:Crop(snapshot, width, height)
    local scale = width / crop.width
    local pieces = {}
    for _, tile in ipairs(snapshot.tiles) do
        local x0, y0 = math.max(crop.x, tile.x), math.max(crop.y, tile.y)
        local x1, y1 = math.min(crop.x + crop.width, tile.x + tile.width), math.min(crop.y + crop.height, tile.y + tile.height)
        if x1 > x0 and y1 > y0 then
            pieces[#pieces + 1] = { file = tile.file, kind = tile.kind, overlay = tile.overlay, sublevel = tile.sublevel,
                x = (x0 - crop.x) * scale, y = (y0 - crop.y) * scale,
                width = (x1 - x0) * scale, height = (y1 - y0) * scale,
                u0 = (x0 - tile.x) / tile.fileWidth, u1 = (x1 - tile.x) / tile.fileWidth,
                v0 = (y0 - tile.y) / tile.fileHeight, v1 = (y1 - tile.y) / tile.fileHeight }
        end
    end
    return pieces
end

function Art:Hide(row)
    for _, texture in ipairs(row.artTextures or { row.art, row.art2 }) do texture:Hide() end
end

function Art:Render(row, parent, snapshot, x, y, width, height)
    self:Hide(row)
    if not snapshot then return 0, "PAPER" end
    row.artTextures = row.artTextures or { row.art, row.art2 }
    local pieces = self:Project(snapshot, width, height)
    local applied, badOverlays = {}, {}
    for i, piece in ipairs(pieces) do
        local texture = row.artTextures[i]
        if not texture then
            texture = parent:CreateTexture(nil, "ARTWORK", nil, 1)
            row.artTextures[i] = texture
        end
        local ok, accepted = pcall(texture.SetTexture, texture, piece.file)
        if ok and accepted ~= false then
            texture:ClearAllPoints(); texture:SetPoint("TOPLEFT", parent, "TOPLEFT", x + piece.x, -y - piece.y)
            texture:SetSize(piece.width, piece.height)
            texture:SetTexCoord(piece.u0, piece.u1, piece.v0, piece.v1)
            texture:SetDrawLayer("ARTWORK", piece.sublevel)
            texture:SetAlpha(1); texture:Show()
            applied[#applied + 1] = { texture = texture, kind = piece.kind, overlay = piece.overlay }
        elseif piece.kind == "OVERLAY" then
            badOverlays[piece.overlay] = true
        end
    end
    local bases, overlays = 0, 0
    for _, item in ipairs(applied) do
        if item.kind == "BASE" then bases = bases + 1
        elseif badOverlays[item.overlay] then item.texture:Hide()
        else overlays = overlays + 1 end
    end
    if bases == 0 then
        self:Hide(row)
        if snapshot.fallback then return self:Render(row, parent, snapshot.fallback, x, y, width, height) end
        return 0, "PAPER"
    end
    local source = snapshot.source
    if source == "BASE_EXPLORATION" and overlays == 0 then source = "BASE_ONLY" end
    return bases + overlays, source
end
