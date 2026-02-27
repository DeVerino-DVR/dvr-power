---@diagnostic disable: undefined-global
local PlayerCache <const> = require 'server.player_cache'
local lastActionBySource = {}
local logQueue = {}
local isSending = false
local MAX_LEVEL <const> = (Config.Leveling and Config.Leveling.max_level) or 5

if (not Config.Logs.webhook or Config.Logs.webhook == '') then
    local convarWebhook = GetConvar('dvr_power_logs_webhook', '')
    if convarWebhook and convarWebhook ~= '' then
        Config.Logs.webhook = convarWebhook
    end
end

local function resolveWebhook(entryWebhook)
    if entryWebhook and entryWebhook ~= '' then
        return entryWebhook
    end

    if Config.Logs and Config.Logs.webhook and Config.Logs.webhook ~= '' then
        return Config.Logs.webhook
    end

    return nil
end

local function getIdentifierByType(player, idType)
    if not player or not player.getIdentifier then
        return nil
    end
    local identifier <const> = player.getIdentifier()
    if idType == 'license' then
        return identifier
    end

    if player.getIdentifiers then
        local identifiers <const> = player.getIdentifiers()
        for _, id in ipairs(identifiers) do
            if idType == 'discord' and id:find('discord:') then
                return id
            elseif idType == 'steam' and id:find('steam:') then
                return id
            elseif idType == 'fivem' and id:find('fivem:') then
                return id
            end
        end
    end

    return identifier
end

local function extractDiscordId(ident)
    if not ident or type(ident) ~= 'string' then
        return nil
    end
    if ident:find('discord:') then
        return ident:gsub('discord:', '')
    end
    return nil
end

local function GetDiscordID(src)
    if not src then return nil end
    local ids <const> = GetPlayerIdentifiers(src)
    if not ids then return nil end
    for _, v in ipairs(ids) do
        if string.sub(v, 1, 8) == "discord:" then
            return v:sub(9)
        end
    end
    return nil
end

local function formatDiscordMention(discordId)
    if not discordId or discordId == '' then
        return 'Non lié'
    end
    return ('<@%s>'):format(discordId)
end

local function formatCoords(coords)
    if not coords then
        return 'Inconnues'
    end
    local x <const> = coords.x or 0.0
    local y <const> = coords.y or 0.0
    local z <const> = coords.z or 0.0
    return ('x: %.2f, y: %.2f, z: %.2f'):format(x, y, z)
end

local function buildFields(data, actionType)
    local prof <const> = data.professor or {}
    local target <const> = data.target or {}
    local spell <const> = data.spell or {}
    local context <const> = data.context or {}

    local fields = {}

    local profName = '👨‍🏫 Professeur'
    if actionType == 'spell_cast' then
        profName = '🏹 Lanceur'
    end

    fields[#fields + 1] = {
        name = profName,
        value = ('**%s**\nDiscord: %s `%s`'):format(prof.name or 'Inconnu', formatDiscordMention(prof.discordId), prof.discordId or 'Inconnu'),
        inline = false
    }

    if target and (target.name or target.discordId) then
        fields[#fields + 1] = {
            name = '🎓 Élève',
            value = ('**%s**\nDiscord: %s `%s`'):format(target.name or 'Inconnu', formatDiscordMention(target.discordId), target.discordId or 'Inconnu'),
            inline = false
        }
    end

    if spell and spell.id then
        local spellValue = ('**%s** (`%s`)'):format(spell.name or spell.id, spell.id)
        if spell.level then
            spellValue = spellValue .. ('\nNiveau %s/%s'):format(spell.level or '?', MAX_LEVEL)
        end
        fields[#fields + 1] = {
            name = '✨ Sort',
            value = spellValue,
            inline = false
        }
    end

    if actionType ~= 'spell_cast' then
        fields[#fields + 1] = {
            name = '📌 Type',
            value = context.temp and '**Temporaire**' or '**Définitif**',
            inline = false
        }
    end

    return fields
