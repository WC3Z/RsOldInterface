-- DEBUG: measures what the plugin's work costs, and what it finds late, to decide how to make it
-- faster. Prints:
-- - every 200 updates, how much of each kind of work there was (the game's Lua has no clock to
--   time it with);
-- - once, with profile.runs_benchmark, what each kind of game call costs (the game stutters for a
--   few seconds);
-- - each interface that loads or shows;
-- - parts only found by the slow regular walk while showing: those were drawn in the new look for
--   a while;
-- - frames that took much longer than the ones around them, with what the plugin did in them;
-- - with profile.measures_cost, what each step of the plugin's work costs (see the cost section).
local interface_walker = require("src/game/interface_walker")

local profile = {}

profile.enabled = false
---@type "generational"|"steps"|nil
profile.garbage_mode = nil
profile.garbage_step_kb = 100
-- The benchmark makes the game stutter for a few seconds, so it's only run when asked for.
profile.runs_benchmark = false
profile.benchmark_iterations = 100000
profile.benchmark_at_update = 300
local prefix = "[Old Interface] "
local report_interval = 200
-- The component of the main interface that plugins' windows are created in: what's inside it is
-- listed once a window shows there (see profile.dump_container).
local plugin_windows_static_id = 61
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

---@type table<integer, integer>
local opened_at = {}
local lines_left = { opened = 80, late = 30, long_frame = 200 }
-- What was counted since the last frame started: the plugin's work in that frame.
---@type table<string, number>
local frame_counts = {}

-- Lua's memory when the last frame started, to tell whether a long frame was one where Lua freed
-- a lot at once (a garbage collection), and how many long frames there were since the last report.
local memory_kb_at_last_frame = 0
local long_frames = 0
local long_frames_freeing_memory = 0
local freed_kb_that_counts = 2000

---@return number # Lua's memory in KB, or 0 if it can't be told.
local function memory_kb()
    local found, kb = pcall(collectgarbage, "count")
    return found and kb or 0
end

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
        frame_counts[name] = (frame_counts[name] or 0) + amount
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
    print(string.format("%sprofile at update %d: %.0f fps, Lua memory %.0f KB, %d long frames (%d while Lua freed memory); per update: %s",
        prefix, current_update, frame_seconds > 0 and frames / frame_seconds or 0, memory_kb(), long_frames, long_frames_freeing_memory,
        per_update(counts, updates, "%s %.1f")))
    long_frames = 0
    long_frames_freeing_memory = 0
    counts = {}
    frames = 0
    frame_seconds = 0
    reports = reports + 1
    if #benchmark_summary > 0 and reports % 3 == 0 then
        print(string.format("%sbenchmark results, ns per call (usual frame was %.1f ms): %s", prefix, benchmark_frame_seconds * 1000, table.concat(benchmark_summary, "; ")))
    end
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
    print_limited("opened", string.format("opened: %s %s at update %d (%s)",
        interface_name(interface_id), reason, current_update, found_by))
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

-- LONG FRAMES. A frame that took much longer than the ones around it is printed with what the
-- plugin did in it. Ordinary numbers there mean the hitch was the game's own (like loading the
-- map while running); a big number says which of the plugin's walks it was.
local long_frame_seconds = 0.03
local long_frame_factor = 2.5
local recent_frame_seconds = 0

