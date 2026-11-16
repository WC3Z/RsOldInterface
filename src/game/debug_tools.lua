-- The debug tools (src/debug), which only dev builds have: release builds leave that folder out.
-- There they're stand-ins that are switched off and whose functions do nothing, so the code using
-- them reads the same either way.
local debug_tools = {}

local function do_nothing() end

---@param module_name string
local function load_or_stand_in(module_name)
    local found, module = pcall(require, module_name)
    if found then
        return module
    end
    return setmetatable({ enabled = false }, { __index = function () return do_nothing end })
end

debug_tools.activity_log = load_or_stand_in("src/debug/activity_log")
debug_tools.profile = load_or_stand_in("src/debug/profile")

return debug_tools
