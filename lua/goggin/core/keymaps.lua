local keymap = vim.keymap.set

-- Save File --

-- -- Normal Mode -- --
keymap("n", "<c-s>", "<cmd>lua vim.lsp.buf.format()<cr><cmd>w!<cr>", {
    desc = "Save File",
})

-- Quit --

-- -- Normal Mode -- --
keymap("n", "<leader>q", "<cmd>q<cr>", {
    desc = "Quit",
})

keymap("n", "<leader>Q", "<cmd>qa<cr>", {
    desc = "Quit All",
})

-- Remap Escape --

-- -- Insert Mode -- --
keymap("i", "jk", "<esc>", {
    desc = "Escape",
})

-- -- Visual Mode -- --
keymap("v", "jk", "<esc>", {
    desc = "Escape",
})

-- Stop Search --

-- -- Normal Mode -- --
keymap("n", "<leader>h", ":nohlsearch<CR>", {
    desc = "Stop Search",
})

-- Window --

-- -- Normal Mode -- --
keymap("n", "<leader>wv", "<cmd>vsplit<cr>", {
    desc = "Verticle Split",
})
keymap("n", "<leader>wh", "<cmd>split<cr>", {
    desc = "Horizontal Split",
})
keymap("n", "<leader>wc", "<c-w>c", {
    desc = "Close Window",
})
keymap("n", "-", "<cmd>vertical resize -5<cr>", {
    desc = "Decrease Window Width",
})
keymap("n", "=", "<cmd>vertical resize +5<cr>", {
    desc = "Increase Window Width",
})
keymap("n", "_", "<cmd>resize -5<cr>", {
    desc = "Decrease Window Height",
})
keymap("n", "+", "<cmd>resize +5<cr>", {
    desc = "Increase Window Height",
})

-- Focus --

-- -- Normal Mode -- --
keymap("n", "<c-h>", "<c-w>h", {
    desc = "Focus Split Left",
})
keymap("n", "<c-j>", "<c-w>j", {
    desc = "Focus Split Below",
})
keymap("n", "<c-k>", "<c-w>k", {
    desc = "Focus Split Above",
})
keymap("n", "<c-l>", "<c-w>l", {
    desc = "Focus Split Right",
})
-- Change --

-- -- Normal Mode -- --
keymap("n", "cc", '"_cc', {
    desc = "Change Line",
})
keymap("n", "cw", '"_cw', {
    desc = "Change Work",
})
keymap("n", "ci{", '"_ci{', {
    desc = "Change Inside {}",
})
keymap("n", "ci{", '"_ci{', {
    desc = "Change Inside {}",
})
keymap("n", "ci[", '"_ci[', {
    desc = "Change Inside []",
})
keymap("n", "ci<", '"_ci<', {
    desc = "Change Inside <>",
})
keymap("n", "ci(", '"_ci(', {
    desc = "Change Inside ()",
})
keymap("n", 'ci"', '"_ci"', {
    desc = 'Change Inside ""',
})
keymap("n", "ci`", '"_ci`', {
    desc = "Change Inside ``}",
})

-- -- Visual Mode -- --
keymap("v", "c", '"_c', {
    desc = "Change Selection",
})

-- Delete --

-- -- Normal Mode -- --
keymap("n", "dd", '"_dd', {
    desc = "Delete Line",
})
keymap("n", "d$", '"_d$', {
    desc = "Delete Rest of Line",
})
keymap("n", "dw", '"_dw', {
    desc = "Delete Word",
})
keymap("n", "x", '"_x', {
    desc = "Delete Character",
})

-- -- Visual Mode -- --
keymap("v", "d", '"_d', {
    desc = "Delete Selection",
})

-- Clipboard --

-- -- Normal Mode -- --
keymap("n", "<c-c>", "yy", {
    desc = "Copy",
})
keymap("n", "<c-v>", "p", {
    desc = "Paste",
})
keymap("n", "<c-x>", "yydd", {
    desc = "Cut",
})

-- -- Visual Mode -- --
keymap("v", "<c-c>", "y", {
    desc = "Copy",
})
keymap("v", "<c-v>", "p", {
    desc = "Paste",
})
keymap("v", "<c-x>", "ygvd", {
    desc = "Cut",
})

-- -- Insert Mode -- --
keymap("i", "<c-v>", "<c-r>+", {
    desc = "Paste",
})

-- Select --

-- -- Normal Mode -- --
keymap("n", "<c-a>", "ggVG", {
    desc = "Select All",
})

-- Buffer --

-- -- Normal Mode -- --
keymap("n", "<s-h>", "<cmd>bprevious<cr>", {
    desc = "Previous Buffer",
})
keymap("n", "<s-l>", "<cmd>bnext<cr>", {
    desc = "Next Buffer",
})
keymap("n", "<leader>c", "<cmd>bp<bar>sp<bar>bn<bar>bd<cr>", {
    desc = "Close Buffer",
})
keymap("n", "<leader>C", "<cmd>bufdo bd<cr>", {
    desc = "Close All Buffers",
})

-- Undotree --

-- -- Normal Mode -- --
keymap("n", "<leader>u", "<cmd>UndotreeToggle<cr>", {
    desc = "Toggle Undotree",
})

-- Git --

-- Normal Mode -- --
keymap("n", "<leader>gg", "<cmd>Git<cr>", {
    desc = "Open Fugitive",
})

-- Toggle Term --

-- -- Normal Mode -- --
keymap("n", "<leader>t", "<cmd>ToggleTerm<cr>", {
    desc = "Toggle Terminal",
})
keymap("n", "<leader>tt", "<cmd>ToggleTerm direction=tab<cr>", {
    desc = "Toggle Terminal in New Tab",
})
keymap("n", "<leader>tf", "<cmd>ToggleTerm direction=float<cr>", {
    desc = "Toggle Floating Terminal",
})
keymap("n", "<leader>tv", "<cmd>ToggleTerm size=80 direction=vertical<cr>", {
    desc = "Toggle Verticle Terminal",
})
keymap("n", "<leader>th", "<cmd>ToggleTerm direction=horizontal<cr>", {
    desc = "Toggle Horizontal Terminal",
})

-- Vim REST Console --

-- -- Normal Mode -- --
keymap("n", "<leader>xr", "<cmd>call VrcQuery()<cr>", {
    desc = "Execute REST Query",
})

-- SQL --

-- -- Normal Mode -- --
keymap("n", "<leader>dd", "<cmd>DBUIToggle<cr>", {
    desc = "Toggle DB UI",
})
keymap("n", "<leader>df", "<cmd>DBUIFindBuffer<cr>", {
    desc = "Add Buffer to DB UI Queries",
})
