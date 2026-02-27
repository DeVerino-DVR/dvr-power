---@diagnostic disable: trailing-space, undefined-global, redefined-local
local GetGameTimer = GetGameTimer
local DoesEntityExist = DoesEntityExist
local GetEntityHealth = GetEntityHealth
local GetEntityMaxHealth = GetEntityMaxHealth
local SetEntityHealth = SetEntityHealth
local SendNUIMessage = SendNUIMessage
local GetResourceState = GetResourceState
local math_floor = math.floor
local LOCK_THRESHOLD = 0.5
local UNLOCK_THRESHOLD = 2.0

local HUD = {
    visible = false,
    initialized = false,
    nuiReady = false,
    currentSpells = {},
    activeSpell = nil,
    activeCooldowns = {},
    userToggled = false,
    needsLocked = false,
    stats = {
        health = 100,
        healthCurrent = 0,
        healthMax = 0,
        hunger = 100,
        thirst = 100,
        magicHp = 100,
        potion = 0
    },
    lastPlayerSpellsCount = 0,
    lastSelectedSpellId = nil
}

local hudReady = false
local STATUS_DEFAULT <const> = 1000000
local STATUS_REFRESH_INTERVAL <const> = 2000
local statusSync = {
    ready = false,
    lastRefresh = 0
}

local function clampPercent(value)
    if value == nil then
        return nil
    end

    local clamped = value
    if clamped < 0 then
        clamped = 0
    elseif clamped > 100 then
        clamped = 100
    elseif clamped > 0 and clamped < 0.5 then
        clamped = 0.5
    end

    return math_floor(clamped + 0.5)
end

local function calculatePercent(value, default)
    if not value or not default or default <= 0 then
        return 0
    end

    return math_floor((value / default) * 100)
end

local function getStatusPercent(entry)
    if not entry or type(entry) ~= 'table' then
        return nil
    end

    local defaultValue = entry.default or STATUS_DEFAULT
    return entry.percent or calculatePercent(entry.val, defaultValue)
end

local function updateSpellLockState()
    local hunger = HUD.stats.hunger
    local thirst = HUD.stats.thirst
    
    if hunger == nil or thirst == nil then
        return
    end
    
    hunger = clampPercent(hunger) or 100
    thirst = clampPercent(thirst) or 100
    
    local shouldLock
    if HUD.needsLocked then
        shouldLock = hunger < UNLOCK_THRESHOLD or thirst < UNLOCK_THRESHOLD
    else
        shouldLock = hunger <= LOCK_THRESHOLD or thirst <= LOCK_THRESHOLD
    end

    if HUD.needsLocked ~= shouldLock then
        HUD.needsLocked = shouldLock
    end
    
    if HUD.nuiReady then
        SendNUIMessage({
            action = 'toggleSpellLock',
            locked = HUD.needsLocked
        })
    end
end

RegisterNUICallback('hudReady', function(data, cb)
    HUD.nuiReady = true
    cb('ok')
    SendNUIMessage({
        action = 'toggleSpellLock',
        locked = HUD.needsLocked
    })
    updateSpellLockState()
end)

RegisterNUICallback('closeHUD', function(data, cb)
    HUD.visible = false
    SendNUIMessage({
        action = 'toggleHUD',
        visible = false
    })
    cb('ok')
end)

RegisterNUICallback('assignSpell', function(data, cb)
    if data and data.spellId and data.keyIndex then
        TriggerEvent('dvr_power:assignSpellToKey', data.spellId, data.keyIndex)
    end
    cb('ok')
end)

RegisterNUICallback('unassignSpell', function(data, cb)
    if data and (data.position or data.spellId) then
        TriggerEvent('dvr_power:removeSpellFromHUD', data.spellId, data.position)
    end
    cb('ok')
end)

