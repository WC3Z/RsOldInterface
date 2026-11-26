-- Draws the old interface in place of the game's current one, and puts the game's back when
-- stopped. This file swaps sprites and keeps them swapped; what each sprite is swapped for is
-- sprite_images' job, plain colours are recolourer's, and finding the components to look at is
-- interface_watcher's.
--
-- A sprite component draws one sprite. Interactive components like buttons and dropdowns draw
-- theirs in several fields (see component_fields.sprite_fields). Each of those is a "part" here,
-- swapped and remembered on its own.
--
-- The game sets its own sprites again all the time: a button's on every hover, a list's rows when
-- it's rebuilt. So swapped parts are remembered and checked again, before the frame that would
-- show the game's sprite, as often as each needs:
--
--   which parts                                        checked                    see
--   the game set lately (the button under the mouse)   before every frame         hot_until
--   showing ones the game changes often, big windows'  before the first frame     is_checked_every_update
--     frames, and ones in use                            after every update
--   the rest (hidden, or rarely changed)               a few each update, in      check_some_in_turns
--                                                        turns
local interface_walker = require("src/game/interface_walker")
local interface_watcher = require("src/game/interface_watcher")
local sprite_images = require("src/game/sprite_images")
local recolourer = require("src/game/recolourer")
local colour_scheme = require("src/game/colour_scheme")
local component_fields = require("src/game/component_fields")
local game_ids = require("src/game/game_ids")
local guard = require("src/game/guard")
local events = require("src/game/debug_tools").events

local sprite_swapper = {}

local subscription_name = "old-interface-sprite-swapper"
local draw_subscription_name = "old-interface-sprite-swapper-draw"

local sprite_fields = component_fields.sprite_fields
local runtime_image_id = component_fields.runtime_image_id

-- A swapped part: the component's IDs and field, to find it again (the game keeps a component's
-- IDs when it rebuilds it), and what the game had there.
---@class SwappedPart : ComponentIds
---@field field string
---@field game_sprite_id integer The sprite the game gave it, which it gets back when the plugin stops.
---@field changing_image_name string? The name of the image it draws, where that can change while the sprite stays the same (see SpriteLook.follows_title).
---@field visible boolean Whether it was showing when last looked at.
---@field changes_often boolean Whether the game changes it all the time, like a button's hover state.
---@field checked_while_hidden boolean Whether it's checked after every update even while hidden, like a big window's frame.
---@field in_use boolean Whether the game changed it, or a part next to it, while it was checked in turns (see mark_in_use).
---@field game_rgb integer? The game's own tint of the part, if the plugin tinted it.
---@field applied_rgb integer? The tint the plugin gave it: the game's with the colour scheme's on top.

-- Everything that changes while the swapping runs, made anew each time it starts.
---@class Swapping
---@field watch InterfaceWatch
---@field parts table<string, SwappedPart> Keyed by interface_walker.component_key and the field.
---@field hot_until table<string, integer> The update until which each part (by its key) is checked before every frame.
---@field in_turns string[] The keys of the parts checked in turns, listed at the start of each round.
---@field in_turns_index integer Where in that list the next update carries on.
---@field checked_after_update integer? The update whose changes have been looked for (see before_frame).
---@field tints boolean Whether any part is tinted.

---@type Swapping?
local swapping = nil

-- How many of the parts checked in turns are checked each update.
local in_turns_per_update = 150
-- For how many updates after the game last changed a part it's checked before every frame.
local hot_updates = 10
-- For a sprite, the game takes black as no tint: many (most of the Bank's) have it and are drawn
-- untinted all the same.
local untinted_rgb = 0x000000
local white_rgb = 0xFFFFFF

-- Interfaces whose parts say they're hidden while they show, so they're in use from the start
-- (see mark_in_use): the docked windows' tab bars.
local interface_ids_in_use = game_ids.interface_ids({ "TOPLEVEL_V2_PARENTS_QUICKCHILDREN" })

-- Whether a part is checked after every update, and not just in turns. None in an interface that
-- isn't showing is: the update it shows in, they are again. (But for the interfaces whose parts
-- say they're hidden while they show.)
---@param watch InterfaceWatch
---@param part SwappedPart
local function is_checked_every_update(watch, part)
    local interface_id = part.interface_id
    if not interface_watcher.is_showing(watch, interface_id) and not interface_ids_in_use[interface_id] then
        return false
    end
    return part.checked_while_hidden or part.in_use or (part.visible and part.changes_often)
end

-- Checks every part in the same static component (with what the game created inside it) after
-- every update from now on. A part is in use when the game changes it while it's only checked in
-- turns: some parts say they're hidden while they show (like docked windows' tab buttons), so the
-- game changing them is the better sign that they're showing.
---@param parts table<string, SwappedPart>
---@param interface_id integer
---@param static_id integer
local function mark_in_use(parts, interface_id, static_id)
    for _, part in pairs(parts) do
        if part.interface_id == interface_id and part.static_id == static_id then
            part.in_use = true
        end
    end
