---@diagnostic disable: undefined-global, trailing-space, unused-local, deprecated, param-type-mismatch
local professorMenuOpen = false
local playerSpellsCache = {}
ProfessorSliderState = ProfessorSliderState or {}
local GetPlayerServerId = GetPlayerServerId
local PlayerId = PlayerId
local GetPlayerName = GetPlayerName

local function IsProfessor()
    local playerData = ESX.GetPlayerData()
    local job = playerData and playerData.job
    return job and (job.name == 'wand_professeur' or job.name == 'professeur' or job.name == 'direction')
end

local function CanManageSpells()
    local playerData = ESX.GetPlayerData()
    local job = playerData and playerData.job
    return job and (job.name == 'wand_professeur' or job.name == 'direction')
end

local function IsDirection()
    local playerData = ESX.GetPlayerData()
    local job = playerData and playerData.job
    return job and job.name == 'direction'
end

local function GetAvailableSpells()
    local combined = {}
    local isDirection = IsDirection()

    for spellId, spellData in pairs(Config.Spells or {}) do
        if spellData and (isDirection or spellData.hidden ~= true) then
            combined[spellId] = spellData
        end
    end

    for _, moduleData in pairs(externalModules or {}) do
        if moduleData then
            local defaultKey = moduleData.keys
            if moduleData.spells then
                for _, spell in ipairs(moduleData.spells or {}) do
                    if spell.id and not combined[spell.id] and (isDirection or spell.hidden ~= true) then
                        combined[spell.id] = {
                            name = spell.name or spell.id,
                            description = spell.description or '',
                            color = spell.color or 'white',
                            cooldown = spell.cooldown or 5000,
                            type = spell.type or 'utility',
                            selfCast = spell.selfCast or false,
                            castTime = spell.castTime or 2000,
                            sound = spell.sound or '',
                            animation = spell.animation,
                            effect = spell.effect or {},
                            professor = spell.professor,
                            keys = spell.keys or defaultKey,
                            image = spell.image or spell.icon or '',
                            soundType = spell.soundType or spell.soundtype,
                            hidden = spell.hidden == true
                        }
                    end
                end
            elseif moduleData.id and not combined[moduleData.id] and (isDirection or moduleData.hidden ~= true) then
                combined[moduleData.id] = {
                    name = moduleData.name or moduleData.id,
                    description = moduleData.description or '',
                    color = moduleData.color or 'white',
                    cooldown = moduleData.cooldown or 5000,
                    type = moduleData.type or 'utility',
                    selfCast = moduleData.selfCast or false,
                    castTime = moduleData.castTime or 2000,
                    sound = moduleData.sound or '',
                    animation = moduleData.animation,
                    effect = moduleData.effect or {},
                    professor = moduleData.professor,
                    keys = moduleData.keys or '',
                    image = moduleData.image or moduleData.icon or '',
                    soundType = moduleData.soundType or moduleData.soundtype,
                    hidden = moduleData.hidden == true
                }
            end
        end
    end

    return combined
end

local function ApplyServerSpellData(playerId, spells)
    local normalized = spells or {}
    playerSpellsCache[playerId] = normalized

    ProfessorSliderState[playerId] = ProfessorSliderState[playerId] or {}
    local sliderState = ProfessorSliderState[playerId]

    for spellId in pairs(sliderState) do
        if not normalized[spellId] then
            sliderState[spellId] = nil
        end
    end

    for spellId, spellData in pairs(normalized) do
        sliderState[spellId] = spellData.level or 0
    end

    return normalized
end

local function RequestPlayerSpells(playerId)
    if not playerId then
        return {}
    end

    local spells = lib.callback.await('th_power:professorFetchPlayerSpells', false, playerId) or {}
    return ApplyServerSpellData(playerId, spells)
end

local function GetPlayerSpells(playerId, options)
    if not playerId then
        return {}
    end

    options = options or {}
    if options.forceRefresh then
        playerSpellsCache[playerId] = nil
    end

    if not playerSpellsCache[playerId] then
        return RequestPlayerSpells(playerId)
    end

    return playerSpellsCache[playerId]
