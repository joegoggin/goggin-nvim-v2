local M = {}

local WEB_ROOT = "/home/joegoggin/Projects/gig-log/web"
local COMPONENTS_DIR = WEB_ROOT .. "/src/components"
local STYLES_DIR = WEB_ROOT .. "/styles/components"

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

local function append_unique_line(path, line)
    local lines = read_lines(path)
    if has_line(lines, line) then
        return false
    end

    table.insert(lines, line)
    write_lines(path, lines)

    return true
end

local function normalize_mod_layout(mod_path)
    local lines = read_lines(mod_path)
    local mod_lines = {}
    local use_lines = {}
    local other_lines = {}

    for _, line in ipairs(lines) do
        if line:match("^pub mod ") then
            table.insert(mod_lines, line)
        elseif line:match("^pub use ") then
            table.insert(use_lines, line)
        elseif line:match("^%s*$") then
            -- skip existing blank lines; rebuilt below
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

local function ensure_mod_declaration(mod_path, module_name)
    ensure_file(mod_path)

    local lines = read_lines(mod_path)
    local declaration = "pub mod " .. module_name .. ";"
    if has_line(lines, declaration) then
        return false
    end

    local last_mod_index = nil
    local first_use_index = nil
    for i, line in ipairs(lines) do
        if line:match("^pub mod ") then
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

local function ensure_forward(index_path, target)
    ensure_file(index_path)
    return append_unique_line(index_path, string.format('@forward "%s";', target))
end

