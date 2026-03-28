local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local web_paths = require("goggin.telescope.web_paths")

local M = {}

local PAGES_DIR = nil
local PAGE_STYLES_DIR = nil
local APP_PATH = nil

local function resolve_paths()
    local paths, err = web_paths.resolve({ "pages_dir", "page_styles_dir" })
    if not paths then
        vim.notify(err, vim.log.levels.WARN)
        return false
    end

    PAGES_DIR = paths.pages_dir
    PAGE_STYLES_DIR = paths.page_styles_dir
    APP_PATH = paths.app_path

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

local function split_words(raw)
    local value = trim(raw)
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

local function to_pascal_case(raw)
    local words = split_words(raw)
    local parts = {}

    for _, word in ipairs(words) do
        table.insert(parts, word:sub(1, 1):upper() .. word:sub(2))
    end

    return table.concat(parts, "")
end

local function to_snake_case(raw)
    return table.concat(split_words(raw), "_")
end

local function to_kebab_case(raw)
    return table.concat(split_words(raw), "-")
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

local function has_line(lines, expected)
    for _, line in ipairs(lines) do
        if line == expected then
            return true
        end
    end
    return false
end

local function normalize_mod_layout(mod_path)
    local lines = read_lines(mod_path)
    local mod_lines = {}
    local use_lines = {}
    local other_lines = {}

    for _, line in ipairs(lines) do
        if line:match("^pub mod ") or line:match("^mod ") then
            table.insert(mod_lines, line)
        elseif line:match("^pub use ") then
            table.insert(use_lines, line)
        elseif line:match("^%s*$") then
            -- rebuilt below
        else
            table.insert(other_lines, line)
        end
    end

    local normalized = {}
    for _, line in ipairs(mod_lines) do
        table.insert(normalized, line)
    end

    if #mod_lines > 0 and (#use_lines > 0 or #other_lines > 0) then
        table.insert(normalized, "")
    end

    for _, line in ipairs(use_lines) do
        table.insert(normalized, line)
    end

    if #other_lines > 0 then
        if #normalized > 0 and normalized[#normalized] ~= "" then
            table.insert(normalized, "")
        end

        for _, line in ipairs(other_lines) do
            table.insert(normalized, line)
        end
    end

    write_lines(mod_path, normalized)
end

local function ensure_mod_declaration(mod_path, module_name, private)
    ensure_file(mod_path)
    local lines = read_lines(mod_path)
    local declaration = (private and "mod " or "pub mod ") .. module_name .. ";"

    if has_line(lines, declaration) then
        return false
    end

    if private and has_line(lines, "pub mod " .. module_name .. ";") then
        return false
    end

    if not private and has_line(lines, "mod " .. module_name .. ";") then
        return false
    end

    local last_mod_index = nil
    local first_use_index = nil

    for i, line in ipairs(lines) do
        if line:match("^pub mod ") or line:match("^mod ") then
            last_mod_index = i
        end

        if line:match("^pub use ") then
            first_use_index = i
            break
        end
    end

    if last_mod_index then
        table.insert(lines, last_mod_index + 1, declaration)
    elseif first_use_index then
        table.insert(lines, first_use_index, declaration)
    else
        table.insert(lines, declaration)
    end

    write_lines(mod_path, lines)
    return true
end

local function ensure_use_declaration(mod_path, use_expression)
    ensure_file(mod_path)
    local lines = read_lines(mod_path)
    local declaration = "pub use " .. use_expression .. ";"

    if has_line(lines, declaration) then
        return false
    end

    local last_use_index = nil
    for i, line in ipairs(lines) do
        if line:match("^pub use ") then
            last_use_index = i
        end
    end

    if last_use_index then
        table.insert(lines, last_use_index + 1, declaration)
    else
        table.insert(lines, declaration)
    end

    write_lines(mod_path, lines)
    return true
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

local function replace_forward(index_path, old_target, new_target)
    ensure_file(index_path)

    local old_line = string.format('@forward "%s";', old_target)
    local new_line = string.format('@forward "%s";', new_target)
    local lines = read_lines(index_path)
    local changed = false
    local has_new = has_line(lines, new_line)
    local normalized = {}

    for _, line in ipairs(lines) do
        if old_target ~= new_target and line == old_line then
            if not has_new then
                table.insert(normalized, new_line)
                has_new = true
            end
            changed = true
        else
            table.insert(normalized, line)
        end
    end

    if not has_new then
        table.insert(normalized, new_line)
        changed = true
    end

    if changed then
        write_lines(index_path, normalized)
    end

    return changed