end

-- Tints a part that draws a grey copy, on top of the tint the game gave it. Again when the game
-- has set its own tint since.
---@param holder ui.Component|userdata|table What holds the part's sprite (see component_fields.holder).
---@param field string
---@param tint integer? The look's tint for the part's sprite, if it has one.
---@param known SwappedPart? What's known of the part from before.
---@return integer?, integer? # The game's tint and the one applied, or nothing if it isn't tinted.
local function tint_part(holder, field, tint, known)
    if tint == nil then
        return nil, nil
    end
    local game_rgb = component_fields.read_rgb(holder, field)
    if game_rgb == nil then
        return nil, nil
    end
    if known and known.applied_rgb == game_rgb then
        return known.game_rgb, known.applied_rgb
    end
    local applied_rgb = colour_scheme.multiplied(game_rgb == untinted_rgb and white_rgb or game_rgb, tint)
    if not component_fields.write_rgb(holder, field, applied_rgb) then
        return nil, nil
    end
    return game_rgb, applied_rgb
end

-- Swaps one part of a component the walk came to, if it shows a sprite the look has an image for.
---@param state Swapping
---@param component ui.Component
---@param field string
---@param walk_kind WalkKind
local function swap_part(state, component, field, walk_kind)
    local holder = component_fields.holder(component, field)
    if holder == nil then
        return
    end
    local sprite_id = holder.spriteID
    if sprite_id == runtime_image_id then
        -- Swapped already (or drawing some other runtime image). Most parts walked are, so nothing
        -- more is looked up for them.
        if events.enabled then
            events.already_swapped(component, field, state.parts)
        end
        return
    end
    local look = sprite_images.look_of(sprite_id)
    if look == nil then
        if events.enabled then
            events.not_swapped(component, field, sprite_id, state.parts)
        end
        return
    end
    local image, changing_image_name = sprite_images.image_at(component, sprite_id, look)
    if not component_fields.set_sprite(holder, image) then
        return
    end

    local key = interface_walker.component_key(component) .. ":" .. field
    local known = state.parts[key]
    local is_showing = component.visibleGlobal
    if known then
        -- The game changed a part the plugin had swapped, and the walk got to it before the check
        -- did. It may be one the game sets every frame, and if it was only checked in turns, it's
        -- in use.
        state.hot_until[key] = state.watch.update_number + hot_updates
        if not is_checked_every_update(state.watch, known) then
            mark_in_use(state.parts, known.interface_id, known.static_id)
        end
    elseif is_showing then
        -- New parts often come in batches (a list filling in), so more may follow.
        interface_watcher.found_new_part(state.watch, component.interfaceID, component.staticID,
            component_fields.is_created(component), walk_kind)
    end
    if events.enabled then
        events.swapped(component, key, sprite_id, known ~= nil, walk_kind)
    end

    local game_rgb, applied_rgb = tint_part(holder, field, look.tint, known)
    state.parts[key] = {
        interface_id = component.interfaceID,
        static_id = component.staticID,
        category_id = component.categoryID,
        dynamic_id = component.dynamicID,
        field = field,
        game_sprite_id = sprite_id,
        changing_image_name = changing_image_name,
        visible = is_showing,
        changes_often = look.changes_often,
        checked_while_hidden = look.checked_while_hidden,
        in_use = interface_ids_in_use[component.interfaceID] or (known ~= nil and known.in_use),
        game_rgb = game_rgb,
        applied_rgb = applied_rgb,
    }
end

-- What the walks do for each component they come to (see interface_watcher). Called for every
-- component of every loaded window several times a second, so it does as little as it can for the
-- many that aren't changed.
---@param component ui.Component
---@param walk_kind WalkKind
local function visit(component, walk_kind)
    local state = swapping
    if state == nil then
        return
    end
    if events.enabled then
        events.visited(component)
    end
    recolourer.recolour(component, walk_kind)
    local fields = sprite_fields[component.type]
    if fields then
        for _, field in ipairs(fields) do
            swap_part(state, component, field, walk_kind)
        end
    end
