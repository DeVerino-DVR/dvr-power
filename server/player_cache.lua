---@diagnostic disable: undefined-global
local GetPlayers <const> = GetPlayers
local GetPlayerName <const> = GetPlayerName
local pairs <const> = pairs
local table_sort <const> = table.sort
local tonumber <const> = tonumber
local type <const> = type

local playerEntriesBySource = {}
local sourceByIdentifier = {}
local playersListCache = {}
local playersListDirty = true

local PlayerCache = {}

local function TrackPlayer(source, xPlayer)
    local src <const> = tonumber(source)
    if not src or src <= 0 then
        return
    end

    local player = xPlayer
    if not player then
        if not ESX or type(ESX.GetPlayerFromId) ~= 'function' then
            return
        end
        player = ESX.GetPlayerFromId(src)
    end
    if not player then
        return
    end

    local identifier = player.identifier
    if not identifier and type(player.getIdentifier) == 'function' then
        identifier = player.getIdentifier()
    end
    if not identifier or identifier == '' then
        return
    end

    local name = nil
    if type(player.getName) == 'function' then
        name = player.getName()
    end
    if not name or name == '' then
        name = GetPlayerName(src) or ('Joueur %s'):format(src)
    end

    local existing = playerEntriesBySource[src]
    if existing and existing.identifier and existing.identifier ~= identifier and sourceByIdentifier[existing.identifier] == src then
        sourceByIdentifier[existing.identifier] = nil
    end

    playerEntriesBySource[src] = {
        source = src,
        identifier = identifier,
        name = name,
        player = player
    }
    sourceByIdentifier[identifier] = src
    playersListDirty = true
end

local function UntrackPlayer(source)
    local src <const> = tonumber(source)
    if not src then
        return
    end

    local existing = playerEntriesBySource[src]
    if not existing then
        return
    end

    playersListDirty = true
    playerEntriesBySource[src] = nil

    local identifier <const> = existing.identifier
    if identifier and sourceByIdentifier[identifier] == src then
        sourceByIdentifier[identifier] = nil
    end
end

function PlayerCache.Refresh()
    for key in pairs(playerEntriesBySource) do
        playerEntriesBySource[key] = nil
    end
    for key in pairs(sourceByIdentifier) do
        sourceByIdentifier[key] = nil
    end
    playersListCache = {}
    playersListDirty = true

    local players <const> = GetPlayers()
    for i = 1, #players do
        TrackPlayer(players[i], nil)
    end
end

function PlayerCache.Track(source, xPlayer)
    TrackPlayer(source, xPlayer)
end

function PlayerCache.Untrack(source)
    UntrackPlayer(source)
end

function PlayerCache.GetSource(identifier)
    if not identifier then
        return nil
    end
    return sourceByIdentifier[identifier]
end

function PlayerCache.GetIdentifier(source)
    local src <const> = tonumber(source)
    local entry <const> = src and playerEntriesBySource[src] or nil
    return entry and entry.identifier or nil
end

function PlayerCache.GetName(source)
    local src <const> = tonumber(source)
    local entry <const> = src and playerEntriesBySource[src] or nil
    return entry and entry.name or nil
end

function PlayerCache.GetPlayer(source)
    local src <const> = tonumber(source)
    local entry <const> = src and playerEntriesBySource[src] or nil
    return entry and entry.player or nil
end

function PlayerCache.GetPlayerByIdentifier(identifier)
    local src <const> = PlayerCache.GetSource(identifier)
    if not src then
        return nil
    end

    local cached <const> = PlayerCache.GetPlayer(src)
    if cached then
        return cached
    end

    local player <const> = ESX.GetPlayerFromId(src)
    if player then
        TrackPlayer(src, player)
        return player
    end

    return nil
end

function PlayerCache.ForEach(callback)
    if type(callback) ~= 'function' then
        return
    end
    for src, entry in pairs(playerEntriesBySource) do
        callback(src, entry)
    end
end

function PlayerCache.GetPlayers()
    if not playersListDirty and playersListCache then
        return playersListCache
    end

    local players = {}
    for src, entry in pairs(playerEntriesBySource) do
        if entry and entry.identifier then
            players[#players + 1] = {
                id = src,
                name = entry.name,
                identifier = entry.identifier
            }
        end
    end
    table_sort(players, function(a, b)
        return a.id < b.id
    end)

    playersListCache = players
    playersListDirty = false

    return playersListCache
end

AddEventHandler('esx:playerLoaded', function(source, xPlayer)
    TrackPlayer(source, xPlayer)
end)

AddEventHandler('playerDropped', function()
    UntrackPlayer(source)
end)

AddEventHandler('esx:playerLogout', function(playerId)
    UntrackPlayer(playerId)
end)

CreateThread(function()
    PlayerCache.Refresh()
end)

_G.TH_Power = _G.TH_Power or {}
_G.TH_Power.Players = PlayerCache

return PlayerCache
