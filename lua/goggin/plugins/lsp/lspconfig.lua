return {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
        "hrsh7th/cmp-nvim-lsp",
        { "antosha417/nvim-lsp-file-operations", config = true },
        { "folke/neodev.nvim", opts = {} },
    },
    config = function()
        -- import lspconfig plugin
        local lspconfig = require("lspconfig")

        -- import mason_lspconfig plugin
        local mason_lspconfig = require("mason-lspconfig")

        -- import cmp-nvim-lsp plugin
        local cmp_nvim_lsp = require("cmp_nvim_lsp")

        local keymap = vim.keymap.set

        vim.diagnostic.config({
            virtual_text = false,
        })

        vim.api.nvim_create_autocmd("LspAttach", {
            group = vim.api.nvim_create_augroup("UserLspConfig", {}),
            callback = function(ev)
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

        -- Change the Diagnostic symbols in the sign column (gutter)
        -- (not in youtube nvim video)
        local signs = { Error = " ", Warn = " ", Hint = "󰠠 ", Info = " " }
        for type, icon in pairs(signs) do
            local hl = "DiagnosticSign" .. type
            vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
        end

        lspconfig["emmet_ls"].setup({
            capabilities = capabilities,
            filetypes = { "html" },
        })

        -- configure lua server (with special settings)
        lspconfig["lua_ls"].setup({
            capabilities = capabilities,
            settings = {
                Lua = {
                    -- make the language server recognize "vim" global
                    diagnostics = {
                        globals = { "vim" },
                    },
                    completion = {
                        callSnippet = "Replace",
                    },
                },
            },
        })

        lspconfig["ts_ls"].setup({
            capabilites = capabilities,
            init_options = {
                preferences = {
                    importModuleSpecifierPreference = "non-relative",
                },
            },
        })

        lspconfig["rust_analyzer"].setup({
            capabilities = capabilities,
            settings = {
                ["rust_analyzer"] = {
                    check = {
                        allTargets = false,
                    },
                    procMacro = {
                        enable = true,
                    },
                    cargo = {
                        buildScripts = {
                            enable = true,
                        },
                    },
                },
            },
        })

        lspconfig["postgres_lsp"].setup({
            capabilities = capabilities,
        })
    end,
}