end

local function move_path(source, destination)
    if source == destination then
        return true, nil
    end

    local result = vim.fn.rename(source, destination)
    if result == 0 then
        return true, nil
    end

    return false, string.format("Failed to move %s to %s", source, destination)
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

local function style_forward_target_from_path(style_path)
    local stem = vim.fn.fnamemodify(style_path, ":t:r")
    return stem:gsub("^_", "")
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

local function parse_component_name(file_path)
    local lines = read_lines(file_path)
    local awaiting_component_fn = false

    for _, line in ipairs(lines) do
        if line:match("^%s*#%s*%[%s*component%s*%]") then
            awaiting_component_fn = true
        elseif awaiting_component_fn then
            local name = line:match("^%s*pub%s+fn%s+([%w_]+)")
            if name then
                return name
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

local function resolve_page_style_path(page)
    if page.is_module_layout then
        local module_style_dir =
            page.module_relative_dir ~= "" and path_join(PAGE_STYLES_DIR, page.module_relative_dir) or PAGE_STYLES_DIR
        local module_style = path_join(module_style_dir, "_page.scss")
        if file_exists(module_style) then
            return module_style
        end

        return nil
    end

    local style_parent_dir =
        page.rust_parent_relative ~= "" and path_join(PAGE_STYLES_DIR, page.rust_parent_relative) or PAGE_STYLES_DIR

    local by_stem = resolve_partial_style(style_parent_dir, page.module_name)
    if by_stem then
        return by_stem
    end

    local component_kebab = to_kebab_case(page.page_component_name)
    if component_kebab ~= "" then
        local by_component = path_join(style_parent_dir, "_" .. component_kebab .. ".scss")
        if file_exists(by_component) then
            return by_component
        end

        local without_page_suffix = component_kebab:gsub("%-page$", "")
        if without_page_suffix ~= component_kebab then
            local by_component_without_page = path_join(style_parent_dir, "_" .. without_page_suffix .. ".scss")
            if file_exists(by_component_without_page) then
                return by_component_without_page
            end
        end
    end

    return nil
end

local function collect_pages()
    local page_files = vim.fn.glob(PAGES_DIR .. "/**/*.rs", true, true)
    local page_by_module = {}
    local pages = {}

    for _, page_rs in ipairs(page_files) do
        local file_name = vim.fn.fnamemodify(page_rs, ":t")
        if file_name ~= "mod.rs" then
            local component_name = parse_component_name(page_rs)
            if component_name and component_name:sub(-4) == "Page" then
                local rust_relative = path_relative(PAGES_DIR, page_rs)
                local is_component_file = rust_relative:match("^components/") or rust_relative:match("/components/")
                if not is_component_file then
                    local rust_parent_relative = vim.fn.fnamemodify(rust_relative, ":h")
                    if rust_parent_relative == "." then
                        rust_parent_relative = ""
                    end

                    local module_name = vim.fn.fnamemodify(rust_relative, ":t:r")
                    local is_module_layout = file_name == "page.rs"
                    local module_relative_dir = module_name

                    if is_module_layout then
                        module_relative_dir = rust_parent_relative
                        module_name = vim.fn.fnamemodify(module_relative_dir, ":t")
                    elseif rust_parent_relative ~= "" then
                        module_relative_dir = path_join(rust_parent_relative, module_name)
                    end

                    if module_relative_dir ~= "" then
                        local page = {
                            page_rs = page_rs,
                            rust_relative = rust_relative,
                            rust_parent_relative = rust_parent_relative,
                            page_dir = path_join(PAGES_DIR, module_relative_dir),
                            relative_dir = module_relative_dir,
                            module_relative_dir = module_relative_dir,
                            module_name = module_name,
                            is_module_layout = is_module_layout,
                            page_component_name = component_name,
                            display_name = component_name:gsub("Page$", ""),
                        }

                        page.page_style_path = resolve_page_style_path(page)

                        local existing = page_by_module[module_relative_dir]
                        if not existing or (page.is_module_layout and not existing.is_module_layout) then
                            page_by_module[module_relative_dir] = page
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
            return a.module_relative_dir < b.module_relative_dir
        end

        return a.display_name < b.display_name
    end)

    return pages
end

