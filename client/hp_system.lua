---@diagnostic disable: trailing-space, undefined-global
local currentHP = 100
local maxHP = 100
local isDead = false
local lastDamageTime = 0
local isRegenerating = false

local function UpdateHPDisplay()
    local displayHP = isDead and 0 or currentHP
    local hpPercent = (displayHP / maxHP) * 100
    LocalPlayer.state:set('magicHp', math.floor(hpPercent), true)

    SendNUIMessage({
        action = 'updateMagicHp',
        value = math.floor(hpPercent)
    })

    if hpPercent <= 0 and not isDead then
        local ped = PlayerPedId()
        if ped and ped ~= 0 then
            SetEntityHealth(ped, 0)
        end
        SendNUIMessage({ action = 'showMagicDeathOverlay', visible = true })
        SendNUIMessage({ action = 'showMagicDeathText', visible = true })
    end
end

local function ApplyRespawnState(hp, max)
    currentHP = hp
    maxHP = max
    isDead = false
    lastDamageTime = 0
    isRegenerating = false

    SendNUIMessage({
        action = 'setMagicHpRegen',
        regenerating = false
    })
    SendNUIMessage({ action = 'showMagicDeathOverlay', visible = false })
    SendNUIMessage({ action = 'showMagicDeathText', visible = false })
    SendNUIMessage({ action = 'hideMagicDamageOverlay' })

    UpdateHPDisplay()
end

local REGEN_CONFIG = {
    DELAY_AFTER_DAMAGE = 10000,
    CHECK_INTERVAL = 500,
    RATE = 1,
    TICK_INTERVAL = 5000
}

local function CheckRegeneration()
    if isDead or currentHP >= maxHP then
        if isRegenerating then
            isRegenerating = false
            SendNUIMessage({
                action = 'setMagicHpRegen',
                regenerating = false
            })
        end
        return
    end
    
    local timeSinceDamage = GetGameTimer() - lastDamageTime
    local shouldRegen = timeSinceDamage >= REGEN_CONFIG.DELAY_AFTER_DAMAGE
    
    if shouldRegen and not isRegenerating then
        isRegenerating = true
        SendNUIMessage({
            action = 'setMagicHpRegen',
            regenerating = true
        })
    elseif not shouldRegen and isRegenerating then
        isRegenerating = false
        SendNUIMessage({
            action = 'setMagicHpRegen',
            regenerating = false
        })
    end
end

RegisterNetEvent('th_power:updateHP', function(hp, max)
    local oldHP = currentHP
    currentHP = hp
    maxHP = max
    
    if isDead and currentHP > 0 then
        local ped = PlayerPedId()

        if ped ~= 0 and (IsEntityDead(ped) or IsPedFatallyInjured(ped)) or ESX.PlayerData.dead then
            CreateThread(function()
                while true do
                    ped = PlayerPedId()
                    if ped ~= 0 and not IsEntityDead(ped) and not IsPedFatallyInjured(ped) and not ESX.PlayerData.dead then
                        break
                    end
                    Wait(250)
                end
                ApplyRespawnState(currentHP, maxHP)
            end)
        else
            ApplyRespawnState(currentHP, maxHP)
        end
        return
    end
    
    if currentHP < oldHP then
        lastDamageTime = GetGameTimer()
        isRegenerating = false
        
        local damageAmount = oldHP - currentHP
        SendNUIMessage({
            action = 'setMagicHpRegen',
            regenerating = false
        })
        SendNUIMessage({
            action = 'magicHpDamage',
            damage = damageAmount
        })
    end
    
    UpdateHPDisplay()
    
    if currentHP <= 0 and not isDead then
        isDead = true
        isRegenerating = false
        SendNUIMessage({
            action = 'setMagicHpRegen',
            regenerating = false
        })

        local ped = PlayerPedId()
        if ped and ped ~= 0 then
            SetEntityHealth(ped, 0)
        end

        SendNUIMessage({ action = 'showMagicDeathOverlay', visible = true })
        SendNUIMessage({ action = 'showMagicDeathText', visible = true })
    end
end)

RegisterNetEvent('th_power:respawn', function(hp, max)
    local ped = PlayerPedId()

    if ped ~= 0 and (IsEntityDead(ped) or IsPedFatallyInjured(ped)) or ESX.PlayerData.dead then
        CreateThread(function()
            while true do
                ped = PlayerPedId()
                if ped ~= 0 and not IsEntityDead(ped) and not IsPedFatallyInjured(ped) and not ESX.PlayerData.dead then
                    break
                end
                Wait(250)
            end
            ApplyRespawnState(hp, max)
        end)
    else
        ApplyRespawnState(hp, max)
    end
end)

CreateThread(function()
    Wait(1000)
    UpdateHPDisplay()
    
    while true do
        Wait(REGEN_CONFIG.CHECK_INTERVAL)
        CheckRegeneration()
    end
end)

CreateThread(function()
    while true do
        Wait(REGEN_CONFIG.TICK_INTERVAL)
        
        if not isDead and currentHP < maxHP and isRegenerating then
            currentHP = math.min(maxHP, currentHP + REGEN_CONFIG.RATE)
            UpdateHPDisplay()
        end
    end
end)