end

local function processQueue()
    if isSending then return end
    if #logQueue == 0 then return end
    isSending = true
    local entry <const> = table.remove(logQueue, 1)

    if not entry or not entry.embed then
        if Config.Logs.debug then
            print('[dvr_power] LogDiscord: entrée invalide, log ignoré')
        end
        isSending = false
        if #logQueue > 0 then
            processQueue()
        end
        return
    end

    local webhook <const> = resolveWebhook(entry.webhook)
    if not webhook or webhook == '' then
        if Config.Logs.debug then
            print('[dvr_power] LogDiscord: webhook absent, log ignoré')
        end
        isSending = false
        if #logQueue > 0 then
            processQueue()
        end
        return
    end

    local payload <const> = {
        username = entry.username or Config.Logs.server_name or 'Vlight',
        embeds = { entry.embed }
    }

    if entry.content then
        payload.content = entry.content
    end

    if entry.allowed_mentions then
        payload.allowed_mentions = entry.allowed_mentions
    end

    local jsonPayload <const> = json.encode(payload)
    if Config.Logs.debug then
        print('[dvr_power] LogDiscord payload:', jsonPayload)
    end

    PerformHttpRequest(webhook, function(status, body, headers)
        if Config.Logs.debug then
            print('[dvr_power] Discord response:', status, body or 'nil')
        end
        isSending = false
        if #logQueue > 0 then
            processQueue()
        end
    end, 'POST', jsonPayload, { ['Content-Type'] = 'application/json' })
end