local function route_segment_to_fs(segment)
    local cleaned = trim(segment)
    cleaned = cleaned:gsub("^:", "")
    cleaned = cleaned:gsub("%*", "all")

    local snake = to_snake_case(cleaned)
    if snake == "" then
        return "index"
    end

    return snake
end

local function route_segment_to_path(segment)
    local cleaned = trim(segment)
    if cleaned:sub(1, 1) == ":" then
        return cleaned
    end
    return to_kebab_case(cleaned)
end

local function parse_route_segments(route_value, subroute_value)
    local raw_route = trim(route_value)
    local raw_subroute = trim(subroute_value or "")

    if raw_route == "" then
        return nil, "Route is required."
    end

    if raw_route == "/" and raw_subroute ~= "" then
        return nil, "Root route cannot include sub-route."
    end

    local route_segments = {}
    if raw_route ~= "/" then
        local normalized_route = raw_route:gsub("^/+", ""):gsub("/+$", "")
        for _, segment in ipairs(split_path_segments(normalized_route)) do
            table.insert(route_segments, segment)
        end
    end

    local sub_segments = {}
    if raw_subroute ~= "" then
        local normalized_sub = raw_subroute:gsub("^/+", ""):gsub("/+$", "")
        for _, segment in ipairs(split_path_segments(normalized_sub)) do
            table.insert(sub_segments, segment)
        end
    end

    local path_segments = {}
    local fs_segments = {}

    for _, segment in ipairs(route_segments) do
        table.insert(path_segments, route_segment_to_path(segment))
        table.insert(fs_segments, route_segment_to_fs(segment))
    end

    for _, segment in ipairs(sub_segments) do
        table.insert(path_segments, route_segment_to_path(segment))
        table.insert(fs_segments, route_segment_to_fs(segment))
    end

    local route_path = #path_segments == 0 and "/" or "/" .. table.concat(path_segments, "/")

    return {
        route_path = route_path,
        path_segments = path_segments,
        fs_segments = fs_segments,
        route_segments = route_segments,
    }, nil
end

local function build_page_component_name(input_name)
    local base = to_pascal_case(input_name)
    base = base:gsub("Page$", "")

    if base == "" then
        return nil
    end

    return base .. "Page"
end

local function class_name_from_component(component_name)
    local base = component_name:gsub("Page$", "")
    local kebab = to_kebab_case(base)
    if kebab == "" then
        return nil
    end

    return kebab .. "-page"
end

local function build_page_rust_template(component_name, class_name)
    local var_name = to_snake_case(class_name)

    return {
        "use leptos::prelude::*;",
        "",
        "use crate::utils::class_name::ClassNameUtil;",
        "",
        "#[component]",
        string.format("pub fn %s() -> impl IntoView {", component_name),
        "    // Classes",
        string.format('    let class_name = ClassNameUtil::new("%s", None);', class_name),
        string.format("    let %s = class_name.get_root_class();", var_name),
        "",
        "    view! {",
        string.format("        <div class=%s></div>", var_name),
        "    }",
        "}",
    }
end

local function build_page_component_template(component_name, class_name, var_name)
    return {
        "use leptos::prelude::*;",
        "",
        "use crate::utils::class_name::ClassNameUtil;",
        "",
        "#[component]",
        string.format("pub fn %s(#[prop(optional, into)] class: Option<String>) -> impl IntoView {", component_name),
        "    // Classes",
        string.format('    let class_name = ClassNameUtil::new("%s", class);', class_name),
        string.format("    let %s = class_name.get_root_class();", var_name),
        "",
        "    view! {",
        string.format("        <div class=%s></div>", var_name),
        "    }",
        "}",
    }
end

local function build_scss_template(class_name)
    return {
        string.format(".%s {", class_name),
        "}",
    }
end

local function mark_once(map, list, path)
    if not map[path] then
        map[path] = true
        table.insert(list, path)
    end
end

