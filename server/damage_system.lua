---@diagnostic disable: undefined-global, trailing-space
local DamageSystem = {}

-- Track expected HP for players with pending damage
-- This prevents incorrect HP logs when multiple damages arrive rapidly
---@type table<number, {expectedHP: number, lastUpdate: number}>
local pendingDamageTracker = {}

-- Clean up old entries every 5 seconds
local TRACKER_CLEANUP_INTERVAL = 5000
local TRACKER_ENTRY_TTL = 3000 -- Entries expire after 3 seconds

CreateThread(function()
    while true do
        Wait(TRACKER_CLEANUP_INTERVAL)
        local now = GetGameTimer()
        for playerId, data in pairs(pendingDamageTracker) do
            if now - data.lastUpdate > TRACKER_ENTRY_TTL then
                pendingDamageTracker[playerId] = nil
            end
        end
    end
end)

---Get the expected HP for a player (accounts for pending damage)
---@param playerId number Server ID of the player
---@param actualHP number Current HP from GetEntityHealth
---@return number Expected HP
local function GetExpectedHP(playerId, actualHP)
    local tracker = pendingDamageTracker[playerId]
    local now = GetGameTimer()
    
    if tracker and (now - tracker.lastUpdate) < TRACKER_ENTRY_TTL then
        -- Use tracked value if it's lower (damage pending)
        return math.min(tracker.expectedHP, actualHP)
    end
    
    return actualHP
end

---Update the expected HP after applying damage
---@param playerId number Server ID of the player
---@param newExpectedHP number New expected HP after damage
local function UpdateExpectedHP(playerId, newExpectedHP)
    pendingDamageTracker[playerId] = {
        expectedHP = newExpectedHP,
        lastUpdate = GetGameTimer()
    }
end

---Check if player has Prothea shield active
---@param targetId number Server ID of the player to check
---@return boolean
local function HasProtheaShield(targetId)
    if exports['dvr_prothea'] and exports['dvr_prothea'].hasActiveShield then
        local success, result = pcall(function()
            return exports['dvr_prothea']:hasActiveShield(targetId)
        end)
        return success and result == true
    end
    return false
end

---Get all players within a radius of coordinates
---@param coords vector3 Center coordinates
---@param radius number Radius in meters
---@param excludeSource? number Optional server ID to exclude (usually the caster)
---@return table List of {playerId, ped, distance}
local function GetPlayersInRadius(coords, radius, excludeSource)
    local playersInRadius = {}
    local players = GetPlayers()
    
    for _, playerId in ipairs(players) do
        local targetId = tonumber(playerId)
        
        if targetId and targetId ~= excludeSource then
            local targetPed = GetPlayerPed(targetId)
            
            if targetPed and DoesEntityExist(targetPed) then
                local targetCoords = GetEntityCoords(targetPed)
                local distance = #(vector3(coords.x, coords.y, coords.z) - targetCoords)
                
                if distance <= radius then
                    table.insert(playersInRadius, {
                        playerId = targetId,
                        ped = targetPed,
                        distance = distance
                    })
                end
            end
        end
    end
    
    return playersInRadius
end

---@class SpellOptions
---@field ragdollDuration? number Duration in ms for forced ragdoll (0 = no ragdoll)
---@field ragdollForce? number Force multiplier for ragdoll (default: 1.0)

