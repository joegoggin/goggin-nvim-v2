local M = {}

M._colors = nil
M._theme_name = nil

local home = os.getenv("HOME")
local theme_dir = home .. "/.config/omarchy/current/theme"

-- Simple TOML parser: handles [section.subsection] headers and key = "value" lines
local function parse_toml(content)
    local result = {}
    local current = result

    for line in content:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line == "" or line:sub(1, 1) == "#" then
            goto continue
        end

        local section = line:match("^%[([^%]]+)%]$")
        if section then
            current = result
            for part in section:gmatch("[^%.]+") do
                part = part:match("^%s*(.-)%s*$")
                if not current[part] then
                    current[part] = {}
                end
                current = current[part]
            end
            goto continue
        end

        local key, value = line:match('^([%w_]+)%s*=%s*"([^"]*)"')
        if key and value then
            current[key] = value
        end

        ::continue::
    end

    return result
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local content = f:read("*a")
    f:close()
    return content
end

local function hex_to_rgb(hex)
    hex = hex:gsub("#", "")
    return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

local function rgb_to_hex(r, g, b)
    return string.format(
        "#%02x%02x%02x",
        math.max(0, math.min(255, math.floor(r))),
        math.max(0, math.min(255, math.floor(g))),
        math.max(0, math.min(255, math.floor(b)))
    )
end

local function lighten(hex, amount)
    local r, g, b = hex_to_rgb(hex)
    return rgb_to_hex(r + amount, g + amount, b + amount)
end

local function get_theme_name()
    local content = read_file(home .. "/.config/omarchy/current/theme.name")
    if content then
        return content:match("^%s*(.-)%s*$")
    end
    return nil
end

local function load_from_colors_toml()
    local content = read_file(theme_dir .. "/colors.toml")
    if not content then
        return nil
    end

    local data = parse_toml(content)
    if not data.background then
        return nil
    end

    local ansi_names = { "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white" }
    local colors = {
        bg = data.background,
        fg = data.foreground,
        cursor = data.cursor or data.foreground,
        cursor_text = data.cursor_text or data.background,
        selection = data.selection_background or lighten(data.background, 20),
        selected_text = data.selection_foreground or data.foreground,
        accent = data.accent or data["color4"] or data.foreground,
        link = data.accent or data["color4"] or data.foreground,
        comment = data["color8"] or lighten(data.background, 40),
    }

    for i, name in ipairs(ansi_names) do
        colors[name] = data["color" .. (i - 1)] or data.background
        colors["bright_" .. name] = data["color" .. (i + 7)] or colors[name]
    end

    return colors
end

local function load_from_alacritty_toml()
    local content = read_file(theme_dir .. "/alacritty.toml")
    if not content then
        return nil
    end

    local data = parse_toml(content)
    local c = data.colors
    if not c or not c.primary then
        return nil
    end

    local bg = c.primary.background or "#1a1b26"
    local fg = c.primary.foreground or "#a9b1d6"

    local colors = {
        bg = bg,
        fg = fg,
        cursor = (c.cursor and c.cursor.cursor) or fg,
        cursor_text = (c.cursor and c.cursor.text) or bg,
        selection = lighten(bg, 20),
        selected_text = (c.bright and c.bright.green) or fg,
        accent = (c.normal and c.normal.blue) or fg,
        link = (c.normal and c.normal.blue) or fg,
        comment = (c.bright and c.bright.black) or lighten(bg, 40),
    }

    local ansi_names = { "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white" }
    for _, name in ipairs(ansi_names) do
        colors[name] = (c.normal and c.normal[name]) or fg
        colors["bright_" .. name] = (c.bright and c.bright[name]) or colors[name]
    end

    return colors
end

