-- DEBUG: prints where the game draws the pieces of something, to find out how it's laid out:
-- each showing swapped sprite whose name matches a pattern, with its place on screen and its size,
-- everything else showing in the same static components, and the texts drawn over the same strip
-- of the screen (like a window's title over its banner).
-- Each is printed once per place and size, so a window that's moved or resized is printed again.
local interface_walker = require("src/game/interface_walker")
local component_fields = require("src/game/component_fields")
local game_ids = require("src/game/game_ids")

local layout = {}

local prefix = "[Old Interface] layout: "
local lines_left = 200
---@type table<string, boolean>
local printed = {}

---@param text string
local function print_once(text)
    if not printed[text] and lines_left > 0 then
        printed[text] = true
        lines_left = lines_left - 1
        print(prefix .. text)
    end
end

---@param component ui.Component
---@return string
local function place_of(component)
    local position = component.xyGlobal
    local parent = component.parentStatic
    return string.format("at %.0f,%.0f size %dx%d (x %d in its parent %s)", position.x, position.y, component.width, component.height,
        component.x, parent and tostring(parent.staticID) or "none")
end

-- Prints the showing swapped sprites whose game sprite's name matches the pattern, and the texts
-- over the strip they're in.
---@param parts table<string, SwappedPart>
---@param pattern string
function layout.report(parts, pattern)
    -- The strip of the screen the pieces are in, for each interface that has any.
    ---@type table<integer, { top: number, bottom: number, static_ids: table<integer, boolean> }>
    local strips = {}
    for key, part in pairs(parts) do
        local sprite_name = game_ids.sprite_name(part.game_sprite_id)
        local component = sprite_name and sprite_name:find(pattern) and component_fields.find(part)
        if component and component.visibleGlobal then
            local described, place = pcall(place_of, component)
            if described then
                print_once(string.format("%s %s %s", sprite_name, key, place))
                local top = component.xyGlobal.y
                local strip = strips[part.interface_id] or { top = top, bottom = top + component.height, static_ids = {} }
                strip.static_ids[part.static_id] = true
                strip.top = math.min(strip.top, top)
                strip.bottom = math.max(strip.bottom, top + component.height)
                strips[part.interface_id] = strip
            end
        end
    end
    for interface_id, strip in pairs(strips) do
        interface_walker.each_component(interface_id, function (component)
            local is_beside_a_piece = strip.static_ids[component.staticID]
            if component.type ~= ui.ComponentType.LABEL and not is_beside_a_piece then
                return
            end
            local described, place = pcall(place_of, component)
            if not described then
                return
            end
            local top = component.xyGlobal.y
            local overlaps_strip = top < strip.bottom and top + component.height > strip.top
            if is_beside_a_piece or overlaps_strip then
                local text = component.type == ui.ComponentType.LABEL
                    and string.format(" \"%s\" font %s", tostring(component.content), tostring(component.font)) or ""
                print_once(string.format("%s%s %s %s", tostring(component.type), text, interface_walker.component_key(component), place))
            end
        end, true)
    end
end

return layout
