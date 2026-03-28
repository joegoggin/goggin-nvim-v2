local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local web_paths = require("goggin.telescope.web_paths")
local delete_utils = require("goggin.telescope.delete_utils")

local M = {}

local COMPONENTS_DIR = nil
local STYLES_DIR = nil

local function resolve_paths()
    local paths, err = web_paths.resolve({ "components_dir", "styles_components_dir" })
    if not paths then
        vim.notify(err, vim.log.levels.WARN)
        return false
    end

    COMPONENTS_DIR = paths.components_dir
    STYLES_DIR = paths.styles_components_dir

    return true
end

local function resolve_scss_path(rust_path)
    local relative = delete_utils.path_relative(COMPONENTS_DIR, rust_path)
    local relative_dir = vim.fn.fnamemodify(relative, ":h")
    if relative_dir == "." then
        relative_dir = ""
    end

    local stem = vim.fn.fnamemodify(relative, ":t:r")
    local kebab_stem = stem:gsub("_", "-")
    local base_dir = relative_dir ~= "" and delete_utils.path_join(STYLES_DIR, relative_dir) or STYLES_DIR

    local direct_match = delete_utils.path_join(base_dir, "_" .. kebab_stem .. ".scss")
    if delete_utils.file_exists(direct_match) then
        return direct_match
    end

    if relative_dir ~= "" then
        local parent = vim.fn.fnamemodify(relative_dir, ":t"):gsub("_", "-")
        local prefixed_match = delete_utils.path_join(base_dir, "_" .. parent .. "-" .. kebab_stem .. ".scss")
        if delete_utils.file_exists(prefixed_match) then
            return prefixed_match
        end
    end

    return nil
end

local function collect_components()
    local rust_files = vim.fn.glob(COMPONENTS_DIR .. "/**/*.rs", true, true)
    local components = {}

    for _, rust_path in ipairs(rust_files) do
        if vim.fn.fnamemodify(rust_path, ":t") ~= "mod.rs" then
            local component_name = delete_utils.parse_component_name(rust_path)
            if component_name then
                local relative = delete_utils.path_relative(COMPONENTS_DIR, rust_path)

                table.insert(components, {
                    component_name = component_name,
                    rust_path = rust_path,
                    rust_relative = relative,
                    scss_path = resolve_scss_path(rust_path),
                })
            end
        end
    end

    table.sort(components, function(a, b)
        return a.component_name < b.component_name
    end)

    return components
end

local function delete_component(component)
    local touched_map = {}
    local touched_files = {}

    local module_name = vim.fn.fnamemodify(component.rust_path, ":t:r")
    local rust_dir = vim.fn.fnamemodify(component.rust_path, ":h")

    local removed_rust, rust_error = delete_utils.delete_path(component.rust_path, false)
    if not removed_rust then
        vim.notify(rust_error, vim.log.levels.WARN)
        return
    end

    delete_utils.mark_once(touched_map, touched_files, component.rust_path)

    local rust_mod = delete_utils.path_join(rust_dir, "mod.rs")
    if delete_utils.remove_module_reference(rust_mod, module_name) then
        delete_utils.mark_once(touched_map, touched_files, rust_mod)
    end
    if delete_utils.remove_use_symbol(rust_mod, component.component_name) then
        delete_utils.mark_once(touched_map, touched_files, rust_mod)
    end

    delete_utils.prune_empty_rust_dirs(rust_dir, COMPONENTS_DIR, touched_map, touched_files)

    if component.scss_path then
        local style_dir = vim.fn.fnamemodify(component.scss_path, ":h")
        local forward_target = vim.fn.fnamemodify(component.scss_path, ":t:r"):gsub("^_", "")

        local removed_scss, scss_error = delete_utils.delete_path(component.scss_path, false)
        if not removed_scss then
            vim.notify(scss_error, vim.log.levels.WARN)
        else
            delete_utils.mark_once(touched_map, touched_files, component.scss_path)
        end

        local style_index = delete_utils.path_join(style_dir, "index.scss")
        if delete_utils.remove_forward(style_index, forward_target) then
            delete_utils.mark_once(touched_map, touched_files, style_index)
        end

        delete_utils.prune_empty_style_dirs(style_dir, STYLES_DIR, touched_map, touched_files)
    else
        vim.notify("No matching SCSS file found for " .. component.component_name .. ". Deleted Rust component only.", vim.log.levels.WARN)
    end

    vim.notify("Deleted component " .. component.component_name)
    if #touched_files > 0 then
        vim.notify(table.concat(touched_files, "\n"), vim.log.levels.INFO)
    end
end

local function confirm_delete(component)
    vim.ui.select({ "No", "Yes" }, { prompt = "Delete component " .. component.component_name .. "?" }, function(choice)
        if choice == "Yes" then
            delete_component(component)
        end
    end)
end

function M.pick()
    if not resolve_paths() then
        return
    end

    if vim.fn.isdirectory(COMPONENTS_DIR) ~= 1 then
        vim.notify("Components directory not found: " .. COMPONENTS_DIR, vim.log.levels.WARN)
        return
    end

    local components = collect_components()
    if #components == 0 then
        vim.notify("No Rust components found in " .. COMPONENTS_DIR, vim.log.levels.WARN)
        return
    end

    pickers
        .new({}, {
            prompt_title = "Delete Component",
            finder = finders.new_table({
                results = components,
                entry_maker = function(component)
                    return {
                        value = component,
                        display = component.component_name .. "  " .. component.rust_relative,
                        ordinal = component.component_name .. " " .. component.rust_relative,
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    local selection = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)

                    if selection and selection.value then
                        confirm_delete(selection.value)
                    end
                end)

                return true
            end,
        })
        :find()
end

return M
