local M = {}

local uv = vim.uv or vim.loop

local MAX_FILE_ITEMS = 10000
local FILE_CACHE_TTL = 30000
local SKILL_CACHE_TTL = 30000

local skill_cache = nil
local file_cache = {}
local registered = false

local function path_join(...)
    local result = table.concat({ ... }, "/")
    result = result:gsub("/+", "/")
    return result
end

local function strip_trailing_slash(path)
    if not path or path == "" then
        return nil
    end

    path = path:gsub("/+$", "")
    if path == "" then
        return "/"
    end

    return path
end

local function expand_path(path)
    if not path or path == "" or path == vim.NIL then
        return nil
    end

    return strip_trailing_slash(vim.fn.expand(path))
end

local function real_path(path)
    path = expand_path(path)
    if not path then
        return nil
    end

    return strip_trailing_slash(uv.fs_realpath(path) or vim.fn.fnamemodify(path, ":p"))
end

local function path_is_inside(path, root)
    path = real_path(path)
    root = real_path(root)

    if not path or not root then
        return false
    end

    return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function is_file(path)
    local stat = path and uv.fs_stat(path)
    return stat and stat.type == "file"
end

local function is_directory(path)
    local stat = path and uv.fs_stat(path)
    return stat and stat.type == "directory"
end

local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end

    local content = file:read("*a")
    file:close()
    return content
end

local function trim(value)
    return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function unquote(value)
    value = trim(value)
    local first = value:sub(1, 1)
    local last = value:sub(-1)

    if #value >= 2 and ((first == '"' and last == '"') or (first == "'" and last == "'")) then
        return value:sub(2, -2)
    end

    return value
end

local function parse_frontmatter(content)
    local metadata = {}

    if not content or content:sub(1, 3) ~= "---" then
        return metadata
    end

    local lines = vim.split(content, "\n", { plain = true })
    local index = 2

    while index <= #lines do
        local line = lines[index]
        if line:match("^%-%-%-%s*$") then
            break
        end

        local key, value = line:match("^([%w_-]+):%s*(.-)%s*$")
        if not key then
            index = index + 1
        elseif value == ">" or value == "|" then
            local block = {}
            index = index + 1

            while index <= #lines do
                local block_line = lines[index]
                if block_line:match("^%-%-%-%s*$") or block_line:match("^%S[%w_-]*:%s*") then
                    break
                end

                local text = trim(block_line)
                if text ~= "" then
                    table.insert(block, text)
                end

                index = index + 1
            end

            metadata[key] = table.concat(block, " ")
        else
            metadata[key] = unquote(value)
            index = index + 1
        end
    end

    return metadata
end

local function skill_name_from_path(skill_path)
    return vim.fn.fnamemodify(vim.fn.fnamemodify(skill_path, ":h"), ":t")
end

local function collect_skill_files(root, max_depth)
    local files = {}
    local seen_dirs = {}

    local function scan(dir, depth)
        if depth > max_depth or not is_directory(dir) then
            return
        end

        local real = real_path(dir) or dir
        if seen_dirs[real] then
            return
        end
        seen_dirs[real] = true

        local skill_path = path_join(dir, "SKILL.md")
        if is_file(skill_path) then
            table.insert(files, skill_path)
        end

        local handle = uv.fs_scandir(dir)
        if not handle then
            return
        end

        while true do
            local name = uv.fs_scandir_next(handle)
            if not name then
                break
            end

            if name ~= ".git" and name ~= ".codex-plugin" then
                local child = path_join(dir, name)
                if is_directory(child) then
                    scan(child, depth + 1)
                end
            end
        end
    end

    scan(root, 0)
    return files
end

local function collect_plugin_manifests(root)
    local manifests = {}
    local seen_dirs = {}

    local function scan(dir, depth)
        if depth > 8 or not is_directory(dir) then
            return
        end

        local real = real_path(dir) or dir
        if seen_dirs[real] then
            return
        end
        seen_dirs[real] = true

        local manifest_path = path_join(dir, ".codex-plugin", "plugin.json")
        if is_file(manifest_path) then
            table.insert(manifests, manifest_path)
        end

        local handle = uv.fs_scandir(dir)
        if not handle then
            return
        end

        while true do
            local name = uv.fs_scandir_next(handle)
            if not name then
                break
            end

            if name ~= ".git" and name ~= ".codex-plugin" then
                local child = path_join(dir, name)
                if is_directory(child) then
                    scan(child, depth + 1)
                end
            end
        end
    end

    scan(root, 0)
    return manifests
