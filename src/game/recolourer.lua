-- Gives the game's plain colours the old look's: the coloured rectangles behind lists and cards,
-- and text. The game's colours come from its skin, and skin_palette knows the old colour for
-- each; in a colour scheme other than the classic one that colour is tinted too (see
-- colour_scheme). The game sets its own colours again when it rebuilds things, so the recoloured
-- parts are remembered and checked after every update.
local interface_walker = require("src/game/interface_walker")
local sprite_groups = require("src/game/sprite_groups")
local skin_palette = require("src/game/skin_palette")
local colour_scheme = require("src/game/colour_scheme")
local component_fields = require("src/game/component_fields")
local game_ids = require("src/game/game_ids")
local events = require("src/game/debug_tools").events

local recolourer = {}

-- Where each component type keeps a colour that comes from the skin, and the sprite group that
-- has to be on for it to be changed: a rectangle's or a text's own colour (the empty name), or an
-- interactive component's text.
---@type table<string, { group: string, field: string, is_text: boolean }>
local skin_coloured_fields = {
    [ui.ComponentType.RECTANGLE] = { group = "colours", field = "", is_text = false },
    [ui.ComponentType.LABEL] = { group = "text_colours", field = "", is_text = true },
    [ui.ComponentType.BUTTON] = { group = "text_colours", field = "text", is_text = true },
    [ui.ComponentType.CHECK] = { group = "text_colours", field = "text", is_text = true },
    [ui.ComponentType.INPUTFIELD] = { group = "text_colours", field = "text", is_text = true },
}

-- A recoloured colour: the component's IDs and field, to find it again, and both colours.
---@class RecolouredColour : ComponentIds
---@field field string
---@field game_rgb integer The colour the game gave it, which it gets back when the plugin stops.
---@field applied_rgb integer The colour the plugin gave it.
---@field visible boolean Whether it was showing when last looked at.
---@field is_text boolean
---@field turn integer Which of the updates it's checked in while it's quiet.
---@field left number? Where it was on screen when last looked at.
---@field top number?
---@field right number?
---@field bottom number?
---@field near_mouse boolean Whether the mouse was near it at the last update.
---@field checks_since_place integer How many times it was looked at since its place was last read.

-- Hidden recoloured colours are only checked every this many updates: they can't flash.
local hidden_check_interval = 10
-- While it's quiet (nothing from the server, opened, rebuilt or pressed for a few updates), showing ones
-- are checked every few updates, each in its own turn, and hidden ones more rarely still.
local quiet_check_interval = 4
local near_mouse_margin = 12
local checks_between_places = 4
local quiet_hidden_check_interval = 40
-- How many colours were recoloured for the first time, to give each its turn.
local colours_made = 0
-- The keys of the recoloured colours that were showing when last looked at, and whether colours
-- were recoloured for the first time since the list was made (see recolourer.recolour_changed).
---@type string[]
local showing_keys = {}
local showing_keys_are_stale = true

-- Interfaces whose colours are left alone: hover tooltips are rebuilt for every hover, so their
-- text would change colour a moment after showing each time.
local interface_ids_left_alone = game_ids.interface_ids({ "TEXT_TOOLTIP" })

---@type table<string, boolean>
local swapped_groups = {}
---@type SchemeColours
local colours = {}
-- Called when a showing component is recoloured for the first time.
---@type fun(component: ui.Component, walk_kind: WalkKind)
local on_new = function () end
-- Keyed by interface_walker.component_key and the field.
---@type table<string, RecolouredColour>
local recoloured = {}
-- The look's colour for each game colour worked out so far (false for none): rectangles' and
-- texts' separately.
---@type table<integer, integer|false>, table<integer, integer|false>
local rectangle_colours, text_colours = {}, {}
-- The same for the browns other plugins draw their panels in (see plugin_panel_colour).
---@type table<integer, integer|false>
local plugin_panel_colours = {}

-- The colour the look gives a rectangle or text with the given game colour, or nil if it leaves
-- it alone.
---@param game_rgb integer
---@param is_text boolean
---@return integer?
local function look_colour(game_rgb, is_text)
    local cache = is_text and text_colours or rectangle_colours
    local look_rgb = cache[game_rgb]
    if look_rgb == nil then
        if is_text then
            local old_rgb = skin_palette.old_text_colour(game_rgb)
            look_rgb = old_rgb and colour_scheme.text_colour(old_rgb, colours)
        else
            local old_rgb = skin_palette.old_colour(game_rgb)
            local tint = colour_scheme.part_tint(colours, sprite_groups.panels_part)
            look_rgb = old_rgb and tint and colour_scheme.tinted(old_rgb, tint) or old_rgb
        end
        cache[game_rgb] = look_rgb or false
    end
    return look_rgb or nil
