-- DEBUG: lists what's showing that the plugin doesn't restyle, to find out what another plugin's
-- windows are made of: plain rectangles whose colour isn't one of the skin's, and sprites the
-- plugin has no image for (or that draw another plugin's image). Each kind is printed once, with
-- how many there are and where.
local interface_walker = require("src/game/interface_walker")
local skin_palette = require("src/game/skin_palette")
local component_fields = require("src/game/component_fields")
local game_ids = require("src/game/game_ids")

local unstyled = {}

local prefix = "[Old Interface] unstyled: "
-- The interfaces looked through: the main one, where plugins' windows are made, and the Bank.
local interface_names = { "TOPLEVEL_V2", "BANK" }
local lines_left = 150
-- The kinds printed so far.
---@type table<string, boolean>
local printed = {}

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
            local name = sprite_id == component_fields.runtime_image_id and "a runtime image"
                or game_ids.sprite_name(sprite_id) or tostring(sprite_id)
            kinds[#kinds + 1] = (field ~= "" and field .. "=" or "") .. name
        end
    end
    if #kinds == 0 then
        return nil
    end
    return string.format("%s %s rgba %08X", tostring(component.type), table.concat(kinds, " "), component.rgba or 0)
end

-- Prints the kinds of unstyled things showing now that weren't printed before.
---@param parts table<string, SwappedPart> What the plugin has swapped, which is left out.
function unstyled.report(parts)
    local found = {}
    local order = {}
    for _, interface_name in ipairs(interface_names) do
        local interface_id = game_ids.interface_id(interface_name)
        if interface_id and ui.Interfaces:GetInterface(interface_id) then
            interface_walker.each_component(interface_id, function (component)
                local key = interface_walker.component_key(component)
                local is_swapped = false
                for _, field in ipairs(component_fields.sprite_fields[component.type] or {}) do
                    if parts[key .. ":" .. field] then
                        is_swapped = true
                    end
                end
                local described, kind = pcall(kind_of, component)
                if not is_swapped and described and kind then
                    local where = interface_name .. ":" .. component.staticID
                    local entry = found[kind]
                    if entry == nil then
                        entry = { count = 0, where = where, width = component.width, height = component.height }
                        found[kind] = entry
                        order[#order + 1] = kind
                    end
                    entry.count = entry.count + 1
                end
            end, true)
        end
    end
    table.sort(order)
    for _, kind in ipairs(order) do
        if not printed[kind] and lines_left > 0 then
            printed[kind] = true
            lines_left = lines_left - 1
            local entry = found[kind]
            print(string.format("%s%s x%d, like %dx%d in %s", prefix, kind, entry.count, entry.width, entry.height, entry.where))
        end
    end
end

return unstyled
