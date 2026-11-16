-- The plugin's settings page, opened from the gear on its row in the Plugin Hub: which parts of
-- the interface get the old look.
local sprite_groups = require("src/game/sprite_groups")
local settings = require("src/database/settings")

local settings_view = {}

local subscription_name = "old-interface-settings"

---@type table?
local view = nil

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
