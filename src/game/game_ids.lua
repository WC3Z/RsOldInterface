-- Looks up the game's IDs by name and names by ID. A name this client doesn't have gives nil
-- rather than an error: names come and go between game versions.
local game_ids = {}

---@param sprite_name string
---@return integer?
function game_ids.sprite_id(sprite_name)
    local found, sprite_id = pcall(function () return id.Sprite[sprite_name] end)
    return found and sprite_id or nil
end

---@param sprite_id integer
---@return string?
function game_ids.sprite_name(sprite_id)
    local found, sprite_name = pcall(id.Sprite.FromID, sprite_id)
    return found and sprite_name or nil
end

---@param interface_name string
---@return integer?
function game_ids.interface_id(interface_name)
    local found, interface_id = pcall(function () return id.Interface[interface_name] end)
    return found and interface_id or nil
end

-- The IDs of the interfaces with the given names, as a set.
---@param interface_names string[]
---@return table<integer, boolean>
function game_ids.interface_ids(interface_names)
    local interface_ids = {}
    for _, interface_name in ipairs(interface_names) do
        local interface_id = game_ids.interface_id(interface_name)
        if interface_id then
            interface_ids[interface_id] = true
        end
    end
    return interface_ids
end

return game_ids
