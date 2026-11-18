-- The swapping against a fake game: interfaces are tables of components, and each section
-- plays out something the game does (a window opening, a tab being rebuilt, a hover) between
-- its updates and frames.
package.path = "./?.lua;" .. package.path
local errors = {}
local real_print = print
-- Errors the plugin prints are collected (and checked below) rather than shown.
local quiet = false
print = function (text)
  if tostring(text):find("error") then
    errors[#errors + 1] = text
  elseif not quiet then
    real_print(text)
  end
end
local subs = { Logic = {}, Draw = {} }
Event = {}
for name, list in pairs(subs) do
  Event[name] = { Subscribe = function (n, f) list[n] = f end, Unsubscribe = function (n) list[n] = nil end }
end
ui = { ComponentType = { LINE = "LINE", RECTANGLE = "RECTANGLE", LABEL = "LABEL", SPRITE = "SPRITE", BUTTON = "BUTTON", CHECK = "CHECK", LIST = "LIST", INPUTFIELD = "INPUTFIELD", SLIDER = "SLIDER", COMBO = "COMBO", CAROUSEL = "CAROUSEL", PAGED_CAROUSEL = "PAGED_CAROUSEL", RADIO_GROUP = "RADIO_GROUP", LAYER = "LAYER", PANEL = "PANEL", GRID = "GRID", PAGED_LAYER = "PAGED_LAYER", GROUP_BOX = "GROUP_BOX" } }
local names = { [100] = "RS3_PARENT_FRAME_SIDE_TILE", [101] = "RS3_BTN_MAIN_NEUTRAL_0", [102] = "RS3_BTN_MAIN_NEUTRAL_1" }
id = { Sprite = { FromID = function (i) return names[i] end }, Interface = setmetatable({ FromID = function (i) return "IF" .. i end }, { __index = function () return nil end }) }
for i, n in pairs(names) do id.Sprite[n] = i end
Plugin = { resources = { side_without_edge = "img_side_without_edge", frames = { RS3_PARENT_FRAME_SIDE_TILE = "img_side", RS3_BTN_MAIN_NEUTRAL_0 = "img_btn0", RS3_BTN_MAIN_NEUTRAL_1 = "img_btn1" } } }
-- normal skin: slot 0 heading gold, slot 3 body text, slot 12 card; mobile: the same slots as in game
local function enum(values)
  local e = { values = {} }
  for slot, colour in pairs(values) do e.values[#e.values + 1] = { slot, colour } end
  function e:GetOutputValue(slot) return values[slot] end
  return e
end
config = { Enum = {
  TOPLEVEL_V2_SKIN_COLOUR_NORMAL = enum({ [0] = 0xF0BE79, [3] = 0xE3D7CF, [12] = 0x24211E }),
  TOPLEVEL_V2_SKIN_COLOUR_MOBILE = enum({ [0] = 0xD9DBA9, [3] = 0xA1EAFC, [12] = 0x152648 }),
} }

local function sprite(iface, static, sid, visible)
  local c = { interfaceID = iface, staticID = static, categoryID = -1, dynamicID = -1, type = ui.ComponentType.SPRITE, spriteID = sid, visibleGlobal = visible, x = 0, y = 0, width = 10, height = 10 }
  return setmetatable(c, { __newindex = function (t, k, v)
    if k == "sprite" then rawset(t, "spriteID", type(v) == "number" and v or -1); rawset(t, "image", v) else rawset(t, k, v) end
  end })
end
local loaded = {}
local function load(iface, comps) loaded[iface] = comps end
ui.Interfaces = {
  GetInterface = function (_, i) return loaded[i] and { id = i } or nil end,
  GetComponent = function (_, i, s, cat, dyn)
    local c = loaded[i] and loaded[i][s]
    if c == nil or cat == nil or cat == -1 then return c end
    for _, child in ipairs(c.children or {}) do
      if child.categoryID == cat and child.dynamicID == dyn then return child end
    end
    return nil
  end,
}
local function logic() for _, f in pairs(subs.Logic) do f({}) end end
local function draw() for _, f in pairs(subs.Draw) do f({}) end end
local function tick(n) for _ = 1, n do logic() draw() draw() end end
local all_on = function () return true end

load(5, { [0] = sprite(5, 0, 100, true), [1] = sprite(5, 1, 101, true), [2] = sprite(5, 2, 100, false) })
local label = { interfaceID = 5, staticID = 3, categoryID = -1, dynamicID = -1, type = ui.ComponentType.LABEL, visibleGlobal = true, rgb = 0xF0BE79, content = "MANUAL SETUP" }
local plain = { interfaceID = 5, staticID = 4, categoryID = -1, dynamicID = -1, type = ui.ComponentType.LABEL, visibleGlobal = true, rgb = 0x00FF00, content = "green" }
local button = { interfaceID = 5, staticID = 6, categoryID = -1, dynamicID = -1, type = ui.ComponentType.BUTTON, visibleGlobal = true,
  sprite = sprite(5, 6, 101, true), text = { rgba = 0xE3D7CF80, content = "Preview" } }
local plugin_label = { interfaceID = 5, staticID = 8, categoryID = -1, dynamicID = -1, type = ui.ComponentType.LABEL, visibleGlobal = true, rgb = 0xE7D7B0, content = "Font" }
local card = { interfaceID = 5, staticID = 7, categoryID = -1, dynamicID = -1, type = ui.ComponentType.RECTANGLE, visibleGlobal = true, rgb = 0x24211E }
loaded[5][3] = label
loaded[5][4] = plain
loaded[5][6] = button
loaded[5][7] = card
loaded[5][8] = plugin_label

local swapper = require("src/game/sprite_swapper")
local groups = require("src/game/sprite_groups")
swapper.start(groups.names(all_on))
tick(5)
assert(loaded[5][0].spriteID == -1, "side tile swapped")
assert(loaded[5][1].spriteID == -1, "button swapped")
assert(label.rgb == 0xFCC907, "heading gets the old desktop gold")
assert(plain.rgb == 0x00FF00, "text without a skin colour left alone")
assert(button.text.rgba == 0xA6C7D680, "button text gets the old desktop blue-grey, alpha kept")
assert(card.rgb == 0x152648, "card gets the mobile skin colour")
assert(plugin_label.rgb == 0xA6C7D6, "a plugin window's label gets the old label colour")
label.rgb = 0xF0BE79
logic() draw()
assert(label.rgb == 0xFCC907, "reset text recoloured before the frame")

-- hover: game puts its own sprite back, swapped again
loaded[5][1].spriteID = 102
tick(1)
assert(loaded[5][1].spriteID == -1, "hover re-swapped")

-- a new interface loads at a high ID
load(1800, { [0] = sprite(1800, 0, 101, true) })
tick(8)
assert(loaded[1800][0].spriteID == -1, "a new interface at a high ID is found")

-- a hidden tab (its own interface) that the game shows and rebuilds in one update
load(6, { [0] = sprite(6, 0, 101, false), [1] = sprite(6, 1, 999, false) })
tick(12)
assert(loaded[6][0].spriteID == -1, "hidden tab swapped ahead")
logic()
loaded[6][0].spriteID = 101
loaded[6][0].visibleGlobal = true
loaded[6][1].spriteID = 101
loaded[6][1].visibleGlobal = true
draw()
assert(loaded[6][0].spriteID == -1, "shown tab re-swapped before its first frame")
assert(loaded[6][1].spriteID == -1, "shown tab's new part swapped before its first frame")

-- a tab that loaded with a spinner, and gets its content during an update
load(7, { [0] = sprite(7, 0, 999, true), [1] = sprite(7, 1, 999, false) })
tick(6)
logic()
loaded[7][1].spriteID = 101
loaded[7][1].visibleGlobal = true
draw()
assert(loaded[7][1].spriteID == -1, "content filled in during an update swapped before its first frame")

-- a big window's frame, hidden in the always-showing main interface, reset as the window opens
for i = 10, 400 do loaded[5][i] = sprite(5, i, 100, false) end
tick(40)
assert(loaded[5][10].spriteID == -1, "hidden frame swapped ahead")
logic()
for i = 10, 400 do loaded[5][i].spriteID = 100; loaded[5][i].visibleGlobal = true end
draw()
for i = 10, 400 do assert(loaded[5][i].spriteID == -1, "frame piece re-swapped before the window's first frame") end

-- a docked window's tab bar: the game builds its tabs again with new IDs when switching tabs
local function tab(iface, static, dyn)
  local c = sprite(iface, static, 101, true)
  c.categoryID = 0
  c.dynamicID = dyn
  return c
end
local function layer(iface, static)
  local l = { interfaceID = iface, staticID = static, categoryID = -1, dynamicID = -1, type = ui.ComponentType.LAYER, visibleGlobal = true, children = {} }
  function l:IterateDynamicComponents(callback) for _, child in ipairs(self.children) do callback(child) end end
  return l
end
local bar = layer(8, 0)
for d = 1, 9 do bar.children[d] = tab(8, 0, d) end
load(8, { [0] = bar })
tick(60)
assert(bar.children[1].spriteID == -1, "tabs swapped")
logic()
bar.children = {}
for d = 1, 9 do bar.children[d] = tab(8, 0, 10 + d) end
draw()
for d = 1, 9 do assert(bar.children[d].spriteID == -1, "rebuilt tab swapped before its first frame") end

-- tab buttons that say they're hidden while they show: once the game changes one, the bar is
-- checked after every update
local qbar = layer(9, 5)
for d = 0, 3 do local c = tab(9, 5, d); c.visibleGlobal = false; qbar.children[d + 1] = c end
local q = { [0] = sprite(9, 0, 999, false), [5] = qbar }
for i = 6, 600 do q[i] = sprite(9, i, 101, false) end
load(9, q)
tick(60)
assert(qbar.children[1].spriteID == -1, "quick tabs swapped")
qbar.children[1].spriteID = 102
tick(60)
assert(qbar.children[1].spriteID == -1, "first change caught in turns")
logic()
qbar.children[2].spriteID = 102
draw()
assert(qbar.children[2].spriteID == -1, "next tab change caught before its first frame")

-- stop puts the game's look back
loaded[1800] = nil
tick(8)
swapper.stop()
assert(loaded[5][0].spriteID == 100, "sprite restored on stop")
assert(label.rgb == 0xF0BE79, "text colour restored on stop")
assert(button.text.rgba == 0xE3D7CF80, "button text colour restored on stop")
assert(card.rgb == 0x24211E, "card colour restored on stop")

-- hidden text is checked every 10th update; showing text after every update
swapper.start(groups.names(all_on))
local hidden_label = { interfaceID = 5, staticID = 401, categoryID = -1, dynamicID = -1, type = ui.ComponentType.LABEL, visibleGlobal = false, rgb = 0xE3D7CF, content = "hidden" }
loaded[5][401] = hidden_label
tick(60)
assert(hidden_label.rgb == 0xA6C7D6, "hidden text recoloured")
hidden_label.rgb = 0xE3D7CF
for _ = 1, 10 do logic() draw() end
assert(hidden_label.rgb == 0xA6C7D6, "hidden text recoloured within 10 updates")
swapper.stop()

-- hover: the game sets the hover sprite again every frame while the mouse is over the button
swapper.start(groups.names(all_on))
tick(10)
local hovered = loaded[5][1]
hovered.spriteID = 102
logic() draw()
assert(hovered.spriteID == -1, "hover sprite swapped after the update")
hovered.spriteID = 102
draw()
assert(hovered.spriteID == -1, "hover sprite set again between updates swapped before the next frame")
swapper.stop()

-- every group is in exactly one option
local in_options = {}
for _, option in ipairs(groups.options) do
  for _, name in ipairs(option.groups) do
    assert(in_options[name] == nil, name .. " is in two options")
    in_options[name] = true
  end
end
for _, group in ipairs(groups.all) do assert(in_options[group.name], group.name .. " is in no option") end

-- text colours turned off: text keeps the new colour, the rest still gets the old look
label.rgb = 0xF0BE79
swapper.start(groups.names(function (key) return key ~= "text_colours" end))
tick(10)
assert(label.rgb == 0xF0BE79, "text left alone with text colours off")
assert(card.rgb == 0x152648, "cards still recoloured")
swapper.stop()

-- the debug tools print and count what happens, and run the benchmark, without errors
local events = require("src/game/debug_tools").events
local profile = require("src/debug/profile")
profile.benchmark_iterations = 30
profile.benchmark_at_update = 20
local activity_log = require("src/debug/activity_log")
activity_log.traced_interfaces = { IF5 = true }
local printed_while_debugging = 0
local print_before_debugging = print
print = function (text)
  printed_while_debugging = printed_while_debugging + 1
  if tostring(text):find("error") then errors[#errors + 1] = text end
end
events.enable({ profile = true, activity_log = true })
swapper.start(groups.names(all_on))
tick(5)
loaded[5][1].spriteID = 102
label.rgb = 0xF0BE79
tick(5)
load(21, { [0] = sprite(21, 0, 101, true), [1] = sprite(21, 1, 999, true) })
tick(900)
loaded[21] = nil
tick(5)
swapper.stop()
events.disable()
print = print_before_debugging
assert(#errors == 0, "no errors with the debug tools on: " .. tostring(errors[1]))
assert(printed_while_debugging > 20, "and they printed what happened")
assert(loaded[5][1].spriteID == 102 and label.rgb == 0xF0BE79, "the swapping worked as usual meanwhile")

-- the game reuses a button's IDs for a plain sprite component, and a part's sprite ID turns nil
swapper.start(groups.names(all_on))
tick(10)
loaded[5][6] = { interfaceID = 5, staticID = 6, categoryID = -1, dynamicID = -1, type = ui.ComponentType.SPRITE, visibleGlobal = true, sprite = 7, spriteID = 999 }
loaded[5][1].spriteID = nil
tick(40)
swapper.stop()
assert(#errors == 0, "no errors: " .. tostring(errors[1]))

-- a handler that errors keeps being called, and its error is printed once
local guard = require("src/game/guard")
local calls = 0
local guarded = guard.guarded("in a test", function () calls = calls + 1; error("boom") end)
guarded() guarded()
assert(calls == 2, "keeps being called")
assert(#errors == 1 and errors[1]:find("boom"), "printed once")


-- big windows' title strip: its side pieces fill it and draw nothing; the long ones keep the frame
swapper.start(groups.names(all_on))
local strip = { height = 38 }
local body = { height = 576 }
local strip_side = sprite(10, 0, 100, true); strip_side.height = 38; strip_side.parent = strip
local body_side = sprite(10, 1, 100, true); body_side.height = 418; body_side.parent = body
load(10, { [0] = strip_side, [1] = body_side })
tick(10)
assert(strip_side.image == "img_side_without_edge", "title strip side draws the fill without the edge")
assert(body_side.image == "img_side", "long side keeps the frame image")
logic()
strip_side.spriteID = 100
draw()
assert(strip_side.image == "img_side_without_edge", "and again after the game resets it")
swapper.stop()


-- an interface that's been loaded and hidden since the start, with nothing to change in it until it
-- shows (like the music player in Settings): found by its root showing, before the frame. Its
-- static components sit in a tree, and those inside a hidden one aren't looked at.
local lookups = {}
local function tracked(component)
  return setmetatable({}, {
    __index = function (_, k)
      if k == "visibleGlobal" then lookups[component.staticID] = (lookups[component.staticID] or 0) + 1 end
      return component[k]
    end,
    __newindex = function (_, k, v) component[k] = v end,
  })
end
local root = layer(11, 0); root.visibleGlobal = false
local panel = layer(11, 1); panel.visibleGlobal = false; panel.parentStatic = root
local deep = sprite(11, 2, 999, false); deep.parentStatic = panel
local other = sprite(11, 3, 999, false); other.parentStatic = root
load(11, { [0] = tracked(root), [1] = tracked(panel), [2] = tracked(deep), [3] = tracked(other) })
swapper.start(groups.names(all_on))
tick(40)
logic()
root.visibleGlobal = true
other.visibleGlobal = true
other.spriteID = 101
draw()
assert(other.spriteID == -1, "swapped before the frame it showed in")
lookups = {}
tick(20)
assert((lookups[1] or 0) > 0, "the hidden panel is checked")
assert(lookups[2] == nil or lookups[2] <= 2, "what's inside it only by the slow walk: " .. tostring(lookups[2]))
swapper.stop()

-- an interface with several roots (like the docked windows' tab bars): one of the later ones
-- showing counts as the interface showing, and is swapped before the frame
local roots = {}
for i = 0, 5 do roots[i] = sprite(12, i, 999, i == 0) end
load(12, roots)
swapper.start(groups.names(all_on))
tick(40)
logic()
roots[5].visibleGlobal = true
roots[5].spriteID = 101
draw()
assert(roots[5].spriteID == -1, "a later root showing is swapped before its frame")

-- an interface that's been showing all along, mounted inside one that just loaded (like the
-- music player in Settings' Audio tab): its content turning up a bit later is swapped before the
-- frame too
local mounted_root = layer(13, 0)
mounted_root.parentStatic = { interfaceID = 14, staticID = 0 }
local mounted_part = sprite(13, 1, 999, false)
mounted_part.parentStatic = mounted_root
load(13, { [0] = mounted_root, [1] = mounted_part })
tick(40)
load(14, { [0] = layer(14, 0) })
tick(5)
logic()
mounted_part.visibleGlobal = true
mounted_part.spriteID = 101
draw()
assert(mounted_part.spriteID == -1, "content of an interface mounted in a fresh one is swapped before its frame")
swapper.stop()

-- a big interface where the game creates a window's parts inside one component (like plugins'
-- windows in the main interface): the first parts are found by the pass, a little late; after
-- that the component is remembered, and what's created in it is swapped before its frame
local big = {}
for i = 1, 1700 do big[i] = sprite(15, i, 999, true) end
local plugin_layer = layer(15, 0)
big[0] = plugin_layer
load(15, big)
swapper.start(groups.names(all_on))
tick(40)
plugin_layer.children[1] = tab(15, 0, 1)
tick(40)
assert(plugin_layer.children[1].spriteID == -1, "found by the pass")
for round = 2, 6 do
  tick(3)
  logic()
  plugin_layer.children[round] = tab(15, 0, round)
  draw()
  assert(plugin_layer.children[round].spriteID == -1, "created in a remembered component: swapped before its frame")
end
swapper.stop()

-- a window that's been open a while (warm): when the game rebuilds one part of it, what it created
-- elsewhere in the window at the same time is swapped before the frame too
local list_a, list_b = layer(16, 0), layer(16, 1)
list_a.children[1] = tab(16, 0, 1)
swapper.start(groups.names(all_on))
tick(2)
load(16, { [0] = list_a, [1] = list_b })
tick(60)
for round = 1, 4 do
  tick(9 + round)
  logic()
  list_a.children = { tab(16, 0, 10 + round) }
  list_b.children[round] = tab(16, 1, round)
  draw()
  assert(list_b.children[round].spriteID == -1, "created elsewhere in a rebuilt window: swapped before its frame")
end
swapper.stop()

-- a small window's red title plate is only drawn right after the title corner; where the game
-- draws that piece on its own behind a centred title, it looks like the rest of the title bar
names[103] = "RS3_MODAL_WINDOW_1_TITLE_TILE"
id.Sprite.RS3_MODAL_WINDOW_1_TITLE_TILE = 103
Plugin.resources.frames.RS3_MODAL_WINDOW_1_TITLE_TILE = "img_plate"
Plugin.resources.frames.RS3_MODAL_WINDOW_1_TOP_TILE = "img_title_bar"
package.loaded["src/game/sprite_swapper"] = nil
local fresh_swapper = require("src/game/sprite_swapper")
local after_corner = sprite(17, 0, 103, true); after_corner.x = 28
local behind_title = sprite(17, 1, 103, true); behind_title.x = 125
load(17, { [0] = after_corner, [1] = behind_title })
fresh_swapper.start(groups.names(all_on))
tick(5)
assert(after_corner.image == "img_plate", "the plate after the title corner")
assert(behind_title.image == "img_title_bar", "no plate behind a centred title")
fresh_swapper.stop()

-- a colour scheme: grey copies are drawn and tinted, over the tint the game gave the part, and
-- everything goes back when stopped
Plugin.resources.frames_tintable = { RS3_BTN_MAIN_NEUTRAL_0 = "grey_btn0", RS3_BTN_MAIN_NEUTRAL_1 = "grey_btn1" }
local tinted = sprite(18, 0, 101, true); tinted.rgb = 0xFFFFFF
local dimmed = sprite(18, 1, 101, true); dimmed.rgb = 0x808080
local without_grey_copy = sprite(18, 2, 100, true); without_grey_copy.rgb = 0xFFFFFF; without_grey_copy.height = 1
local tinted_button = { interfaceID = 18, staticID = 3, categoryID = -1, dynamicID = -1, type = ui.ComponentType.BUTTON, visibleGlobal = true,
  sprite = sprite(18, 3, 101, true), text = { rgba = 0xE3D7CFFF, content = "Ok" } }
tinted_button.sprite.rgba = 0xFFFFFF80
local tinted_card = { interfaceID = 18, staticID = 4, categoryID = -1, dynamicID = -1, type = ui.ComponentType.RECTANGLE, visibleGlobal = true, rgb = 0x24211E }
-- a sprite whose tint is black is drawn untinted by the game (most of the Bank's are)
local black_tinted = sprite(18, 5, 101, true); black_tinted.rgb = 0x000000
load(18, { [0] = tinted, [1] = dimmed, [2] = without_grey_copy, [3] = tinted_button, [4] = tinted_card, [5] = black_tinted })
fresh_swapper.start(groups.names(all_on), { tint = 0xFF0000 })
tick(5)
assert(tinted.image == "grey_btn0" and tinted.rgb == 0xFF0000, "a grey copy is drawn, tinted")
assert(dimmed.rgb == 0x800000, "the game's own tint stays under the scheme's")
assert(black_tinted.image == "grey_btn0" and black_tinted.rgb == 0xFF0000, "a sprite with black for its tint takes the scheme's whole")
assert(without_grey_copy.image == "img_side" and without_grey_copy.rgb == 0xFFFFFF, "an image without a grey copy keeps its colours")
assert(tinted_button.sprite.image == "grey_btn0" and tinted_button.sprite.rgba == 0xFF000080, "a button's sprite is tinted, its transparency kept")
assert(tinted_card.rgb == 0x480000, "a panel gets the old colour in the scheme's colour")
assert(tinted_button.text.rgba >> 8 ~= 0xA6C7D6 and tinted_button.text.rgba & 0xFF == 0xFF, "body text leans to the scheme's colour")
-- hover: the game sets its sprite and its tint again
tinted.spriteID = 102
tinted.rgb = 0xFFFFFF
tick(1)
assert(tinted.image == "grey_btn1" and tinted.rgb == 0xFF0000, "tinted again after the game reset it")
-- the game dims a part that stays the same otherwise
tinted.rgb = 0x404040
tick(1)
assert(tinted.rgb == 0x400000, "a new tint from the game gets the scheme's on top")
fresh_swapper.stop()
assert(tinted.spriteID == 102 and tinted.rgb == 0x404040, "stopping gives back the game's sprite and tint")
assert(dimmed.rgb == 0x808080 and tinted_button.sprite.rgba == 0xFFFFFF80 and tinted_card.rgb == 0x24211E, "for every part")
assert(black_tinted.rgb == 0x000000, "and black again where it was")

-- without the grey copies (resources not loaded yet), a scheme falls back to the classic look
Plugin.resources.frames_tintable = nil
fresh_swapper.start(groups.names(all_on), { tint = 0xFF0000 })
tick(5)
assert(tinted.image == "img_btn1" and tinted.rgb == 0x404040, "classic images, untinted")
assert(tinted_card.rgb == 0x152648, "and classic colours")
fresh_swapper.stop()

-- a part of the interface with its own colour: tinted with that, whatever the scheme; the other
-- parts keep the scheme's, and in the classic scheme their own colours
Plugin.resources.frames_tintable = { RS3_BTN_MAIN_NEUTRAL_0 = "grey_btn0", RS3_BTN_MAIN_NEUTRAL_1 = "grey_btn1", RS3_PARENT_FRAME_SIDE_TILE = "grey_side" }
local part_button = sprite(20, 0, 101, true); part_button.rgb = 0xFFFFFF
local part_frame = sprite(20, 1, 100, true); part_frame.rgb = 0xFFFFFF; part_frame.height = 1
local part_card = { interfaceID = 20, staticID = 2, categoryID = -1, dynamicID = -1, type = ui.ComponentType.RECTANGLE, visibleGlobal = true, rgb = 0x24211E }
load(20, { [0] = part_button, [1] = part_frame, [2] = part_card })
fresh_swapper.start(groups.names(all_on), { own_part_tints = { buttons = 0x00FF00 } })
tick(5)
assert(part_button.image == "grey_btn0" and part_button.rgb == 0x00FF00, "a part with its own colour is tinted with it in the classic scheme")
assert(part_frame.image == "img_side" and part_frame.rgb == 0xFFFFFF, "the other parts are drawn as they were")
assert(part_card.rgb == 0x152648, "panels too")
fresh_swapper.start(groups.names(all_on), { tint = 0xFF0000, part_tints = { buttons = 0x00FF00, backgrounds = 0x0000FF } })
tick(5)
assert(part_button.rgb == 0x00FF00, "a part's own colour comes before the scheme's")
assert(part_frame.image == "grey_side" and part_frame.rgb == 0xFF0000, "the other parts get the scheme's")
assert(part_card.rgb == 0x000048, "panels get the backgrounds' colour")
-- a scheme can single out sprites by name
fresh_swapper.start(groups.names(all_on), {
  tint = 0xFF0000, part_tints = { buttons = 0x00FF00 },
  sprite_tints = { { pattern = "^RS3_BTN_MAIN_NEUTRAL_0$", tint = 0x0000FF } },
})
tick(5)
assert(part_button.rgb == 0x0000FF, "a tint for sprites of a name comes before their part's")
assert(part_frame.rgb == 0xFF0000, "the others keep their part's or the scheme's")

-- a scheme with images of its own: those are drawn as they are, the sprites it has none for as
-- in the classic scheme, or tinted where it has a tint for them
names[104] = "RS3_CHILD_HEADER_TILE"
id.Sprite.RS3_CHILD_HEADER_TILE = 104
Plugin.resources.frames.RS3_CHILD_HEADER_TILE = "img_header"
Plugin.resources.frames_tintable.RS3_CHILD_HEADER_TILE = "grey_header"
Plugin.resources.frames_other = { RS3_PARENT_FRAME_SIDE_TILE = "other_side" }
Plugin.resources.side_without_edge_other = "other_side_without_edge"
local set_header = sprite(20, 4, 104, true); set_header.rgb = 0xFFFFFF
local set_strip_side = sprite(20, 5, 100, true); set_strip_side.rgb = 0xFFFFFF
set_strip_side.parent = { height = 10 }
loaded[20][4] = set_header
loaded[20][5] = set_strip_side
local other_scheme = { image_set = "other", sprite_tints = { { pattern = "^RS3_CHILD_HEADER_", tint = 0x0000FF } } }
fresh_swapper.start(groups.names(all_on), other_scheme)
tick(5)
assert(part_frame.image == "other_side" and part_frame.rgb == 0xFFFFFF, "the scheme's own image, untinted")
assert(set_strip_side.image == "other_side_without_edge", "and its own side piece for the title strip")
assert(part_button.image == "img_btn0" and part_button.rgb == 0xFFFFFF, "a sprite it has no image for is drawn as in the classic scheme")
assert(set_header.image == "grey_header" and set_header.rgb == 0x0000FF, "or tinted where the scheme has a tint for it")
-- the player's own colour for a part comes before the scheme's image for it
fresh_swapper.start(groups.names(all_on), { image_set = "other", own_part_tints = { frames = 0x00FF00 } })
tick(5)
assert(part_frame.image == "grey_side" and part_frame.rgb == 0x00FF00, "the part is tinted with the player's colour, not drawn with the scheme's image")
Plugin.resources.frames_other = nil
fresh_swapper.start(groups.names(all_on), other_scheme)
tick(5)
assert(part_frame.image == "img_side" and set_header.image == "img_header" and set_header.rgb == 0xFFFFFF, "without its images loaded, a scheme is drawn as the classic one")
fresh_swapper.stop()
assert(part_button.rgb == 0xFFFFFF and part_frame.rgb == 0xFFFFFF and part_card.rgb == 0x24211E, "stopping gives everything back")
Plugin.resources.frames_tintable = nil

-- the player's own text colours replace the old look's, in any scheme
local heading = { interfaceID = 19, staticID = 0, categoryID = -1, dynamicID = -1, type = ui.ComponentType.LABEL, visibleGlobal = true, rgb = 0xF0BE79, content = "Heading" }
local body = { interfaceID = 19, staticID = 1, categoryID = -1, dynamicID = -1, type = ui.ComponentType.LABEL, visibleGlobal = true, rgb = 0xE3D7CF, content = "Body" }
load(19, { [0] = heading, [1] = body })
fresh_swapper.start(groups.names(all_on), { heading_text = 0x112233, body_text = 0x445566 })
tick(5)
assert(heading.rgb == 0x112233, "a heading gets the player's heading colour")
assert(body.rgb == 0x445566, "other text gets the player's body colour")
assert(tinted_card.rgb == 0x152648, "panels keep the classic colour")
fresh_swapper.stop()
assert(heading.rgb == 0xF0BE79 and body.rgb == 0xE3D7CF, "stopping gives back the game's text colours")

-- nothing above made the plugin print an error (but for the one asked for)
assert(#errors == 1, "unexpected error: " .. tostring(errors[2]))