end

-- What holds a swapped part's sprite, and its component, if they're still there.
---@param part SwappedPart
---@return (ui.Component|userdata|table)?, ui.Component?
local function find(part)
    local component = component_fields.find(part)
    local fields = component and sprite_fields[component.type]
    if fields == nil then
        return nil, nil
    end
    -- The game can reuse a component's IDs for another type of component, which has other fields.
    for _, field in ipairs(fields) do
        if field == part.field then
            local holder = component_fields.holder(component, field)
            if holder and holder.spriteID ~= nil then
                return holder, component
            end
        end
    end
    return nil, nil
end

-- A few parts draw an image that depends on more than their sprite, like a title plate's on the
-- window's title. For a showing one that still has the plugin's image, this draws the other image
-- when what it depends on has changed.
---@param holder ui.Component|userdata|table
---@param component ui.Component
---@param part SwappedPart
local function draw_changed_image(holder, component, part)
    if not part.visible then
        return
    end
    local look = sprite_images.look_of(part.game_sprite_id)
    if look == nil or not look.follows_title then
        return
    end
    local image, changing_image_name = sprite_images.image_at(component, part.game_sprite_id, look)
    if changing_image_name ~= part.changing_image_name and component_fields.set_sprite(holder, image) then
        part.changing_image_name = changing_image_name
    end
end

-- Swaps a part again if the game has given it a sprite since: the same one when it rebuilds it
-- (like the tab bar when switching tabs), or another one when its state changes (like a button's
-- hover sprite). Parts that are gone are forgotten; if their window opens again, the walk finds
-- them.
---@param state Swapping
---@param key string
---@param part SwappedPart
---@param is_between_updates boolean Whether this is a frame between updates, where only hot parts are checked.
local function swap_again_if_changed(state, key, part, is_between_updates)
    local watch = state.watch
    local holder, component = find(part)
    if holder == nil or component == nil then
        state.parts[key] = nil
        -- Parts the game created that are gone were likely built again under new IDs.
        if part.category_id ~= component_fields.static_category_id then
            interface_watcher.walk_container_soon(watch, part.interface_id, part.static_id)
        end
        if events.enabled then
            events.gone(key, part)
        end
        return
    end
    part.visible = component.visibleGlobal

    local sprite_id = holder.spriteID
    if sprite_id == runtime_image_id then
        draw_changed_image(holder, component, part)
    end
    local look = sprite_id ~= runtime_image_id and sprite_images.look_of(sprite_id) or nil
    local image, changing_image_name
    if look then
        image, changing_image_name = sprite_images.image_at(component, sprite_id, look)
    end
    if look and component_fields.set_sprite(holder, image) then
        part.changing_image_name = changing_image_name
        local was_checked_every_update = is_checked_every_update(state.watch, part)
        local was_hot = state.hot_until[key] ~= nil
        state.hot_until[key] = watch.update_number + hot_updates
        -- The same sprite again means the game rebuilt the component (a different one is just a
        -- state change, like hovering). Then it's likely rebuilding what's around it, and new parts
        -- may follow there. Not for hot parts: the game sets those again all the time.
        local was_rebuilt = sprite_id == part.game_sprite_id and not was_hot and not is_between_updates
        if was_rebuilt then
            interface_watcher.walk_container_soon(watch, part.interface_id, part.static_id)
        end
        if not was_checked_every_update and not is_between_updates then
            mark_in_use(state.parts, part.interface_id, part.static_id)
        end
        if events.enabled then
            events.swapped_again(key, part, sprite_id, was_checked_every_update, was_rebuilt)
        end
        -- What the game shows now is what it should get back when stopped.
        part.game_sprite_id = sprite_id
    end
    if state.tints then
        local current_look = sprite_images.look_of(part.game_sprite_id)
        part.game_rgb, part.applied_rgb = tint_part(holder, part.field, current_look and current_look.tint, part)
    end
end

-- Hot parts are checked before every frame (see the top of the file).
---@param state Swapping
local function check_hot_parts(state)
    local checked = 0
    for key, hot_until in pairs(state.hot_until) do
        local part = state.parts[key]
        if part == nil or hot_until < state.watch.update_number then
            state.hot_until[key] = nil
        else
            swap_again_if_changed(state, key, part, true)
            checked = checked + 1
        end
    end
    if events.enabled then
        events.count("hot part checks", checked)
    end
end

