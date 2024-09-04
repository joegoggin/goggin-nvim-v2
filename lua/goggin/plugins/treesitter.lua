return {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPre", "BufNewFile" },
    build = ":TSUpdate",
    dependencies = {
        "windwp/nvim-ts-autotag",
    },
    config = function()
        local treesitter = require("nvim-treesitter.configs")

        treesitter.setup({
            -- Languages --
            ensure_installed = {
                "css",
                "lua",
                "tsx",
                "typescript",
                "gitignore",
                "html",
                "javascript",
                "json",
                "markdown",
                "prisma",
                "regex",
                "bash",
                "rust",
            },
            sync_install = false,
            auto_install = true,
            highlight = {
                enable = true,
            },
        })
    end,
}
