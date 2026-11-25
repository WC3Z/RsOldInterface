-- Chooses what to draw in place of each of the game's sprites: the plugin's image with the
-- sprite's name (resources/frames/RS3_CHILD_CONTENT_TILE.png for RS3_CHILD_CONTENT_TILE), in the
-- chosen colour scheme (see colour_scheme):
-- - a scheme's own image for the sprite, where it has one, drawn as it is;
-- - else, where the scheme or the player has a tint for the sprite, a grey copy of the old image
--   (resources/frames_tintable) for the game to tint;
-- - else the old image as it was.
local sprite_groups = require("src/game/sprite_groups")
local colour_scheme = require("src/game/colour_scheme")
local game_ids = require("src/game/game_ids")

local sprite_images = {}

---@class SpriteLook What a game sprite is drawn as.
---@field image PluginResource
---@field tint integer? The tint (0xRRGGBB) for the image, when it's a grey copy.
---@field image_set_suffix string What's after "frames" in the name of the image's folder, like "_tintable".
---@field changes_often boolean Whether the game changes the sprite all the time (see SpriteGroup.changes_often).
---@field checked_while_hidden boolean See SpriteGroup.checked_while_hidden.

---@type table<string, boolean>
local swapped_groups = {}
-- What the look is drawn in, as far as the images that are loaded allow (see sprite_images.use).
---@type SchemeColours
local colours = {}
-- The look of each game sprite seen so far, by sprite ID; false for sprites that aren't swapped.
-- The resources can't be listed, so each sprite's image is looked up by name when it's first seen.
---@type table<integer, SpriteLook|false>
local looks = {}

-- Big windows' frame is built in strips, and the strip between the title and the tabs only has
-- side pieces, each filling it. The old frame had no border there (it starts at the curls by the
-- tabs), so those side pieces draw the window's dark fill without the edge line.
local side_tile_name = "RS3_PARENT_FRAME_SIDE_TILE"
local side_without_edge_image = "side_without_edge"
-- Smaller windows' title bar had its title on a red plate at the left, which started at the title
-- corner. The game centres titles now, and some windows (like the one for making items) draw the
-- plate's middle piece on its own behind the title, where it would be a red block with cut-off
-- ends. So the plate is only drawn where it follows the title corner; elsewhere that piece looks
-- like the rest of the title bar.
local title_plate_name = "RS3_MODAL_WINDOW_1_TITLE_TILE"
local title_bar_image = "RS3_MODAL_WINDOW_1_TOP_TILE"
local title_corner_width = 28
-- The panels inside windows, like the Bank's item area, were a plain blue from 2019 on, which is
-- what their images are. Before that there were no panels: the window's own textured background
-- showed there. The player can have that instead, by drawing the panel's pieces see-through.
local panel_piece_pattern = "^RS3_PARENT_CONTENT_TAB_FRAME_%d$"
local see_through_image = "see_through"
local has_textured_panels = false
-- The two sprites' IDs, looked up when the swapping starts.
---@type integer?, integer?
local side_tile_id, title_plate_id = nil, nil

-- The plugin's image with the given name in a folder of its resources, if there is one.
---@param images table?
---@param name string
---@return PluginResource?
local function resource(images, name)
    return images and (images[name] or images[name .. ".png"]) or nil
end

-- A folder of images: "" for the old ones, "_tintable" for their grey copies, or a scheme's own.
---@param image_set_suffix string
---@return table?
local function frames(image_set_suffix)
    return Plugin.resources and Plugin.resources["frames" .. image_set_suffix]
end

