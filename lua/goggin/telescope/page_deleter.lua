local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local web_paths = require("goggin.telescope.web_paths")
local delete_utils = require("goggin.telescope.delete_utils")

local M = {}

local PAGES_DIR = nil
local PAGE_STYLES_DIR = nil
local APP_PATH = nil

local function resolve_paths()
    local paths, err = web_paths.resolve({ "pages_dir", "page_styles_dir", "app_path" })
    if not paths then
        vim.notify(err, vim.log.levels.WARN)
        return false
    end

    PAGES_DIR = paths.pages_dir
    PAGE_STYLES_DIR = paths.page_styles_dir
    APP_PATH = paths.app_path

    return true
end

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_path_segments(path)
    local segments = {}
    for segment in path:gmatch("[^/]+") do
        if segment ~= "" and segment ~= "." then
            table.insert(segments, segment)
        end
    end
    return segments
end

local function join_segments(root, segments)
    local path = root
    for _, segment in ipairs(segments) do
        path = delete_utils.path_join(path, segment)
    end
    return path
end

local function resolve_partial_style(base_dir, stem)
    local kebab_stem = stem:gsub("_", "-")
    local direct = delete_utils.path_join(base_dir, "_" .. kebab_stem .. ".scss")
    if delete_utils.file_exists(direct) then
        return direct
    end

    local parent = vim.fn.fnamemodify(base_dir, ":t"):gsub("_", "-")
    local prefixed = delete_utils.path_join(base_dir, "_" .. parent .. "-" .. kebab_stem .. ".scss")
    if delete_utils.file_exists(prefixed) then
        return prefixed
    end

    return nil
end

