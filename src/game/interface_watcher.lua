-- Keeps visiting the components of the game's loaded interfaces, so a change stays on them when
-- the game opens windows or rebuilds their contents (like switching a tab). Walking everything at
-- once costs a lot of frames, so the walk is spread out: each client logic update visits a few
-- hundred components and carries on from there the next time. The shorter a pass, the sooner
-- rebuilt content is changed, so most passes skip hidden components (with everything inside
-- them) and interfaces with nothing to change. Every few passes a full one goes over those too, so
-- hidden things (like a window's other tabs) are already changed the first time they show.
--
-- Some interfaces can't wait for the pass to get to them: ones that have just loaded or just been
-- shown (like a tab in Settings, which is an interface of its own, loaded the first time and
-- hidden and shown after that) and ones the caller asks for with
-- interface_watcher.watch_closely (like one the game is rebuilding). The game often fills those
-- in over several frames (a Settings tab shows a loading spinner, then its rows), so they're
-- watched closely for a while: walked whole once, then their visible parts every update, within a
-- budget of their own, before the pass carries on.
--
-- Between updates only numbers are kept (which interface, which static component), never the
-- components themselves: the game can destroy those in the meantime, and touching a destroyed
-- component can crash the client.
local interface_walker = require("src/game/interface_walker")
local activity_log = require("src/debug/activity_log")

local interface_watcher = {}

-- Enough to go over every loaded window about once a second. Windows that just opened, showed or
-- were rebuilt don't wait for it: they're watched closely.
local components_per_update = 500
-- Every this many passes is a full one, which also walks hidden components and interfaces that
-- had nothing to change in their last pass.
local full_pass_interval = 5
-- Looking for newly loaded or shown interfaces checks every interface ID, so it's only done every
-- this many updates.
local new_interface_check_interval = 3
-- How many updates an interface is watched closely after it loads or shows (about a second), and
-- after it's rebuilt (the game rebuilds bits of big interfaces like the main one often).
local close_watch_updates = { loaded = 30, shown = 30, rebuilt = 10 }
-- The most components the closely watched interfaces may take each update. They take turns, so a
-- big one doesn't crowd out the rest.
local close_watch_components_per_update = 1500

---@class CloseWatch
---@field updates_left integer
---@field walk_hidden boolean Whether the next walk also goes over hidden components (once, after it loads or shows).

---@class InterfaceWatch
---@field subscription_name string
---@field visit fun(component: ui.Component): boolean? Returns true for components it changes, or changed before.
---@field interface_ids integer[] The interfaces loaded when this pass started.
---@field interface_index integer
---@field static_id integer
---@field missing_in_a_row integer
---@field pass_number integer
---@field had_changes table<integer, boolean> Whether each interface had anything to change in its last pass.
---@field changes_in_this_interface boolean
---@field is_full_pass boolean
---@field loaded table<integer, boolean> The interfaces loaded at the last check for new ones, and whether they were showing.
---@field updates_since_new_interface_check integer
---@field closely_watched table<integer, CloseWatch>
---@field close_watch_turn integer Where in the closely watched interfaces the next update starts.
---@field update_number integer
---@field probes table<integer, integer> For each interface, the static ID of a component that had something to change: whether it's showing tells whether the interface is.

---@param watch InterfaceWatch
local function start_pass(watch)
    watch.pass_number = watch.pass_number + 1
    watch.is_full_pass = watch.pass_number % full_pass_interval == 1
    watch.interface_ids = {}
    interface_walker.each_loaded_interface(function (interface_id)
        if watch.is_full_pass or watch.had_changes[interface_id] ~= false then
            watch.interface_ids[#watch.interface_ids + 1] = interface_id
        end
    end)
    watch.changes_in_this_interface = false
    watch.interface_index = 1
    watch.static_id = 0
    watch.missing_in_a_row = 0
end

---@param watch InterfaceWatch
---@param interface_id integer
---@param reason "loaded"|"shown"|"rebuilt"
function interface_watcher.watch_closely(watch, interface_id, reason)
    local close_watch = watch.closely_watched[interface_id]
    if not close_watch then
        activity_log.watching_closely(watch.update_number, interface_id, reason)
        close_watch = { updates_left = 0, walk_hidden = false }
        watch.closely_watched[interface_id] = close_watch
    end
    close_watch.updates_left = math.max(close_watch.updates_left, close_watch_updates[reason])
    if reason ~= "rebuilt" then
        close_watch.walk_hidden = true
    end
end

-- Watches an interface closely for longer, if it already is: while new parts keep turning up in a
-- tab that just loaded, it's still filling in.
---@param watch InterfaceWatch
---@param interface_id integer
function interface_watcher.keep_watching_closely(watch, interface_id)
    local close_watch = watch.closely_watched[interface_id]
    if close_watch then
        close_watch.updates_left = math.max(close_watch.updates_left, close_watch_updates.rebuilt)
    end
end

-- Whether an interface is showing, going by its probe: a component that had something to change,
-- so it's part of what the interface shows (like the rows of a tab). Without one, it goes by its
-- first few components, where the root usually is.
---@param watch InterfaceWatch
---@param interface_id integer
local function is_showing(watch, interface_id)
    local probe = watch.probes[interface_id]
    if probe then
        local component = ui.Interfaces:GetComponent(interface_id, probe)
        return component ~= nil and component.visibleGlobal
    end
    for static_id = 0, 2 do
        local component = ui.Interfaces:GetComponent(interface_id, static_id)
        if component and component.visibleGlobal then
            return true
        end
    end
    return false
end

-- Visits a component, and keeps it as its interface's probe if it has something to change and
-- the interface has none yet.
---@param watch InterfaceWatch
---@param component ui.Component
---@return boolean? # What the visit returned.
local function visit_and_probe(watch, component)
    local changed = watch.visit(component)
    if changed and watch.probes[component.interfaceID] == nil then
        watch.probes[component.interfaceID] = component.staticID
    end
    return changed
end

---@param watch InterfaceWatch
local function watch_new_interfaces_closely(watch)
    watch.updates_since_new_interface_check = watch.updates_since_new_interface_check + 1
    if watch.updates_since_new_interface_check < new_interface_check_interval then
        return
    end
    watch.updates_since_new_interface_check = 0
    local loaded = {}
    interface_walker.each_loaded_interface(function (interface_id)
        local showing = is_showing(watch, interface_id)
        loaded[interface_id] = showing
        if watch.loaded[interface_id] == nil then
            interface_watcher.watch_closely(watch, interface_id, "loaded")
        elseif showing and not watch.loaded[interface_id] then
            interface_watcher.watch_closely(watch, interface_id, "shown")
        end
    end)
    watch.loaded = loaded
end

-- Hidden components only the first time after an interface loads or shows, so a tab that loads
-- hidden is ready when it shows.
---@param watch InterfaceWatch
local function walk_closely_watched(watch)
    -- Walking can make the caller watch more interfaces closely, so go over a copy, in a fixed
    -- order so taking turns works.
    local interface_ids = {}
    for interface_id in pairs(watch.closely_watched) do
        interface_ids[#interface_ids + 1] = interface_id
    end
    table.sort(interface_ids)
    local count = #interface_ids
    local looked_up = 0
    for turn = 0, count - 1 do
        if looked_up >= close_watch_components_per_update then
            watch.close_watch_turn = watch.close_watch_turn + turn
            break
        end
        local interface_id = interface_ids[(watch.close_watch_turn + turn) % count + 1]
        local close_watch = watch.closely_watched[interface_id]
        if ui.Interfaces:GetInterface(interface_id) then
            looked_up = looked_up + interface_walker.each_component(interface_id, function (component)
                visit_and_probe(watch, component)
            end, not close_watch.walk_hidden)
            close_watch.walk_hidden = false
        end
    end
    for _, interface_id in ipairs(interface_ids) do
        local close_watch = watch.closely_watched[interface_id]
        close_watch.updates_left = close_watch.updates_left - 1
        if close_watch.updates_left <= 0 then
            watch.closely_watched[interface_id] = nil
        end
    end
end

---@param watch InterfaceWatch
local function continue_pass(watch)
    watch.update_number = watch.update_number + 1
    watch_new_interfaces_closely(watch)
    walk_closely_watched(watch)

    local visited = 0
    local function visit(component)
        visited = visited + 1
        if visit_and_probe(watch, component) then
            watch.changes_in_this_interface = true
        end
    end

    while visited < components_per_update do
        local interface_id = watch.interface_ids[watch.interface_index]
        if interface_id == nil then
            start_pass(watch)
            return
        end
        local found, showing = interface_walker.visit_static(interface_id, watch.static_id, visit, not watch.is_full_pass)
        if found then
            watch.missing_in_a_row = 0
        else
            watch.missing_in_a_row = watch.missing_in_a_row + 1
        end
        if not showing then
            -- Looking a component up costs too, so it counts even when it isn't visited.
            visited = visited + 1
        end
        watch.static_id = watch.static_id + 1
        if watch.missing_in_a_row >= interface_walker.allowed_missing_ids then
            watch.had_changes[interface_id] = watch.changes_in_this_interface
            watch.changes_in_this_interface = false
            watch.interface_index = watch.interface_index + 1
            watch.static_id = 0
            watch.missing_in_a_row = 0
        end
    end
end

---@param subscription_name string
---@param visit fun(component: ui.Component): boolean?
---@return InterfaceWatch
function interface_watcher.start(subscription_name, visit)
    ---@type InterfaceWatch
    local watch = {
        subscription_name = subscription_name,
        visit = visit,
        interface_ids = {},
        interface_index = 1,
        static_id = 0,
        missing_in_a_row = 0,
        pass_number = 0,
        had_changes = {},
        changes_in_this_interface = false,
        is_full_pass = false,
        loaded = {},
        updates_since_new_interface_check = 0,
        closely_watched = {},
        close_watch_turn = 0,
        update_number = 0,
        probes = {},
    }
    start_pass(watch)
    -- Everything loaded now is walked by the first pass, so only interfaces loading later count
    -- as new.
    interface_walker.each_loaded_interface(function (interface_id)
        watch.loaded[interface_id] = is_showing(watch, interface_id)
    end)
    Event.Logic.Subscribe(subscription_name, function ()
        continue_pass(watch)
    end)
    return watch
end

---@param watch InterfaceWatch
function interface_watcher.stop(watch)
    Event.Logic.Unsubscribe(watch.subscription_name)
end

return interface_watcher
