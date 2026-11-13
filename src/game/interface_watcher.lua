-- Keeps visiting the components of the game's loaded interfaces, so a change stays on them when
-- the game opens windows or rebuilds their contents (like switching a tab). Walking everything at once costs a lot of frames, so the walk is spread out: each
-- client logic update visits a few hundred components and carries on from there the next time.
-- The shorter a pass, the sooner rebuilt content is changed, so most passes skip hidden
-- components (with everything inside them) and interfaces with nothing to change. Every few
-- passes a full one goes over those too, so hidden things (like a window's other tabs) are
-- already changed the first time they show.
--
-- Between updates only numbers are kept (which interface, which static component), never the
-- components themselves: the game can destroy those in the meantime, and touching a destroyed
-- component can crash the client.
local interface_walker = require("src/game/interface_walker")

local interface_watcher = {}

-- Enough to go over every loaded window several times a second without costing frames.
local components_per_update = 1500
-- Every this many passes is a full one, which also walks hidden components and interfaces that
-- had nothing to change in their last pass.
local full_pass_interval = 5

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
local function continue_pass(watch)
    local visited = 0
    local function visit(component)
        visited = visited + 1
        if watch.visit(component) then
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
    }
    start_pass(watch)
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