local function ensure_page_export(fs_segments, component_name, touched_map, touched_files)
    local pages_root_mod = path_join(PAGES_DIR, "mod.rs")
    local top_segment = fs_segments[1]
    local root_wildcard = false

    if top_segment then
        local root_lines = read_lines(pages_root_mod)
        root_wildcard = has_line(root_lines, "pub use " .. top_segment .. "::*;")
    end

    if root_wildcard and #fs_segments > 1 then
        local tail_segments = {}
        for i = 2, #fs_segments do
            table.insert(tail_segments, fs_segments[i])
        end

        local top_mod = path_join(PAGES_DIR, top_segment, "mod.rs")
        local top_use = table.concat(tail_segments, "::") .. "::" .. component_name
        if ensure_use_declaration(top_mod, top_use) then
            mark_once(touched_map, touched_files, top_mod)
        end
        normalize_mod_layout(top_mod)
        mark_once(touched_map, touched_files, top_mod)
        return
    end

    if not root_wildcard then
        local root_use = table.concat(fs_segments, "::") .. "::" .. component_name
        if ensure_use_declaration(pages_root_mod, root_use) then
            mark_once(touched_map, touched_files, pages_root_mod)
        end
        normalize_mod_layout(pages_root_mod)
        mark_once(touched_map, touched_files, pages_root_mod)
    end
end

local function insert_route_into_app(route_path, view_name, is_private)
    local lines = read_lines(APP_PATH)
    local indent = "                    "
    local route_tag = is_private and "PrivateRoute" or "Route"
    local macro_path = route_path
    if route_path:sub(1, 6) == "/auth/" then
        macro_path = route_path:sub(2)
    elseif route_path == "/auth" then
        macro_path = "auth"
    end

    local route_line = string.format('%s<%s path=path!("%s") view=%s />', indent, route_tag, macro_path, view_name)
    if has_line(lines, route_line) then
        return false
    end

    local function title_case(segment)
        local words = split_words(segment)
        local parts = {}
        for _, word in ipairs(words) do
            table.insert(parts, word:sub(1, 1):upper() .. word:sub(2))
        end
        return table.concat(parts, " ")
    end

    local top_segment = "home"
    if route_path ~= "/" then
        top_segment = split_path_segments(route_path:gsub("^/+", ""):gsub("/+$", ""))[1] or "home"
    end

    local group_label
    if route_path == "/" then
        group_label = "Home"
    elseif top_segment == "auth" then
        group_label = "Auth routes"
    else
        group_label = title_case(top_segment)
    end

    local comment_line = indent .. "// " .. group_label
    local comment_index = nil
    local routes_end_index = nil

    for i, line in ipairs(lines) do
        if line:match("^%s*</Routes>") then
            routes_end_index = i
            break
        end
        if line == comment_line then
            comment_index = i
        end
    end

    if not routes_end_index then
        return false
    end

    if comment_index then
        local insert_at = routes_end_index
        for i = comment_index + 1, routes_end_index do
            if lines[i] and lines[i]:match("^%s*// ") then
                insert_at = i
                break
            end
        end

        while insert_at > comment_index + 1 and lines[insert_at - 1]:match("^%s*$") do
            insert_at = insert_at - 1
        end

        table.insert(lines, insert_at, route_line)
    else
        local block = {
            "",
            comment_line,
            route_line,
        }
        for index = #block, 1, -1 do
            table.insert(lines, routes_end_index, block[index])
        end
    end

    write_lines(APP_PATH, lines)
    return true
end

