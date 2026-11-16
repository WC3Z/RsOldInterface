local sprite_swapper = require("src/game/sprite_swapper")
local sprite_groups = require("src/game/sprite_groups")
local settings = require("src/database/settings")
local settings_view = require("src/interface/settings_view")

-- Starts again with the groups of the options that are on (the game's own look comes back first).
local function swap_what_is_on()
    sprite_swapper.start(sprite_groups.names(settings.is_on))
end

swap_what_is_on()
settings_view.start(swap_what_is_on)

function PluginShutdown()
    settings_view.stop()
    sprite_swapper.stop()
end
