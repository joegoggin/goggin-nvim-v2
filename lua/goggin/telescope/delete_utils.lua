local M = {}

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function starts_with(value, prefix)
    return value:sub(1, #prefix) == prefix
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

function M.to_kebab_case(raw)
    return table.concat(split_words(raw), "-")
end

function M.path_join(...)
    local parts = {}
    for _, part in ipairs({ ... }) do
        if part and part ~= "" then
            table.insert(parts, part)
        end
    end

    return table.concat(parts, "/")
end

function M.path_relative(root, path)
    local prefix = root .. "/"
    if path:sub(1, #prefix) == prefix then
        return path:sub(#prefix + 1)
    end

    if path == root then
        return ""
    end

    return path
end

local function normalize_path(path)
    if not path or path == "" then
        return nil
    end

    local normalized = vim.fn.fnamemodify(path, ":p")
    normalized = normalized:gsub("/+$", "")
    if normalized == "" then
        return "/"
    end

    return normalized
end

function M.file_exists(path)
    return vim.uv.fs_stat(path) ~= nil
end

function M.is_directory(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == "directory"
end

function M.read_lines(path)
    if not M.file_exists(path) then
        return {}
    end

    return vim.fn.readfile(path)
end

function M.write_lines(path, lines)
    vim.fn.writefile(lines, path)
end

function M.mark_once(map, list, path)
    if not map[path] then
        map[path] = true
        table.insert(list, path)
    end
end

local function has_non_blank_lines(lines)
    for _, line in ipairs(lines) do
        if trim(line) ~= "" then
            return true
        end
    end

    return false
end

local function normalize_mod_layout(mod_path)
    local lines = M.read_lines(mod_path)
    local mod_lines = {}
    local use_lines = {}
    local other_lines = {}

    for _, line in ipairs(lines) do
        if line:match("^%s*pub%s+mod%s+") or line:match("^%s*mod%s+") then
            table.insert(mod_lines, trim(line))
        elseif line:match("^%s*pub%s+use%s+") then
            table.insert(use_lines, trim(line))
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

    M.write_lines(mod_path, normalized)
end

function M.remove_module_reference(mod_path, module_name)
    if not M.file_exists(mod_path) then
        return false
    end

    local module_pattern = vim.pesc(module_name)
    local lines = M.read_lines(mod_path)
    local updated = {}
    local changed = false

    for _, line in ipairs(lines) do
        local trimmed = trim(line)
        local is_mod_declaration =
            trimmed:match("^pub%s+mod%s+" .. module_pattern .. "%s*;$")
            or trimmed:match("^mod%s+" .. module_pattern .. "%s*;$")

        if is_mod_declaration then
            changed = true
        else
            local expression = trimmed:match("^pub%s+use%s+(.+);$")
            if expression then
                expression = trim(expression)
                if expression == module_name or starts_with(expression, module_name .. "::") then
                    changed = true
                else
                    table.insert(updated, line)
                end
            else
                table.insert(updated, line)
            end
        end
    end

    if not changed then
        return false
    end

    M.write_lines(mod_path, updated)
    normalize_mod_layout(mod_path)
    return true
end

local function remove_symbol_from_use_expression(expression, symbol)
    local prefix, body = expression:match("^(.-)::%s*{%s*(.-)%s*}$")
    if prefix and body then
        local items = {}
        for item in body:gmatch("[^,]+") do
            table.insert(items, trim(item))
        end

        local kept = {}
        local changed = false
        for _, item in ipairs(items) do
            if item ~= symbol then
                table.insert(kept, item)
            else
                changed = true
            end
        end

        if not changed then
            return expression, false
        end

        if #kept == 0 then
            return nil, true
        end

        if #kept == 1 then
            return prefix .. "::" .. kept[1], true
        end

        return prefix .. "::{" .. table.concat(kept, ", ") .. "}", true
    end

    local symbol_pattern = vim.pesc(symbol)
    if expression == symbol or expression:match("::" .. symbol_pattern .. "$") then
        return nil, true
    end

    return expression, false
end

function M.remove_use_symbol(mod_path, symbol)
    if not M.file_exists(mod_path) then
        return false
    end

    local lines = M.read_lines(mod_path)
    local updated = {}
    local changed = false

    for _, line in ipairs(lines) do
        local trimmed = trim(line)
        local expression = trimmed:match("^pub%s+use%s+(.+);$")
        if not expression then
            table.insert(updated, line)
        else
            local next_expression, did_change = remove_symbol_from_use_expression(trim(expression), symbol)
            if did_change then
                changed = true
            end

            if next_expression then
                table.insert(updated, "pub use " .. next_expression .. ";")
            end
        end
    end

    if not changed then
        return false
    end

    M.write_lines(mod_path, updated)
    normalize_mod_layout(mod_path)
    return true
end

function M.remove_use_symbol_tree(root_dir, symbol, touched_map, touched_files)
    local mod_files = vim.fn.glob(M.path_join(root_dir, "**/mod.rs"), true, true)
    local root_mod = M.path_join(root_dir, "mod.rs")
    if M.file_exists(root_mod) then
        table.insert(mod_files, root_mod)
    end

    local seen = {}
    for _, mod_path in ipairs(mod_files) do
        if not seen[mod_path] then
            seen[mod_path] = true
            if M.remove_use_symbol(mod_path, symbol) then
                M.mark_once(touched_map, touched_files, mod_path)
            end
        end
    end
end

function M.remove_forward(index_path, target)
    if not M.file_exists(index_path) then
        return false
    end

    local lines = M.read_lines(index_path)
    local updated = {}
    local changed = false

    for _, line in ipairs(lines) do
        local forward_target = line:match('^%s*@forward%s+"([^"]+)"%s*;%s*$')
        if forward_target == target then
            changed = true
        else
            table.insert(updated, line)
        end
    end

    if not changed then
        return false
    end

    M.write_lines(index_path, updated)
    return true
end

function M.delete_path(path, recursive)
    local stat = vim.uv.fs_stat(path)
    if not stat then
        return true, nil
    end

    local ok
    if stat.type == "directory" then
        local flags = recursive and "rf" or "d"
        ok = vim.fn.delete(path, flags) == 0
    else
        ok = vim.fn.delete(path) == 0
    end

    if ok then
        return true, nil
    end

    return false, "Failed to delete " .. path
end

function M.parse_component_name(file_path)
    local lines = M.read_lines(file_path)
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

local function is_route_start_line(line)
    return line:match("<%s*Route%f[%W]") ~= nil or line:match("<%s*PrivateRoute%f[%W]") ~= nil
end

local function is_group_comment_line(line)
    return line:match("^%s*//%s*.+") ~= nil
end

local function cleanup_orphan_route_group_comments(lines)
    local routes_start = nil
    local routes_end = nil

    for i, line in ipairs(lines) do
        if not routes_start and line:match("<%s*Routes%f[%W]") then
            routes_start = i
        elseif routes_start and line:match("^%s*</Routes>") then
            routes_end = i
            break
        end
    end

    if not routes_start or not routes_end or routes_end <= routes_start then
        return lines, false
    end

    local remove_indexes = {}
    local changed = false
    local i = routes_start + 1

    while i < routes_end do
        local line = lines[i]
        if is_group_comment_line(line) then
            local has_route = false
            local j = i + 1

            while j < routes_end do
                local next_line = lines[j]
                if is_group_comment_line(next_line) then
                    break
                end

                if is_route_start_line(next_line) then
                    has_route = true
                    break
                end

                j = j + 1
            end

            if not has_route then
                remove_indexes[i] = true
                changed = true

                local k = i + 1
                while k < routes_end and trim(lines[k]) == "" do
                    remove_indexes[k] = true
                    k = k + 1
                end
            end

            i = j
        else
            i = i + 1
        end
    end

    if not changed then
        return lines, false
    end

    local updated = {}
    for idx, line in ipairs(lines) do
        if not remove_indexes[idx] then
            table.insert(updated, line)
        end
    end

    return updated, true
end

local function normalize_routes_blank_lines(lines)
    local routes_start = nil
    local routes_end = nil

    for i, line in ipairs(lines) do
        if not routes_start and line:match("<%s*Routes%f[%W]") then
            routes_start = i
        elseif routes_start and line:match("^%s*</Routes>") then
            routes_end = i
            break
        end
    end

    if not routes_start or not routes_end or routes_end <= routes_start then
        return lines, false
    end

    local section = {}
    for i = routes_start + 1, routes_end - 1 do
        table.insert(section, lines[i])
    end

    while #section > 0 and trim(section[1]) == "" do
        table.remove(section, 1)
    end

    while #section > 0 and trim(section[#section]) == "" do
        table.remove(section, #section)
    end

    local compact = {}
    local previous_blank = false
    for _, line in ipairs(section) do
        local is_blank = trim(line) == ""
        if not (is_blank and previous_blank) then
            table.insert(compact, line)
        end
        previous_blank = is_blank
    end

    local updated = {}
    for i = 1, routes_start do
        table.insert(updated, lines[i])
    end

    for _, line in ipairs(compact) do
        table.insert(updated, line)
    end

    for i = routes_end, #lines do
        table.insert(updated, lines[i])
    end

    local changed = false
    if #updated ~= #lines then
        changed = true
    else
        for i = 1, #lines do
            if updated[i] ~= lines[i] then
                changed = true
                break
            end
        end
    end

    return updated, changed
end

function M.remove_route_view(app_path, view_name)
    if not M.file_exists(app_path) then
        return false
    end

    local view_pattern = "view%s*=%s*" .. vim.pesc(view_name) .. "%f[%W]"
    local lines = M.read_lines(app_path)
    local updated = {}
    local changed = false
    local i = 1

    while i <= #lines do
        local line = lines[i]
        local is_route_start = is_route_start_line(line)

        if not is_route_start then
            table.insert(updated, line)
            i = i + 1
        else
            local block = {}
            local j = i
            local has_view = false

            while j <= #lines do
                local block_line = lines[j]
                table.insert(block, block_line)

                if block_line:match(view_pattern) then
                    has_view = true
                end

                if block_line:match("/>%s*$") then
                    break
                end

                j = j + 1
            end

            if has_view then
                changed = true
            else
                for _, block_line in ipairs(block) do
                    table.insert(updated, block_line)
                end
            end

            i = j + 1
        end
    end

    if not changed then
        return false
    end

    updated, _ = cleanup_orphan_route_group_comments(updated)
    updated, _ = normalize_routes_blank_lines(updated)

    M.write_lines(app_path, updated)
    return true
end

function M.prune_empty_rust_dirs(start_dir, root_dir, touched_map, touched_files)
    local root = normalize_path(root_dir)
    local current = normalize_path(start_dir)

    while current and root and current ~= root do
        if not M.is_directory(current) then
            current = normalize_path(vim.fn.fnamemodify(current, ":h"))
        else
            local entries = vim.fn.readdir(current)
            local has_non_mod_entries = false

            for _, entry in ipairs(entries) do
                if entry ~= "mod.rs" then
                    has_non_mod_entries = true
                    break
                end
            end

            if has_non_mod_entries then
                break
            end

            local mod_path = M.path_join(current, "mod.rs")
            if M.file_exists(mod_path) then
                local mod_lines = M.read_lines(mod_path)
                if has_non_blank_lines(mod_lines) then
                    break
                end

                local removed_mod, mod_error = M.delete_path(mod_path, false)
                if not removed_mod then
                    vim.notify(mod_error, vim.log.levels.WARN)
                    break
                end

                M.mark_once(touched_map, touched_files, mod_path)
            end

            local removed_dir, dir_error = M.delete_path(current, false)
            if not removed_dir then
                vim.notify(dir_error, vim.log.levels.WARN)
                break
            end

            M.mark_once(touched_map, touched_files, current)

            local parent = normalize_path(vim.fn.fnamemodify(current, ":h"))
            if not parent or parent == current then
                break
            end

            local module_name = vim.fn.fnamemodify(current, ":t")
            local parent_mod = M.path_join(parent, "mod.rs")
            if M.remove_module_reference(parent_mod, module_name) then
                M.mark_once(touched_map, touched_files, parent_mod)
            end

            current = parent
        end
    end
end

function M.prune_empty_style_dirs(start_dir, root_dir, touched_map, touched_files)
    local root = normalize_path(root_dir)
    local current = normalize_path(start_dir)

    while current and root and current ~= root do
        if not M.is_directory(current) then
            current = normalize_path(vim.fn.fnamemodify(current, ":h"))
        else
            local entries = vim.fn.readdir(current)
            local has_non_index_entries = false

            for _, entry in ipairs(entries) do
                if entry ~= "index.scss" then
                    has_non_index_entries = true
                    break
                end
            end

            if has_non_index_entries then
                break
            end

            local index_path = M.path_join(current, "index.scss")
            if M.file_exists(index_path) then
                local index_lines = M.read_lines(index_path)
                if has_non_blank_lines(index_lines) then
                    break
                end

                local removed_index, index_error = M.delete_path(index_path, false)
                if not removed_index then
                    vim.notify(index_error, vim.log.levels.WARN)
                    break
                end

                M.mark_once(touched_map, touched_files, index_path)
            end

            local removed_dir, dir_error = M.delete_path(current, false)
            if not removed_dir then
                vim.notify(dir_error, vim.log.levels.WARN)
                break
            end

            M.mark_once(touched_map, touched_files, current)

            local parent = normalize_path(vim.fn.fnamemodify(current, ":h"))
            if not parent or parent == current then
                break
            end

            local child_name = vim.fn.fnamemodify(current, ":t")
            local parent_index = M.path_join(parent, "index.scss")
            if M.remove_forward(parent_index, child_name) then
                M.mark_once(touched_map, touched_files, parent_index)
            end

            current = parent
        end
    end
end

return M
