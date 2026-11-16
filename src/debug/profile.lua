-- DEBUG: measures what the plugin's work costs, and what it finds late, to decide how to make it
-- faster. Prints:
-- - every 200 updates, how much of each kind of work there was (the game's Lua has no clock to
--   time it with);
-- - once, what each kind of game call costs (the benchmark: the game stutters for a few seconds);
-- - each interface that loads or shows, and how long before that the last server packet, click
--   and key press were (would those be a sign to look for new interfaces right away?);
-- - parts only found by the slow regular walk while showing: those were drawn in the new look for
--   a while;
-- - which of a hovered part's parents also count as under the mouse.
local interface_walker = require("src/game/interface_walker")

local profile = {}

profile.enabled = false
profile.benchmark_iterations = 100000
profile.benchmark_at_update = 300
-- Both off: one of them crashed the client when the plugin was turned on (2026-11-17). To be tried
-- one at a time.
profile.listens_to_events = false
profile.traces_hover = false

local prefix = "[Old Interface] "
local subscription_name = "old-interface-profile"
local report_interval = 200
local clock = type(os) == "table" and os.clock or nil

---@type table<string, number>
local counts = {}
local frames = 0
local frame_seconds = 0
local typical_frame_seconds = 0
local reported_at = 0
local benchmark_frame_seconds = 0
-- The results so far, printed again with every few reports: the console only keeps so many lines.
---@type string[]
local benchmark_summary = {}
local reports = 0
local current_update = 0

---@type table<string, integer>
local last_event_update = {}
local listened_events = { ServerLogic = "packet", MiniMenuEntrySelected = "click", KeyDown = "key" }

---@type table<integer, integer>
local opened_at = {}
local lines_left = { opened = 80, late = 30, hover = 15 }

---@param interface_id integer
local function interface_name(interface_id)
    local found, name = pcall(id.Interface.FromID, interface_id)
    return found and name or tostring(interface_id)
end

---@param kind string
---@param text string
local function print_limited(kind, text)
    if lines_left[kind] > 0 then
        lines_left[kind] = lines_left[kind] - 1
        print(prefix .. text)
    end
end

---@param name string
---@param amount number
function profile.count(name, amount)
    if profile.enabled then
        counts[name] = (counts[name] or 0) + amount
    end
end

