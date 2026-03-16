local function open_yazi_in_dir(dir)
    local path = vim.fn.getcwd() .. "/" .. dir

    if vim.fn.isdirectory(path) == 1 then
        require("yazi").yazi(nil, path)
    else
        vim.notify("Directory '" .. dir .. "' not found in current project", vim.log.levels.WARN)
    end
end

return {
    "mikavilpas/yazi.nvim",
    event = "VeryLazy",
    dependencies = {
        { "nvim-lua/plenary.nvim", lazy = true },
    },
    keys = {
        {
            "<leader>ee",
            "<cmd>Yazi cwd<cr>",
            desc = "Browse project root",
        },
        {
            "<leader>ea",
            function()
                open_yazi_in_dir("api")
            end,
            desc = "Browse API directory",
        },
        {
            "<leader>ew",
            function()
                open_yazi_in_dir("web")
            end,
            desc = "Browse Web directory",
        },
        {
            "<leader>ec",
            function()
                open_yazi_in_dir("common")
            end,
            desc = "Browse Common directory",
        },
        {
            "<leader>ei",
            function()
                open_yazi_in_dir("issues")
            end,
            desc = "Browse Issues directory",
        },
        {
            "<leader>E",
            "<cmd>Yazi<cr>",
            desc = "Open yazi at the current file",
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
}
