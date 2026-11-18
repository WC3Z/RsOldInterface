-- The settings page against a fake prettyui and PersistentDB.
package.path = "./?.lua;" .. package.path
local stored = { option_backgrounds = false }
PersistentDB = {
    GetBool = function (_, key) return stored[key] end,
    SetBool = function (_, key, value) stored[key] = value; return true end,
    GetString = function (_, key) return stored[key] or "" end,
    SetString = function (_, key, value) stored[key] = value; return true end,
}
local handler
Event = { SettingsLayerReady = {
    Subscribe = function (_, f) handler = f end,
    Unsubscribe = function () handler = nil end,
} }
local shown
local dropdown, picker
local selected_in_dropdown
prettyui = {
    CheckboxButton = { getSize = function () return 200, 100 end },
    SimpleView = { new = function ()
        return {
            AddTitle = function () end,
            AddText = function () end,
            AddCheckboxButton = function (_, items, options) shown = { items = items, options = options } end,
            AddComboBox = function (_, options)
                dropdown = options
                return { Select = function (_, index) selected_in_dropdown = index end }
            end,
            AddColourPicker = function (_, options) picker = options end,
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

-- The colour scheme: classic until another is chosen.
local colour_scheme = require("src/game/colour_scheme")
assert(settings.colour_scheme() == "classic" and settings.tint() == nil, "classic, untinted, when nothing is saved")
assert(colour_scheme.all[dropdown.selectedID].key == "classic", "the dropdown shows the classic scheme")
assert(#dropdown.entries == #colour_scheme.all, "every scheme is in the dropdown")
assert(picker.value == colour_scheme.default_custom_tint * 256 + 0xFF, "the picker shows the default colour")

local crimson_index
for index, scheme in ipairs(colour_scheme.all) do
    if scheme.key == "crimson" then crimson_index = index end
end
dropdown.onChange(nil, crimson_index)
assert(settings.colour_scheme() == "crimson" and settings.tint() == colour_scheme.all[crimson_index].tint, "choosing a scheme is saved")
assert(changes == 2, "and the swapping starts again")

picker.onChange(nil, 0x102030FF)
assert(settings.colour_scheme() == "custom", "picking a colour chooses the custom scheme")
assert(settings.tint() == 0x102030, "with the picked colour as its tint")
assert(colour_scheme.all[selected_in_dropdown].key == "custom", "and the dropdown shows it")

stored.colour_scheme = "gone"
assert(settings.colour_scheme() == "classic", "a scheme that no longer exists falls back to classic")

-- What the schemes do to colours.
assert(colour_scheme.multiplied(0xFFFFFF, 0xFF8040) == 0xFF8040, "an untinted part takes the tint")
assert(colour_scheme.multiplied(0x808080, 0xFF0000) == 0x800000, "the game's own tint stays under it")
assert(colour_scheme.tinted(0x152648, 0xFF0000) == 0x480000, "a plain colour keeps its brightness in the tint's colour")
assert(colour_scheme.tinted_text(0xFCC907, 0xFF0000) == 0xFCC907, "gold text stays gold")
local body_text = colour_scheme.tinted_text(0xA6C7D6, 0xFF0000)
assert(body_text >> 16 == 0xD6 and body_text & 0xFF < 0xD6, "blue-grey text leans to the tint and stays light")

view.stop()
assert(handler == nil, "stops listening")
