local M = {}

local function warn(message)
    vim.notify(message, vim.log.levels.WARN)
end

local function current_line()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""

    return row, line
end

local function save_current_buffer()
    if vim.bo.buftype ~= "" then
        return
    end

    if vim.api.nvim_buf_get_name(0) == "" then
        warn("Markdown checkbox toggled, but buffer has no file name to save")
        return
    end

    local ok, err = pcall(vim.cmd, "silent update")
    if not ok then
        warn("Markdown checkbox toggled, but save failed: " .. err)
    end
end

local function jump_to_matching_line(pattern, missing_message)
    local line_count = vim.api.nvim_buf_line_count(0)

    for row = 1, line_count do
        local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
        if line:match(pattern) then
            vim.api.nvim_win_set_cursor(0, { row, 0 })
            return true
        end
    end

    warn(missing_message)
    return false
end

local function current_step_number()
    local current_row = vim.api.nvim_win_get_cursor(0)[1]

    for row = current_row, 1, -1 do
        local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
        local step_number = line:match("^###%s+Step%s+(%d+)%s*$")

        if step_number then
            return step_number
        end
    end

    return nil
end

function M.is_issue_file(bufnr)
    bufnr = bufnr or 0

    local name = vim.api.nvim_buf_get_name(bufnr)
    local basename = vim.fn.fnamemodify(name, ":t")

    return basename:match("^issue%-.*%.md$") ~= nil
end

function M.toggle_checkbox()
    local row, line = current_line()
    local start_index, end_index = line:find("%[[ xX]%]")

    if not start_index then
        warn("No Markdown checkbox found on this line")
        return
    end

    local state = line:sub(start_index + 1, start_index + 1)
    local replacement = state == " " and "[x]" or "[ ]"
    local updated = line:sub(1, start_index - 1) .. replacement .. line:sub(end_index + 1)

    vim.api.nvim_buf_set_lines(0, row - 1, row, false, { updated })
    save_current_buffer()
end

function M.goto_progress()
    local step_number = current_step_number()

    if step_number then
        jump_to_matching_line(
            "^%s*[-*+]%s+%[[ xX]%]%s+Step%s+" .. step_number .. "%s+%-",
            "No progress line found for Step " .. step_number
        )
        return
    end

    jump_to_matching_line("^###%s+Progress%s*$", "No ### Progress heading found")
end

function M.goto_step_definition()
    local _, line = current_line()
    local step_number = line:match("^%s*[-*+]%s+%[[ xX]%]%s+Step%s+(%d+)%s+%-")

    if not step_number then
        warn("Current line is not a Markdown progress step")
        return
    end

    jump_to_matching_line(
        "^###%s+Step%s+" .. step_number .. "%s*$",
        "No ### Step " .. step_number .. " heading found"
    )
end

return M
