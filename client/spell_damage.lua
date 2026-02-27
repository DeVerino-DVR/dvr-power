---@diagnostic disable: undefined-global, trailing-space
local isProtected = false
local protectionEndTime = 0
local pendingDamages = {}  -- Queue of damages to apply after protection
local savedHealth = nil

-- Thread that handles temporary invincibility during spell explosions
-- Uses health restoration instead of full invincibility to allow ragdoll
CreateThread(function()
    while true do
        if isProtected then
            local currentTime = GetGameTimer()
            if currentTime >= protectionEndTime then
                -- Protection expired, restore normal state
                isProtected = false
                savedHealth = nil
            else
                -- Keep health stable during protection by restoring if it drops
                -- This allows ragdoll physics while preventing damage
                if savedHealth then
                    local currentHealth = GetEntityHealth(cache.ped)
                    if currentHealth < savedHealth then
                        SetEntityHealth(cache.ped, savedHealth)
                    end
                end
            end
            Wait(0)
        else
            Wait(100)
        end
    end
end)

--- Force ragdoll on the local player with direction from explosion
---@param duration number Duration in ms
---@param force number Force multiplier
---@param explosionCoords vector3|nil Coordinates of the explosion for direction calculation
local function ForceRagdoll(duration, force, explosionCoords)
    local ped = cache.ped
    if not ped or not DoesEntityExist(ped) then return end
    
    -- Don't ragdoll if player is in a vehicle
    if IsPedInAnyVehicle(ped, false) then return end
    
    -- Don't ragdoll if player is dead
    if IsPedDeadOrDying(ped, true) then return end
    
    -- Calculate push direction from explosion
    local pushX, pushY, pushZ = 0.0, 0.0, 0.0
    if explosionCoords then
        local pedCoords = GetEntityCoords(ped)
        local dirX = pedCoords.x - explosionCoords.x
        local dirY = pedCoords.y - explosionCoords.y
        local dirZ = 0.3  -- Slight upward push
        
        -- Normalize direction
        local length = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
        if length > 0.001 then
            pushX = (dirX / length) * force * 15.0
            pushY = (dirY / length) * force * 15.0
            pushZ = (dirZ / length) * force * 8.0 + 2.0  -- Minimum upward force
        end
    else
        -- Random direction if no explosion coords
        local randomAngle = math.random() * 2 * math.pi
        pushX = math.cos(randomAngle) * force * 10.0
        pushY = math.sin(randomAngle) * force * 10.0
        pushZ = force * 5.0
    end
    
    -- Enable ragdoll
    SetPedCanRagdoll(ped, true)
    
    -- Apply ragdoll with realistic duration
    local durationSeconds = duration / 1000.0
    SetPedToRagdollWithFall(
        ped,
        duration,                    -- Time in ms
        duration + 500,              -- Max time
        1,                           -- Ragdoll type (1 = normal fall)
        pushX, pushY, pushZ,         -- Push direction
        1.0,                         -- Blend in
        0.0, 0.0, 0.0,              -- Ground normal (auto-detect)
        0.0, 0.0, 0.0,              -- Velocity (use push instead)
        0.0                          -- Water level
    )
    
    -- Alternative: Simple ragdoll if the complex one fails
    if not IsPedRagdoll(ped) then
        SetPedToRagdoll(ped, duration, duration + 500, 0, true, true, false)
        
        -- Apply velocity for push effect
        SetEntityVelocity(ped, pushX, pushY, pushZ)
    end
end

