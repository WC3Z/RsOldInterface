-- DEBUG: the one place the plugin's own code calls into the debug tools. Each function is named
-- after something that happened in the swapping, takes the values as they are, and decides what
-- of it to print (activity_log) or count (profile). The callers only call these while
-- events.enabled is true, so nothing here costs anything otherwise.
--
-- To switch the tools on while developing, in main.lua:
--
--   require("src/game/debug_tools").events.enable({ profile = true, activity_log = true })
--
-- With `cost = true` as well as `profile`, what each step of the plugin's work costs is measured
-- by leaving it out in turns (see the cost section of src/debug/profile.lua).
-- With `unstyled = true`, what's showing that the plugin doesn't restyle is listed every few
-- seconds (see src/debug/unstyled.lua).
--
-- With `garbage = "generational"` as well as `profile`, Lua frees its garbage another way, to
-- try against long frames (see src/debug/profile.lua).
--
-- With `layout = "^RS3_PARENT_BANNER_"`, where the game draws the swapped sprites with matching
-- names is printed, with the texts over them (see src/debug/layout.lua).
local activity_log = require("src/debug/activity_log")
local profile = require("src/debug/profile")
local unstyled = require("src/debug/unstyled")
local layout = require("src/debug/layout")
local interface_walker = require("src/game/interface_walker")
local component_fields = require("src/game/component_fields")
local game_ids = require("src/game/game_ids")

local events = {}

events.enabled = false

-- The watch of the swapping that's running, to tell which update it is and which interfaces are
-- watched closely.
---@type InterfaceWatch?
local watch = nil

-- What the swapping did since the last stats line (see activity_log.stats).
local stats_interval = 200
local stats = { frames = 0, checks = 0, swapped_parts = 0, recoloured = 0, reswapped = 0, rebuilt = {} }
local stats_logged_at = 0
-- Whether what's unstyled is listed, and how many updates apart.
local lists_unstyled = false
local unstyled_interval = 150
-- The pattern of the sprite names whose layout is printed, if any.
---@type string?
local layout_pattern = nil
-- The update each interface last had a new swap logged in.
---@type table<integer, integer>
local swap_logged_at = {}

---@return integer
local function update_number()
    return watch and watch.update_number or 0
end

---@param interface_id integer
---@return boolean
local function is_closely_watched(interface_id)
    return watch ~= nil and watch.closely_watched[interface_id] ~= nil
end

---@param tools { profile: boolean?, activity_log: boolean?, unstyled: boolean?, cost: boolean?, layout: string?, garbage: string?, benchmark: boolean? }
function events.enable(tools)
    events.enabled = true
    lists_unstyled = tools.unstyled == true
    layout_pattern = tools.layout
    activity_log.enabled = tools.activity_log == true
    if tools.profile then
        profile.enable()
        profile.measures_cost = tools.cost == true
        profile.collect_garbage_as(tools.garbage)
        profile.runs_benchmark = tools.benchmark == true
    end
end

-- Whether a step of the plugin's work is left out right now, to measure what it costs.
---@param step string
---@return boolean
function events.skips(step)
    return profile.skips(step)
end

function events.disable()
    events.enabled = false
    lists_unstyled = false
    layout_pattern = nil
    activity_log.enabled = false
    profile.disable()
end

-- The swapping started.
---@param new_watch InterfaceWatch
function events.started(new_watch)
    watch = new_watch
    stats_logged_at = 0
    swap_logged_at = {}
end

---@param name string
---@param amount number
function events.count(name, amount)
    profile.count(name, amount)
end

-- A walk came to a component.
---@param component ui.Component
function events.visited(component)
    if not activity_log.enabled or not is_closely_watched(component.interfaceID) or not component.visibleGlobal then
        return
    end
    if component.type == ui.ComponentType.RECTANGLE then
        activity_log.rectangle(component)
    end
    local fields = component_fields.sprite_fields[component.type]
    if fields and fields[1] ~= component_fields.on_component then
        local sprite_ids = {}
        for _, field in ipairs(fields) do
            local holder = component_fields.holder(component, field)
            sprite_ids[field] = holder and holder.spriteID or "none"
        end
        activity_log.interactive(component, sprite_ids)
    end
end

-- A walk came to a part that draws a runtime image: one the plugin swapped, or someone else's.
---@param component ui.Component
---@param field string
---@param parts table<string, SwappedPart>
function events.already_swapped(component, field, parts)
    if not activity_log.enabled or not component.visibleGlobal then
        return
    end
    local key = interface_walker.component_key(component) .. ":" .. field
    local part = parts[key]
    if part then
        activity_log.frame_piece(component, part.game_sprite_id)
    else
        activity_log.trace(update_number(), component.interfaceID, component_fields.runtime_image_id, key .. " shows an image the plugin didn't set")
    end
end

-- A walk came to a part showing a sprite the look has no image for.
---@param component ui.Component
---@param field string
---@param sprite_id integer
---@param parts table<string, SwappedPart>
function events.not_swapped(component, field, sprite_id, parts)
    if not activity_log.enabled or not component.visibleGlobal then
        return
    end
    local key = interface_walker.component_key(component) .. ":" .. field
    if parts[key] then
        activity_log.trace(update_number(), component.interfaceID, sprite_id, key .. " has no image, but was swapped before")
    end
    -- Only in interfaces that just loaded, showed or were rebuilt, not everything at startup.
    if is_closely_watched(component.interfaceID) then
        activity_log.unswapped(component.interfaceID, sprite_id, field, component.width, component.height)
    end
end

-- A showing part or colour was changed for the first time by a walk that isn't a "now" one: it
-- was showing in the game's look for a while.
---@param interface_id integer
---@param what string
---@param walk_kind WalkKind
function events.found_late(interface_id, what, walk_kind)
    if walk_kind ~= "now" then
        profile.late(interface_id, what .. " (" .. walk_kind .. ")")
    end
