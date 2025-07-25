return {
    "goolord/alpha-nvim",
    dependencies = {
        "nvim-tree/nvim-web-devicons", -- Recommended for icons in alpha-nvim
    },
    event = "VimEnter",                -- Load on Neovim startup
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
            dashboard.button("u", "   Update Plugins", ":Lazy update<CR>"),
            dashboard.button("q", " 󰍃  Quit Neovim", ":qa!<CR>"),
        }

        dashboard.section.footer.val = function()
            local ok, lazy_status = pcall(require, "lazy.status")

            if not ok or type(lazy_status) ~= "table" or type(lazy_status.updates) ~= "function" then
                return "Plugin update status: (Lazy.nvim API not available)"
            end

            local updates = lazy_status.updates()

            updates = type(updates) == "number" and updates or 0

            if updates > 0 then
                return updates .. " plugin(s) need updating! (Press 'u' to update)"
            else
                return "All plugins are up to date!"
            end
        end

        -- Configure `alpha-nvim`
        alpha.setup(dashboard.opts)
    end,
}
