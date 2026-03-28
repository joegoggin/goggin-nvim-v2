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
local PAGES_DIR = nil
local PAGE_STYLES_DIR = nil

local function resolve_paths()
    local paths, err = web_paths.resolve({ "components_dir", "styles_components_dir", "pages_dir", "page_styles_dir" })
    if not paths then
        vim.notify(err, vim.log.levels.WARN)
        return false
    end

    COMPONENTS_DIR = paths.components_dir
    STYLES_DIR = paths.styles_components_dir
    PAGES_DIR = paths.pages_dir
    PAGE_STYLES_DIR = paths.page_styles_dir

    return true
end

local function file_exists(path)
    return vim.uv.fs_stat(path) ~= nil
end

local function is_directory(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == "directory"
end

local function path_join(...)
    local parts = {}
    for _, part in ipairs({ ... }) do
        if part and part ~= "" then
            table.insert(parts, part)
        end
    end

    return table.concat(parts, "/")
end

local function join_segments(root, segments)
    local path = root
    for _, segment in ipairs(segments) do
        path = path_join(path, segment)
    end
    return path
end

local function path_relative(root, path)
    local prefix = root .. "/"
    if path:sub(1, #prefix) == prefix then
        return path:sub(#prefix + 1)
    end

    if path == root then
        return ""
    end

    return path
end

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_words(raw)
    local value = trim(raw or "")
    if value == "" then
        return {}
    end

    value = value:gsub("[-_]+", " ")
    value = value:gsub("(%l)(%u)", "%1 %2")
    value = value:gsub("(%u)(%u%l)", "%1 %2")

    local words = {}
    for word in value:gmatch("[%w]+") do
        table.insert(words, word:lower())
    end

    return words
end

local function to_snake_case(raw)
    return table.concat(split_words(raw), "_")
end

local function to_kebab_case(raw)
    return table.concat(split_words(raw), "-")
end

local function split_path_segments(path)
    local segments = {}
    for segment in (path or ""):gmatch("[^/]+") do
        if segment ~= "" and segment ~= "." then
            table.insert(segments, segment)
        end
    end
    return segments
end

local function copy_segments(segments)
    local copy = {}
    for _, segment in ipairs(segments or {}) do
        table.insert(copy, segment)
    end
    return copy
end

local function read_lines(path)
    if not file_exists(path) then
        return {}
    end

    return vim.fn.readfile(path)
end

local function write_lines(path, lines)
    vim.fn.writefile(lines, path)
end

local function ensure_directory(path)
    if not is_directory(path) then
        vim.fn.mkdir(path, "p")
    end
end

local function ensure_file(path)
    if not file_exists(path) then
        write_lines(path, {})
    end
end

local function has_line(lines, expected)
    for _, line in ipairs(lines) do
        if line == expected then
            return true
        end
    end

    return false
end

local function mark_once(map, list, path)
    if not map[path] then
        map[path] = true
        table.insert(list, path)
    end
end

local function parse_component_name(file_path)
    local lines = read_lines(file_path)
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

local function extract_existing_class_name(file_path)
    local lines = read_lines(file_path)

    for _, line in ipairs(lines) do
        local direct = line:match('ClassNameUtil::new%("([^"]+)"')
        if direct then
            return direct
        end

        local _, child = line:match('ClassNameUtil::new_with_parent%("([^"]+)",%s*"([^"]+)"')
        if child then
            return child
        end

        local layout = line:match('ClassNameUtil::new_layout_class_name%("([^"]+)"')
        if layout then
            return layout
        end
    end

    return nil
end

local function has_class_setup(lines)
    for _, line in ipairs(lines) do
        if line:find("ClassNameUtil::new(", 1, true)
            or line:find("ClassNameUtil::new_with_parent(", 1, true)
            or line:find("ClassNameUtil::new_layout_class_name(", 1, true)
        then
            return true
        end
    end

    return false
end

local function ensure_class_name_import(lines)
    for _, line in ipairs(lines) do
        if line:find("ClassNameUtil", 1, true) then
            return false
        end
    end

    local import_line = "use crate::utils::class_name::ClassNameUtil;"
    local last_use_index = nil

    for i, line in ipairs(lines) do
        if line:match("^%s*use%s+") then
            last_use_index = i
        end
    end

    if last_use_index then
        table.insert(lines, last_use_index + 1, import_line)
    else
        table.insert(lines, 1, import_line)
        table.insert(lines, 2, "")
    end

    return true
end

local function find_component_function(lines)
    local awaiting_component_fn = false
    local signature_start = nil
    local signature_lines = {}

    for i, line in ipairs(lines) do
        if line:match("^%s*#%s*%[%s*component%s*%]") then
            awaiting_component_fn = true
            signature_start = nil
            signature_lines = {}
        elseif awaiting_component_fn then
            if not signature_start then
                if line:match("^%s*pub%s+fn%s+") then
                    signature_start = i
                    table.insert(signature_lines, line)
                    if line:find("{", 1, true) then
                        return {
                            signature_start = signature_start,
                            body_start = i,
                            signature_text = table.concat(signature_lines, " "),
                            fn_indent = line:match("^(%s*)") or "",
                        }
                    end
                elseif not line:match("^%s*$") and not line:match("^%s*#") then
                    awaiting_component_fn = false
                end
            else
                table.insert(signature_lines, line)
                if line:find("{", 1, true) then
                    return {
                        signature_start = signature_start,
                        body_start = i,
                        signature_text = table.concat(signature_lines, " "),
                        fn_indent = lines[signature_start]:match("^(%s*)") or "",
                    }
                end
            end
        end
    end

    return nil
end

local function insert_class_setup(lines, class_name)
    if has_class_setup(lines) then
        return false, nil
    end

    local component_fn = find_component_function(lines)
    if not component_fn then
        return false, "Could not locate #[component] function body for class setup."
    end

    local has_class_param = component_fn.signature_text:match("class%s*:%s*Option%s*<%s*String%s*>") ~= nil
    local class_arg = has_class_param and "class" or "None"

    local var_name = to_snake_case(class_name)
    if var_name == "" then
        var_name = "component_class"
    end

    local body_indent = (component_fn.fn_indent or "") .. "    "
    local block = {
        body_indent .. "// Classes",
        string.format('%slet class_name = ClassNameUtil::new("%s", %s);', body_indent, class_name, class_arg),
        string.format("%slet %s = class_name.get_root_class();", body_indent, var_name),
        "",
    }

    local insert_at = component_fn.body_start + 1
    for i, entry in ipairs(block) do
        table.insert(lines, insert_at + i - 1, entry)
    end

    return true, nil
end

local function ensure_rust_class_setup(rust_path, class_name)
    local lines = read_lines(rust_path)
    if #lines == 0 then
        vim.notify("Rust file is empty or missing: " .. rust_path, vim.log.levels.WARN)
        return false
    end

    local changed = false

    if ensure_class_name_import(lines) then
        changed = true
    end

    local inserted, insert_error = insert_class_setup(lines, class_name)
    if inserted then
        changed = true
    elseif insert_error then
        vim.notify(insert_error .. "\n" .. rust_path, vim.log.levels.WARN)
    end

    if changed then
        write_lines(rust_path, lines)
    end

    return changed
end

local function ensure_forward(index_path, target)
    ensure_file(index_path)
    local line = string.format('@forward "%s";', target)
    local lines = read_lines(index_path)

    if has_line(lines, line) then
        return false
    end

    table.insert(lines, line)
    write_lines(index_path, lines)
    return true
end

local function ensure_style_forward_chain(style_root, segments, target, touched_map, touched_files)
    local current = style_root

    for _, segment in ipairs(segments) do
        ensure_directory(current)
        local parent_index = path_join(current, "index.scss")
        if ensure_forward(parent_index, segment) then
            mark_once(touched_map, touched_files, parent_index)
        end

        current = path_join(current, segment)
        ensure_directory(current)
    end

    local target_index = path_join(current, "index.scss")
    if ensure_forward(target_index, target) then
        mark_once(touched_map, touched_files, target_index)
    end
end

local function supports_buffer_formatting(bufnr)
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    for _, client in ipairs(clients) do
        if client.supports_method and client:supports_method("textDocument/formatting") then
            return true
        end
    end

    return false
end

local function format_file_with_nvim(path)
    if not file_exists(path) then
        return
    end

    local bufnr = vim.fn.bufadd(path)
    local was_loaded = vim.api.nvim_buf_is_loaded(bufnr)

    if not was_loaded then
        vim.fn.bufload(bufnr)
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    if supports_buffer_formatting(bufnr) then
        local format_ok, format_err = pcall(vim.lsp.buf.format, {
            bufnr = bufnr,
            async = false,
            timeout_ms = 5000,
        })

        if not format_ok then
            vim.notify("Formatting failed for " .. path .. ":\n" .. tostring(format_err), vim.log.levels.WARN)
        end
    end

    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified then
        local write_ok, write_err = pcall(vim.api.nvim_buf_call, bufnr, function()
            vim.cmd("silent write")
        end)

        if not write_ok then
            vim.notify("Failed to write formatted file " .. path .. ":\n" .. tostring(write_err), vim.log.levels.WARN)
        end
    end

    if not was_loaded and vim.api.nvim_buf_is_valid(bufnr) and vim.fn.bufwinnr(bufnr) == -1 and not vim.bo[bufnr].modified then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
end

local function format_touched_files(touched_files)
    local seen = {}

    for _, path in ipairs(touched_files) do
        local should_format = path:match("%.rs$") or path:match("%.scss$")
        if should_format and not seen[path] then
            seen[path] = true
            format_file_with_nvim(path)
        end
    end
end

local function open_created_pair(rust_path, scss_path)
    vim.schedule(function()
        if not file_exists(rust_path) then
            vim.notify("Rust file not found: " .. rust_path, vim.log.levels.WARN)
            return
        end

        vim.cmd("edit " .. vim.fn.fnameescape(rust_path))

        if scss_path and file_exists(scss_path) then
            vim.cmd("vsplit " .. vim.fn.fnameescape(scss_path))
            vim.cmd("wincmd h")
        elseif scss_path then
            vim.notify("Style file not found: " .. scss_path, vim.log.levels.WARN)
        end
    end)
end

local function build_scss_template(class_name)
    return {
        string.format(".%s {", class_name),
        "}",
    }
end

local function collect_forward_targets(index_path)
    local forwards = {}
    for _, line in ipairs(read_lines(index_path)) do
        local target = line:match('^%s*@forward%s+"([^"]+)"%s*;%s*$')
        if target then
            forwards[target] = true
        end
    end

    return forwards
end

local function resolve_partial_style_plan(base_dir, stem)
    local kebab_stem = stem:gsub("_", "-")
    local direct_target = kebab_stem
    local direct_path = path_join(base_dir, "_" .. direct_target .. ".scss")
    if file_exists(direct_path) then
        return {
            exists = true,
            path = direct_path,
            target = direct_target,
        }
    end

    local parent = vim.fn.fnamemodify(base_dir, ":t"):gsub("_", "-")
    local prefixed_target = parent .. "-" .. kebab_stem
    local prefixed_path = path_join(base_dir, "_" .. prefixed_target .. ".scss")
    if file_exists(prefixed_path) then
        return {
            exists = true,
            path = prefixed_path,
            target = prefixed_target,
        }
    end

    local prefer_prefixed = false
    if is_directory(base_dir) then
        local pattern = path_join(base_dir, "_" .. parent .. "-*.scss")
        prefer_prefixed = #vim.fn.glob(pattern, true, true) > 0
    end

    if prefer_prefixed then
        return {
            exists = false,
            path = prefixed_path,
            target = prefixed_target,
        }
    end

    return {
        exists = false,
        path = direct_path,
        target = direct_target,
    }
end

local function class_name_from_page_component(page_component_name)
    local base = (page_component_name or ""):gsub("Page$", "")
    local kebab = to_kebab_case(base)
    if kebab == "" then
        return nil
    end

    return kebab .. "-page"
end

local function display_page_name(component_name)
    if component_name:sub(-4) == "Page" then
        return component_name:sub(1, -5)
    end

    return component_name
end

local function map_component_style_segments(rust_segments, root_forwards)
    if #rust_segments == 0 then
        return {}
    end

    local mapped = copy_segments(rust_segments)
    local first = rust_segments[1]
    local singular = first:gsub("s$", "")
    local plural = first .. "s"

    if root_forwards[first] then
        mapped[1] = first
    elseif singular ~= first and root_forwards[singular] then
        mapped[1] = singular
    elseif root_forwards[plural] then
        mapped[1] = plural
    end

    local mapped_dir = join_segments(STYLES_DIR, mapped)
    local original_dir = join_segments(STYLES_DIR, rust_segments)
    if not is_directory(mapped_dir) and is_directory(original_dir) then
        return copy_segments(rust_segments)
    end

    return mapped
end

local function collect_regular_component_items(include_existing)
    local rust_files = vim.fn.glob(COMPONENTS_DIR .. "/**/*.rs", true, true)
    local root_forwards = collect_forward_targets(path_join(STYLES_DIR, "index.scss"))
    local items = {}

    for _, rust_path in ipairs(rust_files) do
        if vim.fn.fnamemodify(rust_path, ":t") ~= "mod.rs" then
            local component_name = parse_component_name(rust_path)
            if component_name then
                local rust_relative = path_relative(COMPONENTS_DIR, rust_path)
                local rust_relative_dir = vim.fn.fnamemodify(rust_relative, ":h")
                if rust_relative_dir == "." then
                    rust_relative_dir = ""
                end

                local rust_segments = split_path_segments(rust_relative_dir)
                local style_segments = map_component_style_segments(rust_segments, root_forwards)
                local style_base_dir = join_segments(STYLES_DIR, style_segments)
                local rust_stem = vim.fn.fnamemodify(rust_relative, ":t:r")
                local style_plan = resolve_partial_style_plan(style_base_dir, rust_stem)

                local include_item = (include_existing and style_plan.exists) or (not include_existing and not style_plan.exists)
                if include_item then
                    local class_name = extract_existing_class_name(rust_path)
                    if not class_name or class_name == "" then
                        class_name = style_plan.target
                    end

                    table.insert(items, {
                        item_type = "component",
                        kind_label = "Component",
                        component_name = component_name,
                        rust_path = rust_path,
                        rust_relative = rust_relative,
                        scss_path = style_plan.path,
                        style_segments = style_segments,
                        style_target = style_plan.target,
                        class_name = class_name,
                    })
                end
            end
        end
    end

    return items
end

local function collect_pages()
    local page_files = vim.fn.glob(PAGES_DIR .. "/**/*.rs", true, true)
    local page_by_module = {}

    for _, page_rs in ipairs(page_files) do
        local file_name = vim.fn.fnamemodify(page_rs, ":t")
        if file_name ~= "mod.rs" then
            local component_name = parse_component_name(page_rs)
            if component_name and component_name:sub(-4) == "Page" then
                local rust_relative = path_relative(PAGES_DIR, page_rs)
                local is_component_file = rust_relative:match("^components/") or rust_relative:match("/components/")

                if not is_component_file then
                    local without_ext = rust_relative:gsub("%.rs$", "")
                    local module_segments = split_path_segments(without_ext)
                    local is_module_layout = file_name == "page.rs"

                    if is_module_layout and module_segments[#module_segments] == "page" then
                        table.remove(module_segments, #module_segments)
                    end

                    if #module_segments > 0 then
                        local parent_segments = {}
                        for i = 1, #module_segments - 1 do
                            table.insert(parent_segments, module_segments[i])
                        end

                        local module_relative = table.concat(module_segments, "/")
                        local page = {
                            rust_path = page_rs,
                            rust_relative = rust_relative,
                            page_component_name = component_name,
                            display_name = display_page_name(component_name),
                            is_module_layout = is_module_layout,
                            module_segments = module_segments,
                            parent_segments = parent_segments,
                            module_name = module_segments[#module_segments],
                            module_dir = join_segments(PAGES_DIR, module_segments),
                        }

                        local existing = page_by_module[module_relative]
                        if not existing or (page.is_module_layout and not existing.is_module_layout) then
                            page_by_module[module_relative] = page
                        end
                    end
                end
            end
        end
    end

    local pages = {}
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

local function resolve_page_style_plan(page)
    if page.is_module_layout then
        local style_segments = copy_segments(page.module_segments)
        local style_dir = join_segments(PAGE_STYLES_DIR, style_segments)
        local scss_path = path_join(style_dir, "_page.scss")

        return {
            exists = file_exists(scss_path),
            path = scss_path,
            target = "page",
            segments = style_segments,
        }
    end

    local style_segments = copy_segments(page.parent_segments)
    local style_dir = join_segments(PAGE_STYLES_DIR, style_segments)
    local style_target = to_kebab_case(page.module_name)
    local scss_path = path_join(style_dir, "_" .. style_target .. ".scss")

    return {
        exists = file_exists(scss_path),
        path = scss_path,
        target = style_target,
        segments = style_segments,
    }
end

local function collect_page_related_items(include_existing)
    local items = {}
    local pages = collect_pages()

    for _, page in ipairs(pages) do
        local page_style = resolve_page_style_plan(page)
        local include_page = (include_existing and page_style.exists) or (not include_existing and not page_style.exists)
        if include_page then
            local class_name = extract_existing_class_name(page.rust_path) or class_name_from_page_component(page.page_component_name)
            if not class_name or class_name == "" then
                class_name = page_style.target
            end

            table.insert(items, {
                item_type = "page",
                kind_label = "Page",
                component_name = page.page_component_name,
                rust_path = page.rust_path,
                rust_relative = page.rust_relative,
                scss_path = page_style.path,
                style_segments = page_style.segments,
                style_target = page_style.target,
                class_name = class_name,
            })
        end

        if page.is_module_layout then
            local components_dir = path_join(page.module_dir, "components")
            if is_directory(components_dir) then
                local component_files = vim.fn.glob(components_dir .. "/**/*.rs", true, true)

                for _, rust_path in ipairs(component_files) do
                    if vim.fn.fnamemodify(rust_path, ":t") ~= "mod.rs" then
                        local component_name = parse_component_name(rust_path)
                        if component_name then
                            local relative_from_components = path_relative(components_dir, rust_path)
                            local component_subdir = vim.fn.fnamemodify(relative_from_components, ":h")
                            if component_subdir == "." then
                                component_subdir = ""
                            end

                            local style_segments = copy_segments(page.module_segments)
                            table.insert(style_segments, "components")
                            for _, segment in ipairs(split_path_segments(component_subdir)) do
                                table.insert(style_segments, segment)
                            end

                            local style_base_dir = join_segments(PAGE_STYLES_DIR, style_segments)
                            local stem = vim.fn.fnamemodify(relative_from_components, ":t:r")
                            local style_plan = resolve_partial_style_plan(style_base_dir, stem)

                            local include_component =
                                (include_existing and style_plan.exists) or (not include_existing and not style_plan.exists)
                            if include_component then
                                local class_name = extract_existing_class_name(rust_path)
                                if not class_name or class_name == "" then
                                    class_name = style_plan.target
                                end

                                table.insert(items, {
                                    item_type = "page_component",
                                    kind_label = "Page Component",
                                    component_name = component_name,
                                    rust_path = rust_path,
                                    rust_relative = path_relative(PAGES_DIR, rust_path),
                                    scss_path = style_plan.path,
                                    style_segments = style_segments,
                                    style_target = style_plan.target,
                                    class_name = class_name,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    return items
end

local TYPE_ORDER = {
    page = 1,
    page_component = 2,
    component = 3,
}

local function collect_style_items(include_existing)
    local items = {}

    for _, item in ipairs(collect_page_related_items(include_existing)) do
        table.insert(items, item)
    end

    for _, item in ipairs(collect_regular_component_items(include_existing)) do
        table.insert(items, item)
    end

    table.sort(items, function(a, b)
        local order_a = TYPE_ORDER[a.item_type] or 99
        local order_b = TYPE_ORDER[b.item_type] or 99
        if order_a ~= order_b then
            return order_a < order_b
        end

        if a.component_name == b.component_name then
            return a.rust_relative < b.rust_relative
        end

        return a.component_name < b.component_name
    end)

    return items
end

local function create_missing_style(item)
    if file_exists(item.scss_path) then
        vim.notify("Style file already exists: " .. item.scss_path, vim.log.levels.WARN)
        open_created_pair(item.rust_path, item.scss_path)
        return
    end

    local class_name = item.class_name
    if not class_name or class_name == "" then
        vim.notify("Could not derive class name for " .. item.component_name, vim.log.levels.WARN)
        return
    end

    local touched_map = {}
    local touched_files = {}

    local style_dir = vim.fn.fnamemodify(item.scss_path, ":h")
    ensure_directory(style_dir)
    write_lines(item.scss_path, build_scss_template(class_name))
    mark_once(touched_map, touched_files, item.scss_path)

    ensure_style_forward_chain(
        item.item_type == "component" and STYLES_DIR or PAGE_STYLES_DIR,
        item.style_segments,
        item.style_target,
        touched_map,
        touched_files
    )

    if ensure_rust_class_setup(item.rust_path, class_name) then
        mark_once(touched_map, touched_files, item.rust_path)
    end

    format_touched_files(touched_files)
    open_created_pair(item.rust_path, item.scss_path)
end

local function delete_existing_style(item)
    if not file_exists(item.scss_path) then
        vim.notify("Style file not found: " .. item.scss_path, vim.log.levels.WARN)
        return
    end

    local touched_map = {}
    local touched_files = {}

    local removed_scss, scss_error = delete_utils.delete_path(item.scss_path, false)
    if not removed_scss then
        vim.notify(scss_error, vim.log.levels.WARN)
        return
    end

    mark_once(touched_map, touched_files, item.scss_path)

    local style_dir = vim.fn.fnamemodify(item.scss_path, ":h")
    local style_index = path_join(style_dir, "index.scss")
    if delete_utils.remove_forward(style_index, item.style_target) then
        mark_once(touched_map, touched_files, style_index)
    end

    local style_root = item.item_type == "component" and STYLES_DIR or PAGE_STYLES_DIR
    delete_utils.prune_empty_style_dirs(style_dir, style_root, touched_map, touched_files)

    format_touched_files(touched_files)

    vim.notify("Successfully deleted style for " .. item.component_name)
end

local function ensure_required_directories()
    if vim.fn.isdirectory(COMPONENTS_DIR) ~= 1 or vim.fn.isdirectory(PAGES_DIR) ~= 1 then
        vim.notify("Component or page directories were not found.", vim.log.levels.WARN)
        return false
    end

    if vim.fn.isdirectory(STYLES_DIR) ~= 1 or vim.fn.isdirectory(PAGE_STYLES_DIR) ~= 1 then
        vim.notify("Component or page style directories were not found.", vim.log.levels.WARN)
        return false
    end

    return true
end

local function pick_items(prompt_title, items, on_select)
    pickers
        .new({}, {
            prompt_title = prompt_title,
            finder = finders.new_table({
                results = items,
                entry_maker = function(item)
                    return {
                        value = item,
                        display = string.format("[%s] %s  %s", item.kind_label, item.component_name, item.rust_relative),
                        ordinal = item.kind_label .. " " .. item.component_name .. " " .. item.rust_relative,
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    local selection = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)

                    if selection and selection.value then
                        on_select(selection.value)
                    end
                end)

                return true
            end,
        })
        :find()
end

local function confirm_delete(item)
    vim.ui.select({ "No", "Yes" }, { prompt = "Delete style for " .. item.component_name .. "?" }, function(choice)
        if choice == "Yes" then
            delete_existing_style(item)
        end
    end)
end

function M.pick()
    if not resolve_paths() then
        return
    end

    if not ensure_required_directories() then
        return
    end

    local items = collect_style_items(false)
    if #items == 0 then
        vim.notify("No pages or components are missing styles.", vim.log.levels.WARN)
        return
    end

    pick_items("Add Missing Style", items, create_missing_style)
end

function M.pick_delete()
    if not resolve_paths() then
        return
    end

    if not ensure_required_directories() then
        return
    end

    local items = collect_style_items(true)
    if #items == 0 then
        vim.notify("No pages or components with styles were found.", vim.log.levels.WARN)
        return
    end

    pick_items("Delete Style", items, confirm_delete)
end

return M