end

-- A walk swapped a part.
---@param component ui.Component
---@param key string The part's key.
---@param sprite_id integer The game sprite it had.
---@param was_known boolean Whether the plugin had swapped it before.
---@param walk_kind WalkKind
function events.swapped(component, key, sprite_id, was_known, walk_kind)
    local is_showing = component.visibleGlobal
    if is_showing then
        activity_log.frame_piece(component, sprite_id)
    end
    activity_log.trace(update_number(), component.interfaceID, sprite_id, string.format("%s by walk (%s, %s, the %s walk)", key,
        was_known and "again" or "new", is_showing and "showing" or "hidden", walk_kind))
    if was_known then
        return
    end
    if is_showing then
        events.found_late(component.interfaceID, game_ids.sprite_name(sprite_id) or tostring(sprite_id), walk_kind)
    end
    if swap_logged_at[component.interfaceID] ~= update_number() then
        swap_logged_at[component.interfaceID] = update_number()
        activity_log.first_swap(update_number(), component.interfaceID)
    end
end

-- A part is about to get its check after an update: counted by why it's checked that often.
---@param part SwappedPart
function events.checked_every_update(part)
    local why = part.in_use and "in use"
        or part.checked_while_hidden and (part.visible and "showing, a window's frame" or "hidden, a window's frame")
        or part.near_mouse and "near the mouse" or "its turn, away from the mouse"
    profile.count("checked after update: " .. why, 1)
end

-- A swapped part's component is gone.
---@param key string
---@param part SwappedPart
function events.gone(key, part)
    activity_log.trace(update_number(), part.interface_id, part.game_sprite_id, key .. " gone")
end

-- The game had given a swapped part a sprite, and it was swapped again before the frame.
---@param key string
---@param part SwappedPart As it was before this swap.
---@param sprite_id integer The sprite the game gave it.
---@param was_checked_every_update boolean
---@param was_rebuilt boolean Whether it was taken as the game rebuilding the component.
function events.swapped_again(key, part, sprite_id, was_checked_every_update, was_rebuilt)
    activity_log.trace(update_number(), part.interface_id, sprite_id, string.format("%s swapped again before frame (was %d, %s, %s)",
        key, part.game_sprite_id, part.visible and "showing" or "hidden", was_checked_every_update and "every update" or "in turns"))
    stats.reswapped = stats.reswapped + 1
    if sprite_id == part.game_sprite_id then
        stats.rebuilt[part.interface_id] = (stats.rebuilt[part.interface_id] or 0) + 1
    end
    if was_rebuilt then
        profile.rebuilt(part.interface_id)
    end
end

-- A colour is about to be changed.
---@param component ui.Component
---@param field string
---@param game_rgb integer
---@param look_rgb integer
function events.recolouring(component, field, game_rgb, look_rgb)
    if is_closely_watched(component.interfaceID) and component.visibleGlobal then
        activity_log.colour(component, field, game_rgb, look_rgb)
    end
end

---@param interface_id integer
---@param reason string
function events.watching_closely(interface_id, reason)
    activity_log.watching_closely(update_number(), interface_id, reason)
end

-- An interface was found to have loaded or shown.
---@param interface_id integer
---@param reason string
---@param detail string
function events.opened(interface_id, reason, detail)
    profile.opened(interface_id, reason, detail)
end

-- A remembered component was walked.
---@param interface_id integer
---@param static_id integer
function events.remembered_container(interface_id, static_id)
    profile.dump_container(interface_id, static_id)
end

-- What the benchmark runs on.
---@param parts table<string, SwappedPart>
---@param visit fun(component: ui.Component, walk_kind: WalkKind)
---@return BenchmarkSubjects
local function benchmark_subjects(parts, visit)
    local subjects = { visit = function (component) visit(component, "now") end }
    for _, part in pairs(parts) do
        if part.field == component_fields.on_component and part.visible then
            if part.category_id == component_fields.static_category_id then
                subjects.static = subjects.static or part
            else
                subjects.dynamic = subjects.dynamic or part
            end
        end
    end
    subjects.walked_interface_id = game_ids.interface_id("TOPLEVEL_V2") or (subjects.static and subjects.static.interface_id)
    return subjects
end

-- A frame is about to be drawn, before the plugin's own work for it.
---@param event DrawEventPayload?
---@param update integer
---@param parts table<string, SwappedPart>
---@param visit fun(component: ui.Component, walk_kind: WalkKind)
function events.frame(event, update, parts, visit)
    stats.frames = stats.frames + 1
    if activity_log.enabled and watch and update - stats_logged_at >= stats_interval then
        stats_logged_at = update
        activity_log.stats(update, stats, watch.closely_watched)
        stats = { frames = 0, checks = 0, swapped_parts = stats.swapped_parts, recoloured = stats.recoloured, reswapped = 0, rebuilt = {} }
    end
    profile.frame(event, update, function () return benchmark_subjects(parts, visit) end)
end

-- An update's looking and checking is done.
---@param parts table<string, SwappedPart>
---@param recoloured_count integer
function events.checked(parts, recoloured_count)
    local part_count = 0
    for _ in pairs(parts) do
        part_count = part_count + 1
    end
    if lists_unstyled and update_number() % unstyled_interval == 0 then
        unstyled.report(parts)
    end
    if layout_pattern and update_number() % unstyled_interval == 0 then
        layout.report(parts, layout_pattern)
    end
    profile.after_update()
    stats.checks = stats.checks + 1
    stats.swapped_parts = part_count
    stats.recoloured = recoloured_count
    profile.count("swapped parts in all", part_count)
    profile.count("recoloured parts in all", recoloured_count)
end

return events
