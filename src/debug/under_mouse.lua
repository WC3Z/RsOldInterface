-- DEBUG: prints what's under the mouse, to find out what one thing on screen is made of. Point at
-- it and press Control and Shift together: every showing component whose box holds the mouse is
-- printed, smallest first, with its type, size, colour, sprite (and the sprite the game had, for
-- one the plugin swapped) or text. (It used to print whenever the mouse rested, which during play
-- was all the time.)
local interface_walker = require("src/game/interface_walker")
local component_fields = require("src/game/component_fields")
local game_ids = require("src/game/game_ids")
local component_types = require("src/debug/type_names")

local under_mouse = {}

local prefix = "[Old Interface] under the mouse: "
local most_lines = 14

-- Whether the keys were held at the last update, to print once each time they're pressed.
local were_keys_held = false

---@param interface_id integer
---@return string
local function interface_name(interface_id)
    local found, name = pcall(id.Interface.FromID, interface_id)
    return found and name or tostring(interface_id)
end

---@param sprite_id integer?
---@return string
local function sprite_text(sprite_id)
    if sprite_id == nil then
        return "none"
    end
    if sprite_id == component_fields.runtime_image_id then
        return "a runtime image"
    end
    return game_ids.sprite_name(sprite_id) or tostring(sprite_id)
end

---@param component ui.Component
---@param parts table<string, SwappedPart>
---@return string
local function describe(component, parts)
    local component_type = component.type
    local key = interface_walker.component_key(component)
    local text = string.format("%s %s %s size %.0fx%.0f%s", interface_name(component.interfaceID), key, component_types.name(component_type),
        component.width, component.height, component.visibleGlobal and "" or " (reports hidden)")
    if component_type == ui.ComponentType.RECTANGLE then
        return text .. string.format(" rectangle rgba %08X%s", component.rgba, component.fill and " filled" or " outline")
    end
    if component_type == ui.ComponentType.CANVAS then
        -- What's drawn on a canvas isn't components: only how many shapes there are can be read.
        return text .. string.format(" canvas with %s drawn shapes", tostring(component.numElements))
    end
    if component_type == ui.ComponentType.LABEL then
        local content = tostring(component.content):sub(1, 30)
        return text .. string.format(" text rgb %06X \"%s\"", component.rgb, content)
    end
    local fields = component_fields.sprite_fields[component_type]
    if fields then
        local sprites = {}
        for _, field in ipairs(fields) do
            local holder = component_fields.holder(component, field)
            local sprite_id = holder and holder.spriteID
            if sprite_id ~= nil then
                local part = parts[key .. ":" .. field]
                local swapped = part and (" (swapped, the game's: " .. sprite_text(part.game_sprite_id) .. ")") or ""
                local field_name = field ~= component_fields.on_component and field .. "=" or ""
                sprites[#sprites + 1] = field_name .. sprite_text(sprite_id) .. swapped
            end
        end
        return text .. " sprite " .. table.concat(sprites, " ") .. string.format(" rgba %08X", component.rgba or 0)
    end
    return text
end

---@param component ui.Component
---@param x number
---@param y number
---@return number? # The component's area, if it holds the point.
local function area_holding(component, x, y)
    local width, height = component.width, component.height
    if width <= 0 or height <= 0 then
        return nil
    end
    local position = component.xyGlobal
    if x < position.x or y < position.y or x >= position.x + width or y >= position.y + height then
        return nil
    end
    return width * height
end

---@param parts table<string, SwappedPart>
---@param interface_ids integer[] The interfaces that are showing.
---@param x number
---@param y number
local function print_what_is_at(parts, interface_ids, x, y)
    local found = {}
    for _, interface_id in ipairs(interface_ids) do
        interface_walker.each_component(interface_id, function (component)
            local measured, area = pcall(area_holding, component, x, y)
            if measured and area then
                local described, text = pcall(describe, component, parts)
                found[#found + 1] = { area = area, text = described and text or ("(couldn't be described: " .. tostring(text) .. ")") }
            end
        end, true)
    end
    table.sort(found, function (one, other) return one.area < other.area end)
    print(string.format("%sat %d,%d, %d things, smallest first:", prefix, x, y, #found))
    for index = 1, math.min(#found, most_lines) do
        print(prefix .. found[index].text)
    end
end

---@return boolean
local function are_keys_held()
    return Keyboard.IsControlDown() and Keyboard.IsShiftDown()
end

-- Called after every update. Prints what's under the mouse when Control and Shift are pressed.
---@param parts table<string, SwappedPart>
---@param interface_ids integer[] The interfaces that are showing.
function under_mouse.check(parts, interface_ids)
    local found, keys_held = pcall(are_keys_held)
    keys_held = found and keys_held == true
    local was_pressed = keys_held and not were_keys_held
    were_keys_held = keys_held
    if not was_pressed then
        return
    end
    local found_mouse, x, y = pcall(function ()
        if not Mouse.IsAvailable() then
            return nil, nil
        end
        return Mouse.GetX(), Mouse.GetY()
    end)
    if found_mouse and x ~= nil and y ~= nil then
        print_what_is_at(parts, interface_ids, x, y)
    end
end

return under_mouse
