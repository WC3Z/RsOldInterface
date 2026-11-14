-- Draws the old (blue) interface sprites in place of the game's current ones, and puts the game's
-- sprites back when stopped. An image in resources/frames/ replaces the game sprite with the same
-- name, so resources/frames/RS3_CHILD_CONTENT_TILE.png replaces RS3_CHILD_CONTENT_TILE. Sprites
-- with no old image can have a built-in stand-in instead (see sprite_groups.stand_ins). Which
-- sprites are swapped is chosen by group (see sprite_groups).
--
-- A sprite component draws one sprite. Interactive components like buttons and dropdowns draw
-- theirs in parts (see sprite_parts), and each part is swapped on its own.
--
-- The game changes some sprites all the time (hover and selected states, rebuilt lists), so those
-- changes are swapped again just before each frame is drawn.
--
-- With the colours group on, plain coloured rectangles get the old colour too (see skin_palette).
local interface_walker = require("src/game/interface_walker")
local interface_watcher = require("src/game/interface_watcher")
local sprite_groups = require("src/game/sprite_groups")
local skin_palette = require("src/game/skin_palette")
local activity_log = require("src/debug/activity_log")

local sprite_swapper = {}

local subscription_name = "old-interface-sprite-swapper"
local draw_subscription_name = "old-interface-sprite-swapper-draw"

-- The fields holding each component type's sprites. A sprite component's own sprite is the
-- empty name.
---@type table<string, string[]>
local sprite_parts = {
    [ui.ComponentType.SPRITE] = { "" },
    [ui.ComponentType.BUTTON] = { "sprite" },
    [ui.ComponentType.CHECK] = { "sprite" },
    [ui.ComponentType.COMBO] = { "entrySprite", "buttonSprite", "headerSprite" },
    [ui.ComponentType.LIST] = { "entrySprite", "buttonSprite", "headerSprite" },
    [ui.ComponentType.INPUTFIELD] = { "containerSprite" },
    [ui.ComponentType.RADIO_GROUP] = { "buttonSprite" },
    [ui.ComponentType.SLIDER] = { "thumbSprite", "trackSprite", "notchSprite" },
    [ui.ComponentType.CAROUSEL] = { "buttonSprite", "backgroundSprite" },
    [ui.ComponentType.PAGED_CAROUSEL] = { "buttonSprite", "pageBackgroundSprite" },
    [ui.ComponentType.PAGED_LAYER] = { "backgroundSprite", "pageHeaderSprite" },
    [ui.ComponentType.GROUP_BOX] = { "contentBackgroundSprite", "headerBackgroundSprite" },
}

---@type table<string, boolean>
local swapped_groups = {}

---@type InterfaceWatch?
local watch = nil

-- What to draw for each game sprite seen so far, by sprite ID: the plugin's image, a built-in
-- stand-in's ID, or false for sprites it doesn't swap. The resources can't be listed, so each
-- sprite's image is looked up by name.
---@type table<integer, PluginResource|integer|false>
local image_cache = {}

-- Each swapped part's component IDs, field, and the game sprite it had, keyed by
-- interface_walker.component_key and the field. When the game rebuilds a component it keeps its
-- IDs, so they find it again, both to swap it back right away and to restore it.
---@class SwappedPart
---@field interface_id integer
---@field static_id integer
---@field category_id integer
---@field dynamic_id integer
---@field field string
---@field original_sprite_id integer
---@field applied_sprite_id integer What the part reports after the swap: -1 for the plugin's image, or the stand-in's ID.

---@type table<string, SwappedPart>
local swapped_parts = {}

-- Each recoloured rectangle's IDs, the game's colour and the old one it got, keyed like
-- swapped_parts.
---@class RecolouredRectangle
---@field interface_id integer
---@field static_id integer
---@field category_id integer
---@field dynamic_id integer
---@field original_rgb integer
---@field applied_rgb integer

---@type table<string, RecolouredRectangle>
local recoloured_rectangles = {}

-- DEBUG: the update each interface last had a new swap logged in.
---@type table<integer, integer>
local swap_logged_at = {}

---@param sprite_name string
---@return integer?
local function stand_in_for(sprite_name)
    local stand_in_name = sprite_groups.stand_ins[sprite_name]
    if stand_in_name == nil then
        return nil
    end
    local found, stand_in_id = pcall(function () return id.Sprite[stand_in_name] end)
    return found and stand_in_id or nil
end

