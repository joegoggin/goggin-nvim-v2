local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local web_paths = require("goggin.telescope.web_paths")

local M = {}

local PREVIEW_NS = vim.api.nvim_create_namespace("goggin_telescope_color_picker")
local SQUARE_WIDTH = 28
local SQUARE_HEIGHT = 12

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

local function clamp(value, min, max)
    if value < min then
        return min
    end

    if value > max then
        return max
    end

    return value
end

local function rgb_to_hex(r, g, b)
    return string.format(
        "#%02x%02x%02x",
        clamp(math.floor(r + 0.5), 0, 255),
        clamp(math.floor(g + 0.5), 0, 255),
        clamp(math.floor(b + 0.5), 0, 255)
    )
end

local function collect_numbers(value, limit)
    local numbers = {}

    for number in value:gmatch("[-+]?%d*%.?%d+") do
        table.insert(numbers, tonumber(number))

        if limit and #numbers >= limit then
            break
        end
    end

    return numbers
end

local function format_rgb(r, g, b)
    return string.format(
        "rgb(%d, %d, %d)",
        clamp(math.floor(r + 0.5), 0, 255),
        clamp(math.floor(g + 0.5), 0, 255),
        clamp(math.floor(b + 0.5), 0, 255)
    )
end

local function parse_rgb_triplet(value)
    local numbers = collect_numbers(value, 3)
    if #numbers < 3 then
        return nil
    end

    return numbers[1], numbers[2], numbers[3]
end

local function parse_hex_color(value)
    local long = value:match("^%s*(#%x%x%x%x%x%x)%x?%x?%s*$")
    if long then
        return long:lower(), long:lower()
    end

    local r, g, b = value:match("^%s*#(%x)(%x)(%x)%x?%s*$")
    if r and g and b then
        local hex = "#" .. r .. r .. g .. g .. b .. b
        return hex:lower(), hex:lower()
    end

    return nil, nil
end

local function parse_rgb_color(value)
    local inner = value:match("^%s*rgba?%s*%((.*)%)%s*$")
    if not inner or inner:match("var%s*%(") then
        return nil, nil
    end

    local r, g, b = parse_rgb_triplet(inner)
    if not r then
        return nil, nil
    end

    return rgb_to_hex(r, g, b), format_rgb(r, g, b)
end

local function hsl_to_rgb(h, s, l)
    h = (h % 360) / 360
    s = clamp(s / 100, 0, 1)
    l = clamp(l / 100, 0, 1)

    if s == 0 then
        local value = l * 255
        return value, value, value
    end

    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q

    local function hue_to_rgb(t)
        if t < 0 then
            t = t + 1
        end

        if t > 1 then
            t = t - 1
        end

        if t < 1 / 6 then
            return p + (q - p) * 6 * t
        end

        if t < 1 / 2 then
            return q
        end

        if t < 2 / 3 then
            return p + (q - p) * (2 / 3 - t) * 6
        end

        return p
    end

    return hue_to_rgb(h + 1 / 3) * 255, hue_to_rgb(h) * 255, hue_to_rgb(h - 1 / 3) * 255
end

local function parse_hsl_color(value)
    local inner = value:match("^%s*hsla?%s*%((.*)%)%s*$")
    if not inner then
        return nil, nil
    end

    local numbers = collect_numbers(inner, 3)
    if #numbers < 3 then
        return nil, nil
    end

    local r, g, b = hsl_to_rgb(numbers[1], numbers[2], numbers[3])
    return rgb_to_hex(r, g, b), format_rgb(r, g, b)
end

local function clean_scss_value(value)
    local cleaned = value:gsub("%s*!default%s*$", "")
    return trim(cleaned)
end

local function parse_default_palette(lines)
    local in_root = false

    for _, line in ipairs(lines) do
        if line:match("^%s*:root%s*{") then
            in_root = true
        end

        if in_root then
            local palette = line:match("@include%s+palette%-css%-variables%(%s*([%w_-]+)%s*%)")
            if palette then
                return palette
            end

            if line:match("^%s*}%s*$") then
                in_root = false
            end
        end
    end

    return nil
