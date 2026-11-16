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
-- changes are swapped again before the frame after each logic update is drawn.
--
-- With the colours group on, plain coloured rectangles get the old colour too (see skin_palette).
local interface_walker = require("src/game/interface_walker")
local interface_watcher = require("src/game/interface_watcher")
local sprite_groups = require("src/game/sprite_groups")
local skin_palette = require("src/game/skin_palette")
local guard = require("src/game/guard")
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
-- Whether the game changes each swapped sprite all the time (see SpriteGroup.window_contents), by
-- sprite ID.
---@type table<integer, boolean>
local changes_often_cache = {}
-- Whether each swapped sprite is checked even while hidden (see SpriteGroup.checked_while_hidden),
-- by sprite ID.
---@type table<integer, boolean>
local checked_while_hidden_cache = {}

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
---@field visible boolean Whether it was showing when last looked at.
---@field changes_often boolean Whether the game changes it all the time, like a button's hover state.
---@field checked_while_hidden boolean Whether it's checked after every update even while hidden, like a big window's frame.
---@field in_use boolean Whether the game changed it, or a part next to it, while it was checked in turns: some parts say they're hidden while they show (like docked windows' tab buttons), so the game changing them is the better sign.

---@type table<string, SwappedPart>
local swapped_parts = {}

-- The game only changes sprites in its logic updates, which are fewer than frames, so parts are
-- checked on the first frame after each update.
---@type integer?
local checked_after_update = nil

-- Only showing parts the game changes all the time (like buttons, which have hover states), and
-- big windows' frames (shown or not), are checked after every update. The rest, hidden or rarely
-- changed like docked windows' frames, are checked this many at a time, in turns, from a list of
-- them made at the start of each round.
local other_parts_per_update = 150
---@type string[]
local other_round = {}
local other_round_index = 1

-- The parts of each component type whose colour comes from the skin, by group: a rectangle's or
-- a text's own colour (the empty name), or an interactive component's label ("text").
---@type table<string, { group: string, field: string }>
local colour_parts = {
    [ui.ComponentType.RECTANGLE] = { group = "colours", field = "" },
    [ui.ComponentType.LABEL] = { group = "text_colours", field = "" },
    [ui.ComponentType.BUTTON] = { group = "text_colours", field = "text" },
    [ui.ComponentType.CHECK] = { group = "text_colours", field = "text" },
    [ui.ComponentType.INPUTFIELD] = { group = "text_colours", field = "text" },
}

-- Each recoloured part's IDs, field, the game's colour and the old one it got, keyed like
-- swapped_parts.
---@class RecolouredPart
---@field interface_id integer
---@field static_id integer
---@field category_id integer
---@field dynamic_id integer
---@field field string
---@field original_rgb integer
---@field applied_rgb integer
---@field visible boolean Whether it was showing when last looked at.
---@field is_text boolean

-- Hidden recoloured parts are only checked every this many updates: they can't flash.
local hidden_colour_check_interval = 10

---@type table<string, RecolouredPart>
local recoloured_parts = {}

-- DEBUG: what the swapping costs since the last stats line (see activity_log.stats).
local stats_interval = 200
local stats = { frames = 0, checks = 0, swapped_parts = 0, visible_parts = 0, recoloured = 0, reswapped = 0, rebuilt = {} }
local stats_logged_at = 0

-- DEBUG: whether the swaps happening now are before a frame (Event.Draw) or in a logic update.
local in_draw = false

-- DEBUG: the update each interface last had a new swap logged in.
---@type table<integer, integer>
local swap_logged_at = {}

-- Interfaces whose parts say they're hidden while they show, so they're in use from the start
-- (see SwappedPart.in_use): the docked windows' tab bars.
local interfaces_in_use = { "TOPLEVEL_V2_PARENTS_QUICKCHILDREN" }
---@type table<integer, boolean>
local interface_ids_in_use = {}
for _, name in ipairs(interfaces_in_use) do
    local found, interface_id = pcall(function () return id.Interface[name] end)
    if found and interface_id then
        interface_ids_in_use[interface_id] = true
    end
end

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

-- Called through pcall, which takes these as they are rather than a new function each time:
-- they run for thousands of components every update.
local function get_field(object, field)
    return object[field]
