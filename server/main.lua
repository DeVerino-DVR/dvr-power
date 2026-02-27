---@diagnostic disable: trailing-space, undefined-global, missing-fields, unused-local, redundant-return-value, deprecated
local HPSystem <const> = require 'server.hp_system'
local LogDiscord <const> = require 'server.logs'
local EnsureDatabaseSchema <const> = require 'server.sql_schema'
local PlayerCache <const> = require 'server.player_cache'
local playerCooldowns = {}
local activeLights = {}
local registeredModules = {}
local playerSpells = {}
local registeredSpellIndex = {}
local temporarySpells = {}
local moduleCount = 0
local RegisterModuleInternal, RemoveModuleInternal, FlushPendingModules, QueueModuleRegistration
local IsCooldownEnabledForPlayer
local lastModuleSyncRequest = {}
local pendingModuleQueue = {}
local bootstrapReady = false
local STOLEN_WAND_BACKFIRE_DAMAGE <const> = 35
local STOLEN_WAND_BACKFIRE_COOLDOWN <const> = 3000
local stolenWandBackfireCooldowns = {}
local PROFESSOR_POINT_RANGE <const> = 10.0
local LEVELING_CONFIG <const> = Config.Leveling or {}
local SPELL_LEVEL_OVERRIDES <const> = Config.SpellLevelOverrides or {}
local ABSOLUTE_MAX_LEVEL <const> = 5
local COOLDOWN_DISABLE_LEVEL <const> = 5
local STAFF_RESTRICTION <const> = {
    'group.owner',
}
local STAFF_GROUPS <const> = {
    admin = true,
    superadmin = true,
    mod = true,
    moderator = true,
    staff = true,
    owner = true
}
local madvr_sqrt <const> = math.sqrt

local function canManageSpells(src)
    local xPlayer <const> = ESX.GetPlayerFromId(src)
    if not xPlayer or not xPlayer.job then return false end
    return xPlayer.job.name == 'wand_professeur' or xPlayer.job.name == 'direction'
end

local function IsStaffMember(src)
    if not src then
        return false
    end

    if canManageSpells(src) then
        return true
    end

    local xPlayer <const> = ESX.GetPlayerFromId(src)
    if not xPlayer then
        return false
    end

    if xPlayer.getGroup then
        local group <const> = xPlayer.getGroup()
        if group and STAFF_GROUPS[group] then
            return true
        end
    end

    if IsPlayerAceAllowed and IsPlayerAceAllowed(src, 'dvr_power.staff') then
        return true
    end

    return false
end

local function IsWithinProfessorRange(professorSrc, targetSrc, maxDistance)
    local range <const> = maxDistance or PROFESSOR_POINT_RANGE
    if not professorSrc or not targetSrc then
        return false
    end

    local professorPed <const> = GetPlayerPed(professorSrc)
    local targetPed <const> = GetPlayerPed(targetSrc)

    if not professorPed or professorPed == 0 or not targetPed or targetPed == 0 then
        return false
    end

    if not DoesEntityExist(professorPed) or not DoesEntityExist(targetPed) then
        return false
    end

    local professorCoords <const> = GetEntityCoords(professorPed)
    local targetCoords <const> = GetEntityCoords(targetPed)
    if not professorCoords or not targetCoords then
        return false
    end

    local dx <const> = (professorCoords.x or 0.0) - (targetCoords.x or 0.0)
    local dy <const> = (professorCoords.y or 0.0) - (targetCoords.y or 0.0)
    local dz <const> = (professorCoords.z or 0.0) - (targetCoords.z or 0.0)

    return (dx * dx + dy * dy + dz * dz) <= (range * range)
end

FlushPendingModules = function() end
QueueModuleRegistration = function(moduleData, source)
    if not moduleData or not moduleData.name then
        return
    end
    pendingModuleQueue[#pendingModuleQueue + 1] = {
        data = moduleData,
        source = source or 0
    }
end

MySQL.ready(function()
    EnsureDatabaseSchema()
    bootstrapReady = true
    FlushPendingModules()
end)

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

local function MergeTables(target, source)
    if type(target) ~= 'table' or type(source) ~= 'table' then
        return target
    end

    for key, value in pairs(source) do
        if type(value) == 'table' and type(target[key]) == 'table' then
            MergeTables(target[key], value)
        else
            target[key] = DeepCopyTable(value)
        end
    end

    return target
end

local function GetLevelingConfigForSpell(spellId)
    if not LEVELING_CONFIG or LEVELING_CONFIG.enabled == false then
        return nil
    end

    local override = SPELL_LEVEL_OVERRIDES[spellId]
    if not override then
        return LEVELING_CONFIG
    end

    local merged = DeepCopyTable(LEVELING_CONFIG)
    return MergeTables(merged, override)
end

local function Clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function CalculateCooldownForLevel(spellId, spell, level)
    local config <const> = GetLevelingConfigForSpell(spellId)
    if not config then
        return (spell and spell.cooldown) or Config.DefaultCooldown
    end

    if level and level >= COOLDOWN_DISABLE_LEVEL then
        return 0
    end

    local baseCooldown <const> = (spell and spell.cooldown) or Config.DefaultCooldown
    local multipliers <const> = config.cooldown_multiplier or {}
    local minMultiplier <const> = multipliers.minimum or 1.0
    local maxMultiplier <const> = multipliers.maximum or 3.0
    local maxLevel <const> = math.min(config.max_level or ABSOLUTE_MAX_LEVEL, ABSOLUTE_MAX_LEVEL)
    local clampedLevel <const> = Clamp(level or 0, 0, maxLevel)
    local ratio <const> = maxLevel > 0 and (clampedLevel / maxLevel) or 1.0
    local multiplier <const> = minMultiplier + ((1.0 - ratio) * (maxMultiplier - minMultiplier))

    local adjustedCooldown = baseCooldown * multiplier

    local dividerCfg <const> = config.cooldown_divider
    if dividerCfg and dividerCfg.enabled ~= false then
        local step = dividerCfg.step or 0.15
        local divider <const> = 1.0 + (clampedLevel * step)
        if divider > 0 then
            adjustedCooldown = adjustedCooldown / divider
        end
    end

    return math.floor(adjustedCooldown)
end

local function GetDefaultSpellLevel(spellId)
    local config <const> = GetLevelingConfigForSpell(spellId)
    if not config then
        return 0
    end
    local maxLevel <const> = math.min(config.max_level or ABSOLUTE_MAX_LEVEL, ABSOLUTE_MAX_LEVEL)
    if config.default_level ~= nil then
        return Clamp(config.default_level, 0, maxLevel)
    end
    return 0
end

local function GetMaxSpellLevel(spellId)
    local config <const> = GetLevelingConfigForSpell(spellId)
    if config and config.max_level then
        return Clamp(config.max_level, 0, ABSOLUTE_MAX_LEVEL)
    end
    if LEVELING_CONFIG and LEVELING_CONFIG.max_level then
        return Clamp(LEVELING_CONFIG.max_level, 0, ABSOLUTE_MAX_LEVEL)
    end
    return ABSOLUTE_MAX_LEVEL
end

local function NormalizeSpellLevel(spellId, level)
    local maxLevel <const> = GetMaxSpellLevel(spellId) or 5
    local numericLevel <const> = tonumber(level) or 0
    return Clamp(math.floor(numericLevel), 0, maxLevel)
end

local function ReduceWandDurability(source)
    local inventoryExports <const> = exports.ft_inventory
    if not inventoryExports or type(inventoryExports.GetUsedWeapon) ~= "function" then
        return
    end

    local usedWeapon <const> = inventoryExports:GetUsedWeapon(source)
    if not usedWeapon then
        return
    end

    local weaponHash <const> = usedWeapon.weaponHash or (type(usedWeapon.meta) == "table" and usedWeapon.meta.weaponHash)
    local itemName <const> = usedWeapon.item

    if itemName ~= "wand" and weaponHash ~= Config.WandWeapon then
        return
    end
    local meta <const> = type(usedWeapon.meta) == "table" and usedWeapon.meta or {}
    local maxDurability = 100
    if type(meta.maxDurability) == "number" then
        maxDurability = meta.maxDurability
    elseif type(meta.durability) == "number" then
        maxDurability = meta.durability
    end
    if maxDurability > 200 then
        maxDurability = 200
    elseif maxDurability < 0 then
        maxDurability = 0
    end

    local current = type(meta.durability) == "number" and meta.durability or maxDurability
    if current > maxDurability then
        current = maxDurability
    end

    local newDurability = current - 0.1
    if newDurability < 0 then newDurability = 0 end

    if type(inventoryExports.SetDurability) == "function" then
        if type(meta) == "table" then
            meta.maxDurability = maxDurability
        end

        inventoryExports:SetDurability(source, { itemHash = usedWeapon.itemHash }, newDurability)

        local inv <const> = inventoryExports.GetInventory and inventoryExports:GetInventory(source)
        if inv and inv.getItemBy and inv.OnItemUpdate then
            local itemRef <const> = inv:getItemBy({ itemHash = usedWeapon.itemHash })
            if itemRef and type(itemRef.meta) == "table" then
                itemRef.meta.maxDurability = maxDurability
                inv:OnItemUpdate(itemRef)
            end
        end
    end
end

