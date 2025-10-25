-- FIAT HUB: Blox Fruits (versão revisada)
-- Atenção: ajustar asset ids e URLs conforme necessário

-- Carrega UI lib (corrigido para apontar ao raw .lua)
local success, redzlib = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/tbao143/Library-ui/main/Redzhubui.lua", true))()
end)
if not success or not redzlib then
    warn("Falha ao carregar RedzLib. Verifique a URL ou se o executor permite HttpGet.")
    return
end

-- Cria janela
local Window = redzlib:MakeWindow({
    Title = "FIAT HUB: Blox Fruits BETA⚠️",
    SubTitle = "by FIAT",
    SaveFolder = "testando | redz lib v5"
})

-- Botão minimizar (exemplo)
Window:AddMinimizeButton({
    Button = { Image = "rbxassetid://71014873973869", BackgroundTransparency = 0 },
    Corner = { CornerRadius = UDim.new(35, 1) },
})

-- Aba Settings (mantive nome)
local SettingsTab = Window:MakeTab({"Settings"})

-- Aba Farm
local FarmTab = Window:MakeTab({"Farm"})
FarmTab.TabIcon = "rbxassetid://1234567890" -- substituir por asset válido

-- Toggles da aba Farm (placeholders se quiser implementar depois)
local FarmToggle = FarmTab:AddToggle({ Name = "Farm Level Beta ⚠️", Description = "", Default = false })
FarmToggle:Callback(function(value)
    -- placeholder: ativar rotina de farm quando quiser
end)

local KillAuraToggle = FarmTab:AddToggle({ Name = "Kill Aura ⚠️", Default = false })
KillAuraToggle:Callback(function(value)
    -- placeholder
end)

local FastAttackToggle = FarmTab:AddToggle({ Name = "Fast Attack ⚠️", Default = false })
FastAttackToggle:Callback(function(value)
    -- placeholder
end)

local AttackSpeedDropdown = FarmTab:AddDropdown({
    Name = "Fast Attack Speed",
    Description = "",
    Options = {"0.1⚠️", "0.2⚠️", "0.6⚠️", "2✅"},
    Default = "0.1⚠️",
    Callback = function(val)
        -- usar val se implementar o fast attack
    end
})

-- Aba Discord
local DiscordTab = Window:MakeTab({"Discord"})
DiscordTab.TabIcon = "rbxassetid://18751483361"

DiscordTab:AddButton({
    Name = "Copiar link Discord",
    Callback = function()
        local ok, err = pcall(function() setclipboard("https://discord.gg/rWx9Y9xD") end)
        if ok then
            Window:Notify({ Title = "Sucesso!", Text = "link na área de transferência :D" })
        else
            Window:Notify({ Title = "Erro", Text = "Não foi possível copiar: "..tostring(err) })
        end
    end
})

-- Aba OP
local OPTab = Window:MakeTab({"OP"})
OPTab.TabIcon = "rbxassetid://9876543210"

local SpinFrutaToggle = OPTab:AddToggle({ Name = "Spin Fruta Anti Ban Beta ⚠️", Default = false })
SpinFrutaToggle:Callback(function(value)
    -- placeholder
end)

-- Anti Lag: tenta desativar efeitos que tenham propriedade Enabled
local AntiLagToggle = OPTab:AddToggle({ Name = "Anti Lag", Default = false })
AntiLagToggle:Callback(function(value)
    local Lighting = game:GetService("Lighting")
    for _, obj in pairs(Lighting:GetChildren()) do
        -- só mexe se a propriedade Enabled existir
        if obj and obj:IsA("Instance") then
            if value then
                pcall(function()
                    if obj.Enabled ~= nil then obj.Enabled = false end
                end)
            else
                pcall(function()
                    if obj.Enabled ~= nil then obj.Enabled = true end
                end)
            end
        end
    end
end)

-- Speed Bomba (corrigido para não acumular conexões)
local SpeedBombaToggle = OPTab:AddToggle({ Name = "Speed Bomba ⚠️", Default = false })
local _speedConn = nil
local originalWalkSpeed = nil

SpeedBombaToggle:Callback(function(value)
    local player = game:GetService("Players").LocalPlayer
    if not player then return end
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    if value then
        -- salva valor original uma vez
        if originalWalkSpeed == nil then
            originalWalkSpeed = humanoid.WalkSpeed
        end
        humanoid.WalkSpeed = 200
        -- conecta somente uma vez
        if not _speedConn then
            _speedConn = humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
                -- mantém enquanto estiver se movendo
                if humanoid.MoveDirection and humanoid.MoveDirection.Magnitude > 0 then
                    humanoid.WalkSpeed = 200
                end
            end)
        end
    else
        -- restaura e desconecta
        if originalWalkSpeed then
            humanoid.WalkSpeed = originalWalkSpeed
        else
            humanoid.WalkSpeed = 16
        end
        if _speedConn then
            _speedConn:Disconnect()
            _speedConn = nil
        end
    end
end)

-- Fim do script
