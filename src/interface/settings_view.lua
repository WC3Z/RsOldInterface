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

    page:AddText("Your own colour, for the Custom scheme:")
    page:AddColourPicker({
        -- The picker's colours have transparency too (0xRRGGBBAA).
        value = settings.custom_tint() * 256 + 0xFF,
        onChange = function (_, rgba)
            settings.set_custom_tint(math.floor(rgba / 256))
            settings.set_colour_scheme(colour_scheme.custom_key)
            if dropdown and dropdown.Select then
                dropdown:Select(scheme_index(colour_scheme.custom_key), false)
            end
            on_change()
        end,
    })
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