end

local function RefreshPlayerSpells(playerId)
    if not playerId then
        return
    end

    playerSpellsCache[playerId] = nil
    RequestPlayerSpells(playerId)
end

local function LoadAllPlayerSpells()
    if not IsProfessor() then
        return
    end

    local players = lib.callback.await('th_power:professorGetPlayers', false)
    
    if players and #players > 0 then
        for _, playerData in ipairs(players) do
            if playerData.id ~= GetPlayerServerId(PlayerId()) then
                GetPlayerSpells(playerData.id, { forceRefresh = true })
                Wait(50)
            end
        end
    end
end

local function GetNearbyPlayers(radius)
    local nearbyPlayers = {}
    local playerPed = PlayerPedId()
    if not playerPed or playerPed == 0 then return nearbyPlayers end
    local playerCoords = GetEntityCoords(playerPed)
    local players = GetActivePlayers()
    
    for _, player in ipairs(players) do
        local targetPed = GetPlayerPed(player)
        if targetPed and targetPed ~= 0 and targetPed ~= playerPed and DoesEntityExist(targetPed) then
            local targetCoords = GetEntityCoords(targetPed)
            local distance = #(playerCoords - targetCoords)
            
            if distance <= radius then
                local serverId = GetPlayerServerId(player)
                local playerName = GetPlayerName(player)
                table.insert(nearbyPlayers, {
                    id = serverId,
                    name = playerName,
                    distance = distance
                })
            end
        end
    end
    
    return nearbyPlayers
end

local function OpenProfessorNuiMenu()
    local allSpells = {}
    local isDirection = IsDirection()
    for spellId, spellData in pairs(GetAvailableSpells() or {}) do
        if spellData and (isDirection or spellData.hidden ~= true) and (spellData.professor ~= false) then
            table.insert(allSpells, {
                id = spellId,
                name = spellData.name,
                description = spellData.description or '',
                icon = spellData.image or spellData.icon or '',
                image = spellData.image or spellData.icon or '',
                type = spellData.type or 'utility',
                color = spellData.color or 'white'
            })
        end
    end
    
    local allPlayers = lib.callback.await('th_power:professorGetPlayers', false) or {}
    
    SetNuiFocus(true, true)
    professorMenuOpen = true
    
    SendNUIMessage({
        action = 'openProfessorMenu',
        spells = allSpells,
        players = allPlayers,
        professor = {
            id = GetPlayerServerId(PlayerId()),
            name = GetPlayerName(PlayerId())
        },
        canManageSpells = CanManageSpells()
    })
end

RegisterKeyMapping('professor', '~m~(MENU)~s~ Ouvrir le menu professeur', 'keyboard', 'F6')
RegisterCommand('professor', function()
    local MyJobs = ESX.GetPlayerData().job.name
    if MyJobs ~= 'wand_professeur' and MyJobs ~= 'professeur' and MyJobs ~= 'direction' then
        return
    end
    OpenProfessorNuiMenu()
end, false)

RegisterNetEvent('th_power:receivePlayerSpells', function(playerId, spells)
    ApplyServerSpellData(playerId, spells or {})
    
    if professorMenuOpen then
        SendNUIMessage({
            action = 'professorPlayerSpells',
            playerId = playerId,
            spells = spells or {}
        })
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    SetTimeout(5000, function()
        LoadAllPlayerSpells()
    end)
end)

RegisterNetEvent('esx:playerLoaded', function()
    SetTimeout(2000, function()
        LoadAllPlayerSpells()
    end)
end)

