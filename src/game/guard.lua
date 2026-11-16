-- Keeps an event handler running when it runs into an error. The game stops calling a handler
-- that errors, which would leave the swapping half done until the plugin is reloaded; instead the
-- error is printed (each one once) and the handler carries on the next time.
local guard = {}

---@type table<string, boolean>
local printed = {}

---@param where string Where the handler runs, for the printed error, like "before a frame".
---@param handler fun(...)
---@return fun(...)
function guard.guarded(where, handler)
    return function (...)
        local ok, problem = pcall(handler, ...)
        if not ok then
            local message = tostring(problem)
            if not printed[message] then
                printed[message] = true
                print(string.format("[Old Interface] error %s: %s", where, message))
            end
        end
    end
end

return guard