end

local function make_skill(skill_path, prefix)
    local metadata = parse_frontmatter(read_file(skill_path))
    local name = metadata.name or skill_name_from_path(skill_path)

    if not name or name == "" then
        return nil
    end

    if prefix and prefix ~= "" then
        name = prefix .. ":" .. name
    end

    return {
        name = name,
        description = metadata.description or "",
        path = skill_path,
    }
end

local function append_skill(items, seen, skill_path, prefix)
    local skill = make_skill(skill_path, prefix)
    if not skill or seen[skill.name] then
        return
    end

    seen[skill.name] = true
    table.insert(items, skill)
end

local function plugin_skills_dir(plugin_root, skills_value)
    skills_value = skills_value or "skills"
    if skills_value:sub(1, 1) == "/" then
        return skills_value
    end

    skills_value = skills_value:gsub("^%./", "")
    return path_join(plugin_root, skills_value)
end

local function collect_skills()
    local now = uv.now()
    if skill_cache and now - skill_cache.time < SKILL_CACHE_TTL then
        return skill_cache.items
    end

    local items = {}
    local seen = {}
    local direct_roots = {
        expand_path("~/.codex/skills"),
        expand_path("~/.agents/skills"),
    }

    for _, root in ipairs(direct_roots) do
        for _, skill_path in ipairs(collect_skill_files(root, 6)) do
            append_skill(items, seen, skill_path)
        end
    end

    local plugin_root = expand_path("~/.codex/plugins/cache")
    for _, manifest_path in ipairs(collect_plugin_manifests(plugin_root)) do
        local ok, manifest = pcall(vim.json.decode, read_file(manifest_path) or "")
        if ok and type(manifest) == "table" and manifest.name then
            local root = vim.fn.fnamemodify(manifest_path, ":h:h")
            local skills_dir = plugin_skills_dir(root, manifest.skills)

            for _, skill_path in ipairs(collect_skill_files(skills_dir, 4)) do
                append_skill(items, seen, skill_path, manifest.name)
            end
        end
    end

    table.sort(items, function(left, right)
        return left.name < right.name
    end)

    skill_cache = {
        time = now,
        items = items,
    }

    return items
end

local function markdown_buffer(bufnr)
    local filetype = vim.bo[bufnr].filetype
    local name = vim.api.nvim_buf_get_name(bufnr)

    return filetype == "markdown" or name:match("%.md$")
end

local function temp_dirs()
    local dirs = {}
    local seen = {}

    local function add(path)
        path = expand_path(path)
        if path and not seen[path] then
            seen[path] = true
            table.insert(dirs, path)
        end
    end

    add(vim.env.TMPDIR)
    add(uv.os_tmpdir())
    add("/tmp")
    add("/var/tmp")
    add("/usr/tmp")

    return dirs
end

