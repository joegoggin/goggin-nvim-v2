local M = {}

local function warn(message)
    vim.notify(message, vim.log.levels.WARN)
end

local function current_line()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""

    return row, line
end

local function line_at(row)
    return vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
end

local function trim(value)
    return value:match("^%s*(.-)%s*$")
end

local function escape_pattern(value)
    return value:gsub("([^%w])", "%%%1")
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
        local line = line_at(row)
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
        local line = line_at(row)
        local step_number = line:match("^###%s+Step%s+(%d+)%s*$")

        if step_number then
            return step_number
        end
    end

    return nil
end

local function current_test_command()
    local _, line = current_line()

    return line:match("^%s*[-*+]%s+%[[ xX]%]%s+Run%s+`([^`]+)`")
end

local function is_confirm_checkmark(line)
    return line:match("^%s*[-*+]%s+%[[ xX]%]%s+Confirm%s+") ~= nil
end

local function useful_commands_block()
    local line_count = vim.api.nvim_buf_line_count(0)
    local heading_row = nil

    for row = 1, line_count do
        if line_at(row):match("^###%s+Useful commands%s*$") then
            heading_row = row
            break
        end
    end

    if not heading_row then
        return nil, nil
    end

    local fence_start = nil

    for row = heading_row + 1, line_count do
        local line = line_at(row)

        if line:match("^###%s+") then
            return nil, nil
        end

        if line:match("^```%s*[%w_-]*%s*$") then
            fence_start = row
            break
        end
    end

    if not fence_start then
        return nil, nil
    end

    for row = fence_start + 1, line_count do
        if line_at(row):match("^```%s*$") then
            return fence_start + 1, row - 1
        end
    end

    return fence_start + 1, line_count
end

local function current_useful_command()
    local row, line = current_line()
    local start_row, end_row = useful_commands_block()

    if not start_row or row < start_row or row > end_row then
        return nil
    end

    local command = trim(line)
    if command == "" then
        return nil
    end

    return command
end

local function confirm_checkmark_rows()
    local rows = {}
    local line_count = vim.api.nvim_buf_line_count(0)

    for row = 1, line_count do
        if is_confirm_checkmark(line_at(row)) then
            table.insert(rows, row)
        end
    end

    return rows
end

local function current_confirm_checkmark_index()
    local current_row, line = current_line()

    if not is_confirm_checkmark(line) then
        return nil
    end

    for index, row in ipairs(confirm_checkmark_rows()) do
        if row == current_row then
            return index
        end
    end

    return nil
end

local function rg_command_rows()
    local rows = {}
    local start_row, end_row = useful_commands_block()

    if not start_row then
        return rows
    end

    for row = start_row, end_row do
        local command = trim(line_at(row))

        if command:match("^rg%s+") then
            table.insert(rows, row)
        end
    end

    return rows
end

local function current_rg_command_index()
    local current_row = vim.api.nvim_win_get_cursor(0)[1]
    local command = current_useful_command()

    if not command or not command:match("^rg%s+") then
        return nil
    end

    for index, row in ipairs(rg_command_rows()) do
        if row == current_row then
            return index
        end
    end

    return nil
end

local function goto_useful_command(command)
    local start_row, end_row = useful_commands_block()

    if not start_row then
        warn("No ### Useful commands block found")
        return false
    end

    for row = start_row, end_row do
        if trim(line_at(row)) == command then
            vim.api.nvim_win_set_cursor(0, { row, 0 })
            return true
        end
    end

    warn("No useful command found for: " .. command)
    return false
end

local function goto_test_command(command)
    local escaped_command = escape_pattern(command)
    local pattern = "^%s*[-*+]%s+%[[ xX]%]%s+Run%s+`" .. escaped_command .. "`"

    return jump_to_matching_line(pattern, "No test checkmark found for: " .. command)
end

local function goto_rg_command(index)
    local rows = rg_command_rows()
    local row = rows[index]

    if row then
        vim.api.nvim_win_set_cursor(0, { row, 0 })
        return true
    end

    warn("No rg command found for Confirm checkmark " .. index)
    return false
end

local function goto_confirm_checkmark(index)
    local rows = confirm_checkmark_rows()
    local row = rows[index]

    if row then
        vim.api.nvim_win_set_cursor(0, { row, 0 })
        return true
    end

    warn("No Confirm checkmark found for rg command " .. index)
    return false
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
    local command = current_useful_command()

    if command then
        local rg_index = current_rg_command_index()

        if rg_index then
            goto_confirm_checkmark(rg_index)
            return
        end

        goto_test_command(command)
        return
    end

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
    local command = current_test_command()

    if command then
        goto_useful_command(command)
        return
    end

    local confirm_index = current_confirm_checkmark_index()

    if confirm_index then
        goto_rg_command(confirm_index)
        return
    end

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
