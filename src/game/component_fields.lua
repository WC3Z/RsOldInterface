-- Reads and writes the fields of the game's components that the plugin changes: sprites and
-- colours. Everything goes through pcall: the game can have destroyed a component, or given it
-- another type, since it was found.
local component_fields = {}

-- What a sprite reports as its ID while it draws an image made at runtime, like a plugin's.
component_fields.runtime_image_id = -1
-- The category ID (and dynamic ID) of a static component: one that's part of its interface, not
-- created by the game while running.
component_fields.static_category_id = -1

-- The fields holding each component type's sprites. A sprite component's own sprite is the empty
-- name; interactive components like buttons and dropdowns keep theirs in sprite data objects.
---@type table<string, string[]>
component_fields.sprite_fields = {
    [ui.ComponentType.SPRITE] = { "" },
    [ui.ComponentType.BUTTON] = { "sprite" },
    [ui.ComponentType.CHECK] = { "sprite" },
    [ui.ComponentType.COMBO] = { "entrySprite", "buttonSprite", "headerSprite" },
    [ui.ComponentType.LIST] = { "entrySprite", "buttonSprite", "headerSprite" },
    [ui.ComponentType.INPUTFIELD] = { "containerSprite" },
    [ui.ComponentType.RADIO_GROUP] = { "buttonSprite" },
    [ui.ComponentType.SLIDER] = { "thumbSprite", "trackSprite", "notchSprite" },
    [ui.ComponentType.CAROUSEL] = { "buttonSprite", "backgroundSprite" },
    [ui.ComponentType.PAGED_CAROUSEL] = { "buttonSprite", "pageBackgroundSprite" },
    [ui.ComponentType.PAGED_LAYER] = { "backgroundSprite", "pageHeaderSprite" },
    [ui.ComponentType.GROUP_BOX] = { "contentBackgroundSprite", "headerBackgroundSprite" },
}

-- Called through pcall, which takes these as they are rather than a new function each time: they
-- run for thousands of components every update.
local function get_field(object, field)
    return object[field]
end

local function set_field(object, field, value)
    object[field] = value
end

-- What holds a sprite or a colour: the component itself for the empty field name, or the object
-- in the given field (a button's sprite data, or its text).
---@param component ui.Component
---@param field string
---@return (ui.Component|userdata|table)?
function component_fields.holder(component, field)
    if field == "" then
        return component
    end
    local found, holder = pcall(get_field, component, field)
    -- An object, not a plain value: a sprite component's own "sprite" field, for one, is a number.
    if found and (type(holder) == "userdata" or type(holder) == "table") then
        return holder
    end
    return nil
end

---@param holder ui.Component|userdata|table
---@param sprite integer|PluginResource
---@return boolean # Whether it took.
function component_fields.set_sprite(holder, sprite)
    return (pcall(set_field, holder, "sprite", sprite))
end

-- A holder's colour as 0xRRGGBB. A component has it as such; the objects in its fields have it
-- with transparency (0xRRGGBBAA).
---@param holder ui.Component|userdata|table
---@param field string The field the holder was found in.
---@return integer?
function component_fields.read_rgb(holder, field)
    if field == "" then
        local found, rgb = pcall(get_field, holder, "rgb")
        return found and rgb or nil
    end
    local found, rgba = pcall(get_field, holder, "rgba")
    return found and rgba and math.floor(rgba / 256) or nil
end

-- Sets a holder's colour, keeping its transparency.
---@param holder ui.Component|userdata|table
---@param field string The field the holder was found in.
---@param rgb integer
---@return boolean # Whether it took.
function component_fields.write_rgb(holder, field, rgb)
    if field == "" then
        return (pcall(set_field, holder, "rgb", rgb))
    end
    local found, rgba = pcall(get_field, holder, "rgba")
    if not found or rgba == nil then
        return false
    end
    return (pcall(set_field, holder, "rgba", rgb * 256 + rgba % 256))
end

-- The four IDs that find a component again later.
---@class ComponentIds
---@field interface_id integer
---@field static_id integer
---@field category_id integer
---@field dynamic_id integer

-- Looked up fresh each time: the game may have destroyed or rebuilt the component since.
---@param ids ComponentIds
---@return ui.Component?
function component_fields.find(ids)
    if ids.category_id == component_fields.static_category_id then
        return ui.Interfaces:GetComponent(ids.interface_id, ids.static_id)
    end
    return ui.Interfaces:GetComponent(ids.interface_id, ids.static_id, ids.category_id, ids.dynamic_id)
end

-- Whether the game created the component while running (like a list's rows).
---@param component ui.Component
---@return boolean
function component_fields.is_created(component)
    return component.categoryID ~= component_fields.static_category_id
end

return component_fields
