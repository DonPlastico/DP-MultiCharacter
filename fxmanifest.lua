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
    'client/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    
    'ui/*.css',
    'ui/js/*.js',
    'ui/lib/*.js',
    'ui/lib/*.css',
    'ui/img/*.jpg',
    'ui/img/*.png',
    'ui/items/*.png',
    'ui/items/*.jpg',
    'ui/items/*.svg',
    'ui/items/*.webp',
}

dependencies {
    'qb-core'
}