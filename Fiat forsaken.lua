-- fiat_hub_delta.lua (corrigido para garantir que a UI apareça)
-- Versão adaptada para executor "Delta"
-- Ajustes:
--  - Garante LocalPlayer disponível
--  - Criação do Fluent protegida por pcall; fallback funcional em ScreenGui se necessário
--  - Prints/warns para debugging no executor

-- Serviços
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")

-- garante LocalPlayer válido (alguns ambientes podem não ter imediatamente)
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    repeat task.wait(0.03) LocalPlayer = Players.LocalPlayer until LocalPlayer
end

-- Helpers
local function safeWait(t) task.wait(t or 0.03) end

-- ---------- carrega Fluent com pcall ----------
local ok, Fluent = pcall(function()
    -- URL: pode variar conforme a fonte; pcall protege falhas
    return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
end)
if not ok or not Fluent then
    warn("[fiat_hub] Falha ao carregar Fluent. Mensagem:", Fluent)
    Fluent = nil
end

-- tenta carregar addons (pcall para segurança)
local SaveManager, InterfaceManager
pcall(function() SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))() end)
pcall(function() InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))() end)

-- ---------- função para pressionar teclas (muitos fallbacks, incluindo Delta) ----------
local keypressMethod = nil -- string descrevendo o método detectado
local function detectKeypressMethod()
    if keypressMethod then return keypressMethod end

    if type(syn) == "table" and syn.keypress then
        keypressMethod = "syn.keypress"
        return keypressMethod
    end

    if type(keypress) == "function" then
        keypressMethod = "global.keypress"
        return keypressMethod
    end

    local deltaCandidates = {"delta","Delta","DELTA"}
    for _, name in ipairs(deltaCandidates) do
        local ok, val = pcall(function() return _G[name] or _G[name:lower()] or _G[name:upper()] end)
        if ok and val then
            if type(val) == "table" then
                if val.keypress and type(val.keypress) == "function" then
                    keypressMethod = "delta.keypress"
                    return keypressMethod
                end
                if val.KeyPress and type(val.KeyPress) == "function" then
                    keypressMethod = "delta.KeyPress"
                    return keypressMethod
                end
                if val.Input and type(val.Input) == "function" then
                    keypressMethod = "delta.Input"
                    return keypressMethod
                end
            elseif type(val) == "function" then
                keypressMethod = "delta.globalfunc"
                return keypressMethod
            end
        end
    end

    local success, vim = pcall(function() return game:GetService("VirtualInputManager") end)
    if success and vim and vim.SendKeyEvent then
        keypressMethod = "VirtualInputManager"
        return keypressMethod
    end

    local vu = game:GetService("VirtualUser")
    if vu then
        keypressMethod = "VirtualUser"
        return keypressMethod
    end

    keypressMethod = "none"
    return keypressMethod
end

local function pressKey(keyStr)
    local method = detectKeypressMethod()
    pcall(function() print("[fiat_hub] keypress method:", method) end)

    if method == "syn.keypress" then
        pcall(function() syn.keypress(keyStr) end)
        return true
    end

    if method == "global.keypress" then
        local ok, res = pcall(function() return keypress(keyStr) end)
        return ok
    end

    if method == "delta.keypress" or method == "delta.KeyPress" or method == "delta.Input" or method == "delta.globalfunc" then
        local deltaNames = {"delta","Delta","DELTA"}
        for _, nm in ipairs(deltaNames) do
            local obj = _G[nm] or _G[nm:lower()] or _G[nm:upper()]
            if obj then
                pcall(function()
                    if type(obj.keypress) == "function" then obj.keypress(keyStr) end
                    if type(obj.KeyPress) == "function" then obj.KeyPress(keyStr) end
                    if type(obj.Input) == "function" then obj.Input(keyStr) end
                    if type(obj) == "function" then obj(keyStr) end
                end)
                return true
            end
        end
    end

    if method == "VirtualInputManager" then
        local ok, vim = pcall(function() return game:GetService("VirtualInputManager") end)
        if ok and vim and vim.SendKeyEvent then
            local keyEnum = nil
            pcall(function() keyEnum = Enum.KeyCode[string.upper(keyStr)] end)
            if keyEnum then
                pcall(function()
                    vim:SendKeyEvent(true, keyEnum, false, game)
                    safeWait(0.05)
                    vim:SendKeyEvent(false, keyEnum, false, game)
                end)
                return true
            end
        end
    end

    if method == "VirtualUser" then
        pcall(function()
            local vu = game:GetService("VirtualUser")
            vu:CaptureController()
        end)
        return false
    end

    return false
