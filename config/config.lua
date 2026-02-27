---@diagnostic disable: trailing-space
local Config <const> = {}
Config.ApplySound = "YOUR_SOUND_URL_HERE" -- Sound played when spell is cast successfully
Config.EchecSound = "YOUR_SOUND_URL_HERE" -- Sound played when spell fails
Config.IsServer = IsDuplicityVersion()
Config.IsClient = not Config.IsServer

Config.WandWeapon = 'WEAPON_WAND'
Config.MaxSpellDistance = 50.0
Config.DefaultCooldown = 5000
Config.ThunderSoundUrl = "YOUR_SOUND_URL_HERE" -- Thunder/explosion sound effect
Config.ThunderSoundVolume = 0.85
Config.ThunderSoundDistance = 80.0
Config.MagicHPRespawnTime = 0

-- Identifiants immunisés aux dégâts magiques et à la perte de HP RP
-- Supporte tous types : license, discord, steam, fivem, ip, etc.
-- Exemples :
--   'license:abc123def456'
--   'discord:123456789012345678'
--   'steam:110000112345678'
--   'fivem:12345'
Config.DamageImmunity = {
    -- 'discord:YOUR_DISCORD_ID',
    -- 'license:YOUR_LICENSE',
}

Config.DeathCause = {
    {removeHp = 0, name = 'Melee', id = { -1569615261, 1737195953, 1317494643, -1786099057, 1141786504, -2067956739, -868994466 }},
    {removeHp = 1, name = 'Knife', id = { -1716189206, 1223143800, -1955384325, -1833087301, 910830060, }},
    {removeHp = 5, name = 'Bullet', id = { 453432689, 1593441988, 584646201, -1716589765, 324215364, 736523883, -270015777, -1074790547, -2084633992, -1357824103, -1660422300, 2144741730, 487013001, 2017895192, -494615257, -1654528753, 100416529, 205991906, 1119849093 }},
    {removeHp = 2, name = 'Animal', id = { -100946242, 148160082 }},
    {removeHp = 5, name = 'FallDamage', id = { -842959696 }},
    {removeHp = 10, name = 'Explosion', id = { -1568386805, 1305664598, -1312131151, 375527679, 324506233, 1752584910, -1813897027, 741814745, -37975472, 539292904, 341774354, -1090665087 }},
    {removeHp = 5, name = 'Gas', id = { -1600701090 }},
    {removeHp = 10, name = 'Burn', id = { 615608432, 883325847, -544306709 }},
    {removeHp = 5, name = 'Drown', id = { -10959621, 1936677264 }},
    {removeHp = 5, name = 'Car', id = { 133987706, -1553120962 }},
}

Config.SpellColors = {
    red = {r = 255, g = 50, b = 50},
    blue = {r = 50, g = 100, b = 255},
    green = {r = 50, g = 255, b = 100},
    purple = {r = 150, g = 50, b = 200},
    yellow = {r = 255, g = 255, b = 50},
    white = {r = 255, g = 255, b = 255},
    black = {r = 20, g = 20, b = 20},
    orange = {r = 255, g = 150, b = 50}
}

Config.JobTrailColors = {
    wand_professeur = { r = 255, g = 0, b = 0 },        -- rouge
    professeur = { r = 60, g = 140, b = 255 },          -- bleu
    potion = { r = 170, g = 80, b = 200 },              -- violet
    herbomagie = { r = 0, g = 255, b = 0 },             -- vert
    employe = { r = 255, g = 255, b = 255 },            -- blanc
    direction = { r = 255, g = 200, b = 60 },           -- or
    baguette = { r = 125, g = 90, b = 55 },             -- marron
    sennara = { r = 255, g = 255, b = 255 },            -- blanc
    dahrion = { r = 255, g = 255, b = 255 },            -- blanc
    veylaryn = { r = 255, g = 255, b = 255 },           -- blanc
    thaelora = { r = 255, g = 255, b = 255 },           -- blanc
    magenoir = { r = 0, g = 0, b = 0 },                 -- noir
    default = { r = 255, g = 255, b = 255 }             -- blanc / défaut
}

Config.SpellTypes = {
    ATTACK = 'attack',      -- Sorts offensifs
    DEFENSE = 'defense',    -- Sorts défensifs
    UTILITY = 'utility',    -- Sorts utilitaires
    HEAL = 'heal',         -- Sorts de soin
    CONTROL = 'control',   -- Sorts de contrôle
    SUMMON = 'summon'      -- Sorts d'invocation
}

Config.Spells = {}

Config.Leveling = {
    enabled = true,
    max_level = 5,
    default_level = 0,
    training_level = 0, -- Niveau <= à cette valeur = version d'entraînement
    min_quality = 0.35, -- Intensité minimale des FX pour les faibles niveaux
    min_sound_level = 2, -- Niveau requis pour déclencher les sons de sort
    cooldown_multiplier = {
        minimum = 1.0,  -- Multiplicateur appliqué au niveau maximum
        maximum = 3.0   -- Multiplicateur appliqué au niveau 0
    },
    cooldown_divider = {
        enabled = true, -- Divise le cooldown de base à mesure que le niveau augmente
        step = 0.15     -- Plus cette valeur est grande, plus le cooldown diminue vite (1 lvl = base/(1 + lvl*step))
    },
    range_multiplier = {
        minimum = 0.1,
        maximum = 1.0,
        curve = 1.65, -- >1 ralentit la progression, <1 l'accélère
        levels = { 0.12, 0.25, 0.45, 0.75, 0.9, 1.0 } -- progression 0->5 (index 0 = 0.12, 5 = 1.0)
    },
    backfire = {
        max_level = 1,              -- Appliquer la punition aux petits niveaux uniquement
        base_chance = 0.4,          -- Chance quand niveau = 0
        chance_reduction_per_level = 0.2,
        damage = 15
    },
    training_fx = {
        particle_dict = 'core',
        particle_name = 'ent_amb_smoke_factory',
        scale = 1.25,
        duration = 2000
    },
    backfire_fx = {
        particle_dict = 'core',
        particle_name = 'ent_amb_fire_ring',
        scale = 1.0,
        duration = 1500
    }
}

Config.SpellLevelOverrides = {
    lumora = {
        max_level = 5,
        default_level = 0,
        min_sound_level = 0
    },
    prothea = {
        max_level = 5,
        default_level = 0
    }
}

-- Touches configurables pour les sorts
Config.SpellKeys = {
    -- Touche pour ouvrir le menu de configuration des sorts
    spellConfigMenu = 'M'
}

_ENV.Config = Config
