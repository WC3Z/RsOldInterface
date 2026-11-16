-- DEBUG: prints what the swapping does, for tracking down delays and sprites that aren't swapped.
-- Each kind of line is only printed a limited number of times.
local activity_log = {}

activity_log.enabled = false

local prefix = "[Old Interface] "
local lines_left = { activity = 120, unswapped = 80, interactive = 60, rectangle = 40, colour = 150 }
---@type table<string, boolean>
local unswapped_seen = {}

-- Sprites that look like interface parts rather than icons.
local interface_part_words = { "BTN", "BUTTON", "CONTAINER", "DROPDOWN", "FRAME", "TAB", "INPUT", "SLIDER", "SCROLL", "PANEL", "TILE", "CORNER", "BACKING", "HEADER", "BOX", "BANNER", "LINE", "BAR", "EDGE" }

---@param interface_id integer
local function interface_name(interface_id)
    local found, name = pcall(id.Interface.FromID, interface_id)
    return found and name or tostring(interface_id)
end

---@param kind string
---@param text string
local function print_limited(kind, text)
    if lines_left[kind] <= 0 then
        return
    end
    lines_left[kind] = lines_left[kind] - 1
    print(prefix .. text)
end

---@param update_number integer
---@param interface_id integer
---@param reason string
function activity_log.watching_closely(update_number, interface_id, reason)
    if activity_log.enabled then
        print_limited("activity", string.format("update %d: watching %s closely (%s)", update_number, interface_name(interface_id), reason))
    end
end

---@param update_number integer
---@param interface_id integer
function activity_log.first_swap(update_number, interface_id)
    if activity_log.enabled then
        print_limited("activity", string.format("update %d: swapping in %s", update_number, interface_name(interface_id)))
    end
end

-- A sprite that's showing but has no old image, and the size it's drawn at. The field is the part
-- of an interactive component it's in, or empty for a sprite component.
---@param interface_id integer
---@param sprite_id integer
---@param field string
---@param width integer
---@param height integer
function activity_log.unswapped(interface_id, sprite_id, field, width, height)
    if not activity_log.enabled then
        return
    end
    local found, sprite_name = pcall(id.Sprite.FromID, sprite_id)
    if not found or not sprite_name or unswapped_seen[sprite_name] then
        return
    end
    unswapped_seen[sprite_name] = true
    for _, word in ipairs(interface_part_words) do
        if sprite_name:find(word) then
            local part = field ~= "" and (" (" .. field .. ")") or ""
            print_limited("unswapped", string.format("not swapped: %s (%d)%s %dx%d in %s", sprite_name, sprite_id, part, width, height, interface_name(interface_id)))
            return
        end
    end
end

