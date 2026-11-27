-- DEBUG: lists what's showing that the plugin doesn't restyle, to find out what a window is made
-- of: plain rectangles and text whose colour isn't one of the skin's, sprites the plugin has no
-- image for (or that draw another plugin's image), and the sprites it did swap, by the game's name. Goes through every interface that's showing.
-- Each kind is printed once for each interface it's in, with how many there are and where, so
-- opening a window prints just what's new in it. What's showing when the listing starts (the HUD,
-- mostly) is only noted, not printed: hundreds of lines nobody asked for, which used to fill the
-- console before any window was opened.
local interface_walker = require("src/game/interface_walker")
local skin_palette = require("src/game/skin_palette")
local component_fields = require("src/game/component_fields")
local sprite_groups = require("src/game/sprite_groups")
local game_ids = require("src/game/game_ids")
local component_types = require("src/debug/type_names")

local unstyled = {}

local prefix = "[Old Interface] unstyled: "
local lines_left = 400
-- What was printed so far: each interface's name, and each kind in it.
---@type table<string, boolean>
local printed = {}
-- Whether what was showing at the start has been noted.
local has_noted_start = false

---@param interface_id integer
---@return string
local function interface_name(interface_id)
    local found, name = pcall(id.Interface.FromID, interface_id)
    return found and name or tostring(interface_id)
end

---@param sprite_name string
---@return string # Whether the plugin would swap the sprite if it had an image for it.
local function sprite_note(sprite_name)
    return sprite_groups.group_of(sprite_name) and " (in a group, no image)" or ""
end

---@param component ui.Component
---@return string? # What kind of unstyled thing the component is, or nil if it's styled or not of interest.
local function kind_of(component)
    if component.type == ui.ComponentType.RECTANGLE then
        local rgb = component.rgb
        if skin_palette.old_colour(rgb) ~= nil then
            return nil
        end
        return string.format("rectangle rgba %08X%s", component.rgba, component.fill and " filled" or " outline")
    end
    if component.type == ui.ComponentType.LABEL then
        if skin_palette.old_text_colour(component.rgb) ~= nil then
            return nil
        end
        return string.format("text rgb %06X font %s", component.rgb, tostring(component.font))
    end
    local fields = component_fields.sprite_fields[component.type]
    if fields == nil then
        return nil
    end
    local kinds = {}
    for _, field in ipairs(fields) do
        local holder = component_fields.holder(component, field)
        local sprite_id = holder and holder.spriteID
        if sprite_id ~= nil then
            local sprite_name = game_ids.sprite_name(sprite_id)
            local name = sprite_id == component_fields.runtime_image_id and "a runtime image"
                or sprite_name and sprite_name .. sprite_note(sprite_name) or tostring(sprite_id)
            kinds[#kinds + 1] = (field ~= component_fields.on_component and field .. "=" or "") .. name
        end
    end
    if #kinds == 0 then
        return nil
    end
    return string.format("%s %s rgba %08X", component_types.name(component.type), table.concat(kinds, " "), component.rgba or 0)
end

---@param line string
local function print_limited(line)
    if lines_left > 0 then
        lines_left = lines_left - 1
        print(prefix .. line)
    end
end

-- Prints the kinds of unstyled things showing now that weren't printed before.
---@param parts table<string, SwappedPart> What the plugin has swapped, which is left out.
---@param interface_ids integer[] The interfaces that are showing.
function unstyled.report(parts, interface_ids)
    local is_start = not has_noted_start
    has_noted_start = true
    local noted_kinds = 0
    table.sort(interface_ids)
    for _, interface_id in ipairs(interface_ids) do
        local name = interface_name(interface_id)
        local found = {}
        local order = {}
        interface_walker.each_component(interface_id, function (component)
            local key = interface_walker.component_key(component)
            -- What the plugin swapped is listed too, by the game's sprite: an old image can look
            -- as new as the game's (gold edges were around well before the overhaul).
            local swapped_from = {}
            for _, field in ipairs(component_fields.sprite_fields[component.type] or {}) do
                local part = parts[key .. ":" .. field]
                if part then
                    swapped_from[#swapped_from + 1] = game_ids.sprite_name(part.game_sprite_id) or tostring(part.game_sprite_id)
                end
            end
            local described, kind
            if #swapped_from > 0 then
                described, kind = true, "swapped " .. table.concat(swapped_from, " ")
            else
                described, kind = pcall(kind_of, component)
            end
            if described and kind and not printed[name .. " " .. kind] then
                local entry = found[kind]
                if entry == nil then
                    entry = { count = 0, static_id = component.staticID, width = component.width or 0, height = component.height or 0 }
                    found[kind] = entry
                    order[#order + 1] = kind
                end
                entry.count = entry.count + 1
            end
        end, true)
        if #order > 0 and not printed[name] and not is_start then
            print_limited("--- " .. name .. " (" .. interface_id .. ")")
        end
        if #order > 0 then
            printed[name] = true
        end
        table.sort(order)
        for _, kind in ipairs(order) do
            printed[name .. " " .. kind] = true
            noted_kinds = noted_kinds + 1
            local entry = found[kind]
            if not is_start then
                print_limited(string.format("%s: %s x%d, like %dx%d at %d", name, kind, entry.count, entry.width, entry.height, entry.static_id))
            end
        end
    end
    if is_start then
        print_limited(string.format("noted the %d kinds already showing in %d windows; open a window to list what's in it", noted_kinds, #interface_ids))
    end
end

return unstyled
