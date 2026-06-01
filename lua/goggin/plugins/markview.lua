return {
    "OXY2DEV/markview.nvim",
    lazy = false,
    opts = {
        markdown = {
            code_blocks = {
                ["diff"] = {
                    block_hl = function(_, line)
                        if line:match("^%+") then
                            return "MarkviewPalette4Bg"
                        elseif line:match("^%-") then
                            return "MarkviewPalette1Bg"
                        else
                            return "MarkviewCode"
                        end
                    end,
                    pad_hl = "MarkviewCode",
                },
            },
        },
    },

    -- Completion for `blink.cmp`
    -- dependencies = { "saghen/blink.cmp" },
}
