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
local title_plate = require("src/game/title_plate")

local sprite_images = {}

---@class SpriteLook What a game sprite is drawn as.
---@field image PluginResource
---@field sprite_name string The game sprite's name.
---@field follows_title boolean Whether its image depends on the window's title, which the game can change without touching the sprite (see title_plate).
---@field tint integer? The tint (0xRRGGBB) for the image, when it's a grey copy.
---@field image_set_suffix string What's after "frames" in the name of the image's folder, like "_tintable".
---@field changes_often boolean Whether the game changes the sprite all the time (see SpriteGroup.changes_often).
---@field checked_while_hidden boolean See SpriteGroup.checked_while_hidden.

-- The player's choices for how windows are drawn.
---@class WindowLook
---@field textured_panels boolean? Whether the panels inside windows show the window's texture, as before 2019. Off if left out.
---@field title_plates boolean? Whether big windows' titles sit on a red plate (see title_plate). On if left out.

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
-- The panels inside windows, like the Bank's item area, were a plain blue from 2019 on, which is
-- what their images are. Before that there were no panels: the window's own textured background
-- showed there. The player can have that instead, by drawing the panel's pieces see-through.
local panel_piece_pattern = "^RS3_PARENT_CONTENT_TAB_FRAME_%d$"
local see_through_image = "see_through"
local has_textured_panels = false
-- Whether big windows' titles sit on a red plate (see title_plate).
local shows_title_plates = true
-- The side piece's sprite ID, looked up when the swapping starts.
---@type integer?
local side_tile_id = nil

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
        sprite_name = sprite_name,
        follows_title = shows_title_plates and title_plate.follows_title(sprite_name),
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
---@return PluginResource image
---@return string? changing_image_name The image's name, where it can change while the sprite stays the same (see SpriteLook.follows_title).
function sprite_images.image_at(component, sprite_id, look)
    if sprite_id == side_tile_id and fills_its_parent(component) then
        return resource(Plugin.resources, side_without_edge_image .. look.image_set_suffix) or look.image
    end
    local plate_image = title_plate.image_name_at(component, look.sprite_name, shows_title_plates)
    if plate_image then
        return resource(frames(look.image_set_suffix), plate_image) or look.image, plate_image
    end
    return look.image
end

-- Whether a table has anything in it, whatever its keys are.
---@param entries table?
---@return boolean
local function has_entries(entries)
    return entries ~= nil and next(entries) ~= nil
end

-- Whether any sprite is tinted. In the classic scheme without colours of the player's own, none is.
---@return boolean
function sprite_images.tints_any()
    local scheme_has_tint = colours.tint ~= nil
    local scheme_tints_parts = has_entries(colours.part_tints)
    local scheme_tints_sprites = has_entries(colours.sprite_tints)
    local player_tints_parts = has_entries(colours.own_part_tints)
    return scheme_has_tint or scheme_tints_parts or scheme_tints_sprites or player_tints_parts
end

-- Sets which groups of sprites are swapped (names from sprite_groups) and what the look is drawn
-- in, and forgets the looks chosen before.
---@param groups table<string, boolean>
---@param scheme_colours SchemeColours
---@param window_look WindowLook? The player's choices for how windows are drawn; the usual look if left out.
---@return SchemeColours # The colours as they can be drawn with the images that are loaded.
function sprite_images.use(groups, scheme_colours, window_look)
    swapped_groups = groups
    has_textured_panels = window_look ~= nil and window_look.textured_panels == true
    shows_title_plates = window_look == nil or window_look.title_plates ~= false
    looks = {}
    side_tile_id = game_ids.sprite_id(side_tile_name)
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
