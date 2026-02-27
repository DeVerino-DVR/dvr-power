---@diagnostic disable: trailing-space, undefined-global, missing-parameter, missing-fields, undefined-field, redundant-parameter, deprecated, param-type-mismatch, redundant-return-value
local GetGameTimer = GetGameTimer
local DoesEntityExist = DoesEntityExist
local GetEntityCoords = GetEntityCoords
local GetPlayerPed = GetPlayerPed
local GetPlayerServerId = GetPlayerServerId
local IsEntityAPed = IsEntityAPed
local IsPedAPlayer = IsPedAPlayer
local IsControlPressed = IsControlPressed
local GetCurrentPedWeaponEntityIndex = GetCurrentPedWeaponEntityIndex
local SetEntityCoords = SetEntityCoords
local SetEntityRotation = SetEntityRotation
local SetEntityAlpha = SetEntityAlpha
local SetEntityCollision = SetEntityCollision
local SetEntityAsMissionEntity = SetEntityAsMissionEntity
local SetEntityVisible = SetEntityVisible
local DrawLightWithRange = DrawLightWithRange
local DeleteObject = DeleteObject
local DeleteEntity = DeleteEntity
local TaskPlayAnim = TaskPlayAnim
local ClearPedTasks = ClearPedTasks
local GetActivePlayers = GetActivePlayers
local GetPlayerFromServerId = GetPlayerFromServerId
local GetGameplayCamCoord = GetGameplayCamCoord
local GetGameplayCamRot = GetGameplayCamRot
local GetPedBoneIndex = GetPedBoneIndex
local GetWorldPositionOfEntityBone = GetWorldPositionOfEntityBone
local IsEntityDead = IsEntityDead
local HasNamedPtfxAssetLoaded = HasNamedPtfxAssetLoaded
local RequestNamedPtfxAsset = RequestNamedPtfxAsset
local UseParticleFxAsset = UseParticleFxAsset
local UseParticleFxAssetNextCall = UseParticleFxAssetNextCall
local StartNetworkedParticleFxLoopedOnEntity = StartNetworkedParticleFxLoopedOnEntity
local StartParticleFxLoopedOnEntityBone = StartParticleFxLoopedOnEntityBone
local SetParticleFxLoopedAlpha = SetParticleFxLoopedAlpha
local SetParticleFxLoopedColour = SetParticleFxLoopedColour
local SetParticleFxLoopedEvolution = SetParticleFxLoopedEvolution
local SetEntityAnimSpeed = SetEntityAnimSpeed
local RemoveParticleFx = RemoveParticleFx
local StopParticleFxLooped = StopParticleFxLooped
local RemoveNamedPtfxAsset = RemoveNamedPtfxAsset
local SetPedToRagdoll = SetPedToRagdoll
local IsPedFatallyInjured = IsPedFatallyInjured
local IsPedRagdoll = IsPedRagdoll
local string_lower = string.lower
local math_min = math.min
local math_max = math.max

local soundCooldownActive = false
local isCasting = false
local playerSpells = {}
local activeSpellSounds = {}
local playerSpellSet = {}
local playerSpellLevels = {}
local spellCooldowns = {}
local activeLights = {}
local wandFxHandles = {}
local selectedSpellId = nil
local spellRayProps = {}
local externalModules = {}
local externalSpellIndex = {}
local spellKeyAssignments = {}
local spellCastLevelCache = {}
local spellSets = {}
local currentSpellSetId = 1
local MAX_SPELL_SETS = 5
local lastSpellChange = 0
local isInitialLoad = true
local hasLoadedPlayerSpells = false
local SPELL_CHANGE_COOLDOWN = 0
local LEFT_CLICK_SOUND_URL <const> = 'YOUR_SOUND_URL_HERE' -- Left click sound effect
local LEFT_CLICK_SOUND_VOLUME <const> = 1.0
local leftClickSoundActive = false
local castLockUntil = 0
local lastStateLockNotify = 0
local lastSpellInteractionAt = 0
local SPELL_INACTIVITY_TIMEOUT <const> = 5 * 60 * 1000
local INPUT_PUSH_TO_TALK <const> = 249

local SaveSpellKeyAssignments
local SaveCooldownsToCache
local LoadSpellKeyAssignmentsFromCache
local UpdateHUD
local RestoreActiveSpell
local UpdateSingleSpellInHUD

local WAND_BONE_INDEX <const> = 57005
local WAND_TRAIL_COLOR <const> = { r = 1.0, g = 0.05, b = 0.05 }
local WAND_CAST_EXTENSION_LEAD <const> = 380
local WAND_TRAIL_LINGER <const> = 350

local WAND_TRAIL_VARIANTS <const> = {
    precast = {
        dict = 'core',
        particle = 'veh_light_red_trail',
        offset = { x = 0.34, y = 0.0, z = 0.015 },
        scale = 1.35,
        alpha = 220.0,
        speed = 0.95
    },
    cast = {
        dict = 'core',
        particle = 'veh_light_red_trail',
        offset = { x = 0.5, y = 0.0, z = 0.02 },
        scale = 2.8,
        alpha = 255.0,
        speed = 1.35
    }
}

for _, variant in pairs(WAND_TRAIL_VARIANTS) do
    variant.color = WAND_TRAIL_COLOR
end

local POSITION_TO_KEY <const> = {
    top = '7',
    left = '6',
    right = '9',
    center = 'H',
    bottom = '8'
}

local ELEMENT_BY_TYPE = {
    attack = 'fire',
    defense = 'water',
    heal = 'light',
    control = 'dark'
}

local ICON_BY_TYPE = {
    attack = 'wand-sparkles',
    defense = 'shield-halved',
    heal = 'heart',
    control = 'hand',
    utility = 'lightbulb',
    summon = 'ghost'
}

local lastModuleSync = 0
local lastNeedsLockNotify = 0
local LEVEL_CONFIG <const> = Config.Leveling or {}
local LEVEL_OVERRIDES <const> = Config.SpellLevelOverrides or {}
local COOLDOWN_DISABLE_LEVEL <const> = 5

local function DeepCopyTable(source)
    if type(source) ~= 'table' then
        return source
    end

    local target = {}
    for key, value in pairs(source) do
        target[key] = DeepCopyTable(value)
    end
    return target
end

local function MergeTables(base, override)
    if type(base) ~= 'table' or type(override) ~= 'table' then
        return base
    end
    for key, value in pairs(override) do
        if type(value) == 'table' and type(base[key]) == 'table' then
            MergeTables(base[key], value)
        else
            base[key] = DeepCopyTable(value)
        end
    end
    return base
end

local function GetLevelingConfig(spellId)
    if not LEVEL_CONFIG or LEVEL_CONFIG.enabled == false then
        return nil
    end

    local override = LEVEL_OVERRIDES[spellId]
    if not override then
        return LEVEL_CONFIG
    end

    local merged = DeepCopyTable(LEVEL_CONFIG)
    return MergeTables(merged, override)
end

local function GetDefaultSpellLevel(spellId)
    local config = GetLevelingConfig(spellId)
    if not config then
        return 0
    end
    if config.default_level ~= nil then
        return config.default_level
    end
    return config.max_level or 0
end

local function GetSpellLevel(spellId)
    local level = playerSpellLevels[spellId]
    if level ~= nil then
        return level
    end
    return GetDefaultSpellLevel(spellId)
end

local function GetSpellMaxLevel(spellId)
    local config = GetLevelingConfig(spellId)
    if config and config.max_level then
        return config.max_level
    end
    if Config.Leveling and Config.Leveling.max_level then
        return Config.Leveling.max_level
    end
    return 1
end