local function create_page(route_value, is_private, page_name_input, subroute_value)
    local parsed, parse_error = parse_route_segments(route_value, subroute_value)
    if parse_error then
        vim.notify(parse_error, vim.log.levels.WARN)
        return
    end

    local component_name = build_page_component_name(page_name_input)
    if not component_name then
        vim.notify("Invalid page name.", vim.log.levels.WARN)
        return
    end

    if #parsed.fs_segments == 0 then
        vim.notify("Root route generation is not supported by this generator.", vim.log.levels.WARN)
        return
    end

    local class_name = class_name_from_component(component_name)
    if not class_name then
        vim.notify("Invalid page class name.", vim.log.levels.WARN)
        return
    end

    local leaf_segment = parsed.fs_segments[#parsed.fs_segments]
    local parent_segments = {}
    for i = 1, #parsed.fs_segments - 1 do
        table.insert(parent_segments, parsed.fs_segments[i])
    end

    local pages_cursor = PAGES_DIR
    for _, segment in ipairs(parent_segments) do
        local conflicting_flat_page = path_join(pages_cursor, segment .. ".rs")
        if file_exists(conflicting_flat_page) then
            vim.notify(
                "Cannot create nested page under flat page: " .. conflicting_flat_page .. ". Convert it to a module first.",
                vim.log.levels.WARN
            )
            return
        end

        pages_cursor = path_join(pages_cursor, segment)
    end

    local current_pages_dir = PAGES_DIR
    local current_style_dir = PAGE_STYLES_DIR
    for _, segment in ipairs(parent_segments) do
        current_pages_dir = path_join(current_pages_dir, segment)
        current_style_dir = path_join(current_style_dir, segment)
    end

    ensure_directory(current_pages_dir)
    ensure_directory(current_style_dir)

    local rust_path = path_join(current_pages_dir, leaf_segment .. ".rs")
    local module_page_path = path_join(current_pages_dir, leaf_segment, "page.rs")
    local scss_stem = to_kebab_case(leaf_segment)
    local scss_path = path_join(current_style_dir, "_" .. scss_stem .. ".scss")
    local module_scss_path = path_join(current_style_dir, leaf_segment, "_page.scss")

    if file_exists(rust_path) or file_exists(module_page_path) then
        vim.notify("Page already exists: " .. rust_path, vim.log.levels.WARN)
        return
    end

    if file_exists(scss_path) or file_exists(module_scss_path) then
        vim.notify("Page style already exists: " .. scss_path, vim.log.levels.WARN)
        return
    end

    write_lines(rust_path, build_page_rust_template(component_name, class_name))
    write_lines(scss_path, build_scss_template(class_name))

    local touched_map = {}
    local touched_files = {}
    mark_once(touched_map, touched_files, rust_path)
    mark_once(touched_map, touched_files, scss_path)

    current_pages_dir = PAGES_DIR
    for _, segment in ipairs(parent_segments) do
        local parent_mod = path_join(current_pages_dir, "mod.rs")
        if ensure_mod_declaration(parent_mod, segment, false) then
            mark_once(touched_map, touched_files, parent_mod)
        end

        normalize_mod_layout(parent_mod)
        mark_once(touched_map, touched_files, parent_mod)

        current_pages_dir = path_join(current_pages_dir, segment)
        ensure_directory(current_pages_dir)
        ensure_file(path_join(current_pages_dir, "mod.rs"))
    end

    local leaf_parent_mod = path_join(current_pages_dir, "mod.rs")
    if ensure_mod_declaration(leaf_parent_mod, leaf_segment, false) then
        mark_once(touched_map, touched_files, leaf_parent_mod)
    end
    normalize_mod_layout(leaf_parent_mod)
    mark_once(touched_map, touched_files, leaf_parent_mod)

    ensure_page_export(parsed.fs_segments, component_name, touched_map, touched_files)

    current_style_dir = PAGE_STYLES_DIR
    for _, segment in ipairs(parent_segments) do
        local parent_index = path_join(current_style_dir, "index.scss")
        if ensure_forward(parent_index, segment) then
            mark_once(touched_map, touched_files, parent_index)
        end

        current_style_dir = path_join(current_style_dir, segment)
        ensure_directory(current_style_dir)
    end

    local parent_index = path_join(current_style_dir, "index.scss")
    if ensure_forward(parent_index, scss_stem) then
        mark_once(touched_map, touched_files, parent_index)
    end

    if insert_route_into_app(parsed.route_path, component_name, is_private) then
        mark_once(touched_map, touched_files, APP_PATH)
    end

    format_touched_files(touched_files)

    open_created_pair(rust_path, scss_path)
end

local function collect_component_subdirectories(base_dir)
    local directories = vim.fn.glob(base_dir .. "/**/", true, true)
    local seen = {}
    local results = {}

    for _, directory in ipairs(directories) do
        if directory ~= base_dir .. "/" then
            local cleaned = directory:gsub("/$", "")
            local relative = cleaned:sub(#base_dir + 2)
            if relative ~= "" and not seen[relative] then
                seen[relative] = true
                table.insert(results, relative)
            end
        end
    end

    table.sort(results)
    return results
end

local function collect_page_subdirectories(base_dir)
    local directories = vim.fn.glob(base_dir .. "/**/", true, true)
    local seen = {}
    local results = {}

    for _, directory in ipairs(directories) do
        if directory ~= base_dir .. "/" then
            local cleaned = directory:gsub("/$", "")
            local relative = cleaned:sub(#base_dir + 2)
            local is_components_path =
                relative == "components"
                or relative:match("^components/")
                or relative:match("/components$")
                or relative:match("/components/")

            if relative ~= "" and not is_components_path and not seen[relative] then
                seen[relative] = true
                table.insert(results, relative)
            end
        end
    end

    table.sort(results)
    return results
end

local function normalize_relative_dir(input)
    local raw_segments = split_path_segments(input)
    local normalized = {}

    for _, segment in ipairs(raw_segments) do
        local snake_segment = to_snake_case(segment)
        if snake_segment ~= "" then
            table.insert(normalized, snake_segment)
        end
    end

    return table.concat(normalized, "/")
end

local function choose_page_subdirectory(on_select)
    local options = collect_page_subdirectories(PAGES_DIR)
    table.insert(options, "+ Create new sub-directory")

    vim.ui.select(options, { prompt = "Select page sub-directory" }, function(choice)
        if not choice then
            return
        end

        if choice == "+ Create new sub-directory" then
            vim.ui.input({ prompt = "New sub-directory (relative to pages): " }, function(new_dir)
                if not new_dir or trim(new_dir) == "" then
                    return
                end

                local normalized = normalize_relative_dir(new_dir)
                if normalized == "" then
                    vim.notify("Invalid sub-directory.", vim.log.levels.WARN)
                    return
                end

                on_select(normalized)
            end)
            return
        end

        on_select(choice)
    end)
end

local function ensure_page_components_module(page_mod_path)
    ensure_file(page_mod_path)
    local lines = read_lines(page_mod_path)

    if has_line(lines, "mod components;") or has_line(lines, "pub mod components;") then
        return false
    end

    local first_pub_mod = nil
    for i, line in ipairs(lines) do
        if line:match("^pub mod ") then
            first_pub_mod = i
            break
        end
    end

    if first_pub_mod then
        table.insert(lines, first_pub_mod, "mod components;")
    else
        table.insert(lines, "mod components;")
    end

    write_lines(page_mod_path, lines)
    return true
end

local function convert_page_to_module_layout(page, touched_map, touched_files)
    if page.is_module_layout then
        return true
    end

    local source_rust_path = page.page_rs
    local target_page_dir = page.page_dir
    local target_rust_path = path_join(target_page_dir, "page.rs")

    if not file_exists(source_rust_path) then
        vim.notify("Page file not found: " .. source_rust_path, vim.log.levels.WARN)
        return false
    end

    if file_exists(target_rust_path) then
        vim.notify("Cannot convert page. Target already exists: " .. target_rust_path, vim.log.levels.WARN)
        return false
    end

    ensure_directory(target_page_dir)

    local moved_page, page_move_error = move_path(source_rust_path, target_rust_path)
    if not moved_page then
        vim.notify(page_move_error, vim.log.levels.WARN)
        return false
    end

    mark_once(touched_map, touched_files, target_rust_path)

    local page_mod = path_join(target_page_dir, "mod.rs")
    if ensure_page_components_module(page_mod) then
        mark_once(touched_map, touched_files, page_mod)
    end
    if ensure_mod_declaration(page_mod, "page", false) then
        mark_once(touched_map, touched_files, page_mod)
    end
    if ensure_use_declaration(page_mod, "page::" .. page.page_component_name) then
        mark_once(touched_map, touched_files, page_mod)
    end
    normalize_mod_layout(page_mod)
    mark_once(touched_map, touched_files, page_mod)

    local module_style_dir = path_join(PAGE_STYLES_DIR, page.module_relative_dir)
    local target_style_path = path_join(module_style_dir, "_page.scss")
    local existing_style_path = page.page_style_path

    ensure_directory(module_style_dir)

    if existing_style_path and file_exists(existing_style_path) then
        if existing_style_path ~= target_style_path then
            if file_exists(target_style_path) then
                vim.notify("Cannot convert page style. Target already exists: " .. target_style_path, vim.log.levels.WARN)
                return false
            end

            local moved_style, style_move_error = move_path(existing_style_path, target_style_path)
            if not moved_style then
                vim.notify(style_move_error, vim.log.levels.WARN)
                return false
            end
        end
    elseif not file_exists(target_style_path) then
        local class_name = class_name_from_component(page.page_component_name)
        if class_name then
            write_lines(target_style_path, build_scss_template(class_name))
        else
            write_lines(target_style_path, {})
        end
    end

    mark_once(touched_map, touched_files, target_style_path)

    local module_style_index = path_join(module_style_dir, "index.scss")
    if ensure_forward(module_style_index, "page") then
        mark_once(touched_map, touched_files, module_style_index)
    end

    local parent_style_dir =
        page.rust_parent_relative ~= "" and path_join(PAGE_STYLES_DIR, page.rust_parent_relative) or PAGE_STYLES_DIR
    local parent_style_index = path_join(parent_style_dir, "index.scss")
    local previous_forward_target = to_kebab_case(page.module_name)
    if existing_style_path and existing_style_path ~= "" then
        previous_forward_target = style_forward_target_from_path(existing_style_path)
    end

    if replace_forward(parent_style_index, previous_forward_target, page.module_name) then
        mark_once(touched_map, touched_files, parent_style_index)
    end

    page.page_rs = target_rust_path
    page.rust_relative = path_relative(PAGES_DIR, target_rust_path)
    page.rust_parent_relative = page.module_relative_dir
    page.is_module_layout = true
    page.page_style_path = target_style_path

    return true
end

local function create_page_component(page, input_name, relative_dir)
    local touched_map = {}
    local touched_files = {}

    local normalized_input = to_pascal_case(input_name)
    if normalized_input == "" then
        vim.notify("Invalid component name.", vim.log.levels.WARN)
        return
    end

    local suffix = normalized_input
    if normalized_input:sub(1, #page.page_component_name) == page.page_component_name then
        suffix = normalized_input:sub(#page.page_component_name + 1)
    end

    if suffix == "" then
        vim.notify("Component name must add a suffix to " .. page.page_component_name, vim.log.levels.WARN)
        return
    end

    local module_name = to_snake_case(suffix)
    local suffix_kebab = to_kebab_case(suffix)
    local page_prefix = to_kebab_case(page.page_component_name:gsub("Page$", "")) .. "-page"
    local class_name = page_prefix .. "-" .. suffix_kebab
    local component_name = page.page_component_name .. suffix

    local base_rust_dir = path_join(page.page_dir, "components")
    local base_style_dir = path_join(PAGE_STYLES_DIR, page.relative_dir, "components")

    local rust_dir = base_rust_dir
    local style_dir = base_style_dir

    if relative_dir ~= "" then
        rust_dir = path_join(rust_dir, relative_dir)
        style_dir = path_join(style_dir, relative_dir)
    end

    local rust_path = path_join(rust_dir, module_name .. ".rs")
    local scss_path = path_join(style_dir, "_" .. suffix_kebab .. ".scss")

    if file_exists(rust_path) then
        vim.notify("Page component already exists: " .. rust_path, vim.log.levels.WARN)
        return
    end

    if file_exists(scss_path) then
        vim.notify("Page component style already exists: " .. scss_path, vim.log.levels.WARN)
        return
    end

    if not page.is_module_layout then
        local converted = convert_page_to_module_layout(page, touched_map, touched_files)
        if not converted then
            return
        end
    end

    ensure_directory(rust_dir)
    ensure_directory(style_dir)

    write_lines(rust_path, build_page_component_template(component_name, class_name, module_name))
    write_lines(scss_path, build_scss_template(class_name))

    mark_once(touched_map, touched_files, rust_path)
    mark_once(touched_map, touched_files, scss_path)

    local page_mod = path_join(page.page_dir, "mod.rs")
    if ensure_page_components_module(page_mod) then
        mark_once(touched_map, touched_files, page_mod)
    end
    normalize_mod_layout(page_mod)
    mark_once(touched_map, touched_files, page_mod)

    local components_segments = relative_dir == "" and {} or split_path_segments(relative_dir)
    local current_components_dir = base_rust_dir
    ensure_directory(current_components_dir)

    for _, segment in ipairs(components_segments) do
        local parent_mod = path_join(current_components_dir, "mod.rs")
        if ensure_mod_declaration(parent_mod, segment, false) then
            mark_once(touched_map, touched_files, parent_mod)
        end
        normalize_mod_layout(parent_mod)
        mark_once(touched_map, touched_files, parent_mod)

        current_components_dir = path_join(current_components_dir, segment)
        ensure_directory(current_components_dir)
    end

    local components_mod = path_join(current_components_dir, "mod.rs")
    if ensure_mod_declaration(components_mod, module_name, false) then
        mark_once(touched_map, touched_files, components_mod)
    end
    if ensure_use_declaration(components_mod, module_name .. "::" .. component_name) then
        mark_once(touched_map, touched_files, components_mod)
    end
    normalize_mod_layout(components_mod)
    mark_once(touched_map, touched_files, components_mod)

    local page_style_index = path_join(PAGE_STYLES_DIR, page.relative_dir, "index.scss")
    if ensure_forward(page_style_index, "components") then
        mark_once(touched_map, touched_files, page_style_index)
    end

    local current_style_components_dir = base_style_dir
    ensure_directory(current_style_components_dir)

    for _, segment in ipairs(components_segments) do
        local parent_index = path_join(current_style_components_dir, "index.scss")
        if ensure_forward(parent_index, segment) then
            mark_once(touched_map, touched_files, parent_index)
        end

        current_style_components_dir = path_join(current_style_components_dir, segment)
        ensure_directory(current_style_components_dir)
    end

    local components_index = path_join(current_style_components_dir, "index.scss")
    if ensure_forward(components_index, suffix_kebab) then
        mark_once(touched_map, touched_files, components_index)
    end

    format_touched_files(touched_files)

    open_created_pair(rust_path, scss_path)
end

local function prompt_for_page_component_target()
    local pages = collect_pages()
    if #pages == 0 then
        vim.notify("No page components found in " .. PAGES_DIR, vim.log.levels.WARN)
        return
    end

    pickers
        .new({}, {
            prompt_title = "Select Page",
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

                    if not selection or not selection.value then
                        return
                    end

                    local page = selection.value

                    vim.ui.input({ prompt = "Component name (e.g. Workflow): " }, function(component_input)
                        if not component_input or trim(component_input) == "" then
                            return
                        end

                        vim.ui.select(
                            { "No", "Yes" },
                            { prompt = "Nest component in a sub-directory?" },
                            function(choice)
                                if not choice then
                                    return
                                end

                                if choice == "No" then
                                    create_page_component(page, component_input, "")
                                    return
                                end

                                local base_dir = path_join(page.page_dir, "components")
                                ensure_directory(base_dir)

                                local options = collect_component_subdirectories(base_dir)
                                table.insert(options, "+ Create new sub-directory")

                                vim.ui.select(options, { prompt = "Select page components sub-directory" }, function(dir)
                                    if not dir then
                                        return
                                    end

                                    if dir == "+ Create new sub-directory" then
                                        vim.ui.input(
                                            { prompt = "New sub-directory (relative to page components): " },
                                            function(new_dir)
                                                if not new_dir or trim(new_dir) == "" then
                                                    return
                                                end

                                                local normalized = normalize_relative_dir(new_dir)
                                                if normalized == "" then
                                                    vim.notify("Invalid sub-directory.", vim.log.levels.WARN)
                                                    return
                                                end

                                                create_page_component(page, component_input, normalized)
                                            end
                                        )
                                    else
                                        create_page_component(page, component_input, dir)
                                    end
                                end)
                            end
                        )
                    end)
                end)

                return true
            end,
        })
        :find()
end

local function prompt_create_page()
    vim.ui.input({ prompt = "Route: " }, function(route_value)
        if not route_value or trim(route_value) == "" then
            return
        end

        vim.ui.select({ "Private", "Public" }, { prompt = "Route visibility" }, function(visibility)
            if not visibility then
                return
            end

            vim.ui.input({ prompt = "Page name (without Page): " }, function(page_name)
                if not page_name or trim(page_name) == "" then
                    return
                end

                vim.ui.select({ "No", "Yes" }, { prompt = "Nest page in a sub-directory?" }, function(choice)
                    if not choice then
                        return
                    end

                    if choice == "No" then
                        create_page(route_value, visibility == "Private", page_name, "")
                        return
                    end

                    choose_page_subdirectory(function(subroute)
                        create_page(route_value, visibility == "Private", page_name, subroute)
                    end)
                end)
            end)
        end)
    end)
end

function M.generate()
    if not resolve_paths() then
        return
    end

    if not is_directory(PAGES_DIR) then
        vim.notify("Pages directory not found: " .. PAGES_DIR, vim.log.levels.WARN)
        return
    end

    if not is_directory(PAGE_STYLES_DIR) then
        vim.notify("Page styles directory not found: " .. PAGE_STYLES_DIR, vim.log.levels.WARN)
        return
    end

    vim.ui.select({ "Create Page", "Create Page Component" }, { prompt = "What would you like to create?" }, function(choice)
        if not choice then
            return
        end

        if choice == "Create Page" then
            prompt_create_page()
        else
            prompt_for_page_component_target()
        end
    end)
end

return M
