loadstring([==[
--[[
    ████████╗██████╗ ██╗ ██████╗  ██████╗ ███╗   ██╗
    ╚══██╔══╝██╔══██╗██║██╔════╝ ██╔═══██╗████╗  ██║
       ██║   ██████╔╝██║██║  ███╗██║   ██║██╔██╗ ██║
       ██║   ██╔══██╗██║██║   ██║██║   ██║██║╚██╗██║
       ██║   ██║  ██║██║╚██████╔╝╚██████╔╝██║ ╚████║
       ╚═╝   ╚═╝  ╚═╝╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝
   
   TRIGON.PLUGIN v1.0 — Universal Shooter Hub
   Single-file loadstring. Studio + Executor safe.
   By AxomJB
--]]

-- ═══════════════════════════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════════════════════════
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local LocalPlayer      = Players.LocalPlayer
local Camera           = Workspace.CurrentCamera

-- ═══════════════════════════════════════════════════════════════
-- CONFIG
-- ═══════════════════════════════════════════════════════════════
local Config = {
    Version = "1.0.0",
    Defaults = {
        ESP = {
            Enabled = false, Boxes = true, Names = true,
            Health = true, Tracers = true, MaxDistance = 500, TeamColor = true,
        },
        Aimbot = {
            Enabled = false, Key = Enum.KeyCode.E, FOV = 120,
            Smoothness = 0.15, Bone = "Head", TeamCheck = true, Visible = false,
        },
        SilentAim = { Enabled = false, Mode = "Camera", Bone = "Head", TeamCheck = true },
        FOV = {
            Visible = true, Radius = 120,
            Color = Color3.fromRGB(0, 200, 255),
            Transparency = 0.5, Thickness = 1,
        },
        UI = { Position = Vector2.new(40, 120), Theme = "Midnight", Scale = 1.0 },
        Performance = { RenderThrottle = 1/120, MaxTargets = 64 },
    },
}

-- ═══════════════════════════════════════════════════════════════
-- CORE: SIGNAL
-- ═══════════════════════════════════════════════════════════════
local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
    assert(typeof(fn) == "function", "Signal:Connect expects function")
    local conn = { fn = fn, connected = true }
    table.insert(self._handlers, conn)
    return {
        Disconnect = function()
            conn.connected = false
            for i, c in ipairs(self._handlers) do
                if c == conn then table.remove(self._handlers, i) break end
            end
        end,
    }
end

function Signal:Fire(...)
    for _, conn in ipairs(self._handlers) do
        if conn.connected then
            local ok, err = pcall(conn.fn, ...)
            if not ok then warn("[Trigon Signal] " .. tostring(err)) end
        end
    end
end

function Signal:Clear()
    for _, conn in ipairs(self._handlers) do conn.connected = false end
    self._handlers = {}
end

-- ═══════════════════════════════════════════════════════════════
-- CORE: STORE
-- ═══════════════════════════════════════════════════════════════
local Store = {}
Store.__index = Store

function Store.new(initial)
    local self = setmetatable({
        _state = {},
        Changed = Signal.new(),
    }, Store)
    self._state = self:_deepClone(initial or {})
    return self
end

function Store:_deepClone(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = self:_deepClone(v) end
    return out
end

function Store:Get(path)
    local node = self._state
    for part in string.gmatch(path, "[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

function Store:Set(path, value)
    local parts = {}
    for p in string.gmatch(path, "[^%.]+") do table.insert(parts, p) end
    local node = self._state
    for i = 1, #parts - 1 do
        if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
        node = node[parts[i]]
    end
    node[parts[#parts]] = value
    self.Changed:Fire(path, value)
end

function Store:Snapshot() return self:_deepClone(self._state) end

function Store:Load(snapshot)
    self._state = self:_deepClone(snapshot)
    self.Changed:Fire("*", snapshot)
end

-- ═══════════════════════════════════════════════════════════════
-- CORE: UTIL
-- ═══════════════════════════════════════════════════════════════
local Util = {}

function Util.isAlive(plr)
    local char = plr and plr.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

function Util.getRoot(plr)
    local char = plr and plr.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

function Util.getHead(plr)
    local char = plr and plr.Character
    return char and char:FindFirstChild("Head")
end

function Util.getHum(plr)
    local char = plr and plr.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

function Util.isTeammate(plr)
    return plr.Team ~= nil and plr.Team == LocalPlayer.Team
end

function Util.dist(a, b) return (a - b).Magnitude end
function Util.lerp(a, b, t) return a + (b - a) * t end

function Util.trackConnection(bag, conn)
    table.insert(bag, conn)
    return conn
end

function Util.disconnectAll(bag)
    for _, c in ipairs(bag) do
        if typeof(c) == "RBXScriptConnection" then
            pcall(function() c:Disconnect() end)
        end
    end
    table.clear(bag)
end

-- ═══════════════════════════════════════════════════════════════
-- RENDER: DRAW (Drawing wrapper w/ Studio fallback)
-- ═══════════════════════════════════════════════════════════════
local Draw = {}
Draw.hasDrawing = (typeof(Drawing) == "table" and typeof(Drawing.new) == "function")

local fallbackHost
if not Draw.hasDrawing then
    local pg = LocalPlayer:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "TrigonFallback"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 999
    gui.Parent = pg

    fallbackHost = Instance.new("Frame")
    fallbackHost.Size = UDim2.fromScale(1, 1)
    fallbackHost.BackgroundTransparency = 1
    fallbackHost.Parent = gui
end

local Handle = {}
Handle.__index = function(self, key)
    return rawget(self, "_cached_" .. key) or (self._obj and self._obj[key])
end

function Handle.__newindex(self, key, value)
    if self._native then
        local obj = self._obj
        if key == "Color" then obj.BackgroundColor3 = value
        elseif key == "Transparency" then obj.BackgroundTransparency = value
        elseif key == "Visible" then obj.Visible = value
        elseif key == "Text" then obj.Text = value
        elseif key == "Size" and typeof(value) == "Vector2" then
            obj.Size = UDim2.fromOffset(value.X, value.Y)
        elseif key == "Position" and typeof(value) == "Vector2" then
            obj.Position = UDim2.fromOffset(value.X, value.Y)
        elseif key == "Center" and value then
            obj.AnchorPoint = Vector2.new(0.5, 0.5)
        elseif key == "Outline" and value then
            local s = Instance.new("UIStroke", obj)
            s.Color = Color3.new(0, 0, 0)
            s.Thickness = 1
        elseif key == "OutlineColor" then
            local s = obj:FindFirstChildOfClass("UIStroke")
            if s then s.Color = value end
        end
    else
        self._obj[key] = value
    end
    rawset(self, "_cached_" .. key, value)
end

function Handle:Remove()
    if self._native then
        if self._obj and self._obj.Parent then self._obj:Destroy() end
    else
        if self._obj and self._obj.Remove then self._obj:Remove() end
    end
end

function Draw.new(class, props)
    if Draw.hasDrawing then
        local obj = Drawing.new(class)
        for k, v in pairs(props or {}) do obj[k] = v end
        return setmetatable({ _obj = obj, _native = false }, Handle)
    end

    local instance
    if class == "Line" or class == "Square" then
        instance = Instance.new("Frame")
        instance.BorderSizePixel = 0
    elseif class == "Text" then
        instance = Instance.new("TextLabel")
        instance.BackgroundTransparency = 1
        instance.Font = Enum.Font.Code
        instance.TextScaled = false
    elseif class == "Circle" then
        instance = Instance.new("Frame")
        instance.BackgroundTransparency = 1
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = instance
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1
        stroke.Parent = instance
    else
        instance = Instance.new("Frame")
    end
    instance.Parent = fallbackHost

    local self = setmetatable({ _obj = instance, _native = true, _class = class }, Handle)
    for k, v in pairs(props or {}) do self[k] = v end
    return self
end

function Draw.cleanup()
    if not Draw.hasDrawing and fallbackHost then
        for _, c in ipairs(fallbackHost:GetChildren()) do
            if c:IsA("GuiObject") then c:Destroy() end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- RENDER: CAMERA
-- ═══════════════════════════════════════════════════════════════
local Cam = {}

function Cam.worldToScreen(worldPos)
    local cam = Workspace.CurrentCamera
    if not cam then return Vector2.zero, false end
    local sp, onScreen = cam:WorldToViewportPoint(worldPos)
    return Vector2.new(sp.X, sp.Y), onScreen and sp.Z > 0
end

function Cam.viewportCenter()
    local cam = Workspace.CurrentCamera
    if not cam then return Vector2.zero end
    return Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
end

function Cam.distanceTo(pos)
    local cam = Workspace.CurrentCamera
    if not cam then return math.huge end
    return (cam.CFrame.Position - pos).Magnitude
end

-- ═══════════════════════════════════════════════════════════════
-- RENDER: THEME
-- ═══════════════════════════════════════════════════════════════
local Theme = {
    Midnight = {
        Bg = Color3.fromRGB(12, 12, 18), BgAlt = Color3.fromRGB(20, 20, 28),
        Accent = Color3.fromRGB(0, 200, 255), Text = Color3.fromRGB(220, 220, 220),
        TextDim = Color3.fromRGB(140, 140, 150), Danger = Color3.fromRGB(255, 70, 70),
        Success = Color3.fromRGB(0, 220, 120),
    },
    Blood = {
        Bg = Color3.fromRGB(15, 8, 8), BgAlt = Color3.fromRGB(24, 12, 12),
        Accent = Color3.fromRGB(255, 40, 40), Text = Color3.fromRGB(240, 220, 220),
        TextDim = Color3.fromRGB(150, 110, 110), Danger = Color3.fromRGB(255, 80, 80),
        Success = Color3.fromRGB(120, 255, 120),
    },
}
function Theme.get(n) return Theme[n] or Theme.Midnight end

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: ESP
-- ═══════════════════════════════════════════════════════════════
local ESP = {}
ESP.__index = ESP

function ESP.new(store)
    return setmetatable({
        store = store, _drawings = {}, _conn = nil, _lastRender = 0,
    }, ESP)
end

function ESP:_clearPlayer(plr)
    local bag = self._drawings[plr]
    if not bag then return end
    for _, obj in pairs(bag) do obj:Remove() end
    self._drawings[plr] = nil
end

function ESP:_renderPlayer(plr)
    local root = Util.getRoot(plr)
    local head = Util.getHead(plr)
    local hum  = Util.getHum(plr)
    if not (root and head and hum and hum.Health > 0) then
        return self:_clearPlayer(plr)
    end

    local dist = Cam.distanceTo(root.Position)
    if dist > self.store:Get("ESP.MaxDistance") then
        return self:_clearPlayer(plr)
    end

    local topWorld    = head.Position + Vector3.new(0, 1, 0)
    local bottomWorld = root.Position - Vector3.new(0, 3, 0)
    local topScreen, topOn    = Cam.worldToScreen(topWorld)
    local bottomScreen, botOn = Cam.worldToScreen(bottomWorld)
    if not (topOn and botOn) then return self:_clearPlayer(plr) end

    local h = bottomScreen.Y - topScreen.Y
    local w = h * 0.6

    local color
    if self.store:Get("ESP.TeamColor") and plr.Team then
        color = plr.Team.TeamColor.Color
    else
        color = Util.isTeammate(plr) and Color3.fromRGB(0, 220, 120)
                                     or Color3.fromRGB(255, 60, 60)
    end

    local bag = self._drawings[plr]
    if not bag then bag = {} self._drawings[plr] = bag end

    if self.store:Get("ESP.Boxes") then
        if not bag.box then
            bag.box = Draw.new("Square", { Filled = false, Thickness = 1, Visible = true })
        end
        bag.box.Size = Vector2.new(w, h)
        bag.box.Position = Vector2.new(topScreen.X - w / 2, topScreen.Y)
        bag.box.Color = color
        bag.box.Visible = true
    elseif bag.box then bag.box.Visible = false end

    if self.store:Get("ESP.Names") then
        if not bag.name then
            bag.name = Draw.new("Text", { Size = 14, Center = true, Outline = true, Color = color, Visible = true })
        end
        bag.name.Text = plr.Name
        bag.name.Position = Vector2.new(topScreen.X, topScreen.Y - 16)
        bag.name.Color = color
        bag.name.Visible = true
    elseif bag.name then bag.name.Visible = false end

    if self.store:Get("ESP.Health") then
        if not bag.hp then
            bag.hp = Draw.new("Text", { Size = 12, Center = true, Outline = true, Color = Color3.new(1,1,1), Visible = true })
        end
        bag.hp.Text = string.format("%d HP", math.floor(hum.Health))
        bag.hp.Position = Vector2.new(topScreen.X, bottomScreen.Y + 2)
        bag.hp.Visible = true
    elseif bag.hp then bag.hp.Visible = false end

    if self.store:Get("ESP.Tracers") then
        if not bag.tracer then
            bag.tracer = Draw.new("Line", { Thickness = 1, Transparency = 0.5, Color = color, Visible = true })
        end
        local origin = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
        bag.tracer.From = origin
        bag.tracer.To = Vector2.new(topScreen.X, (topScreen.Y + bottomScreen.Y) / 2)
        bag.tracer.Color = color
        bag.tracer.Visible = true
    elseif bag.tracer then bag.tracer.Visible = false end
end

function ESP:Start()
    if self._conn then return end
    local throttle = self.store:Get("Performance.RenderThrottle") or (1/120)
    self._conn = RunService.RenderStepped:Connect(function()
        local now = os.clock()
        if now - self._lastRender < throttle then return end
        self._lastRender = now

        if not self.store:Get("ESP.Enabled") then
            for plr in pairs(self._drawings) do self:_clearPlayer(plr) end
            return
        end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local ok, err = pcall(self._renderPlayer, self, plr)
                if not ok then warn("[Trigon ESP] " .. tostring(err)) self:_clearPlayer(plr) end
            end
        end
    end)
end

function ESP:Stop()
    if self._conn then self._conn:Disconnect() self._conn = nil end
    for plr in pairs(self._drawings) do self:_clearPlayer(plr) end
end

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: AIMBOT
-- ═══════════════════════════════════════════════════════════════
local Aimbot = {}
Aimbot.__index = Aimbot

function Aimbot.new(store)
    return setmetatable({
        store = store, _conn = nil, _begConn = nil, _endConn = nil, _holding = false,
    }, Aimbot)
end

function Aimbot:_acquireTarget()
    local center = Cam.viewportCenter()
    local fov = self.store:Get("Aimbot.FOV")
    local teamCheck = self.store:Get("Aimbot.TeamCheck")
    local bone = self.store:Get("Aimbot.Bone")
    local bestTarget, bestDist = nil, fov

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and Util.isAlive(plr) then
            if not (teamCheck and Util.isTeammate(plr)) then
                local part = (bone == "Head") and Util.getHead(plr) or Util.getRoot(plr)
                if part then
                    local screen, onScreen = Cam.worldToScreen(part.Position)
                    if onScreen then
                        local d = (screen - center).Magnitude
                        if d < bestDist then bestTarget, bestDist = part, d end
                    end
                end
            end
        end
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and not Players:GetPlayerFromCharacter(obj) then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            local part = (bone == "Head") and obj:FindFirstChild("Head") or obj:FindFirstChild("HumanoidRootPart")
            if hum and part and hum.Health > 0 then
                local screen, onScreen = Cam.worldToScreen(part.Position)
                if onScreen then
                    local d = (screen - center).Magnitude
                    if d < bestDist then bestTarget, bestDist = part, d end
                end
            end
        end
    end
    return bestTarget
end

function Aimbot:_applyAim(targetPart)
    local cam = Workspace.CurrentCamera
    if not cam or not targetPart then return end
    local camPos = cam.CFrame.Position
    local desired = CFrame.new(camPos, targetPart.Position)
    local smooth = self.store:Get("Aimbot.Smoothness")
    cam.CFrame = cam.CFrame:Lerp(desired, math.clamp(smooth, 0.01, 1))
end

function Aimbot:Start()
    if self._conn then return end
    self._begConn = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == self.store:Get("Aimbot.Key") then self._holding = true end
    end)
    self._endConn = UserInputService.InputEnded:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == self.store:Get("Aimbot.Key") then self._holding = false end
    end)
    self._conn = RunService.RenderStepped:Connect(function()
        if not self.store:Get("Aimbot.Enabled") then return end
        local target = self:_acquireTarget()
        if self._holding and target then
            local ok, err = pcall(self._applyAim, self, target)
            if not ok then warn("[Trigon Aimbot] " .. tostring(err)) end
        end
    end)
end

function Aimbot:Stop()
    if self._conn then self._conn:Disconnect() self._conn = nil end
    if self._begConn then self._begConn:Disconnect() self._begConn = nil end
    if self._endConn then self._endConn:Disconnect() self._endConn = nil end
    self._holding = false
end

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: SILENT AIM (simulation only — read target from your own weapon)
-- ═══════════════════════════════════════════════════════════════
local SilentAim = {}
SilentAim.__index = SilentAim

function SilentAim.new(store)
    local self = setmetatable({
        store = store, _conn = nil, _target = nil,
    }, SilentAim)
    self.GetTarget = function() return self._target end
    return self
end

function SilentAim:_scan()
    local center = Cam.viewportCenter()
    local fov = self.store:Get("Aimbot.FOV")
    local teamCheck = self.store:Get("SilentAim.TeamCheck")
    local bone = self.store:Get("SilentAim.Bone")
    local bestTarget, bestDist = nil, fov

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and Util.isAlive(plr) then
            if not (teamCheck and Util.isTeammate(plr)) then
                local part = (bone == "Head") and Util.getHead(plr) or Util.getRoot(plr)
                if part then
                    local screen, onScreen = Cam.worldToScreen(part.Position)
                    if onScreen then
                        local d = (screen - center).Magnitude
                        if d < bestDist then bestTarget, bestDist = part, d end
                    end
                end
            end
        end
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and not Players:GetPlayerFromCharacter(obj) then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            local part = (bone == "Head") and obj:FindFirstChild("Head") or obj:FindFirstChild("HumanoidRootPart")
            if hum and part and hum.Health > 0 then
                local screen, onScreen = Cam.worldToScreen(part.Position)
                if onScreen then
                    local d = (screen - center).Magnitude
                    if d < bestDist then bestTarget, bestDist = part, d end
                end
            end
        end
    end
    return bestTarget
end

function SilentAim:Start()
    if self._conn then return end
    self._conn = RunService.RenderStepped:Connect(function()
        if not self.store:Get("SilentAim.Enabled") then
            self._target = nil
            return
        end
        self._target = self:_scan()
    end)
end

function SilentAim:Stop()
    if self._conn then self._conn:Disconnect() self._conn = nil end
    self._target = nil
end

-- ═══════════════════════════════════════════════════════════════
-- FEATURE: FOV CIRCLE
-- ═══════════════════════════════════════════════════════════════
local FOV = {}
FOV.__index = FOV

function FOV.new(store)
    return setmetatable({ store = store, _circle = nil, _conn = nil }, FOV)
end

function FOV:Start()
    if self._conn then return end
    self._circle = Draw.new("Circle", {
        Thickness = self.store:Get("FOV.Thickness"),
        Color = self.store:Get("FOV.Color"),
        Transparency = self.store:Get("FOV.Transparency"),
        Filled = false, Visible = true, NumSides = 64,
    })
    self._conn = RunService.RenderStepped:Connect(function()
        if not self._circle then return end
        local visible = self.store:Get("FOV.Visible")
        self._circle.Visible = visible
        if not visible then return end
        self._circle.Position = Cam.viewportCenter()
        self._circle.Radius = self.store:Get("FOV.Radius")
        self._circle.Color = self.store:Get("FOV.Color")
        self._circle.Transparency = self.store:Get("FOV.Transparency")
        self._circle.Thickness = self.store:Get("FOV.Thickness")
    end)
end

function FOV:Stop()
    if self._conn then self._conn:Disconnect() self._conn = nil end
    if self._circle then self._circle:Remove() self._circle = nil end
end

-- ═══════════════════════════════════════════════════════════════
-- UI FRAMEWORK
-- ═══════════════════════════════════════════════════════════════
local function buildUI(store, theme)
    local pg = LocalPlayer:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "TrigonHubUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = pg

    local T = Theme.get(theme)

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 260, 0, 340)
    main.Position = UDim2.new(0, store:Get("UI.Position").X, 0, store:Get("UI.Position").Y)
    main.BackgroundColor3 = T.Bg
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = gui

    local mc = Instance.new("UICorner")
    mc.CornerRadius = UDim.new(0, 10)
    mc.Parent = main

    local stroke = Instance.new("UIStroke")
    stroke.Color = T.Accent
    stroke.Thickness = 1.5
    stroke.Transparency = 0.3
    stroke.Parent = main

    local title = Instance.new("Frame")
    title.Size = UDim2.new(1, 0, 0, 34)
    title.BackgroundColor3 = T.BgAlt
    title.BorderSizePixel = 0
    title.Parent = main

    local tc = Instance.new("UICorner")
    tc.CornerRadius = UDim.new(0, 10)
    tc.Parent = title

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -50, 1, 0)
    titleLbl.Position = UDim2.new(0, 12, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = "🔺 TRIGON.PLUGIN v" .. Config.Version
    titleLbl.TextColor3 = T.Accent
    titleLbl.Font = Enum.Font.GothamBlack
    titleLbl.TextSize = 13
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = title

    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 22, 0, 22)
    close.Position = UDim2.new(1, -28, 0, 6)
    close.BackgroundColor3 = T.Danger
    close.Text = "×"
    close.TextColor3 = Color3.new(1,1,1)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 16
    close.BorderSizePixel = 0
    close.Parent = title

    local cc = Instance.new("UICorner")
    cc.CornerRadius = UDim.new(1, 0)
    cc.Parent = close

    close.MouseButton1Click:Connect(function() gui.Enabled = false end)

    -- Toggle button (mini)
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(0, 46, 0, 46)
    toggleBtn.Position = UDim2.new(0, 20, 0, 20)
    toggleBtn.BackgroundColor3 = T.Bg
    toggleBtn.Text = "🔺"
    toggleBtn.TextSize = 20
    toggleBtn.TextColor3 = T.Accent
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Visible = false
    toggleBtn.Parent = gui

    local tbc = Instance.new("UICorner")
    tbc.CornerRadius = UDim.new(1, 0)
    tbc.Parent = toggleBtn

    local toggleStroke = Instance.new("UIStroke")
    toggleStroke.Color = T.Accent
    toggleStroke.Thickness = 1.5
    toggleStroke.Parent = toggleBtn

    toggleBtn.MouseButton1Click:Connect(function()
        main.Visible = not main.Visible
        toggleBtn.Visible = not main.Visible
    end)

    -- Scroll list
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -12, 1, -44)
    scroll.Position = UDim2.new(0, 6, 0, 38)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = T.Accent
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = main

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 5)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroll

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 4)
    pad.Parent = scroll

    -- Drag
    local drag = false
    local dragOffset
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            drag = true
            dragOffset = Vector2.new(input.Position.X - main.AbsolutePosition.X,
                                     input.Position.Y - main.AbsolutePosition.Y)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if drag and input.UserInputType == Enum.UserInputType.MouseMovement then
            main.Position = UDim2.new(0, input.Position.X - dragOffset.X, 0, input.Position.Y - dragOffset.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
    end)

    -- Components
    local function section(text)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 20)
        f.BackgroundTransparency = 1
        f.Parent = scroll
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 1, 0)
        l.BackgroundTransparency = 1
        l.Text = text
        l.TextColor3 = T.Accent
        l.Font = Enum.Font.GothamBold
        l.TextSize = 11
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Parent = f
    end

    local function toggle(name, default, cb)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 26)
        btn.BackgroundColor3 = T.BgAlt
        btn.Text = ""
        btn.BorderSizePixel = 0
        btn.AutoButtonColor = false
        btn.Parent = scroll

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = btn

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -55, 1, 0)
        lbl.Position = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = name
        lbl.TextColor3 = T.Text
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = btn

        local ind = Instance.new("Frame")
        ind.Size = UDim2.new(0, 34, 0, 15)
        ind.Position = UDim2.new(1, -44, 0.5, -7.5)
        ind.BackgroundColor3 = default and T.Accent or Color3.fromRGB(45, 45, 55)
        ind.BorderSizePixel = 0
        ind.Parent = btn

        local ic = Instance.new("UICorner")
        ic.CornerRadius45 = UDim.new(1,, 0 )
        ic.Parent = ind55

        local knob = Instance.new)