RegisterNetEvent('th_power:professorSpellAction', function(action, playerName, spellName, success, playerId, spellId, isTemporary, level)
    SendNUIMessage({
        action = 'professorSpellAction',
        actionType = action,
        playerName = playerName,
        spellName = spellName,
        success = success,
        playerId = playerId,
        spellId = spellId,
        isTemporary = isTemporary or false,
        level = level
    })
    if success then
        if playerId then
            RefreshPlayerSpells(playerId)
        end
    else
        lib.notify({
            title = 'Erreur',
            description = 'Impossible de ' .. action:lower() .. ' le sort "' .. spellName .. '"',
            type = 'error'
        })
    end
end)

exports('openProfessorMenu', OpenProfessorNuiMenu)

RegisterNetEvent('th_power:professorTempSpells', function(tempSpells)
    SendNUIMessage({
        action = 'professorTempSpells',
        tempSpells = tempSpells or {}
    })
end)

RegisterNUICallback('closeProfessorMenu', function(data, cb)
    SetNuiFocus(false, false)
    professorMenuOpen = false
    cb('ok')
end)

RegisterNUICallback('professorGetData', function(data, cb)
    local allSpells = {}
    local isDirection = IsDirection()
    for spellId, spellData in pairs(GetAvailableSpells() or {}) do
        if spellData and (isDirection or spellData.hidden ~= true) and (spellData.professor ~= false) then
            table.insert(allSpells, {
                id = spellId,
                name = spellData.name,
                description = spellData.description or '',
                icon = spellData.image or spellData.icon or '',
                image = spellData.image or spellData.icon or '',
                type = spellData.type or 'utility',
                color = spellData.color or 'white'
            })
        end
    end
    
    local allPlayers = lib.callback.await('th_power:professorGetPlayers', false) or {}
    local tempSpells = lib.callback.await('th_power:professorGetTempSpells', false) or {}
    
    SendNUIMessage({
        action = 'professorAllSpells',
        spells = allSpells
    })
    
    SendNUIMessage({
        action = 'professorAllPlayers',
        players = allPlayers
    })
    
    SendNUIMessage({
        action = 'professorTempSpells',
        tempSpells = tempSpells
    })
    
    cb('ok')
end)

RegisterNUICallback('professorGetNearbyPlayers', function(data, cb)
    local radius = tonumber(data.radius) or 10.0
    local nearbyPlayers = lib.callback.await('th_power:professorGetNearbyPlayers', false, radius) or {}
    if not nearbyPlayers or #nearbyPlayers == 0 then
        nearbyPlayers = GetNearbyPlayers(radius)
    end
    
    SendNUIMessage({
        action = 'professorNearbyPlayers',
        players = nearbyPlayers or {}
    })
    
    cb('ok')
end)

RegisterNUICallback('professorGiveTempSpell', function(data, cb)
    local playerId = data.playerId
    local spellId = data.spellId
    local level = data.level or 0
    
    TriggerServerEvent('th_power:professorGiveTempSpell', playerId, spellId, level)
    
    cb('ok')
end)

RegisterNUICallback('professorGiveSpell', function(data, cb)
    local playerId = data.playerId
    local spellId = data.spellId
    local level = tonumber(data.level) or 0

    TriggerServerEvent('th_power:professorGiveSpell', playerId, spellId, level)

    cb('ok')
end)


RegisterNUICallback('professorGiveSpellToMultiple', function(data, cb)
    local playerIds = data.playerIds
    local spellId = data.spellId
    local level = tonumber(data.level) or 0

    if not playerIds or not spellId then
        cb('error')
        return
    end

    TriggerServerEvent('th_power:professorGiveSpellToMultiple', playerIds, spellId, level)

    cb('ok')
end)

RegisterNUICallback('professorGiveSkillPoint', function(data, cb)
    local playerId = data.playerId
    local amount = tonumber(data.amount) or 1
    TriggerServerEvent('th_power:professorGiveSkillPoint', playerId, amount)
    cb('ok')
end)

RegisterNUICallback('professorRemoveSkillPoint', function(data, cb)
    local playerId = data.playerId
    local amount = tonumber(data.amount) or 1
    TriggerServerEvent('th_power:professorRemoveSkillPoint', playerId, amount)
    cb('ok')
end)

