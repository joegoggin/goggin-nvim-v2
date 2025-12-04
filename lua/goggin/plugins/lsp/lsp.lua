return {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
        "hrsh7th/cmp-nvim-lsp",
        { "antosha417/nvim-lsp-file-operations", config = true },
    },
    config = function()
        local cmp_nvim_lsp = require("cmp_nvim_lsp")

        local keymap = vim.keymap.set

        vim.diagnostic.config({
            virtual_text = false,
        })

        vim.api.nvim_create_autocmd("LspAttach", {
            group = vim.api.nvim_create_augroup("UserLspConfig", {}),
            callback = function()
                keymap("n", "<leader>lr", vim.lsp.buf.rename, {
                    desc = "Rename",
                })
                keymap("n", "<leader>la", vim.lsp.buf.code_action, {
                    desc = "Run Code Action",
                })
                keymap("n", "gd", vim.lsp.buf.definition, {
                    desc = "Go to Definition",
                })
                keymap("n", "gi", vim.lsp.buf.implementation, {
                    desc = "Go to Implementation",
                })
                keymap("n", "gl", vim.diagnostic.open_float, {
                    desc = "Show Diagnostics Info",
                })
                keymap("n", "K", vim.lsp.buf.hover, {
                    desc = "Hover",
                })
            end,
        })

        -- used to enable autocompletion (assign to every lsp server config)
        local capabilities = cmp_nvim_lsp.default_capabilities()

        vim.lsp.config("*", {
            capabilities = capabilities,
        })

        -- Change the Diagnostic symbols in the sign column (gutter)
        local severity = vim.diagnostic.severity

        vim.diagnostic.config({
            signs = {
                text = {
                    [severity.ERROR] = " ",
                    [severity.WARN] = " ",
                    [severity.HINT] = "󰠠 ",
                    [severity.INFO] = " ",
                },
            },
        })
    end,
}
