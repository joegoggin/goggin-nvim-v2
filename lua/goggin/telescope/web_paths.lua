local M = {}

local function is_directory(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == "directory"
end

local function file_exists(path)
    return vim.uv.fs_stat(path) ~= nil
end

local function path_join(...)
    return table.concat({ ... }, "/")
end

local function normalize_dir(path)
    if not path or path == "" then
        return nil
    end

    local normalized = vim.fn.fnamemodify(path, ":p")
    if normalized == "" then
        return nil
    end

    normalized = normalized:gsub("/+$", "")
    if normalized == "" then
        return "/"
    end

    return normalized
end

local function append_ancestors(start_dir, roots, seen)
    local current = normalize_dir(start_dir)
    while current and not seen[current] do
        seen[current] = true
        table.insert(roots, current)

        local parent = normalize_dir(vim.fn.fnamemodify(current, ":h"))
        if not parent or parent == current then
            break
        end

        current = parent
    end
end

local function collect_search_roots()
    local roots = {}
    local seen = {}

    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file ~= "" then
        append_ancestors(vim.fn.fnamemodify(current_file, ":p:h"), roots, seen)
    end

    append_ancestors(vim.fn.getcwd(), roots, seen)

    local expanded = vim.fn.expand("%:p:h")
    if expanded ~= "" then
        append_ancestors(expanded, roots, seen)
    end

    return roots
end

local function build_paths(web_root)
    return {
        web_root = web_root,
        components_dir = path_join(web_root, "src", "components"),
        styles_components_dir = path_join(web_root, "styles", "components"),
        pages_dir = path_join(web_root, "src", "pages"),
        page_styles_dir = path_join(web_root, "styles", "pages"),
        app_path = path_join(web_root, "src", "app.rs"),
    }
end

local function build_layouts(root)
    return {
        build_paths(path_join(root, "web")),
        build_paths(root),
    }
end

local function path_satisfies(paths, key)
    local value = paths[key]
    if not value then
        return false
    end

    if key == "app_path" then
        return file_exists(value)
    end

    return is_directory(value)
end

local function has_required_paths(paths, required)
    for _, key in ipairs(required) do
        if not path_satisfies(paths, key) then
            return false
        end
    end

    return true
end

local REQUIRED_LABELS = {
    components_dir = "src/components",
    styles_components_dir = "styles/components",
    pages_dir = "src/pages",
    page_styles_dir = "styles/pages",
    app_path = "src/app.rs",
}

local function describe_required(required)
    local labels = {}
    local seen = {}

    for _, key in ipairs(required) do
        local label = REQUIRED_LABELS[key] or key
        if not seen[label] then
            seen[label] = true
            table.insert(labels, label)
        end
    end

    table.sort(labels)
    return table.concat(labels, ", ")
end

function M.resolve(required)
    local required_paths = required or {}
    local search_roots = collect_search_roots()

    for _, root in ipairs(search_roots) do
        for _, paths in ipairs(build_layouts(root)) do
            if has_required_paths(paths, required_paths) then
                return paths
            end
        end
    end

    local description = describe_required(required_paths)
    if description == "" then
        description = "required project paths"
    end

    return nil,
        "Could not locate web project paths for "
            .. description
            .. ". Expected either ./web/... from the repo root or ./... from the web root."
end

return M