RegisterNUICallback('professorRemoveSkillLevel', function(data, cb)
    local playerId = data.playerId
    local skillId = data.skillId
    local amount = tonumber(data.amount) or 1
    TriggerServerEvent('th_power:professorRemoveSkillLevel', playerId, skillId, amount)
    cb('ok')
end)

RegisterNUICallback('professorRemoveTempSpell', function(data, cb)
    local playerId = data.playerId
    local spellId = data.spellId
    
    TriggerServerEvent('th_power:professorRemoveTempSpell', playerId, spellId)
    
    cb('ok')
end)

RegisterNUICallback('professorUpdateTempSpellLevel', function(data, cb)
    local playerId = data.playerId
    local spellId = data.spellId
    local level = data.level or 0
    
    TriggerServerEvent('th_power:professorUpdateTempSpellLevel', playerId, spellId, level)
    
    cb('ok')
end)

RegisterNUICallback('professorGetPlayerSpells', function(data, cb)
    local playerId = data.playerId
    local spells = lib.callback.await('th_power:professorFetchPlayerSpells', false, playerId) or {}
    local skillPoints = lib.callback.await('th_power:professorGetSkillPoints', false, playerId) or 0
    local skillLevels = lib.callback.await('th_power:professorGetSkillLevels', false, playerId) or {}
    
    SendNUIMessage({
        action = 'professorPlayerSpells',
        spells = spells,
        playerId = playerId
    })

    SendNUIMessage({
        action = 'professorPlayerSkillPoints',
        playerId = playerId,
        points = skillPoints
    })

    SendNUIMessage({
        action = 'professorPlayerSkillLevels',
        playerId = playerId,
        levels = skillLevels.skills or {},
        availablePoints = skillLevels.availablePoints or 0
    })
    
    cb('ok')
end)

RegisterNUICallback('professorFetchSkillLevels', function(data, cb)
    local playerId = data.playerId
    local skillLevels = lib.callback.await('th_power:professorGetSkillLevels', false, playerId) or {}
    SendNUIMessage({
        action = 'professorPlayerSkillLevels',
        playerId = playerId,
        levels = skillLevels.skills or {},
        availablePoints = skillLevels.availablePoints or 0
    })
    cb('ok')
end)

RegisterNUICallback('professorSetSpellLevel', function(data, cb)
    local playerId = data.playerId
    local spellId = data.spellId
    local level = data.level or 0
    
    TriggerServerEvent('th_power:professorSetSpellLevel', playerId, spellId, level)
    
    cb('ok')
end)

RegisterNUICallback('professorRemoveSpell', function(data, cb)
    local playerId = data.playerId
    local spellId = data.spellId
    
    TriggerServerEvent('th_power:professorRemoveSpell', playerId, spellId)
    
    cb('ok')
end)

RegisterNUICallback('professorResetCooldowns', function(data, cb)
    local playerId = data.playerId
    
    TriggerServerEvent('th_power:professorResetCooldowns', playerId)
    
    cb('ok')
end)

RegisterNUICallback('professorGiveAllSpells', function(data, cb)
    local playerId = data.playerId
    
    TriggerServerEvent('th_power:professorGiveAllSpells', playerId)
    
    cb('ok')
end)

RegisterNUICallback('professorRemoveAllSpells', function(data, cb)
    local playerId = data.playerId
    
    TriggerServerEvent('th_power:professorRemoveAllSpells', playerId)
    
    cb('ok')
end)

RegisterNUICallback('professorSetGlobalLevel', function(data, cb)
    local playerId = data.playerId
    local level = data.level or 0
    
    TriggerServerEvent('th_power:professorSetGlobalLevel', playerId, level)
    
    cb('ok')
end)

RegisterNUICallback('professorNotify', function(data, cb)
    lib.notify({
        title = data.title or 'Notification',
        description = data.message or '',
        type = data.type or 'info',
        duration = data.duration or 5000
    })
    cb('ok')
end)
