-- fiat_hub.lua
-- "Fiat Hub" — UI Fluent modificado com aba Combat (aim bot, auto block, ESP)
-- Idioma: Português (comentários)
-- Observações: pressiona teclas via syn.keypress ou VirtualInputManager quando disponível (dependendo do executor).
-- Use em ambiente compatível com exploits (Synapse/KRNL/etc.) se quiser funcionalidade de simular teclas.

-- Serviços
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer

-- Carrega Fluent e Addons (mantive SaveManager/InterfaceManager)
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- Janela principal renomeada para "fiat hub"
local Window = Fluent:CreateWindow({
    Title = "fiat hub",
    SubTitle = "by fiat",
    TabWidth = 160,
    Size = UDim2.fromOffset(640, 480),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

-- Abas: Combat primeiro
local Tabs = {
    Combat = Window:AddTab({ Title = "Combat", Icon = "sword" }),
    Main = Window:AddTab({ Title = "Main", Icon = "" }),
    Settings = Window:AddTab({ Title = "Configurações", Icon = "settings" })
}

local Options = Fluent.Options

-- ======================================================================
-- Utilitários gerais
-- ======================================================================

-- Safe wait helper
local function safeWait(t)
    t = t or 0.03
    if RunService:IsStudio() then wait(t) else task.wait(t) end
end

-- Pressionar tecla: tenta várias estratégias (syn, VirtualInputManager). pcall para segurança.
local function pressKey(key)
    -- key should be string like "q", "r", or Enum.KeyCode names like "Q"
    pcall(function()
        -- syn (Synapse) API
        if syn and syn.keypress then
            syn.keypress(key)
            return
        end

        -- KRNL has a different function name (not standardized), but many exploit envs expose VirtualInputManager
        local ok, vim = pcall(function()
            return game:GetService("VirtualInputManager")
        end)
        if ok and vim and vim.SendKeyEvent then
            -- SendKeyEvent(isDown, keyCode, isRepeat, process)
            -- key must be Enum.KeyCode
            local keyEnum = nil
            -- try to convert string to Enum.KeyCode
            pcall(function()
                keyEnum = Enum.KeyCode[string.upper(key)]
            end)
            if keyEnum then
                vim:SendKeyEvent(true, keyEnum, false, game)
                safeWait(0.05)
                vim:SendKeyEvent(false, keyEnum, false, game)
                return
            end
        end

        -- fallback: VirtualUser (não envia teclas, mas mantemos pcall)
        local vu = game:GetService("VirtualUser")
        if vu and vu.Button1Down then
            -- não há método confiável para teclas, então nada aqui
            -- deixamos pcall para evitar erro
        end
    end)
end

-- Guarda/restaura estado de câmera
local Camera = workspace.CurrentCamera
local SavedCameraState = {}
local function saveCameraState()
    if not SavedCameraState.saved then
        SavedCameraState = {
            saved = true,
            CameraType = Camera.CameraType,
            CameraSubject = Camera.CameraSubject,
            CameraCFrame = Camera.CFrame
        }
    end
end
local function restoreCameraState()
    if SavedCameraState.saved then
        pcall(function()
            Camera.CameraType = SavedCameraState.CameraType or Enum.CameraType.Custom
            Camera.CameraSubject = SavedCameraState.CameraSubject or LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if SavedCameraState.CameraCFrame then
                Camera.CFrame = SavedCameraState.CameraCFrame
            end
        end)
        SavedCameraState.saved = false
    end
end

-- Obtém posição alvo de um objeto: aceita Player (Model) ou Part (BasePart)
local function getTargetPosition(target)
    if typeof(target) == "Instance" then
        if target:IsA("Player") or target:IsA("Model") then
            local char = target.Character or (target:IsA("Player") and target.Character)
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
                if hrp then return hrp.Position end
            end
        elseif target:IsA("BasePart") then
            return target.Position
        end
    elseif typeof(target) == "table" then
        -- in case we pass info table
        return target.Position
    end
    return nil
end

-- Distância ao jogador
local function distanceToPlayer(pos)
    local char = LocalPlayer.Character
    if not char then return math.huge end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return math.huge end
    return (hrp.Position - pos).Magnitude
end

-- ======================================================================
-- AIM BOT KILLER (toggle)
-- - Aceita Players e Parts com nome "killer" (ou exatamente "killer")
-- - Segue suavemente com a câmera (lerp)
-- - Alcance: 90 studs; ao sair, restaura câmera; se voltar, segue novamente
-- ======================================================================

local aimEnabled = false
local aimRadius = 90
local aimTarget = nil

local function findClosestKiller()
    local bestTarget = nil
    local bestDist = math.huge

    -- Check players
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            local nameMatch = tostring(plr.Name):lower():find("killer") or tostring(plr.DisplayName):lower():find("killer")
            if nameMatch then
                local pos = plr.Character.HumanoidRootPart.Position
                local d = distanceToPlayer(pos)
                if d <= aimRadius and d < bestDist then
                    bestDist = d
                    bestTarget = plr
                end
            end
        end
    end

    -- Check parts in workspace with name "killer" (case-insensitive)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            if tostring(obj.Name):lower():find("^killer$") or tostring(obj.Name):lower():find("killer") then
                local pos = obj.Position
                local d = distanceToPlayer(pos)
                if d <= aimRadius and d < bestDist then
                    bestDist = d
                    bestTarget = obj
                end
            end
        end
    end

    return bestTarget
end

-- Loop para atualizar câmera suavemente
local aimConnection = nil
local function startAimLoop()
    if aimConnection then return end
    aimConnection = RunService.RenderStepped:Connect(function(dt)
        if not aimEnabled then return end

        -- encontra alvo
        local target = findClosestKiller()
        if target then
            -- found target
            aimTarget = target
            saveCameraState()
            -- compute target position (slightly above center)
            local tgtPos = getTargetPosition(target)
            if tgtPos then
                local cam = workspace.CurrentCamera
                -- keep camera position, only change look at (we smoothly rotate to look at target)
                -- compute desired CFrame looking at target
                local camPos = cam.CFrame.Position
                local lookAt = tgtPos + Vector3.new(0, 1.5, 0)
                local desired = CFrame.new(camPos, lookAt)
                -- smoothly interpolate
                local alpha = math.clamp(5 * dt, 0, 1) -- smoothing speed
                cam.CFrame = cam.CFrame:Lerp(desired, alpha)
                -- ensure camera remains in Scriptable mode to control it
                pcall(function() cam.CameraType = Enum.CameraType.Scriptable end)
            end
        else
            -- no target in radius -> if had previously saved camera, restore
            aimTarget = nil
            restoreCameraState()
        end
    end)
end

local function stopAimLoop()
    if aimConnection then
        aimConnection:Disconnect()
        aimConnection = nil
    end
    aimTarget = nil
    restoreCameraState()
end

-- ======================================================================
-- AUTO BLOCK 🛡️⚠️ (toggle)
-- - Detecta "partes que causam dano" ao observar contato com o personagem e queda de vida
-- - Quando uma parte que causou dano antes estiver a <= 30 studs, pressing Q then R, espera 26s para repetir
-- - Só age sobre parts que já provaram causar dano (registro por experiência prévia)
-- ======================================================================

local autoBlockEnabled = false
local autoBlockRadius = 30
local knownDamagers = {} -- set of Instance -> true
local damagersDebounce = {} -- to avoid multiple registers
local blockCooldown = 26 -- segundos
local lastBlockTime = 0

-- Atualiza referência de humanoid/local char
local function getLocalHumanoid()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

-- Listen Touched on parts to detect if they deal damage
local function watchPartForDamage(part)
    if not part or not part:IsA("BasePart") then return end
    if damagersDebounce[part] then return end
    damagersDebounce[part] = true

    -- connect Touched
    local conn
    conn = part.Touched:Connect(function(hit)
        local humanoid = getLocalHumanoid()
        if not humanoid then return end
        local h, hrp = humanoid, getLocalHumanoid() and getLocalHumanoid() -- get local humanoid again
        if not LocalPlayer.Character then return end
        -- only consider touches that hit player's character
        if not hit or not hit:IsDescendantOf(LocalPlayer.Character) then return end

        -- record health before and after short delay
        local before = nil
        if LocalPlayer.Character then
            local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then before = hum.Health end
        end
        safeWait(0.12)
        if LocalPlayer.Character then
            local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                local after = hum.Health
                if before and after and after < before then
                    knownDamagers[part] = true
                    -- keep knownDamagers pruned later by checking .Parent
                end
            end
        end
    end)

    -- cleanup when part removed
    part.AncestryChanged:Connect(function(_, parent)
        if not parent then
            damagersDebounce[part] = nil
            knownDamagers[part] = nil
            if conn then pcall(function() conn:Disconnect() end) end
        end
    end)
end

-- Attach watchers to all current parts and to new ones
local watchedInit = false
local function initDamageWatchers()
    if watchedInit then return end
    watchedInit = true

    for _, part in ipairs(workspace:GetDescendants()) do
        if part:IsA("BasePart") then
            watchPartForDamage(part)
        end
    end

    workspace.DescendantAdded:Connect(function(desc)
        if desc:IsA("BasePart") then
            watchPartForDamage(desc)
        end
    end)
end

-- Loop responsible to auto-block when known damager is nearby
local autoBlockLoop = nil
local function startAutoBlockLoop()
    if autoBlockLoop then return end
    initDamageWatchers()
    autoBlockLoop = RunService.Heartbeat:Connect(function()
        if not autoBlockEnabled then return end
        -- ensure char exists
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
        local now = time()
        if now - lastBlockTime < blockCooldown then return end

        for part, _ in pairs(knownDamagers) do
            if part and part.Parent then
                local pos = nil
                if part:IsA("BasePart") then pos = part.Position end
                if pos then
                    local d = distanceToPlayer(pos)
                    if d <= autoBlockRadius then
                        -- Press Q then R
                        lastBlockTime = now
                        pressKey("q")
                        safeWait(0.08)
                        pressKey("r")
                        -- finished this cycle; wait loop will respect cooldown
                        break
                    end
                end
            else
                knownDamagers[part] = nil
            end
        end
    end)
end

local function stopAutoBlockLoop()
    if autoBlockLoop then
        autoBlockLoop:Disconnect()
        autoBlockLoop = nil
    end
end

-- ======================================================================
-- ESP (toggle)
-- - Adiciona contorno (SelectionBox) e nome (BillboardGui em branco) acima da cabeça
-- - Aplica a todos os players exceto LocalPlayer
-- ======================================================================

local espEnabled = false
local espObjects = {} -- player -> {selectionBox = Instance, billboard = Instance, connections = {}}

local function createESPForCharacter(plr)
    if not plr or not plr.Character then return end
    local char = plr.Character
    local head = char:FindFirstChild("Head")
    if not head then return end

    -- SelectionBox
    local box = Instance.new("SelectionBox")
    box.Name = "FiatESPBox"
    box.Adornee = head
    box.Parent = head
    box.LineThickness = 0.02
    box.SurfaceTransparency = 1
    box.Color3 = Color3.new(1, 1, 1) -- branco

    -- BillboardGui with name
    local bg = Instance.new("BillboardGui")
    bg.Name = "FiatESPName"
    bg.Adornee = head
    bg.Size = UDim2.new(0, 120, 0, 30)
    bg.AlwaysOnTop = true
    bg.StudsOffset = Vector3.new(0, 1.5, 0)
    bg.Parent = head

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Text = plr.Name
    label.TextColor3 = Color3.new(1, 1, 1) -- branco
    label.TextStrokeTransparency = 1
    label.TextScaled = true
    label.Font = Enum.Font.SourceSansBold
    label.Parent = bg

    -- store
    espObjects[plr] = espObjects[plr] or {}
    espObjects[plr].selectionBox = box
    espObjects[plr].billboard = bg
end

local function removeESPForPlayer(plr)
    local data = espObjects[plr]
    if not data then return end
    if data.selectionBox and data.selectionBox.Parent then pcall(function() data.selectionBox:Destroy() end) end
    if data.billboard and data.billboard.Parent then pcall(function() data.billboard:Destroy() end) end
    espObjects[plr] = nil
end

local function enableESP()
    espEnabled = true
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            -- wait for character and head
            plr.CharacterAdded:Connect(function(char)
                safeWait(0.1)
                if espEnabled then createESPForCharacter(plr) end
            end)
            if plr.Character and plr.Character:FindFirstChild("Head") then
                createESPForCharacter(plr)
            end
        end
    end

    -- listen to new players
    Players.PlayerAdded:Connect(function(plr)
        plr.CharacterAdded:Connect(function()
            safeWait(0.1)
            if espEnabled and plr ~= LocalPlayer then createESPForCharacter(plr) end
        end)
    end)

    -- cleanup on leave
    Players.PlayerRemoving:Connect(function(plr)
        removeESPForPlayer(plr)
    end)
end

local function disableESP()
    espEnabled = false
    for plr, _ in pairs(espObjects) do
        removeESPForPlayer(plr)
    end
end

-- ======================================================================
-- UI: adiciona controles na aba Combat conforme solicitado
-- ======================================================================

-- Aim bot toggle
local AimToggle = Tabs.Combat:AddToggle("AimBotKiller", { Title = "aim bot killer", Default = false })
AimToggle:OnChanged(function()
    aimEnabled = AimToggle.Value
    if aimEnabled then
        startAimLoop()
    else
        stopAimLoop()
    end
end)
Options.AimBotKiller:SetValue(false)

-- Auto block toggle
local AutoBlockToggle = Tabs.Combat:AddToggle("AutoBlock", { Title = "auto block 🛡️⚠️", Default = false })
AutoBlockToggle:OnChanged(function()
    autoBlockEnabled = AutoBlockToggle.Value
    if autoBlockEnabled then
        startAutoBlockLoop()
    else
        stopAutoBlockLoop()
    end
end)
Options.AutoBlock:SetValue(false)

-- ESP toggle
local ESPToggle = Tabs.Combat:AddToggle("ESPPlayers", { Title = "ESP", Default = false })
ESPToggle:OnChanged(function()
    if ESPToggle.Value then
        enableESP()
    else
        disableESP()
    end
end)
Options.ESPPlayers:SetValue(false)

-- ======================================================================
-- Inicialização: configura Addons, load autoload, selecionar primeira aba
-- ======================================================================

-- Addons
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("FiatHubConfigs")
SaveManager:SetFolder("FiatHubConfigs/specific-game")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
Fluent:Notify({
    Title = "fiat hub",
    Content = "Script carregado. Aba Combat disponível com aim, auto block e ESP.",
    Duration = 6
})

-- Start watchers to detect damaging parts
initDamageWatchers()

-- Attempt to load autoload config (pcall para não quebrar)
pcall(function() SaveManager:LoadAutoloadConfig() end)

-- ======================================================================
-- Cleanup quando a biblioteca for descarregada
-- ======================================================================
task.spawn(function()
    while true do
        safeWait(1)
        if Fluent.Unloaded then
            -- desligar loops e remover ESP
            aimEnabled = false
            stopAimLoop()
            autoBlockEnabled = false
            stopAutoBlockLoop()
            disableESP()
            break
        end
    end
end)

-- ======================================================================
-- Comentários finais:
-- - Aim bot procura por players cujo nome/displayname contenha "killer" e por partes com nome que contenha "killer".
-- - Auto block registra partes que efetivamente causaram dano observando Touched + queda de vida, e depois reage quando tais partes estiverem a <= 30 studs.
-- - A simulação de teclas usa syn.keypress ou VirtualInputManager quando disponível. Alguns executores não permitem enviar teclas via scripts — se não funcionar, experimente um executor diferente ou me diga qual executor você usa para eu adaptar.
-- - Limitações: a detecção "parte causa dano" só marca um part como danoso depois que ele efetivamente causou dano ao jogador ao menos uma vez. Depois disso o sistema poderá reagir preventivamente dentro do raio.
-- - Posso ajustar parâmetros (raios, tempo de cooldown, suavidade da câmera) se quiser.
-- ======================================================================