---@param sprite_id integer
---@return (PluginResource|integer)?
local function image_for(sprite_id)
    local image = image_cache[sprite_id]
    if image == nil then
        image = false
        local frames = Plugin.resources and Plugin.resources.frames
        local found, sprite_name = pcall(id.Sprite.FromID, sprite_id)
        local group = found and sprite_name and sprite_groups.group_of(sprite_name)
        if group and swapped_groups[group] then
            image = frames and (frames[sprite_name] or frames[sprite_name .. ".png"]) or stand_in_for(sprite_name) or false
        end
        image_cache[sprite_id] = image
    end
    return image or nil
end

-- What a part reports as its sprite ID once it draws the image.
---@param image PluginResource|integer
local function applied_id(image)
    return type(image) == "number" and image or -1
end

-- Called through pcall, which takes these as they are rather than a new function each time:
-- they run for thousands of components every update.
local function get_field(object, field)
    return object[field]
end

local function set_field(object, field, value)
    object[field] = value
end

-- The sprite component itself, or the component's sprite data in the given field.
---@param component ui.Component
---@param field string
---@return (ui.Sprite|ui.SpriteData)?
local function part_of(component, field)
    if field == "" then
        ---@cast component ui.Sprite
        return component
    end
    local found, part = pcall(get_field, component, field)
    return found and part or nil
end

---@param part ui.Sprite|ui.SpriteData
---@param sprite integer|PluginResource
---@return boolean # Whether it took.
local function set_sprite(part, sprite)
    return (pcall(set_field, part, "sprite", sprite))
end

---@param component ui.Component
---@param field string
---@return boolean # Whether the part is swapped, or may be (sprites drawing a runtime image
-- report -1, as swapped ones do).
local function swap_part(component, field)
    local part = part_of(component, field)
    if part == nil then
        return false
    end
    local sprite_id = part.spriteID
    if sprite_id == -1 then
        return true
    end
    local image = image_for(sprite_id)
    if not image then
        -- Only in interfaces that just loaded, showed or were rebuilt, not everything at startup.
        if activity_log.enabled and watch and watch.closely_watched[component.interfaceID] and component.visibleGlobal then
            activity_log.unswapped(component.interfaceID, sprite_id, field)
        end
        return false
    end
    if not set_sprite(part, image) then
        return false
    end
    local key = interface_walker.component_key(component) .. ":" .. field
    if swapped_parts[key] == nil and watch then
        -- New parts often come in batches (a list filling in), so more may follow.
        interface_watcher.keep_watching_closely(watch, component.interfaceID)
        if activity_log.enabled and swap_logged_at[component.interfaceID] ~= watch.update_number then
            swap_logged_at[component.interfaceID] = watch.update_number
            activity_log.first_swap(watch.update_number, component.interfaceID)
        end
    end
    swapped_parts[key] = {
        interface_id = component.interfaceID,
        static_id = component.staticID,
        category_id = component.categoryID,
        dynamic_id = component.dynamicID,
        field = field,
        original_sprite_id = sprite_id,
        applied_sprite_id = applied_id(image),
    }
    return true
end

---@param component ui.Rectangle
---@return boolean # Whether it has the old colour.
local function recolour(component)
    local key = interface_walker.component_key(component)
    local rgb = component.rgb
    local recoloured = recoloured_rectangles[key]
    if recoloured and rgb == recoloured.applied_rgb then
        return true
    end
    local old_rgb = skin_palette.old_colour(rgb)
    if old_rgb == nil or not pcall(set_field, component, "rgb", old_rgb) then
        return false
    end
    recoloured_rectangles[key] = {
        interface_id = component.interfaceID,
        static_id = component.staticID,
        category_id = component.categoryID,
        dynamic_id = component.dynamicID,
        original_rgb = rgb,
        applied_rgb = old_rgb,
    }
    return true
end

-- Called for every component of every loaded window several times a second, so it does as
-- little as it can for the many that aren't swapped.
---@param component ui.Component
---@return boolean # Whether any of the component's parts is swapped.
local function swap(component)
    if component.type == ui.ComponentType.RECTANGLE then
        ---@cast component ui.Rectangle
        if activity_log.enabled and watch and watch.closely_watched[component.interfaceID] and component.visibleGlobal then
            activity_log.rectangle(component)
        end
        return swapped_groups.colours == true and recolour(component)
    end
    local fields = sprite_parts[component.type]
    if fields == nil then
        return false
    end
    local swapped = false
    for _, field in ipairs(fields) do
        if swap_part(component, field) then
            swapped = true
        end
    end
    if activity_log.enabled and fields[1] ~= "" and watch and watch.closely_watched[component.interfaceID] and component.visibleGlobal then
        local part_sprite_ids = {}
        for _, field in ipairs(fields) do
            local part = part_of(component, field)
            part_sprite_ids[field] = part and part.spriteID or "none"
        end
        activity_log.interactive(component, part_sprite_ids)
    end
    return swapped
