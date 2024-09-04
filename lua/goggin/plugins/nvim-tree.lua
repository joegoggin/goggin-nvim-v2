return {
  "nvim-tree/nvim-tree.lua",
  dependencies = "nvim-tree/nvim-web-devicons",
  config = function()
    local nvim_tree = require("nvim-tree")

    -- recommended settings from nvim-tree documentation
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1

    nvim_tree.setup({
    update_focused_file = {
        enable = true,
        update_cwd = true,
    },
    renderer = {
        root_folder_modifier = ":t",
        icons = {
            glyphs = {
                default = "",
                symlink = "",
                folder = {
                    arrow_open = "",
                    arrow_closed = "",
                    default = "",
                    open = "",
                    empty = "",
                    empty_open = "",
                    symlink = "",
                    symlink_open = "",
                },
                git = {
                    unstaged = "",
                    staged = "S",
                    unmerged = "",
                    renamed = "➜",
                    untracked = "U",
                    deleted = "",
                    ignored = "◌",
                },
            },
        },
    },
    diagnostics = {
        enable = true,
        show_on_dirs = true,
        icons = {
            hint = "",
            info = "",
            warning = "",
            error = "",
        },
    },
    view = {
        width = 30,
        side = "left",
    },
    git = {
        enable = true,
        ignore = false,
        timeout = 500,
    },
    filters = { dotfiles = false, custom = { "^.git$" } },
})

    -- set keymaps
    local keymap = vim.keymap.set -- for conciseness
    local nt_api = require("nvim-tree.api");
    
    keymap("n", "<leader>e", function()
        nt_api.git.reload()
        vim.cmd("NvimTreeFindFileToggle")
    end, {
        desc = "Toggle Explorer",
    })
  end
}
