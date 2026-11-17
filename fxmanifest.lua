fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'whip_persist'
description 'Street cars players drove stay where they are left, and come back if the game removes them (this session). Owned cars are whip_core\'s own.'
version '0.1.0'
author 'Flek'

shared_script '@whip_core/lib/satellite.lua'
shared_script 'config.lua'
client_script 'client/main.lua'
server_script 'server/main.lua'

dependencies { 'whip_core' }
whip_requires '1.0'
