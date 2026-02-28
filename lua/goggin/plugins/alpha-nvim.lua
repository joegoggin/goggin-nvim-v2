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
        local buttons = {
            dashboard.button("f", "   Find File", ":Telescope find_files<CR>"),
        }

        local dirs = {
            { key = "a", label = "   Find in API", dir = "api" },
            { key = "w", label = "   Find in Web", dir = "web" },
            { key = "c", label = "   Find in Common", dir = "common" },
        }

        for _, d in ipairs(dirs) do
            if vim.fn.isdirectory(vim.fn.getcwd() .. "/" .. d.dir) == 1 then
                table.insert(buttons, dashboard.button(d.key, d.label, ":Telescope find_files cwd=" .. d.dir .. "<CR>"))
            end
        end

        vim.list_extend(buttons, {
            dashboard.button("e", "   Browse Files", ":Yazi<CR>"),
            dashboard.button("d", "   Code Diff", ":CodeDiff HEAD<CR>"),
            dashboard.button("g", "   Git", ":Git<CR>"),
            dashboard.button("u", "   Update Plugins", ":Lazy update<CR>"),
            dashboard.button("q", " 󰍃  Quit Neovim", ":qa!<CR>"),
        })

        dashboard.section.buttons.val = buttons

        dashboard.section.footer.val = function()
            local cwd = vim.uv.cwd()

            return "Current Directory: " .. cwd
        end

        -- Configure `alpha-nvim`
        alpha.setup(dashboard.opts)
    end,
}
