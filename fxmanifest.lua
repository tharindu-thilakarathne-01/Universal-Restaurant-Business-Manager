fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'restaurant_manager'
author 'Senior FiveM Developer'
description 'Universal Multi-Restaurant & Business Management Framework for QBCore / Qbox (Burger Shot, Pizza This, Cafes, Bars, Diners & Food Trucks)'
version '1.0.0'

ui_page 'web/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/en.lua',
    'locales/si.lua'
}

client_scripts {
    'client/main.lua',
    'client/doors.lua',
    'client/nui.lua',
    'client/target.lua',
    'client/placement.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/doors.lua',
    'server/orders.lua',
    'server/stations.lua',
    'server/recipes.lua',
    'server/roles.lua',
    'server/stock.lua',
    'server/vending.lua',
    'server/logs.lua'
}

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/images/**',
    'web/images/*'
}

dependencies {
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'oxmysql'
}
