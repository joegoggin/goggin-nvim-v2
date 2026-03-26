local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values

local M = {}

local WEB_ROOT = "/home/joegoggin/Projects/gig-log/web"
local PAGES_DIR = WEB_ROOT .. "/src/pages"
local PAGE_STYLES_DIR = WEB_ROOT .. "/styles/pages"
local APP_PATH = WEB_ROOT .. "/src/app.rs"

local function file_exists(path)
    return vim.uv.fs_stat(path) ~= nil
end

local function is_directory(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == "directory"
end

local function path_join(...)
    return table.concat({ ... }, "/")
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

local function run_command(command, args)
    local cmd = { command }
    vim.list_extend(cmd, args)

    if vim.system then
        local result = vim.system(cmd, { text = true }):wait()
        if result.code == 0 then
            return true, nil
        end

        local output = result.stderr
        if not output or output == "" then
            output = result.stdout
        end

        return false, output or ""
    end

    local escaped = {}
    for _, part in ipairs(cmd) do
        table.insert(escaped, vim.fn.shellescape(part))
    end

    local output = vim.fn.system(table.concat(escaped, " "))
    if vim.v.shell_error == 0 then
        return true, nil
    end

    return false, output
end

local function format_touched_files(touched_files)
    local rust_files = {}
    local scss_files = {}

    for _, path in ipairs(touched_files) do
        if path:match("%.rs$") then
            table.insert(rust_files, path)
        elseif path:match("%.scss$") then
            table.insert(scss_files, path)
        end
    end

    if #rust_files > 0 then
        if vim.fn.executable("rustfmt") == 1 then
            local ok, output = run_command("rustfmt", rust_files)
            if not ok then
                vim.notify("rustfmt failed:\n" .. output, vim.log.levels.WARN)
            end
        else
            vim.notify("rustfmt not found in PATH; skipping Rust formatting.", vim.log.levels.WARN)
        end
    end

    if #scss_files > 0 then
        if vim.fn.executable("prettier") == 1 then
            local args = { "--write", "--parser", "scss" }
            vim.list_extend(args, scss_files)
            local ok, output = run_command("prettier", args)
            if not ok then
                vim.notify("prettier failed:\n" .. output, vim.log.levels.WARN)
            end
        else
            vim.notify("prettier not found in PATH; skipping SCSS formatting.", vim.log.levels.WARN)
        end
    end
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

local function collect_pages()
    local page_files = vim.fn.glob(PAGES_DIR .. "/**/page.rs", true, true)
    local pages = {}

    for _, page_rs in ipairs(page_files) do
        local component_name = parse_component_name(page_rs)
        if component_name then
            local page_dir = vim.fn.fnamemodify(page_rs, ":h")
            local relative_dir = page_dir:sub(#PAGES_DIR + 2)

            table.insert(pages, {
                page_rs = page_rs,
                page_dir = page_dir,
                relative_dir = relative_dir,
                page_component_name = component_name,
                display_name = component_name:gsub("Page$", ""),
            })
        end
    end

    table.sort(pages, function(a, b)
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

local function build_page_component_name(input_name, path_segments)
    local base = to_pascal_case(input_name)
    base = base:gsub("Page$", "")

    if base == "" then
        return nil
    end

    local suffix_parts = {}
    if #path_segments > 0 then
        for _, segment in ipairs(path_segments) do
            local cleaned = segment:gsub("^:", "")
            local pascal = to_pascal_case(cleaned)
            if pascal ~= "" then
                table.insert(suffix_parts, pascal)
            end
        end
    end

    local suffix = ""
    if #suffix_parts > 0 then
        suffix = table.concat(suffix_parts, "")
    end

    if suffix ~= "" and suffix:sub(1, #base) == base then
        suffix = suffix:sub(#base + 1)
    end

    return base .. suffix .. "Page"
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

    local component_name = build_page_component_name(page_name_input, parsed.path_segments)
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

    local leaf_dir = PAGES_DIR
    local style_leaf_dir = PAGE_STYLES_DIR
    for _, segment in ipairs(parsed.fs_segments) do
        leaf_dir = path_join(leaf_dir, segment)
        style_leaf_dir = path_join(style_leaf_dir, segment)
    end

    ensure_directory(leaf_dir)
    ensure_directory(style_leaf_dir)

    local rust_path = path_join(leaf_dir, "page.rs")
    local scss_path = path_join(style_leaf_dir, "_page.scss")

    if file_exists(rust_path) then
        vim.notify("Page already exists: " .. rust_path, vim.log.levels.WARN)
        return
    end

    if file_exists(scss_path) then
        vim.notify("Page style already exists: " .. scss_path, vim.log.levels.WARN)
        return
    end

    write_lines(rust_path, build_page_rust_template(component_name, class_name))
    write_lines(scss_path, build_scss_template(class_name))

    local touched_map = {}
    local touched_files = {}
    mark_once(touched_map, touched_files, rust_path)
    mark_once(touched_map, touched_files, scss_path)

    local current_pages_dir = PAGES_DIR
    for _, segment in ipairs(parsed.fs_segments) do
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

    local leaf_mod = path_join(current_pages_dir, "mod.rs")
    if ensure_mod_declaration(leaf_mod, "page", false) then
        mark_once(touched_map, touched_files, leaf_mod)
    end
    if ensure_use_declaration(leaf_mod, "page::" .. component_name) then
        mark_once(touched_map, touched_files, leaf_mod)
    end
    normalize_mod_layout(leaf_mod)
    mark_once(touched_map, touched_files, leaf_mod)

    local root_use = table.concat(parsed.fs_segments, "::") .. "::" .. component_name

    local pages_root_mod = path_join(PAGES_DIR, "mod.rs")
    if ensure_use_declaration(pages_root_mod, root_use) then
        mark_once(touched_map, touched_files, pages_root_mod)
    end
    normalize_mod_layout(pages_root_mod)
    mark_once(touched_map, touched_files, pages_root_mod)

    local current_style_dir = PAGE_STYLES_DIR
    for _, segment in ipairs(parsed.fs_segments) do
        local parent_index = path_join(current_style_dir, "index.scss")
        if ensure_forward(parent_index, segment) then
            mark_once(touched_map, touched_files, parent_index)
        end

        current_style_dir = path_join(current_style_dir, segment)
        ensure_directory(current_style_dir)
    end

    local leaf_index = path_join(current_style_dir, "index.scss")
    if ensure_forward(leaf_index, "page") then
        mark_once(touched_map, touched_files, leaf_index)
    end

    if insert_route_into_app(parsed.route_path, component_name, is_private) then
        mark_once(touched_map, touched_files, APP_PATH)
    end

    format_touched_files(touched_files)

    vim.notify("Created page " .. component_name)
    vim.notify(table.concat(touched_files, "\n"), vim.log.levels.INFO)
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

local function create_page_component(page, input_name, relative_dir)
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

    ensure_directory(rust_dir)
    ensure_directory(style_dir)

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

    write_lines(rust_path, build_page_component_template(component_name, class_name, module_name))
    write_lines(scss_path, build_scss_template(class_name))

    local touched_map = {}
    local touched_files = {}
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

    vim.notify("Created page component " .. component_name)
    vim.notify(table.concat(touched_files, "\n"), vim.log.levels.INFO)
end

local function prompt_for_page_component_target()
    local pages = collect_pages()
    if #pages == 0 then
        vim.notify("No pages with page.rs found in " .. PAGES_DIR, vim.log.levels.WARN)
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
                        display = page.display_name .. "  " .. page.relative_dir,
                        ordinal = page.display_name .. " " .. page.relative_dir,
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

                vim.ui.input({ prompt = "Sub route (optional): " }, function(subroute)
                    create_page(route_value, visibility == "Private", page_name, subroute or "")
                end)
            end)
        end)
    end)
end

function M.generate()
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