end

local function set_field(object, field, value)
    object[field] = value
end

---@param sprite_id integer
---@return (PluginResource|integer)?
local function image_for(sprite_id)
    if sprite_id == nil then
        return nil
    end
    local image = image_cache[sprite_id]
    if image == nil then
        image = false
        local frames = Plugin.resources and Plugin.resources.frames
        local found, sprite_name = pcall(id.Sprite.FromID, sprite_id)
        local group = found and sprite_name and sprite_groups.group_of(sprite_name)
        if group and swapped_groups[group] then
            image = frames and (frames[sprite_name] or frames[sprite_name .. ".png"]) or stand_in_for(sprite_name) or false
            changes_often_cache[sprite_id] = sprite_groups.is_window_contents(group)
            checked_while_hidden_cache[sprite_id] = sprite_groups.is_checked_while_hidden(group)
        end
        image_cache[sprite_id] = image
    end
    return image or nil
end

-- Big windows' frame is built in strips, and the strip between the title and the tabs only has
-- side pieces, each filling it: the old frame had no border there, it starts at the curls by the
-- tabs. Those side pieces draw the window's dark fill without the edge line.
local side_tile_id = (function ()
    local found, sprite_id = pcall(function () return id.Sprite.RS3_PARENT_FRAME_SIDE_TILE end)
    return found and sprite_id or nil
end)()

---@param component ui.Component
local function is_title_strip_side(component)
    local parent = component.parent
    return parent ~= nil and component.height >= parent.height
end

-- What to draw for a part showing the given game sprite: image_for's, except for the title strip's
-- side pieces.
---@param component ui.Component
---@param sprite_id integer
---@return (PluginResource|integer)?
local function image_for_part(component, sprite_id)
    local image = image_for(sprite_id)
    if image and sprite_id == side_tile_id and is_title_strip_side(component) then
        local resources = Plugin.resources
        return resources and (resources.side_without_edge or resources["side_without_edge.png"]) or image
    end
    return image
end

-- What a part reports as its sprite ID once it draws the image.
---@param image PluginResource|integer
local function applied_id(image)
    return type(image) == "number" and image or -1
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
    -- Sprite data is an object; a sprite component's own "sprite" field, for one, is a number.
    if found and (type(part) == "userdata" or type(part) == "table") then
        return part
    end
    return nil
end

---@param part ui.Sprite|ui.SpriteData
---@param sprite integer|PluginResource
---@return boolean # Whether it took.
local function set_sprite(part, sprite)
    return (pcall(set_field, part, "sprite", sprite))
end

---@param swapped SwappedPart
local function is_checked_every_update(swapped)
    return swapped.checked_while_hidden or swapped.in_use or (swapped.visible and swapped.changes_often)
end

-- Checks every part in the same static component (with what the game created inside it) after
-- every update from now on.
---@param interface_id integer
---@param static_id integer
local function mark_in_use(interface_id, static_id)
    for _, swapped in pairs(swapped_parts) do
        if swapped.interface_id == interface_id and swapped.static_id == static_id then
            swapped.in_use = true
        end
    end
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
        -- Already swapped: it may have shown since it was last looked at, and then needs checking
        -- after every update again.
        local swapped = swapped_parts[interface_walker.component_key(component) .. ":" .. field]
        if swapped and not swapped.visible then
            swapped.visible = component.visibleGlobal
        end
        if activity_log.enabled and swapped and component.visibleGlobal then
            activity_log.frame_piece(component, swapped.original_sprite_id)
        end
        if activity_log.enabled and watch and not swapped and component.visibleGlobal then
            activity_log.trace(watch.update_number, component.interfaceID, -1, string.format("%s:%s shows an image the plugin didn't set",
                interface_walker.component_key(component), field))
        end
        return true
    end
    local image = image_for_part(component, sprite_id)
    if not image then
        if activity_log.enabled and watch then
            local key = interface_walker.component_key(component) .. ":" .. field
            if swapped_parts[key] and component.visibleGlobal then
                activity_log.trace(watch.update_number, component.interfaceID, sprite_id, key .. " has no old image, but was swapped before")
            end
        end
        -- Only in interfaces that just loaded, showed or were rebuilt, not everything at startup.
        if activity_log.enabled and watch and watch.closely_watched[component.interfaceID] and component.visibleGlobal then
            activity_log.unswapped(component.interfaceID, sprite_id, field, component.width, component.height)
        end
        return false
    end
    if not set_sprite(part, image) then
        return false
    end
    if activity_log.enabled and component.visibleGlobal then
        activity_log.frame_piece(component, sprite_id)
    end
    local key = interface_walker.component_key(component) .. ":" .. field
    -- The game changed a part that wasn't checked after every update, and the walk got to it
    -- first: it's in use (see SwappedPart.in_use).
    local known = swapped_parts[key]
    if known and not is_checked_every_update(known) then
        mark_in_use(known.interface_id, known.static_id)
    end
    if activity_log.enabled and watch then
        activity_log.trace(watch.update_number, component.interfaceID, sprite_id, string.format("%s by walk (%s, %s, %s)", key,
            swapped_parts[key] and "again" or "new", component.visibleGlobal and "showing" or "hidden",
            in_draw and "before frame" or "in update"))
    end
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
        visible = component.visibleGlobal,
        changes_often = changes_often_cache[sprite_id] == true,
        checked_while_hidden = checked_while_hidden_cache[sprite_id] == true,
        in_use = interface_ids_in_use[component.interfaceID] or (swapped_parts[key] ~= nil and swapped_parts[key].in_use),
    }
    return true
