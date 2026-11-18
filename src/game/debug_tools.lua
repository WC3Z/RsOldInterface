-- The debug tools (src/debug), which only dev builds have: release builds leave that folder out.
-- There the tools are a stand-in that's switched off and whose functions do nothing, so the code
-- using them reads the same either way: `if events.enabled then events.something(...) end`.
local debug_tools = {}

local function do_nothing() end

local found, events = pcall(require, "src/debug/events")

-- What happened in the swapping, for the tools to print and count (see src/debug/events.lua).
debug_tools.events = found and events or setmetatable({ enabled = false }, { __index = function () return do_nothing end })

return debug_tools
