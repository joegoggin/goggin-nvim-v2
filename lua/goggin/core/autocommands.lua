vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = "justfile",
    command = "set filetype=make",
})

local function open_alpha_dashboard()
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].filetype == "yazi" then
        return
    end

    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.w[win].codediff_restore then
            return
        end
    end

    if vim.fn.exists(":Alpha") == 2 then
        vim.cmd("Alpha")
    end
end

vim.api.nvim_create_autocmd("FocusGained", {
    callback = function()
        require("goggin.theme").reload()
    end,
})

vim.api.nvim_create_autocmd("TabNewEntered", {
    callback = function()
        local buf = vim.api.nvim_get_current_buf()

        if vim.bo[buf].filetype == "alpha" then
            return
        end

        if vim.bo[buf].buftype ~= "" then
            return
        end

        if vim.bo[buf].modified then
            return
        end

        if vim.api.nvim_buf_get_name(buf) ~= "" then
            return
        end

        open_alpha_dashboard()
    end,
})

vim.api.nvim_create_autocmd("BufDelete", {
    callback = function()
        vim.schedule(function()
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                local buf = vim.api.nvim_win_get_buf(win)
                local filetype = vim.bo[buf].filetype
                if filetype == "alpha" or filetype == "yazi" then
                    return
                end
                if vim.w[win].codediff_restore then
                    return
                end
            end

            local real = 0
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if
                    vim.api.nvim_buf_is_valid(buf)
                    and vim.bo[buf].buflisted
                    and vim.bo[buf].buftype == ""
                    and vim.api.nvim_buf_get_name(buf) ~= ""
                then
                    real = real + 1
                end
            end

            if real == 0 then
                open_alpha_dashboard()
            end
        end)
    end,
})

vim.api.nvim_create_user_command("OmarchyReloadTheme", function()
    local theme = require("goggin.theme")
    theme.setup()
    pcall(function()
        require("lualine").setup({ options = { theme = theme.get_lualine_theme() } })
    end)
end, {})
