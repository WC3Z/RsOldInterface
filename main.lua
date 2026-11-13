local sprite_swapper = require("src/game/sprite_swapper")

sprite_swapper.start()

function PluginShutdown()
    sprite_swapper.stop()
end
