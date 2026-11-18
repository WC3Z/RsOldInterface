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
local text_pickers, reset_text_colours = {}, nil
local hex_fields = {}
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
            AddColourPicker = function (_, options)
                -- The scheme's picker comes first, then the heading and body text ones.
                if picker == nil then
                    picker = options
                    return {}
                end
                local text_picker = { options = options, SetValue = function (self, value, notify) self.value = value; self.notified = notify end }
                text_pickers[#text_pickers + 1] = text_picker
                return text_picker
            end,
            AddTextField = function (_, options)
                local field = { options = options, SetText = function (self, text) self.text = text end }
                hex_fields[#hex_fields + 1] = field
                return field
            end,
            AddSimpleButton = function (_, _, action) reset_text_colours = action end,
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

-- A colour can be typed too. The first field is the scheme's, next to the picker used above.
local scheme_field = hex_fields[1]
assert(scheme_field.options.text == "#4A87FF", "the field starts with the colour as hex")
assert(scheme_field.text == "#102030", "and follows the picker")
scheme_field.options.onSubmit(scheme_field, "#A0B0C0")
assert(settings.tint() == 0xA0B0C0, "a typed colour is used")
scheme_field.options.onSubmit(scheme_field, "40ff80")
assert(settings.tint() == 0x40FF80 and scheme_field.text == "#40FF80", "without the # and in small letters too, shown tidied")
scheme_field.options.onSubmit(scheme_field, "blue")
assert(settings.tint() == 0x40FF80 and scheme_field.text == "#40FF80", "something that isn't a colour changes nothing, and the field shows the colour again")

-- What the schemes do to colours.
assert(colour_scheme.multiplied(0xFFFFFF, 0xFF8040) == 0xFF8040, "an untinted part takes the tint")
assert(colour_scheme.multiplied(0x808080, 0xFF0000) == 0x800000, "the game's own tint stays under it")
assert(colour_scheme.tinted(0x152648, 0xFF0000) == 0x480000, "a plain colour keeps its brightness in the tint's colour")
assert(colour_scheme.tinted_text(0xFCC907, 0xFF0000) == 0xFCC907, "gold text stays gold")
local body_text = colour_scheme.tinted_text(0xA6C7D6, 0xFF0000)
assert(body_text >> 16 == 0xD6 and body_text & 0xFF < 0xD6, "blue-grey text leans to the tint and stays light")

-- The player's own text colours: off until one is picked.
local colours = settings.colours()
assert(colours.heading_text == nil and colours.body_text == nil, "no own text colours when nothing is saved")
local heading_picker, body_picker = text_pickers[#text_pickers - 1], text_pickers[#text_pickers]
assert(heading_picker.options.value == colour_scheme.default_heading_text * 256 + 0xFF, "the heading picker shows the old gold")
body_picker.options.onChange(nil, 0x334455FF)
colours = settings.colours()
assert(colours.body_text == 0x334455, "a picked text colour is used")
assert(colours.heading_text == colour_scheme.default_heading_text, "with the old gold for headings until one is picked")
reset_text_colours()
colours = settings.colours()
assert(colours.heading_text == nil and colours.body_text == nil, "the button goes back to the scheme's text colours")
assert(body_picker.value == colour_scheme.default_body_text * 256 + 0xFF and body_picker.notified == false, "and the pickers show the old colours again")

view.stop()
assert(handler == nil, "stops listening")
