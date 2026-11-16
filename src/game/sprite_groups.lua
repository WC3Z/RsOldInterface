-- The sprites the plugin can swap, in groups that can be turned on and off separately (like from
-- a settings page later). A sprite belongs to the first group with a matching name pattern.
local sprite_groups = {}

---@class SpriteGroup
---@field name string
---@field patterns string[]
---@field window_contents boolean Whether the game changes these all the time (hover and selected states, rebuilt lists).
---@field checked_while_hidden boolean? Whether to check these after every update even while hidden: the frames of windows that open inside the always-showing main interface, which the game resets as the window opens. There are few of them.

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
        -- Big windows like Settings, and plugin windows: the frame and the title banner.
        name = "big_windows",
        patterns = { "^RS3_PARENT_FRAME_", "^RS3_PARENT_BANNER_" },
        window_contents = false,
        checked_while_hidden = true,
    },
    {
        -- Modal windows like the Bank and plugins' settings windows: the frame and title bar.
        name = "modal_windows",
        patterns = { "^RS3_MAIN_MODAL_", "^RS3_MODAL_WINDOW_1_" },
        window_contents = false,
        checked_while_hidden = true,
    },
    {
        -- The edges and corners of the frames inside windows, like around the Bank's item area and
        -- side panels, and round the boxes in plugins' windows.
        name = "content_frames",
        patterns = { "^RS3_PARENT_CONTENT_TAB_FRAME_%d$", "^RS3_CONTENT_FRAME_%d$" },
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
        -- Not sprites: text (labels, and buttons', checkboxes' and input boxes' text) gets the old
        -- colour from skin_palette too, like headings and descriptions.
        name = "text_colours",
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

-- What players can turn on and off in the settings, each a few groups. Every group is in one.
---@class SpriteGroupOption
---@field key string Saved under this name.
---@field label string
---@field tooltip string
---@field groups string[]

---@type SpriteGroupOption[]
sprite_groups.options = {
    {
        key = "frames",
        label = "Window frames",
        tooltip = "The frames, title bars and tabs of windows, like docked windows, Settings and the Bank",
        groups = { "docked_windows", "big_windows", "modal_windows", "content_frames", "tabs" },
    },
    {
        key = "backgrounds",
        label = "Window backgrounds",
        tooltip = "The backgrounds of windows, and the coloured panels in their lists",
        groups = { "backgrounds", "colours" },
    },
    {
        key = "controls",
        label = "Buttons and controls",
        tooltip = "Buttons, dropdowns, list rows, checkboxes, input boxes, sliders and scrollbars",
        groups = { "buttons", "dropdowns", "rows", "styled_controls", "sliders_and_scrollbars" },
    },
    {
        key = "text_colours",
        label = "Text colours",
        tooltip = "The old colours of headings, descriptions and button text. Turn off to keep the new ones, which some find easier to read",
        groups = { "text_colours" },
    },
}

-- The names of the groups in the options that are on.
---@param is_on fun(option_key: string): boolean
---@return table<string, boolean>
function sprite_groups.names(is_on)
    local names = {}
    for _, option in ipairs(sprite_groups.options) do
        if is_on(option.key) then
            for _, group_name in ipairs(option.groups) do
                names[group_name] = true
            end
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

---@param group_name string
---@return boolean
function sprite_groups.is_checked_while_hidden(group_name)
    for _, group in ipairs(sprite_groups.all) do
        if group.name == group_name then
            return group.checked_while_hidden == true
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
