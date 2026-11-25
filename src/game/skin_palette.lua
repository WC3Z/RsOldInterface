-- The old colour of each colour the current interface uses, from the game's own skin colour lists.
-- They have the same slots: slot 12 is 0x24211E in the normal skin and 0x152648 in the mobile
-- skin, which still has the old blue look. Where the normal skin uses a colour in several slots,
-- the lowest slot decides.
local skin_palette = {}

---@type table<integer, integer>?
local old_colours = nil

---@return table<integer, integer>
local function read_old_colours()
    local colours = {}
    local found_normal, normal = pcall(function () return config.Enum.TOPLEVEL_V2_SKIN_COLOUR_NORMAL end)
    local found_mobile, mobile = pcall(function () return config.Enum.TOPLEVEL_V2_SKIN_COLOUR_MOBILE end)
    if not (found_normal and normal and found_mobile and mobile) then
        return colours
    end
    local slots = {}
    for _, pair in ipairs(normal.values) do
        slots[#slots + 1] = pair
    end
    table.sort(slots, function (a, b) return a[1] < b[1] end)
    for _, pair in ipairs(slots) do
        local slot, colour = pair[1], pair[2]
        local old_colour = mobile:GetOutputValue(slot)
        if old_colour ~= nil and colours[colour] == nil and old_colour ~= colour then
            colours[colour] = old_colour
        end
    end
    return colours
end

-- The old colour for a colour the interface uses (0xRRGGBB), or nil if it has none.
---@param rgb integer
---@return integer?
function skin_palette.old_colour(rgb)
    old_colours = old_colours or read_old_colours()
    return old_colours[rgb]
end

-- The mobile skin's text colours are close to the old desktop ones but not the same: headings were
-- a stronger gold and body text a softer blue-grey (measured from a screenshot of the old Settings
-- window).
---@type table<integer, integer>
local old_desktop_text_colours = {
    [0xD9DBA9] = 0xFCC907,
    [0xA1EAFC] = 0xA6C7D6,
}

-- Text colours that aren't in the skin, like the ones prettyui (used by plugins' windows) draws
-- with, and the old colours for the same kind of text.
---@type table<integer, integer>
local other_text_colours = {
    [0xF4E4B8] = 0xFCC907, -- window titles
    [0xF2C66D] = 0xFCC907, -- sub-headings
    [0xE7D7B0] = 0xA6C7D6, -- labels
    [0xF2E2BC] = 0xC4DDE9, -- tabs and options
    -- Other plugins' own text colours, in the current look's beige and gold.
    [0xA99F8A] = 0xA6C7D6,
    [0xAFA58F] = 0xA6C7D6,
    [0xB7AA8E] = 0xA6C7D6,
    [0xC9BEA4] = 0xA6C7D6,
    [0xD7C9AD] = 0xA6C7D6,
    [0xD8CCAE] = 0xA6C7D6,
    [0xE9E5DD] = 0xC4DDE9,
    [0xE7C878] = 0xFCC907,
}

-- The old colour for a text colour, or nil if it has none.
---@param rgb integer
---@return integer?
function skin_palette.old_text_colour(rgb)
    local old_rgb = skin_palette.old_colour(rgb)
    if old_rgb then
        return old_desktop_text_colours[old_rgb] or old_rgb
    end
    return other_text_colours[rgb]
end

-- Other plugins draw their own panels, rows and lines as rectangles in the current look's browns:
-- warm, dark, nearly grey colours that aren't in the skin. Their old colour is the panel blue of
-- the old Bank (#1E3146, which the current look's panel brown #332E29 becomes), lighter or
-- darker as the brown is. Colours that aren't such a brown have none: gold lines stay gold.
local panel_blue = { 0x1E, 0x31, 0x46 }
local panel_brown_red = 0x33
local least_warmth, most_warmth = 4, 60
local brightest_brown_red = 0xA0

---@param rgb integer
---@return integer?
function skin_palette.old_panel_colour(rgb)
    local red, green, blue = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
    local warmth = red - blue
    if red < green or green < blue or warmth < least_warmth or warmth > most_warmth or red > brightest_brown_red then
        return nil
    end
    local old_rgb = 0
    for _, channel in ipairs(panel_blue) do
        old_rgb = old_rgb * 256 + math.min(255, math.floor(channel * red / panel_brown_red + 0.5))
    end
    return old_rgb
end

return skin_palette
