vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = "justfile",
    command = "set filetype=make",
})

vim.api.nvim_create_autocmd("FocusGained", {
    callback = function()
        require("goggin.theme").reload()
    end,
})

vim.api.nvim_create_user_command("OmarchyReloadTheme", function()
    local theme = require("goggin.theme")
    theme.setup()
    pcall(function()
        require("lualine").setup({ options = { theme = theme.get_lualine_theme() } })
    end)
end, {})
