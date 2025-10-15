return {
    "williamboman/mason.nvim",
    dependencies = {
        "williamboman/mason-lspconfig.nvim",
        "WhoIsSethDaniel/mason-tool-installer.nvim",
    },
    config = function()
        -- import mason
        local mason = require("mason")

        -- import mason-lspconfig
        local mason_lspconfig = require("mason-lspconfig")

        local mason_tool_installer = require("mason-tool-installer")

        -- enable mason and configure icons
        mason.setup({
            ui = {
                icons = {
                    package_installed = "✓",
                    package_pending = "➜",
                    package_uninstalled = "✗",
                },
            },
        })

        mason_lspconfig.setup({
            -- list of servers for mason to install
            ensure_installed = {
                "lua_ls",
                "ts_ls",
                "emmet_ls",
                "prismals",
                "dockerls",
                "docker_compose_language_service",
                "bashls",
                "eslint",
                "somesass_ls",
                "postgres_lsp",
                "pyright",
                "elixirls",
            },
            automatic_enable = true,
        })

        mason_tool_installer.setup({
            ensure_installed = { "stylua", "prettierd", "shellcheck", "shfmt", "eslint_d" },
        })
    end,
}
