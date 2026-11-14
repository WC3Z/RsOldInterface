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

return skin_palette