---@param values table<string, number>
---@param updates integer
---@param format string
local function per_update(values, updates, format)
    local names = {}
    for name in pairs(values) do
        names[#names + 1] = name
    end
    table.sort(names)
    local texts = {}
    for _, name in ipairs(names) do
        texts[#texts + 1] = string.format(format, name, values[name] / updates)
    end
    return table.concat(texts, ", ")
end

local function report()
    local updates = math.max(1, current_update - reported_at)
    reported_at = current_update
    typical_frame_seconds = frames > 0 and frame_seconds / frames or 0
    print(string.format("%sprofile at update %d: %.0f fps; per update: %s", prefix, current_update,
        frame_seconds > 0 and frames / frame_seconds or 0, per_update(counts, updates, "%s %.1f")))
    counts = {}
    frames = 0
    frame_seconds = 0
    reports = reports + 1
    if #benchmark_summary > 0 and reports % 3 == 0 then
        print(string.format("%sbenchmark results, ns per call (usual frame was %.1f ms): %s", prefix, benchmark_frame_seconds * 1000, table.concat(benchmark_summary, "; ")))
    end
end

---@param name string
local function updates_since(name)
    local last = last_event_update[name]
    return last and tostring(current_update - last) or "never"
end

-- An interface was found to have loaded or shown.
---@param interface_id integer
---@param reason string
---@param found_by string
function profile.opened(interface_id, reason, found_by)
    if not profile.enabled then
        return
    end
    opened_at[interface_id] = current_update
    local events = profile.listens_to_events and string.format("; updates since last packet %s, click %s, key %s",
        updates_since("packet"), updates_since("click"), updates_since("key")) or ""
    print_limited("opened", string.format("opened: %s %s at update %d (%s)%s",
        interface_name(interface_id), reason, current_update, found_by, events))
end

-- A showing part was only found by the regular walk.
---@param interface_id integer
---@param what string
function profile.late(interface_id, what)
    -- Everything is found by the regular walk when the plugin starts.
    if not profile.enabled or current_update < 300 then
        return
    end
    profile.count("late in " .. interface_name(interface_id), 1)
    local opened = opened_at[interface_id]
    print_limited("late", string.format("late: %s in %s at update %d, %s", what, interface_name(interface_id), current_update,
        opened and string.format("%d updates after it opened", current_update - opened) or "not opened since the plugin started"))
end

-- A part got its own sprite back, which is taken as its interface being rebuilt.
---@param interface_id integer
function profile.rebuilt(interface_id)
    profile.count("rebuilt " .. interface_name(interface_id), 1)
end

---@type table<string, boolean>
local dumped = {}

-- Prints, once, what the game created directly inside a component: to find out what a window is
-- built from. Waits until there's a window's worth.
---@param interface_id integer
---@param static_id integer
function profile.dump_container(interface_id, static_id)
    local key = interface_id .. ":" .. static_id
    if not profile.enabled or dumped[key] then
        return
    end
    local container = ui.Interfaces:GetComponent(interface_id, static_id)
    if not container or not container.visibleGlobal or type(container.IterateDynamicComponents) ~= "function" then
        return
    end
    local lines = {}
    -- Showing parts only, three levels deep: a window's frame pieces sit inside its own layer.
    local function add(parent, depth)
        parent:IterateDynamicComponents(function (child)
            if child.visibleGlobal and #lines < 90 then
                local found, sprite_id = pcall(function () return child.spriteID end)
                local sprite = ""
                if found and type(sprite_id) == "number" then
                    local named, name = pcall(id.Sprite.FromID, sprite_id)
                    sprite = " sprite " .. (named and name or tostring(sprite_id))
                end
                local position = child.xyGlobal
                lines[#lines + 1] = string.format("%sinside %s:%s %d:%d type %s at %.0f,%.0f size %dx%d rgba %08X%s", prefix, key,
                    string.rep(" >", depth), child.categoryID, child.dynamicID, tostring(child.type),
                    position.x, position.y, child.width, child.height, child.rgba, sprite)
                if depth < 2 and type(child.IterateDynamicComponents) == "function" then
                    add(child, depth + 1)
                end
            end
            return false
        end)
    end
    -- Whatever goes wrong in here, it shouldn't be tried again every update.
    local worked, problem = pcall(add, container, 0)
    if not worked then
        dumped[key] = true
        print(prefix .. "couldn't list what's inside " .. key .. ": " .. tostring(problem))
        return
    end
    if #lines < 8 then
        return
    end
    dumped[key] = true
    for _, line in ipairs(lines) do
        print(line)
    end
end

local last_hovered = nil

-- A swapped part is under the mouse: which of its parents are too?
---@param key string
---@param component ui.Component
function profile.hovered(key, component)
    if not profile.traces_hover then
        return
    end
    profile.count("parts under the mouse", 1)
    if key == last_hovered then
        return
    end
    last_hovered = key
    local chain = {}
    local current = component
    for _ = 1, 16 do
        local found, parent = pcall(function () return current.parent end)
        if not found or parent == nil then
            break
        end
        current = parent
        chain[#chain + 1] = string.format("%d:%d%s", current.interfaceID, current.staticID, current.isMouseOver and "*" or "")
    end
    print_limited("hover", string.format("hover: %s, parents (* = also under the mouse): %s", key, table.concat(chain, " < ")))
end

---@class BenchmarkSubjects
---@field static { interface_id: integer, static_id: integer }? A showing static sprite component.
---@field dynamic { interface_id: integer, static_id: integer, category_id: integer, dynamic_id: integer }? A showing sprite component the game created.
---@field walked_interface_id integer? A big showing interface to walk.
---@field visit fun(component: ui.Component) What the plugin does for each component it walks.

-- Each test runs its own loop (a function call per iteration would be most of what's measured) and
-- returns how many calls it made, or nil if it has nothing to run on.
---@param subjects BenchmarkSubjects
---@return { name: string, run: fun(): integer? }[]
local function benchmark_tests(subjects)
    local iterations = profile.benchmark_iterations
    local function static_component()
        local ids = subjects.static
        return ids and ui.Interfaces:GetComponent(ids.interface_id, ids.static_id)
    end
    ---@param read fun(component: ui.Component)
    local function on_static(read)
        return function ()
            local component = static_component()
            if not component then
                return nil
            end
            read(component)
            return iterations
        end
    end
    ---@param visit fun(component: ui.Component)
    ---@param visible_only boolean
    local function walk(visit, visible_only)
        return function ()
            local interface_id = subjects.walked_interface_id
            if not interface_id then
                return nil
            end
            local total = 0
            repeat
                local looked_up = interface_walker.each_component(interface_id, visit, visible_only)
                total = total + looked_up
            until total >= iterations / 3 or looked_up == 0
            return total > 0 and total or nil
        end
    end
    local function nothing() end

    return {
        { name = "empty loop", run = function ()
            local sum = 0
            for i = 1, iterations do sum = sum + i end
            return iterations
        end },
        { name = "GetInterface", run = function ()
            local rounds = math.max(1, iterations // (interface_walker.last_interface_id + 1))
            for _ = 1, rounds do
                for interface_id = 0, interface_walker.last_interface_id do
                    local _ = ui.Interfaces:GetInterface(interface_id)
                end
            end
            return rounds * (interface_walker.last_interface_id + 1)
        end },
        { name = "GetComponent (static)", run = function ()
            local ids = subjects.static
            if not ids then
                return nil
            end
            for _ = 1, iterations do
                local _ = ui.Interfaces:GetComponent(ids.interface_id, ids.static_id)
            end
            return iterations
        end },
        { name = "GetComponent (dynamic)", run = function ()
            local ids = subjects.dynamic
            if not ids then
                return nil
            end
            for _ = 1, iterations do
                local _ = ui.Interfaces:GetComponent(ids.interface_id, ids.static_id, ids.category_id, ids.dynamic_id)
            end
            return iterations
        end },
        { name = "visibleGlobal", run = on_static(function (c) for _ = 1, iterations do local _ = c.visibleGlobal end end) },
        { name = "type", run = on_static(function (c) for _ = 1, iterations do local _ = c.type end end) },
        { name = "spriteID", run = on_static(function (c) for _ = 1, iterations do local _ = c.spriteID end end) },
        { name = "rgb", run = on_static(function (c) for _ = 1, iterations do local _ = c.rgb end end) },
        { name = "interfaceID", run = on_static(function (c) for _ = 1, iterations do local _ = c.interfaceID end end) },
        { name = "pcall read of type", run = on_static(function (c)
            local function read(component) return component.type end
            for _ = 1, iterations do pcall(read, c) end
        end) },
        { name = "component_key", run = on_static(function (c)
            for _ = 1, iterations do local _ = interface_walker.component_key(c) end
        end) },
        { name = "walk showing, no work (per lookup)", run = walk(nothing, true) },
        { name = "walk showing, plugin's work (per lookup)", run = walk(subjects.visit, true) },
        { name = "walk all, no work (per lookup)", run = walk(nothing, false) },
        { name = "walk all, plugin's work (per lookup)", run = walk(subjects.visit, false) },
    }
end

---@type { tests: { name: string, run: fun(): integer? }[], index: integer, pending: { name: string, calls: integer }? }?
local benchmark = nil
local benchmark_done = false

---@param name string
---@param calls integer?
---@param elapsed number
local function print_benchmark_result(name, calls, elapsed)
    if calls then
        benchmark_summary[#benchmark_summary + 1] = string.format("%s %.0f", name, elapsed / calls * 1e9)
        print(string.format("%sbenchmark: %s: %.0f ns (%d calls in %.1f ms)", prefix, name, elapsed / calls * 1e9, calls, elapsed * 1000))
    else
        print(string.format("%sbenchmark: %s: nothing to run it on", prefix, name))
    end
end

-- Runs one test a frame. Without a clock, a test's time is how much longer than usual its frame
-- took, which the next frame tells.
---@param frame_delta number
---@param subjects fun(): BenchmarkSubjects
local function continue_benchmark(frame_delta, subjects)
    if benchmark == nil then
        benchmark = { tests = benchmark_tests(subjects()), index = 1 }
        benchmark_frame_seconds = typical_frame_seconds
        print(string.format("%sbenchmark: starting (%s), usual frame %.1f ms", prefix,
            clock and "timed with the clock" or "no clock: timed by frame length", typical_frame_seconds * 1000))
    end
    if benchmark.pending then
        print_benchmark_result(benchmark.pending.name, benchmark.pending.calls, math.max(0, frame_delta - typical_frame_seconds))
        benchmark.pending = nil
    end
    local test = benchmark.tests[benchmark.index]
    if test == nil then
        benchmark_done = true
        benchmark = nil
        print(prefix .. "benchmark: done")
        return
    end
    benchmark.index = benchmark.index + 1
    local started = clock and clock()
    local calls = test.run()
    if started then
        print_benchmark_result(test.name, calls, clock() - started)
    elseif calls then
        benchmark.pending = { name = test.name, calls = calls }
    else
        print_benchmark_result(test.name, nil, 0)
    end
end

-- Called for every frame, before the plugin's own work.
---@param event DrawEventPayload?
---@param update_number integer
---@param subjects fun(): BenchmarkSubjects
function profile.frame(event, update_number, subjects)
    if not profile.enabled then
        return
    end
    current_update = update_number
    local found, delta = pcall(function () return event.timeDeltaSecs end)
    delta = found and tonumber(delta) or 0
    local benchmarking = not benchmark_done and update_number >= profile.benchmark_at_update
    if benchmarking then
        continue_benchmark(delta, subjects)
        return
    end
    -- The component plugins' windows are created in: listed once a window shows in it.
    if update_number % 50 == 0 then
        local found, main_interface_id = pcall(function () return id.Interface.TOPLEVEL_V2 end)
        if found and main_interface_id then
            profile.dump_container(main_interface_id, 61)
        end
    end
    frames = frames + 1
    frame_seconds = frame_seconds + delta
    if update_number - reported_at >= report_interval then
        report()
    end
end

function profile.enable()
    profile.enabled = true
    for event_name, name in pairs(profile.listens_to_events and listened_events or {}) do
        local event = Event[event_name]
        if event then
            pcall(event.Subscribe, subscription_name, function ()
                last_event_update[name] = current_update
                profile.count(name .. "s", 1)
            end)
        end
    end
    print(string.format("%sprofile: on, clock %s", prefix, clock and "available" or "not available"))
end

function profile.disable()
    if not profile.enabled then
        return
    end
    profile.enabled = false
    -- Only what was subscribed to: unsubscribing from an event that wasn't may be what crashed
    -- the client when the plugin was turned off.
    for event_name in pairs(profile.listens_to_events and listened_events or {}) do
        local event = Event[event_name]
        if event then
            pcall(event.Unsubscribe, subscription_name)
        end
    end
end

return profile