---Apply spell damage to players in radius with explosion protection
---This is the main function to use for spells with visual explosions
---@param coords vector3 Center coordinates of the damage area
---@param spellLevel number Level of the spell (1-5)
---@param damagePerLevel number Damage per level (e.g. 50 = level 1 does 50, level 2 does 100)
---@param radius number Radius in meters
---@param sourceId number Server ID of the caster (will not be damaged)
---@param spellName? string Optional spell name for debug logging
---@param protectionDuration? number Optional protection duration in ms (default 800)
---@param options? SpellOptions Optional settings (ragdoll, etc.)
---@return table List of affected players
function DamageSystem.ApplySpellDamage(coords, spellLevel, damagePerLevel, radius, sourceId, spellName, protectionDuration, options)
    local level = math.max(1, math.floor(tonumber(spellLevel) or 1))
    local damage = level * damagePerLevel
    local protection = protectionDuration or 800
    local spellInfo = spellName and string.format('[%s]', spellName) or '[Sort]'
    
    -- Ragdoll options (enabled by default for explosion spells)
    local opts = options or {}
    local ragdollDuration = opts.ragdollDuration
    local ragdollForce = opts.ragdollForce or 1.0
    
    -- Default ragdoll duration based on spell level if not specified
    if ragdollDuration == nil then
        ragdollDuration = 1500 + (level * 300)  -- 1.8s to 3s based on level
    end
    
    -- Get all players in radius
    local playersInRadius = GetPlayersInRadius(coords, radius, sourceId)
    local affectedPlayers = {}
    
    if #playersInRadius == 0 then
        return affectedPlayers
    end
    
    for _, playerData in ipairs(playersInRadius) do
        local targetId = playerData.playerId
        local targetName = GetPlayerName(targetId) or ('Joueur #' .. tostring(targetId))
        local targetPed = playerData.ped
        local hasShield = HasProtheaShield(targetId)
        
        if hasShield then
            -- Player has shield, no damage but record it
            table.insert(affectedPlayers, {
                playerId = targetId,
                damage = 0,
                distance = playerData.distance,
                blocked = true
            })
            
            print(string.format('^3[damage_system]^0 %s ^2Niv.%d^0 ^5%s^0 - ^4Bouclier Prothea^0, dégâts bloqués', 
                spellInfo, level, targetName))
        else
            -- Send protection + damage event to client
            -- Client will protect itself from explosion, then apply custom damage + ragdoll
            local actualHealth = GetEntityHealth(targetPed)
            local currentHealth = GetExpectedHP(targetId, actualHealth)
            local newHealth = math.max(0, currentHealth - damage)
            
            -- Update tracker with new expected HP
            UpdateExpectedHP(targetId, newHealth)
            
            -- Calculate ragdoll force based on distance (closer = stronger)
            local distanceFactor = math.max(0.3, 1.0 - (playerData.distance / radius))
            local actualRagdollForce = ragdollForce * distanceFactor
            
            TriggerClientEvent('dvr_power:protectFromExplosion', targetId, protection, damage, level, spellName, {
                ragdollDuration = ragdollDuration,
                ragdollForce = actualRagdollForce,
                explosionCoords = coords
            })
            
            table.insert(affectedPlayers, {
                playerId = targetId,
                damage = damage,
                distance = playerData.distance,
                blocked = false
            })
            
            -- Single line log: spell, level, target, damage, HP before -> after
            print(string.format('^3[damage_system]^0 %s ^2Niv.%d^0 ^5%s^0 - ^1%d dégâts^0 (HP: ^2%d^0 → ^1%d^0)', 
                spellInfo, level, targetName, damage, currentHealth, newHealth))
        end
    end
    
    return affectedPlayers
end

---Apply direct area damage without explosion protection (for non-explosion spells)
---@param coords vector3 Center coordinates of the damage area
---@param damage number Amount of damage to apply
---@param radius number Radius in meters
---@param sourceId number Server ID of the caster (will not be damaged)
---@param spellName? string Optional spell name for debug logging
---@return table List of affected players
function DamageSystem.ApplyAreaDamage(coords, damage, radius, sourceId, spellName)
    local spellInfo = spellName and string.format('[%s]', spellName) or '[Sort]'
    local playersInRadius = GetPlayersInRadius(coords, radius, sourceId)
    local affectedPlayers = {}
    
    if #playersInRadius == 0 then
        return affectedPlayers
    end
    
    for _, playerData in ipairs(playersInRadius) do
        local targetId = playerData.playerId
        local targetName = GetPlayerName(targetId) or ('Joueur #' .. tostring(targetId))
        local targetPed = playerData.ped
        local hasShield = HasProtheaShield(targetId)
        
        if hasShield then
            table.insert(affectedPlayers, {
                playerId = targetId,
                damage = 0,
                distance = playerData.distance,
                blocked = true
            })
            
            print(string.format('^3[damage_system]^0 %s ^5%s^0 - ^4Bouclier Prothea^0, dégâts bloqués', 
                spellInfo, targetName))
        else
            -- Apply damage directly server-side
            local currentHealth = GetEntityHealth(targetPed)
            local newHealth = math.max(0, currentHealth - damage)
            SetEntityHealth(targetPed, newHealth)
            
            table.insert(affectedPlayers, {
                playerId = targetId,
                damage = damage,
                distance = playerData.distance,
                blocked = false
            })
            
            -- Single line log (for ApplyAreaDamage, no level info available)
            print(string.format('^3[damage_system]^0 %s ^5%s^0 - ^1%d dégâts^0 (HP: ^2%d^0 → ^1%d^0)', 
                spellInfo, targetName, damage, currentHealth, newHealth))
        end
    end
    
    return affectedPlayers
end

-- Export functions
exports('ApplyAreaDamage', DamageSystem.ApplyAreaDamage)
exports('ApplySpellDamage', DamageSystem.ApplySpellDamage)
exports('GetPlayersInRadius', GetPlayersInRadius)
exports('HasProtheaShield', HasProtheaShield)

-- Global access
_G.THPowerDamageSystem = DamageSystem

return DamageSystem
