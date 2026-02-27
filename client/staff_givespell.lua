---@diagnostic disable: undefined-global, trailing-space, unused-local, param-type-mismatch
local math_floor = math.floor
local table_sort = table.sort
local tonumber = tonumber

local MENU_ID_PLAYERS <const> = 'th_power:staff_givespell_players'
local MENU_ID_SPELLS <const> = 'th_power:staff_givespell_spells'
local REMOVE_LABEL <const> = 'retirer'
local LEVEL_VALUES <const> = { '1', '2', '3', '4', '5', REMOVE_LABEL }
local NUI_BASE <const> = 'nui://th_power/html/'

local function FetchSpells()
    local spells = lib.callback.await('th_power:staffGetSpells', false) or {}
    table_sort(spells, function(a, b)
        local an = (a.name or a.id or ''):lower()
        local bn = (b.name or b.id or ''):lower()
        if an == bn then
            return (a.id or '') < (b.id or '')
        end
        return an < bn
    end)
    return spells
end

local function FetchPlayers()
    local players = lib.callback.await('th_power:professorGetPlayers', false) or {}
    table_sort(players, function(a, b)
        return (a.name or '') < (b.name or '')
    end)
    return players
end

local function ResolveLevelSelection(scrollIndex)
    local value = LEVEL_VALUES[scrollIndex or 1] or LEVEL_VALUES[1]
    if value == REMOVE_LABEL then
        return nil, true
    end

    local numeric = math_floor(tonumber(value) or 1)
    if numeric < 1 then numeric = 1 end
    if numeric > 5 then numeric = 5 end
    return numeric, false
end

local function ShowSpellMenu(targetPlayerId, targetPlayerName)
    local spells = FetchSpells()
    if #spells == 0 then
        lib.notify({
            title = 'GiveSpell',
            description = 'Aucun sort disponible.',
            type = 'error'
        })
        return
    end

    local options = {}
    for i = 1, #spells do
        local spell = spells[i]
        options[#options + 1] = {
            label = string.format('%s (%s)', spell.name or spell.id, spell.id),
            description = spell.description or '',
            icon = NUI_BASE.. spell.image,
            values = LEVEL_VALUES,
            args = {
                spellId = spell.id,
                targetPlayerId = targetPlayerId
            },
            close = false
        }
    end

    lib.registerMenu({
        id = MENU_ID_SPELLS,
        title = 'GiveSpell - ' .. targetPlayerName,
        position = 'top-right',
        options = options
    }, function(selected, scrollIndex, args)
        if not args or not args.spellId then
            return
        end
        local level, removeSpell = ResolveLevelSelection(scrollIndex)
        TriggerServerEvent('th_power:staffGiveSpell', args.spellId, level or 0, removeSpell, args.targetPlayerId)
    end)

    lib.showMenu(MENU_ID_SPELLS)
end

local function ShowPlayerMenu()
    local players = FetchPlayers()
    if #players == 0 then
        lib.notify({
            title = 'GiveSpell',
            description = 'Aucun joueur en ligne.',
            type = 'error'
        })
        return
    end

    local myServerId = GetPlayerServerId(PlayerId())
    local options = {}

    -- Ajouter "Moi-même" en premier
    options[#options + 1] = {
        label = 'Moi-même',
        description = 'Attribuer un sort à vous-même',
        icon = 'user',
        args = {
            playerId = myServerId,
            playerName = 'Vous'
        }
    }

    -- Ajouter les autres joueurs
    for i = 1, #players do
        local player = players[i]
        if player.id ~= myServerId then
            options[#options + 1] = {
                label = player.name or ('Joueur ' .. player.id),
                description = 'ID: ' .. player.id,
                icon = 'user',
                args = {
                    playerId = player.id,
                    playerName = player.name or ('Joueur ' .. player.id)
                }
            }
        end
    end

    lib.registerMenu({
        id = MENU_ID_PLAYERS,
        title = 'GiveSpell - Sélection joueur',
        position = 'top-right',
        options = options
    }, function(selected, scrollIndex, args)
        if not args or not args.playerId then
            return
        end
        ShowSpellMenu(args.playerId, args.playerName)
    end)

    lib.showMenu(MENU_ID_PLAYERS)
end

local function OpenStaffGiveSpell()
    ShowPlayerMenu()
end

RegisterNetEvent('th_power:openStaffSpellMenu', function()
    OpenStaffGiveSpell()
end)

RegisterNetEvent('th_power:staffSpellResult', function(success, message)
    if not message then
        return
    end
    lib.notify({
        title = 'GiveSpell',
        description = message,
        type = success and 'success' or 'error'
    })
end)
