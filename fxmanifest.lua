fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'DP-Scripts'
description 'DP-MultiCharacter - Sistema de selección de personajes optimizado'
version '1.0.0'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'config.lua',
    'locales/sistema.lua',
    'locales/de.lua',
    'locales/en.lua',
    'locales/es.lua',
    'locales/fr.lua',
    'locales/it.lua',
    'locales/pt.lua'
}

client_scripts {
    'client/cl_main.lua',
    'client/cl_events.lua',
    'client/cl_utils.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_main.lua',
    'server/sv_database.lua',
    'server/sv_utils.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/js/app.js',
    'ui/js/sounds.js',
    'ui/js/validators.js',
    'ui/img/bg1.jpg',
    'ui/img/bg2.png',
    'ui/img/bg3.jpg'
}

dependencies {
    'qb-core'
}