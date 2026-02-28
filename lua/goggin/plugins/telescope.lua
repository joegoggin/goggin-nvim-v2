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
                    ".elixir_ls/",
                    "_build/",
                    "deps/",
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
        local function find_in_dir(dir)
            local path = vim.fn.getcwd() .. "/" .. dir
            if vim.fn.isdirectory(path) == 1 then
                builtin.find_files({ cwd = path, no_ignore = true, hidden = true })
            else
                vim.notify("Directory '" .. dir .. "' not found in current project", vim.log.levels.WARN)
            end
        end

        keymap("n", "<leader>fa", function()
            find_in_dir("api")
        end, { desc = "Find Files in API" })
        keymap("n", "<leader>fw", function()
            find_in_dir("web")
        end, { desc = "Find Files in Web" })
        keymap("n", "<leader>fc", function()
            find_in_dir("common")
        end, { desc = "Find Files in Common" })
        keymap("n", "<leader>fr", builtin.resume, {
            desc = "Resume Previous Search",
        })
        keymap("n", "<leader>ft", "<cmd>TodoTelescope<cr>", { desc = "Find ToDos" })
        keymap("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Find Open Buffers" })
    end,
}
