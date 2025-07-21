fx_version 'cerulean'
game 'gta5'

author 'SmartFire System'
description 'Advanced Fire System for FiveM with spreading, sync and performance optimization'
version '1.0.0'

-- Shared files
shared_scripts {
    'shared/config.lua',
    'shared/utils.lua'
}

-- Client files
client_scripts {
    'client/main.lua',
    'client/fire_renderer.lua',
    'client/effects.lua',
    'client/commands.lua'
}

-- Server files
server_scripts {
    'server/main.lua',
    'server/fire_handler.lua',
    'server/sync.lua',
    'server/commands.lua'
}

-- Core files
files {
    'core/fire_manager.lua'
}

dependencies {
    'spawnmanager'
}