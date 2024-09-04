vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = "justfile",
    command = "set filetype=make",
})