end

-- Other plugins make their windows in the main interface, and some add pages to the Bank. So
-- rectangles created while running in those two, in the current look's browns, get the old panel
-- colour (see skin_palette.old_panel_colour).
local interface_ids_with_plugin_panels = game_ids.interface_ids({ "TOPLEVEL_V2", "BANK" })

---@param component ui.Component
---@param game_rgb integer
---@return integer?
local function plugin_panel_colour(component, game_rgb)
    local look_rgb = plugin_panel_colours[game_rgb]
    if look_rgb == nil then
        local old_rgb = skin_palette.old_panel_colour(game_rgb)
        local tint = colour_scheme.part_tint(colours, sprite_groups.panels_part)
        look_rgb = old_rgb and tint and colour_scheme.tinted(old_rgb, tint) or old_rgb or false
        plugin_panel_colours[game_rgb] = look_rgb
    end
    -- Most colours aren't such a brown, and are told by the colour alone.
    if look_rgb and interface_ids_with_plugin_panels[component.interfaceID] and component_fields.is_created(component) then
        return look_rgb
    end
    return nil
end

-- The colour the look gives one of a component's colours, or nil if it leaves it alone.
---@param component ui.Component
---@param game_rgb integer
---@param is_text boolean
---@return integer?
local function look_colour_of(component, game_rgb, is_text)
    local look_rgb = look_colour(game_rgb, is_text)
    if look_rgb == nil and not is_text then
        look_rgb = plugin_panel_colour(component, game_rgb)
    end
    return look_rgb
end

---@param component ui.Component
---@param field string
---@return integer?
local function read_colour(component, field)
    local holder = component_fields.holder(component, field)
    return holder and component_fields.read_rgb(holder, field)
end

---@param component ui.Component
---@param field string
---@param rgb integer
---@return boolean # Whether it took.
local function write_colour(component, field, rgb)
    local holder = component_fields.holder(component, field)
    return holder ~= nil and component_fields.write_rgb(holder, field, rgb)
end

-- Notes where a recoloured component is on screen, for telling later whether the mouse is near it.
---@param colour RecolouredColour
---@param component ui.Component
local function note_place(colour, component)
    local position = component.xyGlobal
    colour.left, colour.top = position.x, position.y
    colour.right, colour.bottom = position.x + component.width, position.y + component.height
end

---@param colour RecolouredColour
---@param mouse_x number?
---@param mouse_y number?
---@return boolean
local function is_near_mouse(colour, mouse_x, mouse_y)
    if mouse_x == nil or mouse_y == nil or colour.left == nil then
        return false
    end
    return mouse_x >= colour.left - near_mouse_margin and mouse_x <= colour.right + near_mouse_margin
        and mouse_y >= colour.top - near_mouse_margin and mouse_y <= colour.bottom + near_mouse_margin
end

-- Gives a component's skin colour the look's, if it has one. Called for every component walked,
-- so it does as little as it can for the many with nothing to change.
---@param component ui.Component
---@param component_type string The component's type, which the walk has read already.
---@param walk_kind WalkKind
function recolourer.recolour(component, component_type, walk_kind)
    local coloured = skin_coloured_fields[component_type]
    if coloured == nil or not swapped_groups[coloured.group] then
        return
    end
    local field = coloured.field
    local game_rgb = read_colour(component, field)
    local look_rgb = game_rgb and look_colour_of(component, game_rgb, coloured.is_text)
    -- Most colours have none: those are told by the colour alone, without working out the
    -- component's key (which reads four IDs).
    if look_rgb == nil or interface_ids_left_alone[component.interfaceID] then
        return
    end
    local key = interface_walker.component_key(component) .. ":" .. field
    local known = recoloured[key]
    if known and game_rgb == known.applied_rgb then
        return
    end
    if events.enabled then
        events.recolouring(component, field, game_rgb, look_rgb)
    end
    if not write_colour(component, field, look_rgb) then
        return
    end
    local is_showing = component.visibleGlobal
    if known == nil and is_showing then
        on_new(component, walk_kind)
        if events.enabled then
            events.found_late(component.interfaceID, coloured.is_text and "a text colour" or "a panel colour", walk_kind)
        end
    end
    if known == nil then
        colours_made = colours_made + 1
        showing_keys_are_stale = true
    end
    recoloured[key] = {
        interface_id = component.interfaceID,
        static_id = component.staticID,
        category_id = component.categoryID,
        dynamic_id = component.dynamicID,
        field = field,
        game_rgb = game_rgb,
        applied_rgb = look_rgb,
        visible = is_showing,
        is_text = coloured.is_text,
        turn = known and known.turn or colours_made,
        near_mouse = false,
        checks_since_place = 0,
    }
    if is_showing then
        pcall(note_place, recoloured[key], component)
    end