end

local function parse_palette_values(lines)
    local palettes = {}
    local in_palette_values = false
    local current_palette = nil

    for _, line in ipairs(lines) do
        if line:match("^%s*%$palette%-values%s*:") then
            in_palette_values = true
        end

        if in_palette_values then
            if current_palette then
                if line:match("^%s*%),?%s*$") then
                    current_palette = nil
                else
                    local token, triplet = line:match('^%s*([%w_-]+)%s*:%s*"([^"]+)"%s*,?%s*$')
                    if not token then
                        token, triplet = line:match("^%s*([%w_-]+)%s*:%s*([%d%s,%.]+)%s*,?%s*$")
                    end

                    if token and triplet then
                        palettes[current_palette][token] = triplet
                    end
                end
            else
                local palette = line:match("^%s*([%w_-]+)%s*:%s*%(%s*$")
                if palette then
                    current_palette = palette
                    palettes[current_palette] = palettes[current_palette] or {}
                elseif line:match("^%s*%);%s*$") then
                    in_palette_values = false
                end
            end
        end
    end

    return palettes
end

local function resolve_css_color_var(value, palettes, default_palette)
    local token = value:match("var%(%s*%-%-color%-([%w%-]+)%-rgb%s*%)")
    if not token or not default_palette then
        return nil, nil
    end

    local palette = palettes[default_palette]
    if not palette then
        return nil, nil
    end

    local triplet = palette[token]
    if not triplet then
        return nil, nil
    end

    local r, g, b = parse_rgb_triplet(triplet)
    if not r then
        return nil, nil
    end

    return rgb_to_hex(r, g, b), format_rgb(r, g, b)
end

local function analyze_color_value(value, palettes, default_palette)
    local cleaned = clean_scss_value(value)

    local hex, resolved = resolve_css_color_var(cleaned, palettes, default_palette)
    if hex then
        return {
            raw_value = cleaned,
            resolved_value = resolved,
            hex = hex,
        }
    end

    hex, resolved = parse_hex_color(cleaned)
    if hex then
        return {
            raw_value = cleaned,
            resolved_value = resolved,
            hex = hex,
        }
    end

    hex, resolved = parse_rgb_color(cleaned)
    if hex then
        return {
            raw_value = cleaned,
            resolved_value = resolved,
            hex = hex,
        }
    end

    hex, resolved = parse_hsl_color(cleaned)
    if hex then
        return {
            raw_value = cleaned,
            resolved_value = resolved,
            hex = hex,
        }
    end

    if cleaned:match("var%(%s*%-%-color%-") or cleaned:match("^%s*rgba?%s*%(") or cleaned:match("^%s*hsla?%s*%(") then
        return {
            raw_value = cleaned,
            resolved_value = nil,
            hex = nil,
        }
    end

    return nil
end

local function resolve_paths()
    local attempts = {
        { "components_dir" },
        { "pages_dir" },
        { "styles_components_dir" },
        { "page_styles_dir" },
        { "app_path" },
    }
    local last_error = nil

    for _, required in ipairs(attempts) do
        local paths, err = web_paths.resolve(required)
        if paths then
            return paths
        end

        last_error = err
    end

    vim.notify(last_error or "Could not locate web project paths.", vim.log.levels.WARN)
    return nil
end

local function add_color_file(files, seen, path)
    if file_exists(path) and not seen[path] then
        seen[path] = true
        table.insert(files, path)
    end
end

local function collect_color_files(web_root)
    local files = {}
    local seen = {}
    local roots = {
        path_join(web_root, "styles"),
        path_join(web_root, "assets", "css"),
        path_join(web_root, "src"),
    }

    add_color_file(files, seen, path_join(web_root, "_colors.scss"))

    for _, root in ipairs(roots) do
        if is_directory(root) then
            for _, path in ipairs(vim.fn.glob(path_join(root, "**", "_colors.scss"), true, true)) do
                add_color_file(files, seen, path)
            end
        end
    end

    return files
