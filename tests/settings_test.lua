-- The settings page against a fake prettyui and PersistentDB.
package.path = "./?.lua;" .. package.path
local stored = { option_backgrounds = false }
PersistentDB = {
    GetBool = function (_, key) return stored[key] end,
    SetBool = function (_, key, value) stored[key] = value; return true end,
    GetString = function (_, key) return stored[key] or "" end,
    SetString = function (_, key, value) stored[key] = value; return true end,
}
local handler, update_handler
Event = {
    SettingsLayerReady = {
        Subscribe = function (_, f) handler = f end,
        Unsubscribe = function () handler = nil end,
    },
    Logic = {
        Subscribe = function (_, f) update_handler = f end,
        Unsubscribe = function () update_handler = nil end,
    },
}

-- What the page last built: everything added to it, whichever tab it's in. Colour pickers and
-- their hex fields are in the order added: in the custom scheme its main colour and one per part,
-- then always the headings' and the other text's.
local built
local builds = 0
local function fake_page()
    local page = {
        AddTitle = function () end,
        AddText = function () end,
        AddCheckboxButton = function (_, items, options) built.checkboxes = { items = items, options = options } end,
        AddComboBox = function (_, options)
            built.dropdown = options
            return { Select = function (_, index) built.selected_in_dropdown = index end }
        end,
        AddColourPicker = function (_, options)
            local picker = { options = options, SetValue = function (self, value, notify) self.value = value; self.notified = notify end }
            built.pickers[#built.pickers + 1] = picker
            return picker
        end,
        AddTextField = function (_, options)
            local field = { options = options, SetText = function (self, text) self.text = text end }
            built.fields[#built.fields + 1] = field
            return field
        end,
        AddSimpleButton = function (_, label, action) built.buttons[label] = action end,
        Destroy = function () end,
    }
    page.AddTabs = function (_, labels, options)
        built.tabs = labels
        built.shown_tab = options.activeIndex
        return { GetPage = function () return page end }
    end
    return page
end
prettyui = {
    CheckboxButton = { getSize = function () return 200, 100 end },
    SimpleView = { new = function ()
        builds = builds + 1
        built = { pickers = {}, fields = {}, buttons = {} }
        return fake_page()
    end },
}

local sprite_groups = require("src/game/sprite_groups")
local colour_scheme = require("src/game/colour_scheme")
local settings = require("src/database/settings")
local view = require("src/interface/settings_view")
local changes = 0
view.start(function () changes = changes + 1 end)
local function open() handler({ component = { width = 400, height = 300 } }) end
open()

assert(#built.tabs == 3, "the page has three tabs")
assert(#built.checkboxes.items == #sprite_groups.options, "every option is shown")
for _, item in ipairs(built.checkboxes.items) do
    assert(item.selected == (item.value ~= "backgrounds"), item.value .. " shows its saved state")
end

built.checkboxes.options.onChange(nil, {}, "text_colours", false)
assert(stored.option_text_colours == false, "turning text colours off is saved")
assert(not settings.is_on("text_colours"), "and read back")
assert(changes == 1, "the swapping starts again")

-- Opening the page again builds it again, from the saved states.
open()
for _, item in ipairs(built.checkboxes.items) do
    if item.value == "text_colours" then
        assert(not item.selected, "text colours shows as off")
    end
end

-- The colour scheme: classic until another is chosen. Only the text colours can be picked then.
local part_count = #sprite_groups.colour_parts
assert(settings.colour_scheme() == "classic" and settings.tint() == nil, "classic, untinted, when nothing is saved")
assert(colour_scheme.all[built.dropdown.selectedID].key == "classic", "the dropdown shows the classic scheme")
assert(#built.dropdown.entries == #colour_scheme.all, "every scheme is in the dropdown")
assert(#built.pickers == 2, "only the two text colours have pickers")

local crimson_index, custom_index
for index, scheme in ipairs(colour_scheme.all) do
    if scheme.key == "crimson" then crimson_index = index end
    if scheme.key == "custom" then custom_index = index end
end
local crimson = colour_scheme.all[crimson_index].tint
built.dropdown.onChange(nil, crimson_index)
assert(settings.colour_scheme() == "crimson" and settings.tint() == crimson, "choosing a scheme is saved")
assert(changes == 2, "and the swapping starts again")
local builds_before = builds
update_handler()
assert(builds == builds_before, "the page stays as it is between schemes without colours to pick")

-- Choosing the custom scheme builds the page again, on the next update, with its colours to pick.
stored.part_tint_tabs = "112233"
assert(next(settings.colours().part_tints) == nil, "a part's saved colour isn't used outside the custom scheme")
built.dropdown.onChange(nil, custom_index)
assert(settings.colour_scheme() == "custom" and settings.tint() == colour_scheme.default_custom_tint, "the custom scheme starts with the default colour")
assert(builds == builds_before, "not while the dropdown is still telling of the change")
update_handler()
assert(builds == builds_before + 1 and built.shown_tab == 2, "built again, showing the Colours tab")
update_handler()
assert(builds == builds_before + 1, "once")
assert(#built.pickers == 1 + part_count + 2, "pickers for the main colour, each part and the two text colours")
assert(colour_scheme.all[built.dropdown.selectedID].key == "custom", "the dropdown shows the custom scheme")
assert(settings.colours().part_tints.tabs == 0x112233, "and the part's saved colour is used")
stored.part_tint_tabs = nil
open()
assert(built.shown_tab == 1, "opening the page shows the first tab")

local main_picker, main_field = built.pickers[1], built.fields[1]
assert(main_picker.options.value == colour_scheme.default_custom_tint * 256 + 0xFF, "the main colour's picker shows it")
assert(main_field.options.text == "#4A87FF", "and its field the same colour as hex")
assert(main_picker.options.inline and main_field.options.inline, "picker and field are on the label's row")
main_picker.options.onChange(nil, 0x102030FF)
assert(settings.tint() == 0x102030, "a picked colour is the scheme's tint")
assert(main_field.text == "#102030", "and the field follows the picker")

-- A colour can be typed too.
main_field.options.onSubmit(main_field, "#A0B0C0")
assert(settings.tint() == 0xA0B0C0, "a typed colour is used")
assert(main_picker.value == 0xA0B0C0FF and main_picker.notified == false, "and the picker follows the field")
main_field.options.onSubmit(main_field, "40ff80")
assert(settings.tint() == 0x40FF80 and main_field.text == "#40FF80", "without the # and in small letters too, shown tidied")
main_field.options.onSubmit(main_field, "blue")
assert(settings.tint() == 0x40FF80 and main_field.text == "#40FF80", "something that isn't a colour changes nothing, and the field shows the colour again")
main_field.options.onSubmit(main_field, "")
assert(settings.tint() == 0x40FF80 and main_field.text == "#40FF80", "nor does clearing the main colour")

-- A part of the interface follows the main colour until it gets a colour of its own.
local tabs_index
for index, part in ipairs(sprite_groups.colour_parts) do
    if part.key == "tabs" then tabs_index = index end
end
local tabs_picker, tabs_field = built.pickers[1 + tabs_index], built.fields[1 + tabs_index]
assert(next(settings.colours().part_tints) == nil, "no part has its own colour when nothing is saved")
assert(tabs_field.options.text == "#4A87FF" and tabs_field.text == "#40FF80", "a part following the main colour shows it, and its changes")
tabs_field.options.onSubmit(tabs_field, "#112233")
assert(settings.colours().part_tints.tabs == 0x112233, "a part's typed colour is used")
assert(settings.tint() == 0x40FF80, "and the main colour stays as it was")
main_field.options.onSubmit(main_field, "#506070")
assert(tabs_field.text == "#112233", "a part with its own colour doesn't follow the main colour")
assert(built.fields[2].text == "#506070", "the other parts do")
tabs_field.options.onSubmit(tabs_field, "  ")
assert(settings.colours().part_tints.tabs == nil, "clearing a part's colour has it follow the main colour again")
assert(tabs_field.text == "#506070", "and show it")
tabs_picker.options.onChange(nil, 0x445566FF)
assert(settings.colours().part_tints.tabs == 0x445566, "a part's picked colour is used")
built.buttons["All parts follow the main colour"]()
assert(next(settings.colours().part_tints) == nil, "the button has every part follow the main colour again")
assert(tabs_field.text == "#506070", "and show it")

-- Leaving the custom scheme takes its colours off the page again.
built.dropdown.onChange(nil, crimson_index)
update_handler()
assert(#built.pickers == 2 and built.shown_tab == 2, "built again without them")

stored.colour_scheme = "gone"
assert(settings.colour_scheme() == "classic", "a scheme that no longer exists falls back to classic")

-- What the schemes do to colours.
assert(colour_scheme.multiplied(0xFFFFFF, 0xFF8040) == 0xFF8040, "an untinted part takes the tint")
assert(colour_scheme.multiplied(0x808080, 0xFF0000) == 0x800000, "the game's own tint stays under it")
assert(colour_scheme.tinted(0x152648, 0xFF0000) == 0x480000, "a plain colour keeps its brightness in the tint's colour")
assert(colour_scheme.tinted_text(0xFCC907, 0xFF0000) == 0xFCC907, "gold text stays gold")
local body_text = colour_scheme.tinted_text(0xA6C7D6, 0xFF0000)
assert(body_text >> 16 == 0xD6 and body_text & 0xFF < 0xD6, "blue-grey text leans to the tint and stays light")
assert(colour_scheme.part_tint({ tint = 0x111111, part_tints = { tabs = 0x222222 } }, "tabs") == 0x222222, "a part's own tint comes first")
assert(colour_scheme.part_tint({ tint = 0x111111, part_tints = { tabs = 0x222222 } }, "buttons") == 0x111111, "then the scheme's")
assert(colour_scheme.part_tint({}, "buttons") == nil, "and none in the classic scheme")

-- Which part of the interface a sprite belongs to.
for sprite_name, part_key in pairs({
    RS3_PARENT_FRAME_SIDE_TILE = "frames",
    RS3_HUD_WINDOW_CORNER_TOP = "frames",
    RS3_CONTENT_FRAME_0 = "frames",
    RS3_PARENT_BANNER_BAR_TILE = "title_bars",
    RS3_CHILD_HEADER_TILE = "title_bars",
    RS3_MODAL_WINDOW_1_TITLE_TILE = "title_bars",
    RS3_CHILD_TAB_SELECTED = "tabs",
    RS3_PARENT_TAB_CURRENT_LEFT = "tabs",
    BANK_TABS_HORIZONTAL_2 = "tabs",
    RS3_BTN_CHILD_TAB_SCROLL_SML_0 = "tabs",
    RS3_CHILD_CONTENT_TILE = "backgrounds",
    RS3_CONTENT_FRAME_4 = "backgrounds",
    RS3_BTN_MAIN_NEUTRAL_0 = "buttons",
    RS3_BTN_MODAL_WINDOW_1_CLOSE_NML = "buttons",
    BUTTON_CORNERED_POSITIVE = "buttons",
    RS3_BTN_DROPDOWN_3 = "controls",
    RS3_BTN_CHECKBOX_SMALL_1 = "controls",
    SCROLLBAR_V2_0 = "controls",
    RS3_CONTENT_CONTAINER_12 = "controls",
}) do
    assert(sprite_groups.colour_part_of(sprite_name) == part_key, sprite_name .. " belongs to " .. part_key .. ", not " .. sprite_groups.colour_part_of(sprite_name))
end

-- The player's own text colours: off until one is picked.
local colours = settings.colours()
assert(colours.heading_text == nil and colours.body_text == nil, "no own text colours when nothing is saved")
local heading_picker, body_picker = built.pickers[#built.pickers - 1], built.pickers[#built.pickers]
assert(heading_picker.options.value == colour_scheme.default_heading_text * 256 + 0xFF, "the heading picker shows the old gold")
body_picker.options.onChange(nil, 0x334455FF)
colours = settings.colours()
assert(colours.body_text == 0x334455, "a picked text colour is used")
assert(colours.heading_text == colour_scheme.default_heading_text, "with the old gold for headings until one is picked")
built.buttons["Use the scheme's text colours"]()
colours = settings.colours()
assert(colours.heading_text == nil and colours.body_text == nil, "the button goes back to the scheme's text colours")
assert(body_picker.value == colour_scheme.default_body_text * 256 + 0xFF and body_picker.notified == false, "and the pickers show the old colours again")

view.stop()
assert(handler == nil and update_handler == nil, "stops listening")