end

-- The component a recoloured colour is on, if it's still there and still the same kind.
---@param colour RecolouredColour
---@return ui.Component?
local function find(colour)
    local component = component_fields.find(colour)
    local coloured = component and skin_coloured_fields[component.type]
    -- The game can reuse a component's IDs for another type of component.
    if coloured and coloured.field == colour.field then
        return component
    end
    return nil
end

-- Gives a recoloured colour the look's colour again if the game has set its own since, and forgets
-- it if its component is gone.
---@param key string
---@param colour RecolouredColour
---@return boolean # Whether its component is still there.
local function check(key, colour)
    local component = find(colour)
    if component == nil then
        recoloured[key] = nil
        return false
    end
    colour.visible = component.visibleGlobal
    -- Where it is now only matters once the mouse comes near, and reading it is several reads from
    -- the game: every time for what's near the mouse, every few checks for the rest.
    colour.checks_since_place = colour.checks_since_place + 1
    local place_is_due = colour.left == nil or colour.near_mouse or colour.checks_since_place >= checks_between_places
    if colour.visible and place_is_due then
        colour.checks_since_place = 0
        pcall(note_place, colour, component)
    end
    local game_rgb = read_colour(component, colour.field)
    local look_rgb = game_rgb and game_rgb ~= colour.applied_rgb and look_colour_of(component, game_rgb, colour.is_text)
    if look_rgb and write_colour(component, colour.field, look_rgb) then
        colour.game_rgb = game_rgb
        colour.applied_rgb = look_rgb
    end
    return true
end

-- Gives the look's colour again where the game has set its own since. Showing colours are kept
-- on a list of their own, so that most updates don't have to go through every recoloured colour
-- (hundreds, most of them hidden). Every few updates all of them are looked at, hidden ones too,
-- and the list is made anew.
---@param update_number integer
---@param is_quiet boolean Whether nothing is likely to be changing (see interface_watcher.is_alert).
---@param mouse_x number? Where the mouse is, if that can be told.
---@param mouse_y number?
function recolourer.recolour_changed(update_number, is_quiet, mouse_x, mouse_y)
    local checks_all = update_number % (is_quiet and quiet_hidden_check_interval or hidden_check_interval) == 0
    local checked = 0
    if checks_all then
        showing_keys = {}
        for key, colour in pairs(recoloured) do
            if check(key, colour) then
                checked = checked + 1
                if colour.visible then
                    showing_keys[#showing_keys + 1] = key
                end
            end
        end
        showing_keys_are_stale = false
    else
        if showing_keys_are_stale then
            showing_keys = {}
            for key, colour in pairs(recoloured) do
                if colour.visible then
                    showing_keys[#showing_keys + 1] = key
                end
            end
            showing_keys_are_stale = false
        end
        for _, key in ipairs(showing_keys) do
            local colour = recoloured[key]
            if colour then
                -- The game changes a panel's or a text's colour when the mouse comes over it or
                -- leaves, so the ones near the mouse are looked at after every update.
                local was_near = colour.near_mouse
                colour.near_mouse = is_near_mouse(colour, mouse_x, mouse_y)
                local is_its_turn = not is_quiet or (update_number + colour.turn) % quiet_check_interval == 0
                if (is_its_turn or colour.near_mouse or was_near) and check(key, colour) then
                    checked = checked + 1
                end
            end
        end
    end
    if events.enabled then
        events.count("colours checked", checked)
    end
end

---@return integer # How many colours are recoloured.
function recolourer.count()
    local count = 0
    for _ in pairs(recoloured) do
        count = count + 1
    end
    return count
end

---@param groups table<string, boolean> The sprite groups that are on (names from sprite_groups).
---@param scheme_colours SchemeColours
---@param on_new_colour fun(component: ui.Component, walk_kind: WalkKind) Called when a showing component is recoloured for the first time.
function recolourer.start(groups, scheme_colours, on_new_colour)
    swapped_groups = groups
    colours = scheme_colours
    on_new = on_new_colour
    recoloured = {}
    showing_keys = {}
    showing_keys_are_stale = true
    rectangle_colours, text_colours = {}, {}
    plugin_panel_colours = {}
end

-- Gives back the game's colours, where they still are what the plugin set.
function recolourer.stop()
    for _, colour in pairs(recoloured) do
        local component = find(colour)
        if component and read_colour(component, colour.field) == colour.applied_rgb then
            write_colour(component, colour.field, colour.game_rgb)
        end
    end
    recoloured = {}
    showing_keys = {}
    showing_keys_are_stale = true
end

return recolourer
