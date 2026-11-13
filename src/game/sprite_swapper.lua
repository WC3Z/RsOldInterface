-- Draws the old (blue) interface sprites in place of the game's current ones, and puts the game's
-- sprites back when stopped. An image in resources/frames/ replaces the game sprite with the same
-- name, so resources/frames/RS3_CHILD_CONTENT_TILE.png replaces RS3_CHILD_CONTENT_TILE.
--
-- Only some sprites are swapped: the frames of the windows docked around the game screen, every
-- window's background, and tooltips. Backgrounds are tiles the game repeats to fill a window, or
-- the middle of a frame built from 3x3 pieces (piece 4), which the game stretches to fill the
-- frame, so they fit whatever their size. Left out are the frames of big windows like Settings
-- (their old sprites are different sizes and break the layout) and window contents like buttons,
-- tabs and list rows: the game changes those all the time (hover and selected states, rebuilt
-- lists), and each change shows the game's sprite until it's swapped again, so they flash.
local interface_walker = require("src/game/interface_walker")
local interface_watcher = require("src/game/interface_watcher")

local sprite_swapper = {}

local subscription_name = "old-interface-sprite-swapper"
local draw_subscription_name = "old-interface-sprite-swapper-draw"

local swapped_sprite_patterns = {
    "^RS3_CHILD_",
    "^RS3_HUD_WINDOW_",
    "^RS3_TOOLTIP_FILL_",
    "^RS3_[A-Z_]*CONTENT_TILE$",
    "^RS3_CONTENT_FRAME_4$",
    "^RS3_PARENT_CONTENT_TAB_FRAME_4$",
}
-- Docked windows' tabs change sprite when clicked.
local unswapped_sprites = {
    RS3_CHILD_TAB_SELECTED = true,
    RS3_CHILD_TAB_UNSELECTED = true,
}

---@type InterfaceWatch?
local watch = nil

-- The plugin's image for each game sprite seen so far, by sprite ID, or false for sprites it
-- doesn't swap. The resources can't be listed, so each sprite's image is looked up by name.
---@type table<integer, PluginResource|false>
local image_cache = {}

-- Each swapped component's IDs and the game sprite it had, keyed by
-- interface_walker.component_key. When the game rebuilds a component it keeps its IDs, so they
-- find it again, both to swap it back right away and to restore it.
---@class SwappedComponent
---@field interface_id integer
---@field static_id integer
---@field category_id integer
---@field dynamic_id integer
---@field original_sprite_id integer

---@type table<string, SwappedComponent>
local swapped_components = {}

---@param sprite_name string
local function is_swapped_sprite(sprite_name)
    if unswapped_sprites[sprite_name] then
        return false
    end
    for _, pattern in ipairs(swapped_sprite_patterns) do
        if sprite_name:find(pattern) then
            return true
        end
    end
    return false
end

---@param sprite_id integer
---@return PluginResource?
local function image_for(sprite_id)
    local image = image_cache[sprite_id]
    if image == nil then
        image = false
        local frames = Plugin.resources and Plugin.resources.frames
        local found, sprite_name = pcall(id.Sprite.FromID, sprite_id)
        if frames and found and sprite_name and is_swapped_sprite(sprite_name) then
            image = frames[sprite_name] or frames[sprite_name .. ".png"] or false
        end
        image_cache[sprite_id] = image
    end
    return image or nil
end

-- Called for every component of every loaded window several times a second, so it does as
-- little as it can for the many that aren't swapped.
---@param component ui.Component
---@return boolean # Whether the component is swapped, or may be (sprites drawing a runtime image
-- report -1, as swapped ones do).
local function swap(component)
    if component.type ~= ui.ComponentType.SPRITE then
        return false
    end
    ---@cast component ui.Sprite
    local sprite_id = component.spriteID
    if sprite_id == -1 then
        return true
    end
    local image = image_for(sprite_id)
    if not image then
        return false
    end
    local set = pcall(function ()
        component.sprite = image
    end)
    if not set then
        return false
    end
    swapped_components[interface_walker.component_key(component)] = {
        interface_id = component.interfaceID,
        static_id = component.staticID,
        category_id = component.categoryID,
        dynamic_id = component.dynamicID,
        original_sprite_id = sprite_id,
    }
    return true
end

-- Looked up fresh each time: the game may have destroyed or rebuilt the component since.
---@param swapped SwappedComponent
---@return ui.Sprite?
local function find_swapped(swapped)
    local component
    if swapped.category_id == -1 then
        component = ui.Interfaces:GetComponent(swapped.interface_id, swapped.static_id)
    else
        component = ui.Interfaces:GetComponent(swapped.interface_id, swapped.static_id, swapped.category_id, swapped.dynamic_id)
    end
    if component and component.type == ui.ComponentType.SPRITE then
        ---@cast component ui.Sprite
        return component
    end
    return nil
end

-- Just before each frame is drawn, swaps back the components the game has reset since (like the
-- tab bar when switching tabs), so its sprites don't show for a frame. Components that are gone
-- are forgotten; if their window opens again, the walk finds them.
local function reswap_reset_components()
    for key, swapped in pairs(swapped_components) do
        local component = find_swapped(swapped)
        if component == nil then
            swapped_components[key] = nil
        elseif component.spriteID == swapped.original_sprite_id then
            local image = image_for(swapped.original_sprite_id)
            if image then
                pcall(function ()
                    component.sprite = image
                end)
            end
        end
    end
end

-- Only components still showing the plugin's image get the game's sprite back.
local function restore_swapped_components()
    for _, swapped in pairs(swapped_components) do
        local component = find_swapped(swapped)
        if component and component.spriteID ~= swapped.original_sprite_id then
            pcall(function ()
                component.sprite = swapped.original_sprite_id
            end)
        end
    end
    swapped_components = {}
end

function sprite_swapper.start()
    sprite_swapper.stop()
    image_cache = {}
    watch = interface_watcher.start(subscription_name, swap)
    Event.Draw.Subscribe(draw_subscription_name, reswap_reset_components)
end

function sprite_swapper.stop()
    if watch == nil then
        return
    end
    interface_watcher.stop(watch)
    Event.Draw.Unsubscribe(draw_subscription_name)
    watch = nil
    restore_swapped_components()
end

return sprite_swapper