-- Every so many updates, what the swapping costs: how many parts and rectangles it keeps track
-- of (each is looked up again every frame), how many it had to swap again since the last line,
-- how often that looked like a rebuild, and which interfaces are watched closely.
---@param update_number integer
---@param counts { frames: integer, checks: integer, swapped_parts: integer, visible_parts: integer, recoloured: integer, reswapped: integer, rebuilt: table<integer, integer> }
---@param closely_watched table<integer, any>
function activity_log.stats(update_number, counts, closely_watched)
    if not activity_log.enabled then
        return
    end
    local watched = {}
    for interface_id in pairs(closely_watched) do
        watched[#watched + 1] = interface_name(interface_id)
    end
    table.sort(watched)
    local rebuilt = {}
    for interface_id, times in pairs(counts.rebuilt) do
        rebuilt[#rebuilt + 1] = interface_name(interface_id) .. " x" .. times
    end
    table.sort(rebuilt)
    print(string.format("%sstats at update %d: %d frames (%d checked), %d parts (%d checked every update), %d rectangles, %d swapped again, rebuilt: %s, watching closely: %s",
        prefix, update_number, counts.frames, counts.checks, counts.swapped_parts, counts.visible_parts, counts.recoloured, counts.reswapped,
        table.concat(rebuilt, ", "), table.concat(watched, ", ")))
end

-- The interfaces whose swaps are traced one by one (see activity_log.trace), by name.
activity_log.traced_interfaces = { ESCAPE_MENU = true }
local trace_lines_left = 300

-- What happens to one swapped part in a traced interface: swapped by the walk, swapped again
-- before a frame, or gone.
---@param update_number integer
---@param interface_id integer
---@param sprite_id integer
---@param text string
function activity_log.trace(update_number, interface_id, sprite_id, text)
    if not activity_log.enabled or trace_lines_left <= 0 or not activity_log.traced_interfaces[interface_name(interface_id)] then
        return
    end
    local found, sprite_name = pcall(id.Sprite.FromID, sprite_id)
    sprite_name = found and sprite_name or tostring(sprite_id)
    trace_lines_left = trace_lines_left - 1
    print(string.format("%supdate %d: %s %s", prefix, update_number, sprite_name, text))
end

---@type table<string, boolean>
local frame_piece_seen = {}

-- Where a big or plugin window's frame piece sits, once per piece: to tell the pieces with the same image
-- apart, like the short side piece between the title and the tabs.
---@param component ui.Component
---@param sprite_id integer
function activity_log.frame_piece(component, sprite_id)
    if not activity_log.enabled then
        return
    end
    local found, sprite_name = pcall(id.Sprite.FromID, sprite_id)
    if not found or not sprite_name or not (sprite_name:find("^RS3_PARENT_FRAME_") or sprite_name:find("MODAL_WINDOW_1_")) then
        return
    end
    local key = string.format("%d:%d:%d:%d", component.interfaceID, component.staticID, component.categoryID, component.dynamicID)
    if frame_piece_seen[key] then
        return
    end
    frame_piece_seen[key] = true
    local parent = component.parent
    print(string.format("%sframe %s %s at %d,%d size %dx%d, parent %s %dx%d", prefix, sprite_name, key,
        component.x, component.y, component.width, component.height,
        parent and tostring(parent.staticID) or "-", parent and parent.width or 0, parent and parent.height or 0))
end

---@type table<string, boolean>
local colour_seen = {}

-- A text's colour and the old one it gets (or none), with a bit of the text to know it by. Only
-- printed once per colour, kind of text and window.
---@param component ui.Component
---@param field string
---@param rgb integer
---@param old_rgb integer?
function activity_log.colour(component, field, rgb, old_rgb)
    if not activity_log.enabled or component.type == ui.ComponentType.RECTANGLE then
        return
    end
    local signature = string.format("0x%06X %s%s", rgb, tostring(component.type), field ~= "" and (" " .. field) or "")
    local seen_key = signature .. component.interfaceID
    if colour_seen[seen_key] then
        return
    end
    colour_seen[seen_key] = true
    local found, text = pcall(function ()
        return field == "" and component.content or component[field].content
    end)
    local sample = found and type(text) == "string" and text:sub(1, 30) or "?"
    local target = old_rgb and string.format("0x%06X", old_rgb) or "no old colour"
    print_limited("colour", string.format("text %s -> %s \"%s\" in %s", signature, target, sample, interface_name(component.interfaceID)))
end

---@type table<string, boolean>
local interactive_seen = {}
---@type table<string, boolean>
local rectangle_seen = {}

-- A plain coloured rectangle that's showing, like the background of a card in a list: its colour,
-- whether it's filled, and its size. Rectangles that look the same are only printed once.
---@param component ui.Rectangle
function activity_log.rectangle(component)
    if not activity_log.enabled then
        return
    end
    local signature = string.format("rectangle 0x%08X%s %dx%d", component.rgba, component.fill and " filled" or "", component.width, component.height)
    if rectangle_seen[signature] then
        return
    end
    rectangle_seen[signature] = true
    print_limited("rectangle", signature .. " in " .. interface_name(component.interfaceID))
end

-- An interactive component (button, dropdown and the like) that's showing: its type, stylesheet,
-- and the sprite ID of each of its parts, to see where its look comes from. Components that look
-- the same are only printed once.
---@param component ui.Component
---@param part_sprite_ids table<string, integer|string>
function activity_log.interactive(component, part_sprite_ids)
    if not activity_log.enabled then
        return
    end
    local parts = {}
    for field, sprite_id in pairs(part_sprite_ids) do
        parts[#parts + 1] = field .. "=" .. tostring(sprite_id)
    end
    table.sort(parts)
    local signature = string.format("%s, stylesheet %s, %s", tostring(component.type), tostring(component.stylesheetID), table.concat(parts, " "))
    if interactive_seen[signature] then
        return
    end
    interactive_seen[signature] = true
    print_limited("interactive", signature .. " in " .. interface_name(component.interfaceID))
end

return activity_log
