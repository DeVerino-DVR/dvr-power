---@diagnostic disable: trailing-space, undefined-global
local HPSystem = {}
local playerHP = {}
local LogDiscord <const> = require 'server.logs'

local HP_CONFIG <const> = {
    START_HP = 100,
    MAX_HP = 100,
    REGEN_ENABLED = true,
    REGEN_RATE = 1,
    REGEN_INTERVAL = 30000,
    REGEN_DELAY_AFTER_DAMAGE = 10000,
    DEATH_RESPAWN_TIME = Config.MagicHPRespawnTime or 30000,
}

local immunityCache = {}

local function IsPlayerImmune(source)
    if not Config.DamageImmunity or #Config.DamageImmunity == 0 then
        return false
    end

    if immunityCache[source] ~= nil then
        return immunityCache[source]
    end

    local identifiers = GetPlayerIdentifiers(source)
    if not identifiers then
        immunityCache[source] = false
        return false
    end

    for _, playerIdent in ipairs(identifiers) do
        for _, immuneIdent in ipairs(Config.DamageImmunity) do
            if string.lower(playerIdent) == string.lower(immuneIdent) then
                immunityCache[source] = true
                return true
            end
        end
    end

    immunityCache[source] = false
    return false
end

AddEventHandler('playerDropped', function()
    immunityCache[source] = nil
end)

function HPSystem.LoadHP(identifier)    
    local result <const> = MySQL.single.await('SELECT *, UNIX_TIMESTAMP(last_damage_time) as last_damage_timestamp FROM character_magic_hp WHERE identifier = ?', {identifier})
    
    if result then
        local lastDamageTime = nil
        if result.last_damage_timestamp then
            local timestamp = result.last_damage_timestamp
            if timestamp > 10000000000 then
                timestamp = timestamp / 1000
            end
            lastDamageTime = timestamp
        end
        
        return {
            current = result.current_hp,
            max = result.max_hp,
            isDead = result.is_dead == 1,
            lastDamageTime = lastDamageTime
        }
    else
        MySQL.insert.await('INSERT IGNORE INTO character_magic_hp (identifier, current_hp, max_hp) VALUES (?, ?, ?)', 
            {identifier, HP_CONFIG.START_HP, HP_CONFIG.MAX_HP})
        
        local newResult <const> = MySQL.single.await('SELECT *, UNIX_TIMESTAMP(last_damage_time) as last_damage_timestamp FROM character_magic_hp WHERE identifier = ?', {identifier})
        if newResult then
            local lastDamageTime = nil
            if newResult.last_damage_timestamp then
                local timestamp = newResult.last_damage_timestamp
                if timestamp > 10000000000 then
                    timestamp = timestamp / 1000
                end
                lastDamageTime = timestamp
            end
            
            return {
                current = newResult.current_hp,
                max = newResult.max_hp,
                isDead = newResult.is_dead == 1,
                lastDamageTime = lastDamageTime
            }
        else
            return {
                current = HP_CONFIG.START_HP,
                max = HP_CONFIG.MAX_HP,
                isDead = false,
                lastDamageTime = nil
            }
        end
    end
end

function HPSystem.SaveHP(identifier, hp, isDead, lastDamageTime)
    if lastDamageTime then
        local timestampInSeconds = lastDamageTime
        if timestampInSeconds > 10000000000 then
            timestampInSeconds = timestampInSeconds / 1000
        end
        
        MySQL.update.await('UPDATE character_magic_hp SET current_hp = ?, is_dead = ?, last_damage_time = FROM_UNIXTIME(?), updated_at = NOW() WHERE identifier = ?', 
            {hp, isDead and 1 or 0, timestampInSeconds, identifier})
    else
        MySQL.update.await('UPDATE character_magic_hp SET current_hp = ?, is_dead = ?, last_damage_time = NULL, updated_at = NOW() WHERE identifier = ?', 
            {hp, isDead and 1 or 0, identifier})
    end
end

function HPSystem.GetHP(source)
    local player <const> = ESX.GetPlayerFromId(source)
    if not player or not player.identifier then return nil end
    
    if not playerHP[player.identifier] then
        playerHP[player.identifier] = HPSystem.LoadHP(player.identifier)
    end
    
    return playerHP[player.identifier]
end

