-- The plugin's settings page, opened from the gear on its row in the Plugin Hub: which parts of
-- the interface get the old look, and in which colour scheme.
local sprite_groups = require("src/game/sprite_groups")
local colour_scheme = require("src/game/colour_scheme")
local settings = require("src/database/settings")

local settings_view = {}

local subscription_name = "old-interface-settings"

---@type table?
local view = nil

local combo_width = 220
local hex_field_width = 110

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

-- A colour the player chooses with a picker, or by typing its hex value and pressing Enter.
---@class ColourChoice
---@field show fun(rgb: integer) Shows a colour without it counting as chosen.

---@param page table The prettyui view.
---@param label string
---@param rgb integer The colour to start with.
---@param on_chosen fun(rgb: integer)
---@return ColourChoice
local function add_colour_choice(page, label, rgb, on_chosen)
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

    page:AddText(label)
    picker = page:AddColourPicker({
        value = picker_colour(rgb),
        onChange = function (_, rgba)
            show(math.floor(rgba / 256))
            on_chosen(shown_rgb)
        end,
    })
    hex_field = page:AddTextField({
        text = hex_text(rgb),
        width = hex_field_width,
        maxLength = 7,
        tooltip = "Type a colour like #4A87FF and press Enter",
        onSubmit = function (_, text)
            local typed_rgb = typed_colour(text)
            show(typed_rgb or shown_rgb)
            if typed_rgb then
                on_chosen(typed_rgb)
            end
        end,
    })
    return { show = show }
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

---@param page table The prettyui view.
---@param on_change fun()
local function add_colour_scheme_choice(page, on_change)
    page:AddTitle("Colour scheme")
    page:AddText("Classic blue draws the old interface as it was. The other schemes draw it in one colour, so its gold and red details take that colour too.")

    local entries = {}
    for index, scheme in ipairs(colour_scheme.all) do
        entries[index] = { label = scheme.label, id = index }
    end
    local dropdown = page:AddComboBox({
        entries = entries,
        selectedID = scheme_index(settings.colour_scheme()),
        width = combo_width,
        onChange = function (_, index)
            local scheme = colour_scheme.all[index]
            if scheme then
                settings.set_colour_scheme(scheme.key)
                on_change()
            end
        end,
    })

    add_colour_choice(page, "Your own colour, for the Custom scheme:", settings.custom_tint(), function (rgb)
        settings.set_custom_tint(rgb)
        settings.set_colour_scheme(colour_scheme.custom_key)
        if dropdown and dropdown.Select then
            dropdown:Select(scheme_index(colour_scheme.custom_key), false)
        end
        on_change()
    end)
end

---@param page table The prettyui view.
---@param on_change fun()
local function add_text_colour_choice(page, on_change)
    page:AddTitle("Text colours")
    page:AddText("Your own colours for headings and for other text, in any colour scheme. They need the Text colours option above to be on.")

    local heading_choice = add_colour_choice(page, "Headings:", settings.heading_text(), function (rgb)
        settings.set_heading_text(rgb)
        settings.set_own_text_colours(true)
        on_change()
    end)
    local body_choice = add_colour_choice(page, "Other text:", settings.body_text(), function (rgb)
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

-- Starts showing the settings page when the player opens it.
---@param on_change fun() Called after an option is turned on or off.
function settings_view.start(on_change)
    Event.SettingsLayerReady.Subscribe(subscription_name, function (event)
        -- This runs every time the page is opened, so throw away the old one first.
        if view then
            view:Destroy()
        end

        local parent = event.component
        view = prettyui.SimpleView.new(parent, {
            categoryID = "auto",
            width = parent.width,
            height = parent.height,
        })
        view:AddTitle("Old Interface")
        view:AddText("Which parts of the interface get the blue look from before January 2026. Changes show right away.")

        local items = {}
        for _, option in ipairs(sprite_groups.options) do
            items[#items + 1] = {
                text = option.label,
                value = option.key,
                selected = settings.is_on(option.key),
                tooltip = option.tooltip,
            }
        end
        view:AddCheckboxButton(items, {
            width = (prettyui.CheckboxButton.getSize(items)),
            onChange = function (_, _, option_key, selected)
                settings.set_on(option_key, selected)
                on_change()
            end,
        })
        add_colour_scheme_choice(view, on_change)
        add_text_colour_choice(view, on_change)
    end)
end

function settings_view.stop()
    Event.SettingsLayerReady.Unsubscribe(subscription_name)
    if view then
        view:Destroy()
        view = nil
    end
end

return settings_view
