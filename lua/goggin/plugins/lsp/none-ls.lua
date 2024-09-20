return {
    "nvimtools/none-ls.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
        local null_ls = require("null-ls")
        local formatting = null_ls.builtins.formatting

        local sources = {
            formatting.prettierd.with({
                env = {
                    PRETTIERD_DEFAULT_CONFIG = vim.fn.expand("~/.config/nvim/utils/linter-config/.prettierrc.json"),
                },
            }),
            formatting.stylua,
            formatting.shfmt,
            formatting.leptosfmt.with({
                command = "leptosfmt",
                args = { "--stdin", "--rustfmt" },
            }),
        }

        if IsDelavieMediaProject() then
            sources = {}
        end

        null_ls.setup({
            sources = sources,
        })
    end,
}
