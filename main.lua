local sprite_swapper = require("src/game/sprite_swapper")
local sprite_groups = require("src/game/sprite_groups")

-- EXPERIMENT: also swap window contents (buttons, tabs, list rows and the like). False keeps to
-- window frames, backgrounds and tooltips.
local with_window_contents = true

sprite_swapper.start(sprite_groups.names(with_window_contents))

function PluginShutdown()
    sprite_swapper.stop()
end
