local MS = _G.MS
MS.GameSurfaceContract = { version = "V3", generation = 0 }
local Contract = MS.GameSurfaceContract
local function Finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
local function Read(frame, method)
    if not frame or type(frame[method]) ~= "function" then return end
    local ok, a, b, c, d = pcall(frame[method], frame)
    if ok then return a, b, c, d end
end
local function Rect(r)
    return type(r) == "table" and Finite(r.x) and Finite(r.y) and Finite(r.width) and r.width > 0
        and Finite(r.height) and r.height > 0 and Finite(r.x + r.width) and Finite(r.y + r.height)
end
local function Immutable(data)
    return setmetatable({}, { __index = data, __newindex = function() error("IMMUTABLE_GAME_SURFACE", 2) end,
        __metatable = "GameSurfaceContract" })
end
local function CopyRect(r)
    return Rect(r) and Immutable({ x = r.x, y = r.y, width = r.width, height = r.height }) or nil
end

-- Refresh only at explicit topology/lifecycle boundaries. Hot paths use Get().
function Contract:Refresh()
    local ok, data = pcall(function()
        local layout, metrics = MS.Config:GetLayout(), MS.Transform:GetMetrics()
        if not layout or not metrics then return end
        local game = MS.Transform:RectToUI(layout.game, metrics)
        local screen = { x = 0, y = 0, width = Read(UIParent, "GetWidth"), height = Read(UIParent, "GetHeight") }
        -- The screen is the full window: SPAN_ROOT (equal to native UIParent in
        -- LEGACY, wider than the GAME-sized UIParent in VIEWPORT).
        if MS.ViewportRoots then
            local spanWidth, spanHeight = MS.ViewportRoots:GetSpanSize()
            if spanWidth then screen.width, screen.height = spanWidth, spanHeight end
        end
        local effective, uiScale = Read(UIParent, "GetEffectiveScale"), Read(UIParent, "GetScale")
        if not Rect(game) or not Rect(screen) or not Finite(effective) or effective <= 0 then return end
        local inside = game.x >= 0 and game.y >= 0 and game.x + game.width <= screen.width + .001
            and game.y + game.height <= screen.height + .001
        local anchor = MS.GameUI and MS.GameUI.frame
        local x, y, w, h = Read(anchor, "GetRect")
        local scale = Read(anchor, "GetEffectiveScale")
        local anchorMatches = Finite(scale) and scale > 0 and Finite(x) and Finite(y) and Finite(w) and Finite(h)
            and math.abs(x * scale / effective - game.x) < 1 and math.abs(y * scale / effective - game.y) < 1
            and math.abs(w * scale / effective - game.width) < 1 and math.abs(h * scale / effective - game.height) < 1
        local physical = CopyRect(layout.game)
        local workspace = layout.workspace and MS.Transform:RectToUI(layout.workspace, metrics)
        local _, build, _, interface = GetBuildInfo()
        return { uiRect = CopyRect(game), physicalRect = physical, origin = Immutable({ x = game.x, y = game.y }),
            screenRect = CopyRect(screen), workspaceRect = CopyRect(workspace),
            width = game.width, height = game.height, uiScale = uiScale or effective, effectiveScale = effective,
            metrics = Immutable({ pixelsPerUiX = metrics.pixelsPerUiX, pixelsPerUiY = metrics.pixelsPerUiY,
                physicalWidth = metrics.physicalWidth, physicalHeight = metrics.physicalHeight }),
            runtimeToken = tostring(MS.Runtime and MS.Runtime.enableGeneration or 0) .. ":" .. tostring(MS.Runtime and MS.Runtime.state or "UNINITIALIZED"),
            clientBuild = tostring(build), clientInterface = interface,
            safety = Immutable({ validTopology = inside, anchorMatches = anchorMatches == true }) }
    end)
    local signature = "INVALID"
    if ok and data then
        local parts = {}
        for _, field in ipairs({ "uiRect", "screenRect", "physicalRect", "workspaceRect" }) do
            local r = data[field]
            for _, key in ipairs({ "x", "y", "width", "height" }) do parts[#parts + 1] = tostring(r and r[key]) end
        end
        for _, key in ipairs({ "uiScale", "effectiveScale", "clientBuild", "clientInterface", "runtimeToken" }) do
            parts[#parts + 1] = tostring(data[key])
        end
        parts[#parts + 1] = tostring(data.safety.anchorMatches)
        parts[#parts + 1] = tostring(data.metrics.pixelsPerUiX)
        parts[#parts + 1] = tostring(data.metrics.pixelsPerUiY)
        signature = table.concat(parts, "|")
    end
    if signature ~= self.signature then
        self.generation = self.generation + 1
        self.signature = signature
        if data and ok then
            data.version, data.generation = self.version, self.generation
            data.topologyGeneration, data.runtimeGeneration = self.generation, self.generation
            self.current = Immutable(data)
        else self.current = nil end
    end
    return self.current
end
function Contract:Get() return self.current end
