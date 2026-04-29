local function get_first_capture(match, capture_id)
    local capture = match[capture_id]

    if type(capture) == "table" then
        return capture[1]
    end

    return capture
end

local function patch_nvim_treesitter_query_handlers()
    local query = require("vim.treesitter.query")

    local html_script_type_languages = {
        ["importmap"] = "json",
        ["module"] = "javascript",
        ["application/ecmascript"] = "javascript",
        ["text/ecmascript"] = "javascript",
    }

    local non_filetype_match_injection_language_aliases = {
        ex = "elixir",
        pl = "perl",
        sh = "bash",
        ts = "typescript",
        uxn = "uxntal",
    }

    local function valid_args(name, pred, count, strict_count)
        local arg_count = #pred - 1

        if strict_count and arg_count ~= count then
            vim.api.nvim_err_writeln(string.format("%s must have exactly %d arguments", name, count))
            return false
        end

        if not strict_count and arg_count < count then
            vim.api.nvim_err_writeln(string.format("%s must have at least %d arguments", name, count))
            return false
        end

        return true
    end

    local function get_types(pred)
        local types = {}

        for i = 3, #pred do
            types[#types + 1] = pred[i]
        end

        return types
    end

    local function get_parser_from_markdown_info_string(injection_alias)
        local match = vim.filetype.match({ filename = "a." .. injection_alias })
        return match or non_filetype_match_injection_language_aliases[injection_alias] or injection_alias
    end

    local opts = { force = true }

    -- Neovim 0.12 passes custom query handlers capture lists. These handlers
    -- keep nvim-treesitter's compatibility predicates working with that API.
    query.add_predicate("nth?", function(match, _, _, pred)
        if not valid_args("nth?", pred, 2, true) then
            return
        end

        local node = get_first_capture(match, pred[2])
        local n = tonumber(pred[3])

        if node and n and node:parent() and node:parent():named_child_count() > n then
            return node:parent():named_child(n) == node
        end

        return false
    end, opts)

    query.add_predicate("is?", function(match, _, bufnr, pred)
        if not valid_args("is?", pred, 2) then
            return
        end

        local node = get_first_capture(match, pred[2])

        if not node then
            return true
        end

        local _, _, kind = require("nvim-treesitter.locals").find_definition(node, bufnr)
        return vim.tbl_contains(get_types(pred), kind)
    end, opts)

    query.add_predicate("kind-eq?", function(match, _, _, pred)
        if not valid_args(pred[1], pred, 2) then
            return
        end

        local node = get_first_capture(match, pred[2])

        if not node then
            return true
        end

        return vim.tbl_contains(get_types(pred), node:type())
    end, opts)

    query.add_directive("set-lang-from-mimetype!", function(match, _, bufnr, pred, metadata)
        local node = get_first_capture(match, pred[2])

        if not node then
            return
        end

        local type_attr_value = vim.treesitter.get_node_text(node, bufnr)
        local configured = html_script_type_languages[type_attr_value]

        if configured then
            metadata["injection.language"] = configured
        else
            local parts = vim.split(type_attr_value, "/", {})
            metadata["injection.language"] = parts[#parts]
        end
    end, opts)

    query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
        local node = get_first_capture(match, pred[2])

        if not node then
            return
        end

        local injection_alias = vim.treesitter.get_node_text(node, bufnr):lower()
        metadata["injection.language"] = get_parser_from_markdown_info_string(injection_alias)
    end, opts)

    query.add_directive("make-range!", function() end, opts)

    query.add_directive("downcase!", function(match, _, bufnr, pred, metadata)
        local id = pred[2]
        local node = get_first_capture(match, id)

        if not node then
            return
        end

        local text = vim.treesitter.get_node_text(node, bufnr, { metadata = metadata[id] }) or ""

        if not metadata[id] then
            metadata[id] = {}
        end

        metadata[id].text = string.lower(text)
    end, opts)
end

return {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPre", "BufNewFile" },
    build = ":TSUpdate",
    dependencies = {
        "windwp/nvim-ts-autotag",
        "rayliwell/tree-sitter-rstml",
    },
    config = function()
        local treesitter = require("nvim-treesitter.configs")

        treesitter.setup({
            -- Languages --
            ensure_installed = {
                "css",
                "lua",
                "tsx",
                "typescript",
                "gitignore",
                "html",
                "javascript",
                "json",
                "markdown",
                "markdown_inline",
                "python",
                "prisma",
                "regex",
                "bash",
                "rust",
            },
            sync_install = false,
            auto_install = true,
            highlight = {
                enable = true,
            },
        })

        patch_nvim_treesitter_query_handlers()
        require("tree-sitter-rstml").setup()
        require("nvim-ts-autotag").setup()
    end,
}