local function CreateCastFunction(source)
    local defaultTarget <const> = source

    return function(eventName, ...)
        if not eventName then
            return
        end

        local args <const> = { ... }
        local target = defaultTarget

        if #args > 0 and type(args[1]) == 'table' and args[1].__broadcast then
            local opts <const> = table.remove(args, 1)
            if opts then
                target = opts.target or -1
            end
        end

        TriggerClientEvent(eventName, target, table.unpack(args))
    end
end

local function ShouldUseTrainingVersion(spellId, level)
    local config <const> = GetLevelingConfigForSpell(spellId)
    if not config then
        return false
    end

    local trainingLevel <const> = config.training_level or 0
    return level <= trainingLevel
end

local function GetBackfireChance(spellId, level)
    local config <const> = GetLevelingConfigForSpell(spellId)
    if not config or not config.backfire then
        return 0.0
    end

    local backfire <const> = config.backfire
    if level > (backfire.max_level or -1) then
        return 0.0
    end

    local chance = (backfire.base_chance or 0.0) - ((backfire.chance_reduction_per_level or 0.0) * level)
    if chance < 0 then
        chance = 0
    end
    return chance
end

local function GetBackfireDamage(spellId)
    local config <const> = GetLevelingConfigForSpell(spellId)
    if not config or not config.backfire then
        return 0
    end

    return config.backfire.damage or 0
end

local function GetPlayerSpellLevel(identifier, spellId)
    if not identifier or not spellId then
        return NormalizeSpellLevel(spellId, GetDefaultSpellLevel(spellId))
    end

    local tempSpells <const> = temporarySpells[identifier]
    if tempSpells and tempSpells[spellId] ~= nil then
        return NormalizeSpellLevel(spellId, tempSpells[spellId])
    end

    local playerSpellData <const> = playerSpells[identifier]
    if playerSpellData and playerSpellData[spellId] and playerSpellData[spellId].level ~= nil then
        return NormalizeSpellLevel(spellId, playerSpellData[spellId].level)
    end

    return NormalizeSpellLevel(spellId, GetDefaultSpellLevel(spellId))
end

local function ShouldMuteSpellSound(spellId, level)
    local config <const> = GetLevelingConfigForSpell(spellId)
    if not config then
        return false
    end

    local minSoundLevel <const> = config.min_sound_level or 2
    return (level or 0) < minSoundLevel
end

local function GetRangeFactorForLevel(spellId, level)
    local config <const> = GetLevelingConfigForSpell(spellId)
    if not config or not config.range_multiplier then
        return 1.0
    end

    local rangeConfig <const> = config.range_multiplier
    local maxLevel <const> = math.min(config.max_level or ABSOLUTE_MAX_LEVEL, ABSOLUTE_MAX_LEVEL)
    local clampedLevel <const> = Clamp(level or 0, 0, maxLevel)

    if rangeConfig.levels and #rangeConfig.levels > 0 then
        local index = math.floor(clampedLevel + 1)
        if index < 1 then
            index = 1
        elseif index > #rangeConfig.levels then
            index = #rangeConfig.levels
        end
        local value <const> = rangeConfig.levels[index]
        if type(value) == 'number' and value > 0 then
            return value
        end
    end

    local minFactor <const> = rangeConfig.minimum or 1.0
    local maxFactor <const> = rangeConfig.maximum or 1.0
    if maxLevel <= 0 then
        return maxFactor
    end

    local ratio = clampedLevel / maxLevel
    local curve <const> = rangeConfig.curve or 1.0
    if curve ~= 1.0 then
        ratio = math.pow(ratio, math.max(0.01, curve))
    end
    return minFactor + ((maxFactor - minFactor) * ratio)
end

local function ClampTargetCoordsForLevel(source, spellId, coords, level, isSelfCast)
    if isSelfCast or not coords then
        return coords
    end

    local factor <const> = GetRangeFactorForLevel(spellId, level)
    if factor >= 0.999 then
        return coords
    end

    local ped <const> = GetPlayerPed(source)
    if not ped or ped == 0 then
        return coords
    end
    
    if not DoesEntityExist(ped) then
        return coords
    end

    local origin <const> = GetEntityCoords(ped)
    local target <const> = vector3(coords.x or origin.x, coords.y or origin.y, coords.z or origin.z)
    local direction <const> = target - origin
    local distance <const> = #(direction)

    if distance <= 0.001 then
        return coords
    end

    local scaledDistance <const> = distance * factor
    local normalized <const> = direction / distance
    local adjusted <const> = origin + (normalized * scaledDistance)
    return adjusted
end

exports('ClampSpellCoords', function(source, spellId, coords, levelOverride, isSelfCast)
    if not spellId then
        return coords
    end

    local level = levelOverride
    if level == nil then
        local player <const> = source and ESX.GetPlayerFromId(source) or nil
        if player and player.identifier then
            level = GetPlayerSpellLevel(player.identifier, spellId)
        else
            level = GetDefaultSpellLevel(spellId)
        end
    end

    return ClampTargetCoordsForLevel(source, spellId, coords, level, isSelfCast)
end)

local function CleanSpellsWithKeys()
    for _, moduleEntry in pairs(registeredModules) do
        local moduleData <const> = moduleEntry.data
        if moduleData.keys and moduleData.keys ~= '' and moduleEntry.addedSpellIds then
            for _, spellId in ipairs(moduleEntry.addedSpellIds) do
                Config.Spells[spellId] = nil
            end
            moduleEntry.addedSpellIds = {}
        end
    end
end

local function IndexModuleSpells(moduleName, moduleData)
    if not moduleName or not moduleData then
        return
    end

    if moduleData.spells then
        for _, spell in ipairs(moduleData.spells or {}) do
            if spell.id then
                registeredSpellIndex[spell.id] = {
                    moduleName = moduleName,
                    module = moduleData,
                    spell = spell
                }
            end
        end
    elseif moduleData.id then
        registeredSpellIndex[moduleData.id] = {
            moduleName = moduleName,
            module = moduleData,
            spell = moduleData
        }
    end
end

local function RemoveModuleSpellsFromIndex(moduleData)
    if not moduleData then
        return
    end

    if moduleData.spells then
        for _, spell in ipairs(moduleData.spells or {}) do
            if spell.id then
                registeredSpellIndex[spell.id] = nil
            end
        end
    elseif moduleData.id then
        registeredSpellIndex[moduleData.id] = nil
    end
end

local function CopySpellToConfig(spell)
    return {
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
        soundType = spell.soundType or spell.soundtype or nil,
        image = spell.image or spell.icon,
        icon = spell.icon or nil,
        video = spell.video or spell.previewVideo,
        professor = spell.professor
    }
end

RemoveModuleInternal = function(moduleName, skipClientEvent)
    local moduleEntry <const> = registeredModules[moduleName]
    if not moduleEntry then
        return false
    end

    local moduleData <const> = moduleEntry.data

    RemoveModuleSpellsFromIndex(moduleData)

    if moduleEntry.addedSpellIds then
        for _, spellId in ipairs(moduleEntry.addedSpellIds) do
            Config.Spells[spellId] = nil
        end
    end

    registeredModules[moduleName] = nil
    moduleCount = math.max(0, moduleCount - 1)

    if not skipClientEvent then
        TriggerClientEvent('dvr_power:unregisterModule', -1, moduleName)
    end

    return true
end

RegisterModuleInternal = function(moduleData, source, skipClientEvent)
    if not moduleData or not moduleData.name then
        return false
    end

    if registeredModules[moduleData.name] then
        RemoveModuleInternal(moduleData.name, skipClientEvent)
    end

    local addedSpellIds <const> = {}

    registeredModules[moduleData.name] = {
        data = moduleData,
        registeredBy = source or 0,
        registeredAt = os.time(),
        addedSpellIds = addedSpellIds
    }
    moduleCount = moduleCount + 1

    IndexModuleSpells(moduleData.name, moduleData)

    local spellsToProcess <const> = {}

    if moduleData.spells then
        for _, spell in ipairs(moduleData.spells or {}) do
            table.insert(spellsToProcess, spell)
        end
    elseif moduleData.id then
        table.insert(spellsToProcess, moduleData)
    end

    for _, spell in ipairs(spellsToProcess) do
        if spell.id and (moduleData.keys == nil or moduleData.keys == '') and not Config.Spells[spell.id] then
            Config.Spells[spell.id] = CopySpellToConfig(spell)
            table.insert(addedSpellIds, spell.id)
        end
    end

    if not skipClientEvent then
        TriggerClientEvent('dvr_power:registerModule', -1, moduleData)
    end

    CleanSpellsWithKeys()
    return true
end

FlushPendingModules = function()
    if not bootstrapReady or not pendingModuleQueue or #pendingModuleQueue == 0 then
        return
    end

    for i = 1, #pendingModuleQueue do
        local entry <const> = pendingModuleQueue[i]
        if entry and entry.data then
            RegisterModuleInternal(entry.data, entry.source, false)
        end
    end

    pendingModuleQueue = {}
end

QueueModuleRegistration = function(moduleData, source)
    if not moduleData or not moduleData.name then
        return
    end

    for i = #pendingModuleQueue, 1, -1 do
        if pendingModuleQueue[i].data and pendingModuleQueue[i].data.name == moduleData.name then
            table.remove(pendingModuleQueue, i)
        end
    end

    pendingModuleQueue[#pendingModuleQueue + 1] = {
        data = moduleData,
        source = source or 0
    }
