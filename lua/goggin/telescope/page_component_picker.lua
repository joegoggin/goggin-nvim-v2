local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local web_paths = require("goggin.telescope.web_paths")

local M = {}

local PAGES_DIR = nil
local PAGE_STYLES_DIR = nil

local function resolve_paths()
    local paths, err = web_paths.resolve({ "pages_dir" })
    if not paths then
        vim.notify(err, vim.log.levels.WARN)
        return false
    end

    PAGES_DIR = paths.pages_dir
    PAGE_STYLES_DIR = paths.page_styles_dir

    return true
end

local function file_exists(path)
    return vim.uv.fs_stat(path) ~= nil
end

local function path_join(...)
    return table.concat({ ... }, "/")
end

local function parse_component_name(file_path)
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

local function resolve_partial_style(base_dir, stem)
    local kebab_stem = stem:gsub("_", "-")
    local direct = path_join(base_dir, "_" .. kebab_stem .. ".scss")
    if file_exists(direct) then
        return direct
    end

    local parent = vim.fn.fnamemodify(base_dir, ":t"):gsub("_", "-")
    local prefixed = path_join(base_dir, "_" .. parent .. "-" .. kebab_stem .. ".scss")
    if file_exists(prefixed) then
        return prefixed
    end

    return nil
end

local function display_page_name(component_name)
    if component_name:sub(-4) == "Page" then
        return component_name:sub(1, -5)
    end

    return component_name
end

local function collect_pages()
    local page_files = vim.fn.glob(PAGES_DIR .. "/**/page.rs", true, true)
    local pages = {}

    for _, page_rs in ipairs(page_files) do
        local component_name = parse_component_name(page_rs)
        if component_name then
            local page_dir = vim.fn.fnamemodify(page_rs, ":h")
            local relative_dir = page_dir:sub(#PAGES_DIR + 2)

            table.insert(pages, {
                display_name = display_page_name(component_name),
                component_name = component_name,
                page_dir = page_dir,
                relative_dir = relative_dir,
                page_rs = page_rs,
                page_scss = path_join(PAGE_STYLES_DIR, relative_dir, "_page.scss"),
            })
        end
    end

    table.sort(pages, function(a, b)
        return a.display_name < b.display_name
    end)

    return pages
end

local function trim_page_prefix(component_name, page_component_name)
    local prefix = page_component_name
    if prefix:sub(-4) ~= "Page" then
        return component_name
    end

    local trimmed_prefix = prefix:sub(1, -5) .. "Page"
    if component_name:sub(1, #trimmed_prefix) == trimmed_prefix and #component_name > #trimmed_prefix then
        return component_name:sub(#trimmed_prefix + 1)
    end

    return component_name
end

local function collect_page_entries(page)
    local entries = {
        {
            label = "Page",
            rust_path = page.page_rs,
            rust_relative = path_join(page.relative_dir, "page.rs"),
            scss_path = file_exists(page.page_scss) and page.page_scss or nil,
            entry_type = "page",
        },
    }

    local components_dir = path_join(page.page_dir, "components")
    if vim.fn.isdirectory(components_dir) == 1 then
        local component_files = vim.fn.glob(components_dir .. "/**/*.rs", true, true)

        for _, rust_path in ipairs(component_files) do
            if vim.fn.fnamemodify(rust_path, ":t") ~= "mod.rs" then
                local component_name = parse_component_name(rust_path)
                if component_name then
                    local file_relative = rust_path:sub(#page.page_dir + 2)
                    local file_stem = vim.fn.fnamemodify(file_relative, ":t:r")
                    local style_dir_relative = vim.fn.fnamemodify(file_relative, ":h")
                    if style_dir_relative == "." then
                        style_dir_relative = ""
                    end

                    local style_base_dir = path_join(PAGE_STYLES_DIR, page.relative_dir)
                    if style_dir_relative ~= "" then
                        style_base_dir = path_join(style_base_dir, style_dir_relative)
                    end

                    local entry_label = trim_page_prefix(component_name, page.component_name)

                    table.insert(entries, {
                        label = entry_label,
                        rust_path = rust_path,
                        rust_relative = path_join(page.relative_dir, file_relative),
                        scss_path = resolve_partial_style(style_base_dir, file_stem),
                        entry_type = "component",
                    })
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        if a.entry_type == "page" and b.entry_type ~= "page" then
            return true
        end
        if b.entry_type == "page" and a.entry_type ~= "page" then
            return false
        end
        return a.label < b.label
    end)

    return entries
end

local function open_entry(entry)
    vim.cmd("edit " .. vim.fn.fnameescape(entry.rust_path))

    if entry.scss_path then
        vim.cmd("vsplit " .. vim.fn.fnameescape(entry.scss_path))
        vim.cmd("wincmd h")
    end
end

local function pick_page_entries(page)
    local entries = collect_page_entries(page)

    pickers
        .new({}, {
            prompt_title = "Open Page Component: " .. page.display_name,
            finder = finders.new_table({
                results = entries,
                entry_maker = function(entry)
                    return {
                        value = entry,
                        display = entry.label .. "  " .. entry.rust_relative,
                        ordinal = entry.label .. " " .. entry.rust_relative,
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    local selection = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)

                    if selection and selection.value then
                        open_entry(selection.value)
                    end
                end)

                return true
            end,
        })
        :find()
end

function M.pick_page()
    if not resolve_paths() then
        return
    end

    if vim.fn.isdirectory(PAGES_DIR) ~= 1 then
        vim.notify("Pages directory not found: " .. PAGES_DIR, vim.log.levels.WARN)
        return
    end

    local pages = collect_pages()
    if #pages == 0 then
        vim.notify("No page.rs components found in " .. PAGES_DIR, vim.log.levels.WARN)
        return
    end

    pickers
        .new({}, {
            prompt_title = "Open Page",
            finder = finders.new_table({
                results = pages,
                entry_maker = function(page)
                    return {
                        value = page,
                        display = page.display_name .. "  " .. path_join(page.relative_dir, "page.rs"),
                        ordinal = page.display_name .. " " .. page.component_name .. " " .. page.relative_dir,
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    local selection = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)

                    if selection and selection.value then
                        pick_page_entries(selection.value)
                    end
                end)

                return true
            end,
        })
        :find()
end

return M
