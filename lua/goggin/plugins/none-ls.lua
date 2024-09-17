return {
    "nvimtools/none-ls.nvim",
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
        }

        local function letptos_enabled()
            local file = vim.fn.findfile("leptosfmt.toml", "**/")
            return file ~= ""
        end

        if letptos_enabled() then
            sources = {
                formatting.leptosfmt.with({
                    command = "leptosfmt",
                    args = { "--stdin", "--rustfmt" },
                }),
            }
        end

        if IsDelavieMediaProject() then
            sources = {
                formatting.eslint_d,
            }
        end

        null_ls.setup({
            sources = sources,
        })
    end,
}