end

CreateThread(function()
    Wait(1500)
    if not bootstrapReady then
        bootstrapReady = true
    end
    FlushPendingModules()
end)

local function GetSpellDefinition(spellId)
    local entry <const> = registeredSpellIndex[spellId]
    local spell <const> = Config.Spells[spellId] or (entry and entry.spell)
    if spell then
        return spell, entry
    end
    return nil, nil
end

CreateThread(function()
    while true do
        Wait(60000)
        if next(playerCooldowns) == nil then
            goto continue
        end

        local currentTime <const> = os.time()
        
        for playerId, cooldowns in pairs(playerCooldowns) do
            for spellId, endTime in pairs(cooldowns) do
                if currentTime >= endTime then
                    cooldowns[spellId] = nil
                end
            end
            
            if next(cooldowns) == nil then
                playerCooldowns[playerId] = nil
            end
        end
        ::continue::
    end
end)

local function CountModules()
    return moduleCount
end

local function LoadPlayerSpells(identifier)
    if not identifier then
        return { list = {}, levels = {} }
    end

    local cached <const> = playerSpells[identifier]
    if cached and next(cached) then
        local list <const> = {}
        local levels <const> = {}
        for spellId, spellData in pairs(cached) do
            list[#list + 1] = spellId
            levels[spellId] = NormalizeSpellLevel(spellId, spellData.level)
        end
        return { list = list, levels = levels }
    end

    local moduleTotal <const> = CountModules()
    playerSpells[identifier] = {}
    if moduleTotal == 0 then
        return { list = {}, levels = {} }
    end
    
    local result <const> = MySQL.query.await('SELECT spell_id, COALESCE(level, 0) as level FROM character_spells WHERE identifier = ?', {identifier})
    local spells <const> = {}
    local levels <const> = {}
    
    if result then
        for _, row in ipairs(result) do
            local spellId <const> = row.spell_id
            local level <const> = NormalizeSpellLevel(spellId, row.level)
            spells[#spells + 1] = spellId
            levels[spellId] = level

            playerSpells[identifier][spellId] = {
                learned = true,
                learnedAt = os.time(),
                level = level
            }
        end
    end
    
    return {
        list = spells,
        levels = levels
    }
end

local function BuildPermanentSpellPayload(identifier)
    if not identifier then
        return { list = {}, levels = {} }
    end

    local data <const> = playerSpells[identifier]
    if not data then
        return LoadPlayerSpells(identifier)
    end

    local list <const> = {}
    local levels <const> = {}

    for spellId, spellData in pairs(data) do
        table.insert(list, spellId)
        levels[spellId] = NormalizeSpellLevel(spellId, spellData.level)
    end

    return { list = list, levels = levels }
end

local function BuildSpellSnapshot(identifier)
    local permanent <const> = BuildPermanentSpellPayload(identifier)
    local combinedList <const> = {}
    local combinedLevels <const> = {}

    for _, spellId in ipairs(permanent.list) do
        combinedList[#combinedList + 1] = spellId
        combinedLevels[spellId] = NormalizeSpellLevel(spellId, permanent.levels[spellId])
    end

    local temp <const> = temporarySpells[identifier]
    if temp then
        for spellId, level in pairs(temp) do
            if combinedLevels[spellId] == nil then
                combinedList[#combinedList + 1] = spellId
            end
            combinedLevels[spellId] = NormalizeSpellLevel(spellId, (type(level) == 'number') and level or 0)
        end
    end

    return combinedList, combinedLevels
end

local function ResolvePlayerIdentifier(target)
    if not target then
        return nil
    end

    if type(target) == 'string' and target ~= '' then
        return target
    end

    if type(target) ~= 'number' then
        return nil
    end

    local player <const> = ESX.GetPlayerFromId(target)
    if player and player.identifier then
        return player.identifier
    end

    return nil
end

local function GetPlayerHighestSpellLevel(identifier)
    if not identifier then
        return 0
    end

    local highest = 0
    local spells = playerSpells[identifier]

    if not spells or not next(spells) then
        local loaded <const> = LoadPlayerSpells(identifier)
        if loaded and playerSpells[identifier] then
            spells = playerSpells[identifier]
        end
    end

    if spells then
        for _, spellData in pairs(spells) do
            if spellData and spellData.level and spellData.level > highest then
                highest = spellData.level
            end
        end
    end

    local tempSpells <const> = temporarySpells[identifier]
    if tempSpells then
        for spellId, level in pairs(tempSpells) do
            local normalized <const> = NormalizeSpellLevel(spellId, level)
            if normalized > highest then
                highest = normalized
            end
        end
    end

    if highest <= 0 and LEVELING_CONFIG and LEVELING_CONFIG.default_level then
        highest = LEVELING_CONFIG.default_level
    end

    if highest > ABSOLUTE_MAX_LEVEL then
        highest = ABSOLUTE_MAX_LEVEL
    end

    return highest
end

IsCooldownEnabledForPlayer = function(identifier, spellId)
    if spellId then
        local level <const> = GetPlayerSpellLevel(identifier, spellId)
        return level < COOLDOWN_DISABLE_LEVEL
    end

    local playerLevel <const> = GetPlayerHighestSpellLevel(identifier)
    return playerLevel < COOLDOWN_DISABLE_LEVEL
end

local function SetPlayerSpellLevel(identifier, spellId, newLevel)
    local level <const> = NormalizeSpellLevel(spellId, newLevel)
    local affectedRows <const> = MySQL.update.await('UPDATE character_spells SET level = ? WHERE identifier = ? AND spell_id = ?', {
        level,
        identifier,
        spellId
    })

    if affectedRows and affectedRows > 0 then
        if not playerSpells[identifier] then
            playerSpells[identifier] = {}
        end

        if playerSpells[identifier][spellId] then
            playerSpells[identifier][spellId].level = level
        end

        return true
    end

    return false
end

local function CanCastSpell(source, spellId)
    local spell <const> = GetSpellDefinition(spellId)
    if not spell then
        return false, 'Sort inconnu'
    end
    
    local identifier <const> = ResolvePlayerIdentifier(source)
    if not identifier then
        return false, 'Joueur inconnu'
    end

    local playerId <const> = tostring(source)

    if not IsCooldownEnabledForPlayer(identifier, spellId) then
        if playerCooldowns[playerId] and playerCooldowns[playerId][spellId] then
            playerCooldowns[playerId][spellId] = nil
        end
        return true, 'OK'
    end
    
    if playerCooldowns[playerId] and playerCooldowns[playerId][spellId] then
        local timeLeft <const> = playerCooldowns[playerId][spellId] - os.time()
        if timeLeft > 0 then
            return false, 'Cooldown actif: ' .. timeLeft .. 's'
        end
    end
    
    return true, 'OK'
end

local function ApplyCooldown(source, spellId, cooldown)
    local identifier <const> = ResolvePlayerIdentifier(source)
    local playerId <const> = tostring(source)

    if not IsCooldownEnabledForPlayer(identifier, spellId) or (cooldown or 0) <= 0 then
        if playerCooldowns[playerId] and playerCooldowns[playerId][spellId] then
            playerCooldowns[playerId][spellId] = nil
        end
        return
    end

    if not playerCooldowns[playerId] then
        playerCooldowns[playerId] = {}
    end
    playerCooldowns[playerId][spellId] = os.time() + math.floor(cooldown / 1000)
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        temporarySpells = {}

        bootstrapReady = true
        FlushPendingModules()
        
        local result <const> = MySQL.single.await('SELECT classes, notes, attendance FROM professor_data WHERE id = 1', {})
        if result then
            MySQL.update.await('UPDATE professor_data SET history = ?, updated_at = NOW() WHERE id = 1', {
                json.encode({})
            })
        end
        
        Wait(3000)
        
        local players <const> = GetPlayers()
        for _, playerIdStr in ipairs(players) do
            local playerId <const> = tonumber(playerIdStr)
            if not playerId then
                goto continue
            end
            
            local player <const> = ESX.GetPlayerFromId(playerId)
            if player and player.identifier then
                local spellsData <const> = LoadPlayerSpells(player.identifier)
                
                TriggerClientEvent('dvr_power:loadSpells', playerId, spellsData.list, spellsData.levels)
            end
            
            ::continue::
        end
    end
end)

AddEventHandler('esx:playerLoaded', function(source, xplayer)
    CreateThread(function()
        local maxAttempts <const> = 20
        local attempts = 0
        local moduleCount = 0
        
        while moduleCount == 0 and attempts < maxAttempts do
            Wait(500)
            moduleCount = CountModules()
            attempts = attempts + 1
            
            if moduleCount > 0 then
                break
            end
        end
        
        if moduleCount == 0 then
            return
        end
        
        Wait(2000)
        
        for moduleName, moduleInfo in pairs(registeredModules) do
            TriggerClientEvent('dvr_power:registerModule', source, moduleInfo.data)
        end
        
        Wait(1000)
        
        local spellsData <const> = LoadPlayerSpells(xplayer.identifier)
        
        TriggerClientEvent('dvr_power:loadSpells', source, spellsData.list, spellsData.levels)
    end)
end)

RegisterNetEvent('dvr_power:playSpellSound', function(spellId, coords)
    local source <const> = source
    local spell <const> = GetSpellDefinition(spellId)
    if not spell or not spell.sound or spell.sound == '' then
        return
    end

    local player <const> = ESX.GetPlayerFromId(source)
    if not player or not player.identifier then
        return
    end

    local level <const> = GetPlayerSpellLevel(player.identifier, spellId)
    if ShouldMuteSpellSound(spellId, level) then
        return
    end
    
    local soundId <const> = 'spell_' .. spellId .. '_' .. source .. '_' .. os.time()
    
    TriggerClientEvent('dvr_power:playSpellSound', -1, soundId, spell.sound, coords, spellId)
end)

RegisterNetEvent('dvr_power:requestRemoveLight', function(lightId)
    local source <const> = source

    if activeLights[lightId] and activeLights[lightId].playerId == source then
        TriggerClientEvent('dvr_power:removeLight', -1, lightId)
        activeLights[lightId] = nil
    end
end)

RegisterNetEvent('dvr_power:requestModuleSync', function()
    local src <const> = source
    local now <const> = os.time()
    if lastModuleSyncRequest[src] and (now - lastModuleSyncRequest[src]) < 2 then
        return
    end
    lastModuleSyncRequest[src] = now

    if not bootstrapReady then
        bootstrapReady = true
    end
    FlushPendingModules()

    for _, moduleEntry in pairs(registeredModules) do
        TriggerClientEvent('dvr_power:registerModule', src, moduleEntry.data)
    end

    local player <const> = ESX.GetPlayerFromId(src)
    if player and player.identifier then
        local combinedList <const>, combinedLevels <const> = BuildSpellSnapshot(player.identifier)
        TriggerClientEvent('dvr_power:loadSpells', src, combinedList, combinedLevels)
    end
end)

local function GetSpellCooldown(spellId)
    local spell <const> = GetSpellDefinition(spellId)
    if spell and spell.cooldown then
        return spell.cooldown
    end
    return 5000
end

exports('registerModule', function(moduleData, source)
    if not bootstrapReady then
        QueueModuleRegistration(moduleData, source)
        return true
    end

    return RegisterModuleInternal(moduleData, source, false)
end)

exports('unregisterModule', function(moduleName, source)
    if not bootstrapReady and pendingModuleQueue and #pendingModuleQueue > 0 then
        for i = #pendingModuleQueue, 1, -1 do
            if pendingModuleQueue[i].data and pendingModuleQueue[i].data.name == moduleName then
                table.remove(pendingModuleQueue, i)
            end
        end
        return true
    end

    local src <const> = source or 0
    local moduleEntry <const> = registeredModules[moduleName]

    if not moduleEntry then
        return false
    end

    if moduleEntry.registeredBy ~= src and src ~= 0 then
        return false
    end

    return RemoveModuleInternal(moduleName, false)
end)

exports('getModule', function(moduleName)
    return registeredModules[moduleName] and registeredModules[moduleName].data or nil
end)

exports('GetSpellCooldown', function(spellId)
    return GetSpellCooldown(spellId)
end)

exports('GetSpell', function(targetOrSpellId, spellId)
    local target = targetOrSpellId
    local id = spellId

    if id == nil then
        id = targetOrSpellId
        target = source
    end

    if not id then
        return false, 0, nil
    end

    local spell <const> = GetSpellDefinition(id)
    if not spell then
        return false, 0, nil
    end

    local identifier <const> = ResolvePlayerIdentifier(target)
    if identifier and not playerSpells[identifier] then
        LoadPlayerSpells(identifier)
    end

    local hasSpell = false
    local level = GetDefaultSpellLevel(id)
    local hasTemp = false
    local hasPermanent = false

    if identifier then
        local tempSpells <const> = temporarySpells[identifier]
        if tempSpells and tempSpells[id] ~= nil then
            hasTemp = true
            level = NormalizeSpellLevel(id, tempSpells[id])
        end

        if playerSpells[identifier] then
            hasPermanent = playerSpells[identifier][id] ~= nil
            if not hasTemp and hasPermanent then
                level = GetPlayerSpellLevel(identifier, id)
            end
        else
            level = GetPlayerSpellLevel(identifier, id)
        end
    end

    hasSpell = hasTemp or hasPermanent

    return hasSpell, level, spell.name or id
end)

exports('GetSpellName', function(spellId)
    local spell = GetSpellDefinition(spellId)
    if not spell then
        return nil
    end

    return spell.name or spellId
end)

exports('getAllModules', function()
    local modules = {}
    for name, module in pairs(registeredModules) do
        modules[name] = module.data
    end
    return modules
end)

local function BuildStaffSpellList()
    local spells = {}
    local added = {}

    for spellId, entry in pairs(registeredSpellIndex) do
        local spellData <const> = entry and entry.spell
        if spellId and spellData then
            spells[#spells + 1] = {
                id = spellId,
                name = spellData.name or spellId,
                description = spellData.description or '',
                icon = spellData.icon or spellData.image or '',
                image = spellData.image or spellData.icon or ''
            }
            added[spellId] = true
        end
    end

    for spellId, spellData in pairs(Config.Spells) do
        if spellId and spellData and not added[spellId] then
            spells[#spells + 1] = {
                id = spellId,
                name = spellData.name or spellId,
                description = spellData.description or '',
                icon = spellData.icon or spellData.image or '',
                image = spellData.image or spellData.icon or ''
            }
        end
    end

    return spells
end

lib.callback.register('dvr_power:staffGetSpells', function(source)
    if not IsStaffMember(source) then
        TriggerClientEvent('dvr_power:staffSpellResult', source, false, 'Accès staff requis.')
        return {}
    end

    FlushPendingModules()
    return BuildStaffSpellList()
end)

RegisterNetEvent('dvr_power:staffGiveSpell', function(spellId, level, removeSpell, targetPlayerId)
    local src <const> = source
    if not IsStaffMember(src) then
        TriggerClientEvent('dvr_power:staffSpellResult', src, false, 'Accès staff requis.')
        return
    end

    if type(spellId) ~= 'string' or spellId == '' then
        TriggerClientEvent('dvr_power:staffSpellResult', src, false, 'Sort invalide.')
        return
    end

    local spell <const> = GetSpellDefinition(spellId)
    if not spell then
        TriggerClientEvent('dvr_power:staffSpellResult', src, false, 'Sort introuvable.')
        return
    end

    -- Si aucun joueur cible n'est spécifié, utiliser le joueur qui exécute la commande
    local targetSrc <const> = targetPlayerId or src
    local xPlayer <const> = ESX.GetPlayerFromId(targetSrc)
    local identifier <const> = xPlayer and (xPlayer.identifier or (xPlayer.getIdentifier and xPlayer.getIdentifier()))

    if not identifier then
        TriggerClientEvent('dvr_power:staffSpellResult', src, false, 'Identifiant joueur introuvable.')
        return
    end

    local targetName = xPlayer and xPlayer.getName() or 'Joueur'
    local isSelf = targetSrc == src

    if removeSpell then
        local hadSpell = playerSpells[identifier] and playerSpells[identifier][spellId] ~= nil
        local result <const> = MySQL.query.await('DELETE FROM character_spells WHERE identifier = ? AND spell_id = ? LIMIT 1', {
            identifier,
            spellId
        })

        if not hadSpell and (not result or (type(result) == 'table' and (result.affectedRows or 0) == 0)) then
            if isSelf then
                TriggerClientEvent('dvr_power:staffSpellResult', src, false, 'Vous ne possédez pas ce sort.')
            else
                TriggerClientEvent('dvr_power:staffSpellResult', src, false, targetName .. ' ne possède pas ce sort.')
            end
            return
        end

        if playerSpells[identifier] then
            playerSpells[identifier][spellId] = nil
        end

        local playerIdStr <const> = tostring(targetSrc)
        if playerCooldowns[playerIdStr] then
            playerCooldowns[playerIdStr][spellId] = nil
            if next(playerCooldowns[playerIdStr]) == nil then
                playerCooldowns[playerIdStr] = nil
            end
        end

        local updatedSpells <const> = LoadPlayerSpells(identifier)
        TriggerClientEvent('dvr_power:loadSpells', targetSrc, updatedSpells.list, updatedSpells.levels)
        TriggerClientEvent('dvr_power:spellRemoved', targetSrc, spellId, spell.name or spellId)

        if isSelf then
            TriggerClientEvent('dvr_power:staffSpellResult', src, true, ('%s retiré.'):format(spell.name or spellId))
        else
            TriggerClientEvent('dvr_power:staffSpellResult', src, true, ('%s retiré à %s.'):format(spell.name or spellId, targetName))
        end
        return
    end

    local desiredLevel <const> = NormalizeSpellLevel(spellId, level or 1)
    local finalLevel <const> = desiredLevel < 1 and 1 or desiredLevel

    MySQL.insert.await('INSERT INTO character_spells (identifier, spell_id, level, unlocked_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE level = VALUES(level)', {
        identifier,
        spellId,
        finalLevel,
        os.date('%Y-%m-%d %H:%M:%S')
    })

    if not playerSpells[identifier] then
        playerSpells[identifier] = {}
    end

    playerSpells[identifier][spellId] = {
        learned = true,
        learnedAt = os.time(),
        level = finalLevel
    }

    local playerIdStr <const> = tostring(targetSrc)
    if playerCooldowns[playerIdStr] and playerCooldowns[playerIdStr][spellId] then
        playerCooldowns[playerIdStr][spellId] = nil
    end

    local spellsData <const> = LoadPlayerSpells(identifier)
    TriggerClientEvent('dvr_power:loadSpells', targetSrc, spellsData.list, spellsData.levels)
    TriggerClientEvent('dvr_power:updateSpellLevel', targetSrc, spellId, finalLevel)

    if isSelf then
        TriggerClientEvent('dvr_power:staffSpellResult', src, true, ('%s niveau %d appliqué.'):format(spell.name or spellId, finalLevel))
    else
        TriggerClientEvent('dvr_power:staffSpellResult', src, true, ('%s niveau %d attribué à %s.'):format(spell.name or spellId, finalLevel, targetName))
    end
end)

lib.addCommand('givespell', {
    help = 'Ouvrir le menu GiveSpell (staff)',
    restricted = STAFF_RESTRICTION
}, function(source)
    if not IsStaffMember(source) then
        lib.notify(source, {
            title = 'GiveSpell',
            description = 'Accès staff requis.',
            type = 'error'
        })
        return
    end

    TriggerClientEvent('dvr_power:openStaffSpellMenu', source)
end)

RegisterNetEvent('dvr_power:castSpell', function(spellId, targetCoords, targetServerId)
    local source = source
    local player <const> = ESX.GetPlayerFromId(source)
    
    if not player then return end

    local playerState <const> = Player(source)?.state
    if playerState and playerState.staturion == true then
        lib.notify(source, {
            title = 'Sort bloqué',
            description = 'Vous êtes staturisé, impossible de lancer un sort.',
            type = 'error'
        })
        return
    end
    
    local canCast <const>, message <const> = CanCastSpell(source, spellId)
    
    if not canCast then
        lib.notify(source, {
            title = 'Sorts',
            description = message,
            type = 'error'
        })
        return
    end
    
    local spell <const>, moduleEntry <const> = GetSpellDefinition(spellId)
    if not spell then
        return
    end
    
    local playerLevel <const> = GetPlayerSpellLevel(player.identifier, spellId)
    local clampedLevel <const> = NormalizeSpellLevel(spellId, playerLevel)
    local cooldownEnabled <const> = IsCooldownEnabledForPlayer(player.identifier, spellId)
    local cooldownDuration <const> = cooldownEnabled and CalculateCooldownForLevel(spellId, spell, clampedLevel) or 0

    if ShouldUseTrainingVersion(spellId, clampedLevel) then
        ApplyCooldown(source, spellId, cooldownDuration)
        TriggerClientEvent('dvr_power:spellTrainingEffect', -1, source, spellId, clampedLevel)
        
        lib.notify(source, {
            title = 'Sort instable',
            description = ('%s produit seulement un voile de fumée.'):format(spell.name or spellId),
            type = 'warning',
            duration = 4000
        })
        return
    end

    local backfireChance <const> = GetBackfireChance(spellId, clampedLevel)
    if backfireChance > 0 then
        local roll <const> = math.random()
        if roll < backfireChance then
            ApplyCooldown(source, spellId, cooldownDuration)
            local damage <const> = GetBackfireDamage(spellId)
            if damage > 0 then
                HPSystem.DealDamage(source, damage, source, spellId)
            end
            TriggerClientEvent('dvr_power:spellBackfire', -1, source, spellId, clampedLevel)
            lib.notify(source, {
                title = 'Retour de flamme',
                description = ('%s vous échappe des mains !'):format(spell.name or spellId),
                type = 'error',
                duration = 4000
            })
            return
        end
    end

    if targetCoords and not spell.selfCast then
        targetCoords = ClampTargetCoordsForLevel(source, spellId, targetCoords, clampedLevel, spell.selfCast)
    end

    ApplyCooldown(source, spellId, cooldownDuration)
    
    TriggerClientEvent('dvr_power:spellCast', -1, source, spellId, targetCoords, clampedLevel)
    
    if moduleEntry and moduleEntry.spell and moduleEntry.spell.onCast then
        local cast <const> = CreateCastFunction(source)
        local ok, err = pcall(moduleEntry.spell.onCast, true, { hit = true, hitCoords = targetCoords, entityHit = targetServerId }, source, targetServerId, clampedLevel, cast)
        if not ok then
            print(('[dvr_power] onCast error for spell "%s": %s'):format(spellId, err or 'unknown'))
        end
    end

    --ReduceWandDurability(source)
end)

RegisterNetEvent('dvr_power:stolenWandBackfire', function(spellId)
    local source <const> = source
    local player <const> = ESX.GetPlayerFromId(source)
    
    if not player then return end

    local now <const> = os.time() * 1000
    local lastBackfire = stolenWandBackfireCooldowns[source] or 0
    if (now - lastBackfire) < STOLEN_WAND_BACKFIRE_COOLDOWN then
        return
    end
    stolenWandBackfireCooldowns[source] = now

    local spell <const> = spellId and GetSpellDefinition(spellId)
    local spellName <const> = spell and spell.name or 'Sort inconnu'

    HPSystem.DealDamage(source, STOLEN_WAND_BACKFIRE_DAMAGE, source, 'stolen_wand_backfire')

    TriggerClientEvent('dvr_power:spellBackfire', -1, source, spellId or 'unknown', 0)

    LogDiscord({
        title = 'Baguette Volée - Backfire',
        description = ('%s a tenté d\'utiliser une baguette qui ne lui appartient pas.'):format(player.getName()),
        fields = {
            { name = 'Joueur', value = player.getName(), inline = true },
            { name = 'Sort tenté', value = spellName, inline = true },
            { name = 'Dégâts subis', value = tostring(STOLEN_WAND_BACKFIRE_DAMAGE), inline = true }
        },
        color = 15158332
    })

    lib.notify(source, {
        title = 'Baguette refusée',
        description = 'Cette baguette ne vous appartient pas ! Le sort se retourne contre vous.',
        type = 'error',
        duration = 5000
    })
end)

CreateThread(function()
    while true do
        Wait(1000)
        if next(activeLights) == nil then
            goto continue
        end

        local currentTime <const> = os.time()
        for lightId, light in pairs(activeLights) do
            if light.endTime <= currentTime then
                TriggerClientEvent('dvr_power:removeLight', -1, lightId)
                activeLights[lightId] = nil
            end
        end
        ::continue::
    end
end)

local function BuildTempSpellsPayload()
    local tempSpellsData <const> = {}

    if next(temporarySpells) == nil then
        return tempSpellsData
    end

    PlayerCache.ForEach(function(playerId, entry)
        local identifier <const> = entry and entry.identifier or nil
        local spells <const> = identifier and temporarySpells[identifier] or nil
        if spells and next(spells) ~= nil then
            local payloadSpells <const> = {}
            for spellId, level in pairs(spells) do
                if type(level) == 'number' then
                    payloadSpells[spellId] = level
                else
                    payloadSpells[spellId] = tonumber(level) or 0
                end
            end
            tempSpellsData[tostring(playerId)] = payloadSpells
        end
    end)

    return tempSpellsData
end

local function BroadcastTempSpells()
    local payload = BuildTempSpellsPayload()
    PlayerCache.ForEach(function(playerId, entry)
        local player <const> = entry and entry.player or nil
        local job <const> = player and player.job or nil
        if job and (job.name == 'wand_professeur' or job.name == 'professeur' or job.name == 'direction') then
            TriggerClientEvent('dvr_power:professorTempSpells', playerId, payload)
        end
    end)
end

RegisterNetEvent('dvr_power:professorGiveTempSpell', function(targetPlayerId, spellId, level)
    local source <const> = source
    if not canManageSpells(source) then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', 'Joueur', 'Sort', false)
        return
    end
    local professor <const> = ESX.GetPlayerFromId(source)
    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)
    
    if not professor or not targetPlayer then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', 'Joueur', 'Sort', false)
        return
    end
    
    local spell <const> = GetSpellDefinition(spellId)
    if not spell then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', targetPlayer.getName(), spellId, false)
        return
    end
    
    local identifier <const> = targetPlayer.identifier
    if not identifier then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', targetPlayer.getName(), spell.name or spellId, false)
        return
    end

    if not temporarySpells[identifier] then
        temporarySpells[identifier] = {}
    end
    
    if temporarySpells[identifier][spellId] then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', targetPlayer.getName(), spell.name or spellId, false)
        return
    end
    
    local spellLevel <const> = NormalizeSpellLevel(spellId, level)
    temporarySpells[identifier][spellId] = spellLevel
    
    local allSpells <const>, allLevels <const> = BuildSpellSnapshot(identifier)

    TriggerClientEvent('dvr_power:loadSpells', targetPlayerId, allSpells, allLevels)
    TriggerClientEvent('dvr_power:updateSpellLevel', targetPlayerId, spellId, spellLevel)
    TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', targetPlayer.getName(), spell.name or spellId, true, targetPlayerId, spellId, true, spellLevel)
    
    LogDiscord('give_temp', {
        professor = { source = source, name = professor.getName(), license = professor.getIdentifier() },
        target = { source = targetPlayerId, name = targetPlayer.getName(), license = targetPlayer.identifier },
        spell = { id = spellId, name = spell.name or spellId, level = spellLevel },
        context = { temp = true }
    })

    BroadcastTempSpells()
end)

RegisterNetEvent('dvr_power:professorRemoveTempSpell', function(targetPlayerId, spellId)
    local source <const> = source
    if not canManageSpells(source) then
        return
    end
    local professor <const> = ESX.GetPlayerFromId(source)
    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)
    
    if not professor then
        return
    end
    
    local identifier = nil
    if targetPlayer then
        identifier = targetPlayer.identifier
    end
    
    if identifier and temporarySpells[identifier] then
        temporarySpells[identifier][spellId] = nil
        if next(temporarySpells[identifier]) == nil then
            temporarySpells[identifier] = nil
        end
    end
    
    if targetPlayer and identifier then
        local allSpells <const>, allLevels <const> = BuildSpellSnapshot(identifier)
        TriggerClientEvent('dvr_power:loadSpells', targetPlayerId, allSpells, allLevels)
    end
    
    local playerIdStr <const> = tostring(targetPlayerId)
    if playerCooldowns[playerIdStr] and playerCooldowns[playerIdStr][spellId] then
        playerCooldowns[playerIdStr][spellId] = nil
    end

    local targetName = 'Déconnecté'
    local targetLicense <const> = identifier or 'unknown'
    if targetPlayer then
        targetName = targetPlayer.getName()
    end

    LogDiscord('remove_temp', {
        professor = { source = source, name = professor.getName(), license = professor.getIdentifier() },
        target = { source = targetPlayerId, name = targetName, license = targetLicense },
        spell = { id = spellId },
        context = { temp = true }
    })

    BroadcastTempSpells()
end)

RegisterNetEvent('dvr_power:professorUpdateTempSpellLevel', function(targetPlayerId, spellId, level)
    local source <const> = source
    if not canManageSpells(source) then
        return
    end
    local professor <const> = ESX.GetPlayerFromId(source)
    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)
    
    if not professor or not targetPlayer then
        return
    end

    local identifier <const> = targetPlayer.identifier
    if not identifier then
        return
    end
    
    local spell <const> = GetSpellDefinition(spellId)
    if not spell then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Modification', targetPlayer.getName(), spellId, false, targetPlayerId, spellId, true)
        return
    end
    
    local spellLevel <const> = NormalizeSpellLevel(spellId, level)

    if not temporarySpells[identifier] then
        temporarySpells[identifier] = {}
    end
    if temporarySpells[identifier][spellId] == nil then
        temporarySpells[identifier][spellId] = spellLevel
    else
        temporarySpells[identifier][spellId] = spellLevel
    end
    temporarySpells[identifier][spellId] = spellLevel
    
    local playerIdStr <const> = tostring(targetPlayerId)
    if playerCooldowns[playerIdStr] and playerCooldowns[playerIdStr][spellId] then
        playerCooldowns[playerIdStr][spellId] = nil
    end
    
    local allSpells <const>, allLevels <const> = BuildSpellSnapshot(identifier)
    
    TriggerClientEvent('dvr_power:updateSpellLevel', targetPlayerId, spellId, spellLevel)
    Wait(100)
    TriggerClientEvent('dvr_power:loadSpells', targetPlayerId, allSpells, allLevels)
    TriggerClientEvent('dvr_power:professorSpellAction', source, 'Modification', targetPlayer.getName(), spell.name or spellId, true, targetPlayerId, spellId, true, spellLevel)

    LogDiscord('set_temp_level', {
        professor = { source = source, name = professor.getName(), license = professor.getIdentifier() },
        target = { source = targetPlayerId, name = targetPlayer.getName(), license = identifier },
        spell = { id = spellId, name = spell.name or spellId, level = spellLevel },
        context = { temp = true }
    })

    BroadcastTempSpells()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    temporarySpells = {}

    local cooldownCount = 0
    for _ in pairs(playerCooldowns or {}) do cooldownCount = cooldownCount + 1 end
    playerCooldowns = {}
    
    local lightCount = 0
    for lightId, _ in pairs(activeLights or {}) do
        TriggerClientEvent('dvr_power:removeLight', -1, lightId)
        lightCount = lightCount + 1
    end
    activeLights = {}

    for spellId in pairs(registeredSpellIndex) do
        Config.Spells[spellId] = nil
    end

    registeredModules = {}
    registeredSpellIndex = {}
    playerSpells = {}
    moduleCount = 0
    pendingModuleQueue = {}
    bootstrapReady = false
end)

