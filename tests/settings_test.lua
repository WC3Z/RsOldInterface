-- The plugin's page and its settings window against a fake prettyui and PersistentDB.
package.path = "./?.lua;" .. package.path
local stored = { option_backgrounds = false }
local function get(_, key) return stored[key] end
local function set(_, key, value) stored[key] = value; return true end
PersistentDB = {
    GetBool = get, SetBool = set, GetInt = get, SetInt = set,
    GetString = function (_, key) return stored[key] or "" end,
    SetString = set,
}
local handlers = {}
Event = {}
for _, name in ipairs({ "ContentLayerReady", "Logic", "KeyDown" }) do
    Event[name] = {
        Subscribe = function (_, f) handlers[name] = f end,
        Unsubscribe = function () assert(handlers[name], name .. " is only unsubscribed from when subscribed") handlers[name] = nil end,
    }
end
GameKey = { ESCAPE = "escape" }
id = { Component = { TOPLEVEL_V2__GAME_AREA = 1 } }
ui = { Interfaces = { GetComponent = function () return { width = 1000, height = 800 } end } }

-- What the window last built: everything added to it, whichever tab it's in. Colour pickers and
-- their hex fields are in the order added: in the custom scheme its colour, then one per part,
-- then the headings' and the other text's.
local built
local builds = 0
-- What the plugin's page last built.
local content
local function fake_page(record)
    local page = {
        AddTitle = function () end,
        AddText = function () end,
        AddCheckboxButton = function (_, items, options) record.checkboxes = { items = items, options = options } end,
        AddComboBox = function (_, options)
            record.dropdown = options
            return {}
        end,
        AddColourPicker = function (_, options)
            local picker = { options = options, SetValue = function (self, value, notify) self.value = value; self.notified = notify end }
            record.pickers[#record.pickers + 1] = picker
            return picker
        end,
        AddTextField = function (_, options)
            local field = { options = options, SetText = function (self, text) self.text = text end }
            record.fields[#record.fields + 1] = field
            return field
        end,
        AddSimpleButton = function (_, label, action) record.buttons[label] = action end,
        Destroy = function () record.destroyed = true end,
    }
    page.AddTabs = function (_, labels, options)
        record.tabs = labels
        record.tabs_options = options
        record.shown_tab = options.activeIndex
        return { GetPage = function () return page end, GetActiveIndex = function () return record.shown_tab end, SetActive = function () end }
    end
    return page
end
prettyui = {
    CheckboxButton = { getSize = function () return 200, 100 end },
    SimpleView = { new = function ()
        content = { pickers = {}, fields = {}, buttons = {} }
        return fake_page(content)
    end },
    Window = { new = function (_, options)
        builds = builds + 1
        built = { pickers = {}, fields = {}, buttons = {}, options = options }
        local window = fake_page(built)
        window.root = { x = options.x or 100, y = options.y or 50, width = options.width, height = options.height }
        window.SetSize = function () end
        window.Close = function (self)
            options.onClose(self)
            built.destroyed = true
        end
        built.window = window
        return window
    end },
}

local sprite_groups = require("src/game/sprite_groups")
local colour_scheme = require("src/game/colour_scheme")
local settings = require("src/database/settings")
local settings_window = require("src/interface/settings_window")
local content_view = require("src/interface/content_view")
local changes = 0
settings_window.start(function () changes = changes + 1 end)
content_view.start()
local update_handler = handlers.Logic

-- The plugin's page has a button that opens the settings window.
handlers.ContentLayerReady({ component = { width = 400, height = 300 } })
assert(built == nil, "the window isn't open before it's asked for")
local function open() content.buttons["Open settings"]() end
open()
assert(built.options.width == 400 and built.options.x == nil, "the window opens at its size to start with, where prettyui puts it")
assert(#built.tabs == 3 and built.shown_tab == 1, "with three tabs, on the first")
assert(#built.checkboxes.items == #sprite_groups.options, "every option is shown")
for _, item in ipairs(built.checkboxes.items) do
    assert(item.selected == (item.value ~= "backgrounds"), item.value .. " shows its saved state")
end

built.checkboxes.options.onChange(nil, {}, "text_colours", false)
assert(stored.option_text_colours == false, "turning text colours off is saved")
assert(not settings.is_on("text_colours"), "and read back")
assert(changes == 1, "the swapping starts again")

-- Opening the window again builds it again, from the saved states.
open()
for _, item in ipairs(built.checkboxes.items) do
    if item.value == "text_colours" then
        assert(not item.selected, "text colours shows as off")
    end
end

-- The colour scheme: classic until another is chosen.
local part_count = #sprite_groups.colour_parts
assert(settings.colour_scheme() == "classic" and settings.tint() == nil, "classic, untinted, when nothing is saved")
assert(colour_scheme.all[built.dropdown.selectedID].key == "classic", "the dropdown shows the classic scheme")
assert(#built.dropdown.entries == #colour_scheme.all, "every scheme is in the dropdown")
assert(#built.pickers == part_count + 2, "pickers for each part and the two text colours")

local crimson_index, custom_index
for index, scheme in ipairs(colour_scheme.all) do
    if scheme.key == "crimson" then crimson_index = index end
    if scheme.key == "custom" then custom_index = index end
end
local crimson = colour_scheme.all[crimson_index].tint

-- Choosing a scheme builds the page again, on the next update, showing the Colours tab.
local builds_before = builds
built.dropdown.onChange(nil, crimson_index)
assert(settings.colour_scheme() == "crimson" and settings.tint() == crimson, "choosing a scheme is saved")
assert(changes == 2, "and the swapping starts again")
assert(builds == builds_before, "the window isn't built again while the dropdown is still telling of the change")
built.tabs_options.onChange(nil, 2)
update_handler()
assert(builds == builds_before + 1 and built.shown_tab == 2, "but on the next update, on the tab the player was on")
update_handler()
assert(builds == builds_before + 1, "once")
assert(colour_scheme.all[built.dropdown.selectedID].key == "crimson", "the dropdown shows the chosen scheme")
assert(built.pickers[1].options.value == crimson * 256 + 0xFF, "a part's picker starts from the scheme's colour")

-- The custom scheme has its colour to pick.
built.dropdown.onChange(nil, custom_index)
update_handler()
assert(settings.colour_scheme() == "custom" and settings.tint() == colour_scheme.default_custom_tint, "the custom scheme starts with the default colour")
assert(#built.pickers == 1 + part_count + 2, "it has a picker for its colour too")

local main_picker, main_field = built.pickers[1], built.fields[1]
assert(main_picker.options.value == colour_scheme.default_custom_tint * 256 + 0xFF, "the scheme's picker shows its colour")
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
assert(settings.tint() == 0x40FF80 and main_field.text == "#40FF80", "nor does clearing the scheme's colour")
update_handler()
assert(built.pickers[2].options.value == 0x40FF80FF, "the parts' pickers start from the scheme's new colour")

-- A part of the interface is drawn as the scheme has it until it gets a colour of its own.
local tabs_index
for index, part in ipairs(sprite_groups.colour_parts) do
    if part.key == "tabs" then tabs_index = index end
end
local tabs_picker, tabs_field = built.pickers[1 + tabs_index], built.fields[1 + tabs_index]
assert(next(settings.colours().own_part_tints) == nil, "no part has its own colour when nothing is saved")
assert(tabs_field.options.text == "", "a part without its own colour shows no value")
tabs_field.options.onSubmit(tabs_field, "#112233")
assert(settings.colours().own_part_tints.tabs == 0x112233, "a part's typed colour is used")
assert(settings.tint() == 0x40FF80, "and the scheme's colour stays as it was")
tabs_field.options.onSubmit(tabs_field, "  ")
assert(settings.colours().own_part_tints.tabs == nil, "clearing a part's colour has the scheme's again")
assert(tabs_field.text == "" and tabs_picker.value == 0x40FF80FF, "and shows no value, the picker back at the scheme's colour")
tabs_picker.options.onChange(nil, 0x445566FF)
assert(settings.colours().own_part_tints.tabs == 0x445566 and tabs_field.text == "#445566", "a part's picked colour is used and shown")

-- A part's own colour stays whatever the scheme.
built.dropdown.onChange(nil, crimson_index)
update_handler()
assert(settings.colours().own_part_tints.tabs == 0x445566, "in another scheme too")
assert(colour_scheme.sprite_tint(settings.colours(), "RS3_CHILD_TAB_SELECTED", "tabs") == 0x445566, "where it comes before the scheme's colour")
assert(colour_scheme.sprite_tint(settings.colours(), "RS3_BTN_MAIN_NEUTRAL_0", "buttons") == crimson, "which the other parts have")
assert(built.fields[tabs_index].options.text == "#445566", "and the page shows it")
built.buttons["Use the scheme's colours for all parts"]()
assert(next(settings.colours().own_part_tints) == nil, "the button gives every part the scheme's colour again")
assert(built.fields[tabs_index].text == "", "and their values are cleared")

-- A scheme can have its own images, with colours for what they leave out.
stored.colour_scheme = "darkscape"
local darkscape = settings.colours()
assert(darkscape.image_set == "darkscape", "DarkScape has its own images")
assert(darkscape.tint == nil, "and no tint for everything: what it has no image of is drawn as in the classic scheme")
assert(colour_scheme.sprite_tint(darkscape, "RS3_MODAL_WINDOW_1_SIDE_TILE", "frames") ~= nil, "but for the pieces it built differently, which have its colours")
assert(colour_scheme.sprite_tint(darkscape, "RS3_BTN_MAIN_NEUTRAL_0", "buttons") == nil, "buttons, which it kept, have none")
assert(colour_scheme.part_tint(darkscape, "backgrounds") ~= nil, "plain panels have its background colour")
assert(colour_scheme.sprite_tint({ tint = 1, part_tints = { tabs = 2 }, sprite_tints = { { pattern = "^A", tint = 3 } } }, "AB", "tabs") == 3, "a tint for sprites of a name comes first")
assert(colour_scheme.sprite_tint({ tint = 1, part_tints = { tabs = 2 }, sprite_tints = { { pattern = "^A", tint = 3 } } }, "B", "tabs") == 2, "then the part's")
assert(colour_scheme.sprite_tint({ own_part_tints = { tabs = 4 }, part_tints = { tabs = 2 }, sprite_tints = { { pattern = "^A", tint = 3 } } }, "AB", "tabs") == 4, "and the player's own for the part before both")
local part_keys = {}
for _, part in ipairs(sprite_groups.colour_parts) do
    part_keys[part.key] = true
end
for _, scheme in ipairs(colour_scheme.all) do
    for part_key in pairs(scheme.part_tints or {}) do
        assert(part_keys[part_key], scheme.key .. "'s " .. part_key .. " is a part of the interface")
    end
end

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
    BUTTON_CORNERED_POSITIVE = "buttons",
    BUTTON_ACCORDION_24PX = "buttons",
    RS3_BTN_MODAL_WINDOW_1_CLOSE_NML = "small_buttons",
    RS3_BTN_INCREASE_ACTIVE_SMALL = "small_buttons",
    RS3_BTN_DECREASE_OVER = "small_buttons",
    RS3_CHILD_CLOSE_BUTTON_BACKING = "small_buttons",
    RS3_BTN_DROPDOWN_3 = "dropdowns",
    DROPDOWN_DEFAULT_ARROW = "dropdowns",
    RS3_BTN_CHECKBOX_SMALL_1 = "checkboxes",
    RS3_BTN_RADIO_ON = "checkboxes",
    CHECKBOX_DEFAULT = "checkboxes",
    SCROLLBAR_V2_0 = "scrollbars",
    SCROLLBAR_DRAGGER_V2_1 = "scrollbars",
    RS3_SLIDER_BAR_TILE = "sliders",
    RS3_BTN_ADJUST_SLIDER_2 = "sliders",
    RS3_CONTENT_CONTAINER_12 = "rows",
    RS3_CONTEXTUAL_INPUT_BOX_3 = "rows",
    INPUT_DEFAULT = "rows",
}) do
    assert(sprite_groups.colour_part_of(sprite_name) == part_key, sprite_name .. " belongs to " .. part_key .. ", not " .. sprite_groups.colour_part_of(sprite_name))
end
local part_labels = {}
for _, part in ipairs(sprite_groups.colour_parts) do
    assert(part_labels[part.label] == nil, part.label .. " is the name of one part only")
    part_labels[part.label] = true
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

-- The window opens again where it was and at the size it had when it was closed, on the same tab.
built.window.root.x, built.window.root.y, built.window.root.width, built.window.root.height = 300, 200, 500, 600
built.window:Close()
open()
assert(built.options.x == 300 and built.options.y == 200 and built.options.width == 500 and built.options.height == 600, "where and as big as it was")
assert(built.shown_tab == 2, "on the tab it was on")

-- Escape closes it; without a window, the key does nothing.
local closed = built
handlers.KeyDown({ gameKey = GameKey.ESCAPE })
assert(closed.destroyed, "Escape closes the window")
handlers.KeyDown({ gameKey = GameKey.ESCAPE })
update_handler()
assert(built == closed, "and nothing is built again without a window")

open()
local open_window = built
content_view.stop()
settings_window.stop()
assert(open_window.destroyed and content.destroyed, "stopping closes the window and the page")
assert(next(handlers) == nil, "and stops listening")
