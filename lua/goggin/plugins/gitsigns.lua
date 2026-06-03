return {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
        local gitsigns = require("gitsigns")

        gitsigns.setup({
            signs = {
                add = { text = "+" },
                change = { text = "~" },
                delete = { text = "_" },
                topdelete = { text = "‾" },
                changedelete = { text = "~" },
            },
            on_attach = function(bufnr)
                local opts = { buffer = bufnr }

                vim.keymap.set("n", "gj", function()
                    gitsigns.nav_hunk("next")
                end, vim.tbl_extend("force", opts, {
                    desc = "Next Git chunk",
                }))

                vim.keymap.set("n", "gk", function()
                    gitsigns.nav_hunk("prev")
                end, vim.tbl_extend("force", opts, {
                    desc = "Previous Git chunk",
                }))
            end,
        })
    end,
}