end

-- A part's colour as 0xRRGGBB: a component's own, or its label's (whose rgba has alpha too).
---@param component ui.Component
---@param field string
---@return integer?
local function read_colour(component, field)
    if field == "" then
        return component.rgb
    end
    local found, text = pcall(get_field, component, field)
    if not found or text == nil then
        return nil
    end
    local found_rgba, rgba = pcall(get_field, text, "rgba")
    return found_rgba and rgba and math.floor(rgba / 256) or nil
end

---@param component ui.Component
---@param field string
---@param rgb integer
---@return boolean # Whether it took.
local function write_colour(component, field, rgb)
    if field == "" then
        return (pcall(set_field, component, "rgb", rgb))
    end
    local found, text = pcall(get_field, component, field)
    if not found or text == nil then
        return false
    end
    local found_rgba, rgba = pcall(get_field, text, "rgba")
    if not found_rgba or rgba == nil then
        return false
    end
    return (pcall(set_field, text, "rgba", rgb * 256 + rgba % 256))
end

---@param component ui.Component
---@param field string
---@return boolean # Whether it has the old colour.
local function recolour(component, field, is_text)
    local key = interface_walker.component_key(component) .. ":" .. field
    local rgb = read_colour(component, field)
    if rgb == nil then
        return false
    end
    local recoloured = recoloured_parts[key]
    if recoloured and rgb == recoloured.applied_rgb then
        recoloured.visible = recoloured.visible or component.visibleGlobal
        return true
    end
    local old_rgb = is_text and skin_palette.old_text_colour(rgb) or skin_palette.old_colour(rgb)
    if activity_log.enabled and watch and watch.closely_watched[component.interfaceID] and component.visibleGlobal then
        activity_log.colour(component, field, rgb, old_rgb)
    end
    if old_rgb == nil or not write_colour(component, field, old_rgb) then
        return false
    end
    recoloured_parts[key] = {
        interface_id = component.interfaceID,
        static_id = component.staticID,
        category_id = component.categoryID,
        dynamic_id = component.dynamicID,
        field = field,
        original_rgb = rgb,
        applied_rgb = old_rgb,
        visible = component.visibleGlobal,
        is_text = is_text,
    }
    return true
end