---@param state Swapping
local function check_parts_checked_every_update(state)
    local watch = state.watch
    local checked = 0
    for key, part in pairs(state.parts) do
        if is_checked_every_update(watch, part) then
            if events.enabled then
                events.checked_every_update(part)
            end
            swap_again_if_changed(state, key, part, false)
            checked = checked + 1
        end
    end
    if events.enabled then
        events.count("parts checked every update", checked)
    end
end

-- The parts not checked after every update are checked a few each time, in turns. A hidden part
-- that shows comes back to the every-update check when the walk next sees it, or its turn comes.
---@param state Swapping
local function check_some_in_turns(state)
    if state.in_turns_index > #state.in_turns then
        state.in_turns = {}
        for key, part in pairs(state.parts) do
            if not is_checked_every_update(state.watch, part) then
                state.in_turns[#state.in_turns + 1] = key
            end
        end
        state.in_turns_index = 1
    end
    local last = math.min(state.in_turns_index + in_turns_per_update - 1, #state.in_turns)
    if events.enabled then
        events.count("parts checked in turns", last - state.in_turns_index + 1)
    end
    for index = state.in_turns_index, last do
        local key = state.in_turns[index]
        local part = state.parts[key]
        if part and not is_checked_every_update(state.watch, part) then
            swap_again_if_changed(state, key, part, false)
        end
    end
    state.in_turns_index = last + 1
end

-- Runs before every frame. The game changes its interfaces during its logic updates, which are
-- fewer than frames, so the looking for new and changed parts is done once after each update,
-- before the first frame that would show them. On the frames in between, only hot parts are
-- checked.
---@param event DrawEventPayload?
local function before_frame(event)
    local state = swapping
    if state == nil then
        return
    end
    local watch = state.watch
    if events.enabled then
        events.frame(event, watch.update_number, state.parts, visit)
    end
    -- The debug tools can leave a step out for a moment, to measure what it costs.
    if watch.update_number == state.checked_after_update then
        if not events.skips("hot checks") then
            check_hot_parts(state)
        end
        return
    end
    state.checked_after_update = watch.update_number

    interface_watcher.before_frame(watch)
    if not events.skips("every-update checks") then
        check_parts_checked_every_update(state)
    end
    if not events.skips("in-turn checks") then
        check_some_in_turns(state)
    end
    -- After the checks: they point out where the game rebuilt things.
    if not events.skips("container walks") then
        interface_watcher.walk_containers(watch)
    end
    if not events.skips("colour checks") then
        recolourer.recolour_changed(watch.update_number)
    end
    if events.enabled then
        events.checked(state.parts, recolourer.count())
    end
end

-- Gives back the game's sprites and tints. Only where a part still has what the plugin set.
---@param parts table<string, SwappedPart>
local function restore(parts)
    for _, part in pairs(parts) do
        local holder = find(part)
        if holder and holder.spriteID == runtime_image_id then
            component_fields.set_sprite(holder, part.game_sprite_id)
        end
        if holder and part.applied_rgb and component_fields.read_rgb(holder, part.field) == part.applied_rgb then
            component_fields.write_rgb(holder, part.field, part.game_rgb)
        end
    end
end

-- Swaps the sprites in the given groups (names from sprite_groups).
---@param groups table<string, boolean>
---@param colours SchemeColours? What to draw the look in (see colour_scheme); the classic look if left out.
---@param window_look WindowLook? The player's choices for how windows are drawn (see sprite_images); the usual look if left out.
function sprite_swapper.start(groups, colours, window_look)
    sprite_swapper.stop()
    local drawn_colours = sprite_images.use(groups, colours or {}, window_look)
    local watch = interface_watcher.start(subscription_name, visit)
    recolourer.start(groups, drawn_colours, function (component, walk_kind)
        interface_watcher.found_new_part(watch, component.interfaceID, component.staticID,
            component_fields.is_created(component), walk_kind)
    end)
    swapping = {
        watch = watch,
        parts = {},
        hot_until = {},
        in_turns = {},
        in_turns_index = 1,
        checked_after_update = nil,
        tints = sprite_images.tints_any(),
    }
    if events.enabled then
        events.started(watch)
    end
    Event.Draw.Subscribe(draw_subscription_name, guard.guarded("before a frame", before_frame))
end

function sprite_swapper.stop()
    local state = swapping
    if state == nil then
        return
    end
    swapping = nil
    interface_watcher.stop(state.watch)
    Event.Draw.Unsubscribe(draw_subscription_name)
    restore(state.parts)
    recolourer.stop()
end

return sprite_swapper