RegisterNUICallback('closeSpellSelector', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('getSpellSets', function(data, cb)
    local sets = exports['dvr_power']:getSpellSets()
    cb(json.encode(sets or {}))
end)

RegisterNUICallback('switchSpellSet', function(data, cb)
    if data and data.setId then
        local success = exports['dvr_power']:switchSpellSet(tonumber(data.setId))
        cb(success and 'ok' or 'error')
    else
        cb('error')
    end
end)

RegisterNUICallback('renameSpellSet', function(data, cb)
    if data and data.setId and data.name then
        local success = exports['dvr_power']:renameSpellSet(tonumber(data.setId), data.name)
        cb(success and 'ok' or 'error')
    else
        cb('error')
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        SetNuiFocus(false, false)
    end
end)

local function canUseEsxStatus()
    return GetResourceState('esx_status') == 'started'
end

local function extractStatusPercent(entry)
    if not entry then
        return nil
    end

    return clampPercent(getStatusPercent(entry))
end

local function fetchStatusPercent(name)
    if not canUseEsxStatus() then
        return nil
    end

    local percent = nil

    TriggerEvent('esx_status:getStatus', name, function(status)
        percent = extractStatusPercent(status)
    end)

    return percent
end

local function refreshEsxStatuses(force)
    if not canUseEsxStatus() then
        return
    end

    if statusSync.ready and not force then
        return
    end

    local now = GetGameTimer()
    if not force and (now - statusSync.lastRefresh) < STATUS_REFRESH_INTERVAL then
        return
    end

    statusSync.lastRefresh = now

    local hunger = fetchStatusPercent('hunger')
    local thirst = fetchStatusPercent('thirst')

    if hunger or thirst then
        statusSync.ready = true
        HUD.UpdateStats(nil, hunger, thirst)
    end
end

local function handleStatusTick(status)
    if not status or type(status) ~= 'table' or not canUseEsxStatus() then
        return
    end

    local hunger, thirst

    for _, entry in pairs(status) do
        if entry.name == 'hunger' then
            hunger = extractStatusPercent(entry)
        elseif entry.name == 'thirst' then
            thirst = extractStatusPercent(entry)
        end
    end

    if hunger or thirst then
        statusSync.ready = true
        HUD.UpdateStats(nil, hunger, thirst)
    end
end

RegisterNetEvent('esx_status:onTick')
AddEventHandler('esx_status:onTick', handleStatusTick)

function HUD.UpdateStats(health, hunger, thirst, magicHp, potion, healthCurrent, healthMax)
    local previous = {
        health = HUD.stats.health,
        healthCurrent = HUD.stats.healthCurrent,
        healthMax = HUD.stats.healthMax,
        hunger = HUD.stats.hunger,
        thirst = HUD.stats.thirst,
        magicHp = HUD.stats.magicHp,
        potion = HUD.stats.potion
    }

    if health ~= nil then
        HUD.stats.health = clampPercent(health) or HUD.stats.health
    end
    if healthCurrent ~= nil then
        HUD.stats.healthCurrent = math_floor(tonumber(healthCurrent) or HUD.stats.healthCurrent or 0)
    end
    if healthMax ~= nil then
        HUD.stats.healthMax = math_floor(tonumber(healthMax) or HUD.stats.healthMax or 0)
    end
    if hunger ~= nil then
        HUD.stats.hunger = clampPercent(hunger) or HUD.stats.hunger
    end
    if thirst ~= nil then
        HUD.stats.thirst = clampPercent(thirst) or HUD.stats.thirst
    end
    if magicHp ~= nil then
        HUD.stats.magicHp = clampPercent(magicHp) or HUD.stats.magicHp
    end
    if potion ~= nil then
        HUD.stats.potion = clampPercent(potion) or HUD.stats.potion
    end

    updateSpellLockState()

    if not hudReady then 
        return 
    end

    if HUD.stats.health == previous.health
        and HUD.stats.healthCurrent == previous.healthCurrent
        and HUD.stats.healthMax == previous.healthMax
        and HUD.stats.hunger == previous.hunger
        and HUD.stats.thirst == previous.thirst
        and HUD.stats.magicHp == previous.magicHp
        and HUD.stats.potion == previous.potion then
        return
    end

    SendNUIMessage({
        action = 'updateBars',
        health = HUD.stats.health,
        healthCurrent = HUD.stats.healthCurrent,
        healthMax = HUD.stats.healthMax,
        hunger = HUD.stats.hunger,
        thirst = HUD.stats.thirst,
        magicHp = HUD.stats.magicHp,
        potion = HUD.stats.potion
    })
end

function HUD.SetSpells(spells)
    if not hudReady then 
        CreateThread(function()
            while not hudReady do Wait(100) end
            HUD.SetSpells(spells)
        end)
        return
    end

    if not spells or type(spells) ~= 'table' then
        HUD.currentSpells = {}
        return
    end
    
    HUD.currentSpells = spells
    
    for position, spell in pairs(spells) do
        if spell then   
            local payload = {
                id = spell.id or position,
                name = spell.name or 'Sort',
                icon = spell.icon or '✦',
                color = spell.color or spell.element or 'neutral',
                key = spell.key or ''
            }

            local level = tonumber(spell.level)
            local maxLevel = tonumber(spell.maxLevel or spell.max_level)
            if level and maxLevel and maxLevel > 0 then
                level = math_floor(level + 0.0001)
                maxLevel = math_floor(maxLevel + 0.0001)
                payload.level = level
                payload.maxLevel = maxLevel
                payload.levelRatio = math.min(1.0, math.max(0.0, level / maxLevel))
                payload.levelText = ('Lv %d/%d'):format(level, maxLevel)
            end
            
            SendNUIMessage({
                action = 'setSpell',
                position = position,
                spell = payload
            })
            Wait(50)
        end
    end
end

function HUD.SetActiveSpell(position)
    if not hudReady then 
        return 
    end
    
    HUD.activeSpell = position
    
    SendNUIMessage({
        action = 'setActiveSpell',
        id = position and ('spell-' .. position) or nil
    })
end

function HUD.StartCooldown(spellId, duration, position)
    if HUD.activeCooldowns[spellId] then
        return
    end
    
    local startTime = GetGameTimer()
    local endTime = startTime + (duration * 1000)
    
    if not position then
        local assignments = spellKeyAssignments or {}
        for sid, pos in pairs(assignments) do
            if sid == spellId then
                position = pos
                break
            end
        end
    end
    
    if not position then
        return
    end
    
    local hudId = 'spell-' .. position
    
    
    HUD.activeCooldowns[spellId] = true
    
    CreateThread(function()
        while GetGameTimer() < endTime and HUD.activeCooldowns[spellId] do
            if not spellCooldowns or not spellCooldowns[spellId] then
                break
            end
            
            local remaining = endTime - GetGameTimer()
            local percent = (remaining / (duration * 1000)) * 100
            
            
            SendNUIMessage({
                action = 'updateCooldown',
                id = hudId,
                percent = percent
            })
            
            Wait(50)
        end
        
        HUD.activeCooldowns[spellId] = nil
        
        SendNUIMessage({
            action = 'updateCooldown',
            id = hudId,
            percent = 0
        })
    end)
end

function HUD.StopCooldown(spellId, position)
    if not position then
        local assignments = spellKeyAssignments or {}
        for sid, pos in pairs(assignments) do
            if sid == spellId then
                position = pos
                break
            end
        end
    end
    
    if not position then
        return
    end
    
    local hudId = 'spell-' .. position
    
    HUD.activeCooldowns[spellId] = nil
    
    if spellCooldowns then
        spellCooldowns[spellId] = nil
    end
    
    SendNUIMessage({
        action = 'updateCooldown',
        id = hudId,
        percent = 0
    })
end

function HUD.ToggleHUD(visible)
    if visible and not ESX.IsPlayerLoaded() then
        return
    end
    
    HUD.visible = visible
    HUD.userToggled = true

    -- REPLACE WITH YOUR HUD SYSTEM IF NEEDED (e.g. lo_soupofdestiny)
    -- if GetResourceState('lo_soupofdestiny') == 'started' then
    --     exports['lo_soupofdestiny']:ToggleHouseHUD(visible)
    -- end
    
    SendNUIMessage({
        action = 'toggleHUD',
        visible = visible
    })
end

function HUD.ClearSpells()
    HUD.currentSpells = {}
    SendNUIMessage({
        action = 'clearSpells'
    })
end

function HUD.GetPlayerSpellsFromMain()
    return playerSpells or exports.dvr_power:getPlayerSpells() or {}
end

function HUD.GetUnlockedSpells()
    return HUD.GetPlayerSpellsFromMain()
end

function HUD.GetSelectedSpellFromMain()
    return selectedSpellId or exports.dvr_power:getSelectedSpell()
end

function HUD.GetConfigSpells()
    return Config and Config.Spells or {}
end

function HUD.VibrateSpell(position)
    if not hudReady then 
        return 
    end
    
    SendNUIMessage({
        action = 'vibrateSpell',
        id = 'spell-' .. position
    })
end

function HUD.Destroy()
    HUD.visible = false
    HUD.initialized = false

    SendNUIMessage({
        action = 'toggleHUD',
        visible = false
    })
    
    HUD.currentSpells = {}
    HUD.activeSpell = nil
    HUD.stats = {
        health = 100,
        healthCurrent = 0,
        healthMax = 0,
        hunger = 100,
        thirst = 100,
        potion = 0
    }
    HUD.lastPlayerSpellsCount = 0
    HUD.lastSelectedSpellId = nil
end

function HUD.SyncSpellsToHUD()
    if not hudReady then 
        return 
    end
    
    HUD.currentSpells = {}
end

CreateThread(function()
    while not ESX.IsPlayerLoaded() do 
        Wait(250) 
    end
    
    if not HUD then
        return
    end
    
    while not HUD.nuiReady do 
        Wait(100) 
    end
    
    Wait(1000)
    
    local playerData = ESX.GetPlayerData()
    if not playerData or not playerData.identifier then
        while not playerData or not playerData.identifier do
            Wait(500)
            playerData = ESX.GetPlayerData()
        end
    end
    
    hudReady = true
    HUD.initialized = true

    HUD.ToggleHUD(true)
    
    HUD.UpdateStats(HUD.stats.health, HUD.stats.hunger, HUD.stats.thirst, HUD.stats.magicHp, HUD.stats.potion)
    
    Wait(500)
    HUD.SyncSpellsToHUD()
    
    Wait(500)
    HUD.SyncKeysToHUD()
    refreshEsxStatuses(true)
    
    CreateThread(function()
        while true do
            Wait(500)
            
            if not HUD then
                break
            end
            
            if HUD.initialized then
                local invOpen = LocalPlayer.state.invOpen
                local shouldHide = IsPauseMenuActive() or IsScreenFadedOut() or IsScreenFadingOut() or IsScreenFadingIn() or (invOpen == true)
                
                if shouldHide and HUD.visible then
                    HUD.visible = false
                    SendNUIMessage({
                        action = 'toggleHUD',
                        visible = false
                    })

                    HUD.userToggled = false
                elseif not shouldHide and not HUD.visible and not HUD.userToggled then
                    HUD.visible = true
                    SendNUIMessage({
                        action = 'toggleHUD',
                        visible = true
                    })
                end
            end
        end
    end)
end)

local FIXED_KEYS = {
    ['center'] = 'H',
    ['top'] = '7',
    ['right'] = '9', 
    ['bottom'] = '8',
    ['left'] = '6'
}

function HUD.SyncKeysToHUD()
    if not hudReady then 
        return 
    end
    
    SendNUIMessage({
        action = 'updateKeys',
        keys = FIXED_KEYS
    })
end

CreateThread(function()
    while not hudReady do Wait(100) end
    
    while true do
        Wait(1000)
        
        if hudReady then
            local unlockedSpells = HUD.GetUnlockedSpells()
            local selectedSpellId = HUD.GetSelectedSpellFromMain()
            
            if unlockedSpells and #unlockedSpells ~= HUD.lastPlayerSpellsCount then
                HUD.lastPlayerSpellsCount = #unlockedSpells
            end
            
            if selectedSpellId and selectedSpellId ~= HUD.lastSelectedSpellId then
                HUD.lastSelectedSpellId = selectedSpellId
                
                local foundPosition = nil
                for position, spell in pairs(HUD.currentSpells) do
                    if spell.id == selectedSpellId then
                        foundPosition = position
                        break
                    end
                end
                
                if foundPosition then
                    HUD.SetActiveSpell(foundPosition)
                end
            end

            refreshEsxStatuses()
            
            local ped <const> = cache.ped
            if DoesEntityExist(ped) then
                local health <const> = GetEntityHealth(ped)
                local maxHealth <const> = GetEntityMaxHealth(ped)
                local healthPercent = 0
                if maxHealth and maxHealth > 0 then
                    healthPercent = math_floor((health / maxHealth) * 100)
                end

                local magicHp = LocalPlayer.state.magicHp or 100
                
                HUD.UpdateStats(healthPercent, nil, nil, magicHp, nil, health, maxHealth)
            end
        end
end
end)

RegisterNetEvent('esx_status:loaded')
AddEventHandler('esx_status:loaded', function()
    refreshEsxStatuses(true)
end)

CreateThread(function()
    while not ESX or not ESX.IsPlayerLoaded() do
        Wait(250)
    end

    if canUseEsxStatus() then
        refreshEsxStatuses(true)
    end
end)

RegisterCommand('hud', function()
    HUD.userToggled = true
    HUD.visible = not HUD.visible
    HUD.ToggleHUD(HUD.visible)
end, false)

RegisterNetEvent('dvr_power:onSpellCast', function(spellData)
    if spellData.id then
        for position, spell in pairs(HUD.currentSpells) do
            if spell.id == spellData.id then
                SendNUIMessage({
                    action = 'flashSpell',
                    id = 'spell-' .. position
                })
                
                if spellData.cooldown and spellData.cooldown > 0 then
                    local cooldownDuration = spellData.cooldown / 1000
                    if cooldownDuration < 0.1 then
                        cooldownDuration = 0.5
                    end
                    
                    HUD.StartCooldown(position, cooldownDuration)
                end
                break
            end
        end
    end
end)


RegisterNetEvent('dvr_power:unlockSpell', function(spellId)
    if not hudReady then
        return
    end
end)

RegisterNetEvent('dvr_power:registerModule', function(moduleData)
    if not hudReady then
        return
    end
end)

RegisterNetEvent('dvr_power:healPlayer', function()
    local ped <const> = cache.ped
    if DoesEntityExist(ped) then
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
    end
end)

exports('syncHUD', function()
    HUD.SyncSpellsToHUD()
end)

exports('UpdateStats', HUD.UpdateStats)
exports('SetSpells', HUD.SetSpells)
exports('SetActiveSpell', HUD.SetActiveSpell)
exports('StartCooldown', HUD.StartCooldown)
exports('UpdatePotionBar', function(value)
    HUD.UpdateStats(nil, nil, nil, nil, value)
end)

exports('ToggleHUD', HUD.ToggleHUD)
exports('ClearSpells', HUD.ClearSpells)
exports('VibrateSpell', HUD.VibrateSpell)

_ENV.HUD = HUD
