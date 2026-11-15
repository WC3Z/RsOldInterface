-- DEBUG: prints what the swapping does, for tracking down delays and sprites that aren't swapped.
-- Each kind of line is only printed a limited number of times.
local activity_log = {}

activity_log.enabled = false

local prefix = "[Old Interface] "
local lines_left = { activity = 120, unswapped = 80, interactive = 60, rectangle = 40 }
---@type table<string, boolean>
local unswapped_seen = {}

-- Sprites that look like interface parts rather than icons.
local interface_part_words = { "BTN", "BUTTON", "CONTAINER", "DROPDOWN", "FRAME", "TAB", "INPUT", "SLIDER", "SCROLL", "PANEL", "TILE", "CORNER", "BACKING", "HEADER", "BOX" }

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

-- A sprite that's showing but has no old image. The field is the part of an interactive component
-- it's in, or empty for a sprite component.
---@param interface_id integer
---@param sprite_id integer
---@param field string
function activity_log.unswapped(interface_id, sprite_id, field)
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
            print_limited("unswapped", string.format("not swapped: %s (%d)%s in %s", sprite_name, sprite_id, part, interface_name(interface_id)))
            return
        end
    end
end

-- Every so many updates, what the swapping costs: how many parts and rectangles it keeps track
-- of (each is looked up again every frame), how many it had to swap again since the last line,
-- how often that looked like a rebuild, and which interfaces are watched closely.
---@param update_number integer
---@param counts { frames: integer, swapped_parts: integer, visible_parts: integer, recoloured: integer, reswapped: integer, rebuilt: table<integer, integer> }
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
    print(string.format("%sstats at update %d: %d frames, %d parts (%d checked every frame), %d rectangles, %d swapped again, rebuilt: %s, watching closely: %s",
        prefix, update_number, counts.frames, counts.swapped_parts, counts.visible_parts, counts.recoloured, counts.reswapped,
        table.concat(rebuilt, ", "), table.concat(watched, ", ")))
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
