-- opt --
vim.opt.backup = false -- creates a backup file
vim.opt.clipboard = "unnamedplus"
vim.opt.cmdheight = 2 -- more space in the neovim command line for displaying messages
vim.opt.completeopt = { "menuone", "noselect" } -- mostly just for cmp
vim.opt.conceallevel = 0 -- so that `` is visible in markdown files
vim.opt.fileencoding = "utf-8" -- the encoding written to a file
vim.opt.hlsearch = true -- highlight all matches on previous search pattern
vim.opt.ignorecase = true -- ignore case in search patterns
vim.opt.mouse = "a" -- allow the mouse to be used in neovim
vim.opt.pumheight = 10 -- pop up menu height
vim.opt.showmode = false -- we don't need to see things like -- INSERT -- anymore
vim.opt.showtabline = 2 -- always show tabs
vim.opt.smartcase = true -- smart case
vim.opt.smartindent = true -- make indenting smarter again
vim.opt.splitbelow = true -- force all horizontal splits to go below current window
vim.opt.splitright = true -- force all vertical splits to go to the right of current window
vim.opt.swapfile = false -- creates a swapfile
vim.opt.termguicolors = true -- set term gui colors (most terminals support this)
vim.opt.timeoutlen = 1000 -- time to wait for a mapped sequence to complete (in milliseconds)
vim.opt.undofile = true -- enable persistent undo
vim.opt.updatetime = 300 -- faster completion (4000ms default)
vim.opt.writebackup = false -- if a file is being edited by another program (or was written to file while editing with another program), it is not allowed to be edited
vim.opt.expandtab = true -- convert tabs to spaces
vim.opt.cursorline = true -- highlight the current line
vim.opt.number = true -- set numbered lines
vim.opt.relativenumber = true -- set relative numbered lines
vim.opt.numberwidth = 4 -- set number column width to 2 {default 4}
vim.opt.signcolumn = "yes" -- always show the sign column, otherwise it would shift the text each time
vim.opt.wrap = true -- wrap text when it goes beyond textwidth
vim.opt.textwidth = 80 -- number of lines before text is wrapped
vim.opt.breakindent = true -- keeps text indented when wrapped
vim.opt.scrolloff = 8 -- sets num of screen line above and below cursor
vim.opt.sidescrolloff = 8 -- sets num of screen columns to left and right of cursor
vim.opt.guifont = "monospace:h17" -- the font used in graphical neovim applications
vim.opt.shortmess:append("c") -- controls behavior of certain messages that are displayed (reduce visual clutter)
vim.opt.spell = true -- turn on spell check
vim.opt.spelllang = "en_us" -- set language for spell checker to American English

-- set custom options for Delavie Media projects --

-- vim.opt.shiftwidth - the number of spaces inserted for each indentation
-- vim.opt.tabstop - the number of spaces for a tab

local function setDelavieMediaSettings()
    vim.opt.shiftwidth = 2
    vim.opt.tabstop = 2
end

local function setDefaultSettings()
    vim.opt.shiftwidth = 4
    vim.opt.tabstop = 4
end

if IsDelavieMediaProject() then
    setDelavieMediaSettings()
else
    setDefaultSettings()
end

-- cmd --
vim.cmd("set whichwrap+=<,>,[,],h,l")
vim.cmd([[set iskeyword+=-]])

-- g --
vim.g.mapleader = " " -- set leader key
vim.g.maplocalleader = " " -- set local leader key
vim.g.skip_ts_context_commentstring_module = true
vim.g.db_ui_execute_on_save = 0

-- WSL clipboard --
if vim.fn.has("wsl") == 1 then
    vim.g.clipboard = {
        name = "WslClipboard",
        copy = {
            ["+"] = "clip.exe",
            ["*"] = "clip.exe",
        },
        paste = {
            ["+"] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
            ["*"] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
        },
    }
end