end

-- ---------- helpers de câmera ----------
local Camera = workspace.CurrentCamera
local savedCamera = nil
local function saveCameraState()
    if savedCamera then return end
    pcall(function()
        savedCamera = {
            CameraType = Camera.CameraType,
            CameraSubject = Camera.CameraSubject,
            CFrame = Camera.CFrame
        }
    end)
end
local function restoreCameraState()
    if not savedCamera then return end
    pcall(function()
        Camera.CameraType = savedCamera.CameraType or Enum.CameraType.Custom
        Camera.CameraSubject = savedCamera.CameraSubject or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid"))
        if savedCamera.CFrame then Camera.CFrame = savedCamera.CFrame end
    end)
    savedCamera = nil
end

-- ---------- utilitários ----------
local function getHrPPosFromInstance(inst)
    if not inst then return nil end
    if inst:IsA("Player") then
        if inst.Character and inst.Character:FindFirstChild("HumanoidRootPart") then
            return inst.Character.HumanoidRootPart.Position
        end
    elseif inst:IsA("Model") then
        local hrp = inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChild("Torso") or inst:FindFirstChild("UpperTorso")
        if hrp then return hrp.Position end
    elseif inst:IsA("BasePart") then
        return inst.Position
    end
    return nil
end

local function distToLocal(pos)
    if not pos or not LocalPlayer.Character then return math.huge end
    local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return math.huge end
    return (hrp.Position - pos).Magnitude
end

-- ---------- lógica do Aim Bot (killer) ----------
local aimEnabled = false
local aimRadius = 90
local aimConn = nil

local function findClosestKiller()
    local best, bestD = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            local name = tostring(plr.Name):lower()
            local dName = tostring(plr.DisplayName or ""):lower()
            if name:find("killer") or dName:find("killer") then
                local pos = plr.Character.HumanoidRootPart.Position
                local d = distToLocal(pos)
                if d <= aimRadius and d < bestD then best, bestD = plr, d end
            end
        end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            local n = tostring(obj.Name):lower()
            if n:find("killer") then
                local pos = obj.Position
                local d = distToLocal(pos)
                if d <= aimRadius and d < bestD then best, bestD = obj, d end
            end
        end
    end
    return best
end

local function startAim()
    if aimConn then return end
    aimConn = RunService.RenderStepped:Connect(function(dt)
        if not aimEnabled then return end
        local tgt = findClosestKiller()
        if tgt then
            saveCameraState()
            local tgtPos = getHrPPosFromInstance(tgt)
            if tgtPos then
                local cam = workspace.CurrentCamera
                local camPos = cam.CFrame.Position
                local lookAt = tgtPos + Vector3.new(0, 1.5, 0)
                local desired = CFrame.new(camPos, lookAt)
                local alpha = math.clamp(5 * dt, 0, 1)
                cam.CFrame = cam.CFrame:Lerp(desired, alpha)
                pcall(function() cam.CameraType = Enum.CameraType.Scriptable end)
            end
        else
            restoreCameraState()
        end
    end)
end

local function stopAim()
    if aimConn then aimConn:Disconnect() aimConn = nil end
    restoreCameraState()
end

-- ---------- lógica Auto Block ----------
local autoEnabled = false
local autoRadius = 30
local knownDamagers = {}
local watched = false
local blockCooldown = 26
local lastBlock = 0

local function getLocalHumanoid()
    if LocalPlayer.Character then
        return LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    end
    return nil
end

local function watchPartForDamage(part)
    if not part or not part:IsA("BasePart") then return end
    if knownDamagers[part] then return end
    knownDamagers[part] = knownDamagers[part] or false

    local conn
    conn = part.Touched:Connect(function(hit)
        if not LocalPlayer.Character then return end
        if not hit or not hit:IsDescendantOf(LocalPlayer.Character) then return end
        local hum = getLocalHumanoid()
        if not hum then return end
        local before = hum.Health
        safeWait(0.12)
        local after = hum.Health
        if after < before then
            knownDamagers[part] = true
            print("[fiat_hub] Parte marcada como danosa:", part:GetFullName())
        end
    end)

    part.AncestryChanged:Connect(function(_, parent)
        if not parent then
            knownDamagers[part] = nil
            if conn then pcall(function() conn:Disconnect() end) end
        end
    end)
end

local function initDamageWatchers()
    if watched then return end
    watched = true
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") then
            pcall(watchPartForDamage, d)
        end
    end
    workspace.DescendantAdded:Connect(function(desc)
        if desc:IsA("BasePart") then
            pcall(watchPartForDamage, desc)
        end
    end)
