---@diagnostic disable: trailing-space, undefined-global
local spellConfigs = {}
local spellConfigCallbacks = {}
local CONFIGURABLE_SPELLS = { 'transvalis' }

local function LoadSpellConfig(spellId)
    if not spellId then return {} end

    local kvpKey = 'th_power_spell_config_' .. spellId
    local configJson = GetResourceKvpString(kvpKey)

    if configJson and configJson ~= '' then
        local success, config = pcall(json.decode, configJson)
        if success and config and type(config) == 'table' then
            spellConfigs[spellId] = config
            return config
        end
    end

    return {}
end

local function SaveSpellConfig(spellId, config, skipCallback)
    if not spellId or not config then return false end

    spellConfigs[spellId] = config
    local kvpKey = 'th_power_spell_config_' .. spellId
    local configJson = json.encode(config)
    SetResourceKvp(kvpKey, configJson)

    if not skipCallback and spellConfigCallbacks[spellId] then
        spellConfigCallbacks[spellId](config)
    end

    return true
end

local function GetSpellConfig(spellId, key, defaultValue)
    local config = spellConfigs[spellId]
    if not config or next(config) == nil then
        config = LoadSpellConfig(spellId)
        if (not config or next(config) == nil) and defaultValue then
            if type(defaultValue) == 'table' then
                config = defaultValue
            elseif key then
                config = {}
                config[key] = defaultValue
            end
        end
    end

    if key then
        local value = config[key]
        if value == nil and defaultValue ~= nil then
            return defaultValue
        end
        return value
    end

    return config
end

local function SetSpellConfig(spellId, key, value)
    local config = GetSpellConfig(spellId)
    config[key] = value
    return SaveSpellConfig(spellId, config)
end

local function RegisterSpellConfigCallback(spellId, callback)
    if type(callback) == 'function' then
        spellConfigCallbacks[spellId] = callback
    end
end

local function RegisterConfigurableSpell(spellId)
    for _, existingSpellId in ipairs(CONFIGURABLE_SPELLS) do
        if existingSpellId == spellId then
            return false
        end
    end

    table.insert(CONFIGURABLE_SPELLS, spellId)
    return true
end

local function OpenSpellConfigMenu()
    local selectedSpell = exports['th_power'] and exports['th_power'].getSelectedSpell and exports['th_power']:getSelectedSpell()

    if selectedSpell then
        for _, configurableSpellId in ipairs(CONFIGURABLE_SPELLS) do
            if selectedSpell == configurableSpellId then
                TriggerEvent('th_power:openSpellConfig', selectedSpell)
                return
            end
        end

        if #CONFIGURABLE_SPELLS > 0 then
            lib.notify({
                title = 'Configuration Sorts',
                description = 'Le sort sélectionné n\'a pas de configuration disponible. Ouverture du menu de sélection.',
                type = 'info',
                duration = 3000
            })
        end
    end

    local availableSpells = {}

    if exports['th_power'] and exports['th_power'].getPlayerSpells then
        local playerSpells = exports['th_power']:getPlayerSpells() or {}
        local playerSpellSet = {}
        for _, spellId in ipairs(playerSpells) do
            playerSpellSet[spellId] = true
        end

        for _, spellId in ipairs(CONFIGURABLE_SPELLS) do
            if playerSpellSet[spellId] then
                local spellInfo = exports['th_power'] and exports['th_power'].GetSpellInfo and exports['th_power']:GetSpellInfo(spellId)
                if spellInfo then
                    table.insert(availableSpells, {
                        id = spellInfo.id,
                        name = spellInfo.name,
                        description = spellInfo.description
                    })
                end
            end
        end
    end

    if #availableSpells == 0 then
        lib.notify({
            title = 'Configuration Sorts',
            description = selectedSpell and
                'Le sort sélectionné n\'a pas de configuration disponible. Aucun autre sort configurable trouvé.' or
                'Aucun sort configurable disponible',
            type = 'info'
        })
        return
    end

    table.sort(availableSpells, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    local menuOptions = {}
    for _, spell in ipairs(availableSpells) do
        table.insert(menuOptions, {
            label = spell.name,
            description = spell.description,
            args = { spellId = spell.id }
        })
    end

    lib.registerMenu({
        id = 'spell_config_main_menu',
        title = 'Configuration des Sorts',
        subtitle = 'Choisissez un sort à configurer',
        position = 'top-left',
        options = menuOptions
    }, function(selected, scrollIndex, args)
        if args and args.spellId then
            TriggerEvent('th_power:openSpellConfig', args.spellId)
        end
    end)

    lib.showMenu('spell_config_main_menu')
end

RegisterCommand('spell_config_menu', function()
    OpenSpellConfigMenu()
end, false)

RegisterKeyMapping('spell_config_menu', '~g~(SORTS)~s~ Configuration Sorts', 'keyboard', Config.SpellKeys.spellConfigMenu)

spellConfigCallbacks['transvalis'] = function(config)
    if exports['th_transvalis'] and exports['th_transvalis'].OpenTransvalisConfigMenu then
        exports['th_transvalis']:OpenTransvalisConfigMenu()
    else
        lib.notify({
            title = 'Configuration Transvalis',
            description = 'Module de configuration non disponible.',
            type = 'error'
        })
    end
end

RegisterNetEvent('th_power:openSpellConfig')
AddEventHandler('th_power:openSpellConfig', function(spellId)
    if spellConfigCallbacks[spellId] then
        spellConfigCallbacks[spellId](GetSpellConfig(spellId))
    else
        lib.notify({
            title = 'Configuration',
            description = 'Aucune configuration disponible pour ce sort.',
            type = 'error'
        })
    end
end)

RegisterNetEvent('th_power:registerConfigurableSpell')
AddEventHandler('th_power:registerConfigurableSpell', function(spellId)
    RegisterConfigurableSpell(spellId)
end)

exports('GetSpellConfig', GetSpellConfig)
exports('SetSpellConfig', SetSpellConfig)
exports('SaveSpellConfig', SaveSpellConfig)
exports('LoadSpellConfig', LoadSpellConfig)
exports('RegisterSpellConfigCallback', RegisterSpellConfigCallback)
exports('OpenSpellConfigMenu', OpenSpellConfigMenu)
exports('RegisterConfigurableSpell', RegisterConfigurableSpell)

_ENV.spellConfigManager = {
    GetSpellConfig = GetSpellConfig,
    SetSpellConfig = SetSpellConfig,
    SaveSpellConfig = SaveSpellConfig,
    LoadSpellConfig = LoadSpellConfig,
    RegisterSpellConfigCallback = RegisterSpellConfigCallback,
    OpenSpellConfigMenu = OpenSpellConfigMenu,
    RegisterConfigurableSpell = RegisterConfigurableSpell
}