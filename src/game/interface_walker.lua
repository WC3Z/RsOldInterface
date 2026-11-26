-- Goes through the game's own interfaces that are loaded right now, and their components.
local interface_walker = {}

-- The highest interface ID in the game data is 1946 (November 2026), with room for new ones.
interface_walker.last_interface_id = 2500
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

-- The children the game created while running, like list rows, and theirs in turn. With a limit,
-- it stops once that many were visited: a list can hold thousands (the Bank's items), which is too
-- much for one frame.
---@param component ui.Component
---@param callback fun(component: ui.Component)
---@param limit { left: integer }? How many more may be visited; counted down.
local function each_dynamic_child(component, callback, limit)
    if not collection_types[component.type] then
        return
    end
    ---@cast component ui.ComponentCollection
    component:IterateDynamicComponents(function (child)
        if limit then
            if limit.left <= 0 then
                return true
            end
            limit.left = limit.left - 1
        end
        callback(child)
        each_dynamic_child(child, callback, limit)
        return false
    end)
end

-- Visits one static component and the components the game created inside it while running.
-- With visible_only, a hidden component is skipped along with everything inside it.
---@param interface_id integer
---@param static_id integer
---@param callback fun(component: ui.Component)
---@param visible_only boolean?
---@param most_created integer? Visit at most this many of the components the game created inside it.
---@return boolean found Whether the interface has a component with this static ID.
---@return boolean visited Whether it was visited (it's visible, or visible_only wasn't asked).
function interface_walker.visit_static(interface_id, static_id, callback, visible_only, most_created)
    local component = ui.Interfaces:GetComponent(interface_id, static_id)
    if not component then
        return false, false
    end
    if visible_only and not component.visibleGlobal then
        return true, false
    end
    callback(component)
    -- A table, not a number: each_dynamic_child calls itself for the children's children, and all
    -- of those calls have to count down the same total.
    local limit = nil
    if most_created then
        limit = { left = most_created }
    end
    each_dynamic_child(component, callback, limit)
    return true, true
end

-- Goes up the static IDs from 0 until the given function has said no for enough in a row (see
-- allowed_missing_ids).
---@param has_component fun(static_id: integer): boolean Whether the interface has a component with this static ID.
local function each_static_id(has_component)
    local static_id = 0
    local missing_in_a_row = 0
    while missing_in_a_row < interface_walker.allowed_missing_ids do
        if has_component(static_id) then
            missing_in_a_row = 0
        else
            missing_in_a_row = missing_in_a_row + 1
        end
        static_id = static_id + 1
    end
end

-- Both the static components and the ones the game creates while running, like list rows. With
-- visible_only, hidden components are skipped along with everything inside them.
---@param interface_id integer
---@param callback fun(component: ui.Component)
---@param visible_only boolean?
---@return integer # How many components were looked up.
function interface_walker.each_component(interface_id, callback, visible_only)
    local looked_up = 0
    -- Defined in here so it can add to this call's count and reach this call's callback.
    local function count_and_visit(component)
        looked_up = looked_up + 1
        callback(component)
    end
    each_static_id(function (static_id)
        local found, visited = interface_walker.visit_static(interface_id, static_id, count_and_visit, visible_only)
        -- A visited component was counted by count_and_visit; a missing or hidden one was still
        -- looked up.
        if not visited then
            looked_up = looked_up + 1
        end
        return found
    end)
    return looked_up
end

---@class StaticTree An interface's static components as a tree, which stays the same while it's loaded.
---@field order integer[] Static IDs, each parent before its children.
---@field after integer[] For each place in `order`, the place after that component and everything inside it.
---@field roots integer[] The static IDs with no parent in the interface.

-- The static ID of the component a component sits inside, if that's in the same interface. An
-- interface's outermost components sit inside a component of another interface (the one their
-- interface is mounted in): for those this gives nil, which is how they're told to be roots.
---@param component ui.Component
---@param own_interface_id integer The interface the component itself is in.
---@return integer?
local function parent_static_id(component, own_interface_id)
    local parent = component.parentStatic
    local is_in_same_interface = parent ~= nil and parent.interfaceID == own_interface_id
    if is_in_same_interface then
        return parent.staticID
    end
    return nil
end

-- Reads how an interface's static components sit inside each other. A component whose parent
-- can't be told counts as a root.
---@param interface_id integer
---@return StaticTree
function interface_walker.static_tree(interface_id)
    local static_ids = {}
    local parents = {}
    each_static_id(function (static_id)
        local component = ui.Interfaces:GetComponent(interface_id, static_id)
        if not component then
            return false
        end
        static_ids[#static_ids + 1] = static_id
        local found, parent_id = pcall(parent_static_id, component, interface_id)
        if found and parent_id ~= nil and parent_id ~= static_id then
            parents[static_id] = parent_id
        end
        return true
    end)

    local is_static = {}
    for _, id in ipairs(static_ids) do
        is_static[id] = true
    end
    local children = {}
    local roots = {}
    for _, id in ipairs(static_ids) do
        local parent_id = parents[id]
        if parent_id ~= nil and is_static[parent_id] then
            children[parent_id] = children[parent_id] or {}
            table.insert(children[parent_id], id)
        else
            roots[#roots + 1] = id
        end
    end

    local order = {}
    local after = {}
    local placed = {}
    local function place(id)
        if placed[id] then
            return
        end
        placed[id] = true
        local index = #order + 1
        order[index] = id
        for _, child_id in ipairs(children[id] or {}) do
            place(child_id)
        end
        after[index] = #order + 1
    end
    for _, id in ipairs(roots) do
        place(id)
    end
    -- Anything left sits in a loop of parents, which shouldn't happen: walk it as roots.
    for _, id in ipairs(static_ids) do
        place(id)
    end
    return { order = order, after = after, roots = roots }
end

-- Visits an interface's showing components, from a place in its tree, until the budget of lookups
-- runs out. A hidden static component is skipped along with every static component inside it.
---@param interface_id integer
---@param tree StaticTree
---@param callback fun(component: ui.Component)
---@param index integer Where in tree.order to start (1 for the whole interface).
---@param budget number
---@return integer? next_index Where to carry on, or nil when the interface is done.
---@return integer looked_up
function interface_walker.walk_showing(interface_id, tree, callback, index, budget)
    local order, after = tree.order, tree.after
    local looked_up = 0
    -- For the components the game created, which each_dynamic_child looks up.
    local function count_and_visit_created(component)
        looked_up = looked_up + 1
        callback(component)
    end
    local count = #order
    while index <= count and looked_up < budget do
        -- A static component is looked up here, so it's counted here, shown or not.
        local component = ui.Interfaces:GetComponent(interface_id, order[index])
        looked_up = looked_up + 1
        if component and component.visibleGlobal then
            callback(component)
            each_dynamic_child(component, count_and_visit_created)
            index = index + 1
        else
            index = after[index]
        end
    end
    return index <= count and index or nil, looked_up
end

-- Identifies a component by its IDs, which stay the same when the game creates the component
-- anew, like when its window reopens.
---@param component ui.Component
---@return string
function interface_walker.component_key(component)
    return string.format("%d:%d:%d:%d", component.interfaceID, component.staticID, component.categoryID, component.dynamicID)
end

return interface_walker
