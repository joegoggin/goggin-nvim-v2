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
            dashboard.button("f f", "   Find File", ":Telescope find_files<CR>"),
        }
        local find_buttons = {}
        local browse_buttons = {}

        local dirs = {
            { key = "a", name = "API", dir = "api" },
            { key = "w", name = "Web", dir = "web" },
            { key = "c", name = "Common", dir = "common" },
            { key = "i", name = "Issues", dir = "issues" },
        }

        for _, d in ipairs(dirs) do
            if vim.fn.isdirectory(vim.fn.getcwd() .. "/" .. d.dir) == 1 then
                local find_cmd = ":Telescope find_files cwd=" .. d.dir .. "<CR>"

                if d.dir == "issues" then
                    find_cmd = ":Telescope find_files cwd=" .. d.dir .. " no_ignore=true hidden=true<CR>"
                end

                table.insert(find_buttons, dashboard.button("f " .. d.key, "   Find in " .. d.name, find_cmd))

                local browse_cmd =
                    "<cmd>lua require('yazi').yazi(nil, vim.fs.joinpath(vim.fn.getcwd(), '" .. d.dir .. "'))<CR>"
                table.insert(browse_buttons, dashboard.button("e " .. d.key, "   Browse " .. d.name, browse_cmd))
            end
        end

        vim.list_extend(buttons, find_buttons)
        table.insert(buttons, dashboard.button("e e", "   Browse Files", ":Yazi cwd<CR>"))
        vim.list_extend(buttons, browse_buttons)

        local function get_default_remote_branch()
            local branch = vim.fn.systemlist({
                "git",
                "symbolic-ref",
                "--quiet",
                "--short",
                "refs/remotes/origin/HEAD",
            })[1]

            if vim.v.shell_error == 0 and branch and branch ~= "" then
                return vim.trim(branch)
            end

            return "main"
        end

        local function open_branch_diff()
            vim.cmd("CodeDiff " .. get_default_remote_branch() .. "...HEAD")
        end

        local branch_diff_button = dashboard.button("d b", "   Code Diff Branch")
        branch_diff_button.on_press = open_branch_diff
        branch_diff_button.opts.keymap = {
            "n",
            "db",
            open_branch_diff,
            { noremap = true, silent = true, nowait = true, desc = "Open branch code diff" },
        }

        vim.list_extend(buttons, {
            dashboard.button("d d", "   Code Diff", ":CodeDiff HEAD<CR>"),
            branch_diff_button,
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