local default_colors = {
    bg = "#0f191c",
    fg = "#426644",
    black = "#0f191c",
    red = "#E83151",
    green = "#82d967",
    yellow = "#ffd700",
    blue = "#227358",
    magenta = "#663F46",
    cyan = "#50b45a",
    white = "#97ABB1",
    bright_black = "#688060",
    bright_red = "#E83151",
    bright_green = "#90d762",
    bright_yellow = "#faff00",
    bright_blue = "#227358",
    bright_magenta = "#663F46",
    bright_cyan = "#2fc079",
    bright_white = "#97ABB1",
    cursor = "#383838",
    cursor_text = "#00ff00",
    selection = "#18281e",
    selected_text = "#00ff87",
    link = "#2fc079",
    comment = "#304f59",
    accent = "#227358",
}

local function load_colors()
    return load_from_colors_toml() or load_from_alacritty_toml() or default_colors
end

local function apply_highlights(colors)
    vim.cmd("highlight clear")
    if vim.fn.exists("syntax_on") == 1 then
        vim.cmd("syntax reset")
    end

    vim.g.colors_name = "omarchy"

    local set = vim.api.nvim_set_hl

    -- Editor highlights
    set(0, "Normal", { fg = colors.fg, bg = "None" })
    set(0, "NormalFloat", { fg = colors.fg, bg = colors.bg })
    set(0, "Cursor", { fg = colors.cursor_text, bg = colors.cursor })
    set(0, "CursorLine", { bg = "None" })
    set(0, "CursorColumn", { bg = colors.bright_black })
    set(0, "ColorColumn", { bg = colors.bright_black })
    set(0, "LineNr", { fg = colors.white })
    set(0, "CursorLineNr", { fg = colors.yellow, bold = true })
    set(0, "Visual", { fg = colors.selected_text, bg = colors.selection })
    set(0, "VisualNOS", { fg = colors.selected_text, bg = colors.selection })
    set(0, "Search", { fg = colors.black, bg = colors.yellow })
    set(0, "IncSearch", { fg = colors.black, bg = colors.bright_yellow })

    -- Syntax highlighting
    set(0, "Comment", { fg = colors.comment, italic = true })
    set(0, "Constant", { fg = colors.red })
    set(0, "String", { fg = colors.green })
    set(0, "Character", { fg = colors.green })
    set(0, "Number", { fg = colors.red })
    set(0, "Boolean", { fg = colors.red })
    set(0, "Float", { fg = colors.red })
    set(0, "Identifier", { fg = colors.cyan })
    set(0, "Function", { fg = colors.blue })
    set(0, "Statement", { fg = colors.magenta })
    set(0, "Conditional", { fg = colors.magenta })
    set(0, "Repeat", { fg = colors.magenta })
    set(0, "Label", { fg = colors.magenta })
    set(0, "Operator", { fg = colors.bright_red })
    set(0, "Keyword", { fg = colors.magenta })
    set(0, "Exception", { fg = colors.magenta })
    set(0, "PreProc", { fg = colors.yellow })
    set(0, "Include", { fg = colors.yellow })
    set(0, "Define", { fg = colors.yellow })
    set(0, "Macro", { fg = colors.yellow })
    set(0, "PreCondit", { fg = colors.yellow })
    set(0, "Type", { fg = colors.blue })
    set(0, "StorageClass", { fg = colors.blue })
    set(0, "Structure", { fg = colors.blue })
    set(0, "Typedef", { fg = colors.blue })
    set(0, "Special", { fg = colors.bright_cyan })
    set(0, "SpecialChar", { fg = colors.bright_cyan })
    set(0, "Tag", { fg = colors.bright_cyan })
    set(0, "Delimiter", { fg = colors.fg })
    set(0, "SpecialComment", { fg = colors.bright_cyan })
    set(0, "Debug", { fg = colors.bright_cyan })
    set(0, "Underlined", { fg = colors.link, underline = true })
    set(0, "Error", { fg = colors.bright_red, bg = colors.bg })
    set(0, "Todo", { fg = colors.bright_yellow, bg = colors.bg, bold = true })

    -- UI elements
    set(0, "Pmenu", { fg = colors.fg, bg = colors.bg })
    set(0, "PmenuSel", { fg = colors.selected_text, bg = colors.selection })
    set(0, "PmenuSbar", { bg = colors.bright_black })
    set(0, "PmenuThumb", { bg = colors.white })
    set(0, "StatusLine", { fg = colors.fg, bg = colors.bright_black })
    set(0, "StatusLineNC", { fg = colors.white, bg = colors.black })
    set(0, "TabLine", { fg = colors.white, bg = "None" })
    set(0, "TabLineFill", { bg = "None" })
    set(0, "TabLineSel", { fg = colors.fg, bg = "None" })
    set(0, "WildMenu", { fg = colors.selected_text, bg = colors.selection })
    set(0, "VertSplit", { fg = colors.bright_black })
    set(0, "Folded", { fg = colors.white, bg = colors.bright_black })
    set(0, "FoldColumn", { fg = colors.white, bg = colors.bg })
    set(0, "SignColumn", { fg = colors.white, bg = "None" })
    set(0, "MatchParen", { fg = colors.bright_yellow, bg = "None", bold = true })

    -- Diff highlighting
    set(0, "DiffAdd", { fg = colors.green, bg = colors.bg })
    set(0, "DiffChange", { fg = colors.yellow, bg = colors.bg })
    set(0, "DiffDelete", { fg = colors.red, bg = colors.bg })
    set(0, "DiffText", { fg = colors.bright_yellow, bg = colors.bg, bold = true })

    -- Git signs
    set(0, "GitSignsAdd", { fg = colors.green })
    set(0, "GitSignsChange", { fg = colors.yellow })
    set(0, "GitSignsDelete", { fg = colors.red })

    -- LSP diagnostics
    set(0, "DiagnosticError", { fg = colors.bright_red })
    set(0, "DiagnosticWarn", { fg = colors.yellow })
    set(0, "DiagnosticInfo", { fg = colors.cyan })
    set(0, "DiagnosticHint", { fg = colors.bright_cyan })

    -- TreeSitter
    set(0, "@comment", { link = "Comment" })
    set(0, "@constant", { link = "Constant" })
    set(0, "@string", { link = "String" })
    set(0, "@number", { link = "Number" })
    set(0, "@boolean", { link = "Boolean" })
    set(0, "@function", { link = "Function" })
    set(0, "@keyword", { link = "Keyword" })
    set(0, "@operator", { link = "Operator" })
    set(0, "@type", { link = "Type" })
    set(0, "@variable", { fg = colors.fg })
    set(0, "@property", { fg = colors.cyan })
    set(0, "@parameter", { fg = colors.bright_red })
