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

-- A text colour of the old look in the scheme's colour. Only the blue-grey ones change, and stay
-- light: gold headings look right on any colour.
---@param rgb integer
---@param tint integer
---@return integer
function colour_scheme.tinted_text(rgb, tint)
    local red, _, blue = channels(rgb)
    if blue <= red then
        return rgb
    end
    local brightness = math.max(channels(rgb))
    local tint_red, tint_green, tint_blue = channels(tint)
    local function mixed(tint_channel)
        return brightness * (255 + (tint_channel - 255) * text_tint_strength) / 255
    end
    return colour(mixed(tint_red), mixed(tint_green), mixed(tint_blue))
end

return colour_scheme