("Frame")
        knob.Size = UDim       2.new(0, 11, 0, 11)
        knob.Position = default and UDim2.new(1, -13, 0.5, -5.5) or UDim2.new(0, 2, 0.5, -5.5)
        knob.BackgroundColor3 = Color3.new(1,1,1)
        knob.BorderSizePixel = 0
        knob.Parent = ind

        local kc = Instance.new("UICorner")
        kc.CornerRadius = UDim.new(1, 0)
        kc.Parent = knob

        local state = default
        btn.MouseButton1Click:Connect(function()
            state = not state
            ind.BackgroundColor3 = state and T.Accent or Color3.fromRGB(45, 45, 55)
            knob.Position = state and UDim2.new(1, -13, 0.5, -5.5) or UDim2.new(0, 2, 0.5, -5.5)
            if cb then cb(state) end
        end)
    end

    local function slider(name, min, max, default, cb)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 38)
        f.BackgroundColor3 = T.BgAlt
        f.BorderSizePixel = 0
        f.Parent = scroll

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = f

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -20, 0, 16)
        lbl.Position = UDim2.new(0, 10, 0, 2)
        lbl.BackgroundTransparency = 1
        lbl.Text = name .. ": " .. tostring(default)
        lbl.TextColor3 = T.Text
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = f

        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, -20, 0, 5)
        track.Position = UDim2.new(0, 10, 0, 25)
        track.BackgroundColor3 = Color3.fromRGB(45,  track.BorderSizePixel = 0
        track.Parent = f

        local trc = Instance.new("UICorner")
        trc.CornerRadius = UDim.new(1, 0)
        trc.Parent = track

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
        fill.BackgroundColor3 = T.Accent
        fill.BorderSizePixel = 0
        fill.Parent = track

        local fc = Instance.new("UICorner")
        fc.CornerRadius = UDim.new(1, 0)
        fc.Parent = fill

        local dragging = false
        local function upd(input)
            local rel = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            local v = min + (max - min) * rel
            fill.Size = UDim2.new(rel, 0, 1, 0)
            lbl.Text = name .. ": " .. string.format("%.2f", v)
            if cb then cb(v) end
        end
        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true upd(input)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then upd(input) end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
    end

    -- Build menu
    section("▸ ESP")
    toggle("ESP Master", store:Get("ESP.Enabled"), function(v) store:Set("ESP.Enabled", v) end)
    toggle("Boxes", store:Get("ESP.Boxes"), function(v) store:Set("ESP.Boxes", v) end)
    toggle("Names", store:Get("ESP.Names"), function(v) store:Set("ESP.Names", v) end)
    toggle("Health", store:Get("ESP.Health"), function(v) store:Set("ESP.Health", v) end)
    toggle("Tracers", store:Get("ESP.Tracers"), function(v) store:Set("ESP.Tracers", v) end)
    toggle("Team Color", store:Get("ESP.TeamColor"), function(v) store:Set("ESP.TeamColor", v) end)
    slider("Max Distance", 50, 2000, store:Get("ESP.MaxDistance"), function(v) store:Set("ESP.MaxDistance", v) end)

    section("▸ AIMBOT")
    toggle("Aimbot Master", store:Get("Aimbot.Enabled"), function(v) store:Set("Aimbot.Enabled", v) end)
    toggle("Team Check", store:Get("Aimbot.TeamCheck"), function(v) store:Set("Aimbot.TeamCheck", v) end)
    slider("Smoothness", 0.01, 1, store:Get("Aimbot.Smoothness"), function(v) store:Set("Aimbot.Smoothness", v) end)

    section("▸ SILENT AIM")
    toggle("Silent Master", store:Get("SilentAim.Enabled"), function(v) store:Set("SilentAim.Enabled", v) end)
    toggle("Team Check", store:Get("SilentAim.TeamCheck"), function(v) store:Set("SilentAim.TeamCheck", v) end)

    section("▸ FOV")
    toggle("Show Circle", store:Get("FOV.Visible"), function(v) store:Set("FOV.Visible", v) end)
    slider("Radius", 20, 600, store:Get("FOV.Radius"), function(v)
        store:Set("FOV.Radius", v)
        store:Set("Aimbot.FOV", v)
    end)
    slider("Transparency", 0, 1, store:Get("FOV.Transparency"), function(v) store:Set("FOV.Transparency", v) end)

    return gui, toggleBtn, main
end

-- ═══════════════════════════════════════════════════════════════
-- BOOTSTRAP
-- ═══════════════════════════════════════════════════════════════
local Trigon = {}
Trigon.Version = Config.Version
Trigon.Store = Store.new(Config.Defaults)

Trigon.ESP        = ESP.new(Trigon.Store)
Trigon.Aimbot     = Aimbot.new(Trigon.Store)
Trigon.SilentAim  = SilentAim.new(Trigon.Store)
Trigon.FOV        = FOV.new(Trigon.Store)

Trigon.ESP:Start()
Trigon.Aimbot:Start()
Trigon.SilentAim:Start()
Trigon.FOV:Start()

local gui, toggleBtn = buildUI(Trigon.Store, Trigon.Store:Get("UI.Theme"))

-- RightShift toggles UI
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        gui.Enabled = not gui.Enabled
    end
end)

-- Cleanup API
function Trigon.Unload()
    pcall(function() Trigon.ESP:Stop() end)
    pcall(function() Trigon.Aimbot:Stop() end)
    pcall(function() Trigon.SilentAim:Stop() end)
    pcall(function() Trigon.FOV:Stop() end)
    if gui then gui:Destroy() end
    Draw.cleanup()
    Util.disconnectAll({})
    Trigon.Store.Changed:Clear()
end

-- Global reference for game code to read silent target
_G.TrigonHub = Trigon

print("[Trigon.Plugin] ✅ Loaded v" .. Trigon.Version)
print("[Trigon.Plugin] RightShift toggles UI | E = aimbot hold | Drawing:", Draw.hasDrawing and "native" or "fallback (Studio)")

return Trigon
]==])()
