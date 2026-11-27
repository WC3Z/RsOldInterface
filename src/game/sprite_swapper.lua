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
---@field in_use_until number The update until which it stays in use.
---@field left number? Where it was on screen when last looked at, for telling whether the mouse is near it (see is_due_after_update).
---@field top number?
---@field right number?
---@field bottom number?
---@field near_mouse boolean Whether the mouse was near it at the last update.
---@field checks_since_place integer How many times it was checked since its place was last read.
---@field turn integer Which of the updates it's checked in while the mouse is elsewhere.
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
---@field parts_made integer How many parts were swapped for the first time, to give each its turn.
---@field checked_often string[] The keys of the parts that are checked often (see list_parts_checked_often).
---@field believed_hidden string[] The keys of hover-prone parts that were hidden when last looked at.
---@field checked_often_listed_at integer The update that list was made in.
---@field checked_often_is_stale boolean Whether parts were added or marked since.
---@field updates_between_alert_checks integer How many updates apart each often-checked part is checked while alert: 1 unless there are very many.
---@field changes_while_rarely_checked integer How many rarely checked parts the game changed this update (see mark_in_use).
---@field containers_to_mark { interface_id: integer, static_id: integer }[] The components whose parts are to be marked in use.
---@field mouse_x number? Where the mouse is, if that can be told.
---@field mouse_y number?

---@type Swapping?
local swapping = nil