function HPSystem.DealDamage(source, damage, attackerId, spellId)
    local player <const> = ESX.GetPlayerFromId(source)
    if not player or not player.identifier then return false end

    if IsPlayerImmune(source) then
        return false
    end

    if exports['th_prothea']:hasGodmode(source) then
        return false
    end

    local reduction = 0
    local ok, shieldReduction = pcall(function()
        return exports['th_prothea']:getShieldReduction(source)
    end)
    if ok and shieldReduction and shieldReduction > 0 then
        reduction = shieldReduction
    end

    if reduction > 0 then
        local adjustedDamage = math.floor(damage * (1.0 - reduction))
        if adjustedDamage <= 0 then
            return false
        end
        damage = adjustedDamage
    end
    
    local hp <const> = HPSystem.GetHP(source)
    if not hp then return false end
    
    if hp.isDead then
        return false
    end
    
    hp.current = math.max(0, hp.current - damage)
    hp.lastDamageTime = os.time()

    if hp.current <= 0 then
        hp.isDead = true
        HPSystem.HandleDeath(source, player.identifier)
    end
    
    HPSystem.SaveHP(player.identifier, hp.current, hp.isDead, hp.lastDamageTime)
    TriggerClientEvent('th_power:updateHP', source, hp.current, hp.max, attackerId, spellId)
    
    return true
end

function HPSystem.Heal(source, amount)
    local player <const> = ESX.GetPlayerFromId(source)
    if not player or not player.identifier then return false end
    
    local hp <const> = HPSystem.GetHP(source)
    if not hp then return false end
    
    if hp.isDead then
        return false
    end
    
    local oldHP <const> = hp.current
    hp.current = math.min(hp.max, hp.current + amount)
    local actualHeal = hp.current - oldHP
    
    
    HPSystem.SaveHP(player.identifier, hp.current, hp.isDead, hp.lastDamageTime)
    TriggerClientEvent('th_power:updateHP', source, hp.current, hp.max)
    
    return true, actualHeal
end

RegisterNetEvent('esx:onPlayerDeath', function(data)
    local _source <const> = source
    local player <const> = ESX.GetPlayerFromId(_source)

    if not player then return end
    if IsPlayerImmune(_source) then return end
    data = data or {}
    
    local removeHp = 0
    local deathType = 'Inconnu'
    
    if data.deathCause then
        for _, deathCause in pairs(Config.DeathCause) do
            for _, causeId in pairs(deathCause.id) do
                if data.deathCause == causeId then
                    removeHp = deathCause.removeHp
                    deathType = deathCause.name
                    break
                end
            end
            if removeHp > 0 then break end
        end
    end
    
    local pedCoords = nil
    local ped <const> = GetPlayerPed(_source)
    if ped and ped ~= 0 then
        local coords <const> = GetEntityCoords(ped)
        if coords then
            pedCoords = { x = coords.x, y = coords.y, z = coords.z }
        end
    end

    local killerInfo = nil
    local killerServerId <const> = data.killerServerId or data.killer
    if killerServerId then
        killerInfo = { source = killerServerId }
    end

    local hp <const> = HPSystem.GetHP(_source)
    if hp then
        local damageAmount <const> = math.floor((hp.max * removeHp) / 100)
        local newHP <const> = math.max(0, hp.current - damageAmount)
        
        hp.current = newHP
        hp.isDead = (newHP <= 0)
        hp.lastDamageTime = os.time()
        HPSystem.SaveHP(player.identifier, hp.current, hp.isDead, hp.lastDamageTime)
        
        TriggerClientEvent('th_power:updateHP', _source, hp.current, hp.max, deathType, deathType, removeHp)
    end

    LogDiscord.LogDeath({
        source = _source,
        name = player.getName(),
        license = player.identifier,
        hp = hp,
        removeHp = removeHp,
        deathType = deathType,
        coords = pedCoords,
        causeHash = data.deathCause,
        killer = killerInfo
    })
end)

function HPSystem.HandleDeath(source, identifier)
    TriggerClientEvent('th_power:playerDied', source)
    
    if HP_CONFIG.DEATH_RESPAWN_TIME and HP_CONFIG.DEATH_RESPAWN_TIME > 0 then
        SetTimeout(HP_CONFIG.DEATH_RESPAWN_TIME, function()
            HPSystem.Respawn(source, identifier)
        end)
    end
end

function HPSystem.Respawn(source, identifier)
    local player <const> = ESX.GetPlayerFromId(source)
    if not player then return end
    
    local playerIdentifier <const> = identifier or player.identifier
    if not playerIdentifier then return end
    
    if not playerHP[playerIdentifier] then
        playerHP[playerIdentifier] = HPSystem.LoadHP(playerIdentifier)
    end
    
    local hp <const> = playerHP[playerIdentifier]
    if hp then
        hp.current = HP_CONFIG.START_HP
        hp.isDead = false
        hp.lastDamageTime = nil
        
        HPSystem.SaveHP(playerIdentifier, hp.current, hp.isDead, nil)
        TriggerClientEvent('th_power:respawn', source, hp.current, hp.max)
    end
