fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'VLight RP'
description 'Système de sorts'
version '2.0.0'

shared_scripts {
    -- '@ox_lib/init.lua', -- REQUIRED: Install ox_lib (https://github.com/overextended/ox_lib)
    -- '@es_extended/imports.lua', -- REQUIRED: Install es_extended or your framework
    'config/config.lua',
    'config/logs.lua',
}

server_scripts {
    -- '@oxmysql/lib/MySQL.lua', -- REQUIRED: Install oxmysql (https://github.com/overextended/oxmysql)
    'server/logs.lua',
    'server/utils.lua',
    'server/damage_system.lua',
    'server/hp_system.lua',
    'server/main.lua',
    'server/hud.lua',
}

client_scripts {
    'client/utils.lua',
    'client/spell_damage.lua',
    'client/hp_system.lua',
    'client/main.lua',
    'client/module_loader.lua',
    'client/spell_config_manager.lua',
    'client/hud.lua',
    'client/professor/main.lua',
    'client/staff_givespell.lua',
    'client/dev.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/images/power/*.png',
    'html/images/hud/*.png',
    'html/images/logo/vlight_logo.png',
    'html/fonts/*.ttf'
}

-- dependencies {
--     'ox_lib', -- REQUIRED: Install ox_lib (https://github.com/overextended/ox_lib)
--     'oxmysql', -- REQUIRED: Install oxmysql (https://github.com/overextended/oxmysql)
--     'lo_audio' -- REPLACE WITH YOUR AUDIO RESOURCE
-- }

server_exports {
    'LogSpellCast',
    'ApplyAreaDamage',
    'ApplySpellDamage'
}
