-- The sprites the plugin can swap, in groups that can be turned on and off separately (like from
-- a settings page later). A sprite belongs to the first group with a matching name pattern.
--
-- The frames of big windows like Settings aren't in any group: their old sprites are different
-- sizes and break the layout.
local sprite_groups = {}

---@class SpriteGroup
---@field name string
---@field patterns string[]
---@field window_contents boolean Whether the game changes these all the time (hover and selected states, rebuilt lists).

---@type SpriteGroup[]
sprite_groups.all = {
    {
        -- Docked windows' tabs change sprite when clicked, so they come before docked_windows.
        name = "tabs",
        patterns = {
            "^RS3_CHILD_TAB_SELECTED$",
            "^RS3_CHILD_TAB_UNSELECTED$",
            "^RS3_PARENT_TAB_",
            "^RS3_PARENT_CONTENT_TILEABLE_TAB_%d+$",
            "^BANK_TABS_%d$",
            "^BANK_TABS_HORIZONTAL_%d$",
        },
        window_contents = true,
    },
    {
        name = "docked_windows",
        patterns = { "^RS3_CHILD_", "^RS3_HUD_WINDOW_", "^RS3_GHOST_COMPACT_" },
        window_contents = false,
    },
    {
        -- Tiles the game repeats to fill a window, or the middle of a frame built from 3x3 pieces
        -- (piece 4), which the game stretches to fill the frame, so they fit whatever their size.
        name = "backgrounds",
        patterns = { "^RS3_[A-Z_]*CONTENT_TILE$", "^RS3_CONTENT_FRAME_4$", "^RS3_PARENT_CONTENT_TAB_FRAME_4$" },
        window_contents = false,
    },
    {
        -- Modal windows like the Bank: the frame and title bar.
        name = "modal_windows",
        patterns = { "^RS3_MAIN_MODAL_" },
        window_contents = false,
    },
    {
        -- The edges and corners of the frames inside windows, like around the Bank's item area and
        -- side panels.
        name = "content_frames",
        patterns = { "^RS3_PARENT_CONTENT_TAB_FRAME_%d$" },
        window_contents = false,
    },
    {
        name = "tooltips",
        patterns = { "^RS3_TOOLTIP_FILL_" },
        window_contents = false,
    },
    {
        name = "dropdowns",
        patterns = { "^RS3_BTN_DROPDOWN_" },
        window_contents = true,
    },
    {
        name = "buttons",
        patterns = { "^RS3_BTN_", "^RS3_BUTTON_CLOSE_", "^RS3_BUTTON_LOGOUT_", "^BUTTON_30PX_[A-Z]+$" },
        window_contents = true,
    },
    {
        name = "rows",
        patterns = { "^RS3_CONTENT_CONTAINER_", "^RS3_CONTEXTUAL_INPUT_BOX_" },
        window_contents = true,
    },
    {
        -- The controls newer windows (like Settings' Gameplay tab) are built from, styled by the
        -- stylesheet of the same name. One sprite per control, holding all its states.
        name = "styled_controls",
        patterns = {
            "^CHECKBOX_DEFAULT$",
            "^BUTTON_CORNERED_[A-Z]+$",
            "^BUTTON_ACCORDION_%d+PX$",
            "^INPUT_SEARCHBOX_%d+PX$",
            "^INPUT_DEFAULT$",
            "^DROPDOWN_DEFAULT_[A-Z_]+$",
        },
        window_contents = true,
    },
    {
        -- Not sprites: plain coloured rectangles, like the cards in Settings' lists, get the old
        -- colour from skin_palette.
        name = "colours",
        patterns = {},
        window_contents = true,
    },
    {
        name = "sliders_and_scrollbars",
        patterns = { "^RS3_SLIDER_", "^SCROLLBAR_" },
        window_contents = true,
    },
}

-- Sprites with no old version (added after the old cache), and a built-in sprite to draw instead:
-- the mobile versions still have the old blue look.
---@type table<string, string>
sprite_groups.stand_ins = {
    BUTTON_ACCORDION_24PX = "BUTTON_ACCORDION_24PX_MOBILE",
    BUTTON_ACCORDION_20PX = "BUTTON_ACCORDION_20PX_MOBILE",
}

-- The names of all groups, or only those that aren't window contents.
---@param with_window_contents boolean
---@return table<string, boolean>
function sprite_groups.names(with_window_contents)
    local names = {}
    for _, group in ipairs(sprite_groups.all) do
        if with_window_contents or not group.window_contents then
            names[group.name] = true
        end
    end
    return names
end

---@param group_name string
---@return boolean
function sprite_groups.is_window_contents(group_name)
    for _, group in ipairs(sprite_groups.all) do
        if group.name == group_name then
            return group.window_contents
        end
    end
    return false
end

---@param sprite_name string
---@return string? # The name of the sprite's group, or nil if it's in none.
function sprite_groups.group_of(sprite_name)
    for _, group in ipairs(sprite_groups.all) do
        for _, pattern in ipairs(group.patterns) do
            if sprite_name:find(pattern) then
                return group.name
            end
        end
    end
    return nil
end

return sprite_groups
