vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = "justfile",
    command = "set filetype=make",
})

vim.api.nvim_create_autocmd("FocusGained", {
    callback = function()
        require("goggin.theme").reload()
    end,
})

vim.api.nvim_create_autocmd("BufDelete", {
    callback = function()
        vim.schedule(function()
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                local buf = vim.api.nvim_win_get_buf(win)
                if vim.bo[buf].filetype == "alpha" then
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
                vim.cmd("Alpha")
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
