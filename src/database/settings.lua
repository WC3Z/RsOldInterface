-- The player's choices from the settings page, saved between sessions. Everything is on unless
-- turned off, and the colour scheme is the classic one unless another is chosen.
local colour_scheme = require("src/game/colour_scheme")
local sprite_groups = require("src/game/sprite_groups")

local settings = {}

local scheme_key = "colour_scheme"
local custom_tint_key = "custom_tint"
local own_text_colours_key = "own_text_colours"
local heading_text_key = "heading_text"
local body_text_key = "body_text"
local window_x_key = "window_x"
local window_y_key = "window_y"
local window_width_key = "window_width"
local window_height_key = "window_height"
local default_window_width = 400
local default_window_height = 520

---@param option_key string
---@return string
local function saved_key(option_key)
    return "option_" .. option_key
end

---@param option_key string A key from sprite_groups.options.
---@return boolean
function settings.is_on(option_key)
    return PersistentDB:GetBool(saved_key(option_key)) ~= false
end

---@param option_key string
---@param on boolean
function settings.set_on(option_key, on)
    PersistentDB:SetBool(saved_key(option_key), on)
end

-- A saved text, or nil when nothing is saved under the key.
---@param key string
---@return string?
local function saved_text(key)
    local text = PersistentDB:GetString(key)
    return type(text) == "string" and text ~= "" and text or nil
end

---@return string # A key from colour_scheme.all.
function settings.colour_scheme()
    local key = saved_text(scheme_key)
    for _, scheme in ipairs(colour_scheme.all) do
        if scheme.key == key then
            return key
        end
    end
    return colour_scheme.classic_key
end

---@param key string
function settings.set_colour_scheme(key)
    PersistentDB:SetString(scheme_key, key)
end

-- A saved colour, or the default when none is saved. Saved as text ("4A87FF"): a number that was
-- never saved can't be told from black.
---@param key string
---@param default integer
---@return integer
local function saved_colour(key, default)
    return tonumber(saved_text(key) or "", 16) or default
end

---@param key string
---@param rgb integer
local function save_colour(key, rgb)
    PersistentDB:SetString(key, string.format("%06X", rgb))
end

---@return integer # The player's own colour for the custom scheme, 0xRRGGBB.
function settings.custom_tint()
    return saved_colour(custom_tint_key, colour_scheme.default_custom_tint)
end

---@param rgb integer
function settings.set_custom_tint(rgb)
    save_colour(custom_tint_key, rgb)
end

---@return boolean # Whether the player's own text colours are used.
function settings.has_own_text_colours()
    return PersistentDB:GetBool(own_text_colours_key) == true
end

---@param on boolean
function settings.set_own_text_colours(on)
    PersistentDB:SetBool(own_text_colours_key, on)
end

---@return integer
function settings.heading_text()
    return saved_colour(heading_text_key, colour_scheme.default_heading_text)
end

---@param rgb integer
function settings.set_heading_text(rgb)
    save_colour(heading_text_key, rgb)
end

---@return integer
function settings.body_text()
    return saved_colour(body_text_key, colour_scheme.default_body_text)
end

---@param rgb integer
function settings.set_body_text(rgb)
    save_colour(body_text_key, rgb)
end

-- The tint of the chosen colour scheme, or nil for the classic one.
---@return integer?
function settings.tint()
    return colour_scheme.tint_of(settings.colour_scheme(), settings.custom_tint())
end

---@param part_key string A key from sprite_groups.colour_parts.
---@return string
local function part_tint_key(part_key)
    return "part_tint_" .. part_key
end

-- The player's own colour for a part of the interface, in any scheme, or nil while it's drawn
-- as the scheme has it.
---@param part_key string
---@return integer?
function settings.part_tint(part_key)
    return tonumber(saved_text(part_tint_key(part_key)) or "", 16)
end

---@param part_key string
---@param rgb integer? Nil for the scheme's colour again.
function settings.set_part_tint(part_key, rgb)
    PersistentDB:SetString(part_tint_key(part_key), rgb and string.format("%06X", rgb) or "")
end

-- Where the settings window was when it was last closed, or nil before it's been closed.
---@return integer? x
---@return integer? y
function settings.window_position()
    local x, y = PersistentDB:GetInt(window_x_key), PersistentDB:GetInt(window_y_key)
    if x == nil or y == nil then
        return nil, nil
    end
    return x, y
end

-- How big the settings window was when it was last closed, or its size to start with.
---@return integer width
---@return integer height
function settings.window_size()
    return PersistentDB:GetInt(window_width_key) or default_window_width,
        PersistentDB:GetInt(window_height_key) or default_window_height
end

---@param x number
---@param y number
---@param width number
---@param height number
function settings.set_window_bounds(x, y, width, height)
    PersistentDB:SetInt(window_x_key, math.floor(x))
    PersistentDB:SetInt(window_y_key, math.floor(y))
    PersistentDB:SetInt(window_width_key, math.floor(width))
    PersistentDB:SetInt(window_height_key, math.floor(height))
end

-- Everything the chosen look is drawn in.
---@return SchemeColours
function settings.colours()
    local has_own_text_colours = settings.has_own_text_colours()
    local scheme = colour_scheme.find(settings.colour_scheme()) or {}
    local own_part_tints = {}
    for _, part in ipairs(sprite_groups.colour_parts) do
        own_part_tints[part.key] = settings.part_tint(part.key)
    end
    return {
        tint = settings.tint(),
        part_tints = scheme.part_tints,
        own_part_tints = own_part_tints,
        sprite_tints = scheme.sprite_tints,
        image_set = scheme.image_set,
        heading_text = has_own_text_colours and settings.heading_text() or nil,
        body_text = has_own_text_colours and settings.body_text() or nil,
    }
end

return settings