end

function HPSystem.SetMaxHP(source, maxHP)
    local player <const> = ESX.GetPlayerFromId(source)
    if not player or not player.identifier then return false end
    
    local hp <const> = HPSystem.GetHP(source)
    if not hp then return false end
    
    hp.max = maxHP
    hp.current = math.min(hp.current, maxHP)
    
    MySQL.update.await('UPDATE character_magic_hp SET max_hp = ?, current_hp = ? WHERE identifier = ?', 
        {maxHP, hp.current, player.identifier})
    
    TriggerClientEvent('th_power:updateHP', source, hp.current, hp.max)
    
    return true
end

if HP_CONFIG.REGEN_ENABLED then
    CreateThread(function()
        local currentTime, timeSinceLastDamage
        local regenDelaySeconds <const> = HP_CONFIG.REGEN_DELAY_AFTER_DAMAGE / 1000
        
        while true do
            Wait(HP_CONFIG.REGEN_INTERVAL)
            currentTime = os.time()
            
            for identifier, hp in pairs(playerHP) do
                if not hp.isDead and hp.current < hp.max then
                    timeSinceLastDamage = hp.lastDamageTime and (currentTime - hp.lastDamageTime) or 999999
                    
                    if timeSinceLastDamage >= regenDelaySeconds then
                        hp.current = math.min(hp.max, hp.current + HP_CONFIG.REGEN_RATE)
                        
                        MySQL.update('UPDATE character_magic_hp SET current_hp = ?, updated_at = NOW() WHERE identifier = ?', 
                            {hp.current, identifier})
                    end
                end
            end
        end
    end)
end

AddEventHandler('esx:playerLoaded', function(source, xplayer)
    if not xplayer or not xplayer.identifier then return end
    
    playerHP[xplayer.identifier] = HPSystem.LoadHP(xplayer.identifier) or {}
    TriggerClientEvent('th_power:updateHP', source, playerHP[xplayer.identifier].current, playerHP[xplayer.identifier].max)
end)

AddEventHandler('esx:playerLogout', function(source)
    local player <const> = ESX.GetPlayerFromId(source)
    if not player or not player.identifier then return end
    
    if playerHP[player.identifier] then
        local hp <const> = playerHP[player.identifier]
        HPSystem.SaveHP(player.identifier, hp.current, hp.isDead, hp.lastDamageTime)
        playerHP[player.identifier] = nil
    end
end)

lib.addCommand('sethp', {
    help = 'Définir les HP d\'un joueur',
    params = {
        { name = 'target', type = 'playerId', help = 'ID du joueur' },
        { name = 'hp', type = 'number', help = 'HP à définir' }
    },
    restricted = 'group.admin'
}, function(source, args)
    local hp <const> = HPSystem.GetHP(args.target)
    if hp then
        hp.current = math.min(args.hp, hp.max)
        hp.isDead = hp.current <= 0
        
        HPSystem.SaveHP(ESX.GetPlayerFromId(args.target).identifier, hp.current, hp.isDead, hp.lastDamageTime)
        TriggerClientEvent('th_power:updateHP', args.target, hp.current, hp.max)
        
        lib.notify(source, {
            title = 'HP System',
            description = 'HP définis à ' .. hp.current,
            type = 'success'
        })
    end
end)

lib.addCommand('setmaxhp', {
    help = 'Définir les HP max d\'un joueur',
    params = {
        { name = 'target', type = 'playerId', help = 'ID du joueur' },
        { name = 'maxhp', type = 'number', help = 'HP max' }
    },
    restricted = 'group.admin'
}, function(source, args)
    if HPSystem.SetMaxHP(args.target, args.maxhp) then
        lib.notify(source, {
            title = 'HP System',
            description = 'HP max définis à ' .. args.maxhp,
            type = 'success'
        })
    end
end)

RegisterNetEvent('th_power:client:dealDamage', function(damage, attackerId, spellId)
    local _source <const> = source
    HPSystem.DealDamage(_source, damage or 1, attackerId, spellId)
end)

exports('DealDamage', HPSystem.DealDamage)
exports('Heal', HPSystem.Heal)
exports('GetHP', HPSystem.GetHP)
exports('Respawn', HPSystem.Respawn)

return HPSystem