end

local function collect_colors_from_file(web_root, file_path)
    local lines = vim.fn.readfile(file_path)
    local palettes = parse_palette_values(lines)
    local default_palette = parse_default_palette(lines)
    local colors = {}

    for line_number, line in ipairs(lines) do
        local name, value = line:match("^%s*(%$[%w_-]+)%s*:%s*(.-)%s*;")
        if name and not name:match("%-rgb$") then
            local color = analyze_color_value(value, palettes, default_palette)
            if color then
                color.name = name
                color.source_path = file_path
                color.source_relative = path_relative(web_root, file_path)
                color.line_number = line_number
                color.display_value = color.resolved_value or color.raw_value

                table.insert(colors, color)
            end
        end
    end

    return colors
end

local function collect_colors(paths)
    local colors = {}
    local color_files = collect_color_files(paths.web_root)

    for _, file_path in ipairs(color_files) do
        for _, color in ipairs(collect_colors_from_file(paths.web_root, file_path)) do
            table.insert(colors, color)
        end
    end

    table.sort(colors, function(a, b)
        if a.name == b.name then
            return a.source_relative < b.source_relative
        end

        return a.name < b.name
    end)

    return colors, color_files
end

local function preview_lines(color)
    local lines = {}

    for _ = 1, SQUARE_HEIGHT do
        table.insert(lines, string.rep(" ", SQUARE_WIDTH))
    end

    table.insert(lines, "")
    table.insert(lines, "Variable: " .. color.name)
    table.insert(lines, "Value: " .. color.raw_value)

    if color.resolved_value then
        table.insert(lines, "Preview: " .. color.resolved_value)
    else
        table.insert(lines, "Preview: unresolved")
    end

    table.insert(lines, "Source: " .. color.source_relative .. ":" .. color.line_number)

    return lines
end

local function color_previewer()
    return previewers.new_buffer_previewer({
        title = "Color Preview",
        define_preview = function(self, entry)
            local color = entry.value
            local bufnr = self.state.bufnr

            vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
            vim.api.nvim_buf_clear_namespace(bufnr, PREVIEW_NS, 0, -1)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, preview_lines(color))
            vim.api.nvim_set_option_value("filetype", "scss", { buf = bufnr })

            if color.hex then
                local group = "GogginTelescopeColorPicker" .. color.hex:gsub("#", "")
                vim.api.nvim_set_hl(0, group, { bg = color.hex })

                for line = 0, SQUARE_HEIGHT - 1 do
                    vim.api.nvim_buf_add_highlight(bufnr, PREVIEW_NS, group, line, 0, SQUARE_WIDTH)
                end
            end

            vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
        end,
    })
end

local function copy_color_name(color)
    local ok = pcall(vim.fn.setreg, "+", color.name)
    if ok then
        vim.notify("Copied " .. color.name)
        return
    end

    vim.fn.setreg('"', color.name)
    vim.notify("Copied " .. color.name .. " to the unnamed register; system clipboard unavailable.", vim.log.levels.WARN)
end

function M.pick()
    local paths = resolve_paths()
    if not paths then
        return
    end

    local colors, color_files = collect_colors(paths)
    if #color_files == 0 then
        vim.notify("No _colors.scss file found under " .. paths.web_root, vim.log.levels.WARN)
        return
    end

    if #colors == 0 then
        vim.notify("No usable color variables found in _colors.scss.", vim.log.levels.WARN)
        return
    end

    pickers
        .new({}, {
            prompt_title = "SCSS Colors",
            finder = finders.new_table({
                results = colors,
                entry_maker = function(color)
                    return {
                        value = color,
                        display = color.name .. "  " .. color.display_value,
                        ordinal = color.name .. " " .. color.raw_value .. " " .. color.display_value,
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            previewer = color_previewer(),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    local selection = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)

                    if selection and selection.value then
                        copy_color_name(selection.value)
                    end
                end)

                return true
            end,
        })
        :find()
end

return M
