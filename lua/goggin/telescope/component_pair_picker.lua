local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values

local M = {}

local WEB_ROOT = "/home/joegoggin/Projects/gig-log/web"
local COMPONENTS_DIR = WEB_ROOT .. "/src/components"
local STYLES_DIR = WEB_ROOT .. "/styles/components"

local function file_exists(path)
    return vim.uv.fs_stat(path) ~= nil
end

local function path_join(...)
    return table.concat({ ... }, "/")
end

local function component_name_from_file(file_path)
    local lines = vim.fn.readfile(file_path)
    local awaiting_component_fn = false

    for _, line in ipairs(lines) do
        if line:match("^%s*#%s*%[%s*component%s*%]") then
            awaiting_component_fn = true
        elseif awaiting_component_fn then
            local component_name = line:match("^%s*pub%s+fn%s+([%w_]+)")

            if component_name then
                return component_name
            end

            local is_attribute = line:match("^%s*#") ~= nil
            local is_blank = line:match("^%s*$") ~= nil

            if not is_attribute and not is_blank then
                awaiting_component_fn = false
            end
        end
    end

    return nil
end

local function resolve_scss_path(rust_path)
    local relative = rust_path:sub(#COMPONENTS_DIR + 2)
    local relative_dir = vim.fn.fnamemodify(relative, ":h")
    if relative_dir == "." then
        relative_dir = ""
    end

    local stem = vim.fn.fnamemodify(relative, ":t:r")
    local kebab_stem = stem:gsub("_", "-")
    local base_dir = relative_dir ~= "" and path_join(STYLES_DIR, relative_dir) or STYLES_DIR

    local direct_match = path_join(base_dir, "_" .. kebab_stem .. ".scss")
    if file_exists(direct_match) then
        return direct_match
    end

    if relative_dir ~= "" then
        local parent = vim.fn.fnamemodify(relative_dir, ":t"):gsub("_", "-")
        local prefixed_match = path_join(base_dir, "_" .. parent .. "-" .. kebab_stem .. ".scss")

        if file_exists(prefixed_match) then
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
            local component_name = component_name_from_file(rust_path)

            if component_name then
                local relative = rust_path:sub(#COMPONENTS_DIR + 2)

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

local function open_component_pair(component)
    vim.cmd("edit " .. vim.fn.fnameescape(component.rust_path))

    if component.scss_path then
        vim.cmd("vsplit " .. vim.fn.fnameescape(component.scss_path))
        vim.cmd("wincmd h")
    end
end

function M.pick()
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
            prompt_title = "Open Component",
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
                        open_component_pair(selection.value)
                    end
                end)

                return true
            end,
        })
        :find()
end

return M