local function resolve_page_style(page)
    if page.is_module_layout then
        local module_style = delete_utils.path_join(page.style_module_dir, "_page.scss")
        if delete_utils.file_exists(module_style) then
            return module_style
        end

        return nil
    end

    local style_parent_dir =
        page.parent_relative ~= "" and delete_utils.path_join(PAGE_STYLES_DIR, page.parent_relative) or PAGE_STYLES_DIR

    local by_stem = resolve_partial_style(style_parent_dir, page.module_name)
    if by_stem then
        return by_stem
    end

    local component_kebab = delete_utils.to_kebab_case(page.page_component_name)
    if component_kebab ~= "" then
        local by_component = delete_utils.path_join(style_parent_dir, "_" .. component_kebab .. ".scss")
        if delete_utils.file_exists(by_component) then
            return by_component
        end

        local without_page_suffix = component_kebab:gsub("%-page$", "")
        if without_page_suffix ~= component_kebab then
            local by_component_without_page = delete_utils.path_join(style_parent_dir, "_" .. without_page_suffix .. ".scss")
            if delete_utils.file_exists(by_component_without_page) then
                return by_component_without_page
            end
        end
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
    local page_files = vim.fn.glob(PAGES_DIR .. "/**/*.rs", true, true)
    local page_by_module = {}
    local pages = {}

    for _, page_rs in ipairs(page_files) do
        local file_name = vim.fn.fnamemodify(page_rs, ":t")
        if file_name ~= "mod.rs" then
            local component_name = delete_utils.parse_component_name(page_rs)
            if component_name and component_name:sub(-4) == "Page" then
                local rust_relative = delete_utils.path_relative(PAGES_DIR, page_rs)
                local is_component_file = rust_relative:match("^components/") or rust_relative:match("/components/")

                if not is_component_file then
                    local is_module_layout = file_name == "page.rs"
                    local without_ext = rust_relative:gsub("%.rs$", "")
                    local module_segments = split_path_segments(without_ext)

                    if is_module_layout and module_segments[#module_segments] == "page" then
                        table.remove(module_segments, #module_segments)
                    end

                    if #module_segments > 0 then
                        local parent_segments = {}
                        for i = 1, #module_segments - 1 do
                            table.insert(parent_segments, module_segments[i])
                        end

                        local module_relative = table.concat(module_segments, "/")
                        local parent_relative = table.concat(parent_segments, "/")
                        local module_name = module_segments[#module_segments]
                        local module_dir = join_segments(PAGES_DIR, module_segments)
                        local parent_dir = #parent_segments > 0 and join_segments(PAGES_DIR, parent_segments) or PAGES_DIR

                        local page = {
                            rust_path = page_rs,
                            rust_relative = rust_relative,
                            page_component_name = component_name,
                            display_name = display_page_name(component_name),
                            is_module_layout = is_module_layout,
                            module_segments = module_segments,
                            parent_segments = parent_segments,
                            module_relative = module_relative,
                            parent_relative = parent_relative,
                            module_name = module_name,
                            module_dir = module_dir,
                            parent_dir = parent_dir,
                            style_module_dir = join_segments(PAGE_STYLES_DIR, module_segments),
                        }

                        page.page_scss = resolve_page_style(page)

                        local existing = page_by_module[module_relative]
                        if not existing or (page.is_module_layout and not existing.is_module_layout) then
                            page_by_module[module_relative] = page
                        end
                    end
                end
            end
        end
    end

    for _, page in pairs(page_by_module) do
        table.insert(pages, page)
    end

    table.sort(pages, function(a, b)
        if a.display_name == b.display_name then
            return a.rust_relative < b.rust_relative
        end

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
            entry_type = "page",
            rust_path = page.rust_path,
            rust_relative = page.rust_relative,
            scss_path = page.page_scss,
            component_name = page.page_component_name,
        },
    }

    if page.is_module_layout then
        local components_dir = delete_utils.path_join(page.module_dir, "components")

        local function resolve_component_style(rust_path)
            local relative_from_components = delete_utils.path_relative(components_dir, rust_path)
            local style_dir_relative = vim.fn.fnamemodify(relative_from_components, ":h")
            if style_dir_relative == "." then
                style_dir_relative = ""
            end

            local file_stem = vim.fn.fnamemodify(relative_from_components, ":t:r")
            local style_base_dir = delete_utils.path_join(page.style_module_dir, "components")
            if style_dir_relative ~= "" then
                style_base_dir = delete_utils.path_join(style_base_dir, style_dir_relative)
            end

            return resolve_partial_style(style_base_dir, file_stem)
        end

        if vim.fn.isdirectory(components_dir) == 1 then
            local component_files = vim.fn.glob(components_dir .. "/**/*.rs", true, true)

            for _, rust_path in ipairs(component_files) do
                if vim.fn.fnamemodify(rust_path, ":t") ~= "mod.rs" then
                    local component_name = delete_utils.parse_component_name(rust_path)
                    if component_name then
                        table.insert(entries, {
                            label = trim_page_prefix(component_name, page.page_component_name),
                            entry_type = "component",
                            rust_path = rust_path,
                            rust_relative = delete_utils.path_relative(PAGES_DIR, rust_path),
                            scss_path = resolve_component_style(rust_path),
                            component_name = component_name,
                        })
                    end
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

local function ensure_forward(index_path, target)
    local line = string.format('@forward "%s";', target)
    local lines = delete_utils.read_lines(index_path)

    for _, existing in ipairs(lines) do
        if existing == line then
            return false
        end
    end

    table.insert(lines, line)
    delete_utils.write_lines(index_path, lines)
    return true
end

local function can_demote_page_to_flat(page)
    if not page.is_module_layout then
        return false
    end

    if not delete_utils.is_directory(page.module_dir) then
        return false
    end

    if not delete_utils.file_exists(delete_utils.path_join(page.module_dir, "page.rs")) then
        return false
    end

    local module_entries = vim.fn.readdir(page.module_dir)
    for _, entry in ipairs(module_entries) do
        if entry ~= "page.rs" and entry ~= "mod.rs" then
            return false
        end
    end

    if delete_utils.is_directory(page.style_module_dir) then
        local style_entries = vim.fn.readdir(page.style_module_dir)
        for _, entry in ipairs(style_entries) do
            if entry ~= "_page.scss" and entry ~= "index.scss" then
                return false
            end
        end
    end

    return true
end

local function demote_page_module_to_flat(page, touched_map, touched_files)
    local page_rs = delete_utils.path_join(page.module_dir, "page.rs")
    local flat_rs = delete_utils.path_join(page.parent_dir, page.module_name .. ".rs")

    local style_plan = nil
    if delete_utils.is_directory(page.style_module_dir) then
        local flat_style_stem = delete_utils.to_kebab_case(page.module_name)
        local flat_style_dir = page.parent_relative ~= "" and delete_utils.path_join(PAGE_STYLES_DIR, page.parent_relative)
            or PAGE_STYLES_DIR
        local module_style_path = delete_utils.path_join(page.style_module_dir, "_page.scss")
        local flat_style_path = delete_utils.path_join(flat_style_dir, "_" .. flat_style_stem .. ".scss")

        if module_style_path ~= flat_style_path and delete_utils.file_exists(module_style_path) and delete_utils.file_exists(flat_style_path) then
            vim.notify("Cannot move page style. Target already exists: " .. flat_style_path, vim.log.levels.WARN)
            return false
        end

        style_plan = {
            module_style_path = module_style_path,
            flat_style_path = flat_style_path,
            flat_style_stem = flat_style_stem,
            flat_style_dir = flat_style_dir,
        }
    end

    if page_rs ~= flat_rs and delete_utils.file_exists(flat_rs) then
        vim.notify("Cannot convert page to flat layout. Target already exists: " .. flat_rs, vim.log.levels.WARN)
        return false
    end

    local moved_page = vim.fn.rename(page_rs, flat_rs) == 0
    if not moved_page then
        vim.notify("Failed to move " .. page_rs .. " to " .. flat_rs, vim.log.levels.WARN)
        return false
    end

    delete_utils.mark_once(touched_map, touched_files, page_rs)
    delete_utils.mark_once(touched_map, touched_files, flat_rs)

    local module_mod = delete_utils.path_join(page.module_dir, "mod.rs")
    local removed_mod, mod_error = delete_utils.delete_path(module_mod, false)
    if not removed_mod then
        vim.notify(mod_error, vim.log.levels.WARN)
        return false
    end
    delete_utils.mark_once(touched_map, touched_files, module_mod)

    local removed_module_dir, module_dir_error = delete_utils.delete_path(page.module_dir, false)
    if not removed_module_dir then
        vim.notify(module_dir_error, vim.log.levels.WARN)
        return false
    end
    delete_utils.mark_once(touched_map, touched_files, page.module_dir)

    if style_plan then
        local moved_style = false
        if delete_utils.file_exists(style_plan.module_style_path) then
            moved_style = vim.fn.rename(style_plan.module_style_path, style_plan.flat_style_path) == 0
            if moved_style then
                delete_utils.mark_once(touched_map, touched_files, style_plan.module_style_path)
                delete_utils.mark_once(touched_map, touched_files, style_plan.flat_style_path)
            else
                vim.notify(
                    "Failed to move " .. style_plan.module_style_path .. " to " .. style_plan.flat_style_path,
                    vim.log.levels.WARN
                )
                return false
            end
        end

        local module_style_index = delete_utils.path_join(page.style_module_dir, "index.scss")
        if delete_utils.file_exists(module_style_index) then
            local removed_index, index_error = delete_utils.delete_path(module_style_index, false)
            if not removed_index then
                vim.notify(index_error, vim.log.levels.WARN)
                return false
            end
            delete_utils.mark_once(touched_map, touched_files, module_style_index)
        end

        local removed_style_dir, style_dir_error = delete_utils.delete_path(page.style_module_dir, false)
        if not removed_style_dir then
            vim.notify(style_dir_error, vim.log.levels.WARN)
            return false
        end
        delete_utils.mark_once(touched_map, touched_files, page.style_module_dir)

        local old_forward = page.module_name
        local new_forward = style_plan.flat_style_stem
        local parent_style_index = delete_utils.path_join(style_plan.flat_style_dir, "index.scss")
        if old_forward ~= new_forward then
            if delete_utils.remove_forward(parent_style_index, old_forward) then
                delete_utils.mark_once(touched_map, touched_files, parent_style_index)
            end

            local has_flat_style = moved_style or delete_utils.file_exists(style_plan.flat_style_path)
            if has_flat_style and ensure_forward(parent_style_index, new_forward) then
                delete_utils.mark_once(touched_map, touched_files, parent_style_index)
            end
        end
    end

    return true
end

local function resolve_page_component_style_from_rust_path(page, rust_path)
    local components_dir = delete_utils.path_join(page.module_dir, "components")
    local relative_from_components = delete_utils.path_relative(components_dir, rust_path)
    local style_dir_relative = vim.fn.fnamemodify(relative_from_components, ":h")
    if style_dir_relative == "." then
        style_dir_relative = ""
    end

    local file_stem = vim.fn.fnamemodify(relative_from_components, ":t:r")
    local style_base_dir = delete_utils.path_join(page.style_module_dir, "components")
    if style_dir_relative ~= "" then
        style_base_dir = delete_utils.path_join(style_base_dir, style_dir_relative)
    end

    return resolve_partial_style(style_base_dir, file_stem)
end

local function module_has_page_components(page)
    local components_dir = delete_utils.path_join(page.module_dir, "components")
    if not delete_utils.is_directory(components_dir) then
        return false
    end

    local component_files = vim.fn.glob(components_dir .. "/**/*.rs", true, true)
    for _, rust_path in ipairs(component_files) do
        if vim.fn.fnamemodify(rust_path, ":t") ~= "mod.rs" then
            return true
        end
    end

    return false
end

local function delete_page_component(page, entry)
    local touched_map = {}
    local touched_files = {}

    local module_name = vim.fn.fnamemodify(entry.rust_path, ":t:r")
    local rust_dir = vim.fn.fnamemodify(entry.rust_path, ":h")

    local removed_rust, rust_error = delete_utils.delete_path(entry.rust_path, false)
    if not removed_rust then
        vim.notify(rust_error, vim.log.levels.WARN)
        return
    end

    delete_utils.mark_once(touched_map, touched_files, entry.rust_path)

    local rust_mod = delete_utils.path_join(rust_dir, "mod.rs")
    if delete_utils.remove_module_reference(rust_mod, module_name) then
        delete_utils.mark_once(touched_map, touched_files, rust_mod)
    end
    if delete_utils.remove_use_symbol(rust_mod, entry.component_name) then
        delete_utils.mark_once(touched_map, touched_files, rust_mod)
    end

    delete_utils.prune_empty_rust_dirs(rust_dir, page.module_dir, touched_map, touched_files)

    local rust_components_dir = delete_utils.path_join(page.module_dir, "components")
    if delete_utils.is_directory(rust_components_dir) then
        delete_utils.prune_empty_rust_dirs(rust_components_dir, page.module_dir, touched_map, touched_files)
    end

    local resolved_scss_path = entry.scss_path or resolve_page_component_style_from_rust_path(page, entry.rust_path)

    if resolved_scss_path and delete_utils.file_exists(resolved_scss_path) then
        local style_dir = vim.fn.fnamemodify(resolved_scss_path, ":h")
        local forward_target = vim.fn.fnamemodify(resolved_scss_path, ":t:r"):gsub("^_", "")

        local removed_scss, scss_error = delete_utils.delete_path(resolved_scss_path, false)
        if not removed_scss then
            vim.notify(scss_error, vim.log.levels.WARN)
        else
            delete_utils.mark_once(touched_map, touched_files, resolved_scss_path)
        end

        local style_index = delete_utils.path_join(style_dir, "index.scss")
        if delete_utils.remove_forward(style_index, forward_target) then
            delete_utils.mark_once(touched_map, touched_files, style_index)
        end

        delete_utils.prune_empty_style_dirs(style_dir, page.style_module_dir, touched_map, touched_files)
    else
        vim.notify("No matching SCSS file found for " .. entry.component_name .. ". Deleted Rust component only.", vim.log.levels.WARN)
    end

    local style_components_dir = delete_utils.path_join(page.style_module_dir, "components")
    local has_components = module_has_page_components(page)
    if not has_components then
        if delete_utils.is_directory(style_components_dir) then
            local removed_components_dir, components_error = delete_utils.delete_path(style_components_dir, true)
            if not removed_components_dir then
                vim.notify(components_error, vim.log.levels.WARN)
            else
                delete_utils.mark_once(touched_map, touched_files, style_components_dir)
            end
        end

        local page_style_index = delete_utils.path_join(page.style_module_dir, "index.scss")
        if delete_utils.remove_forward(page_style_index, "components") then
            delete_utils.mark_once(touched_map, touched_files, page_style_index)
        end
    elseif delete_utils.is_directory(style_components_dir) then
        delete_utils.prune_empty_style_dirs(style_components_dir, page.style_module_dir, touched_map, touched_files)
    end

    if can_demote_page_to_flat(page) then
        local demoted = demote_page_module_to_flat(page, touched_map, touched_files)
        if demoted then
            vim.notify("Converted page " .. page.display_name .. " back to flat layout")
        end
    end

    vim.notify("Deleted page component " .. entry.component_name)
    if #touched_files > 0 then
        vim.notify(table.concat(touched_files, "\n"), vim.log.levels.INFO)
    end
end

local function delete_page(page)
    local touched_map = {}
    local touched_files = {}

    if page.is_module_layout then
        if delete_utils.is_directory(page.module_dir) then
            local removed_dir, dir_error = delete_utils.delete_path(page.module_dir, true)
            if not removed_dir then
                vim.notify(dir_error, vim.log.levels.WARN)
                return
            end

            delete_utils.mark_once(touched_map, touched_files, page.module_dir)
        else
            local removed_file, file_error = delete_utils.delete_path(page.rust_path, false)
            if not removed_file then
                vim.notify(file_error, vim.log.levels.WARN)
                return
            end

            delete_utils.mark_once(touched_map, touched_files, page.rust_path)
        end
    else
        local removed_rust, rust_error = delete_utils.delete_path(page.rust_path, false)
        if not removed_rust then
            vim.notify(rust_error, vim.log.levels.WARN)
            return
        end

        delete_utils.mark_once(touched_map, touched_files, page.rust_path)
    end

    local parent_mod = delete_utils.path_join(page.parent_dir, "mod.rs")
    if delete_utils.remove_module_reference(parent_mod, page.module_name) then
        delete_utils.mark_once(touched_map, touched_files, parent_mod)
    end

    delete_utils.remove_use_symbol_tree(PAGES_DIR, page.page_component_name, touched_map, touched_files)
    delete_utils.prune_empty_rust_dirs(page.parent_dir, PAGES_DIR, touched_map, touched_files)

    local style_prune_start = page.parent_relative ~= "" and delete_utils.path_join(PAGE_STYLES_DIR, page.parent_relative)
        or PAGE_STYLES_DIR

    if page.is_module_layout then
        if delete_utils.is_directory(page.style_module_dir) then
            local removed_style_dir, style_dir_error = delete_utils.delete_path(page.style_module_dir, true)
            if not removed_style_dir then
                vim.notify(style_dir_error, vim.log.levels.WARN)
            else
                delete_utils.mark_once(touched_map, touched_files, page.style_module_dir)
            end
        elseif page.page_scss then
            local removed_style, style_error = delete_utils.delete_path(page.page_scss, false)
            if not removed_style then
                vim.notify(style_error, vim.log.levels.WARN)
            else
                delete_utils.mark_once(touched_map, touched_files, page.page_scss)
            end
        end

        local parent_style_index = delete_utils.path_join(style_prune_start, "index.scss")
        if delete_utils.remove_forward(parent_style_index, page.module_name) then
            delete_utils.mark_once(touched_map, touched_files, parent_style_index)
        end
    else
        if page.page_scss and delete_utils.file_exists(page.page_scss) then
            local style_dir = vim.fn.fnamemodify(page.page_scss, ":h")
            local forward_target = vim.fn.fnamemodify(page.page_scss, ":t:r"):gsub("^_", "")

            local removed_style, style_error = delete_utils.delete_path(page.page_scss, false)
            if not removed_style then
                vim.notify(style_error, vim.log.levels.WARN)
            else
                delete_utils.mark_once(touched_map, touched_files, page.page_scss)
            end

            local style_index = delete_utils.path_join(style_dir, "index.scss")
            if delete_utils.remove_forward(style_index, forward_target) then
                delete_utils.mark_once(touched_map, touched_files, style_index)
            end

            style_prune_start = style_dir
        else
            local fallback_target = delete_utils.to_kebab_case(page.module_name)
            local parent_style_index = delete_utils.path_join(style_prune_start, "index.scss")
            if delete_utils.remove_forward(parent_style_index, fallback_target) then
                delete_utils.mark_once(touched_map, touched_files, parent_style_index)
            end
        end
    end

    delete_utils.prune_empty_style_dirs(style_prune_start, PAGE_STYLES_DIR, touched_map, touched_files)

    if delete_utils.remove_route_view(APP_PATH, page.page_component_name) then
        delete_utils.mark_once(touched_map, touched_files, APP_PATH)
    end

    vim.notify("Deleted page " .. page.display_name)
    if #touched_files > 0 then
        vim.notify(table.concat(touched_files, "\n"), vim.log.levels.INFO)
    end
end

local function confirm_delete(page, entry)
    local prompt
    if entry.entry_type == "page" then
        prompt = "Delete page " .. page.display_name .. "?"
    else
        prompt = "Delete page component " .. entry.component_name .. "?"
    end

    vim.ui.select({ "No", "Yes" }, { prompt = prompt }, function(choice)
        if choice ~= "Yes" then
            return
        end

        if entry.entry_type == "page" then
            delete_page(page)
        else
            delete_page_component(page, entry)
        end
    end)
end

local function pick_page_entries(page)
    local entries = collect_page_entries(page)

    pickers
        .new({}, {
            prompt_title = "Delete Page Item: " .. page.display_name,
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
                        confirm_delete(page, selection.value)
                    end
                end)

                return true
            end,
        })
        :find()
end

function M.pick()
    if not resolve_paths() then
        return
    end

    if vim.fn.isdirectory(PAGES_DIR) ~= 1 then
        vim.notify("Pages directory not found: " .. PAGES_DIR, vim.log.levels.WARN)
        return
    end

    local pages = collect_pages()
    if #pages == 0 then
        vim.notify("No page components found in " .. PAGES_DIR, vim.log.levels.WARN)
        return
    end

    pickers
        .new({}, {
            prompt_title = "Delete Page",
            finder = finders.new_table({
                results = pages,
                entry_maker = function(page)
                    return {
                        value = page,
                        display = page.display_name .. "  " .. page.rust_relative,
                        ordinal = page.display_name .. " " .. page.page_component_name .. " " .. page.rust_relative,
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
