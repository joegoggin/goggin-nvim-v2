return {
    "EdenEast/nightfox.nvim",
    priority = 1000,
    config = function()
        vim.cmd("colorscheme terafox")

        vim.api.nvim_set_hl(0, "Visual", { bg = "#e85c51", fg = "#152528" })
        vim.api.nvim_set_hl(0, "CursorLine", { bg = "NONE" })
        vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#e85c51", bg = "NONE", bold = true })
    end,
}
