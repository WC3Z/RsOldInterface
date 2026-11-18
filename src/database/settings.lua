-- The player's choices from the settings page, saved between sessions. Everything is on unless
-- turned off, and the colour scheme is the classic one unless another is chosen.
local colour_scheme = require("src/game/colour_scheme")

local settings = {}

local scheme_key = "colour_scheme"
local custom_tint_key = "custom_tint"

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

-- Saved as text ("4A87FF"): a number that was never saved can't be told from black.
---@return integer # The player's own colour for the custom scheme, 0xRRGGBB.
function settings.custom_tint()
    return tonumber(saved_text(custom_tint_key) or "", 16) or colour_scheme.default_custom_tint
end

---@param rgb integer
function settings.set_custom_tint(rgb)
    PersistentDB:SetString(custom_tint_key, string.format("%06X", rgb))
end

-- The tint of the chosen colour scheme, or nil for the classic one.
---@return integer?
function settings.tint()
    return colour_scheme.tint_of(settings.colour_scheme(), settings.custom_tint())
end

return settings
