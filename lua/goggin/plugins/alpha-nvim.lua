return {
    "goolord/alpha-nvim",
    dependencies = {
        "nvim-tree/nvim-web-devicons", -- Recommended for icons in alpha-nvim
    },
    event = "VimEnter", -- Load on Neovim startup
    config = function()
        local alpha = require("alpha")
        local dashboard = require("alpha.themes.dashboard")

        -- Your custom header as a table of strings
        dashboard.section.header.val = {
            "███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗",
            "████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║",
            "██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║",
            "██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║",
            "██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║",
            "╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝",
        }

        -- Define your buttons (actions)
        -- The key 'c' is the hotkey you press to activate the action
        dashboard.section.buttons.val = {
            dashboard.button("f", "   Find File", ":Telescope find_files<CR>"),
            dashboard.button("e", "   Browse Files", ":Yazi<CR>"),
            dashboard.button("d", "   Code Diff", ":CodeDiff HEAD<CR>"),
            dashboard.button("u", "   Update Plugins", ":Lazy update<CR>"),
            dashboard.button("q", " 󰍃  Quit Neovim", ":qa!<CR>"),
        }

        dashboard.section.footer.val = function()
            local cwd = vim.uv.cwd()

            return "Current Directory: " .. cwd
        end

        -- Configure `alpha-nvim`
        alpha.setup(dashboard.opts)
    end,
}
