local sprite_swapper = require("src/game/sprite_swapper")
local sprite_groups = require("src/game/sprite_groups")
local settings = require("src/database/settings")
local content_view = require("src/interface/content_view")
local settings_window = require("src/interface/settings_window")

-- Starts again with the groups of the options that are on, in the chosen colour scheme (the game's
-- own look comes back first).
local function swap_what_is_on()
    sprite_swapper.start(sprite_groups.names(settings.is_on), settings.colours(), settings.has_textured_panels())
end

swap_what_is_on()
settings_window.start(swap_what_is_on)
content_view.start()

function PluginShutdown()
    content_view.stop()
    settings_window.stop()
    sprite_swapper.stop()
end
