-- The player's choices from the settings page, saved between sessions. Everything is on unless
-- turned off.
local settings = {}

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

return settings
