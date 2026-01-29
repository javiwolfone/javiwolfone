fx_version 'cerulean'
game 'gta5'

author 'Tota Network'
description 'Sistema de ID Permanente optimizado con panel de administración para ESX y QBCore.'
version '2.0.0'

shared_scripts {
  'config.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/bridge.lua',
  'server/main.lua'
}

client_scripts {
  'client/bridge.lua',
  'client/main.lua'
}

ui_page 'ui/index.html'

files {
  'ui/index.html',
  'ui/style.css',
  'ui/script.js'
}