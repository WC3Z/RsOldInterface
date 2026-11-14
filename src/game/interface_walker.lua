-- Goes through the game's own interfaces that are loaded right now, and their components.
local interface_walker = {}

-- The highest interface ID in the game data is 1946 (November 2026), with room for new ones.
local last_interface_id = 2500
-- Static component IDs run from 0 without gaps (one interface in the game data skips one),
-- so walks stop after this many missing IDs in a row.
interface_walker.allowed_missing_ids = 8

local collection_types = {
    [ui.ComponentType.LAYER] = true,
    [ui.ComponentType.PANEL] = true,
    [ui.ComponentType.GRID] = true,
    [ui.ComponentType.PAGED_LAYER] = true,
    [ui.ComponentType.GROUP_BOX] = true,
}

---@param callback fun(interface_id: integer)
function interface_walker.each_loaded_interface(callback)
    for interface_id = 0, last_interface_id do
        if ui.Interfaces:GetInterface(interface_id) then
            callback(interface_id)
        end
    end
end

-- The children the game created while running, like list rows, and theirs in turn.
---@param component ui.Component
---@param callback fun(component: ui.Component)
local function each_dynamic_child(component, callback)
    if not collection_types[component.type] then
        return
    end
    ---@cast component ui.ComponentCollection
    component:IterateDynamicComponents(function (child)
        callback(child)
        each_dynamic_child(child, callback)
        return false
    end)
end

-- Visits one static component and the components the game created inside it while running.
-- With visible_only, a hidden component is skipped along with everything inside it.
---@param interface_id integer
---@param static_id integer
---@param callback fun(component: ui.Component)
---@param visible_only boolean?
---@return boolean found Whether the interface has a component with this static ID.
---@return boolean visited Whether it was visited (it's visible, or visible_only wasn't asked).
function interface_walker.visit_static(interface_id, static_id, callback, visible_only)
    local component = ui.Interfaces:GetComponent(interface_id, static_id)
    if not component then
        return false, false
    end
    if visible_only and not component.visibleGlobal then
        return true, false
    end
    callback(component)
    each_dynamic_child(component, callback)
    return true, true
end

-- Both the static components and the ones the game creates while running, like list rows. With
-- visible_only, hidden components are skipped along with everything inside them.
---@param interface_id integer
---@param callback fun(component: ui.Component)
---@param visible_only boolean?
---@return integer # How many components were looked up.
function interface_walker.each_component(interface_id, callback, visible_only)
    local looked_up = 0
    local function count_and_visit(component)
        looked_up = looked_up + 1
        callback(component)
    end
    local static_id = 0
    local missing_in_a_row = 0
    while missing_in_a_row < interface_walker.allowed_missing_ids do
        looked_up = looked_up + 1
        if interface_walker.visit_static(interface_id, static_id, count_and_visit, visible_only) then
            missing_in_a_row = 0
        else
            missing_in_a_row = missing_in_a_row + 1
        end
        static_id = static_id + 1
    end
    return looked_up
end

-- Identifies a component by its IDs, which stay the same when the game creates the component
-- anew, like when its window reopens.
---@param component ui.Component
---@return string
function interface_walker.component_key(component)
    return string.format("%d:%d:%d:%d", component.interfaceID, component.staticID, component.categoryID, component.dynamicID)
end

return interface_walker