RegisterNetEvent('dvr_power:professorGiveSpell', function(targetPlayerId, spellId, level)
    local source <const> = source
    if not canManageSpells(source) then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', 'Joueur', 'Sort', false)
        return
    end
    local professor <const> = ESX.GetPlayerFromId(source)
    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)

    if not professor or not targetPlayer then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', 'Joueur', 'Sort', false)
        return
    end

    local spell <const> = GetSpellDefinition(spellId)
    if not spell then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', targetPlayer.getName(), spellId, false)
        return
    end

    if playerSpells[targetPlayer.identifier] and playerSpells[targetPlayer.identifier][spellId] then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', targetPlayer.getName(), spell.name or spellId, false)
        return
    end

    if not playerSpells[targetPlayer.identifier] then
        playerSpells[targetPlayer.identifier] = {}
    end

    local spellLevel = NormalizeSpellLevel(spellId, level or 0)

    playerSpells[targetPlayer.identifier][spellId] = {
        learned = true,
        learnedAt = os.time(),
        level = spellLevel
    }

    local currentTime <const> = os.date('%Y-%m-%d %H:%M:%S')
    local result <const> = MySQL.insert.await('INSERT INTO character_spells (identifier, spell_id, level, unlocked_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE unlocked_at = VALUES(unlocked_at), level = VALUES(level)', {
        targetPlayer.identifier,
        spellId,
        spellLevel,
        currentTime
    })

    local updatedSpells <const> = LoadPlayerSpells(targetPlayer.identifier)
    TriggerClientEvent('dvr_power:loadSpells', targetPlayerId, updatedSpells.list, updatedSpells.levels)
    TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', targetPlayer.getName(), spell.name or spellId, true)

    LogDiscord('give_def', {
        professor = { source = source, name = professor.getName(), license = professor.getIdentifier() },
        target = { source = targetPlayerId, name = targetPlayer.getName(), license = targetPlayer.identifier },
        spell = { id = spellId, name = spell.name or spellId },
        context = { temp = false }
    })