local function collect_component_subdirectories()
    local directories = vim.fn.glob(COMPONENTS_DIR .. "/**/", true, true)
    local seen = {}
    local results = {}

    for _, directory in ipairs(directories) do
        if directory ~= COMPONENTS_DIR .. "/" then
            local cleaned = directory:gsub("/$", "")
            local relative = cleaned:sub(#COMPONENTS_DIR + 2)

            if relative ~= "" and not seen[relative] then
                seen[relative] = true
                table.insert(results, relative)
            end
        end
    end

    table.sort(results)
    return results
end

local function build_rust_template(component_name, module_name, class_name)
    return {
        "use leptos::prelude::*;",
        "",
        "use crate::utils::class_name::ClassNameUtil;",
        "",
        "#[component]",
        string.format(
            "pub fn %s(#[prop(optional, into)] class: Option<String>) -> impl IntoView {",
            component_name
        ),
        "    // Classes",
        string.format('    let class_name = ClassNameUtil::new("%s", class);', class_name),
        string.format("    let %s = class_name.get_root_class();", module_name),
        "",
        "    view! {",
        string.format("        <div class=%s></div>", module_name),
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

local function create_component_files(opts)
    local component_name = to_pascal_case(opts.input_name)
    local module_name = to_snake_case(opts.input_name)
    local class_name = to_kebab_case(opts.input_name)

    if component_name == "" or module_name == "" or class_name == "" then
        vim.notify("Invalid component name.", vim.log.levels.WARN)
        return
    end

    if component_name:match("^%d") then
        vim.notify("Component name cannot start with a number.", vim.log.levels.WARN)
        return
    end

    local relative_dir = opts.relative_dir
    local rust_dir = COMPONENTS_DIR
    local styles_dir = STYLES_DIR

    if relative_dir ~= "" then
        rust_dir = path_join(rust_dir, relative_dir)
        styles_dir = path_join(styles_dir, relative_dir)
    end

    ensure_directory(rust_dir)
    ensure_directory(styles_dir)

    local rust_path = path_join(rust_dir, module_name .. ".rs")
    local scss_path = path_join(styles_dir, "_" .. class_name .. ".scss")

    if file_exists(rust_path) then
        vim.notify("Rust component already exists: " .. rust_path, vim.log.levels.WARN)
        return
    end

    if file_exists(scss_path) then
        vim.notify("SCSS component already exists: " .. scss_path, vim.log.levels.WARN)
        return
    end

    write_lines(rust_path, build_rust_template(component_name, module_name, class_name))
    write_lines(scss_path, build_scss_template(class_name))

    local touched_map = {}
    local touched_files = {}

    local function mark_touched(path)
        if not touched_map[path] then
            touched_map[path] = true
            table.insert(touched_files, path)
        end
    end

    mark_touched(rust_path)
    mark_touched(scss_path)

    local rust_segments = relative_dir == "" and {} or split_path_segments(relative_dir)
    local current_rust_dir = COMPONENTS_DIR

    for index, segment in ipairs(rust_segments) do
        local parent_mod = path_join(current_rust_dir, "mod.rs")
        if ensure_mod_declaration(parent_mod, segment) then
            mark_touched(parent_mod)
        end

        if index == 1 then
            local root_mod = path_join(COMPONENTS_DIR, "mod.rs")
            if ensure_use_declaration(root_mod, segment .. "::*") then
                mark_touched(root_mod)
            end
        end

        current_rust_dir = path_join(current_rust_dir, segment)
        ensure_directory(current_rust_dir)
        ensure_file(path_join(current_rust_dir, "mod.rs"))
    end

    local target_mod = path_join(current_rust_dir, "mod.rs")
    if ensure_mod_declaration(target_mod, module_name) then
        mark_touched(target_mod)
    end
    if ensure_use_declaration(target_mod, module_name .. "::" .. component_name) then
        mark_touched(target_mod)
    end

    normalize_mod_layout(target_mod)
    mark_touched(target_mod)

    if #rust_segments > 0 then
        local root_mod = path_join(COMPONENTS_DIR, "mod.rs")
        normalize_mod_layout(root_mod)
        mark_touched(root_mod)
    end

    local style_segments = rust_segments
    local current_style_dir = STYLES_DIR

    for _, segment in ipairs(style_segments) do
        ensure_directory(current_style_dir)
        local parent_index = path_join(current_style_dir, "index.scss")
        if ensure_forward(parent_index, segment) then
            mark_touched(parent_index)
        end

        current_style_dir = path_join(current_style_dir, segment)
        ensure_directory(current_style_dir)
    end

    local target_index = path_join(current_style_dir, "index.scss")
    if ensure_forward(target_index, class_name) then
        mark_touched(target_index)
    end

    format_touched_files(touched_files)

    vim.notify("Created component " .. component_name)
    vim.notify(table.concat(touched_files, "\n"), vim.log.levels.INFO)
end

local function choose_subdirectory(input_name)
    local directories = collect_component_subdirectories()
    local options = {}

    for _, directory in ipairs(directories) do
        table.insert(options, directory)
    end

    table.insert(options, "+ Create new sub-directory")

    vim.ui.select(options, { prompt = "Select components sub-directory" }, function(choice)
        if not choice then
            return
        end

        if choice == "+ Create new sub-directory" then
            vim.ui.input({ prompt = "New sub-directory (relative to components): " }, function(new_path)
                if not new_path or trim(new_path) == "" then
                    return
                end

                local normalized = normalize_relative_dir(new_path)
                if normalized == "" then
                    vim.notify("Invalid sub-directory path.", vim.log.levels.WARN)
                    return
                end

                create_component_files({
                    input_name = input_name,
                    relative_dir = normalized,
                })
            end)
        else
            create_component_files({
                input_name = input_name,
                relative_dir = choice,
            })
        end
    end)
end

function M.generate()
    if not is_directory(COMPONENTS_DIR) then
        vim.notify("Components directory not found: " .. COMPONENTS_DIR, vim.log.levels.WARN)
        return
    end

    if not is_directory(STYLES_DIR) then
        vim.notify("Component styles directory not found: " .. STYLES_DIR, vim.log.levels.WARN)
        return
    end

    vim.ui.input({ prompt = "Component name: " }, function(input_name)
        if not input_name or trim(input_name) == "" then
            return
        end

        vim.ui.select({ "No", "Yes" }, { prompt = "Nest component in a sub-directory?" }, function(choice)
            if not choice then
                return
            end

            if choice == "Yes" then
                choose_subdirectory(input_name)
            else
                create_component_files({
                    input_name = input_name,
                    relative_dir = "",
                })
            end
        end)
    end)
end

return M
