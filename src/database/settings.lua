-- The player's choices from the settings page, saved between sessions. Everything is on unless
-- turned off, and the colour scheme is the classic one unless another is chosen.
local colour_scheme = require("src/game/colour_scheme")

local settings = {}

local scheme_key = "colour_scheme"
local custom_tint_key = "custom_tint"
local own_text_colours_key = "own_text_colours"
local heading_text_key = "heading_text"
local body_text_key = "body_text"

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

-- Everything the chosen look is drawn in.
---@return SchemeColours
function settings.colours()
    local has_own_text_colours = settings.has_own_text_colours()
    return {
        tint = settings.tint(),
        heading_text = has_own_text_colours and settings.heading_text() or nil,
        body_text = has_own_text_colours and settings.body_text() or nil,
    }
end

return settings
