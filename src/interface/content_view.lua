-- The plugin's page, opened with its icon in the ribbon: a button that opens the settings window.
local settings_window = require("src/interface/settings_window")

local content_view = {}

local subscription_name = "old-interface-content"

---@type table?
local view = nil

-- Starts showing the page when the player opens it.
function content_view.start()
    Event.ContentLayerReady.Subscribe(subscription_name, function (event)
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
        view:AddSimpleButton("Open settings", function ()
            settings_window.open()
        end)
    end)
end

function content_view.stop()
    Event.ContentLayerReady.Unsubscribe(subscription_name)
    if view then
        view:Destroy()
        view = nil
    end
end

return content_view