end

local autoConn = nil
local function startAuto()
    if autoConn then return end
    initDamageWatchers()
    autoConn = RunService.Heartbeat:Connect(function()
        if not autoEnabled then return end
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
        if time() - lastBlock < blockCooldown then return end
        for part, flagged in pairs(knownDamagers) do
            if flagged and part and part.Parent then
                local pos = part.Position
                local d = distToLocal(pos)
                if d <= autoRadius then
                    lastBlock = time()
                    print("[fiat_hub] Auto block triggered. Pressing Q then R")
                    pressKey("q")
                    safeWait(0.08)
                    pressKey("r")
                    break
                end
            else
                knownDamagers[part] = nil
            end
        end
    end)
end

local function stopAuto()
    if autoConn then autoConn:Disconnect() autoConn = nil end
end

-- ---------- ESP ----------
local espEnabled = false
local espStore = {}

local function createESP(plr)
    if not plr or plr == LocalPlayer then return end
    if not plr.Character then return end
    local head = plr.Character:FindFirstChild("Head")
    if not head then return end

    local box = Instance.new("SelectionBox")
    box.Name = "FiatESPBox"
    box.Adornee = head
    box.Parent = head
    box.LineThickness = 0.02
    box.Color3 = Color3.new(1,1,1)

    local gui = Instance.new("BillboardGui")
    gui.Name = "FiatESPName"
    gui.Adornee = head
    gui.Size = UDim2.new(0,120,0,30)
    gui.AlwaysOnTop = true
    gui.StudsOffset = Vector3.new(0,1.5,0)
    gui.Parent = head

    local label = Instance.new("TextLabel", gui)
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1,1)
    label.Text = plr.Name
    label.TextColor3 = Color3.new(1,1,1)
    label.TextScaled = true
    label.Font = Enum.Font.SourceSansBold

    espStore[plr] = {box = box, gui = gui}
end

local function removeESP(plr)
    local t = espStore[plr]
    if not t then return end
    pcall(function() if t.box and t.box.Parent then t.box:Destroy() end end)
    pcall(function() if t.gui and t.gui.Parent then t.gui:Destroy() end end)
    espStore[plr] = nil
end

local function enableESP()
    espEnabled = true
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            if plr.Character and plr.Character:FindFirstChild("Head") then
                createESP(plr)
            end
            plr.CharacterAdded:Connect(function()
                safeWait(0.08)
                if espEnabled then createESP(plr) end
            end)
        end
    end
    Players.PlayerAdded:Connect(function(plr)
        plr.CharacterAdded:Connect(function()
            safeWait(0.08)
            if espEnabled and plr ~= LocalPlayer then createESP(plr) end
        end)
    end)
    Players.PlayerRemoving:Connect(function(plr) removeESP(plr) end)
end

local function disableESP()
    espEnabled = false
    for plr, _ in pairs(espStore) do removeESP(plr) end
end

-- ---------- UI (Fluent) com fallback ----------
local Window = nil
local Options = nil

if Fluent then
    local okW, winOrErr = pcall(function()
        return Fluent:CreateWindow({
            Title = "fiat hub",
            SubTitle = "by fiat (Delta)",
            TabWidth = 160,
            Size = UDim2.fromOffset(640,480),
            Acrylic = true,
            Theme = "Dark",
            MinimizeKey = Enum.KeyCode.LeftControl
        })
    end)
    if okW and winOrErr then
        Window = winOrErr
        pcall(function() Options = Fluent.Options end)
    else
        warn("[fiat_hub] Fluent criou janela? não. Erro:", winOrErr)
        Window = nil
    end
end