-- Event to protect local player from explosion damage temporarily
-- Also handles forced ragdoll for immersion
RegisterNetEvent('th_power:protectFromExplosion', function(duration, damage, spellLevel, spellName, ragdollOptions)
    local durationMs = duration or 800
    local myPed = cache.ped
    local currentTime = GetGameTimer()
    local level = spellLevel or 1
    local spellInfo = spellName and string.format('[%s]', spellName) or ''
    
    -- Parse ragdoll options
    local ragdollDuration = 0
    local ragdollForce = 1.0
    local explosionCoords = nil
    
    if ragdollOptions and type(ragdollOptions) == 'table' then
        ragdollDuration = ragdollOptions.ragdollDuration or 0
        ragdollForce = ragdollOptions.ragdollForce or 1.0
        explosionCoords = ragdollOptions.explosionCoords
    end
    
    -- Save current health IMMEDIATELY before any explosion can happen
    local healthBefore = GetEntityHealth(myPed)
    
    if isProtected then
        -- If already protected, use saved health as baseline
        healthBefore = savedHealth or healthBefore
        
        -- Immediately subtract damage from saved health for next spell
        if damage and damage > 0 then
            savedHealth = math.max(0, healthBefore - damage)
        end
        
        -- Extend protection time if needed
        if currentTime + durationMs > protectionEndTime then
            protectionEndTime = currentTime + durationMs
        end
    else
        -- New protection - activate IMMEDIATELY
        isProtected = true
        protectionEndTime = currentTime + durationMs
        savedHealth = healthBefore
        
        -- Immediately subtract damage from saved health for this spell
        if damage and damage > 0 then
            savedHealth = math.max(0, healthBefore - damage)
        end
    end
    
    -- Queue damage to apply after protection
    table.insert(pendingDamages, {
        damage = damage or 0,
        healthBefore = healthBefore,
        healthAfter = math.max(0, healthBefore - (damage or 0)),
        applyTime = protectionEndTime + 150,
        level = level,
        spellInfo = spellInfo
    })
    
    -- Apply ragdoll immediately if enabled (before explosion for better timing)
    if ragdollDuration > 0 then
        -- Small delay to sync with explosion visual
        SetTimeout(50, function()
            ForceRagdoll(ragdollDuration, ragdollForce, explosionCoords)
        end)
    end
    
    -- Apply all queued damages after protection ends
    SetTimeout(durationMs + 150, function()
        -- Check if this is the last protection (no more pending)
        local shouldRestore = true
        for _, pending in ipairs(pendingDamages) do
            if GetGameTimer() < pending.applyTime then
                shouldRestore = false
                break
            end
        end
        
        if shouldRestore and GetGameTimer() >= protectionEndTime then
            isProtected = false
            savedHealth = nil
        end
        
        -- Apply this specific damage
        if damage and damage > 0 then
            -- Use the pre-calculated health values from queue
            local actualHealthBefore = healthBefore
            local newHealth = math.max(0, actualHealthBefore - damage)
            
            -- Apply health change
            SetEntityHealth(cache.ped, newHealth)
            
            -- Single line log: spell, level, damage applied, HP before -> after
            local maxHealth = GetEntityMaxHealth(cache.ped)
            if newHealth <= 0 then
                print(string.format('^1[damage_system]^0 %s ^2Niv.%d^0 Vous êtes tombé au combat! (^1-%d^0 dégâts)', 
                    spellInfo, level, damage))
            else
                local healthPercent = math.floor((newHealth / maxHealth) * 100)
                print(string.format('^3[damage_system]^0 %s ^2Niv.%d^0 ^1%d dégâts^0 reçus (HP: ^2%d^0 → ^1%d^0, ^2%d%%^0 restant)', 
                    spellInfo, level, damage, actualHealthBefore, newHealth, healthPercent))
            end
        end
        
        -- Remove this damage from queue
        for i = #pendingDamages, 1, -1 do
            if pendingDamages[i].damage == damage and pendingDamages[i].healthBefore == healthBefore then
                table.remove(pendingDamages, i)
                break
            end
        end
    end)
end)

-- Export for modules to check if player is currently protected
local function IsProtectedFromExplosion()
    return isProtected
end

exports('IsProtectedFromExplosion', IsProtectedFromExplosion)
