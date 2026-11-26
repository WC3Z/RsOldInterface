-- Release builds leave out the debug tools (src/debug): the swapping works without them.
package.path = "./?.lua;" .. package.path
for _, name in ipairs({ "src/debug/events", "src/debug/activity_log", "src/debug/profile", "src/debug/unstyled", "src/debug/layout" }) do
    package.preload[name] = function () error(name .. " isn't in release builds") end
end

local printed = {}
print = function (text) printed[#printed + 1] = tostring(text) end

local handlers = { Logic = {}, Draw = {}, KeyDown = {}, ServerLogic = {} }
Event = {}
for name, list in pairs(handlers) do
    Event[name] = { Subscribe = function (n, f) list[n] = f end, Unsubscribe = function (n) list[n] = nil end }
end
ui = { ComponentType = { LINE = "LINE", RECTANGLE = "RECTANGLE", LABEL = "LABEL", SPRITE = "SPRITE", BUTTON = "BUTTON", CHECK = "CHECK", LIST = "LIST", INPUTFIELD = "INPUTFIELD", SLIDER = "SLIDER", COMBO = "COMBO", CAROUSEL = "CAROUSEL", PAGED_CAROUSEL = "PAGED_CAROUSEL", RADIO_GROUP = "RADIO_GROUP", LAYER = "LAYER", PANEL = "PANEL", GRID = "GRID", PAGED_LAYER = "PAGED_LAYER", GROUP_BOX = "GROUP_BOX" } }
id = {
    Sprite = { FromID = function (sprite_id) return sprite_id == 101 and "RS3_BTN_MAIN_NEUTRAL_0" or nil end },
    Interface = setmetatable({ FromID = function (interface_id) return tostring(interface_id) end }, { __index = function () return nil end }),
}
Plugin = { resources = { frames = { RS3_BTN_MAIN_NEUTRAL_0 = "old button" } } }
config = { Enum = {} }

local button = { interfaceID = 5, staticID = 0, categoryID = -1, dynamicID = -1, type = ui.ComponentType.SPRITE, spriteID = 101, visibleGlobal = true }
setmetatable(button, { __newindex = function (t, k, v)
    if k == "sprite" then rawset(t, "spriteID", type(v) == "number" and v or -1) else rawset(t, k, v) end
end })
ui.Interfaces = {
    GetInterface = function (_, interface_id) return interface_id == 5 and { id = 5 } or nil end,
    GetComponent = function (_, interface_id, static_id) return interface_id == 5 and static_id == 0 and button or nil end,
}

local debug_tools = require("src/game/debug_tools")
assert(debug_tools.events.enabled == false, "the stand-in is switched off")
debug_tools.events.enable({ profile = true })
assert(debug_tools.events.enabled == false, "and stays off")

local sprite_swapper = require("src/game/sprite_swapper")
local sprite_groups = require("src/game/sprite_groups")
sprite_swapper.start(sprite_groups.names(function () return true end))
for _ = 1, 20 do
    for _, handler in pairs(handlers.Logic) do handler({}) end
    for _, handler in pairs(handlers.Draw) do handler({}) end
end
assert(button.spriteID == -1, "swapped without the debug tools")
button.spriteID = 101
for _, handler in pairs(handlers.Logic) do handler({}) end
for _, handler in pairs(handlers.Draw) do handler({}) end
assert(button.spriteID == -1, "swapped again without the debug tools")
sprite_swapper.stop()
assert(button.spriteID == 101, "put back on stop")
assert(#printed == 0, "nothing printed: " .. tostring(printed[1]))
