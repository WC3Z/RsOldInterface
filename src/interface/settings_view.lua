-- The plugin's settings page, opened from the gear on its row in the Plugin Hub, in three tabs:
-- which parts of the interface get the old look, in which colours, and the text colours.
local sprite_groups = require("src/game/sprite_groups")
local colour_scheme = require("src/game/colour_scheme")
local settings = require("src/database/settings")
local guard = require("src/game/guard")

local settings_view = {}

local subscription_name = "old-interface-settings"

local tab_labels = { "Look", "Colours", "Text" }
local colours_tab = 2

local combo_width = 220
local colour_label_width = 150
local hex_field_width = 110

---@type table?
local view = nil
-- The game's component the page was last built in.
---@type ui.Component?
local page_parent = nil
-- The tab to build the page again with, after a change to what it shows (see build_again_soon).
---@type integer?
local build_again_with_tab = nil

-- The picker's colours have transparency too (0xRRGGBBAA).
---@param rgb integer
---@return integer
local function picker_colour(rgb)
    return rgb * 256 + 0xFF
end

---@param rgb integer
---@return string
local function hex_text(rgb)
    return string.format("#%06X", rgb)
end

-- The colour typed as "#4A87FF" or "4A87FF", or nil if it isn't one.
---@param text string
---@return integer?
local function typed_colour(text)
    local digits = text:match("^%s*#?(%x%x%x%x%x%x)%s*$")
    return digits and tonumber(digits, 16) or nil
end

-- A colour the player chooses with a picker, or by typing its hex value and pressing Enter: a
-- row with a label, the picker and the value.
---@class ColourChoice
---@field show fun(rgb: integer) Shows a colour without it counting as chosen.

---@param page table The prettyui view or tab page.
---@param label string
---@param rgb integer The colour to start with.
---@param on_chosen fun(rgb: integer)
---@param on_cleared (fun(): integer)? Called when the hex value is cleared; returns the colour to show then. Without it, clearing changes nothing.
---@return ColourChoice
local function add_colour_choice(page, label, rgb, on_chosen, on_cleared)
    local shown_rgb = rgb
    local picker, hex_field

    local function show(new_rgb)
        shown_rgb = new_rgb
        -- Without telling their listeners, which would count it as chosen.
        if picker and picker.SetValue then
            picker:SetValue(picker_colour(new_rgb), false)
        end
        if hex_field and hex_field.SetText then
            hex_field:SetText(hex_text(new_rgb), false)
        end
    end

    page:AddText({ text = label, width = colour_label_width })
    picker = page:AddColourPicker({
        inline = true,
        value = picker_colour(rgb),
        onChange = function (_, rgba)
            show(math.floor(rgba / 256))
            on_chosen(shown_rgb)
        end,
    })
    hex_field = page:AddTextField({
        inline = true,
        text = hex_text(rgb),
        width = hex_field_width,
        maxLength = 7,
        tooltip = "Type a colour like #4A87FF and press Enter",
        onSubmit = function (_, text)
            local typed_rgb = typed_colour(text)
            if typed_rgb then
                show(typed_rgb)
                on_chosen(typed_rgb)
            elseif on_cleared and text:match("^%s*$") then
                show(on_cleared())
            else
                show(shown_rgb)
            end
        end,
    })
    return { show = show }
end

-- Builds the page again before the next update, showing the given tab. Not right away: this is
-- called from the page's own controls, which building it again destroys.
---@param tab integer
local function build_again_soon(tab)
    build_again_with_tab = tab
end

---@param page table The prettyui view or tab page.
---@param on_change fun()
local function add_look_options(page, on_change)
    page:AddTitle("Old Interface")
    page:AddText("Which parts of the interface get the look from before January 2026. Changes show right away.")

    local items = {}
    for _, option in ipairs(sprite_groups.options) do
        items[#items + 1] = {
            text = option.label,
            value = option.key,
            selected = settings.is_on(option.key),
            tooltip = option.tooltip,
        }
    end
    page:AddCheckboxButton(items, {
        width = (prettyui.CheckboxButton.getSize(items)),
        onChange = function (_, _, option_key, selected)
            settings.set_on(option_key, selected)
            on_change()
        end,
    })
end

-- The index of a colour scheme in colour_scheme.all, which is what the dropdown knows it by.
---@param key string
---@return integer
local function scheme_index(key)
    for index, scheme in ipairs(colour_scheme.all) do
        if scheme.key == key then
            return index
        end
    end
    return 1
end