---@param delta number How long the frame before this one took.
local function report_long_frame(delta)
    local is_long = recent_frame_seconds > 0 and delta > long_frame_seconds and delta > recent_frame_seconds * long_frame_factor
    local memory_now = memory_kb()
    local freed_kb = memory_kb_at_last_frame - memory_now
    memory_kb_at_last_frame = memory_now
    if is_long then
        long_frames = long_frames + 1
        if freed_kb >= freed_kb_that_counts then
            long_frames_freeing_memory = long_frames_freeing_memory + 1
        end
        local names = {}
        for name, amount in pairs(frame_counts) do
            -- The totals ("... in all") are the same every frame.
            if amount > 0 and not name:find(" in all$") then
                names[#names + 1] = name
            end
        end
        table.sort(names)
        local texts = {}
        for _, name in ipairs(names) do
            texts[#texts + 1] = string.format("%s %d", name, frame_counts[name])
        end
        print_limited("long_frame", string.format("long frame: %.0f ms at update %d (usual %.0f ms), Lua memory %+.0f KB in it; the plugin's work in it: %s",
            delta * 1000, current_update, recent_frame_seconds * 1000, -freed_kb, #texts > 0 and table.concat(texts, ", ") or "none"))
    else
        -- Long frames are left out of what's usual.
        recent_frame_seconds = recent_frame_seconds == 0 and delta or recent_frame_seconds * 0.95 + delta * 0.05
    end
    frame_counts = {}
end

-- COST. The game's Lua has no clock, so a step's cost is measured by leaving it out for a couple
-- of seconds and seeing how much shorter the frames get. Phases take turns: everything on, one
-- step left out, everything on, the next step left out, and so on, each step compared with the
-- phases before and after it. A round takes about a minute and the numbers are noisy, so the
-- averages over all rounds are printed after each: let it run for a few minutes in one place.
--
-- - While a step is left out, the game's own look can show in places for a moment.
-- - With the frame rate capped (or limited by the graphics card), the plugin's work fits in the
--   time the game would have waited, and everything measures as costing nothing: that itself says
--   the plugin isn't what limits the frame rate there.
profile.measures_cost = false
profile.cost_phase_updates = 100
profile.cost_starts_at_update = 300
local all_steps = "all of it"
-- The names the plugin's code asks profile.skips about.
local cost_steps = {
    all_steps,
    "finding loaded and shown interfaces",
    "fresh and warm walks",
    "the pass",
    "the background walk",
    "every-update checks",
    "in-turn checks",
    "container walks",
    "colour checks",
    "hot checks",
}

---@class CostPhase
---@field step string? The step left out, or nil with everything on.
---@field started_at integer
---@field frames integer
---@field seconds number

---@type { index: integer, phase: CostPhase?, baseline_seconds: number?, pending: { step: string, frame_seconds: number, frames_per_update: number, before: number }?, sums: table<string, number>, rounds: integer, baseline_fps: number, without_fps: number }
local cost = { index = 0, sums = {}, rounds = 0, baseline_fps = 0, without_fps = 0 }

-- Whether a step of the plugin's work is left out right now, to measure what it costs.
---@param step string One of cost_steps.
---@return boolean
function profile.skips(step)
    local phase = cost.phase
    return phase ~= nil and phase.step ~= nil and (phase.step == step or phase.step == all_steps)
end

local function print_costs()
    local texts = {}
    for _, step in ipairs(cost_steps) do
        texts[#texts + 1] = string.format("%s %.2f", step, (cost.sums[step] or 0) / cost.rounds)
    end
    print(string.format("%scost after %d rounds, ms per update: %s (last round: %.0f fps with the plugin's work, %.0f without)",
        prefix, cost.rounds, table.concat(texts, "; "), cost.baseline_fps, cost.without_fps))
end

-- Odd phases have everything on, even ones leave a step out.
---@param index integer
---@return string?
local function step_of_phase(index)
    return index % 2 == 0 and cost_steps[index // 2] or nil
end

---@param phase CostPhase
local function finish_cost_phase(phase)
    if phase.frames == 0 then
        return
    end
    local frame_seconds_in_phase = phase.seconds / phase.frames
    if phase.step then
        cost.pending = {
            step = phase.step,
            frame_seconds = frame_seconds_in_phase,
            frames_per_update = phase.frames / math.max(1, current_update - phase.started_at),
            before = cost.baseline_seconds or frame_seconds_in_phase,
        }
        if phase.step == all_steps then
            cost.without_fps = 1 / frame_seconds_in_phase
        end
        return
    end
    local pending = cost.pending
    if pending then
        local with_everything = (pending.before + frame_seconds_in_phase) / 2
        local seconds_per_update = (with_everything - pending.frame_seconds) * pending.frames_per_update
        cost.sums[pending.step] = (cost.sums[pending.step] or 0) + seconds_per_update * 1000
        cost.pending = nil
        if pending.step == cost_steps[#cost_steps] then
            cost.rounds = cost.rounds + 1
            print_costs()
        end
    end
    cost.baseline_seconds = frame_seconds_in_phase
    cost.baseline_fps = 1 / frame_seconds_in_phase
end

---@param delta number How long the frame before this one took.
local function continue_cost_measuring(delta)
    if current_update < profile.cost_starts_at_update then
        return
    end
    local phase = cost.phase
    if phase and current_update - phase.started_at < profile.cost_phase_updates then
        phase.frames = phase.frames + 1
        phase.seconds = phase.seconds + delta
        return
    end
    if phase then
        finish_cost_phase(phase)
    end
    -- After the last step's phase comes one more with everything on, which is also the next
    -- round's first.
    cost.index = cost.index >= #cost_steps * 2 + 1 and 2 or cost.index + 1
    cost.phase = { step = step_of_phase(cost.index), started_at = current_update, frames = 0, seconds = 0 }
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
    report_long_frame(delta)
    if profile.measures_cost then
        continue_cost_measuring(delta)
    end
    -- The benchmark's stutter would spoil the cost's numbers.
    local benchmarking = profile.runs_benchmark and not profile.measures_cost and not benchmark_done and update_number >= profile.benchmark_at_update
    if benchmarking then
        continue_benchmark(delta, subjects)
        return
    end
    if update_number % 50 == 0 then
        local found, main_interface_id = pcall(function () return id.Interface.TOPLEVEL_V2 end)
        if found and main_interface_id then
            profile.dump_container(main_interface_id, plugin_windows_static_id)
        end
    end
    frames = frames + 1
    frame_seconds = frame_seconds + delta
    if update_number - reported_at >= report_interval then
        report()
    end
end

-- GARBAGE COLLECTION. Every component the plugin looks at is a new Lua object that's thrown away
-- again, tens of kilobytes an update, which Lua frees in bursts. To try whether freeing it another
-- way gives fewer long frames:
--   "generational"   Lua 5.4's mode for lots of short-lived objects
--   "steps"          a small step of collecting after every update, so there's never much to free
---@param mode "generational"|"steps"|nil
function profile.collect_garbage_as(mode)
    profile.garbage_mode = mode
    if mode == "generational" then
        local worked, problem = pcall(collectgarbage, "generational")
        print(string.format("%sgarbage collection: generational %s", prefix, worked and "on" or "isn't available: " .. tostring(problem)))
    elseif mode == "steps" then
        print(prefix .. "garbage collection: a step after every update")
    end
end

-- Called once after each update's work.
function profile.after_update()
    if profile.enabled and profile.garbage_mode == "steps" then
        pcall(collectgarbage, "step", profile.garbage_step_kb)
    end
end

function profile.enable()
    profile.enabled = true
    print(string.format("%sprofile: on, clock %s", prefix, clock and "available" or "not available"))
end

function profile.disable()
    profile.enabled = false
    profile.measures_cost = false
    cost = { index = 0, sums = {}, rounds = 0, baseline_fps = 0, without_fps = 0 }
end

return profile