end)


RegisterNetEvent('dvr_power:professorGiveSpellToMultiple', function(playerIds, spellId, level)
    local source <const> = source
    if not canManageSpells(source) then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', 'Joueurs', 'Sort', false)
        return
    end

    local professor <const> = ESX.GetPlayerFromId(source)
    if not professor then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', 'Joueurs', 'Sort', false)
        return
    end

    local spell <const> = GetSpellDefinition(spellId)
    if not spell then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', 'Joueurs', spellId, false)
        return
    end

    if not playerIds or type(playerIds) ~= 'table' or #playerIds == 0 then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', 'Joueurs', spell.name or spellId, false)
        return
    end

    local spellLevel = NormalizeSpellLevel(spellId, level or 0)
    local successCount = 0
    local failedCount = 0
    local currentTime <const> = os.date('%Y-%m-%d %H:%M:%S')

    for _, targetPlayerId in ipairs(playerIds) do
        local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)

        if targetPlayer and targetPlayer.identifier then
            local alreadyHas = playerSpells[targetPlayer.identifier] and playerSpells[targetPlayer.identifier][spellId]

            if not alreadyHas then
                if not playerSpells[targetPlayer.identifier] then
                    playerSpells[targetPlayer.identifier] = {}
                end

                playerSpells[targetPlayer.identifier][spellId] = {
                    learned = true,
                    learnedAt = os.time(),
                    level = spellLevel
                }

                local success <const>, result <const> = pcall(function()
                    return MySQL.insert.await('INSERT INTO character_spells (identifier, spell_id, level, unlocked_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE level = VALUES(level), unlocked_at = VALUES(unlocked_at)', {
                        targetPlayer.identifier,
                        spellId,
                        spellLevel,
                        currentTime
                    })
                end)

                if success and result then
                    local updatedSpells <const> = LoadPlayerSpells(targetPlayer.identifier)
                    TriggerClientEvent('dvr_power:loadSpells', targetPlayerId, updatedSpells.list, updatedSpells.levels)
                    
                    LogDiscord('give_def_bulk', {
                        professor = { source = source, name = professor.getName(), license = professor.getIdentifier() },
                        target = { source = targetPlayerId, name = targetPlayer.getName(), license = targetPlayer.identifier },
                        spell = { id = spellId, name = spell.name or spellId },
                        context = { bulk = true }
                    })
                    
                    successCount = successCount + 1
                else
                    print(('[dvr_power] Échec attribution sort %s à %s'):format(spellId, targetPlayer.identifier))
                    failedCount = failedCount + 1
                end
            end
        else
            failedCount = failedCount + 1
        end
    end

    local message = string.format('%s attribué à %d joueur(s)', spell.name or spellId, successCount)
    if failedCount > 0 then
        message = message .. string.format(' (%d échec(s))', failedCount)
    end
    
    TriggerClientEvent('dvr_power:professorSpellAction', source, 'Attribution', 'Groupe', message, successCount > 0)