---@param sprite_name string
---@param group_name string
---@return SpriteLook?
local function look_for(sprite_name, group_name)
    local part_key = sprite_groups.colour_part_of(sprite_name)
    local image_name = sprite_groups.image_names[sprite_name] or sprite_name
    local image, tint, image_set_suffix = nil, nil, ""
    if has_textured_panels and sprite_name:find(panel_piece_pattern) then
        image = resource(Plugin.resources, see_through_image)
    end
    -- The player's own colour for the sprite's part comes before the scheme's own image.
    if image == nil and colours.image_set and not colour_scheme.own_part_tint(colours, part_key) then
        image_set_suffix = "_" .. colours.image_set
        image = resource(frames(image_set_suffix), image_name)
    end
    if image == nil and not sprite_groups.keeps_own_colours(sprite_name) then
        tint = colour_scheme.sprite_tint(colours, sprite_name, part_key)
        image_set_suffix = "_tintable"
        image = tint and resource(frames(image_set_suffix), image_name)
    end
    if not image then
        tint = nil
        image_set_suffix = ""
        image = resource(frames(image_set_suffix), image_name)
    end
    if not image then
        return nil
    end
    return {
        image = image,
        tint = tint,
        image_set_suffix = image_set_suffix,
        changes_often = sprite_groups.changes_often(group_name),
        checked_while_hidden = sprite_groups.is_checked_while_hidden(group_name),
    }
end

-- What to draw for a game sprite, or nil if it isn't swapped.
---@param sprite_id integer? Nil for a holder that has no sprite (the game can reuse a component's IDs for another type).
---@return SpriteLook?
function sprite_images.look_of(sprite_id)
    if sprite_id == nil then
        return nil
    end
    local look = looks[sprite_id]
    if look == nil then
        local sprite_name = game_ids.sprite_name(sprite_id)
        local group_name = sprite_name and sprite_groups.group_of(sprite_name)
        look = group_name and swapped_groups[group_name] and look_for(sprite_name, group_name) or false
        looks[sprite_id] = look
    end
    return look or nil
end

---@param component ui.Component
local function fills_its_parent(component)
    local parent = component.parent
    return parent ~= nil and component.height >= parent.height
end

-- The image to draw for a sprite where the given component shows it: the look's own, except
-- where the same sprite should look different depending on where it is (see the top of the file).
-- The other image comes from the same folder as the look's own.
---@param component ui.Component
---@param sprite_id integer
---@param look SpriteLook
---@return PluginResource
function sprite_images.image_at(component, sprite_id, look)
    if sprite_id == side_tile_id and fills_its_parent(component) then
        return resource(Plugin.resources, side_without_edge_image .. look.image_set_suffix) or look.image
    end
    if sprite_id == title_plate_id and component.x ~= title_corner_width then
        return resource(frames(look.image_set_suffix), title_bar_image) or look.image
    end
    return look.image
end

-- Whether any sprite is tinted. In the classic scheme without colours of the player's own, none is.
---@return boolean
function sprite_images.tints_any()
    return colours.tint ~= nil or next(colours.part_tints or {}) ~= nil
        or next(colours.sprite_tints or {}) ~= nil or next(colours.own_part_tints or {}) ~= nil
end

-- Sets which groups of sprites are swapped (names from sprite_groups) and what the look is drawn
-- in, and forgets the looks chosen before.
---@param groups table<string, boolean>
---@param scheme_colours SchemeColours
---@param textured_panels boolean? Whether the panels inside windows show the window's texture (see above).
---@return SchemeColours # The colours as they can be drawn with the images that are loaded.
function sprite_images.use(groups, scheme_colours, textured_panels)
    swapped_groups = groups
    has_textured_panels = textured_panels == true
    looks = {}
    side_tile_id = game_ids.sprite_id(side_tile_name)
    title_plate_id = game_ids.sprite_id(title_plate_name)
    -- Without the grey copies (new images only load when the client reloads its resources) nothing
    -- can be tinted. Without a scheme's own images it's drawn as the classic scheme: its tints are
    -- only for what those images leave out.
    local can_tint = frames("_tintable") ~= nil
    local has_scheme_images = scheme_colours.image_set == nil or frames("_" .. scheme_colours.image_set) ~= nil
    local can_tint_as_scheme = can_tint and has_scheme_images
    colours = {
        tint = can_tint_as_scheme and scheme_colours.tint or nil,
        part_tints = can_tint_as_scheme and scheme_colours.part_tints or nil,
        sprite_tints = can_tint_as_scheme and scheme_colours.sprite_tints or nil,
        own_part_tints = can_tint and scheme_colours.own_part_tints or nil,
        image_set = has_scheme_images and scheme_colours.image_set or nil,
        heading_text = scheme_colours.heading_text,
        body_text = scheme_colours.body_text,
    }
    return colours
end

return sprite_images