-- Called for every component of every loaded window several times a second, so it does as
-- little as it can for the many that aren't swapped.
---@param component ui.Component
---@return boolean # Whether any of the component's parts is swapped.
local function swap(component)
    local colour_part = colour_parts[component.type]
    local recoloured = colour_part ~= nil and swapped_groups[colour_part.group] == true and recolour(component, colour_part.field, colour_part.group == "text_colours")
    if component.type == ui.ComponentType.RECTANGLE then
        ---@cast component ui.Rectangle
        if activity_log.enabled and watch and watch.closely_watched[component.interfaceID] and component.visibleGlobal then
            activity_log.rectangle(component)
        end
    end
    local fields = sprite_parts[component.type]
    if fields == nil then
        return recoloured
    end
    local swapped = recoloured
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
---@return (ui.Sprite|ui.SpriteData)?, ui.Component?
local function find_swapped(swapped)
    local component = find_component(swapped)
    local fields = component and sprite_parts[component.type]
    if fields == nil then
        return nil, nil
    end
    -- The game can reuse a component's IDs for another type of component, which has other parts.
    for _, field in ipairs(fields) do
        if field == swapped.field then
            local part = part_of(component, field)
            if part and part.spriteID ~= nil then
                return part, component
            end
        end
    end
    return nil, nil
end

---@param recoloured RecolouredPart
---@return ui.Component?
local function find_recoloured(recoloured)
    local component = find_component(recoloured)
    local colour_part = component and colour_parts[component.type]
    if colour_part and colour_part.field == recoloured.field then
        return component
    end
    return nil
end

local function log_stats()
    stats.frames = stats.frames + 1
    if watch == nil or watch.update_number - stats_logged_at < stats_interval then
        return
    end
    stats_logged_at = watch.update_number
    for _, swapped in pairs(swapped_parts) do
        stats.swapped_parts = stats.swapped_parts + 1
        if is_checked_every_update(swapped) then
            stats.visible_parts = stats.visible_parts + 1
        end
    end
    for _ in pairs(recoloured_parts) do
        stats.recoloured = stats.recoloured + 1
    end
    activity_log.stats(watch.update_number, stats, watch.closely_watched)
    stats = { frames = 0, checks = 0, swapped_parts = 0, visible_parts = 0, recoloured = 0, reswapped = 0, rebuilt = {} }
end

-- Parts the game changed lately, like the button under the mouse, which the game sets to its hover
-- sprite again every frame: they're checked before every frame, not just after every update, for
-- this many updates after their last change.
local hot_part_updates = 10
-- The update until which each part (by swapped_parts key) is checked before every frame.
---@type table<string, integer>
local hot_parts = {}

-- The static components (by interface and static ID) whose game-created parts have gone since
-- the last update: the game is likely building them again with new parts.
---@type table<string, { interface_id: integer, static_id: integer }>
local emptied_containers = {}

-- Swaps a part again if the game has given it a sprite since: the same one when it rebuilds it
-- (like the tab bar when switching tabs), or another one when its state changes (like a button's
-- hover sprite). Parts that are gone are forgotten; if their window opens again, the walk finds
-- them.
---@param key string
---@param swapped SwappedPart
---@param between_updates boolean? Whether this is a frame between updates, where only hot parts are checked.
local function reswap_if_changed(key, swapped, between_updates)
    local part, component = find_swapped(swapped)
    if part == nil or component == nil then
        if activity_log.enabled and watch then
            activity_log.trace(watch.update_number, swapped.interface_id, swapped.original_sprite_id, key .. " gone")
        end
        swapped_parts[key] = nil
        if swapped.category_id ~= -1 then
            emptied_containers[swapped.interface_id .. ":" .. swapped.static_id] = {
                interface_id = swapped.interface_id,
                static_id = swapped.static_id,
            }
        end
        return
    end
    swapped.visible = component.visibleGlobal
    local sprite_id = part.spriteID
    local image = sprite_id ~= -1 and image_for_part(component, sprite_id)
    if image and set_sprite(part, image) then
        if activity_log.enabled and watch then
            activity_log.trace(watch.update_number, swapped.interface_id, sprite_id, string.format("%s swapped again before frame (was %d, %s, %s)",
                key, swapped.original_sprite_id, swapped.visible and "showing" or "hidden",
                is_checked_every_update(swapped) and "every update" or "in turns"))
        end
        if activity_log.enabled then
            stats.reswapped = stats.reswapped + 1
            if sprite_id == swapped.original_sprite_id then
                stats.rebuilt[swapped.interface_id] = (stats.rebuilt[swapped.interface_id] or 0) + 1
            end
        end
        swapped.applied_sprite_id = applied_id(image)
        local is_hot = hot_parts[key] ~= nil
        if watch then
            hot_parts[key] = watch.update_number + hot_part_updates
        end
        -- The same sprite again means the game rebuilt the component (a different one is just a
        -- state change, like hovering). Then it's likely rebuilding the interface, and new parts
        -- of it may follow. Not for hot parts: the game sets those again all the time.
        if sprite_id == swapped.original_sprite_id and not is_hot and not between_updates and watch then
            interface_watcher.watch_closely(watch, swapped.interface_id, "rebuilt")
        end
        if not is_checked_every_update(swapped) and not between_updates then
            mark_in_use(swapped.interface_id, swapped.static_id)
        end
        -- What the game shows now is what it should get back when stopped.
        swapped.original_sprite_id = sprite_id
    end