-- The custom scheme's colours: one for everything, and one for each part of the interface that
-- should differ from it.
---@param page table The prettyui view or tab page.
---@param on_change fun()
local function add_custom_scheme_colours(page, on_change)
    page:AddTitle("Custom colours")
    page:AddText("The main colour is for everything. Give a part its own colour to make it differ; to have it follow the main colour again, clear its value and press Enter.")

    ---@type table<string, ColourChoice>
    local part_choices = {}

    local function show_main_colour_for_followers()
        for _, part in ipairs(sprite_groups.colour_parts) do
            if settings.part_tint(part.key) == nil then
                part_choices[part.key].show(settings.custom_tint())
            end
        end
    end

    add_colour_choice(page, "Main colour", settings.custom_tint(), function (rgb)
        settings.set_custom_tint(rgb)
        show_main_colour_for_followers()
        on_change()
    end)
    for _, part in ipairs(sprite_groups.colour_parts) do
        part_choices[part.key] = add_colour_choice(page, part.label, settings.part_tint(part.key) or settings.custom_tint(),
            function (rgb)
                settings.set_part_tint(part.key, rgb)
                on_change()
            end,
            function ()
                settings.set_part_tint(part.key, nil)
                on_change()
                return settings.custom_tint()
            end)
    end

    page:AddSimpleButton("All parts follow the main colour", function ()
        for _, part in ipairs(sprite_groups.colour_parts) do
            settings.set_part_tint(part.key, nil)
        end
        show_main_colour_for_followers()
        on_change()
    end)
end

---@param page table The prettyui view or tab page.
---@param on_change fun()
local function add_colour_scheme_choice(page, on_change)
    page:AddTitle("Colour scheme")
    page:AddText("Classic blue draws the old interface as it was. The other schemes draw it in one colour, so its gold and red details take that colour too. Choose Custom to pick the colours yourself.")

    local entries = {}
    for index, scheme in ipairs(colour_scheme.all) do
        entries[index] = { label = scheme.label, id = index }
    end
    local was_custom = settings.colour_scheme() == colour_scheme.custom_key
    page:AddComboBox({
        entries = entries,
        selectedID = scheme_index(settings.colour_scheme()),
        width = combo_width,
        onChange = function (_, index)
            local scheme = colour_scheme.all[index]
            if scheme == nil then
                return
            end
            settings.set_colour_scheme(scheme.key)
            on_change()
            -- The custom scheme's colours are only there to pick while it's chosen.
            if (scheme.key == colour_scheme.custom_key) ~= was_custom then
                build_again_soon(colours_tab)
            end
        end,
    })
    if was_custom then
        add_custom_scheme_colours(page, on_change)
    end
end

---@param page table The prettyui view or tab page.
---@param on_change fun()
local function add_text_colour_choice(page, on_change)
    page:AddTitle("Text colours")
    page:AddText("Your own colours for headings and for other text, in any colour scheme. They need Text colours to be on in the Look tab.")

    local heading_choice = add_colour_choice(page, "Headings", settings.heading_text(), function (rgb)
        settings.set_heading_text(rgb)
        settings.set_own_text_colours(true)
        on_change()
    end)
    local body_choice = add_colour_choice(page, "Other text", settings.body_text(), function (rgb)
        settings.set_body_text(rgb)
        settings.set_own_text_colours(true)
        on_change()
    end)
    page:AddSimpleButton("Use the scheme's text colours", function ()
        settings.set_own_text_colours(false)
        settings.set_heading_text(colour_scheme.default_heading_text)
        settings.set_body_text(colour_scheme.default_body_text)
        heading_choice.show(colour_scheme.default_heading_text)
        body_choice.show(colour_scheme.default_body_text)
        on_change()
    end)
end

---@param parent ui.Component
---@param on_change fun()
---@param shown_tab integer
local function build(parent, on_change, shown_tab)
    if view then
        view:Destroy()
    end
    page_parent = parent
    view = prettyui.SimpleView.new(parent, {
        categoryID = "auto",
        width = parent.width,
        height = parent.height,
        -- Each tab scrolls on its own.
        scrollable = false,
    })
    local tabs = view:AddTabs(tab_labels, { height = parent.height, activeIndex = shown_tab })
    add_look_options(tabs:GetPage(1), on_change)
    add_colour_scheme_choice(tabs:GetPage(colours_tab), on_change)
    add_text_colour_choice(tabs:GetPage(3), on_change)
end

-- Starts showing the settings page when the player opens it.
---@param on_change fun() Called after a setting changed.
function settings_view.start(on_change)
    -- This runs every time the page is opened, and builds it from the start.
    Event.SettingsLayerReady.Subscribe(subscription_name, function (event)
        build_again_with_tab = nil
        build(event.component, on_change, 1)
    end)
    Event.Logic.Subscribe(subscription_name, guard.guarded("building the settings page again", function ()
        local shown_tab = build_again_with_tab
        if shown_tab and page_parent then
            build_again_with_tab = nil
            build(page_parent, on_change, shown_tab)
        end
    end))
end

function settings_view.stop()
    Event.SettingsLayerReady.Unsubscribe(subscription_name)
    Event.Logic.Unsubscribe(subscription_name)
    build_again_with_tab = nil
    page_parent = nil
    if view then
        view:Destroy()
        view = nil
    end
end

return settings_view