function M.is_codex_prompt_buffer(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" or not name:match("%.md$") or not markdown_buffer(bufnr) then
        return false
    end

    for _, dir in ipairs(temp_dirs()) do
        if path_is_inside(name, dir) then
            return true
        end
    end

    return false
end

local function skill_documentation(skill)
    if skill.description == "" then
        return skill.path
    end

    return skill.description .. "\n\n" .. skill.path
end

local SkillSource = {}
SkillSource.__index = SkillSource

function SkillSource.new(cmp)
    return setmetatable({ cmp = cmp }, SkillSource)
end

function SkillSource:is_available()
    return M.is_codex_prompt_buffer(0)
end

function SkillSource:get_debug_name()
    return "codex_skills"
end

function SkillSource:get_trigger_characters()
    return { "$" }
end

function SkillSource:get_keyword_pattern()
    return [[\$[0-9A-Za-z:_-]*]]
end

function SkillSource:complete(params, callback)
    local fragment = params.context.cursor_before_line:sub(params.offset)
    if fragment:sub(1, 1) ~= "$" then
        callback({})
        return
    end

    local items = {}
    for _, skill in ipairs(collect_skills()) do
        local label = "$" .. skill.name
        table.insert(items, {
            label = label,
            insertText = label,
            filterText = label .. " " .. skill.description,
            kind = self.cmp.lsp.CompletionItemKind.Keyword,
            detail = "Codex skill",
            documentation = {
                kind = self.cmp.lsp.MarkupKind.Markdown,
                value = skill_documentation(skill),
            },
        })
    end

    callback(items)
end

local function split_lines(value)
    local lines = {}

    for line in (value or ""):gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    return lines
end

local function file_documentation(cwd, path)
    return path_join(cwd, path)
end

local function make_file_items(cmp, cwd, paths)
    local items = {}

    for _, path in ipairs(paths) do
        if path ~= "" then
            local label = "@" .. path
            table.insert(items, {
                label = label,
                insertText = label,
                filterText = label,
                kind = cmp.lsp.CompletionItemKind.File,
                detail = "Codex file",
                documentation = {
                    kind = cmp.lsp.MarkupKind.Markdown,
                    value = file_documentation(cwd, path),
                },
            })
        end
    end

    return items
end

local function collect_files_fallback(cwd)
    local paths = {}
    local seen_dirs = {}

    local function scan(dir, relative_dir)
        if #paths >= MAX_FILE_ITEMS then
            return
        end

        local real = real_path(dir) or dir
        if seen_dirs[real] then
            return
        end
        seen_dirs[real] = true

        local handle = uv.fs_scandir(dir)
        if not handle then
            return
        end

        while #paths < MAX_FILE_ITEMS do
            local name = uv.fs_scandir_next(handle)
            if not name then
                break
            end

            if name ~= ".git" then
                local full_path = path_join(dir, name)
                local relative_path = relative_dir == "" and name or path_join(relative_dir, name)
                local stat = uv.fs_stat(full_path)

                if stat and stat.type == "directory" then
                    scan(full_path, relative_path)
                elseif stat and stat.type == "file" then
                    table.insert(paths, relative_path)
                end
            end
        end
    end

    scan(cwd, "")
    table.sort(paths)
    return paths
end

local function finish_file_callbacks(cache_entry, items)
    cache_entry.items = items
    cache_entry.time = uv.now()

    local pending = cache_entry.pending or {}
    cache_entry.pending = nil

    for _, callback in ipairs(pending) do
        callback(items)
    end
end

local function collect_file_items(cmp, cwd, callback)
    local now = uv.now()
    local cache_entry = file_cache[cwd]

    if cache_entry and cache_entry.items and now - cache_entry.time < FILE_CACHE_TTL then
        callback(cache_entry.items)
        return
    end

    if cache_entry and cache_entry.pending then
        table.insert(cache_entry.pending, callback)
        return
    end

    cache_entry = { pending = { callback } }
    file_cache[cwd] = cache_entry

    if vim.fn.executable("rg") == 1 and vim.system then
        vim.system({ "rg", "--files", "--hidden", "--glob", "!.git/*" }, { cwd = cwd, text = true }, function(result)
            vim.schedule(function()
                local paths = {}

                if result.code == 0 then
                    paths = split_lines(result.stdout)
                    if #paths > MAX_FILE_ITEMS then
                        paths = vim.list_slice(paths, 1, MAX_FILE_ITEMS)
                    end
                end

                finish_file_callbacks(cache_entry, make_file_items(cmp, cwd, paths))
            end)
        end)
        return
    end

    finish_file_callbacks(cache_entry, make_file_items(cmp, cwd, collect_files_fallback(cwd)))
end

local FileSource = {}
FileSource.__index = FileSource

function FileSource.new(cmp)
    return setmetatable({ cmp = cmp }, FileSource)
end

function FileSource:is_available()
    return M.is_codex_prompt_buffer(0)
end

function FileSource:get_debug_name()
    return "codex_files"
end

function FileSource:get_trigger_characters()
    return { "@" }
end

function FileSource:get_keyword_pattern()
    return [=[@[^[:space:]]*]=]
end

function FileSource:complete(params, callback)
    local fragment = params.context.cursor_before_line:sub(params.offset)
    if fragment:sub(1, 1) ~= "@" then
        callback({})
        return
    end

    collect_file_items(self.cmp, vim.fn.getcwd(), callback)
end

function M.setup(cmp)
    if registered then
        return
    end

    cmp.register_source("codex_skills", SkillSource.new(cmp))
    cmp.register_source("codex_files", FileSource.new(cmp))

    registered = true
end

return M