local function enqueueLog(entry)
    logQueue[#logQueue + 1] = entry
    processQueue()
end

local function shouldDebounce(source, actionKey)
    local debounce = (Config.Logs and Config.Logs.debounce_ms) or 0
    if debounce <= 0 then
        return false
    end
    local now <const> = GetGameTimer()
    local key <const> = ("%s_%s"):format(source or 0, actionKey or 'action')
    local last <const> = lastActionBySource[key]
    if last and (now - last) < debounce then
        return true
    end
    lastActionBySource[key] = now
    return false
end

local function buildPlayerInfo(src)
    local player <const> = ESX.GetPlayerFromId(src)
    if not player then
        return { name = ('Joueur %s'):format(src or '?') }
    end

    return {
        name = player.getName() or ('Joueur %s'):format(src),
        license = getIdentifierByType(player, 'license'),
        discord = getIdentifierByType(player, 'discord'),
        discordId = GetDiscordID(src) or extractDiscordId(getIdentifierByType(player, 'discord')),
        steam = getIdentifierByType(player, 'steam')
    }
end

local function enrichIdentity(info)
    if not info then return {} end

    if info.source then
        local live <const> = buildPlayerInfo(info.source)
        info.name = info.name or live.name
        info.license = info.license or live.license
        info.discord = info.discord or live.discord
        info.discordId = info.discordId or live.discordId or GetDiscordID(info.source)
        info.steam = info.steam or live.steam
    elseif info.license then
        local src <const> = PlayerCache.GetSource(info.license)
        local player <const> = src and (PlayerCache.GetPlayer(src) or ESX.GetPlayerFromId(src)) or nil
        if player then
            info.discord = info.discord or getIdentifierByType(player, 'discord')
            info.discordId = info.discordId or GetDiscordID(src) or extractDiscordId(info.discord)
        end
    end

    if info.discord and not info.discordId then
        info.discordId = extractDiscordId(info.discord)
    end

    return info
end

local function sendLog(actionType, data)
    if not Config or not Config.Logs or not Config.Logs.webhook or Config.Logs.webhook == '' then
        return
    end

    if shouldDebounce(data.professor and data.professor.source or 0, actionType) then
        return
    end

    local titleMap = {
        give_def = 'Professeur : Attribution sort définitif',
        remove_def = 'Professeur : Retrait sort définitif',
        set_level = 'Professeur : Modification niveau',
        mass_add = 'Professeur : Ajout de tous les sorts',
        mass_remove = 'Professeur : Retrait de tous les sorts',
        mass_level = 'Professeur : Niveau global',
        give_temp = 'Professeur : Attribution sort temporaire',
        remove_temp = 'Professeur : Retrait sort temporaire',
        set_temp_level = 'Professeur : Modification niveau temporaire',
        temp_group = 'Professeur : Attribution temporaire de groupe',
        temp_clear = 'Professeur : Fin de cours (nettoyage temporaires)',
        reload = 'Professeur : Reload configuration',
        menu = 'Professeur : Ouverture/Fermeture menu'
    }

    titleMap.spell_cast = 'Lancement de sort'

    data.professor = enrichIdentity(data.professor)
    data.target = enrichIdentity(data.target)

    local embed <const> = {
        title = titleMap[actionType] or 'Log Professeur',
        color = 16747520,
        fields = buildFields(data, actionType),
        footer = { text = ("%s | %s"):format(Config.Logs.server_name or 'Vlight', os.date('%d/%m/%Y à %H:%M')) },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    }

    enqueueLog({ embed = embed })
end

local function LogDeath(data)
    if not Config or not Config.Logs or not Config.Logs.deadvr_webhook or Config.Logs.deadvr_webhook == '' then
        return
    end

    data = data or {}

    local hp <const> = data.hp or {}
    if not hp.current or hp.current > 0 then
        return
    end

    local victim <const> = enrichIdentity({
        source = data.source,
        name = data.name,
        license = data.license,
        discord = data.discord,
        discordId = data.discordId,
        steam = data.steam
    })
    local killer <const> = data.killer and enrichIdentity(data.killer) or nil
    local removeHp <const> = data.removeHp or 0
    local deathType <const> = data.deathType or 'Inconnue'

    local fields <const> = {}

    fields[#fields + 1] = {
        name = 'Victime',
        value = ('**%s** (ID %s)\nDiscord: %s'):format(victim.name or 'Inconnu', data.source or '?', formatDiscordMention(victim.discordId)),
        inline = false
    }

    fields[#fields + 1] = {
        name = 'Identifiants',
        value = ('License: %s\nSteam: %s'):format(victim.license or 'Inconnue', victim.steam or 'Inconnu'),
        inline = false
    }

    fields[#fields + 1] = {
        name = 'Cause',
        value = deathType .. (data.causeHash and (' (`%s`)'):format(tostring(data.causeHash)) or ''),
        inline = true
    }

    fields[#fields + 1] = {
        name = 'HP magiques',
        value = ('%s/%s (-%s%%)'):format(hp.current or '?', hp.max or '?', removeHp),
        inline = true
    }

    if killer and (killer.name or killer.discordId or killer.source) then
        fields[#fields + 1] = {
            name = 'Tueur',
            value = ('%s\nDiscord: %s'):format(killer.name or ('ID ' .. (killer.source or '?')), formatDiscordMention(killer.discordId)),
            inline = false
        }
    end

    if data.coords then
        fields[#fields + 1] = {
            name = 'Position',
            value = formatCoords(data.coords),
            inline = false
        }
    end

    local embed <const> = {
        title = 'Mort RP détectée',
        description = 'Un joueur vient d\'atteindre 0 HP RP.',
        color = 15158332,
        fields = fields,
        footer = { text = ("%s | %s"):format(Config.Logs.server_name or 'Vlight', os.date('%d/%m/%Y à %H:%M')) },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    }

    enqueueLog({
        embed = embed,
        webhook = Config.Logs.deadvr_webhook
    })
end

local LogDiscord = setmetatable({}, {
    __call = function(_, actionType, data)
        return sendLog(actionType, data)
    end
})

LogDiscord.LogDeath = LogDeath

_G.TH_Power = _G.TH_Power or {}
_G.TH_Power.Log = LogDiscord

return LogDiscord
