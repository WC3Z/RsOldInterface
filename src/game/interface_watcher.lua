-- Keeps visiting the components of the game's loaded interfaces, so a change stays on them when
-- the game opens windows or rebuilds their contents. The game has no event for any of that, so it
-- has to be looked for, and looking at a component costs about a microsecond: looking at all of
-- them every update would cost a lot of frames. So, before the frame after each client logic
-- update is drawn (the game fills windows in during its update, so looking then would leave the
-- game's own look showing for a frame), these walks visit components:
--
--   what                              when                                  where              walk kind
--   an interface that just loaded     that update, hidden parts too         on_loaded          now
--   fresh interfaces: just loaded or  every update (bigger ones every 2nd   walk_closely_      now
--     shown, or new parts found late    or 3rd), for fresh_updates            watched
--   warm interfaces: fresh before     every warm_interval updates, for      walk_closely_      warm
--                                       warm_updates                          watched
--   an interface where the caller     that update, but not more often than  walk_containers    now
--     saw something rebuilt             updates_between_rebuild_walks
--   components the caller points out  the next container_updates updates    walk_containers    now
--   remembered components             every update                          walk_remembered_   now
--                                                                             containers
--   everything showing                showing_components_per_update each    continue_showing_  pass
--                                       update, going round                   pass
--   everything loaded, hidden too     background_components_per_update      continue_          background
--                                       each update, going round              background_walk
--
-- - Loading and showing are looked for first: every interface ID is checked for having loaded
--   (that's cheap), and every loaded interface for showing, by its root components (like a tab in
--   Settings, which stays loaded and is hidden and shown).
-- - Fresh interfaces are walked every update because the game often fills a window in over
--   several frames (a spinner, then rows). Interfaces mounted inside one that opened are fresh
--   too: a window's content is often an interface of its own.
-- - Warm is for what turns up while a window's being used, like rows when a list is scrolled.
-- - Remembered components are ones in an interface too big to be fresh where parts the game
--   created were found late, like the layer plugins' windows are made in.
-- - The pass is for what all of that misses; what it finds makes a small interface fresh. The
--   background walk gets hidden content (like a window's other tabs) mostly changed before it
--   shows.
-- - The walk kind is passed to the caller's visit with each component: what a "now" walk finds
--   can't have been showing unchanged for long, what the others find may have been.
--
-- Hidden components are skipped with everything inside them, using each interface's tree of static
-- components (which stays the same while it's loaded).
--
-- Why every ID is checked, instead of walking down from the main interface: the component an
-- interface is mounted in doesn't list that interface among its children (IterateStaticComponents
-- and IterateDynamicComponents give nothing there, and GetChild doesn't reach it either), so a
-- walk from the top never leaves the main interface. And the ONSUBCHANGE hook isn't called for
-- every load (not for the Bank's), and when it is, it's in the same update the check finds the
-- interface anyway.
--
-- Between frames only numbers are kept (which interface, which static component), never the
-- components themselves: the game can destroy those in the meantime, and touching a destroyed
-- component can crash the client.
local interface_walker = require("src/game/interface_walker")
local game_ids = require("src/game/game_ids")
local guard = require("src/game/guard")
local events = require("src/game/debug_tools").events

local interface_watcher = {}

-- Which walk is visiting a component. What a "now" walk finds can't have been showing unchanged
-- for long; what the others find may have been.
---@alias WalkKind "now"|"warm"|"pass"|"background"

-- The pass over everything showing: enough to get round in a fraction of a second.
local showing_components_per_update = 600
-- The slow walk over everything.
local background_components_per_update = 150
-- The numbers below were tuned in game against what was found late and what the walks cost
-- (about a microsecond a lookup), at about 50 updates a second.
--
-- How many updates an interface stays fresh after it loads or shows (a bit over half a second),
-- and for how many more when new parts keep turning up in it.
local fresh_updates = 30
local fresh_updates_after_new_parts = 6
-- How many updates a pointed-out component is walked for.
local container_updates = 4
-- An interface's roots are each checked for showing (the docked windows' tab bars are all roots of
-- one interface). Only the first few if there are more than this: if the tree couldn't be read,
-- every component counts as a root.
local most_roots_checked = 64
local roots_checked_of_many = 3
-- Fresh interfaces are walked every update, so only smaller ones become fresh for other reasons
-- than loading or showing, and all of them together get a budget each update.
local most_components_to_make_fresh = 1500
local fresh_components_per_update = 4000
-- A fresh interface is walked every update for its first few, then every update for each this
-- many lookups its walk takes (the Bank's takes a couple of thousand).
local fresh_updates_walked_always = 5
local fresh_lookups_per_update = 1000
local longest_fresh_interval = 3
-- After being fresh, an interface stays warm while it shows: walked every few updates for about ten
-- seconds, for what turns up while a window's being used (like rows when a list is scrolled).
local warm_updates = 500
local warm_interval = 4
-- Components where the game created parts that were found late are remembered and walked every
-- update from then on (like the layer plugins' windows are made in): at most this many.
local most_remembered_containers = 24
-- When the game rebuilds something in a fresh or warm interface, the whole interface is walked
-- before the frame (what's rebuilt often isn't all in one place), but not more often than this.
local updates_between_rebuild_walks = 3
-- Small interfaces whose content the game swaps without the interface loading or showing, which
-- are walked every update while they show: the pop-up lists of the ribbon's and docked windows'
-- tabs, and the window plugins put their content in.
local always_fresh_ids = game_ids.interface_ids({ "TOPLEVEL_V2_PARENTS_QUICKCHILDREN", "TOPLEVEL_V2_PLUGIN_CONTENT" })
-- The main interface holds every window: it never becomes fresh, nor does what's mounted in it
-- because of it.
local main_interface_id = game_ids.interface_id("TOPLEVEL_V2")
-- A walked_at or rebuild_walk_at from long enough ago for any interval to have passed.
local never_walked = -100

---@class WatchedInterface An interface that's watched closely: fresh, or warm after having been.
---@field fresh_updates_left integer While above zero it's fresh.
---@field warm_updates_left integer How long it stays warm after that.
---@field opened boolean Whether it's fresh because it loaded or showed (what's mounted in it is fresh too then).
---@field walked_at integer The update it was last walked whole in.
---@field lookups integer How many lookups that walk took.
---@field was_rebuilt boolean Whether something in it was rebuilt since it was last walked for that.
---@field rebuild_walk_at integer The update it was last walked in because something in it was rebuilt.

---@param fresh_updates_left integer
---@param warm_updates_left integer
---@param opened boolean
---@return WatchedInterface
local function watched_interface(fresh_updates_left, warm_updates_left, opened)
    return {
        fresh_updates_left = fresh_updates_left,
        warm_updates_left = warm_updates_left,
        opened = opened,
        walked_at = never_walked,
        lookups = 0,
        was_rebuilt = false,
        rebuild_walk_at = never_walked,
    }
end

---@class InterfaceWatch
---@field subscription_name string
---@field visit_as table<WalkKind, fun(component: ui.Component)> The caller's visit for each kind of walk.
---@field update_number integer
---@field is_started boolean Whether before_frame has run: until then, everything loaded is new.
---@field loaded table<integer, boolean> The loaded interfaces, and whether they were showing when last checked.
---@field trees table<integer, StaticTree>
---@field closely_watched table<integer, WatchedInterface> The fresh and warm interfaces.
---@field showing_roots table<integer, table<integer, boolean>> Which of each interface's roots were showing when last checked.
---@field watched_turn integer Which watched interface is walked first next update.
---@field remembered_containers table<string, { interface_id: integer, static_id: integer }>
---@field remembered_container_count integer
---@field containers table<string, { interface_id: integer, static_id: integer, updates_left: integer }>
---@field pass_ids integer[] The showing interfaces the pass goes over.
---@field pass_index integer
---@field pass_position integer Where in the interface's tree the pass is.
---@field background_ids integer[]
---@field background_index integer
---@field background_static_id integer
---@field background_missing_in_a_row integer

-- Checks which of an interface's roots are showing.
---@param watch InterfaceWatch
---@param interface_id integer
---@return boolean showing Whether any is.
---@return boolean newly_showing Whether one is that wasn't at the last check.
local function check_showing(watch, interface_id)
    local tree = watch.trees[interface_id]
    if tree == nil then
        return false, false
    end
    local was_showing = watch.showing_roots[interface_id]
    if was_showing == nil then
        was_showing = {}
        watch.showing_roots[interface_id] = was_showing
    end
    local checked = #tree.roots <= most_roots_checked and #tree.roots or roots_checked_of_many
    local showing, newly_showing = false, false
    for index = 1, checked do
        local component = ui.Interfaces:GetComponent(interface_id, tree.roots[index])
        local root_showing = component ~= nil and component.visibleGlobal
        if root_showing then
            showing = true
            if not was_showing[index] then
                newly_showing = true
            end
        end
        was_showing[index] = root_showing
    end
    return showing, newly_showing
end

---@param component ui.Component
---@return integer? # The interface a root component is mounted in.
local function mounted_in(component)
    local parent = component.parentStatic
    return parent ~= nil and parent.interfaceID or nil
end

---@param watch InterfaceWatch
---@param interface_id integer
---@param reason string
local function make_fresh(watch, interface_id, reason)
    if events.enabled and watch.closely_watched[interface_id] == nil then
        events.watching_closely(interface_id, reason)
    end
    watch.closely_watched[interface_id] = watched_interface(fresh_updates, warm_updates, reason == "loaded" or reason == "shown")
end

---@param watch InterfaceWatch
---@param interface_id integer
local function is_small(watch, interface_id)
    local tree = watch.trees[interface_id]
    return tree ~= nil and interface_id ~= main_interface_id and #tree.order <= most_components_to_make_fresh
end

-- A new showing part was found in an interface. If it's fresh it stays so for longer: while new
-- parts keep turning up in a window that just opened, it's still filling in. If it isn't, the
-- pass found it late, and more may follow (like rows turning up while a list is scrolled), so
-- it becomes fresh.
---@param watch InterfaceWatch
---@param interface_id integer
---@param static_id integer The static component the part is, or is inside.
---@param is_created boolean Whether the game created the part while running.
---@param walk_kind WalkKind The walk that found it.
function interface_watcher.found_new_part(watch, interface_id, static_id, is_created, walk_kind)
    local was_late = walk_kind ~= "now"
    -- The background walk goes over hidden parts too: what it finds says nothing about the rest.
    local found_while_showing = was_late and walk_kind ~= "background"
    local watched = watch.closely_watched[interface_id]
    if watched then
        watched.fresh_updates_left = math.max(watched.fresh_updates_left, was_late and fresh_updates or fresh_updates_after_new_parts)
        watched.warm_updates_left = warm_updates
    elseif found_while_showing and is_small(watch, interface_id) then
        make_fresh(watch, interface_id, "new parts")
    end
    -- Only in interfaces too big to be fresh: the others are walked whole.
    if found_while_showing and is_created and not is_small(watch, interface_id) then
        local key = interface_id .. ":" .. static_id
        if watch.remembered_containers[key] == nil and watch.remembered_container_count < most_remembered_containers then
            watch.remembered_containers[key] = { interface_id = interface_id, static_id = static_id }
            watch.remembered_container_count = watch.remembered_container_count + 1
            if events.enabled then
                events.opened(interface_id, "remembers component " .. static_id, "")
            end
        end
    end
end

-- Interfaces mounted inside a fresh one are fresh too: a window's content is often an interface
-- of its own that was loaded before (like the music player in Settings), filled in a bit later.
---@param watch InterfaceWatch
local function make_mounted_interfaces_fresh(watch)
    if next(watch.closely_watched) == nil then
        return
    end
    for interface_id, showing in pairs(watch.loaded) do
        local tree = watch.trees[interface_id]
        if showing and tree and tree.roots[1] and not watch.closely_watched[interface_id] and is_small(watch, interface_id) then
            local root = ui.Interfaces:GetComponent(interface_id, tree.roots[1])
            local found, parent_interface_id = pcall(mounted_in, root)
            local parent_watched = found and parent_interface_id ~= nil and parent_interface_id ~= interface_id
                and watch.closely_watched[parent_interface_id]
            -- Only in one that opened, and just for as long as that one.
            if parent_watched and parent_watched.opened and parent_watched.fresh_updates_left > 1 and is_small(watch, parent_interface_id) then
                watch.closely_watched[interface_id] = watched_interface(parent_watched.fresh_updates_left, warm_updates, false)
                if events.enabled then
                    events.watching_closely(interface_id, "mounted")
                    events.opened(interface_id, "in a fresh interface", "")
                end
            end
        end
    end
end

-- Walks a static component and what the game created inside it before this frame and the next
-- few: like a tab bar the game is building again with new parts.
---@param watch InterfaceWatch
---@param interface_id integer
---@param static_id integer
function interface_watcher.walk_container_soon(watch, interface_id, static_id)
    watch.containers[interface_id .. ":" .. static_id] = {
        interface_id = interface_id,
        static_id = static_id,
        updates_left = container_updates,
    }
    local watched = watch.closely_watched[interface_id]
    if watched then
        watched.was_rebuilt = true
    end
end

-- Walks the pointed-out components. Called once before each frame after an update, after the
-- caller has pointed out this update's.
---@param watch InterfaceWatch
function interface_watcher.walk_containers(watch)
    local walked = 0
    for key, container in pairs(watch.containers) do
        interface_walker.visit_static(container.interface_id, container.static_id, watch.visit_as.now, true)
        walked = walked + 1
        container.updates_left = container.updates_left - 1
        if container.updates_left <= 0 then
            watch.containers[key] = nil
        end
    end
    if events.enabled then
        events.count("containers walked", walked)
    end

    local rebuilt_ids = {}
    for interface_id, watched in pairs(watch.closely_watched) do
        if watched.was_rebuilt then
            rebuilt_ids[#rebuilt_ids + 1] = interface_id
        end
    end
    for _, interface_id in ipairs(rebuilt_ids) do
        local watched = watch.closely_watched[interface_id]
        local tree = watch.trees[interface_id]
        local walked_this_update = watched and watched.walked_at == watch.update_number
        if watched and tree and watch.loaded[interface_id] and not walked_this_update
            and watch.update_number - watched.rebuild_walk_at >= updates_between_rebuild_walks then
            watched.was_rebuilt = false
            watched.rebuild_walk_at = watch.update_number
            local _, looked_up = interface_walker.walk_showing(interface_id, tree, watch.visit_as.now, 1, math.huge)
            watched.walked_at = watch.update_number
            watched.lookups = looked_up
            if events.enabled then
                events.count("lookups after rebuilds", looked_up)
            end
        end
    end
end

-- An interface that just loaded is walked whole, hidden parts too, so those are ready when they
-- show.
---@param watch InterfaceWatch
---@param interface_id integer
---@param is_start boolean Whether the plugin just started (everything loaded is new to it then).
local function on_loaded(watch, interface_id, is_start)
    watch.trees[interface_id] = interface_walker.static_tree(interface_id)
    watch.showing_roots[interface_id] = nil
    local showing = check_showing(watch, interface_id)
    watch.loaded[interface_id] = showing
    local looked_up = interface_walker.each_component(interface_id, watch.visit_as.now, false)
    if not is_start then
        make_fresh(watch, interface_id, "loaded")
        watch.closely_watched[interface_id].walked_at = watch.update_number
    end
    if events.enabled then
        events.count("lookups in new interfaces", looked_up)
        if not is_start then
            events.opened(interface_id, showing and "loaded" or "loaded hidden",
                string.format("%d components, %d roots", #watch.trees[interface_id].order, #watch.trees[interface_id].roots))
        end
    end
end

---@param watch InterfaceWatch
---@param is_start boolean
local function find_loaded_and_shown(watch, is_start)
    for interface_id = 0, interface_walker.last_interface_id do
        if ui.Interfaces:GetInterface(interface_id) then
            if watch.loaded[interface_id] == nil then
                on_loaded(watch, interface_id, is_start)
            end
        elseif watch.loaded[interface_id] ~= nil then
            watch.loaded[interface_id] = nil
            watch.trees[interface_id] = nil
            watch.showing_roots[interface_id] = nil
            watch.closely_watched[interface_id] = nil
        end
    end
    local showing_count = 0
    for interface_id in pairs(watch.loaded) do
        local showing, newly_showing = check_showing(watch, interface_id)
        if showing then
            showing_count = showing_count + 1
            if newly_showing then
                make_fresh(watch, interface_id, "shown")
                if events.enabled then
                    events.opened(interface_id, "shown", "")
                end
            end
        end
        watch.loaded[interface_id] = showing
    end
    make_mounted_interfaces_fresh(watch)
    for interface_id in pairs(always_fresh_ids) do
        if watch.loaded[interface_id] then
            local watched = watch.closely_watched[interface_id]
            if watched then
                watched.fresh_updates_left = fresh_updates
            else
                watch.closely_watched[interface_id] = watched_interface(fresh_updates, 0, false)
            end
        end
    end
    if events.enabled then
        events.count("showing interfaces", showing_count)
    end
end

-- How many updates apart a closely watched interface is walked.
---@param watched WatchedInterface
---@return integer
local function walk_interval(watched)
    if watched.fresh_updates_left <= 0 then
        return warm_interval
    end
    local just_became_fresh = watched.fresh_updates_left > fresh_updates - fresh_updates_walked_always
    if just_became_fresh then
        return 1
    end
    return math.min(longest_fresh_interval, 1 + watched.lookups // fresh_lookups_per_update)
end

-- Walks the showing parts of the closely watched interfaces that are due, within this update's
-- budget. With more than the budget allows, they take turns.
---@param watch InterfaceWatch
---@param interface_ids integer[] The closely watched interfaces, in a fixed order.
---@return integer # How many components were looked up.
local function walk_closely_watched(watch, interface_ids)
    local count = #interface_ids
    local looked_up = 0
    for turn = 0, count - 1 do
        if looked_up >= fresh_components_per_update then
            watch.watched_turn = watch.watched_turn + turn
            break
        end
        local interface_id = interface_ids[(watch.watched_turn + turn) % count + 1]
        local watched = watch.closely_watched[interface_id]
        local tree = watch.trees[interface_id]
        if tree and watch.loaded[interface_id] and watch.update_number - watched.walked_at >= walk_interval(watched) then
            -- What a warm walk finds was showing unchanged for a few updates.
            local visit = watched.fresh_updates_left <= 0 and watch.visit_as.warm or watch.visit_as.now
            local _, walked = interface_walker.walk_showing(interface_id, tree, visit, 1, math.huge)
            watched.walked_at = watch.update_number
            watched.lookups = walked
            looked_up = looked_up + walked
        end
    end
    return looked_up
end

-- A fresh interface gets an update less fresh, and warm after that; a warm one an update less
-- warm, and no longer watched closely after that, or when it stops showing.
---@param watch InterfaceWatch
---@param interface_ids integer[]
local function age_closely_watched(watch, interface_ids)
    for _, interface_id in ipairs(interface_ids) do
        local watched = watch.closely_watched[interface_id]
        if watched.fresh_updates_left > 0 then
            watched.fresh_updates_left = watched.fresh_updates_left - 1
        else
            watched.warm_updates_left = watched.warm_updates_left - 1
            if watched.warm_updates_left <= 0 or not watch.loaded[interface_id] then
                watch.closely_watched[interface_id] = nil
            end
        end
    end
end

-- The remembered components are walked every update, unless their interface is walked anyway.
---@param watch InterfaceWatch
local function walk_remembered_containers(watch)
    for _, container in pairs(watch.remembered_containers) do
        if not watch.closely_watched[container.interface_id] then
            interface_walker.visit_static(container.interface_id, container.static_id, watch.visit_as.now, true)
        end
        if events.enabled then
            events.remembered_container(container.interface_id, container.static_id)
        end
    end
end

---@param watch InterfaceWatch
local function walk_fresh_and_warm(watch)
    -- Walking can make more interfaces fresh, so go over a copy, in a fixed order so they can
    -- take turns.
    local interface_ids = {}
    for interface_id in pairs(watch.closely_watched) do
        interface_ids[#interface_ids + 1] = interface_id
    end
    table.sort(interface_ids)
    local looked_up = walk_closely_watched(watch, interface_ids)
    age_closely_watched(watch, interface_ids)
    walk_remembered_containers(watch)
    if events.enabled then
        events.count("remembered components", watch.remembered_container_count)
        events.count("lookups in fresh interfaces", looked_up)
        events.count("fresh interfaces", #interface_ids)
    end
end

---@param watch InterfaceWatch
---@return boolean # Whether there's anything to go over.
local function start_showing_pass(watch)
    watch.pass_ids = {}
    for interface_id, showing in pairs(watch.loaded) do
        if showing then
            watch.pass_ids[#watch.pass_ids + 1] = interface_id
        end
    end
    table.sort(watch.pass_ids)
    watch.pass_index = 1
    watch.pass_position = 1
    if events.enabled then
        events.count("passes over what's showing", 1)
    end
    return #watch.pass_ids > 0
end

---@param watch InterfaceWatch
local function continue_showing_pass(watch)
    local budget = showing_components_per_update
    local started_passes = 0
    while budget > 0 do
        local interface_id = watch.pass_ids[watch.pass_index]
        if interface_id == nil then
            started_passes = started_passes + 1
            if started_passes > 1 or not start_showing_pass(watch) then
                break
            end
        else
            local tree = watch.trees[interface_id]
            local next_position = nil
            -- Fresh interfaces are walked every update as it is.
            if tree and watch.loaded[interface_id] and not watch.closely_watched[interface_id] then
                local looked_up
                next_position, looked_up = interface_walker.walk_showing(interface_id, tree, watch.visit_as.pass, watch.pass_position, budget)
                budget = budget - looked_up
                if events.enabled then
                    events.count("lookups in the pass", looked_up)
                end
            end
            if next_position then
                watch.pass_position = next_position
            else
                watch.pass_index = watch.pass_index + 1
                watch.pass_position = 1
                budget = budget - 1
            end
        end
    end
end

---@param watch InterfaceWatch
local function continue_background_walk(watch)
    local looked_up = 0
    local function visit(component)
        looked_up = looked_up + 1
        watch.visit_as.background(component)
    end
    local started_walks = 0
    while looked_up < background_components_per_update do
        local interface_id = watch.background_ids[watch.background_index]
        if interface_id == nil then
            started_walks = started_walks + 1
            if started_walks > 1 then
                break
            end
            watch.background_ids = {}
            for loaded_id in pairs(watch.loaded) do
                watch.background_ids[#watch.background_ids + 1] = loaded_id
            end
            table.sort(watch.background_ids)
            watch.background_index = 1
            watch.background_static_id = 0
            watch.background_missing_in_a_row = 0
        else
            local found = interface_walker.visit_static(interface_id, watch.background_static_id, visit, false)
            if found then
                watch.background_missing_in_a_row = 0
            else
                watch.background_missing_in_a_row = watch.background_missing_in_a_row + 1
                looked_up = looked_up + 1
            end
            watch.background_static_id = watch.background_static_id + 1
            if watch.background_missing_in_a_row >= interface_walker.allowed_missing_ids then
                watch.background_index = watch.background_index + 1
                watch.background_static_id = 0
                watch.background_missing_in_a_row = 0
            end
        end
    end
    if events.enabled then
        events.count("lookups in the background walk", looked_up)
    end
end

-- Does this update's looking and walking. Called before the first frame after each update.
---@param watch InterfaceWatch
function interface_watcher.before_frame(watch)
    local is_start = not watch.is_started
    watch.is_started = true
    find_loaded_and_shown(watch, is_start)
    walk_fresh_and_warm(watch)
    continue_showing_pass(watch)
    continue_background_walk(watch)
end

-- Starts counting the game's updates. Nothing is looked at until before_frame is called.
---@param subscription_name string
---@param visit fun(component: ui.Component, walk_kind: WalkKind) Called for each component a walk comes to.
---@return InterfaceWatch
function interface_watcher.start(subscription_name, visit)
    ---@type InterfaceWatch
    local watch = {
        subscription_name = subscription_name,
        visit_as = {
            now = function (component) visit(component, "now") end,
            warm = function (component) visit(component, "warm") end,
            pass = function (component) visit(component, "pass") end,
            background = function (component) visit(component, "background") end,
        },
        update_number = 0,
        is_started = false,
        loaded = {},
        trees = {},
        closely_watched = {},
        showing_roots = {},
        watched_turn = 0,
        remembered_containers = {},
        remembered_container_count = 0,
        containers = {},
        pass_ids = {},
        pass_index = 1,
        pass_position = 1,
        background_ids = {},
        background_index = 1,
        background_static_id = 0,
        background_missing_in_a_row = 0,
    }
    Event.Logic.Subscribe(subscription_name, guard.guarded("in an update", function ()
        watch.update_number = watch.update_number + 1
    end))
    return watch
end

---@param watch InterfaceWatch
function interface_watcher.stop(watch)
    Event.Logic.Unsubscribe(watch.subscription_name)
end

return interface_watcher
