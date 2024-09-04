return {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
        "nvim-tree/nvim-web-devicons",
        "folke/todo-comments.nvim",
    },
    config = function()
        local telescope = require("telescope")

        telescope.setup({
            defaults = {
                path_display = { "smart" },
                file_ignore_patterns = {
                    "node_modules/",
                    "expo/.expo/",
                    "next/.next/",
                    ".yarn/",
                    ".git/",
                    ".expo/",
                    ".next/",
                    ".DS_Store",
                    "target",
                    ".docusaurus",
                    ".react-email",
                    "**/*.lock",
                },
            },
        })

        telescope.load_extension("fzf")

        -- set keymaps
        local keymap = vim.keymap.set
        local builtin = require("telescope.builtin")

        keymap("n", "<leader>ff", function()
            builtin.find_files({ no_ignore = true, hidden = true })
        end, {
            desc = "Find All Files",
        })
        keymap("n", "<leader>fg", builtin.git_files, {
            desc = "Find Git Files",
        })
        keymap("n", "<leader>fo", builtin.oldfiles, {
            desc = "Find Old Files",
        })
        keymap("n", "<leader>fl", builtin.live_grep, {
            desc = "Search With Live Grep",
        })
        keymap("n", "<leader>fh", builtin.help_tags, {
            desc = "Search Help Tags",
        })
        keymap("n", "<leader>fd", builtin.diagnostics, {
            desc = "Find Diagnostics",
        })
        keymap("n", "<leader>fk", builtin.keymaps, {
            desc = "Find Keymaps",
        })
        keymap("n", "<leader>fw", builtin.lsp_references, {
            desc = "Find LSP References Of Word Under Cursor",
        })
        keymap("n", "<leader>fr", builtin.resume, {
            desc = "Resume Previous Search",
        })
    end,
}