end

-- Looked up fresh each time: the game may have destroyed or rebuilt the component since.
---@param ids { interface_id: integer, static_id: integer, category_id: integer, dynamic_id: integer }
---@return ui.Component?
local function find_component(ids)
    if ids.category_id == -1 then
        return ui.Interfaces:GetComponent(ids.interface_id, ids.static_id)
    end
    return ui.Interfaces:GetComponent(ids.interface_id, ids.static_id, ids.category_id, ids.dynamic_id)
end

---@param swapped SwappedPart
---@return (ui.Sprite|ui.SpriteData)?
local function find_swapped(swapped)
    local component = find_component(swapped)
    local fields = component and sprite_parts[component.type]
    if fields == nil then
        return nil
    end
    return part_of(component, swapped.field)
end

---@param recoloured RecolouredRectangle
---@return ui.Rectangle?
local function find_recoloured(recoloured)
    local component = find_component(recoloured)
    if component and component.type == ui.ComponentType.RECTANGLE then
        ---@cast component ui.Rectangle
        return component
    end
    return nil
end

-- Just before each frame is drawn, swaps again the parts the game has given a sprite since: the
-- same one when it rebuilds them (like the tab bar when switching tabs), or another one when their
-- state changes (like a button's hover sprite). So the game's sprites don't show for a frame.
-- Parts that are gone are forgotten; if their window opens again, the walk finds them.
local function reswap_changed_parts()
    for key, swapped in pairs(swapped_parts) do
        local part = find_swapped(swapped)
        if part == nil then
            swapped_parts[key] = nil
        else
            local sprite_id = part.spriteID
            local image = sprite_id ~= -1 and image_for(sprite_id)
            if image and set_sprite(part, image) then
                swapped.applied_sprite_id = applied_id(image)
                -- The same sprite again means the game rebuilt the component (a different one is
                -- just a state change, like hovering). Then it's likely rebuilding the interface,
                -- and new parts of it may follow.
                if sprite_id == swapped.original_sprite_id and watch then
                    interface_watcher.watch_closely(watch, swapped.interface_id, "rebuilt")
                end
                -- What the game shows now is what it should get back when stopped.
                swapped.original_sprite_id = sprite_id
            end
        end
    end
    for key, recoloured in pairs(recoloured_rectangles) do
        local component = find_recoloured(recoloured)
        if component == nil then
            recoloured_rectangles[key] = nil
        else
            local rgb = component.rgb
            local old_rgb = rgb ~= recoloured.applied_rgb and skin_palette.old_colour(rgb)
            if old_rgb and pcall(set_field, component, "rgb", old_rgb) then
                recoloured.original_rgb = rgb
                recoloured.applied_rgb = old_rgb
            end
        end
    end
end

-- Only parts still showing what the plugin set get the game's sprite back.
local function restore_swapped_parts()
    for _, swapped in pairs(swapped_parts) do
        local part = find_swapped(swapped)
        if part and part.spriteID == swapped.applied_sprite_id then
            set_sprite(part, swapped.original_sprite_id)
        end
    end
    swapped_parts = {}
    for _, recoloured in pairs(recoloured_rectangles) do
        local component = find_recoloured(recoloured)
        if component and component.rgb == recoloured.applied_rgb then
            pcall(set_field, component, "rgb", recoloured.original_rgb)
        end
    end
    recoloured_rectangles = {}
end

-- Swaps the sprites in the given groups (names from sprite_groups).
---@param groups table<string, boolean>
function sprite_swapper.start(groups)
    sprite_swapper.stop()
    swapped_groups = groups
    image_cache = {}
    watch = interface_watcher.start(subscription_name, swap)
    Event.Draw.Subscribe(draw_subscription_name, reswap_changed_parts)
end

function sprite_swapper.stop()
    if watch == nil then
        return
    end
    interface_watcher.stop(watch)
    Event.Draw.Unsubscribe(draw_subscription_name)
    watch = nil
    restore_swapped_parts()
end

return sprite_swapper
