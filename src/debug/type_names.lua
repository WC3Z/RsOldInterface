-- DEBUG: the names of the component types, by the value the game gives them. The game's
-- ui.ComponentType can't be gone through with pairs, so each name is looked up.
local names = {
    "LINE", "RECTANGLE", "LABEL", "SPRITE", "MODEL", "MODEL_GROUP", "RADIAL_PROGRESS_OVERLAY", "CUTSCENE_LAYER",
    "CANVAS", "BUTTON", "CHECK", "LIST", "INPUTFIELD", "SLIDER", "COMBO", "PAGED_LAYER_HEADER", "CAROUSEL",
    "PAGED_CAROUSEL", "RADIO_GROUP", "LAYER", "PANEL", "GRID", "PAGED_LAYER", "GROUP_BOX",
}

---@type table<any, string>
local type_names = {}
for _, name in ipairs(names) do
    local found, value = pcall(function () return ui.ComponentType[name] end)
    if found and value ~= nil then
        type_names[value] = name
    end
end

-- The name of a component type, or the value itself if it has none here.
---@param component_type any
---@return string
return function (component_type)
    return type_names[component_type] or tostring(component_type)
end