end)

RegisterNetEvent('dvr_power:professorGiveSkillPoint', function(targetPlayerId, amount)
    local src <const> = source
    local professor <const> = ESX.GetPlayerFromId(src)
    if not professor or not professor.job or (professor.job.name ~= 'wand_professeur' and professor.job.name ~= 'professeur' and professor.job.name ~= 'direction') then
        TriggerClientEvent('dvr_power:professorSpellAction', src, 'Point', 'Joueur', 'Compétence', false)
        return
    end
    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)
    local points <const> = tonumber(amount) or 1

    if not targetPlayer or points <= 0 then
        TriggerClientEvent('dvr_power:professorSpellAction', src, 'Point', 'Joueur', 'Compétence', false)
        return
    end

    if not IsWithinProfessorRange(src, targetPlayerId) then
        TriggerClientEvent('dvr_power:professorSpellAction', src, 'Point', targetPlayer.getName(), 'Point de compétence', false)
        return
    end

    TriggerEvent('ft_inventory:skills:addPointsServer', targetPlayerId, points)

    TriggerClientEvent('dvr_power:professorSpellAction', src, 'Point', targetPlayer.getName(), 'Point de compétence', true, targetPlayerId, 'skill_point', true, points)
end)

RegisterNetEvent('dvr_power:professorRemoveSkillPoint', function(targetPlayerId, amount)
    local src <const> = source
    local professor <const> = ESX.GetPlayerFromId(src)
    if not professor or not professor.job or (professor.job.name ~= 'wand_professeur' and professor.job.name ~= 'professeur' and professor.job.name ~= 'direction') then
        TriggerClientEvent('dvr_power:professorSpellAction', src, 'Retrait point', 'Joueur', 'Compétence', false)
        return
    end

    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)
    local points <const> = tonumber(amount) or 1

    if not targetPlayer or points <= 0 then
        TriggerClientEvent('dvr_power:professorSpellAction', src, 'Retrait point', 'Joueur', 'Compétence', false)
        return
    end

    if not IsWithinProfessorRange(src, targetPlayerId) then
        TriggerClientEvent('dvr_power:professorSpellAction', src, 'Retrait point', targetPlayer.getName(), 'Compétence', false)
        return
    end

    TriggerEvent('ft_inventory:skills:removePointsServer', targetPlayerId, points)

    TriggerClientEvent(
        'dvr_power:professorSpellAction',
        src,
        'Retrait point',
        targetPlayer.getName(),
        ('-%d point(s) de compétence'):format(points),
        true,
        targetPlayerId,
        'skill_point_remove',
        false,
        -points
    )