-- Se Fluent não criou janela, cria fallback ScreenGui com botões básicos
local function createFallbackUI()
    local fallbackGui = Instance.new("ScreenGui")
    fallbackGui.Name = "FiatHubFallback"
    -- prefer CoreGui, senão PlayerGui
    local parentOK = pcall(function() fallbackGui.Parent = CoreGui end)
    if not parentOK or not fallbackGui.Parent then
        pcall(function() fallbackGui.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") end)
    end

    local frame = Instance.new("Frame", fallbackGui)
    frame.Size = UDim2.new(0,360,0,160)
    frame.Position = UDim2.new(0.5,-180,0.08,0)
    frame.BackgroundColor3 = Color3.fromRGB(28,28,28)
    frame.BorderSizePixel = 0
    frame.AnchorPoint = Vector2.new(0,0)

    local title = Instance.new("TextLabel", frame)
    title.Size = UDim2.new(1,0,0,28)
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0,0,0,0)
    title.Text = "fiat hub (fallback)"
    title.TextColor3 = Color3.new(1,1,1)
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 18

    local function makeButton(name, y, text, onClick)
        local btn = Instance.new("TextButton", frame)
        btn.Size = UDim2.new(0,160,0,36)
        btn.Position = UDim2.new(0,12,y,0)
        btn.Text = text
        btn.Name = name
        btn.BackgroundColor3 = Color3.fromRGB(45,45,45)
        btn.TextColor3 = Color3.new(1,1,1)
        btn.Font = Enum.Font.SourceSans
        btn.TextSize = 16
        btn.BorderSizePixel = 0
        btn.MouseButton1Click:Connect(function()
            pcall(onClick, btn)
        end)
        return btn
    end

    local aimBtn = makeButton("AimBtn", 36, "Aim: OFF", function(btn)
        aimEnabled = not aimEnabled
        if aimEnabled then
            btn.Text = "Aim: ON"
            startAim()
        else
            btn.Text = "Aim: OFF"
            stopAim()
        end
    end)

    local autoBtn = makeButton("AutoBtn", 84, "AutoBlock: OFF", function(btn)
        autoEnabled = not autoEnabled
        if autoEnabled then
            btn.Text = "AutoBlock: ON"
            startAuto()
        else
            btn.Text = "AutoBlock: OFF"
            stopAuto()
        end
    end)

    local espBtn = makeButton("ESPBtn", 132, "ESP: OFF", function(btn)
        espEnabled = not espEnabled
        if espEnabled then
            btn.Text = "ESP: ON"
            enableESP()
        else
            btn.Text = "ESP: OFF"
            disableESP()
        end
    end)

    -- label de instrução
    local info = Instance.new("TextLabel", frame)
    info.Size = UDim2.new(1,-24,0,40)
    info.Position = UDim2.new(0,12,0.5,0)
    info.BackgroundTransparency = 1
    info.TextWrapped = true
    info.Text = "Fallback UI ativa. Fluent não foi carregado ou não criou janela. Use estes botões enquanto investiga o executor (veja Output)."
    info.TextColor3 = Color3.fromRGB(180,180,180)
    info.Font = Enum.Font.SourceSans
    info.TextSize = 14
end

-- Se Window existiu: cria tabs e toggles usando Fluent (protegido)
if Window then
    local Tabs = {
        Combat = Window:AddTab({ Title = "Combat", Icon = "sword" }),
        Main = Window:AddTab({ Title = "Main", Icon = "" }),
        Settings = Window:AddTab({ Title = "Configurações", Icon = "settings" })
    }

    -- proteção caso API de Fluent seja diferente; usamos pcall por segurança
    pcall(function()
        local AimToggle = Tabs.Combat:AddToggle("AimBotKiller", { Title = "aim bot killer", Default = false })
        AimToggle:OnChanged(function()
            aimEnabled = AimToggle.Value
            if aimEnabled then startAim() else stopAim() end
        end)
    end)

    pcall(function()
        local AutoToggle = Tabs.Combat:AddToggle("AutoBlock", { Title = "auto block 🛡️⚠️", Default = false })
        AutoToggle:OnChanged(function()
            autoEnabled = AutoToggle.Value
            if autoEnabled then startAuto() else stopAuto() end
        end)
    end)

    pcall(function()
        local ESPToggle = Tabs.Combat:AddToggle("ESPPlayers", { Title = "ESP", Default = false })
        ESPToggle:OnChanged(function()
            if ESPToggle.Value then enableESP() else disableESP() end
        end)
    end)

    -- Addons config (se existirem)
    if SaveManager and InterfaceManager then
        pcall(function()
            SaveManager:SetLibrary(Fluent)
            SaveManager:IgnoreThemeSettings()
            SaveManager:SetFolder("FiatHubConfigs/specific-game")
            InterfaceManager:SetLibrary(Fluent)
            InterfaceManager:SetFolder("FiatHubConfigs")
            InterfaceManager:BuildInterfaceSection(Tabs.Settings)
            SaveManager:BuildConfigSection(Tabs.Settings)
        end)
    end

    pcall(function() Window:SelectTab(1) end)
    pcall(function() Fluent:Notify({ Title = "fiat hub", Content = "Carregado para executor Delta. Se você não ver a UI, verifique se o executor permite GUIs no CoreGui.", Duration = 6 }) end)
else
    -- cria fallback se Fluent não estiver presente/funcional
    createFallbackUI()
    -- notifica via StarterGui (se disponível)
    pcall(function()
        StarterGui:SetCor
