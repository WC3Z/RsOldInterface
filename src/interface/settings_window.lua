-- The plugin's settings, in a movable window of their own, so the interface can be seen changing
-- behind it. Opened from the plugin's page (see content_view). Three tabs: which parts of the
-- interface get the old look, in which colours, and the text colours.
local sprite_groups = require("src/game/sprite_groups")
local colour_scheme = require("src/game/colour_scheme")
local settings = require("src/database/settings")
local guard = require("src/game/guard")

local settings_window = {}

local subscription_name = "old-interface-settings-window"

local tab_labels = { "Look", "Colours", "Text" }
local colours_tab = 2

local min_width = 380
local min_height = 240
local combo_width = 220
local colour_label_width = 150
local hex_field_width = 110

---@type table?
local window = nil
---@type table?
local tabs = nil
-- The tab that's open, also the next time the window opens.
local open_tab = 1
-- Called after a setting changed (see settings_window.start).
---@type fun()
local on_change = function () end
-- Whether the window is to be built again before the next update (see build_again_soon).
local builds_again = false
-- Whether the window has been opened, which is when it starts listening for the Escape key.
local listens_for_escape = false

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
-- row with a label, the picker and the value. A colour that can be left unset shows no value
-- then, and the picker a colour to start from.
---@class ColourChoice
---@field show fun(rgb: integer?) Shows a colour (or none, for one that's unset) without it counting as chosen.

---@class ColourChoiceOptions
---@field label string
---@field rgb integer? The colour to start with, or nil for one that's unset.
---@field unset_rgb integer? What the picker shows while the colour is unset. With it, clearing the value unsets the colour.
---@field on_chosen fun(rgb: integer)
---@field on_unset fun()? Called when the value is cleared.

---@param page table A tab's page.
---@param options ColourChoiceOptions
---@return ColourChoice
local function add_colour_choice(page, options)
    local can_be_unset = options.unset_rgb ~= nil
    local shown_rgb = options.rgb
    local picker, hex_field

    local function show(new_rgb)
        shown_rgb = new_rgb
        -- Without telling their listeners, which would count it as chosen.
        if picker and picker.SetValue then
            picker:SetValue(picker_colour(new_rgb or options.unset_rgb), false)
        end
        if hex_field and hex_field.SetText then
            hex_field:SetText(new_rgb and hex_text(new_rgb) or "", false)
        end
    end

    page:AddText({ text = options.label, width = colour_label_width })
    picker = page:AddColourPicker({
        inline = true,
        value = picker_colour(options.rgb or options.unset_rgb),
        onChange = function (_, rgba)
            show(math.floor(rgba / 256))
            options.on_chosen(shown_rgb)
        end,
    })
    hex_field = page:AddTextField({
        inline = true,
        text = options.rgb and hex_text(options.rgb) or "",
        placeholder = can_be_unset and "scheme's" or nil,
        width = hex_field_width,
        maxLength = 7,
        tooltip = can_be_unset and "Type a colour like #4A87FF and press Enter. Clear it to use the scheme's"
            or "Type a colour like #4A87FF and press Enter",
        onSubmit = function (_, text)
            local typed_rgb = typed_colour(text)
            if typed_rgb then
                show(typed_rgb)
                options.on_chosen(typed_rgb)
            elseif can_be_unset and text:match("^%s*$") then
                show(nil)
                if options.on_unset then
                    options.on_unset()
                end
            else
                show(shown_rgb)
            end
        end,
    })
    return { show = show }
end

-- Builds the window again before the next update, on the tab it's on. Not right away: this is
-- called from the window's own controls, which building it again destroys.
local function build_again_soon()
    builds_again = true
end

---@param page table A tab's page.
local function add_look_options(page)
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

    local window_look_items = {
        {
            text = "Textured panels",
            value = "textured_panels",
            selected = settings.has_textured_panels(),
            tooltip = "The Bank's item area and panels like it show the window's texture, as before 2019. Off: the plain blue they had from 2019 to 2026",
        },
        {
            text = "Title plates",
            value = "title_plates",
            selected = settings.shows_title_plates(),
            tooltip = "The red plate behind the title of big windows like Settings",
        },
    }
    local set_window_look = { textured_panels = settings.set_textured_panels, title_plates = settings.set_title_plates }
    page:AddCheckboxButton(window_look_items, {
        width = (prettyui.CheckboxButton.getSize(window_look_items)),
        onChange = function (_, _, key, selected)
            set_window_look[key](selected)
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

-- The player's own colours for parts of the interface, on top of whichever scheme is chosen.
---@param page table A tab's page.
local function add_part_colour_choices(page)
    page:AddTitle("Your own colours")
    page:AddText("Give a part of the interface a colour of your own, in any scheme. A part with no value has the scheme's; clear a value and press Enter to go back to it.")

    -- What a part's picker starts from while it has the scheme's colour.
    local scheme_rgb = settings.tint() or colour_scheme.default_custom_tint
    ---@type table<string, ColourChoice>
    local choices = {}
    for _, part in ipairs(sprite_groups.colour_parts) do
        choices[part.key] = add_colour_choice(page, {
            label = part.label,
            rgb = settings.part_tint(part.key),
            unset_rgb = scheme_rgb,
            on_chosen = function (rgb)
                settings.set_part_tint(part.key, rgb)
                on_change()
            end,
            on_unset = function ()
                settings.set_part_tint(part.key, nil)
                on_change()
            end,
        })
    end

    page:AddSimpleButton("Use the scheme's colours for all parts", function ()
        for _, part in ipairs(sprite_groups.colour_parts) do
            settings.set_part_tint(part.key, nil)
            choices[part.key].show(nil)
        end
        on_change()
    end)
end

---@param page table A tab's page.
local function add_colour_scheme_choice(page)
    page:AddTitle("Colour scheme")
    page:AddText("Classic blue and DarkScape use their own art. The others are one colour; Custom lets you pick it.")

    local entries = {}
    for index, scheme in ipairs(colour_scheme.all) do
        entries[index] = { label = scheme.label, id = index }
    end
    page:AddComboBox({
        entries = entries,
        selectedID = scheme_index(settings.colour_scheme()),
        width = combo_width,
        -- The text above is laid out a little short for its last line.
        marginTop = 12,
        onChange = function (_, index)
            local scheme = colour_scheme.all[index]
            if scheme == nil then
                return
            end
            settings.set_colour_scheme(scheme.key)
            on_change()
            -- What the page shows goes with the scheme: the custom one's colour to pick, and the
            -- colour the parts' pickers start from.
            build_again_soon()
        end,
    })
    if settings.colour_scheme() == colour_scheme.custom_key then
        add_colour_choice(page, {
            label = "Its colour",
            rgb = settings.custom_tint(),
            on_chosen = function (rgb)
                settings.set_custom_tint(rgb)
                on_change()
                build_again_soon()
            end,
        })
    end
end

---@param page table A tab's page.
local function add_text_colour_choice(page)
    page:AddTitle("Text colours")
    page:AddText("Your own colours for headings and for other text, in any colour scheme. They need Text colours to be on in the Look tab.")

    local heading_choice = add_colour_choice(page, {
        label = "Headings",
        rgb = settings.heading_text(),
        on_chosen = function (rgb)
            settings.set_heading_text(rgb)
            settings.set_own_text_colours(true)
            on_change()
        end,
    })
    local body_choice = add_colour_choice(page, {
        label = "Other text",
        rgb = settings.body_text(),
        on_chosen = function (rgb)
            settings.set_body_text(rgb)
            settings.set_own_text_colours(true)
            on_change()
        end,
    })
    page:AddSimpleButton("Use the scheme's text colours", function ()
        settings.set_own_text_colours(false)
        settings.set_heading_text(colour_scheme.default_heading_text)
        settings.set_body_text(colour_scheme.default_body_text)
        heading_choice.show(colour_scheme.default_heading_text)
        body_choice.show(colour_scheme.default_body_text)
        on_change()
    end)
end

-- The main game screen, so the window can be moved anywhere over the game.
---@return ui.Component?
local function game_area()
    return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
end

---@param closing table The prettyui window.
local function save_bounds(closing)
    settings.set_window_bounds(closing.root.x, closing.root.y, closing.root.width, closing.root.height)
end

-- prettyui's tabs keep the height they're made with, and it has no callback for a window being
-- resized, so the window's SetSize (which resizing calls) is wrapped: selecting the open tab again
-- makes prettyui measure every tab again.
local function refresh_tabs_on_resize()
    local set_size = window.SetSize
    window.SetSize = function (self, width, height)
        set_size(self, width, height)
        if tabs then
            tabs:SetActive(tabs:GetActiveIndex(), false)
        end
    end
end

-- Opens the window, or a fresh one if it's open already, where it was and at the size it had when
-- it was last closed.
function settings_window.open()
    settings_window.close()
    local parent = game_area()
    if parent == nil then
        return
    end
    local x, y = settings.window_position()
    local width, height = settings.window_size()
    window = prettyui.Window.new(parent, {
        categoryID = "auto",
        title = "Old Interface settings",
        x = x,
        y = y,
        width = width,
        height = height,
        resizable = true,
        minWidth = min_width,
        minHeight = min_height,
        -- Each tab scrolls on its own.
        scrollable = false,
        destroyOnClose = true,
        onClose = function (closing)
            save_bounds(closing)
            window = nil
            tabs = nil
        end,
    })
    refresh_tabs_on_resize()
    tabs = window:AddTabs(tab_labels, {
        activeIndex = open_tab,
        y = 0,
        height = 0,
        heightAnchor = 1.0,
        onChange = function (_, index)
            open_tab = index
        end,
    })
    add_look_options(tabs:GetPage(1))
    add_colour_scheme_choice(tabs:GetPage(colours_tab))
    add_part_colour_choices(tabs:GetPage(colours_tab))
    add_text_colour_choice(tabs:GetPage(3))

    -- Escape closes the window, like the game's own. Subscribed once and left so: it does nothing
    -- without a window.
    if not listens_for_escape then
        listens_for_escape = true
        Event.KeyDown.Subscribe(subscription_name, guard.guarded("closing the settings window", function (event)
            if window and not event.isRepeat and event.gameKey == GameKey.ESCAPE then
                window:Close()
            end
        end))
    end
end

function settings_window.close()
    builds_again = false
    if window then
        save_bounds(window)
        window:Destroy()
        window = nil
        tabs = nil
    end
end

-- Gets the window ready to be opened.
---@param changed fun() Called after a setting changed.
function settings_window.start(changed)
    on_change = changed
    Event.Logic.Subscribe(subscription_name, guard.guarded("building the settings window again", function ()
        if builds_again and window then
            settings_window.open()
        end
        builds_again = false
    end))
end

function settings_window.stop()
    Event.Logic.Unsubscribe(subscription_name)
    -- Only if it was subscribed: unsubscribing from an event that wasn't can crash the client.
    if listens_for_escape then
        Event.KeyDown.Unsubscribe(subscription_name)
        listens_for_escape = false
    end
    settings_window.close()
end

return settings_window
