return {
    "mfussenegger/nvim-lint",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
        local lint = require("lint")
        local uv = vim.loop

        lint.linters_by_ft = {
            javascript = { "eslint" },
            typescript = { "eslint" },
            javascriptreact = { "eslint" },
            typescriptreact = { "eslint" },
        }

        local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

        local function eslint_config_exists()
            local files = { ".eslintrc", ".eslintrc.json", ".eslintrc.js", ".eslintrc.yaml", ".eslintrc.yml" }
            for _, file in ipairs(files) do
                if uv.fs_stat(file) then
                    return true
                end
            end
            return false
        end

        vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
            group = lint_augroup,
            callback = function()
                if eslint_config_exists() then
                    lint.try_lint()
                end
            end,
        })
    end,
}