local function IsPedUnableToCast(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false
    end

    if IsEntityDead(ped) or IsPedFatallyInjured(ped) or ESX.PlayerData.dead then
        return true, 'Vous êtes inconscient, impossible de lancer un sort.'
    end

    if IsPedRagdoll(ped) then
        return true, 'Vous êtes à terre, impossible de lancer un sort.'
    end

    return false
end

local function IsCastingLockedByState()
    local ped = cache and cache.ped
    local pedLocked, pedReason = IsPedUnableToCast(ped)
    if pedLocked then
        return true, pedReason
    end

    if LocalPlayer and LocalPlayer.state then
        if LocalPlayer.state.staturion == true then
            return true, 'Vous êtes staturisé, impossible de lancer un sort.'
        end
    end
    return false
end

local function GetHighestPlayerSpellLevel()
    local highest = 0

    for _, level in pairs(playerSpellLevels) do
        if level and level > highest then
            highest = level
        end
    end

    if highest <= 0 and LEVEL_CONFIG and LEVEL_CONFIG.default_level then
        highest = LEVEL_CONFIG.default_level
    end

    return highest
end

local function IsCooldownEnabledForPlayer(spellId)
    if spellId then
        local level = GetSpellLevel(spellId)
        return level < COOLDOWN_DISABLE_LEVEL
    end

    local playerLevel = GetHighestPlayerSpellLevel()
    return playerLevel < COOLDOWN_DISABLE_LEVEL
end

local function ClampLevelForSpell(spellId, value)
    local level = math.floor(tonumber(value) or 0)
    if level < 0 then
        level = 0
    elseif level > 50 then
        level = 50
    end
    return level
end

local function GetQualityForLevel(spellId, level)
    local config = GetLevelingConfig(spellId)
    if not config then
        return 1.0
    end

    local maxLevel = config.max_level or 5
    if maxLevel <= 0 then
        return 1.0
    end

    local normalizedLevel = math.max(0, math.min(level or maxLevel, maxLevel))
    local minQuality = config.min_quality or 0.35
    local quality = normalizedLevel / maxLevel
    if quality < minQuality then
        return minQuality
    end
    if quality > 1.0 then
        return 1.0
    end
    return quality
end

local function ShouldMuteSoundForLevel(spellId, level)
    local config = GetLevelingConfig(spellId)
    if not config then
        return false
    end

    local minLevel = config.min_sound_level or 2
    return (level or 0) < minLevel
end

local function CacheSpellLevelInfo(sourceId, spellId, level, quality)
    if not sourceId or not spellId then
        return
    end

    local castLevel = level or GetDefaultSpellLevel(spellId)
    local castQuality = quality or GetQualityForLevel(spellId, castLevel)
    local cacheEntry = spellCastLevelCache[sourceId]
    if not cacheEntry then
        cacheEntry = {}
        spellCastLevelCache[sourceId] = cacheEntry
    end
    cacheEntry[spellId] = {
        level = castLevel,
        quality = castQuality,
        time = GetGameTimer()
    }
end

local function GetSpellDefinition(spellId)
    local entry = externalSpellIndex[spellId]
    local spell = Config.Spells[spellId] or (entry and entry.spell)
    if spell then
        return spell, entry
    end
    return nil, nil
end


local function CalculateCooldownForLevel(spellId)
    if not IsCooldownEnabledForPlayer(spellId) then
        return 0
    end

    local spell = GetSpellDefinition(spellId)
    if not spell then
        return Config.DefaultCooldown or 5000
    end
    
    local config = GetLevelingConfig(spellId)
    if not config then
        return spell.cooldown or Config.DefaultCooldown or 5000
    end

    local baseCooldown = spell.cooldown or Config.DefaultCooldown or 5000
    local multipliers = config.cooldown_multiplier or {}
    local minMultiplier = multipliers.minimum or 1.0
    local maxMultiplier = multipliers.maximum or 3.0
    local maxLevel = config.max_level or 5
    
    if maxLevel <= 0 then
        return baseCooldown
    end

    local level = GetSpellLevel(spellId)
    if level < 0 then
        level = 0
    elseif level > maxLevel then
        level = maxLevel
    end

    local ratio = level / maxLevel
    local multiplier = minMultiplier + ((1.0 - ratio) * (maxMultiplier - minMultiplier))
    local adjustedCooldown = baseCooldown * multiplier

    local dividerCfg = config.cooldown_divider
    if dividerCfg and dividerCfg.enabled ~= false then
        local step = dividerCfg.step or 0.15
        local divider = 1.0 + (level * step)
        if divider > 0 then
            adjustedCooldown = adjustedCooldown / divider
        end
    end

    return math.floor(adjustedCooldown)
end

local function RequestModuleSync(force)
    local now = GetGameTimer()
    if not force and (now - lastModuleSync) < 5000 then
        return
    end

    lastModuleSync = now
    TriggerServerEvent('dvr_power:requestModuleSync')
end

AddEventHandler('playerSpawned', function()
    RequestModuleSync(false)
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    CreateThread(function()
        Wait(1500)
        RequestModuleSync(true)
    end)
end)

RegisterNetEvent('dvr_power:refreshModules', function()
    RequestModuleSync(true)
end)

if Config.SpellTypes then
    for _, value in pairs(Config.SpellTypes) do
        local lower = string_lower(value)
        if ELEMENT_BY_TYPE[lower] then
            ELEMENT_BY_TYPE[value] = ELEMENT_BY_TYPE[lower]
        end
        if ICON_BY_TYPE[lower] then
            ICON_BY_TYPE[value] = ICON_BY_TYPE[lower]
        end
    end
end

local function NormalizeSpellType(spellType)
    if not spellType then
        return nil
    end

    if ICON_BY_TYPE[spellType] or ELEMENT_BY_TYPE[spellType] then
        return spellType
    end

    return string_lower(spellType)
end

local function GetSpellElement(spellType)
    local normalized = NormalizeSpellType(spellType)
    return ELEMENT_BY_TYPE[normalized] or 'neutral'
end

local function IndexModuleSpells(moduleName, moduleData, origin)
    if not moduleName or not moduleData then
        return
    end

    local moduleOrigin = origin or moduleData.__origin or 'server'

    if moduleData.spells then
        for _, spell in ipairs(moduleData.spells) do
            if spell.id then
                externalSpellIndex[spell.id] = {
                    moduleName = moduleName,
                    module = moduleData,
                    spell = spell,
                    origin = moduleOrigin
                }
            end
        end
    elseif moduleData.id then
        externalSpellIndex[moduleData.id] = {
            moduleName = moduleName,
            module = moduleData,
            spell = moduleData,
            origin = moduleOrigin
        }
    end
end

local function RemoveModuleSpells(moduleName)
    local moduleData = externalModules[moduleName]
    if not moduleData then
        return
    end

    if moduleData.spells then
        for _, spell in ipairs(moduleData.spells) do
            if spell.id then
                externalSpellIndex[spell.id] = nil
            end
        end
    elseif moduleData.id then
        externalSpellIndex[moduleData.id] = nil
    end
end

local function DeselectActiveSpell()
    if not selectedSpellId then
        return false
    end

    selectedSpellId = nil
    lastSpellInteractionAt = 0
    DeleteResourceKvp('dvr_power:last_active_spell')

    if HUD then
        HUD.lastSelectedSpellId = nil
        HUD.activeSpell = nil
    end

    SendNUIMessage({
        action = 'setSelectedSpell',
        position = nil,
        spellId = nil
    })

    if HUD and HUD.SetActiveSpell then
        HUD.SetActiveSpell(nil)
    else
        SendNUIMessage({
            action = 'setActiveSpell'
        })
    end
    return true
end

local function RemoveAssignmentsForSpell(spellId)
    if not spellId then
        return
    end

    local position = spellKeyAssignments[spellId]
    if not position then
        return
    end

    spellKeyAssignments[spellId] = nil

    if HUD and HUD.currentSpells then
        HUD.currentSpells[position] = nil
    end

    SendNUIMessage({
        action = 'setSpell',
        position = position,
        spell = nil
    })

    if HUD and HUD.StopCooldown then
        HUD.StopCooldown(spellId, position)
    end

    if selectedSpellId == spellId then
        DeselectActiveSpell()
    end

    if spellCooldowns[spellId] then
        spellCooldowns[spellId] = nil
        SaveCooldownsToCache()
    end

    SaveSpellKeyAssignments()
end

local function CleanupHudAssignments()
    if not hasLoadedPlayerSpells then
        return false
    end

    if not spellKeyAssignments or next(spellKeyAssignments) == nil then
        return false
    end

    local toRemove = {}

    for spellId in pairs(spellKeyAssignments) do
        if not playerSpellSet[spellId] then
            toRemove[#toRemove + 1] = spellId
        end
    end

    if #toRemove == 0 then
        return false
    end

    for _, spellId in ipairs(toRemove) do
        RemoveAssignmentsForSpell(spellId)
    end

    return true
end

SaveCooldownsToCache = function()
    local currentTime = GetGameTimer()
    local activeCooldowns = {}
    
    for spellId, endTime in pairs(spellCooldowns) do
        if IsCooldownEnabledForPlayer(spellId) and endTime > currentTime then
            local remainingTime = endTime - currentTime
            activeCooldowns[spellId] = remainingTime
        end
    end
    
    if next(activeCooldowns) then
        local cooldownsJson = json.encode(activeCooldowns)
        SetResourceKvp('dvr_power:active_cooldowns', cooldownsJson)
    else
        DeleteResourceKvp('dvr_power:active_cooldowns')
    end
end

local function LoadCooldownsFromCache()
    local cooldownsJson = GetResourceKvpString('dvr_power:active_cooldowns')
    if cooldownsJson and cooldownsJson ~= '' then
        local success, activeCooldowns = pcall(json.decode, cooldownsJson)
        if success and activeCooldowns then
            local currentTime = GetGameTimer()
            local loadedCount = 0

            Wait(200)
            
            for spellId, remainingTime in pairs(activeCooldowns) do
                if IsCooldownEnabledForPlayer(spellId) and remainingTime > 0 and not spellCooldowns[spellId] then
                    spellCooldowns[spellId] = currentTime + remainingTime
                    loadedCount = loadedCount + 1

                    local duration = remainingTime / 1000
                    local position = GetHudPositionForSpell(spellId)
                    if HUD and HUD.StartCooldown and position then
                        HUD.StartCooldown(spellId, duration, position)
                    end
                end
            end
            
            return loadedCount > 0
        end
    end
    return false
end

CreateThread(function()
    while true do
        Wait(5000)
        
        local currentTime = GetGameTimer()
        local hasActiveCooldowns = false
        
        for spellId, endTime in pairs(spellCooldowns) do
            if endTime <= currentTime then
                spellCooldowns[spellId] = nil
            else
                hasActiveCooldowns = true
            end
        end
        
        if hasActiveCooldowns then
            SaveCooldownsToCache()
        end
    end
end)

local function RotationToDirection(rotation)
    local adjustedRotation <const> = {
        x = (math.pi / 180) * rotation.x,
        y = (math.pi / 180) * rotation.y,
        z = (math.pi / 180) * rotation.z
    }
    local direction <const> = {
        x = -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        y = math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        z = math.sin(adjustedRotation.x)
    }
    return direction
end

local function PlayConfirmationSound(action, spellId)
    if not Config.ApplySound then return end
    if soundCooldownActive then return end
    
    local soundKey = 'spell_' .. action .. '_' .. spellId
    local volume = action == 'assigned' and 0.3 or 0.2
    
    -- REPLACE WITH YOUR SOUND SYSTEM
    -- pcall(function()
    --     exports['lo_audio']:playSound({
    --         id = soundKey,
    --         url = Config.ApplySound,
    --         volume = volume,
    --         loop = false,
    --         distance = 10.0,
    --         category = 'spell',
    --     })
    -- end)

    soundCooldownActive = true
    SetTimeout(1000, function()
        soundCooldownActive = false
    end)
end

local function PlayEchecSound(spellId)
    if not Config.EchecSound then return end
    if soundCooldownActive then return end

    local soundKey = 'spell_echec_' .. spellId
    local volume = 0.2

    -- REPLACE WITH YOUR SOUND SYSTEM
    -- pcall(function()
    --     exports['lo_audio']:playSound({
    --         id = soundKey,
    --         url = Config.EchecSound,
    --         volume = volume,
    --         loop = false,
    --         distance = 10.0,
    --         category = 'spell',
    --     })
    -- end)
    
    soundCooldownActive = true
    SetTimeout(1000, function()
        soundCooldownActive = false
    end)
end

local function PlayLeftClickSound()
    if leftClickSoundActive then
        return
    end

    if not LEFT_CLICK_SOUND_URL or LEFT_CLICK_SOUND_URL == '' then
        return
    end

    leftClickSoundActive = true
    local startAt = GetGameTimer()

    SetTimeout(300, function()
        local soundId = ('dvr_power_left_click_%s_%d'):format(cache and cache.serverId or 'local', startAt)
        -- REPLACE WITH YOUR SOUND SYSTEM
        -- pcall(function()
        --     local handle = exports['lo_audio']:playSound({
        --         id = soundId,
        --         url = LEFT_CLICK_SOUND_URL,
        --         volume = LEFT_CLICK_SOUND_VOLUME,
        --         loop = false,
        --         spatial = false,
        --         distance = 10.0,
        --         category = 'spell',
        --     })
        --     activeSpellSounds[soundId] = handle or true
        -- end)

        SetTimeout(800, function()
            leftClickSoundActive = false
        end)
    end)
end

SaveSpellKeyAssignments = function()
    if selectedSpellId then
        SetResourceKvp('dvr_power:last_active_spell', selectedSpellId)
    else
        DeleteResourceKvp('dvr_power:last_active_spell')
    end

    local assignmentsJson = json.encode(spellKeyAssignments)
    SetResourceKvp('dvr_power:spell_key_assignments', assignmentsJson)

    local currentAssignmentsCopy = {}
    for k, v in pairs(spellKeyAssignments) do
        currentAssignmentsCopy[k] = v
    end
    spellSets[currentSpellSetId] = {
        assignments = currentAssignmentsCopy,
        selectedSpell = selectedSpellId
    }
    local setsJson = json.encode(spellSets)
    SetResourceKvp('dvr_power:spell_sets', setsJson)
    SetResourceKvp('dvr_power:current_spell_set', tostring(currentSpellSetId))
end

local function LoadSpellSetsFromCache()
    local setsJson = GetResourceKvpString('dvr_power:spell_sets')
    print('[SpellSets] Loading from cache...')
    print('[SpellSets] Raw JSON: ' .. tostring(setsJson))

    if setsJson and setsJson ~= '' then
        local success, loadedSets = pcall(json.decode, setsJson)
        print('[SpellSets] Decode success: ' .. tostring(success))
        if success and loadedSets then
            spellSets = {}

            local oldSets = loadedSets.sets
            local oldSelectedPerSet = loadedSets.selectedPerSet
            local needsMigration = false

            for key, value in pairs(loadedSets) do
                local numKey = tonumber(key)
                if numKey and numKey >= 1 and numKey <= MAX_SPELL_SETS and type(value) == 'table' and value.assignments ~= nil then
                    local assignmentCount = 0
                    if type(value.assignments) == 'table' then
                        for _ in pairs(value.assignments) do
                            assignmentCount = assignmentCount + 1
                        end
                    end

                    if assignmentCount > 0 then
                        spellSets[numKey] = value
                        print('[SpellSets] Loaded set ' .. tostring(numKey) .. ' with ' .. assignmentCount .. ' assignments')
                        for spellId, pos in pairs(value.assignments) do
                            print('[SpellSets]   - ' .. tostring(spellId) .. ' -> ' .. tostring(pos))
                        end
                    else
                        needsMigration = true
                    end
                end
            end

            if needsMigration and oldSets and type(oldSets) == 'table' then
                print('[SpellSets] Migrating from old format...')
                for i, oldSetData in ipairs(oldSets) do
                    if type(oldSetData) == 'table' and i <= MAX_SPELL_SETS then
                        local assignmentCount = 0
                        for _ in pairs(oldSetData) do
                            assignmentCount = assignmentCount + 1
                        end

                        if assignmentCount > 0 then
                            local selectedSpell = nil
                            if oldSelectedPerSet and oldSelectedPerSet[i] then
                                selectedSpell = oldSelectedPerSet[i]
                            end

                            spellSets[i] = {
                                assignments = oldSetData,
                                selectedSpell = selectedSpell
                            }
                            print('[SpellSets] Migrated set ' .. i .. ' with ' .. assignmentCount .. ' assignments')
                            for spellId, pos in pairs(oldSetData) do
                                print('[SpellSets]   - ' .. tostring(spellId) .. ' -> ' .. tostring(pos))
                            end
                        end
                    end
                end

                local newSetsJson = json.encode(spellSets)
                SetResourceKvp('dvr_power:spell_sets', newSetsJson)
                print('[SpellSets] Migration complete, saved new format')
            end
        end
    else
        print('[SpellSets] No saved sets found')
    end

    local currentSetStr = GetResourceKvpString('dvr_power:current_spell_set')
    print('[SpellSets] Current set from KVP: ' .. tostring(currentSetStr))
    if currentSetStr and currentSetStr ~= '' then
        local setId = tonumber(currentSetStr)
        if setId and setId >= 1 and setId <= MAX_SPELL_SETS then
            currentSpellSetId = setId
        end
    end
    print('[SpellSets] Using set ID: ' .. tostring(currentSpellSetId))

    if not spellSets[currentSpellSetId] then
        print('[SpellSets] Set ' .. currentSpellSetId .. ' not found, creating empty')
        spellSets[currentSpellSetId] = {
            assignments = {},
            selectedSpell = nil
        }
    else
        print('[SpellSets] Set ' .. currentSpellSetId .. ' found with assignments: ' .. json.encode(spellSets[currentSpellSetId].assignments or {}))
    end
end

local function SwitchSpellSet(setId)
    if setId < 1 or setId > MAX_SPELL_SETS then
        return false
    end

    local currentAssignmentsCopy = {}
    for k, v in pairs(spellKeyAssignments) do
        currentAssignmentsCopy[k] = v
    end
    spellSets[currentSpellSetId] = {
        assignments = currentAssignmentsCopy,
        selectedSpell = selectedSpellId
    }

    local setsJson = json.encode(spellSets)
    SetResourceKvp('dvr_power:spell_sets', setsJson)

    currentSpellSetId = setId

    if spellSets[setId] and spellSets[setId].assignments then
        spellKeyAssignments = {}
        for k, v in pairs(spellSets[setId].assignments) do
            spellKeyAssignments[k] = v
        end
        selectedSpellId = spellSets[setId].selectedSpell
    else
        spellKeyAssignments = {}
        selectedSpellId = nil
        spellSets[setId] = {
            assignments = {},
            selectedSpell = nil
        }
    end

    for _, position in ipairs({'top', 'left', 'center', 'right', 'bottom'}) do
        SendNUIMessage({
            action = 'setSpell',
            position = position,
            spell = nil
        })
    end

    for spellId, position in pairs(spellKeyAssignments) do
        UpdateSingleSpellInHUD(spellId, position)
    end

    if selectedSpellId then
        local position = spellKeyAssignments[selectedSpellId]
        if position and HUD and HUD.SetActiveSpell then
            HUD.SetActiveSpell(position)
        end
    end

    local now = GetGameTimer()
    for spellId, position in pairs(spellKeyAssignments) do
        if spellCooldowns[spellId] and spellCooldowns[spellId] > now then
            local remainingMs = spellCooldowns[spellId] - now
            local remainingSec = remainingMs / 1000
            if remainingSec > 0.1 and HUD and HUD.StartCooldown then
                HUD.StartCooldown(spellId, remainingSec, position)
            end
        end
    end

    SaveSpellKeyAssignments()

    return true
end

local function GetSpellSetsForNUI()
    local sets = {}
    for i = 1, MAX_SPELL_SETS do
        local setData = spellSets[i]
        local spellCount = 0
        if setData and setData.assignments then
            for _ in pairs(setData.assignments) do
                spellCount = spellCount + 1
            end
        end
        table.insert(sets, {
            id = i,
            name = "Set " .. i,
            spellCount = spellCount,
            active = (i == currentSpellSetId)
        })
    end
    return sets
end

local function RenameSpellSet(setId, newName)
    if setId < 1 or setId > MAX_SPELL_SETS then
        return false
    end

    if not spellSets[setId] then
        spellSets[setId] = {
            assignments = {},
            selectedSpell = nil
        }
    end

    spellSets[setId].name = newName

    local setsJson = json.encode(spellSets)
    SetResourceKvp('dvr_power:spell_sets', setsJson)

    return true
end

local function GetSpellName(spellId)
    local spell = GetSpellDefinition(spellId)
    if spell and spell.name then
        return spell.name
    end
    return spellId
end

local function BuildHudSpellPayload(spellId, position, spellDefinition, overrideName)
    if not spellDefinition then
        return nil
    end

    local icon = spellDefinition.image or spellDefinition.icon or 'images/power/dvr_basic.png'
    local element = GetSpellElement(spellDefinition.type)
    local key = POSITION_TO_KEY[position] or ''
    local displayName = overrideName or spellDefinition.name or spellId

    local level = tonumber(GetSpellLevel(spellId)) or 0
    local maxLevel = tonumber(GetSpellMaxLevel(spellId)) or 1

    level = math.floor(level + 0.0001)
    maxLevel = math.floor(maxLevel + 0.0001)
    if maxLevel <= 0 then
        maxLevel = 1
    end

    local levelRatio = math.min(1.0, math.max(0.0, level / 50))

    return {
        id = spellId,
        name = displayName,
        icon = icon,
        element = element,
        key = key,
        color = spellDefinition.color or spellDefinition.element or spellDefinition.type,
        level = level,
        maxLevel = maxLevel,
        levelRatio = levelRatio,
        levelText = ('Lv %d/%d'):format(level, maxLevel)
    }
end

UpdateSingleSpellInHUD = function(spellId, position)
    if not HUD then
        return
    end

    if not spellId or not position then
        return
    end

    local spellName = GetSpellName(spellId)
    local spell = GetSpellDefinition(spellId)
    
    if spell then
        local payload = BuildHudSpellPayload(spellId, position, spell, spellName)
        SendNUIMessage({
            action = 'setSpell',
            position = position,
            spell = payload
        })

        if HUD then
            if not HUD.currentSpells then
                HUD.currentSpells = {}
            end
            HUD.currentSpells[position] = payload
        end
    else
        SendNUIMessage({
            action = 'setSpell',
            position = position,
            spell = nil
        })
        
        if HUD then
            if not HUD.currentSpells then
                HUD.currentSpells = {}
            end
            HUD.currentSpells[position] = nil
        end
    end
end

LoadSpellKeyAssignmentsFromCache = function()
    print('[SpellSets] LoadSpellKeyAssignmentsFromCache called')
    LoadSpellSetsFromCache()

    print('[SpellSets] Checking set ' .. tostring(currentSpellSetId) .. ' exists: ' .. tostring(spellSets[currentSpellSetId] ~= nil))
    if spellSets[currentSpellSetId] then
        print('[SpellSets] Set assignments exists: ' .. tostring(spellSets[currentSpellSetId].assignments ~= nil))
    end

    if spellSets[currentSpellSetId] and spellSets[currentSpellSetId].assignments then
        local assignmentCount = 0
        for _ in pairs(spellSets[currentSpellSetId].assignments) do
            assignmentCount = assignmentCount + 1
        end
        print('[SpellSets] Loading ' .. assignmentCount .. ' assignments from set ' .. currentSpellSetId)

        spellKeyAssignments = {}
        for k, v in pairs(spellSets[currentSpellSetId].assignments) do
            spellKeyAssignments[k] = v
            print('[SpellSets] Applied: ' .. tostring(k) .. ' -> ' .. tostring(v))
        end
        selectedSpellId = spellSets[currentSpellSetId].selectedSpell
        print('[SpellSets] Selected spell: ' .. tostring(selectedSpellId))

        CleanupHudAssignments()

        for spellId, position in pairs(spellKeyAssignments) do
            UpdateSingleSpellInHUD(spellId, position)
        end
    else
        print('[SpellSets] No set assignments, falling back to legacy KVP')
        local assignmentsJson = GetResourceKvpString('dvr_power:spell_key_assignments')
        if assignmentsJson and assignmentsJson ~= '' then
            local success, cachedAssignments = pcall(json.decode, assignmentsJson)
            if success and cachedAssignments then
                spellKeyAssignments = cachedAssignments

                CleanupHudAssignments()

                for spellId, position in pairs(spellKeyAssignments) do
                    UpdateSingleSpellInHUD(spellId, position)
                end
            end
        end

        local activeSpellJson = GetResourceKvpString('dvr_power:last_active_spell')
        if activeSpellJson and activeSpellJson ~= '' then
            selectedSpellId = activeSpellJson
        end
    end

    if selectedSpellId then
        lastSpellInteractionAt = GetGameTimer()

        if HUD and HUD.SetActiveSpell then
            local position = GetHudPositionForSpell(selectedSpellId)
            if position then
                HUD.lastSelectedSpellId = selectedSpellId
                HUD.SetActiveSpell(position)
            end
        end
    end
    print('[SpellSets] Final spellKeyAssignments: ' .. json.encode(spellKeyAssignments))

    return true
end

function GetHudPositionForSpell(spellId)
    return spellKeyAssignments[spellId]
end

UpdateHUD = function()
    if not HUD then 
        return 
    end
    
    local count = 0
    for _ in pairs(spellKeyAssignments) do
        count = count + 1
    end
    
    for spellId, position in pairs(spellKeyAssignments) do
        local spellName = GetSpellName(spellId)
        local spell = GetSpellDefinition(spellId)
        
        if spell then
            local payload = BuildHudSpellPayload(spellId, position, spell, spellName)
            SendNUIMessage({
                action = 'setSpell',
                position = position,
                spell = payload
            })
            if HUD then
                if not HUD.currentSpells then
                    HUD.currentSpells = {}
                end
                HUD.currentSpells[position] = payload
            end
            
            Wait(50)
        end
    end
end

RestoreActiveSpell = function()
    if not selectedSpellId then
        return
    end
    
    if not HUD then
        return
    end
    
    local position = nil
    for spellId, assignedPosition in pairs(spellKeyAssignments) do
        if spellId == selectedSpellId then
            position = assignedPosition
                break
        end
    end
    
    if position then
        SendNUIMessage({
            action = 'setSelectedSpell',
            position = position,
            spellId = selectedSpellId
        })
    end
end

local function AssignSpellToKey(spellId, keyIndex)
    local currentTime = GetGameTimer()
    if currentTime - lastSpellChange < SPELL_CHANGE_COOLDOWN then
        return false
    end
    
    if keyIndex == 6 then
        local currentPosition = spellKeyAssignments[spellId]
        if currentPosition then
            spellKeyAssignments[spellId] = nil
            SendNUIMessage({
                action = 'setSpell',
                position = currentPosition,
                spell = nil
            })
            PlayConfirmationSound('removed', spellId)
            lib.notify({
                title = 'Grimoire de Sorts',
                description = 'Sort retiré du HUD.',
                type = 'success'
            })
            if selectedSpellId == spellId then
                DeselectActiveSpell()
            end
            SaveSpellKeyAssignments()
            lastSpellChange = currentTime
            return true
        else
            lib.notify({
                title = 'Grimoire de Sorts',
                description = 'Ce sort n\'est pas encore assigné à une position',
                type = 'error'
            })
            
            return false
        end
    end
    
    local keyMapping = {
        [1] = 'top',
        [2] = 'left',
        [3] = 'right',
        [4] = 'center',
        [5] = 'bottom'
    }
    
    local position = keyMapping[keyIndex]
    if not position then
        return false
    end
    
    local currentPosition = spellKeyAssignments[spellId]
    local replacedSpellId = nil
    
    for existingSpellId, existingPosition in pairs(spellKeyAssignments) do
        if existingPosition == position then
            replacedSpellId = existingSpellId
            break
        end
    end
            
    if currentPosition == position then
        lib.notify({
            title = 'Grimoire de Sorts',
            description = 'Ce sort est déjà assigné à cette position',
            type = 'info'
        })
        return false
    end
    
    local cooldownEnabled = IsCooldownEnabledForPlayer(spellId)
    local remainingCooldownTime = nil
    if cooldownEnabled and spellCooldowns[spellId] then
        local now = GetGameTimer()
        local remaining = spellCooldowns[spellId] - now
        if remaining > 0 then
            remainingCooldownTime = remaining
        end
    end
    
    if currentPosition then
        spellKeyAssignments[spellId] = nil
        SendNUIMessage({
            action = 'setSpell',
            position = currentPosition,
            spell = nil
        })
        
        if HUD and HUD.StopCooldown then
            HUD.StopCooldown(spellId, currentPosition)
        end
    end
    
    if replacedSpellId then
        spellKeyAssignments[replacedSpellId] = nil
        SendNUIMessage({
            action = 'setSpell',
            position = position,
            spell = nil
        })
        
        if HUD and HUD.StopCooldown then
            HUD.StopCooldown(replacedSpellId, position)
        end
        if spellCooldowns[replacedSpellId] then
            spellCooldowns[replacedSpellId] = nil
        end
    end
    
    Wait(100)
    
    spellKeyAssignments[spellId] = position
    PlayConfirmationSound('assigned', spellId)
    
    UpdateSingleSpellInHUD(spellId, position)

    local shouldUpdateSelected = selectedSpellId == replacedSpellId
        or (selectedSpellId == spellId and currentPosition and currentPosition ~= position)

    if shouldUpdateSelected then
        selectedSpellId = spellId
        lastSpellInteractionAt = GetGameTimer()
        SetResourceKvp('dvr_power:last_active_spell', selectedSpellId)

        SendNUIMessage({
            action = 'setSelectedSpell',
            position = position,
            spellId = spellId
        })

        if HUD then
            HUD.lastSelectedSpellId = spellId
            if HUD.SetActiveSpell then
                HUD.SetActiveSpell(position)
            end
        end
    end
    
    if remainingCooldownTime and remainingCooldownTime > 0 then
        local duration = remainingCooldownTime / 1000
        local newEndTime = GetGameTimer() + remainingCooldownTime
        spellCooldowns[spellId] = newEndTime
        
        if cooldownEnabled and HUD and HUD.StartCooldown then
            HUD.StartCooldown(spellId, duration, position)
        end
    end
    
    SaveSpellKeyAssignments()
    lastSpellChange = currentTime
    
    local message = ('Sort "%s" assigné à la position %s (Touche %s)')
        :format(GetSpellName(spellId), position, POSITION_TO_KEY[position] or '?')
    
    if replacedSpellId and currentPosition then
        message = message .. '\nSort "' .. GetSpellName(replacedSpellId) .. '" déplacé vers la position ' .. currentPosition
    elseif replacedSpellId then
        message = message .. '\nSort "' .. GetSpellName(replacedSpellId) .. '" retiré'
    end
    
    return true
end

RegisterNetEvent('dvr_power:loadSpells', function(spellList, levels) 
    playerSpells = spellList or {}
    playerSpellLevels = {}
    if levels then
        for spellId, lvl in pairs(levels) do
            playerSpellLevels[spellId] = ClampLevelForSpell(spellId, lvl)
        end
    end
    playerSpellSet = {}
    for _, spellId in ipairs(playerSpells) do
        playerSpellSet[spellId] = true
        if playerSpellLevels[spellId] == nil then
            playerSpellLevels[spellId] = ClampLevelForSpell(spellId, GetDefaultSpellLevel(spellId))
        end
    end
    hasLoadedPlayerSpells = true

    CleanupHudAssignments()
    
    Wait(1000)
    LoadSpellKeyAssignmentsFromCache()
    
    if selectedSpellId then
        Wait(500)
        RestoreActiveSpell()
    end
end)

RegisterNetEvent('dvr_power:loadSpellKeys', function(assignments)
    Wait(500)
    LoadSpellKeyAssignmentsFromCache()
    
    if isInitialLoad then
        UpdateHUD()
        
        Wait(300)

        if selectedSpellId then
            RestoreActiveSpell()
            
            SetTimeout(1000, function()
                LoadCooldownsFromCache()
            end)
        else
            LoadCooldownsFromCache()
        end
        
        isInitialLoad = false
    end
end)

RegisterNetEvent('dvr_power:removeSpellFromHUD', function(spellId, position)
    if not spellId then return end
    
    if not position then
        for sid, pos in pairs(spellKeyAssignments) do
            if sid == spellId then
                position = pos
                break
            end
        end
    end
    
    if not position then
        return
    end
    
    spellKeyAssignments[spellId] = nil
    if HUD and HUD.currentSpells then
        HUD.currentSpells[position] = nil
    end
    
    SendNUIMessage({
        action = 'setSpell',
        position = position,
        spell = nil
    })

    if selectedSpellId == spellId then
        DeselectActiveSpell()
    end

    SaveSpellKeyAssignments()
end)

RegisterNetEvent('dvr_power:unregisterModule', function(moduleName)
    local moduleData = externalModules[moduleName]
    if not moduleData then
        return
    end

    local removedSpellIds = {}

    if moduleData.spells then
        for _, spell in ipairs(moduleData.spells) do
            if spell.id then
                Config.Spells[spell.id] = nil
                table.insert(removedSpellIds, spell.id)
            end
        end
    elseif moduleData.id then
        Config.Spells[moduleData.id] = nil
        table.insert(removedSpellIds, moduleData.id)
    end

    RemoveModuleSpells(moduleName)

    for _, spellId in ipairs(removedSpellIds) do
        for i = #playerSpells, 1, -1 do
            if playerSpells[i] == spellId then
                table.remove(playerSpells, i)
            end
        end

        playerSpellSet[spellId] = nil

        RemoveAssignmentsForSpell(spellId)
    end

    local wasSelected = false
    for _, spellId in ipairs(removedSpellIds) do
        if spellId == selectedSpellId then
            wasSelected = true
            break
        end
    end
    
    externalModules[moduleName] = nil
    
    if wasSelected then
        selectedSpellId = nil
        lastSpellInteractionAt = 0
        for _, spellId in ipairs(playerSpells) do
            local spell <const> = Config.Spells[spellId]
            if spell and spell.isBasic then
                selectedSpellId = spellId
                lastSpellInteractionAt = GetGameTimer()
                break
            end
        end
    end
end)

RegisterNetEvent('dvr_power:registerModule', function(moduleData)
    if externalModules[moduleData.name] then
        return
    end

    moduleData.__origin = moduleData.__origin or 'server'
    externalModules[moduleData.name] = moduleData
    IndexModuleSpells(moduleData.name, moduleData, moduleData.__origin)
    
    local spellsToProcess = {}
    local skipSpells = moduleData.keys ~= nil and moduleData.keys ~= ''
    
    if moduleData.spells then
        for _, spell in ipairs(moduleData.spells) do
            table.insert(spellsToProcess, spell)
        end
    elseif moduleData.id then
        table.insert(spellsToProcess, moduleData)
    end
    
    for _, spell in ipairs(spellsToProcess) do
        if not skipSpells and not Config.Spells[spell.id] then
            Config.Spells[spell.id] = {
                name = spell.name,
                description = spell.description,
                color = spell.color or 'white',
                cooldown = spell.cooldown or 5000,
                type = spell.type or 'attack',
                selfCast = spell.selfCast or false,
                castTime = spell.castTime or 2000,
                sound = spell.sound or '',
                animation = spell.animation or nil,
                effect = spell.effect or {},
                keys = spell.keys or nil,
                image = spell.image or nil,
                icon = spell.icon or nil,
                video = spell.video or spell.previewVideo or nil,
                soundType = spell.soundType or spell.soundtype or nil,
                hidden = spell.hidden == true,
                isWand = spell.isWand,
                requiresWand = spell.isWand ~= false,
                professor = spell.professor,
                noWandTrail = spell.noWandTrail
            }
            
            if spell.keys then
                lib.addKeybind({
                    name = 'spell_' .. spell.id,
                    description = spell.name,
                    defaultKey = spell.keys,
                    onPressed = function()
                        if not isCasting and not (HUD and HUD.needsLocked) then
                            TriggerEvent('dvr_power:castSpellByKey', spell.id)
                        elseif HUD and HUD.needsLocked then
                            PlayEchecSound(spell.id)
                        end
                    end
                })
            end
        end
    end
end)

local function HasWandEquipped()
    local weapon = cache.weapon
    local wandHash = GetHashKey(Config.WandWeapon)
    local isEquipped = weapon == wandHash
    return isEquipped
end

local function SpellRequiresWand(spellId)
    if not spellId then
        return true
    end

    local spell = GetSpellDefinition(spellId)
    if not spell then
        return false
    end

    if spell.isWand == false or spell.requiresWand == false then
        return false
    end

    return true
end

local function HasRequiredWand(spellId)
    if not SpellRequiresWand(spellId) then
        return true
    end
    return HasWandEquipped()
end

local function CreateSpellParticle(coords, spellColor, intensity)
    local color = Config.SpellColors[spellColor] or Config.SpellColors.white
    local power = intensity or 1.0
    local range = 5.0 * power
    local brightness = 10.0 * power
    DrawLightWithRange(coords.x, coords.y, coords.z, color.r, color.g, color.b, range, brightness)
end

local function GetCurrentJobName()
    if cache and cache.job and cache.job.name then
        return cache.job.name
    end

    local playerData = ESX and (ESX.PlayerData or (ESX.GetPlayerData and ESX.GetPlayerData()))
    local job = playerData and playerData.job
    if job and job.name then
        return job.name
    end

    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.job then
        local stateJob = LocalPlayer.state.job
        if type(stateJob) == 'table' and stateJob.name then
            return stateJob.name
        elseif type(stateJob) == 'string' then
            return stateJob
        end
    end

    return nil
end

local function IsEsxPlayerLoaded()
    if ESX and ESX.IsPlayerLoaded and ESX.IsPlayerLoaded() then
        return true
    end

    local playerData = ESX and (ESX.PlayerData or (ESX.GetPlayerData and ESX.GetPlayerData()))
    if playerData and playerData.job then
        return true
    end

    return false
end

local function NormalizeTrailComponent(value)
    -- Accept normalized 0-1 or 0-255 color values
    if value == nil then
        return nil
    end

    if value > 1.0 then
        return math_min(1.0, value / 255.0)
    end

    return math_max(value, 0.0)
end

local function ResolveTrailColor(jobName)
    local jobColors = Config.JobTrailColors
    local normalizedJob = jobName and string_lower(jobName)
    local color = jobColors and ((normalizedJob and jobColors[normalizedJob]) or jobColors.default) or nil
    if not color then
        return WAND_TRAIL_COLOR
    end

    local normalized = {
        r = NormalizeTrailComponent(color.r),
        g = NormalizeTrailComponent(color.g),
        b = NormalizeTrailComponent(color.b)
    }

    return {
        r = normalized.r or WAND_TRAIL_COLOR.r,
        g = normalized.g or WAND_TRAIL_COLOR.g,
        b = normalized.b or WAND_TRAIL_COLOR.b
    }
end

local function ApplyWandTrailColor(jobName)
    local color = ResolveTrailColor(jobName)
    WAND_TRAIL_COLOR.r = color.r
    WAND_TRAIL_COLOR.g = color.g
    WAND_TRAIL_COLOR.b = color.b

    for _, variant in pairs(WAND_TRAIL_VARIANTS) do
        variant.color = WAND_TRAIL_COLOR
    end
end

local lastTrailJobName = nil

local function RefreshWandTrailColor(force, overrideJobName)
    local jobName = overrideJobName or GetCurrentJobName()
    local normalizedJob = jobName and string_lower(jobName)
    local lastNormalized = lastTrailJobName and string_lower(lastTrailJobName) or nil

    if not force and lastNormalized and normalizedJob and lastNormalized == normalizedJob then
        return
    end

    lastTrailJobName = jobName or lastTrailJobName
    ApplyWandTrailColor(jobName)
    print(('[dvr_power] wand trail job=%s color=%.2f %.2f %.2f'):format(
        tostring(jobName or 'nil'),
        WAND_TRAIL_COLOR.r,
        WAND_TRAIL_COLOR.g,
        WAND_TRAIL_COLOR.b
    ))
end

CreateThread(function()
    while true do
        if IsEsxPlayerLoaded() then
            RefreshWandTrailColor()
        end
        Wait(1000)
    end
end)

local function StopFxHandleList(handles)
    if not handles then
        return
    end

    for _, handle in ipairs(handles) do
        StopParticleFxLooped(handle, false)
        RemoveParticleFx(handle, false)
    end
end

local function StopWandFx(ped)
    local entry = wandFxHandles[ped]
    if not entry then
        return
    end

    if entry.precastHandles then
        StopFxHandleList(entry.precastHandles)
    end
    if entry.castHandles then
        StopFxHandleList(entry.castHandles)
    end

    if entry.handles then
        StopFxHandleList(entry.handles)
    elseif entry.handle then
        StopFxHandleList({ entry.handle })
    end

    wandFxHandles[ped] = nil
end

local function StartTrailHandles(ped, variant, boneIndex, weaponEntity)
    local handles = {}
    local offset = variant.offset or { x = 0.1, y = 0.0, z = 0.02 }
    local scale = variant.scale or 1.0
    local alpha = variant.alpha or 200.0

    UseParticleFxAsset(variant.dict)
    UseParticleFxAssetNextCall(variant.dict)
    local handle
    if weaponEntity and DoesEntityExist(weaponEntity) then
        handle = StartNetworkedParticleFxLoopedOnEntity(
            variant.particle,
            weaponEntity,
            offset.x,
            offset.y,
            offset.z,
            0.0,
            0.0,
            0.0,
            scale,
            false,
            false,
            false
        )
    else
        handle = StartParticleFxLoopedOnEntityBone(
            variant.particle,
            ped,
            offset.x,
            offset.y,
            offset.z,
            0.0,
            0.0,
            0.0,
            boneIndex,
            scale,
            false,
            false,
            false
        )
    end

    if handle ~= 0 then
        SetParticleFxLoopedEvolution(handle, 'speed', variant.speed or 1.0, false)
        SetParticleFxLoopedColour(handle, variant.color.r, variant.color.g, variant.color.b, false)
        SetParticleFxLoopedAlpha(handle, alpha)
        handles[#handles + 1] = handle
    end

    return handles
end

local function PlayWandFx(ped, duration)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return
    end

    RefreshWandTrailColor(false)

    StopWandFx(ped)
    local wandDuration = duration
    if not wandDuration or wandDuration <= 0 then
        wandDuration = 2000
    end

    local variant = WAND_TRAIL_VARIANTS.precast
    if not HasNamedPtfxAssetLoaded(variant.dict) then
        RequestNamedPtfxAsset(variant.dict)
        local timeout = GetGameTimer() + 3000
        while not HasNamedPtfxAssetLoaded(variant.dict) and GetGameTimer() < timeout do
            Wait(0)
        end
    end

    if not HasNamedPtfxAssetLoaded(variant.dict) then
        return
    end

    local boneIndex = GetPedBoneIndex(ped, WAND_BONE_INDEX)
    local weaponEntity = GetCurrentPedWeaponEntityIndex(ped)
    if (not boneIndex or boneIndex <= 0) and (not weaponEntity or weaponEntity == 0) then
        return
    end

    local precastHandles = StartTrailHandles(ped, variant, boneIndex, weaponEntity)
    if not precastHandles or #precastHandles == 0 then
        return
    end

    local now = GetGameTimer()
    local fxId = now
    local expiry = now + wandDuration + WAND_TRAIL_LINGER
    local castVariant = WAND_TRAIL_VARIANTS.cast

    wandFxHandles[ped] = {
        id = fxId,
        expires = expiry,
        precastHandles = precastHandles
    }

    local castDelay = math.max(200, wandDuration - WAND_CAST_EXTENSION_LEAD)

    CreateThread(function()
        Wait(castDelay)
        local entry = wandFxHandles[ped]
        if not entry or entry.id ~= fxId then
            return
        end

        StopFxHandleList(entry.precastHandles)
        entry.precastHandles = nil

        if not HasNamedPtfxAssetLoaded(castVariant.dict) then
            RequestNamedPtfxAsset(castVariant.dict)
            local deadline = GetGameTimer() + 1500
            while not HasNamedPtfxAssetLoaded(castVariant.dict) and GetGameTimer() < deadline do
                Wait(0)
            end
        end

        if not HasNamedPtfxAssetLoaded(castVariant.dict) then
            return
        end

        entry.castHandles = StartTrailHandles(ped, castVariant, boneIndex, weaponEntity)
    end)

    CreateThread(function()
        local remaining = expiry - GetGameTimer()
        if remaining > 0 then
            Wait(remaining)
        end

        if wandFxHandles[ped] and wandFxHandles[ped].id == fxId then
            StopWandFx(ped)
        end
    end)
end

CreateThread(function()
    while true do
        Wait(1000)
        local now = GetGameTimer()
        for ped, entry in pairs(wandFxHandles) do
            if entry and entry.expires and now >= entry.expires then
                StopWandFx(ped)
            end
        end
    end
end)

local function ApplyAnimSpeedMultiplier(ped, spellId, animation, attempts, interval)
    if not ped or not animation or not animation.dict or not animation.name then
        return
    end

    local multiplier = animation.speedMultiplier
    if spellId == 'mortalis' then
        multiplier = multiplier or 1.5
    end

    if not multiplier or multiplier <= 0 then
        return
    end

    attempts = attempts or 3
    interval = interval or 80

    if lib and lib.requestAnimDict then
        lib.requestAnimDict(animation.dict)
    end

    CreateThread(function()
        for i = 1, attempts do
            SetEntityAnimSpeed(ped, animation.dict, animation.name, multiplier)
            if i < attempts then
                Wait(interval)
            end
        end
    end)
end

local function CastSpell(spellId)
    if isCasting then
        return
    end

    local stateLocked, lockReason = IsCastingLockedByState()
    if stateLocked then
        PlayEchecSound(spellId)
        local now = GetGameTimer()
        if (now - lastStateLockNotify) >= 2000 then
            lastStateLockNotify = now
            lib.notify({
                title = 'Sort bloqué',
                description = lockReason or 'Vous êtes staturisé, impossible de lancer un sort.',
                type = 'error',
                icon = 'snowflake'
            })
        end
        return
    end

    if HUD and HUD.needsLocked then
        PlayEchecSound(spellId)
        local now = GetGameTimer()
        if (now - lastNeedsLockNotify) >= 3000 then
            lastNeedsLockNotify = now
        end
        return
    end
    
    local vehicle = IsPedInAnyVehicle(cache.ped)
    if vehicle then
        PlayEchecSound(spellId)
        return
    end
    
    local spell, moduleEntry = GetSpellDefinition(spellId)
    if not spell then return end
    
    local hasRequiredWand = HasRequiredWand(spellId)
    if not hasRequiredWand then
        PlayEchecSound(spellId)
        return
    end
    
    if not playerSpellSet[spellId] then
        PlayEchecSound(spellId)
        return
    end

    local cooldownEnabled = IsCooldownEnabledForPlayer(spellId)
    local now = GetGameTimer()

    if not cooldownEnabled and now < castLockUntil then
        PlayEchecSound(spellId)
        return
    end

    if cooldownEnabled and spellCooldowns[spellId] and now < spellCooldowns[spellId] then
        PlayEchecSound(spellId)
        local position = spellKeyAssignments[spellId]
        if position then
            SendNUIMessage({
                action = 'cooldownBlocked',
                id = 'spell-' .. position
            })
        end
        return
    end

    local localLevel = GetSpellLevel(spellId)
    local muteSound = ShouldMuteSoundForLevel(spellId, localLevel)
    local adjustedCooldown = cooldownEnabled and CalculateCooldownForLevel(spellId) or 0
    
    isCasting = true
    selectedSpellId = spellId
    lastSpellInteractionAt = now
    
    SetResourceKvp('dvr_power:last_active_spell', selectedSpellId)

    local position = spellKeyAssignments[spellId]
    
    if position then
        HUD.VibrateSpell(position)
    end
    
    SaveSpellKeyAssignments()

    local coords = GetEntityCoords(cache.ped)
    local targetServerId = -1
    
    if spell.selfCast then
        targetServerId = GetPlayerServerId(PlayerId())
    else
        local hit, entityHit, hitCoords = lib.raycast.cam(1 | 2 | 4 | 8 | 16, 4, 100)
        
        if hit and entityHit and IsEntityAPed(entityHit) and IsPedAPlayer(entityHit) then
            local players <const> = GetActivePlayers()
            for _, player in ipairs(players) do
                if GetPlayerPed(player) == entityHit then
                    targetServerId = GetPlayerServerId(player)
                    break
                end
            end
        end
        
        if hitCoords then
            coords = hitCoords
        end
    end
    
    if spell.sound and spell.sound ~= '' and not muteSound then
        TriggerServerEvent('dvr_power:playSpellSound', spellId, coords)
    end

    TriggerServerEvent('dvr_power:castSpell', spellId, coords, targetServerId)
    if not cooldownEnabled then
        local castDuration = spell.castTime or (spell.animation and spell.animation.duration) or 800
        if castDuration < 400 then
            castDuration = 400
        end
        castLockUntil = GetGameTimer() + castDuration
    end
    
    if spell.animation and spell.selfCast then
        lib.requestAnimDict(spell.animation.dict)
        local animDuration = spell.animation.duration or spell.effect.shieldDuration or 2000
        TaskPlayAnim(cache.ped, spell.animation.dict, spell.animation.name, 8.0, -8.0, animDuration, spell.animation.flag, 0, false, false, false)
        ApplyAnimSpeedMultiplier(cache.ped, spellId, spell.animation)
    end
    
    if spell.animation and not spell.selfCast and spell.animation.duration then
        lib.requestAnimDict(spell.animation.dict)
        Wait(100)
        TaskPlayAnim(cache.ped, spell.animation.dict, spell.animation.name, 8.0, -8.0, spell.animation.duration, spell.animation.flag, 0, false, false, false)
        ApplyAnimSpeedMultiplier(cache.ped, spellId, spell.animation)
    end
    
    if spell.animation and not spell.selfCast and not spell.animation.duration then
        lib.requestAnimDict(spell.animation.dict)
        TaskPlayAnim(cache.ped, spell.animation.dict, spell.animation.name, 8.0, -8.0, spell.castTime, spell.animation.flag, 0, false, false, false)
        ApplyAnimSpeedMultiplier(cache.ped, spellId, spell.animation)
    end
    
    if moduleEntry and moduleEntry.spell and moduleEntry.origin == 'client' then
        local raycastData <const> = {
            hit = false,
            entityHit = nil,
            hitCoords = coords,
            targetServerId = targetServerId
        }

        if not spell.selfCast then
            local hit, entityHit, hitCoords = lib.raycast.cam(1 | 2 | 4 | 8 | 16, 4, 100)
            raycastData.hit = hit
            raycastData.entityHit = entityHit
            raycastData.hitCoords = hitCoords or coords
        end
        
        local source <const> = GetPlayerServerId(PlayerId())
        local target <const> = targetServerId
        
        if type(moduleEntry.spell.onCast) == 'function' then
            moduleEntry.spell.onCast(hasRequiredWand, raycastData, source, target)
        end
    end

    if cooldownEnabled and adjustedCooldown > 0 then
        spellCooldowns[spellId] = GetGameTimer() + adjustedCooldown
        SaveCooldownsToCache()
        
        local hudPosition = GetHudPositionForSpell(spellId)
        if hudPosition then
            local cooldownDuration = adjustedCooldown / 1000
            if cooldownDuration < 0.1 then
                cooldownDuration = 0.5
            end
            HUD.StartCooldown(spellId, cooldownDuration, hudPosition)
        end
    else
        spellCooldowns[spellId] = nil
    end
    
    isCasting = false
end

local function OpenSpellMenu()
    local playerSpellSet = {}
    for _, spellId in ipairs(playerSpells) do
        playerSpellSet[spellId] = true
    end
    
    local spells = {}
    for spellId, spell in pairs(Config.Spells) do
        if spell and not spell.keys then
            local isAvailable = playerSpellSet[spellId] == true
            table.insert(spells, {
                id = spellId,
                name = spell.name,
                description = spell.description or '',
                icon = spell.image or spell.icon or '',
                image = spell.image or spell.icon or '',
                video = spell.video or '',
                type = spell.type or 'utility',
                color = spell.color or 'white',
                available = isAvailable
            })
        end
    end
    table.sort(spells, function(a, b)
        local an = string_lower(a.name or a.id or '')
        local bn = string_lower(b.name or b.id or '')
        if an == bn then
            return string_lower(a.id or '') < string_lower(b.id or '')
        end
        return an < bn
    end)
    
    local assignments = {}
    for spellId, position in pairs(spellKeyAssignments) do
        local spell = GetSpellDefinition(spellId)
        if spell then
            local payload = BuildHudSpellPayload(spellId, position, spell, GetSpellName(spellId))
            assignments[position] = payload
        end
    end
    
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openSpellSelector',
        spells = spells,
        assignments = assignments
    })
end

local function IsSpellSystemReady()
    if not ESX or not ESX.IsPlayerLoaded or not ESX.IsPlayerLoaded() then
        return false, 'Le système de sorts est en cours de chargement...'
    end
    
    if not HUD then
        return false, 'Le système de sorts est en cours de chargement...'
    end
    
    if not HUD.initialized then
        return false, 'Le système de sorts est en cours de chargement...'
    end
    
    if not HUD.nuiReady then
        return false, 'Le système de sorts est en cours de chargement...'
    end
    
    if not hasLoadedPlayerSpells then
        return false, 'Le système de sorts est en cours de chargement...'
    end
    
    return true, nil
end

RegisterCommand('spellmenu', function()
    local isReady, errorMessage = IsSpellSystemReady()
    if not isReady then
        lib.notify({
            title = 'Grimoire de Sorts',
            description = errorMessage or 'Le système de sorts est en cours de chargement...',
            type = 'error'
        })
        return
    end
    
    if HUD and HUD.stats and HUD.stats.hunger > 0 and HUD.stats.thirst > 0 then
        OpenSpellMenu()
    else
        lib.notify({
            title = 'Grimoire de Sorts',
            description = 'Vous devez manger et boire pour ouvrir le grimoire.',
            type = 'error'
        })
    end
end, false)

RegisterNetEvent('dvr_power:assignSpellToKey', function(spellId, keyIndex)
    AssignSpellToKey(spellId, keyIndex)
end)

local HUD_SLOT_KEYS <const> = {
    { position = 'left', key = '6', control = 159 },    -- INPUT_SELECT_WEAPON_HANDGUN (6)
    { position = 'top', key = '7', control = 161 },     -- INPUT_SELECT_WEAPON_SMG (7)
    { position = 'center', key = 'H', control = 104 }, -- INPUT_CHARACTER_WHEEL (J)
    { position = 'right', key = '9', control = 163 },   -- INPUT_SELECT_WEAPON_SNIPER (9)
    { position = 'bottom', key = '8', control = 162 }   -- INPUT_SELECT_WEAPON_AUTO_RIFLE (8)
}

local HUD_SLOT_POSITIONS <const> = { 'top', 'left', 'center', 'right', 'bottom' }

local function CanUseHotkeyInputs()
    local ped = cache and cache.ped
    local pedLocked = IsPedUnableToCast(ped)

    return not isCasting
        and not IsPauseMenuActive()
        and not IsScreenFadedOut()
        and not IsScreenFadingOut()
        and not IsScreenFadingIn()
        and not IsNuiFocused()
        and not pedLocked
        and not (HUD and HUD.needsLocked)
end

local function CanUseSpellHotkeys(spellId)
    if not CanUseHotkeyInputs() then
        return false
    end

    if spellId and not HasRequiredWand(spellId) then
        return false
    end

    return true
end

local function GetAssignedSpellsInOrder()
    local ordered = {}
    for _, position in ipairs(HUD_SLOT_POSITIONS) do
        for spellId, assignedPosition in pairs(spellKeyAssignments) do
            if assignedPosition == position then
                ordered[#ordered + 1] = { id = spellId, position = position }
                break
            end
        end
    end
    return ordered
end

local function CycleSelectedSpell(step)
    if not CanUseHotkeyInputs() then
        return
    end

    local assigned = GetAssignedSpellsInOrder()
    local count = #assigned
    if count == 0 then
        return
    end

    local currentIndex = nil
    for i = 1, count do
        if assigned[i].id == selectedSpellId then
            currentIndex = i
            break
        end
    end

    local nextIndex
    if currentIndex then
        nextIndex = ((currentIndex - 1 + step) % count) + 1
    else
        nextIndex = step > 0 and 1 or count
    end

    local target = assigned[nextIndex]
    if not target then
        return
    end

    selectedSpellId = target.id
    lastSpellInteractionAt = GetGameTimer()
    SetResourceKvp('dvr_power:last_active_spell', selectedSpellId)

    SendNUIMessage({
        action = 'setSelectedSpell',
        position = target.position,
        spellId = target.id
    })

    if HUD then
        HUD.lastSelectedSpellId = selectedSpellId
        if HUD.SetActiveSpell then
            HUD.SetActiveSpell(target.position)
        end
        if HUD.VibrateSpell then
            HUD.VibrateSpell(target.position)
        end
    end

    SaveSpellKeyAssignments()
end

local function HandleHudSlotPress(position)
    if not CanUseHotkeyInputs() then
        return
    end

    local assignedSpellId = nil
    for spellId, assignedPosition in pairs(spellKeyAssignments) do
        if assignedPosition == position then
            assignedSpellId = spellId
            break
        end
    end

    if not assignedSpellId then
        return
    end

    if selectedSpellId == assignedSpellId then
        DeselectActiveSpell()
    else
        selectedSpellId = assignedSpellId
        lastSpellInteractionAt = GetGameTimer()
        SetResourceKvp('dvr_power:last_active_spell', selectedSpellId)
        SendNUIMessage({
            action = 'setSelectedSpell',
            position = position,
            spellId = assignedSpellId
        })

        if HUD then
            HUD.lastSelectedSpellId = assignedSpellId
            if HUD.SetActiveSpell then
                HUD.SetActiveSpell(position)
            end
        end
    end

    if HUD and HUD.VibrateSpell then
        HUD.VibrateSpell(position)
    end
    SaveSpellKeyAssignments()
end

CreateThread(function()
    while true do
        Wait(0)

        local canUseHotkeys = CanUseHotkeyInputs()
        local canUseSelected = selectedSpellId and CanUseSpellHotkeys(selectedSpellId)

        if IsDisabledControlJustPressed(0, 24) and canUseSelected and IsControlPressed(0, INPUT_PUSH_TO_TALK) then
            local cooldownEnabled = IsCooldownEnabledForPlayer(selectedSpellId)
            local onCooldown = cooldownEnabled and spellCooldowns[selectedSpellId] and GetGameTimer() < spellCooldowns[selectedSpellId]
            if not onCooldown and SpellRequiresWand(selectedSpellId) then
                PlayLeftClickSound()
            end
        end

        if canUseHotkeys then
            if IsDisabledControlJustPressed(0, 241) then -- mouse wheel up
                CycleSelectedSpell(1)
            elseif IsDisabledControlJustPressed(0, 242) then -- mouse wheel down
                CycleSelectedSpell(-1)
            end

            if IsDisabledControlJustPressed(0, 24) and canUseSelected then
                if selectedSpellId == 'transvalis' and LocalPlayer and LocalPlayer.state and LocalPlayer.state.transvalisActive then
                    TriggerEvent('dvr_transvalis:cancelRequested')
                elseif HUD and HUD.needsLocked then
                    PlayEchecSound(selectedSpellId)
                elseif not IsControlPressed(0, INPUT_PUSH_TO_TALK) then
                    PlayEchecSound(selectedSpellId)
                else
                    CastSpell(selectedSpellId)
                end
            end

            for _, slot in ipairs(HUD_SLOT_KEYS) do
                if IsDisabledControlJustPressed(0, slot.control) then
                    HandleHudSlotPress(slot.position)
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(5000)

        if selectedSpellId and lastSpellInteractionAt > 0 then
            local now = GetGameTimer()
            if (now - lastSpellInteractionAt) >= SPELL_INACTIVITY_TIMEOUT then
                if DeselectActiveSpell() then
                    SaveSpellKeyAssignments()
                end
            end
        end
    end
end)

RegisterNetEvent('dvr_power:spellCast', function(sourceId, spellId, targetCoords, level)
    local spell = GetSpellDefinition(spellId)
    if not spell then return end
    local myServerId = GetPlayerServerId(PlayerId())
    local isLocalCaster = myServerId == sourceId
    local castLevel = level or GetDefaultSpellLevel(spellId)
    local quality = GetQualityForLevel(spellId, castLevel)

    CacheSpellLevelInfo(sourceId, spellId, castLevel, quality)
    
    if isLocalCaster and spell.effect.particle then
        CreateSpellParticle(targetCoords, spell.color, quality)
    end
    
    local casterPed <const> = GetPlayerPed(GetPlayerFromServerId(sourceId))
    if casterPed and casterPed ~= 0 then
        if spell.animation then
            ApplyAnimSpeedMultiplier(casterPed, spellId, spell.animation, 8, 90)
        end

        local wandFxDuration = (spell.animation and spell.animation.duration) or spell.castTime
        if not wandFxDuration or wandFxDuration <= 0 then
            wandFxDuration = 2000
        end

        if isLocalCaster and SpellRequiresWand(spellId) and not spell.noWandTrail then
            PlayWandFx(casterPed, wandFxDuration)
        end

        if isLocalCaster then
            CreateThread(function()
                for _ = 1, 50 do
                    if DoesEntityExist(casterPed) then
                        local casterCoords = GetEntityCoords(casterPed)
                        CreateSpellParticle(casterCoords + vector3(0, 0, 2.0), spell.color, quality)
                    end
                    Wait(10)
                end
            end)
        end
        
        if spell.effect.props then
            local animDuration = spell.animation and spell.animation.duration or 0
            local propsDelay = animDuration * 0.7
            
            CreateThread(function()
                Wait(propsDelay)
                
                if not DoesEntityExist(casterPed) then return end
                
                local propModel = GetHashKey(spell.effect.props)
                lib.requestModel(propModel, 5000)
                
                local casterCoords = GetEntityCoords(casterPed)
                local rayProp <const> = CreateObject(propModel, casterCoords.x, casterCoords.y, casterCoords.z, false, false, false)
                SetEntityCollision(rayProp, false, false)
                SetEntityAsMissionEntity(rayProp, true, true)
                local propAlpha = math.floor(80 + (175 * quality))
                SetEntityAlpha(rayProp, math.max(50, math.min(255, propAlpha)), false)
                
                local handBone <const> = GetPedBoneIndex(casterPed, 28422)
                local startCoords <const> = GetWorldPositionOfEntityBone(casterPed, handBone)

                local finalTargetCoords
                if targetCoords then
                    finalTargetCoords = vector3(
                        targetCoords.x or startCoords.x,
                        targetCoords.y or startCoords.y,
                        targetCoords.z or startCoords.z
                    )
                else
                    local camCoords <const> = GetGameplayCamCoord()
                    local camRot <const> = GetGameplayCamRot(2)
                    local dir <const> = RotationToDirection(camRot)
                    finalTargetCoords = vector3(
                        camCoords.x + dir.x * 25.0,
                        camCoords.y + dir.y * 25.0,
                        camCoords.z + dir.z * 25.0
                    )
                end

                local direction = vector3(
                    finalTargetCoords.x - startCoords.x,
                    finalTargetCoords.y - startCoords.y,
                    finalTargetCoords.z - startCoords.z
                )
                local distance <const> = #direction
                direction = direction / distance

                local heading <const> = math.deg(math.atan2(direction.y, direction.x)) + 90.0
                local pitch <const> = -math.deg(math.asin(direction.z))
                local roll <const> = 0.0

                SetEntityCoords(rayProp, startCoords.x, startCoords.y, startCoords.z, false, false, false, false)
                SetEntityRotation(rayProp, pitch, roll, heading, 2, true)
                
                local duration <const> = spell.effect.propsDuration or 2000
                local startTime = GetGameTimer()
                local endTime = startTime + duration
                
                spellRayProps[rayProp] = {
                    prop = rayProp,
                    startCoords = startCoords,
                    targetCoords = finalTargetCoords,
                    direction = direction,
                    distance = distance,
                    startTime = startTime,
                    endTime = endTime,
                    speed = distance / (duration / 1000.0),
                    heading = heading,
                    pitch = pitch,
                    roll = roll
                }
                
            end)
        end
    end
end)

RegisterNetEvent('dvr_power:resetAllCooldowns', function()
    spellCooldowns = {}
    
    if HUD and HUD.activeCooldowns then
        HUD.activeCooldowns = {}
    end

    SendNUIMessage({
        action = 'clearAllCooldowns'
    })
    
    DeleteResourceKvp('dvr_power:active_cooldowns')
    
    lib.notify({
        title = 'Cooldowns réinitialisés',
        description = 'Tous vos cooldowns ont été réinitialisés',
        type = 'success',
        duration = 3000
    })
end)

RegisterNetEvent('dvr_power:unlockSpell', function(spellId, level)
    local spell = GetSpellDefinition(spellId)
    if not spell then
        return
    end
    
    for _, existingSpell in ipairs(playerSpells) do
        if existingSpell == spellId then
            return
        end
    end
    
    table.insert(playerSpells, spellId)
    playerSpellSet[spellId] = true
    playerSpellLevels[spellId] = ClampLevelForSpell(spellId, level)
end)

exports('registerModule', function(moduleData)
    local moduleName = moduleData and moduleData.name
    if not moduleName then
        return false
    end

    if externalModules[moduleName] then
        TriggerEvent('dvr_power:unregisterModule', moduleName)
    end

    moduleData.__origin = 'client'
    TriggerEvent('dvr_power:registerModule', moduleData)
    return externalModules[moduleName] ~= nil
end)

exports('unregisterModule', function(moduleName)
    if not externalModules[moduleName] then
        return false
    end

    TriggerEvent('dvr_power:unregisterModule', moduleName)
    return externalModules[moduleName] == nil
end)

exports('getModule', function(moduleName)
    return externalModules[moduleName]
end)

exports('getAllModules', function()
    return externalModules
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    spellCooldowns = {}
    
    for lightId, _ in pairs(activeLights) do
        TriggerEvent('dvr_power:removeLight', lightId)
    end
    activeLights = {}
    
    for propId, data in pairs(spellRayProps) do
        local prop = type(data) == "table" and data.prop or propId
        if DoesEntityExist(prop) then
            SetEntityVisible(prop, false, false)
            DeleteEntity(prop)
            DeleteObject(prop)
        end
    end
    spellRayProps = {}

    for ped, _ in pairs(wandFxHandles) do
        StopWandFx(ped)
    end
    wandFxHandles = {}

    externalSpellIndex = {}
    externalModules = {}
    spellKeyAssignments = {}
    playerSpells = {}
    playerSpellSet = {}
    playerSpellLevels = {}
    spellCastLevelCache = {}
    selectedSpellId = nil
    lastSpellInteractionAt = 0
    castLockUntil = 0
    
    if cache.ped then
        ClearPedTasks(cache.ped)
    end
    
    isCasting = false
end)

RegisterNetEvent('esx:playerLoaded', function(playerData)
    local jobName = playerData and playerData.job and playerData.job.name
    RefreshWandTrailColor(true, jobName)
    if jobName then
        lastTrailJobName = jobName
    end

    if HUD and HUD.ToggleHUD then
        HUD.initialized = false
        HUD.visible = false

        SetTimeout(2000, function()
            if HUD then
                HUD.initialized = true
                HUD.ToggleHUD(true)
            end
        end)
    end
end)

RegisterNetEvent('esx:setJob', function(job)
    RefreshWandTrailColor(true, job and job.name)
    if job and job.name then
        lastTrailJobName = job.name
    end
end)

exports('GetSpell', function(spellId)
    if not spellId then
        return false, 0
    end

    local hasSpell = playerSpellSet[spellId] == true
    local level = GetSpellLevel(spellId)
    return hasSpell, level
end)

exports('GetSpellName', function(spellId)
    return GetSpellName(spellId)
end)

exports('getPlayerSpells', function()
    return playerSpells
end)

exports('getSelectedSpell', function()
    return selectedSpellId
end)

exports('getAllModules', function()
    return externalModules
end)

exports('GetSpellInfo', function(spellId)
    if not spellId then
        return nil
    end

    local spell = GetSpellDefinition(spellId)
    if not spell then
        return nil
    end

    return {
        id = spellId,
        name = spell.name or spellId,
        description = spell.description or '',
        type = spell.type or 'utility',
        color = spell.color or 'white'
    }
end)

exports('getSpellSets', function()
    return GetSpellSetsForNUI()
end)

exports('switchSpellSet', function(setId)
    return SwitchSpellSet(setId)
end)

exports('renameSpellSet', function(setId, newName)
    return RenameSpellSet(setId, newName)
end)

exports('getCurrentSpellSetId', function()
    return currentSpellSetId
end)

RegisterNetEvent('dvr_power:spellRemoved', function(spellId, spellName)
    local position = GetHudPositionForSpell(spellId)

    if position then
        spellKeyAssignments[spellId] = nil
        SendNUIMessage({
            action = 'setSpell',
            position = position,
            spell = nil
        })
        SaveSpellKeyAssignments()
    end
    
    if selectedSpellId == spellId then
        selectedSpellId = nil
        lastSpellInteractionAt = 0
        DeleteResourceKvp('dvr_power:last_active_spell')
    end
    
    if spellCooldowns[spellId] then
        if HUD and HUD.StopCooldown and position then
            HUD.StopCooldown(spellId, position)
        end
        
        spellCooldowns[spellId] = nil
        SaveCooldownsToCache()
    end

    for i = #playerSpells, 1, -1 do
        if playerSpells[i] == spellId then
            table.remove(playerSpells, i)
        end
    end
    playerSpellSet[spellId] = nil
    playerSpellLevels[spellId] = nil
end)

local function ResolvePedFromServerId(serverId)
    if not serverId then
        return nil
    end

    local myServerId = GetPlayerServerId(PlayerId())
    if serverId == myServerId then
        return cache.ped
    end

    local playerIndex = GetPlayerFromServerId(serverId)
    if not playerIndex or playerIndex == -1 then
        return nil
    end

    local ped = GetPlayerPed(playerIndex)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        return ped
    end
    return nil
end

local function PlayFxOnPed(ped, fxConfig)
    if not ped or ped == 0 then
        return
    end

    local dict = fxConfig.particle_dict or 'core'
    local particle = fxConfig.particle_name or 'ent_amb_smoke_factory'
    local scale = fxConfig.scale or 1.0
    local duration = fxConfig.duration or 1500

    if not HasNamedPtfxAssetLoaded(dict) then
        RequestNamedPtfxAsset(dict)
        local endTime = GetGameTimer() + 5000
        while not HasNamedPtfxAssetLoaded(dict) and GetGameTimer() < endTime do
            Wait(0)
        end
    end

    if not HasNamedPtfxAssetLoaded(dict) then
        return
    end

    UseParticleFxAssetNextCall(dict)
    local boneIndex = GetPedBoneIndex(ped, 57005)
    local handle = StartParticleFxLoopedOnEntityBone(particle, ped, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, boneIndex, scale, false, false, false)

    if handle == 0 then
        RemoveNamedPtfxAsset(dict)
        return
    end

    SetParticleFxLoopedAlpha(handle, 0.8)

    if duration > 0 then
        CreateThread(function()
            Wait(duration)
            StopParticleFxLooped(handle, false)
            RemoveNamedPtfxAsset(dict)
        end)
    end
end

RegisterNetEvent('dvr_power:spellTrainingEffect', function(casterId, spellId, level)
    local ped = ResolvePedFromServerId(casterId)
    if not ped then
        return
    end

    local fxConfig = (Config.Leveling and Config.Leveling.training_fx) or {}
    PlayFxOnPed(ped, fxConfig)

    if casterId == GetPlayerServerId(PlayerId()) then
        lib.notify({
            title = 'Sort instable',
            description = ('%s ne produit qu\'une fumée timide...'):format(GetSpellName(spellId)),
            type = 'warning',
            icon = 'cloud'
        })
    end
end)

RegisterNetEvent('dvr_power:spellBackfire', function(casterId, spellId, level)
    local ped = ResolvePedFromServerId(casterId)
    if not ped then
        return
    end

    local fxConfig = (Config.Leveling and Config.Leveling.backfire_fx) or (Config.Leveling and Config.Leveling.training_fx) or {}
    PlayFxOnPed(ped, fxConfig)

    if casterId == GetPlayerServerId(PlayerId()) then
        SetPedToRagdoll(ped, 1500, 2000, 0, false, false, false)
        lib.notify({
            title = 'Retour de flamme',
            description = ('%s se retourne contre vous !'):format(GetSpellName(spellId)),
            type = 'error',
            icon = 'skull-crossbones'
        })
    end
end)

RegisterNetEvent('dvr_power:updateSpellLevel', function(spellId, level)
    if not spellId then
        return
    end

    playerSpellLevels[spellId] = ClampLevelForSpell(spellId, level)

    if playerSpellSet[spellId] then
        local position = GetHudPositionForSpell(spellId)
        if position then
            UpdateSingleSpellInHUD(spellId, position)
        end
    end
end)

RegisterNetEvent('dvr_power:hideHUD', function()
    SaveCooldownsToCache()
    
    if HUD and HUD.Destroy then
        HUD.Destroy()
    end
    
    playerSpells = {}
    playerSpellSet = {}
    playerSpellLevels = {}
    selectedSpellId = nil
    lastSpellInteractionAt = 0
    spellKeyAssignments = {}
    spellCastLevelCache = {}
end)

CreateThread(function()
    while true do
        Wait(500)
        
        for soundId, handle in pairs(activeSpellSounds) do
            -- REPLACE WITH YOUR SOUND SYSTEM
            local isPlaying = false
            -- pcall(function()
            --     if handle and type(handle.isPlaying) == 'function' then
            --         isPlaying = handle:isPlaying()
            --     else
            --         local soundInfo = exports['lo_audio']:getSoundInfo(soundId)
            --         if soundInfo then
            --             isPlaying = soundInfo.playing == true
            --         else
            --             isPlaying = false
            --         end
            --     end
            -- end)

            if not isPlaying then
                -- pcall(function()
                --     exports['lo_audio']:stopSound(soundId)
                -- end)
                activeSpellSounds[soundId] = nil
            end
        end
    end
end)

-- REPLACE WITH YOUR SOUND SYSTEM (sound cleanup thread)
-- CreateThread(function()
--     while true do
--         Wait(1000)
--
--         local allSounds = exports['lo_audio']:getAllSounds()
--         if allSounds then
--             for soundId, soundData in pairs(allSounds) do
--                 if soundData and not soundData.playing then
--                     pcall(function()
--                         exports['lo_audio']:stopSound(soundId)
--                     end)
--                 end
--             end
--         end
--     end
-- end)

-- REPLACE WITH YOUR SOUND SYSTEM (spell sound event handler)
RegisterNetEvent('dvr_power:playSpellSound', function(soundId, soundUrl, coords, spellId)
    if not soundId or not soundUrl or not coords then return end

    local is2D = false
    local castTime = 2000
    if spellId and Config and Config.Spells and Config.Spells[spellId] then
        local moduleData = Config.Spells[spellId]
        if moduleData then
            if moduleData.soundType == "2d" then
                is2D = true
            end
            castTime = moduleData.castTime or 2000
        end
    end
    if spellId == 'mortalis' then
        castTime = 400
    end

    -- pcall(function()
    --     local soundConfig = {
    --         id = soundId,
    --         url = soundUrl,
    --         volume = 1.0,
    --         loop = false,
    --         spatial = not is2D,
    --         castTime = castTime,
    --         distance = 10.0,
    --         category = 'spell'
    --     }
    --
    --     if not is2D then
    --         soundConfig.pos = { x = coords.x, y = coords.y, z = coords.z }
    --     end
    --
    --     SetTimeout(soundConfig.castTime, function()
    --         local handle = exports['lo_audio']:playSound(soundConfig)
    --         activeSpellSounds[soundId] = handle
    --     end)
    -- end)
end)

_ENV.playerSpells = playerSpells
_ENV.selectedSpellId = selectedSpellId
_ENV.externalModules = externalModules
_ENV.spellKeyAssignments = spellKeyAssignments
_ENV.spellCooldowns = spellCooldowns
_ENV.spellCastLevelCache = spellCastLevelCache

local function CanSwitchSpellSet()
    if IsPauseMenuActive() then
        return false
    end
    if IsNuiFocused() then
        return false
    end
    if LocalPlayer.state.isTyping then
        return false
    end
    return true
end

local function SwitchToNextSpellSet()
    if not CanSwitchSpellSet() then
        return
    end
    local newSetId = currentSpellSetId + 1
    if newSetId > MAX_SPELL_SETS then
        newSetId = 1
    end
    if SwitchSpellSet(newSetId) then
        SendNUIMessage({
            action = 'updateSpellSetIndicator',
            setId = newSetId
        })
    end
end

local function SwitchToPrevSpellSet()
    if not CanSwitchSpellSet() then
        return
    end
    local newSetId = currentSpellSetId - 1
    if newSetId < 1 then
        newSetId = MAX_SPELL_SETS
    end
    if SwitchSpellSet(newSetId) then
        SendNUIMessage({
            action = 'updateSpellSetIndicator',
            setId = newSetId
        })
    end
end

RegisterCommand('+spellset_next', SwitchToNextSpellSet, false)
RegisterCommand('-spellset_next', function() end, false)
RegisterCommand('+spellset_prev', SwitchToPrevSpellSet, false)
RegisterCommand('-spellset_prev', function() end, false)

RegisterKeyMapping('+spellset_next', '~g~(SORTS)~w~ Set de sorts suivant', 'keyboard', 'DOWN')
RegisterKeyMapping('+spellset_prev', '~g~(SORTS)~w~ Set de sorts précédent', 'keyboard', 'UP')