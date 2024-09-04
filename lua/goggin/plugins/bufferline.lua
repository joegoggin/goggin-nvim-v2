return {
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    version = "*",
    opts = {
        options = {
            numbers = "none", -- | "ordinal" | "buffer_id" | "both" | function({ ordinal, id, lower, raise }): string,
            close_command = "bd %d", -- can be a string | function, see "Mouse actions"
            right_mouse_command = "bd %d", -- can be a string | function, see "Mouse actions"
            left_mouse_command = "buffer %d", -- can be a string | function, see "Mouse actions"
            middle_mouse_command = nil, -- can be a string | function, see "Mouse actions"
            indicator_icon = nil,
            indicator = { style = "icon", icon = "▎" },
            buffer_close_icon = "",
            modified_icon = "●",
            close_icon = "",
            left_trunc_marker = "",
            right_trunc_marker = "",
            name_formatter = function(buf)
                -- Get the file name and path
                local name = buf.name
                local path = buf.path
                -- Get the current working directory
                local cwd = vim.fn.getcwd()
                -- Get the directory of the file
                local file_dir = vim.fn.fnamemodify(path, ":h")
                -- Check if the file is in the root of the current working directory
                if file_dir == cwd then
                    return name
                else
                    -- Extract the root folder
                    local root = vim.fn.fnamemodify(file_dir, ":t")
                    return root .. "/" .. name
                end
            end,
            offsets = { { filetype = "NvimTree", text = "", padding = 1 } },
            show_buffer_icons = true,
            show_buffer_close_icons = true,
            show_close_icon = true,
            show_tab_indicators = true,
            persist_buffer_sort = true, -- whether or not custom sorted buffers should persist
            separator_style = "thin", -- | "thick" | "thin" | { 'any', 'any' },
            enforce_regular_tabs = true,
            always_show_bufferline = true,
        },
    },
}