end

function M.get_lualine_theme()
    local colors = M._colors or load_colors()
    return {
        normal = {
            a = { bg = colors.blue, fg = colors.bg, gui = "bold" },
            b = { bg = colors.bg, fg = colors.fg },
            c = { bg = colors.bg, fg = colors.fg },
        },
        insert = {
            a = { bg = colors.green, fg = colors.bg, gui = "bold" },
            b = { bg = colors.bg, fg = colors.fg },
            c = { bg = colors.bg, fg = colors.fg },
        },
        visual = {
            a = { bg = colors.magenta, fg = colors.bg, gui = "bold" },
            b = { bg = colors.bg, fg = colors.fg },
            c = { bg = colors.bg, fg = colors.fg },
        },
        command = {
            a = { bg = colors.yellow, fg = colors.bg, gui = "bold" },
            b = { bg = colors.bg, fg = colors.fg },
            c = { bg = colors.bg, fg = colors.fg },
        },
        replace = {
            a = { bg = colors.red, fg = colors.bg, gui = "bold" },
            b = { bg = colors.bg, fg = colors.fg },
            c = { bg = colors.bg, fg = colors.fg },
        },
        inactive = {
            a = { bg = colors.bright_black, fg = colors.white, gui = "bold" },
            b = { bg = colors.bright_black, fg = colors.white },
            c = { bg = colors.bright_black, fg = colors.white },
        },
    }
end

function M.setup()
    M._theme_name = get_theme_name()
    M._colors = load_colors()
    apply_highlights(M._colors)
end

function M.reload()
    local name = get_theme_name()
    if name == M._theme_name then
        return
    end
    M.setup()
    pcall(function()
        require("lualine").setup({ options = { theme = M.get_lualine_theme() } })
    end)
end

return M