end

-- The parts not checked after every update get checked in turns, a few each time. A hidden part
-- that shows comes back to the every-update check when the walk next sees it, or its turn comes.
local function reswap_some_other_parts()
    if other_round_index > #other_round then
        other_round = {}
        for key, swapped in pairs(swapped_parts) do
            if not is_checked_every_update(swapped) then
                other_round[#other_round + 1] = key
            end
        end
        other_round_index = 1
    end
    local last = math.min(other_round_index + other_parts_per_update - 1, #other_round)
    for index = other_round_index, last do
        local key = other_round[index]
        local swapped = swapped_parts[key]
        if swapped and not is_checked_every_update(swapped) then
            reswap_if_changed(key, swapped)
        end
    end
    other_round_index = last + 1
end

-- Before the first frame after each logic update is drawn, swaps again the parts the game has
-- given a sprite since, so the game's sprites don't show for a frame: every showing part the game
-- changes all the time, and some of the rest.
local function reswap_changed_parts()
    if activity_log.enabled then
        log_stats()
    end
    if watch == nil then
        return
    end
    if watch.update_number == checked_after_update then
        for key, hot_until in pairs(hot_parts) do
            local swapped = swapped_parts[key]
            if swapped == nil or hot_until < watch.update_number then
                hot_parts[key] = nil
            else
                reswap_if_changed(key, swapped, true)
            end
        end
        return
    end
    checked_after_update = watch.update_number
    in_draw = true
    interface_watcher.walk_newly_shown(watch)
    interface_watcher.walk_closely_watched(watch)
    for key, swapped in pairs(swapped_parts) do
        if is_checked_every_update(swapped) then
            reswap_if_changed(key, swapped)
        end
    end
    reswap_some_other_parts()
    -- New parts in their place get swapped before this frame, not when the walk gets to them.
    for _, container in pairs(emptied_containers) do
        interface_watcher.walk_static(watch, container.interface_id, container.static_id)
    end
    emptied_containers = {}
    in_draw = false
    stats.checks = stats.checks + 1
    local check_hidden_colours = watch.update_number % hidden_colour_check_interval == 0
    for key, recoloured in pairs(recoloured_parts) do
        local component = (recoloured.visible or check_hidden_colours) and find_recoloured(recoloured)
        if component == nil then
            recoloured_parts[key] = nil
        elseif component then
            recoloured.visible = component.visibleGlobal
            local rgb = read_colour(component, recoloured.field)
            local old_rgb = rgb and rgb ~= recoloured.applied_rgb
                and (recoloured.is_text and skin_palette.old_text_colour(rgb) or skin_palette.old_colour(rgb))
            if old_rgb and write_colour(component, recoloured.field, old_rgb) then
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
    other_round = {}
    other_round_index = 1
    hot_parts = {}
    for _, recoloured in pairs(recoloured_parts) do
        local component = find_recoloured(recoloured)
        if component and read_colour(component, recoloured.field) == recoloured.applied_rgb then
            write_colour(component, recoloured.field, recoloured.original_rgb)
        end
    end
    recoloured_parts = {}
end

-- Swaps the sprites in the given groups (names from sprite_groups).
---@param groups table<string, boolean>
function sprite_swapper.start(groups)
    sprite_swapper.stop()
    swapped_groups = groups
    image_cache = {}
    changes_often_cache = {}
    checked_while_hidden_cache = {}
    watch = interface_watcher.start(subscription_name, swap)
    Event.Draw.Subscribe(draw_subscription_name, guard.guarded("before a frame", reswap_changed_parts))
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
