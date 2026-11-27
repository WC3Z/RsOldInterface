-- The sprites the plugin can swap, in groups that can be turned on and off separately (see
-- sprite_groups.options). A sprite belongs to the first group with a matching name pattern.
local sprite_groups = {}

---@class SpriteGroup
---@field name string
---@field patterns string[]
---@field changes_often boolean Whether the game changes these all the time (hover and selected states, rebuilt lists).
---@field checked_while_hidden boolean? Whether to check these after every update even while hidden (see below).

-- Groups checked while hidden are the frames of windows that open inside the always-showing main
-- interface: the game resets them as the window opens, and there are few of them.
---@type SpriteGroup[]
sprite_groups.all = {
    {
        name = "sliders_and_scrollbars",
        -- Before the docked windows, whose pattern matches their scrollbars too.
        patterns = { "^RS3_SLIDER_", "^SCROLLBAR_", "^RS3_CHILD_SCROLL_BAR_" },
        changes_often = true,
    },
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
            -- Big windows' side tabs (Hiscores, Hero's Achievements).
            "^RS3_PARENT_SIDE_TAB_UNSELECTED",
            "^RS3_PARENT_SIDE_TAB_CURRENT$",
        },
        changes_often = true,
    },
    {
        name = "docked_windows",
        patterns = { "^RS3_CHILD_", "^RS3_HUD_WINDOW_", "^RS3_GHOST_COMPACT_" },
        changes_often = false,
    },
    {
        -- Tiles the game repeats to fill a window, or the middle of a frame built from 3x3 pieces
        -- (piece 4), which the game stretches to fill the frame, so they fit whatever their size.
        name = "backgrounds",
        patterns = { "^RS3_[A-Z_]*CONTENT_TILE$", "^RS3_CONTENT_FRAME_4$", "^RS3_PARENT_CONTENT_TAB_FRAME_4$", "^OLD_BACKGROUND_TEXTURE$" },
        changes_often = false,
    },
    {
        -- Big windows like Settings, and plugin windows: the frame and the title banner.
        name = "big_windows",
        patterns = { "^RS3_PARENT_FRAME_", "^RS3_PARENT_BANNER_" },
        changes_often = false,
        checked_while_hidden = true,
    },
    {
        -- Modal windows like the Bank and plugins' settings windows: the frame and title bar.
        name = "modal_windows",
        patterns = { "^RS3_MAIN_MODAL_", "^RS3_MODAL_WINDOW_1_" },
        changes_often = false,
        checked_while_hidden = true,
    },
    {
        -- The edges and corners of the frames inside windows, like around the Bank's item area and
        -- side panels, and round the boxes in plugins' windows.
        name = "content_frames",
        patterns = { "^RS3_PARENT_CONTENT_TAB_FRAME_%d$", "^RS3_CONTENT_FRAME_%d$" },
        changes_often = false,
    },
    {
        name = "dropdowns",
        patterns = { "^RS3_BTN_DROPDOWN_" },
        changes_often = true,
    },
    {
        name = "buttons",
        -- STATS_BACKGROUND_BUTTON_*: the cells behind each skill in the Skills window.
        -- AIF_RING_BTN_1_*: the round tab buttons of the tool belt. They looked the same before
        -- the overhaul, and are swapped so colour schemes colour them too.
        patterns = { "^RS3_BTN_", "^RS3_BUTTON_CLOSE_", "^RS3_BUTTON_LOGOUT_", "^BUTTON_30PX_[A-Z]+$", "^STATS_BACKGROUND_BUTTON_", "^AIF_RING_BTN_1_%d$" },
        changes_often = true,
    },
    {
        name = "rows",
        -- AIF_SKILL_SELECT_BTN_1_0/1: the rows of the skill guide (Hero, Skills tab), normal and hovered.
        -- AIF_BRONZE_MOTTLED_BUTTON_*: the rows of the Minigames list (Adventures). They looked the
        -- same before the overhaul, and are swapped so colour schemes colour them too.
        patterns = { "^RS3_CONTENT_CONTAINER_", "^RS3_CONTEXTUAL_INPUT_BOX_", "^AIF_SKILL_SELECT_BTN_1_[01]$", "^AIF_BRONZE_MOTTLED_BUTTON_%d$" },
        changes_often = true,
    },
    {
        -- The controls newer windows (like Settings' Gameplay tab) are built from, styled by the
        -- stylesheet of the same name. One sprite per control, holding all its states.
        name = "styled_controls",
        patterns = {
            "^CHECKBOX_DEFAULT$",
            "^BUTTON_CORNERED_[A-Z]+$",
            "^BUTTON_PANEL_DEFAULT$",
            "^BUTTON_PANEL_INACTIVE$",
            "^BUTTON_SIDE_TAB_53X70$",
            "^BACKGROUND_SIDE_TAB$",
            "^BUTTON_ACCORDION_%d+PX$",
            "^INPUT_SEARCHBOX_%d+PX$",
            "^INPUT_DEFAULT$",
            "^DROPDOWN_DEFAULT_[A-Z_]+$",
        },
        changes_often = true,
    },
    {
        -- Not sprites: plain coloured rectangles, like the cards in Settings' lists, get the old
        -- colour from skin_palette.
        name = "colours",
        patterns = {},
        changes_often = true,
    },
    {
        -- Not sprites: text (labels, and buttons', checkboxes' and input boxes' text) gets the old
        -- colour from skin_palette too, like headings and descriptions.
        name = "text_colours",
        patterns = {},
        changes_often = true,
    },
}

-- Sprites drawn with another sprite's image, as they have none of their own. Other plugins fill
-- their panels with the game's olive OLD_BACKGROUND_TEXTURE, which gets the old panels' plain
-- blue: an image is stretched over the whole panel, so a texture wouldn't do.
---@type table<string, string>
sprite_groups.image_names = {
    OLD_BACKGROUND_TEXTURE = "RS3_PARENT_CONTENT_TAB_FRAME_4",
    -- The panel buttons (used by other plugins too) were added after the old cache and have no
    -- mobile version. Their image has the same eight states, 24 pixels each, as the cornered
    -- button's, which has an old version.
    BUTTON_PANEL_DEFAULT = "BUTTON_CORNERED_NEUTRAL",
    BUTTON_PANEL_INACTIVE = "BUTTON_CORNERED_NEUTRAL",
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

-- The parts of the interface that can each have their own colour (see colour_scheme). A sprite
-- belongs to the first part with a matching name pattern, and to the frames if none matches.
---@class ColourPart
---@field key string Saved under this name.
---@field label string
---@field patterns string[]

sprite_groups.frames_part = "frames"
-- Plain coloured panels, which aren't sprites, belong to this part.
sprite_groups.panels_part = "backgrounds"

---@type ColourPart[]
sprite_groups.colour_parts = {
    { key = sprite_groups.frames_part, label = "Window frames", patterns = {} },
    {
        key = "title_bars",
        label = "Title bars",
        patterns = {
            "^RS3_PARENT_BANNER_",
            "^RS3_CHILD_[A-Z_]*HEADER_",
            "^RS3_GHOST_COMPACT_HEADER_",
            "^RS3_MAIN_MODAL_HEADER_",
            "^RS3_MODAL_WINDOW_1_TITLE_",
            "^RS3_MODAL_WINDOW_1_TOP_TILE$",
            "^RS3_MODAL_WINDOW_1_CLOSE_CORNER$",
            "^RS3_CHILD_[A-Z_]*TOP_[A-Z_]*TILE$",
            "^RS3_GHOST_COMPACT_TOP_TILE$",
        },
    },
    {
        key = "tabs",
        label = "Tabs",
        patterns = {
            "^RS3_CHILD_TAB_",
            "^RS3_PARENT_TAB_",
            "^RS3_PARENT_CONTENT_TILEABLE_TAB_%d+$",
            "^BANK_TABS_",
            "^RS3_BTN_CHILD_TAB_",
            "^RS3_PARENT_SIDE_TAB_UNSELECTED",
            "^RS3_PARENT_SIDE_TAB_CURRENT$",
            "^BUTTON_SIDE_TAB_",
        },
    },
    {
        key = sprite_groups.panels_part,
        label = "Backgrounds",
        patterns = { "^RS3_[A-Z_]*CONTENT_TILE$", "^RS3_CONTENT_FRAME_4$", "^RS3_PARENT_CONTENT_TAB_FRAME_4$", "^OLD_BACKGROUND_TEXTURE$", "^BACKGROUND_SIDE_TAB$" },
    },
    { key = "dropdowns", label = "Dropdowns", patterns = { "^RS3_BTN_DROPDOWN", "^DROPDOWN_" } },
    {
        key = "checkboxes",
        label = "Checkboxes and radio buttons",
        patterns = { "^RS3_BTN_CHECKBOX", "^RS3_BTN_RADIO", "^CHECKBOX_" },
    },
    { key = "scrollbars", label = "Scrollbars", patterns = { "^SCROLLBAR_", "^RS3_CHILD_SCROLL_BAR_" } },
    { key = "sliders", label = "Sliders", patterns = { "^RS3_BTN_ADJUST_SLIDER", "^RS3_SLIDER_" } },
    {
        key = "rows",
        label = "List rows and input boxes",
        patterns = { "^RS3_CONTENT_CONTAINER", "^RS3_CONTEXTUAL_INPUT_BOX", "^INPUT_", "^AIF_SKILL_SELECT_BTN_1_[01]$", "^AIF_BRONZE_MOTTLED_BUTTON_" },
    },
    {
        -- Before the buttons, whose patterns match these too.
        key = "small_buttons",
        label = "Close and +/- buttons",
        patterns = {
            "^RS3_BTN_[A-Z]+CREASE_",
            "^RS3_BTN_MODAL_WINDOW_1_CLOSE_",
            "^RS3_BUTTON_CLOSE_",
            "^RS3_BUTTON_LOGOUT_",
            "^RS3_CHILD_CLOSE_BUTTON_",
        },
    },
    { key = "buttons", label = "Buttons", patterns = { "^RS3_BTN_", "^RS3_BUTTON_", "^BUTTON_", "^STATS_BACKGROUND_BUTTON_", "^AIF_RING_BTN_1_%d$" } },
}

-- Sprites that keep their own colours in every colour scheme: a small picture in several colours,
-- like the red and yellow X of a window's close button, is a blob in one.
local own_colour_patterns = { "^RS3_BTN_MODAL_WINDOW_1_CLOSE_" }

---@param sprite_name string
---@return boolean
function sprite_groups.keeps_own_colours(sprite_name)
    for _, pattern in ipairs(own_colour_patterns) do
        if sprite_name:find(pattern) then
            return true
        end
    end
    return false
end

---@param sprite_name string
---@return string # The key of the colour part the sprite belongs to.
function sprite_groups.colour_part_of(sprite_name)
    for _, part in ipairs(sprite_groups.colour_parts) do
        for _, pattern in ipairs(part.patterns) do
            if sprite_name:find(pattern) then
                return part.key
            end
        end
    end
    return sprite_groups.frames_part
end

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
function sprite_groups.changes_often(group_name)
    for _, group in ipairs(sprite_groups.all) do
        if group.name == group_name then
            return group.changes_often
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