end)

RegisterNetEvent('dvr_power:professorRemoveSkillLevel', function(targetPlayerId, skillId, amount)
    local src <const> = source
    local professor <const> = ESX.GetPlayerFromId(src)
    if not professor or not professor.job or (professor.job.name ~= 'wand_professeur' and professor.job.name ~= 'professeur' and professor.job.name ~= 'direction') then
        TriggerClientEvent('dvr_power:professorSpellAction', src, 'Retrait point', 'Joueur', 'Compétence', false)
        return
    end

    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)
    local points <const> = tonumber(amount) or 1

    if not targetPlayer or points <= 0 or type(skillId) ~= 'string' then
        TriggerClientEvent('dvr_power:professorSpellAction', src, 'Retrait point', 'Joueur', 'Compétence', false)
        return
    end

    if not IsWithinProfessorRange(src, targetPlayerId) then
        TriggerClientEvent('dvr_power:professorSpellAction', src, 'Retrait point', targetPlayer.getName(), 'Compétence', false)
        return
    end

    TriggerEvent('ft_inventory:skills:removeLevelServer', targetPlayerId, skillId, points)

    local skillLabel = skillId
    if skillId == 'endurance' then skillLabel = 'Endurance'
    elseif skillId == 'force' then skillLabel = 'Force'
    elseif skillId == 'respiration' then skillLabel = 'Oxygène'
    elseif skillId == 'discretion' then skillLabel = 'Discrétion'
    elseif skillId == 'sangfroid' then skillLabel = 'Sang-froid'
    elseif skillId == 'maitrise' then skillLabel = 'Maîtrise' end

    TriggerClientEvent(
        'dvr_power:professorSpellAction',
        src,
        'Retrait point',
        targetPlayer.getName(),
        ('-%d niveau(x) sur %s'):format(points, skillLabel),
        true,
        targetPlayerId,
        'skill_point_remove',
        false,
        -points
    )
end)

RegisterNetEvent('dvr_power:professorRemoveSpell', function(targetPlayerId, spellId)
    local source <const> = source
    if not canManageSpells(source) then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Retrait', 'Joueur', 'Sort', false)
        return
    end
    local professor <const> = ESX.GetPlayerFromId(source)
    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)
    
    if not professor or not targetPlayer then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Retrait', 'Joueur', 'Sort', false)
        return
    end
    
    local spell <const> = GetSpellDefinition(spellId)
    if not spell then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Retrait', targetPlayer.getName(), spellId, false)
        return
    end
    
    local identifier <const> = targetPlayer.identifier
    if not identifier then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Retrait', targetPlayer.getName(), spell.name or spellId, false)
        return
    end

    local result <const> = MySQL.query.await('DELETE FROM character_spells WHERE identifier = ? AND spell_id = ? LIMIT 1', {
        identifier,
        spellId
    })

    if not result or (type(result) == 'table' and result.affectedRows == 0) then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Retrait', targetPlayer.getName(), spell.name or spellId, false)
        return
    end

    if playerSpells[identifier] then
        playerSpells[identifier][spellId] = nil
    end
    
    local updatedSpells <const> = LoadPlayerSpells(identifier)
    TriggerClientEvent('dvr_power:loadSpells', targetPlayerId, updatedSpells.list, updatedSpells.levels)
    TriggerClientEvent('dvr_power:spellRemoved', targetPlayerId, spellId, spell.name or spellId)
    TriggerClientEvent('dvr_power:professorSpellAction', source, 'Retrait', targetPlayer.getName(), spell.name or spellId, true)

    local playerIdStr <const> = tostring(targetPlayerId)
    if playerCooldowns[playerIdStr] and playerCooldowns[playerIdStr][spellId] then
        playerCooldowns[playerIdStr][spellId] = nil
    end

    LogDiscord('remove_def', {
        professor = { source = source, name = professor.getName(), license = professor.getIdentifier() },
        target = { source = targetPlayerId, name = targetPlayer.getName(), license = identifier },
        spell = { id = spellId, name = spell.name or spellId },
        context = { temp = false }
    })
end)

RegisterNetEvent('dvr_power:professorSetSpellLevel', function(targetPlayerId, spellId, newLevel)
    local source <const> = source
    if not canManageSpells(source) then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Niveau', 'Joueur', spellId, false)
        return
    end
    local professor <const> = ESX.GetPlayerFromId(source)
    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)
    
    if not professor or not targetPlayer then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Niveau', 'Joueur', spellId, false)
        return
    end

    local spell <const> = GetSpellDefinition(spellId)
    if not spell then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Niveau', targetPlayer.getName(), spellId, false)
        return
    end

    if not playerSpells[targetPlayer.identifier] or not playerSpells[targetPlayer.identifier][spellId] then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Niveau', targetPlayer.getName(), spell.name or spellId, false)
        return
    end

    local desiredLevel <const> = NormalizeSpellLevel(spellId, newLevel)

    local playerIdStr <const> = tostring(targetPlayerId)
    if playerCooldowns[playerIdStr] and playerCooldowns[playerIdStr][spellId] then
        playerCooldowns[playerIdStr][spellId] = nil
    end

    local updated <const> = SetPlayerSpellLevel(targetPlayer.identifier, spellId, desiredLevel)
    if not updated then
        print(('[dvr_power] Échec mise à niveau DB %s -> %s (identifier: %s)'):format(spellId, desiredLevel, targetPlayer.identifier))
    else
        print(('[dvr_power] Niveau mis à jour %s -> %s pour %s'):format(spellId, desiredLevel, targetPlayer.identifier))
    end
    if not updated then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Niveau', targetPlayer.getName(), spell.name or spellId, false)
        return
    end

    TriggerClientEvent('dvr_power:updateSpellLevel', targetPlayerId, spellId, desiredLevel)
    local spellsData <const> = LoadPlayerSpells(targetPlayer.identifier)
    TriggerClientEvent('dvr_power:loadSpells', targetPlayerId, spellsData.list, spellsData.levels)
    TriggerClientEvent('dvr_power:professorSpellAction', source, 'Niveau', targetPlayer.getName(), spell.name or spellId, true)

    TriggerClientEvent('dvr_power:receivePlayerSpells', source, targetPlayerId, playerSpells[targetPlayer.identifier] or {})

    LogDiscord('set_level', {
        professor = { source = source, name = professor.getName(), license = professor.getIdentifier() },
        target = { source = targetPlayerId, name = targetPlayer.getName(), license = targetPlayer.identifier },
        spell = { id = spellId, name = spell.name or spellId, level = desiredLevel },
        context = { temp = false }
    })
end)

