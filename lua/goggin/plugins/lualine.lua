return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons", "joegoggin/matrix.nvim" },
    config = function()
        local lualine = require("lualine")
        local lazy_status = require("lazy.status") -- to configure lazy pending updates count
        local matrix = require("matrix").lualine

        -- configure lualine with modified theme
        lualine.setup({
            options = {
                theme = matrix,
                component_separators = { left = "", right = "" },
                section_separators = { left = "", right = "" },
                disabled_filetypes = { "alpha", "dashboard", "NvimTree", "Outline" },
            },
            sections = {
                lualine_x = {
                    {
                        lazy_status.updates,
                        cond = lazy_status.has_updates,
                        color = { fg = "#ff9e64" },
                    },
                    { "filetype" },
                },
            },
        })
    end,
}
