-- The colour schemes the old look can be drawn in. The classic scheme draws the old images as
-- they were. Every other scheme draws grey copies of them (resources/frames_tintable, made by
-- tools/frames/make_tintable.cjs) and has the game tint those: a tint multiplies each pixel's
-- colour, so only a grey image can become any colour.
--
-- A grey copy keeps each pixel's brightness (its strongest colour channel), and plain colours are
-- changed the same way here, so panels match the frames around them.
local colour_scheme = {}

---@class ColourScheme
---@field key string
---@field label string
---@field tint integer? 0xRRGGBB. None for the classic scheme and the custom one (the player's own colour).

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
    { key = colour_scheme.custom_key, label = "Custom" },
}

-- What a look is drawn in: a scheme's tint, and the player's own text colours if they chose any.
---@class SchemeColours
---@field tint integer? 0xRRGGBB, or nil for the classic scheme.
---@field part_tints table<string, integer>? The player's own tint for parts of the interface, by sprite_groups.colour_parts key. The other parts have the scheme's.
---@field heading_text integer? Replaces the gold of headings.
---@field body_text integer? Replaces the blue-grey of other text.

-- The old look's text colours, which the player's own replace.
colour_scheme.default_heading_text = 0xFCC907
colour_scheme.default_body_text = 0xA6C7D6

-- How much of the scheme's colour light text takes on (the rest stays white).
local text_tint_strength = 0.4

---@param rgb integer
---@return integer, integer, integer
local function channels(rgb)
    return (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
end

---@param red number
---@param green number
---@param blue number
---@return integer
local function colour(red, green, blue)
    return (math.floor(red + 0.5) << 16) | (math.floor(green + 0.5) << 8) | math.floor(blue + 0.5)
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

-- The tint to draw a part of the interface with, or nil to draw it as it was.
---@param colours SchemeColours
---@param part_key string A key from sprite_groups.colour_parts.
---@return integer?
function colour_scheme.part_tint(colours, part_key)
    return colours.part_tints and colours.part_tints[part_key] or colours.tint
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