-- How much collecting Lua is asked to do after each update: as for this many kilobytes of new
-- objects, which is about what a quiet update makes.
local garbage_step_kb = 100
-- How many of the parts checked in turns are checked each update, and while it's quiet.
local in_turns_per_update = 150
local in_turns_per_quiet_update = 50
-- For how many updates after the game last changed a part it's checked before every frame.
local hot_updates = 10
-- The game changes a showing button's sprite when the mouse comes over it or leaves, which has to
-- be undone before the next frame, so parts near the mouse are checked after every update. The
-- rest change far more rarely, and are checked every few updates, each in its own turn; all of
-- them again after every update when the server sent something or a key was pressed, and for a
-- while once something happens (see is_due_after_update).
-- How long a part stays in use after the game last changed it while it wasn't checked often (ten
-- seconds): without an end, every window that was ever used kept being checked.
local in_use_updates = 500
-- While something may be changing, every often-checked part is checked after each update, up to
-- about this many an update.
local most_alert_checks_per_update = 500
-- How many updates the list of often-checked parts is used for while nothing changes.
local updates_between_lists_of_parts_checked_often = 10
local most_changes_that_mark_in_use = 12
local near_mouse_margin = 12
local updates_between_checks_away_from_mouse = 8
-- Parts a bit further from the mouse are checked more often than the rest: each check also reads
-- where the part is now, and what's around the mouse is what gets scrolled, dragged and hovered
-- next.
local around_mouse_margin = 160
local updates_between_checks_around_mouse = 2
-- How many checks of a part away from the mouse go by between readings of where it is.
local checks_between_places = 4
-- A window's frame, when nothing has arrived from the server and no key was pressed for a few
-- updates (see interface_watcher's alert_updates).
local updates_between_checks_of_frames_when_quiet = 2

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

-- Notes where a part is on screen, for telling later whether the mouse is near it.
---@param part SwappedPart
---@param component ui.Component
local function note_place(part, component)
    local position = component.xyGlobal
    part.left, part.top = position.x, position.y
    part.right, part.bottom = position.x + component.width, position.y + component.height
end

---@param state Swapping
---@param part SwappedPart
---@param margin number How far from the part still counts.
---@return boolean
local function is_near_mouse(state, part, margin)
    local x, y = state.mouse_x, state.mouse_y
    if x == nil or y == nil or part.left == nil then
        return false
    end
    return x >= part.left - margin and x <= part.right + margin
        and y >= part.top - margin and y <= part.bottom + margin
end

-- Whether a part that's checked often is checked after this update (see near_mouse_margin): all
-- of them while something may be happening (the server sent something, a key was pressed, or
-- something opened or was rebuilt); otherwise parts in use, a window's frame every other
-- update, and the others when the mouse is near, or just left, or it's their turn.
---@param state Swapping
---@param part SwappedPart
---@return boolean
local function is_due_after_update(state, part)
    local update_number = state.watch.update_number
    local is_alert = interface_watcher.is_alert(state.watch)
    -- Parts in use are ones whose hover can't be told from where the mouse is.
    if part.in_use then
        return true
    end
    if part.checked_while_hidden then
        -- (Looking only at the static component a hidden piece is in, and at the piece once that
        -- shows, was tried: big windows' tabs flashed now and then.)
        return is_alert or (update_number + part.turn) % updates_between_checks_of_frames_when_quiet == 0
    end
    local was_near = part.near_mouse
    part.near_mouse = is_near_mouse(state, part, near_mouse_margin)
    if part.near_mouse or was_near then
        return true
    end
    -- A window with thousands of buttons (the key binds in Settings) takes turns even while alert.
    local interval = updates_between_checks_away_from_mouse
    if is_alert then
        interval = state.updates_between_alert_checks
    elseif is_near_mouse(state, part, around_mouse_margin) then
        interval = updates_between_checks_around_mouse
    end
    return (update_number + part.turn) % interval == 0
end

---@return number?, number? # Where the mouse is, if that can be told.
local function mouse_position()
    if not Mouse.IsAvailable() then
        return nil, nil
    end
    return Mouse.GetX(), Mouse.GetY()
end

-- Notes that every part in the same static component (with what the game created inside it) is
-- to be checked often for a while (see in_use_updates and mark_what_is_in_use). A part is in use when the game changes it while it's only checked in
-- turns: some parts say they're hidden while they show (like docked windows' tab buttons), so the
-- game changing them is the better sign that they're showing.
---@param state Swapping
---@param interface_id integer
---@param static_id integer
local function mark_in_use(state, interface_id, static_id)
    state.changes_while_rarely_checked = state.changes_while_rarely_checked + 1
    if state.changes_while_rarely_checked <= most_changes_that_mark_in_use then
        state.containers_to_mark[#state.containers_to_mark + 1] = { interface_id = interface_id, static_id = static_id }
    end
end

-- Marks what this update's checks and walks found (see mark_in_use). Not when the game changed
-- many rarely checked parts at once: then it's building things, like the whole HUD behind a
-- loading screen, and nothing says they're showing.
---@param state Swapping
local function mark_what_is_in_use(state)
    if state.changes_while_rarely_checked > 0 and state.changes_while_rarely_checked <= most_changes_that_mark_in_use then
        state.checked_often_is_stale = true
        local in_use_until = state.watch.update_number + in_use_updates
        for _, container in ipairs(state.containers_to_mark) do
            for _, part in pairs(state.parts) do
                if part.interface_id == container.interface_id and part.static_id == container.static_id then
                    part.in_use = true
                    part.in_use_until = math.max(part.in_use_until, in_use_until)
                end
            end
        end
    end
    state.changes_while_rarely_checked = 0
    state.containers_to_mark = {}
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
            mark_in_use(state, known.interface_id, known.static_id)
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
    if known == nil then
        state.parts_made = state.parts_made + 1
    end
    local part = {
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
        in_use_until = interface_ids_in_use[component.interfaceID] and math.huge or (known and known.in_use_until or 0),
        game_rgb = game_rgb,
        applied_rgb = applied_rgb,
        near_mouse = false,
        checks_since_place = 0,
        turn = known and known.turn or state.parts_made,
    }
    if look.changes_often then
        pcall(note_place, part, component)
    end
    state.parts[key] = part
    state.checked_often_is_stale = true
end

-- What the walks do for each component they come to (see interface_watcher). Called for every
-- component of every loaded window several times a second, so it does as little as it can for the
-- many that aren't changed.
---@param component ui.Component
---@param component_type string The component's type, which the walk has read already.
---@param walk_kind WalkKind
local function visit(component, component_type, walk_kind)
    local state = swapping
    if state == nil then
        return
    end
    if events.enabled then
        events.visited(component)
    end
    recolourer.recolour(component, component_type, walk_kind)
    local fields = sprite_fields[component_type]
    if fields then
        for _, field in ipairs(fields) do
            swap_part(state, component, field, walk_kind)
        end
    end
end

-- What holds a swapped part's sprite, its component, and the sprite's ID as it is now, if they're
-- still there.
---@param part SwappedPart
---@return (ui.Component|userdata|table)?, ui.Component?, integer?
local function find(part)
    local component = component_fields.find(part)
    local fields = component and sprite_fields[component.type]
    if fields == nil then
        return nil, nil, nil
    end
    -- The game can reuse a component's IDs for another type of component, which has other fields.
    for _, field in ipairs(fields) do
        if field == part.field then
            local holder = component_fields.holder(component, field)
            local sprite_id = holder and holder.spriteID
            if sprite_id ~= nil then
                return holder, component, sprite_id
            end
        end
    end
    return nil, nil, nil
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
    local holder, component, sprite_id = find(part)
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
    -- Windows get moved and lists scrolled, so where the part is has to be read again. It only
    -- matters once the mouse comes near, and it's several reads from the game: every check for
    -- what's around the mouse, every few checks for the rest.
    if part.visible and part.changes_often then
        part.checks_since_place = part.checks_since_place + 1
        local place_is_due = part.left == nil or part.checks_since_place >= checks_between_places
            or is_near_mouse(state, part, around_mouse_margin)
        if place_is_due then
            part.checks_since_place = 0
            pcall(note_place, part, component)
        end
    end

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
        if (not was_checked_every_update or part.in_use) and not is_between_updates then
            mark_in_use(state, part.interface_id, part.static_id)
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

-- Lists the parts that are checked often (see is_checked_every_update), so that the check after
-- each update doesn't have to go through every swapped part: there are thousands, and even
-- without asking the game anything, that took a good part of the plugin's time. And the hover-prone
-- parts that were hidden when last looked at, for check_parts_under_mouse.
---@param state Swapping
local function list_parts_checked_often(state)
    local watch = state.watch
    local keys = {}
    local believed_hidden = {}
    for key, part in pairs(state.parts) do
        if part.in_use and part.in_use_until < watch.update_number then
            part.in_use = false
        end
        if is_checked_every_update(watch, part) then
            keys[#keys + 1] = key
        elseif part.changes_often and part.left ~= nil
            and (interface_watcher.is_showing(watch, part.interface_id) or interface_ids_in_use[part.interface_id]) then
            believed_hidden[#believed_hidden + 1] = key
        end
    end
    state.checked_often = keys
    state.believed_hidden = believed_hidden
    state.checked_often_listed_at = watch.update_number
    state.checked_often_is_stale = false
    state.updates_between_alert_checks = 1 + #keys // most_alert_checks_per_update
end

-- Checks what the mouse is over, before every frame: the game gives a button its hover sprite in
-- whatever frame the mouse arrives, not just after an update.
-- - Often-checked parts near the mouse, on the frames between updates (after an update they're
--   checked as it is).
-- - Hover-prone parts that were hidden when last looked at: a part can have come to show since
--   without the plugin knowing (a tab switched inside a window), and waiting for its turn to be
--   looked at again left its hover sprite showing in the meantime.
---@param state Swapping
---@param is_between_updates boolean
local function check_parts_under_mouse(state, is_between_updates)
    local found, mouse_x, mouse_y = pcall(mouse_position)
    state.mouse_x, state.mouse_y = found and mouse_x or nil, found and mouse_y or nil
    if state.mouse_x == nil or state.mouse_y == nil then
        return
    end
    local checked = 0
    if is_between_updates then
        for _, key in ipairs(state.checked_often) do
            local part = state.parts[key]
            if part and state.hot_until[key] == nil and is_near_mouse(state, part, near_mouse_margin) then
                swap_again_if_changed(state, key, part, true)
                checked = checked + 1
            end
        end
    else
        -- Once an update is enough for these: most really are hidden, under what the mouse is over.
        for _, key in ipairs(state.believed_hidden) do
            local part = state.parts[key]
            if part and is_near_mouse(state, part, near_mouse_margin) then
                swap_again_if_changed(state, key, part, false)
                checked = checked + 1
                if part.visible then
                    state.checked_often_is_stale = true
                end
            end
        end
    end
    if events.enabled then
        events.count("parts checked under the mouse", checked)
    end
end

---@param state Swapping
local function check_parts_checked_every_update(state)
    local watch = state.watch
    -- The list is made anew every few updates, and right away when parts were added or marked in
    -- use, or while things are changing (which is when interfaces show and hide).
    local is_old = watch.update_number - state.checked_often_listed_at >= updates_between_lists_of_parts_checked_often
    if state.checked_often_is_stale or is_old or interface_watcher.is_alert(watch) then
        list_parts_checked_often(state)
    end
    local checked = 0
    check_parts_under_mouse(state, false)
    for _, key in ipairs(state.checked_often) do
        local part = state.parts[key]
        if part and is_due_after_update(state, part) then
            if events.enabled then
                events.checked_every_update(part)
            end
            swap_again_if_changed(state, key, part, false)
            checked = checked + 1
        end
    end
    if events.enabled then
        events.count("parts checked every update", checked)
        events.count("parts on the list of often checked", #state.checked_often)
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
    local per_update = interface_watcher.is_busy(state.watch) and in_turns_per_update or in_turns_per_quiet_update
    local last = math.min(state.in_turns_index + per_update - 1, #state.in_turns)
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

-- Every component the plugin looks at is a small object that's thrown away again, tens of kilobytes
-- an update. Left alone, Lua lets that pile up until its memory has about doubled and then frees it
-- all in one frame, which took 30-45 ms every ten or twenty seconds: a visible hitch. So after each
-- update Lua is asked to do a little of that work, and while things are quiet the pile never
-- builds up. A hitch can still follow a busy stretch (asking for more work after a busy update
-- was tried, and it stayed).
local function collect_some_garbage()
    collectgarbage("step", garbage_step_kb)
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
            check_parts_under_mouse(state, true)
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
    mark_what_is_in_use(state)
    if not events.skips("colour checks") then
        recolourer.recolour_changed(watch.update_number, not interface_watcher.is_alert(watch), state.mouse_x, state.mouse_y)
    end
    if events.enabled then
        events.checked(state.parts, recolourer.count())
    end
    collect_some_garbage()
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
        parts_made = 0,
        updates_between_alert_checks = 1,
        checked_often = {},
        believed_hidden = {},
        checked_often_listed_at = -100,
        checked_often_is_stale = true,
        changes_while_rarely_checked = 0,
        containers_to_mark = {},
        mouse_x = nil,
        mouse_y = nil,
    }
    if events.enabled then
        events.started(watch)
    end
    Event.Draw.Subscribe(draw_subscription_name, guard.guarded("before a frame", before_frame))
    Event.KeyDown.Subscribe(subscription_name, guard.guarded("on a key press", function ()
        interface_watcher.player_did_something(watch)
    end))
end

function sprite_swapper.stop()
    local state = swapping
    if state == nil then
        return
    end
    swapping = nil
    interface_watcher.stop(state.watch)
    Event.Draw.Unsubscribe(draw_subscription_name)
    Event.KeyDown.Unsubscribe(subscription_name)
    restore(state.parts)
    recolourer.stop()
end

return sprite_swapper
