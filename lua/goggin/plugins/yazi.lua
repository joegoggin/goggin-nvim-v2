return {
    "mikavilpas/yazi.nvim",
    event = "VeryLazy",
    dependencies = {
        { "nvim-lua/plenary.nvim", lazy = true },
    },
    keys = {
        -- 👇 in this section, choose your own keymappings!
        {
            -- Open in the current working directory
            "<leader>e",
            "<cmd>Yazi cwd<cr>",
            desc = "Open the file manager in nvim's working directory",
        },
    },
    opts = {
        open_for_directories = true,
        keymaps = {
            show_help = "<f1>",
        },
    },
    init = function()
        vim.g.loaded_netrwPlugin = 1
    end,
    on_close = function()
        print("yazi closed")
    end,
}
