-- The colour schemes the old look can be drawn in. The classic scheme draws the old images as
-- they were. A scheme with a tint draws grey copies of them (resources/frames_tintable) and has
-- the game tint those: a tint multiplies each pixel's colour, so only a grey image can become any
-- colour. A scheme can also have images of its own, drawn as they are in place of the old ones.
--
-- A grey copy keeps each pixel's brightness (its strongest colour channel), and plain colours are
-- changed the same way here, so panels match the frames around them.
local colour_scheme = {}

---@class ColourScheme
---@field key string
---@field label string
---@field tint integer? 0xRRGGBB. None for the classic scheme and the custom one (the player's own colour).
---@field part_tints table<string, integer>? The tints of the parts of the interface that differ from it, by sprite_groups.colour_parts key.
---@field sprite_tints SpriteTint[]? The tints of sprites that differ from their part's; the first matching one counts.
---@field image_set string? The scheme's own images, in resources/frames_<image_set> (and side_without_edge_<image_set>.png). Sprites it has no image for are drawn like in any scheme.

---@class SpriteTint
---@field pattern string Matches the names of the sprites it's for.
---@field tint integer

colour_scheme.classic_key = "classic"
colour_scheme.custom_key = "custom"
colour_scheme.default_custom_tint = 0x4A87FF

---@type ColourScheme[]
colour_scheme.all = {
    { key = colour_scheme.classic_key, label = "Classic blue" },
    { key = "crimson", label = "Crimson", tint = 0xFF5A52 },
    { key = "emerald", label = "Emerald", tint = 0x5CE08A },
    { key = "amethyst", label = "Amethyst", tint = 0xB088FF },
    { key = "bronze", label = "Bronze", tint = 0xFFB060 },
    { key = "teal", label = "Teal", tint = 0x4FE0D8 },
    { key = "steel", label = "Steel", tint = 0xD4DCE8 },
    {
        -- DarkScape's interface (2015-16): its own versions of the old interface's pieces
        -- (resources/frames_darkscape). It kept the main game's buttons, controls and text
        -- colours, so those are drawn as in the classic scheme. The pieces it had no version of
        -- (or built differently, like smaller windows' frames) are tinted with colours fitted to
        -- its sprites, and so are plain panels.
        key = "darkscape",
        label = "DarkScape",
        image_set = "darkscape",
        part_tints = { backgrounds = 0xA8605A },
        sprite_tints = {
            { pattern = "^RS3_MODAL_WINDOW_1_", tint = 0x906A54 },
            { pattern = "^RS3_HUD_WINDOW_", tint = 0x967F70 },
            { pattern = "^RS3_PARENT_TAB_CURRENT_", tint = 0xFF7F80 },
            { pattern = "^RS3_PARENT_TAB_", tint = 0xFBB8BE },
            { pattern = "^RS3_CONTENT_FRAME_", tint = 0x905D42 },
            { pattern = "^RS3_CONTENT_CONTAINER", tint = 0x917160 },
            { pattern = "^RS3_CONTEXTUAL_INPUT_BOX", tint = 0x8B7B6F },
            { pattern = "^INPUT_DEFAULT$", tint = 0x8B7B6F },
            { pattern = "^DROPDOWN_DEFAULT_LIST_BACKGROUND$", tint = 0x8B7B6F },
        },
    },
    { key = colour_scheme.custom_key, label = "Custom" },
}

-- What a look is drawn in: a scheme's tint, and the player's own text colours if they chose any.
---@class SchemeColours
---@field tint integer? 0xRRGGBB, or nil for the classic scheme.
---@field part_tints table<string, integer>? The scheme's tints for parts of the interface that differ from it, by sprite_groups.colour_parts key.
---@field own_part_tints table<string, integer>? The player's own tints for parts of the interface, which come before everything of the scheme's.
---@field sprite_tints SpriteTint[]? The scheme's tints for sprites that differ from their part's.
---@field image_set string? The scheme's own images (see ColourScheme.image_set).
---@field heading_text integer? Replaces the gold of headings.
---@field body_text integer? Replaces the blue-grey of other text.

-- The old look's text colours, which the player's own replace.
colour_scheme.default_heading_text = 0xFCC907
colour_scheme.default_body_text = 0xA6C7D6

-- How much of the scheme's colour light text takes on (the rest stays white).
local text_tint_strength = 0.4

-- A colour is one number, 0xRRGGBB: two hex digits (8 bits, 0-255) each for red, green and blue.
local red_shift, green_shift = 16, 8
local one_channel = 0xFF

-- Splits a colour into its red, green and blue. Shifting right moves the wanted channel to the
-- lowest 8 bits (0x4FE0D8 >> 8 is 0x4FE0), and `& 0xFF` keeps only those 8 bits, dropping the
-- channels still above it (0x4FE0 & 0xFF is 0xE0).
---@param rgb integer
---@return integer, integer, integer
local function channels(rgb)
    local red = (rgb >> red_shift) & one_channel
    local green = (rgb >> green_shift) & one_channel
    local blue = rgb & one_channel
    return red, green, blue
end

---@param channel number
---@return integer
local function rounded(channel)
    return math.floor(channel + 0.5)
end

-- Puts red, green and blue (0-255 each) back into one colour: shifting left moves each to its
-- place, and `|` joins them, as no two share a bit.
---@param red number
---@param green number
---@param blue number
---@return integer
local function colour(red, green, blue)
    return (rounded(red) << red_shift) | (rounded(green) << green_shift) | rounded(blue)
end

-- The tint to draw a scheme with, or nil for the classic scheme (and unknown ones).
---@param key string?
---@param custom_tint integer? The player's own colour, for the custom scheme.
---@return integer?
function colour_scheme.tint_of(key, custom_tint)
    if key == colour_scheme.custom_key then
        return custom_tint or colour_scheme.default_custom_tint
    end
    for _, scheme in ipairs(colour_scheme.all) do
        if scheme.key == key then
            return scheme.tint
        end
    end
    return nil
end

-- The player's own tint for a part of the interface, if they chose one.
---@param colours SchemeColours
---@param part_key string A key from sprite_groups.colour_parts.
---@return integer?
function colour_scheme.own_part_tint(colours, part_key)
    return colours.own_part_tints and colours.own_part_tints[part_key] or nil
end

-- The tint to draw a part of the interface with, or nil to draw it as it was: the player's own,
-- else the scheme's for the part, else the scheme's.
---@param colours SchemeColours
---@param part_key string A key from sprite_groups.colour_parts.
---@return integer?
function colour_scheme.part_tint(colours, part_key)
    return colour_scheme.own_part_tint(colours, part_key)
        or colours.part_tints and colours.part_tints[part_key]
        or colours.tint
end

---@param key string?
---@return ColourScheme? # The scheme with the given key, if there is one.
function colour_scheme.find(key)
    for _, scheme in ipairs(colour_scheme.all) do
        if scheme.key == key then
            return scheme
        end
    end
    return nil
end

-- The tint to draw a sprite with, or nil to draw it as it was: the player's own for its part,
-- else the scheme's for sprites of its name, else its part's, else the scheme's.
---@param colours SchemeColours
---@param sprite_name string
---@param part_key string The sprite's part, a key from sprite_groups.colour_parts.
---@return integer?
function colour_scheme.sprite_tint(colours, sprite_name, part_key)
    local own_tint = colour_scheme.own_part_tint(colours, part_key)
    if own_tint then
        return own_tint
    end
    for _, sprite_tint in ipairs(colours.sprite_tints or {}) do
        if sprite_name:find(sprite_tint.pattern) then
            return sprite_tint.tint
        end
    end
    return colour_scheme.part_tint(colours, part_key)
end

-- A colour the game already tints a part with, with the scheme's tint on top.
---@param rgb integer
---@param tint integer
---@return integer
function colour_scheme.multiplied(rgb, tint)
    local red, green, blue = channels(rgb)
    local tint_red, tint_green, tint_blue = channels(tint)
    return colour(red * tint_red / 255, green * tint_green / 255, blue * tint_blue / 255)
end

-- A plain colour of the old look in the scheme's colour: what a grey copy of it would be tinted to.
---@param rgb integer
---@param tint integer
---@return integer
function colour_scheme.tinted(rgb, tint)
    local brightness = math.max(channels(rgb))
    return colour_scheme.multiplied(colour(brightness, brightness, brightness), tint)
end

-- Whether a text colour of the old look is a heading's gold; the others are blue-greys.
---@param rgb integer
---@return boolean
function colour_scheme.is_heading_text(rgb)
    local red, _, blue = channels(rgb)
    return blue <= red
end

-- A text colour of the old look in the scheme's colour. Only the blue-grey ones change, and stay
-- light: gold headings look right on any colour.
---@param rgb integer
---@param tint integer
---@return integer
function colour_scheme.tinted_text(rgb, tint)
    if colour_scheme.is_heading_text(rgb) then
        return rgb
    end
    local brightness = math.max(channels(rgb))
    local tint_red, tint_green, tint_blue = channels(tint)
    local function mixed(tint_channel)
        return brightness * (255 + (tint_channel - 255) * text_tint_strength) / 255
    end
    return colour(mixed(tint_red), mixed(tint_green), mixed(tint_blue))
end

-- The colour for a text that has the given colour in the old look.
---@param rgb integer
---@param colours SchemeColours
---@return integer
function colour_scheme.text_colour(rgb, colours)
    local own_colour = colour_scheme.is_heading_text(rgb) and colours.heading_text or colours.body_text
    if own_colour then
        return own_colour
    end
    return colours.tint and colour_scheme.tinted_text(rgb, colours.tint) or rgb
end

return colour_scheme
