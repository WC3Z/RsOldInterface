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
local subs = { Logic = {}, Draw = {}, KeyDown = {}, ServerLogic = {} }
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
events.enable({ profile = true, activity_log = true, benchmark = true })
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

-- measuring the cost: steps are left out in turns, the averages are printed after each round, and
-- everything is swapped again afterwards
profile.cost_phase_updates = 20
profile.cost_starts_at_update = 5
local cost_lines = {}
print = function (text)
  if tostring(text):find("cost after") then cost_lines[#cost_lines + 1] = text end
  if tostring(text):find("error") then errors[#errors + 1] = text end
end
events.enable({ profile = true, cost = true })
swapper.start(groups.names(all_on))
local skipped_steps = {}
for _ = 1, 1200 do
  logic()
  for _, step in ipairs({ "the pass", "colour checks", "hot checks" }) do
    if events.skips(step) then skipped_steps[step] = true end
  end
  for _, handler in pairs(subs.Draw) do handler({ timeDeltaSecs = events.skips("all of it") and 0.008 or 0.010 }) end
  for _, handler in pairs(subs.Draw) do handler({ timeDeltaSecs = 0.010 }) end
end
events.disable()
print = print_before_debugging
assert(#errors == 0, "no errors while measuring the cost: " .. tostring(errors[1]))
assert(#cost_lines >= 2, "a line of costs after each round")
assert(skipped_steps["the pass"] and skipped_steps["colour checks"] and skipped_steps["hot checks"], "each step was left out in turn")
assert(cost_lines[#cost_lines]:find("all of it 1%.9%d"), "the cost of all of it from the shorter frames: " .. cost_lines[#cost_lines])
assert(not events.skips("the pass"), "nothing is left out once the tools are off")
loaded[5][1].spriteID = 102
tick(8)
assert(loaded[5][1].spriteID == -1, "swapped again after the measuring")
swapper.stop()

-- the layout listing prints where matching swapped sprites are, and the texts over them
local layout_lines = {}
print = function (text)
  if tostring(text):find("layout: ") then layout_lines[#layout_lines + 1] = text end
  if tostring(text):find("error") then errors[#errors + 1] = text end
end
loaded[5][1].xyGlobal, loaded[5][1].x, loaded[5][1].width, loaded[5][1].height = { x = 40, y = 100 }, 4, 76, 76
label.xyGlobal, label.x, label.width, label.height = { x = 60, y = 120 }, 24, 90, 20
events.enable({ layout = "^RS3_BTN_MAIN_NEUTRAL_" })
swapper.start(groups.names(all_on))
tick(160)
swapper.stop()
events.disable()
print = print_before_debugging
assert(#errors == 0, "no errors while listing the layout: " .. tostring(errors[1]))
local all_layout = table.concat(layout_lines, "\n")
assert(all_layout:find("at 40,100 size 76x76", 1, true), "the piece's place and size: " .. all_layout)
assert(all_layout:find('LABEL "MANUAL SETUP" font', 1, true) and all_layout:find("at 60,120 size 90x20", 1, true), "and the text over it")

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

-- the same sprite is drawn the same wherever it is in a small window's title bar: the bar has no
-- title plate
names[103] = "RS3_MODAL_WINDOW_1_TITLE_TILE"
id.Sprite.RS3_MODAL_WINDOW_1_TITLE_TILE = 103
Plugin.resources.frames.RS3_MODAL_WINDOW_1_TITLE_TILE = "img_title_bar"
package.loaded["src/game/sprite_swapper"] = nil
local fresh_swapper = require("src/game/sprite_swapper")
local after_corner = sprite(17, 0, 103, true); after_corner.x = 28
local behind_title = sprite(17, 1, 103, true); behind_title.x = 125
load(17, { [0] = after_corner, [1] = behind_title })
fresh_swapper.start(groups.names(all_on))
tick(5)
assert(after_corner.image == "img_title_bar" and behind_title.image == "img_title_bar", "the plain bar in both places")
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

-- textured panels: the pieces of the panels inside windows are drawn see-through, whatever the
-- scheme, so the window's own texture shows there
names[105] = "RS3_PARENT_CONTENT_TAB_FRAME_4"
id.Sprite.RS3_PARENT_CONTENT_TAB_FRAME_4 = 105
Plugin.resources.frames.RS3_PARENT_CONTENT_TAB_FRAME_4 = "img_panel"
Plugin.resources.frames_tintable = { RS3_PARENT_CONTENT_TAB_FRAME_4 = "grey_panel" }
Plugin.resources.see_through = "img_see_through"
local panel = sprite(22, 0, 105, true); panel.rgb = 0xFFFFFF
load(22, { [0] = panel })
fresh_swapper.start(groups.names(all_on))
tick(5)
assert(panel.image == "img_panel", "a panel is the plain blue image")
-- a sprite without an image of its own is drawn with another's
names[106] = "OLD_BACKGROUND_TEXTURE"
id.Sprite.OLD_BACKGROUND_TEXTURE = 106
local plugin_texture = sprite(22, 1, 106, true); plugin_texture.rgb = 0xFFFFFF
loaded[22][1] = plugin_texture
load(22, loaded[22])
fresh_swapper.start(groups.names(all_on))
tick(5)
assert(plugin_texture.image == "img_panel", "another plugin's panel texture is drawn as a plain panel")
fresh_swapper.start(groups.names(all_on), { tint = 0xFF0000 }, { textured_panels = true })
tick(5)
assert(plugin_texture.image == "grey_panel" and plugin_texture.rgb == 0xFF0000, "tinted with the scheme, and not see-through with textured panels")
assert(panel.image == "img_see_through" and panel.rgb == 0xFFFFFF, "with textured panels it's see-through and untinted, in a tinted scheme too")
fresh_swapper.stop()
assert(panel.spriteID == 105, "and the game's again when stopped")
Plugin.resources.frames_tintable = nil

-- another plugin's window: rectangles the game created in the main interface, in the current
-- look's browns, get the old panel blue; gold lines and the game's own static rectangles don't
id.Interface.TOPLEVEL_V2 = 1477
id.Interface.BANK = 517
for _, name in ipairs({ "src/game/recolourer", "src/game/sprite_swapper" }) do package.loaded[name] = nil end
local plugin_swapper = require("src/game/sprite_swapper")
local function rectangle(iface, static, dynamic, rgb)
  return { interfaceID = iface, staticID = static, categoryID = dynamic and 0 or -1, dynamicID = dynamic or -1, type = ui.ComponentType.RECTANGLE, visibleGlobal = true, rgb = rgb }
end
local plugin_layer = { interfaceID = 1477, staticID = 0, categoryID = -1, dynamicID = -1, type = ui.ComponentType.LAYER, visibleGlobal = true, children = {} }
function plugin_layer:IterateDynamicComponents(callback) for _, child in ipairs(self.children) do callback(child) end end
local plugin_panel, plugin_row, plugin_gold_line = rectangle(1477, 0, 1, 0x332E29), rectangle(1477, 0, 2, 0x49371F), rectangle(1477, 0, 3, 0x806432)
plugin_layer.children = { plugin_panel, plugin_row, plugin_gold_line }
local game_brown = rectangle(1477, 1, nil, 0x332E29)
local other_window_brown = rectangle(23, 0, 1, 0x332E29)
local other_layer = { interfaceID = 23, staticID = 0, categoryID = -1, dynamicID = -1, type = ui.ComponentType.LAYER, visibleGlobal = true, children = { other_window_brown } }
function other_layer:IterateDynamicComponents(callback) for _, child in ipairs(self.children) do callback(child) end end
local bank_page_brown = rectangle(517, 0, 1, 0x332E29)
local bank_layer = { interfaceID = 517, staticID = 0, categoryID = -1, dynamicID = -1, type = ui.ComponentType.LAYER, visibleGlobal = true, children = { bank_page_brown } }
function bank_layer:IterateDynamicComponents(callback) for _, child in ipairs(self.children) do callback(child) end end
load(517, { [0] = bank_layer })
load(1477, { [0] = plugin_layer, [1] = game_brown })
load(23, { [0] = other_layer })
plugin_swapper.start(groups.names(all_on))
tick(5)
assert(plugin_panel.rgb == 0x1E3146, "another plugin's brown panel gets the old panel blue")
assert(plugin_row.rgb == 0x2B4664, "a lighter brown gets a lighter blue: " .. string.format("%06X", plugin_row.rgb))
assert(plugin_gold_line.rgb == 0x806432, "gold lines stay gold")
assert(bank_page_brown.rgb == 0x1E3146, "a page another plugin added to the Bank gets it too")
assert(game_brown.rgb == 0x332E29, "the game's own rectangle in that colour is left alone")
assert(other_window_brown.rgb == 0x332E29, "and so is one in a window of the game's")
Plugin.resources.frames_tintable = {}
plugin_swapper.start(groups.names(all_on), { tint = 0xFF0000 })
tick(5)
assert(plugin_panel.rgb == 0x460000, "in a tinted scheme it's the scheme's colour")
plugin_swapper.stop()
Plugin.resources.frames_tintable = nil
assert(plugin_panel.rgb == 0x332E29 and plugin_row.rgb == 0x49371F, "stopping gives back the plugin's own colours")
id.Interface.TOPLEVEL_V2 = nil
id.Interface.BANK = nil
loaded[517] = nil
for _, name in ipairs({ "src/game/recolourer", "src/game/sprite_swapper" }) do package.loaded[name] = nil end
fresh_swapper = require("src/game/sprite_swapper")

-- a window's close button keeps its own colours in every scheme, and whatever the player's own
-- colour for buttons
names[107] = "RS3_BTN_MODAL_WINDOW_1_CLOSE_NML"
id.Sprite.RS3_BTN_MODAL_WINDOW_1_CLOSE_NML = 107
Plugin.resources.frames.RS3_BTN_MODAL_WINDOW_1_CLOSE_NML = "img_close"
Plugin.resources.frames_tintable = { RS3_BTN_MODAL_WINDOW_1_CLOSE_NML = "grey_close" }
local close_button = sprite(24, 0, 107, true); close_button.rgb = 0xFFFFFF
load(24, { [0] = close_button })
fresh_swapper.start(groups.names(all_on), { tint = 0xFF0000, own_part_tints = { small_buttons = 0x00FF00 } })
tick(5)
assert(close_button.image == "img_close" and close_button.rgb == 0xFFFFFF, "the close button is drawn in its own colours")
fresh_swapper.stop()
Plugin.resources.frames_tintable = nil

-- a big window's title plate: the end piece and the bar are drawn with the plate as much longer
-- as the title needs, in steps; the usual pieces without a title; no red at all when turned off
names[110], names[111], names[112] = "RS3_PARENT_BANNER_SWORD_LEFT", "RS3_PARENT_BANNER_SWORD_RIGHT", "RS3_PARENT_BANNER_BAR_TILE"
for sprite_id = 110, 112 do
  id.Sprite[names[sprite_id]] = sprite_id
  Plugin.resources.frames[names[sprite_id]] = "img_" .. names[sprite_id]
end
for _, image in ipairs({ "RS3_PARENT_BANNER_SWORD_RIGHT_LONGER_96", "RS3_PARENT_BANNER_BAR_TILE_LONGER_96",
  "RS3_PARENT_BANNER_SWORD_RIGHT_LONGER_176", "RS3_PARENT_BANNER_BAR_TILE_LONGER_256",
  "RS3_PARENT_BANNER_SWORD_LEFT_NO_PLATE", "RS3_PARENT_BANNER_SWORD_RIGHT_NO_PLATE_LONGER_96",
  "RS3_PARENT_BANNER_BAR_TILE_NO_PLATE_LONGER_96", "RS3_PARENT_BANNER_SWORD_RIGHT_NO_PLATE_LONGER_0" }) do
  Plugin.resources.frames[image] = "img_" .. image
end
local pixels_per_letter = 10
config.Font = { FromID = function (font_id)
  return font_id == 60 and { GetStringWidth = function (_, text) return #text * pixels_per_letter end } or nil
end }
local banner = { interfaceID = 25, staticID = 0, categoryID = -1, dynamicID = -1, type = ui.ComponentType.LAYER, visibleGlobal = true }
function banner:IterateDynamicComponents(callback) for _, child in ipairs(self.children) do callback(child) end end
local function banner_piece(dynamic_id, sprite_id)
  local piece = sprite(25, 0, sprite_id, true)
  piece.categoryID, piece.dynamicID, piece.parentStatic, piece.parent = 0, dynamic_id, banner, banner
  return piece
end
local plate_start, plate_end, plate_bar = banner_piece(1, 110), banner_piece(5, 111), banner_piece(4, 112)
local window_title = { interfaceID = 25, staticID = 0, categoryID = 0, dynamicID = 14, type = ui.ComponentType.LABEL, visibleGlobal = true,
  rgb = 0x00FF00, x = 64, y = -4, content = "Plugin Hub", font = 60 }
banner.children = { plate_start, plate_end, plate_bar, window_title }
load(25, { [0] = banner })
local function reset_banner()
  plate_start.spriteID, plate_end.spriteID, plate_bar.spriteID = 110, 111, 112
end
package.loaded["src/game/sprite_swapper"] = nil
fresh_swapper = require("src/game/sprite_swapper")
fresh_swapper.start(groups.names(all_on))
tick(5)
-- The title ends at 64 + 100; the plate has to reach 8 past that, 91 further than its own end at 81.
assert(plate_end.image == "img_RS3_PARENT_BANNER_SWORD_RIGHT_LONGER_96", "the end piece with the plate long enough for the title: " .. tostring(plate_end.image))
assert(plate_bar.image == "img_RS3_PARENT_BANNER_BAR_TILE_LONGER_96", "and the bar that carries it on")
assert(plate_start.image == "img_RS3_PARENT_BANNER_SWORD_LEFT", "the start piece as it is")
-- another big window opens in the same frame: the game changes the title and leaves the sprites
window_title.content = "A title much longer than any plate there is an image for"
tick(2)
assert(plate_end.image == "img_RS3_PARENT_BANNER_SWORD_RIGHT_LONGER_176", "a long title: the end piece is all plate")
assert(plate_bar.image == "img_RS3_PARENT_BANNER_BAR_TILE_LONGER_256", "and the bar has the longest plate there is")
window_title.content = ""
tick(2)
assert(plate_end.image == "img_RS3_PARENT_BANNER_SWORD_RIGHT" and plate_bar.image == "img_RS3_PARENT_BANNER_BAR_TILE", "without a title, the usual pieces")
fresh_swapper.stop()
reset_banner()
window_title.content = "Plugin Hub"
fresh_swapper.start(groups.names(all_on), nil, { title_plates = false })
tick(5)
assert(plate_start.image == "img_RS3_PARENT_BANNER_SWORD_LEFT_NO_PLATE", "plates turned off: the start piece as plain bar")
assert(plate_end.image == "img_RS3_PARENT_BANNER_SWORD_RIGHT_NO_PLATE_LONGER_96" and plate_bar.image == "img_RS3_PARENT_BANNER_BAR_TILE_NO_PLATE_LONGER_96",
  "and the bar's line starting after the title: " .. tostring(plate_end.image))
window_title.content = ""
tick(2)
assert(plate_end.image == "img_RS3_PARENT_BANNER_SWORD_RIGHT_NO_PLATE_LONGER_0" and plate_bar.image == "img_RS3_PARENT_BANNER_BAR_TILE",
  "without a title, the line from the start and the usual bar")
fresh_swapper.stop()
loaded[25] = nil

load(26, { [0] = big_list })
-- the slow walk over hidden content only visits so many of the parts the game created in one
-- component at a time; the rest are found when the window shows
local big_list = { interfaceID = 26, staticID = 0, categoryID = -1, dynamicID = -1, type = ui.ComponentType.LAYER, visibleGlobal = false, children = {} }
local callbacks_made = 0
function big_list:IterateDynamicComponents(callback)
  for _, child in ipairs(self.children) do
    callbacks_made = callbacks_made + 1
    if callback(child) then return end
  end
end
load(26, { [0] = big_list })
fresh_swapper.start(groups.names(all_on))
logic() draw()
-- The game fills the list in while it's hidden.
for index = 1, 3000 do
  local row = sprite(26, 0, 101, false)
  row.categoryID, row.dynamicID = 0, index
  big_list.children[index] = row
end
callbacks_made = 0
local most_callbacks_in_an_update = 0
for _ = 1, 600 do
  local before = callbacks_made
  tick(1)
  most_callbacks_in_an_update = math.max(most_callbacks_in_an_update, callbacks_made - before)
end
assert(big_list.children[1].spriteID == -1, "the first hidden rows are swapped by the slow walk")
assert(big_list.children[3000].spriteID == 101, "the ones past the limit aren't")
assert(most_callbacks_in_an_update < 1000, "and the slow walk never went through all of them in one go: " .. most_callbacks_in_an_update)
big_list.visibleGlobal = true
for _, row in ipairs(big_list.children) do row.visibleGlobal = true end
tick(3)
assert(big_list.children[3000].spriteID == -1, "all of them once the window shows")
fresh_swapper.stop()
loaded[26] = nil

-- once it's been quiet for a while, a showing button is checked after every update only while the
-- mouse is near it; elsewhere within a few updates, or at once after a key press
local hover_button = sprite(27, 0, 101, true)
hover_button.xyGlobal, hover_button.width, hover_button.height = { x = 100, y = 200 }, 40, 20
local far_button = sprite(27, 1, 101, true)
far_button.xyGlobal, far_button.width, far_button.height = { x = 600, y = 200 }, 40, 20
load(27, { [0] = hover_button, [1] = far_button })
local mouse = { x = 110, y = 205 }
Mouse = { IsAvailable = function () return true end, GetX = function () return mouse.x end, GetY = function () return mouse.y end }
fresh_swapper.start(groups.names(all_on))
tick(400)
-- The game gives the buttons their hover sprite, as it does when the mouse comes over one.
local function updates_until_swapped_again(button)
  button.spriteID = 102
  for updates = 1, 10 do
    logic() draw()
    if button.spriteID == -1 then return updates end
    draw()
  end
  return math.huge
end
assert(updates_until_swapped_again(hover_button) == 1, "near the mouse: swapped again before the next frame")
tick(400)
local updates_away = updates_until_swapped_again(far_button)
assert(updates_away <= 8, "away from the mouse: within a few updates, not " .. updates_away)
tick(400)
mouse.x = 610
assert(updates_until_swapped_again(far_button) == 1, "the mouse moved there: before the next frame")
tick(400)
mouse.x = 110
for _, handler in pairs(subs.KeyDown) do handler({}) end
assert(updates_until_swapped_again(far_button) == 1, "after a key press: before the next frame, wherever the mouse is")
-- a button that was hidden when last looked at comes to show without anything telling the plugin
-- (a tab switched inside a window): hovering it is still caught before the next frame
local tab_button = sprite(27, 2, 101, false)
tab_button.xyGlobal, tab_button.width, tab_button.height = { x = 300, y = 400 }, 40, 20
loaded[27][2] = tab_button
tick(400)
assert(tab_button.spriteID == -1, "the hidden button is swapped")
tab_button.visibleGlobal = true
mouse.x, mouse.y = 310, 405
assert(updates_until_swapped_again(tab_button) == 1, "hovered right after it came to show: swapped again before the next frame")
-- and the game giving a button its hover sprite on a frame between updates is caught on that frame
tick(400)
logic() draw()
hover_button.spriteID = 102
mouse.x, mouse.y = 110, 205
draw()
assert(hover_button.spriteID == -1, "hover sprite given between updates: swapped again before that frame")
-- a recoloured panel the mouse is over gets its colour back before the next frame when the game
-- sets its own again (as it does when the mouse comes over it or leaves); one elsewhere, within a
-- few updates
local hover_card = { interfaceID = 27, staticID = 3, categoryID = -1, dynamicID = -1, type = ui.ComponentType.RECTANGLE, visibleGlobal = true,
  rgb = 0x24211E, xyGlobal = { x = 100, y = 300 }, width = 200, height = 80 }
local far_card = { interfaceID = 27, staticID = 4, categoryID = -1, dynamicID = -1, type = ui.ComponentType.RECTANGLE, visibleGlobal = true,
  rgb = 0x24211E, xyGlobal = { x = 600, y = 300 }, width = 200, height = 80 }
loaded[27][3], loaded[27][4] = hover_card, far_card
tick(400)
assert(hover_card.rgb == 0x152648 and far_card.rgb == 0x152648, "both cards recoloured")
local function updates_until_recoloured(rectangle_component)
  rectangle_component.rgb = 0x24211E
  for updates = 1, 10 do
    logic() draw()
    if rectangle_component.rgb == 0x152648 then return updates end
    draw()
  end
  return math.huge
end
mouse.x, mouse.y = 150, 340
tick(8)
assert(updates_until_recoloured(hover_card) == 1, "under the mouse: recoloured before the next frame")
tick(400)
local updates_for_far_card = updates_until_recoloured(far_card)
assert(updates_for_far_card <= 4, "away from the mouse: within a few updates, not " .. updates_for_far_card)
mouse.x = 900
tick(1)
assert(updates_until_recoloured(hover_card) <= 4, "after the mouse left")
fresh_swapper.stop()
Mouse = nil
loaded[27] = nil

-- once it's been quiet for a while, a window that opens right after the server sent something
-- is still swapped before its first frame; one that opens with nothing from the server, within a
-- couple of updates, or a few if it's the first time it loads
local function packet() for _, handler in pairs(subs.ServerLogic) do handler() end end
local function updates_until_swapped(component)
  for updates = 1, 12 do
    logic() draw()
    if component.spriteID == -1 then return updates end
    draw()
  end
  return math.huge
end
local window_piece = sprite(28, 0, 101, false)
load(28, { [0] = window_piece })
fresh_swapper.start(groups.names(all_on))
tick(400)
window_piece.spriteID = 101
window_piece.visibleGlobal = true
packet()
assert(updates_until_swapped(window_piece) == 1, "shown after a packet: swapped before its first frame")
window_piece.visibleGlobal = false
tick(700)
window_piece.spriteID = 101
window_piece.visibleGlobal = true
local updates_without_packet = updates_until_swapped(window_piece)
assert(updates_without_packet <= 2, "shown with nothing from the server: within two updates, not " .. updates_without_packet)
tick(700)
local new_window_piece = sprite(29, 0, 101, true)
packet()
load(29, { [0] = new_window_piece })
assert(updates_until_swapped(new_window_piece) == 1, "loaded for the first time after a packet: swapped before its first frame")
tick(700)
local late_window_piece = sprite(30, 0, 101, true)
load(30, { [0] = late_window_piece })
local updates_for_first_load = updates_until_swapped(late_window_piece)
assert(updates_for_first_load <= 8, "loaded for the first time with nothing from the server: within a few updates, not " .. updates_for_first_load)
loaded[30] = nil
tick(700)
late_window_piece.spriteID = 101
load(30, { [0] = late_window_piece })
assert(updates_until_swapped(late_window_piece) == 1, "loaded again later: swapped before its first frame, as its ID is known")
fresh_swapper.stop()
loaded[28], loaded[29], loaded[30] = nil, nil, nil

-- the game building many hidden parts again at once (the HUD behind a loading screen) doesn't
-- make them all checked after every update from then on
local hud = { [0] = sprite(31, 0, 999, true) }
for index = 1, 400 do hud[index] = sprite(31, index, 101, false) end
load(31, hud)
fresh_swapper.start(groups.names(all_on))
tick(400)
for index = 1, 400 do hud[index].spriteID = 102 end
tick(400)
for index = 1, 400 do assert(hud[index].spriteID == -1, "the rebuilt parts are swapped again, in turns") end
for index = 1, 100 do hud[index].spriteID = 102 end
logic() draw()
local swapped_at_once = 0
for index = 1, 100 do
  if hud[index].spriteID == -1 then swapped_at_once = swapped_at_once + 1 end
end
assert(swapped_at_once <= 50, "and are still only checked in turns afterwards, not all at once: " .. swapped_at_once)
fresh_swapper.stop()
loaded[31] = nil

-- Lua is asked to collect a little garbage after every update, and not on the frames in between
local collect_before = collectgarbage
local steps_asked_for = 0
collectgarbage = function (what, ...)
  if what == "step" then steps_asked_for = steps_asked_for + 1 end
  return collect_before(what, ...)
end
fresh_swapper.start(groups.names(all_on))
tick(20)
collectgarbage = collect_before
fresh_swapper.stop()
assert(steps_asked_for == 20, "one step of collecting per update, not " .. steps_asked_for)

-- a component's type is read from the game once for each time a walk comes to it, not once for
-- every piece of code that wants to know it
local type_reads = 0
local plain_layer = setmetatable({ interfaceID = 32, staticID = 0, categoryID = -1, dynamicID = -1, visibleGlobal = true, children = {} }, {
  __index = function (_, field)
    if field == "type" then
      type_reads = type_reads + 1
      return ui.ComponentType.LAYER
    end
    return nil
  end,
})
function plain_layer:IterateDynamicComponents(callback) for _, child in ipairs(self.children) do callback(child) end end
fresh_swapper.start(groups.names(all_on))
tick(5)
load(32, { [0] = plain_layer })
type_reads = 0
logic() draw()
assert(type_reads >= 1 and type_reads <= 2, "read once per walk that came to it in the update it loaded, not " .. type_reads)
fresh_swapper.stop()
loaded[32] = nil

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