RegisterNetEvent('dvr_power:professorResetCooldowns', function(targetPlayerId)
    local source <const> = source
    if not canManageSpells(source) then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Reset cooldown', 'Joueur', 'Cooldowns', false)
        return
    end
    local professor <const> = ESX.GetPlayerFromId(source)
    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)
    
    if not professor or not targetPlayer then
        TriggerClientEvent('dvr_power:professorSpellAction', source, 'Reset cooldown', 'Joueur', 'Cooldowns', false)
        return
    end
    
    local playerIdStr <const> = tostring(targetPlayerId)
    if playerCooldowns[playerIdStr] then
        playerCooldowns[playerIdStr] = nil
    end
    
    TriggerClientEvent('dvr_power:resetAllCooldowns', targetPlayerId)
    TriggerClientEvent('dvr_power:professorSpellAction', source, 'Reset cooldown', targetPlayer.getName(), 'Tous les cooldowns', true)
    
    LogDiscord('reset_cooldowns', {
        professor = { source = source, name = professor.getName(), license = professor.getIdentifier() },
        target = { source = targetPlayerId, name = targetPlayer.getName(), license = targetPlayer.identifier }
    })
end)

local function CollectProfessorSpellInfo(identifier)
    if not identifier then
        return {}
    end

    if playerSpells[identifier] then
        return playerSpells[identifier]
    end

    LoadPlayerSpells(identifier)
    return playerSpells[identifier] or {}
end

RegisterNetEvent('dvr_power:professorGetPlayerSpells', function(targetPlayerId)
    local source <const> = source
    local professor <const> = ESX.GetPlayerFromId(source)
    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)
    
    if not professor or not targetPlayer then
        return
    end
    
    local spells <const> = CollectProfessorSpellInfo(targetPlayer.identifier)
    TriggerClientEvent('dvr_power:receivePlayerSpells', source, targetPlayerId, spells)
end)

lib.callback.register('dvr_power:professorFetchPlayerSpells', function(source, targetPlayerId)
    local professor <const> = ESX.GetPlayerFromId(source)
    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)
    if not professor or not targetPlayer then
        return {}
    end

    return CollectProfessorSpellInfo(targetPlayer.identifier)
end)

lib.callback.register('dvr_power:professorGetSkillPoints', function(source, targetPlayerId)
    local professor <const> = ESX.GetPlayerFromId(source)
    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)

    if not professor or not targetPlayer then
        return 0
    end

    local ok, points = pcall(function()
        return exports['ft_inventory']:GetSkillPoints(targetPlayer.getIdentifier())
    end)

    if not ok then
        print(('[dvr_power] Failed to fetch skill points for %s: %s'):format(targetPlayerId, points))
        return 0
    end

    return points or 0
end)

local skillDefs <const> = {
    { id = 'endurance', label = 'Endurance' },
    { id = 'force', label = 'Force' },
    { id = 'respiration', label = 'Oxygène' },
    { id = 'discretion', label = 'Discrétion' },
    { id = 'sangfroid', label = 'Sang-froid' },
    { id = 'maitrise', label = 'Maîtrise' }
}

lib.callback.register('dvr_power:professorGetSkillLevels', function(source, targetPlayerId)
    local professor <const> = ESX.GetPlayerFromId(source)
    local targetPlayer <const> = ESX.GetPlayerFromId(targetPlayerId)

    if not professor or not targetPlayer then
        return { availablePoints = 0, skills = {} }
    end

    local skills <const> = {}
    for _, def in ipairs(skillDefs) do
        local ok <const>, level <const> = pcall(function()
            return exports['ft_inventory']:GetSkillLevel(targetPlayer.getIdentifier(), def.id)
        end)
        local lvl <const> = ok and tonumber(level) or 0
        skills[#skills + 1] = { id = def.id, label = def.label, level = lvl }
    end

    local available = 0
    local okPts <const>, points <const> = pcall(function()
        return exports['ft_inventory']:GetSkillPoints(targetPlayer.getIdentifier())
    end)
    if okPts and points then
        available = points
    end

    return { availablePoints = available, skills = skills }
end)

local function GetNearbyProfessorPlayers(professorSrc, radius)
    local range <const> = tonumber(radius) or PROFESSOR_POINT_RANGE
    if not professorSrc or not range or range <= 0 then
        return {}
    end

    local professorPed <const> = GetPlayerPed(professorSrc)
    if not professorPed or professorPed == 0 or not DoesEntityExist(professorPed) then
        return {}
    end

    local professorCoords <const> = GetEntityCoords(professorPed)
    if not professorCoords then
        return {}
    end

    local nearby = {}
    local players <const> = GetPlayers()
    local maxDistanceSq <const> = range * range

    for i = 1, #players do
        local targetSrc <const> = tonumber(players[i])
        if targetSrc and targetSrc ~= professorSrc then
            local targetPed <const> = GetPlayerPed(targetSrc)
            if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then
                local targetCoords <const> = GetEntityCoords(targetPed)
                if targetCoords then
                    local dx <const> = (professorCoords.x or 0.0) - (targetCoords.x or 0.0)
                    local dy <const> = (professorCoords.y or 0.0) - (targetCoords.y or 0.0)
                    local dz <const> = (professorCoords.z or 0.0) - (targetCoords.z or 0.0)
                    local distSq <const> = dx * dx + dy * dy + dz * dz
                    if distSq <= maxDistanceSq then
                        nearby[#nearby + 1] = {
                            id = targetSrc,
                            name = PlayerCache.GetName(targetSrc) or GetPlayerName(targetSrc) or ('Joueur %s'):format(targetSrc),
                            distance = madvr_sqrt(distSq)
                        }
                    end
                end
            end
        end
    end

    if #nearby > 1 then
        table.sort(nearby, function(a, b)
            return (a.distance or 0) < (b.distance or 0)
        end)
    end

    return nearby
end

lib.callback.register('dvr_power:professorGetNearbyPlayers', function(source, radius)
    local professor <const> = ESX.GetPlayerFromId(source)
    if not professor or not professor.job or (professor.job.name ~= 'wand_professeur' and professor.job.name ~= 'professeur' and professor.job.name ~= 'direction') then
        return {}
    end

    return GetNearbyProfessorPlayers(source, radius)
end)

local function GetProfessorPlayers()
    local cached = PlayerCache.GetPlayers()
    if cached and #cached > 0 then
        return cached
    end
    
    -- Fallback: construire la liste manuellement si le cache est vide
    local players = {}
    local allPlayers <const> = GetPlayers()
    for i = 1, #allPlayers do
        local src <const> = tonumber(allPlayers[i])
        if src then
            local xPlayer <const> = ESX.GetPlayerFromId(src)
            if xPlayer and xPlayer.identifier then
                players[#players + 1] = {
                    id = src,
                    name = xPlayer.getName() or GetPlayerName(src) or ('Joueur %s'):format(src),
                    identifier = xPlayer.identifier
                }
            end
        end
    end
    
    return players
end

lib.callback.register('dvr_power:professorGetPlayers', function(source)
    return GetProfessorPlayers()
end)

lib.callback.register('dvr_power:professorGetTempSpells', function(source)
    return BuildTempSpellsPayload()
end)

lib.callback.register('dvr_power:professorLoadData', function(source)
    local result <const> = MySQL.single.await('SELECT * FROM professor_data WHERE id = 1', {})
    
    if result then
        return {
            classes = json.decode(result.classes or '[]') or {},
            notes = json.decode(result.notes or '{}') or {},
            attendance = json.decode(result.attendance or '[]') or {},
            history = json.decode(result.history or '[]') or {}
        }
    else
        MySQL.insert.await('INSERT INTO professor_data (id, classes, notes, attendance, history) VALUES (1, ?, ?, ?, ?)', {
            json.encode({}),
            json.encode({}),
            json.encode({}),
            json.encode({})
        })
        return {
            classes = {},
            notes = {},
            attendance = {},
            history = {}
        }
    end
end)

RegisterNetEvent('dvr_power:professorSaveData', function(classes, notes, attendance, history)
    local source <const> = source
    local professor <const> = ESX.GetPlayerFromId(source)
    
    if not professor then
        return
    end
    
    MySQL.update.await('UPDATE professor_data SET classes = ?, notes = ?, attendance = ?, history = ?, updated_at = NOW() WHERE id = 1', {
        json.encode(classes or {}),
        json.encode(notes or {}),
        json.encode(attendance or {}),
        json.encode(history or {})
    })
end)

RegisterNetEvent('dvr_power:professorClearHistory', function()
    local source <const> = source
    local professor <const> = ESX.GetPlayerFromId(source)
    
    if not professor then
        return
    end
    
    local result <const> = MySQL.single.await('SELECT classes, notes, attendance FROM professor_data WHERE id = 1', {})
    
    if result then
        MySQL.update.await('UPDATE professor_data SET history = ?, updated_at = NOW() WHERE id = 1', {
            json.encode({})
        })
    end
end)

AddEventHandler('esx:playerLogout', function(playerId)
    TriggerClientEvent('dvr_power:hideHUD', playerId)

    local player <const> = ESX.GetPlayerFromId(playerId)
    local identifier <const> = player and player.identifier or nil

    if identifier and playerSpells[identifier] then
        playerSpells[identifier] = nil
    end

    if identifier and temporarySpells[identifier] then
        temporarySpells[identifier] = nil
    end
    
    local playerIdStr <const> = tostring(playerId)
    if playerCooldowns[playerIdStr] then
        playerCooldowns[playerIdStr] = nil
    end

    for lightId, light in pairs(activeLights) do
        if light.playerId == playerId then
            TriggerClientEvent('dvr_power:removeLight', -1, lightId)
            activeLights[lightId] = nil
        end
    end

    lastModuleSyncRequest[playerId] = nil
end)

_ENV.GetSpellCooldown = GetSpellCooldown
