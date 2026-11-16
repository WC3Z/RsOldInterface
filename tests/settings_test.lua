-- The settings page against a fake prettyui and PersistentDB.
package.path = "./?.lua;" .. package.path
local stored = { option_backgrounds = false }
PersistentDB = {
    GetBool = function (_, key) return stored[key] end,
    SetBool = function (_, key, value) stored[key] = value; return true end,
}
local handler
Event = { SettingsLayerReady = {
    Subscribe = function (_, f) handler = f end,
    Unsubscribe = function () handler = nil end,
} }
local shown
prettyui = {
    CheckboxButton = { getSize = function () return 200, 100 end },
    SimpleView = { new = function ()
        return {
            AddTitle = function () end,
            AddText = function () end,
            AddCheckboxButton = function (_, items, options) shown = { items = items, options = options } end,
            Destroy = function () end,
        }
    end },
}

local sprite_groups = require("src/game/sprite_groups")
local settings = require("src/database/settings")
local view = require("src/interface/settings_view")
local changes = 0
view.start(function () changes = changes + 1 end)
handler({ component = { width = 400, height = 300 } })

assert(#shown.items == #sprite_groups.options, "every option is shown")
for _, item in ipairs(shown.items) do
    assert(item.selected == (item.value ~= "backgrounds"), item.value .. " shows its saved state")
end

shown.options.onChange(nil, {}, "text_colours", false)
assert(stored.option_text_colours == false, "turning text colours off is saved")
assert(not settings.is_on("text_colours"), "and read back")
assert(changes == 1, "the swapping starts again")

-- Opening the page again builds it again, from the saved states.
handler({ component = { width = 400, height = 300 } })
for _, item in ipairs(shown.items) do
    if item.value == "text_colours" then
        assert(not item.selected, "text colours shows as off")
    end
end

view.stop()
assert(handler == nil, "stops listening")
