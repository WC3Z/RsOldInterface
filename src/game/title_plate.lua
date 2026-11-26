-- The red plate behind a big window's title, like Settings'.
--
-- The plate is drawn by three sprites in a row: a start, a middle and an end piece, with the bar
-- that runs along the rest of the window's top after them. The game used to make the middle as
-- wide as the title. It doesn't any more: the middle is 0 wide, so the plate ends a little way
-- into the title, which runs on over the bar.
--
-- A plugin can't resize the game's components, so the plate is made longer with images instead:
-- the end piece and the bar each have versions with the plate carrying on for 16, 32, 48...
-- pixels before it ends (resources/frames/<sprite name>_LONGER_<pixels>.png), and the one that
-- reaches the end of the title is drawn.
--
-- The player can also have no plate at all. Then the pieces are plain bar, and the bar's line
-- starts after the title instead of running through its letters, with the same kind of versions
-- (<sprite name>_NO_PLATE_LONGER_<pixels>.png, and <start piece>_NO_PLATE.png).
local title_plate = {}

local start_piece = "RS3_PARENT_BANNER_SWORD_LEFT"
local end_piece = "RS3_PARENT_BANNER_SWORD_RIGHT"
local bar_piece = "RS3_PARENT_BANNER_BAR_TILE"

-- Where the unchanged plate stops being its full height, from the window's left edge.
local plate_end_x = 81
-- How far past the title's last letter the plate carries on before it ends.
local space_after_title = 8
-- The longer versions there are images for.
local length_step = 16
local longest = 256
-- Past its own width the end piece is all plate, however much longer the plate is.
local end_piece_width = 176
-- The title is in the same static component as the pieces, at about the same height.
local most_rows_apart = 16

---@param piece ui.Component One of the plate's pieces.
---@return ui.Component? # The window's title.
local function title_beside(piece)
    local parent = piece.parentStatic
    if parent == nil then
        return nil
    end
    local title = nil
    parent:IterateDynamicComponents(function (sibling)
        local is_title = sibling.type == ui.ComponentType.LABEL and sibling.content ~= ""
            and math.abs(sibling.y - piece.y) <= most_rows_apart
        if is_title and title == nil then
            title = sibling
        end
        return false
    end)
    return title
end

-- How much longer the plate has to be to reach the end of the window's title: one of the lengths
-- there are images for, or 0 when the plate is long enough as it is (or there's no title).
---@param piece ui.Component One of the plate's pieces.
---@return integer
local function extra_length(piece)
    local title = title_beside(piece)
    local font = title and config.Font.FromID(title.font)
    if title == nil or font == nil then
        return 0
    end
    local title_end_x = title.x + font:GetStringWidth(title.content)
    local missing = title_end_x + space_after_title - plate_end_x
    if missing <= 0 then
        return 0
    end
    local steps = math.ceil(missing / length_step)
    return math.min(steps * length_step, longest)
end

-- Whether a sprite's image depends on the window's title: the game changes the title when another
-- big window opens in the same frame, and leaves the sprites as they are.
---@param sprite_name string
---@return boolean
function title_plate.follows_title(sprite_name)
    return sprite_name == end_piece or sprite_name == bar_piece
end

-- The name of the image to draw for one of the plate's sprites where the given component shows it,
-- or nil for the sprite's usual image (which every other sprite gets too).
---@param component ui.Component
---@param sprite_name string
---@param shows_plate boolean Whether the player wants the plate.
---@return string?
function title_plate.image_name_at(component, sprite_name, shows_plate)
    if sprite_name == start_piece then
        return not shows_plate and sprite_name .. "_NO_PLATE" or nil
    end
    if sprite_name ~= end_piece and sprite_name ~= bar_piece then
        return nil
    end
    -- The game's objects can be gone or of another kind by now: then it's as without a title.
    local measured, longer = pcall(extra_length, component)
    if not measured then
        longer = 0
    end
    if sprite_name == end_piece then
        longer = math.min(longer, end_piece_width)
    end
    if shows_plate then
        return longer > 0 and sprite_name .. "_LONGER_" .. longer or nil
    end
    -- Without a plate the end piece is always another image, the bar only where the title reaches it.
    if sprite_name == bar_piece and longer == 0 then
        return nil
    end
    return sprite_name .. "_NO_PLATE_LONGER_" .. longer
end

return title_plate
