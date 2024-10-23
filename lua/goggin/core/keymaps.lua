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

-- Tabs --

-- -- Normal Mode -- --
keymap("n", "<leader>tn", "<cmd>$tabnew<cr>", {
    desc = "New Tab",
})
keymap("n", "<leader>tc", "<cmd>tabclose<cr>", {
    desc = "Close Tab",
})
keymap("n", "<leader>tC", "<cmd>tabonly<cr>", {
    desc = "Close All Tab",
})
keymap("n", "<leader>th", "<cmd>-tabmove<cr>", {
    desc = "Move Tab Left",
})
keymap("n", "<leader>tl", "<cmd>+tabmove<cr>", {
    desc = "Move Tab Right",
})
keymap("n", "<leader>tm1", "<cmd>tabmove 1<cr>", {
    desc = "Move Tab To 1",
})
keymap("n", "<leader>tm2", "<cmd>tabmove 2<cr>", {
    desc = "Move Tab To 2",
})
keymap("n", "<leader>tm3", "<cmd>tabmove 3<cr>", {
    desc = "Move Tab To 3",
})
keymap("n", "<leader>tm4", "<cmd>tabmove 4<cr>", {
    desc = "Move Tab To 4",
})
keymap("n", "<leader>tm5", "<cmd>tabmove 5<cr>", {
    desc = "Move Tab To 5",
})
keymap("n", "<leader>tm6", "<cmd>tabmove 6<cr>", {
    desc = "Move Tab To 6",
})
keymap("n", "<leader>tm7", "<cmd>tabmove 7<cr>", {
    desc = "Move Tab To 7",
})
keymap("n", "<leader>tm8", "<cmd>tabmove 8<cr>", {
    desc = "Move Tab To 8",
})
keymap("n", "<leader>tm9", "<cmd>tabmove 9<cr>", {
    desc = "Move Tab To 9",
})
keymap("n", "<leader>t1", "<cmd>tabn 1<cr>", {
    desc = "Go To 1",
})
keymap("n", "<leader>t2", "<cmd>tabn 2<cr>", {
    desc = "Go To 2",
})
keymap("n", "<leader>t3", "<cmd>tabn 3<cr>", {
    desc = "Go To 3",
})
keymap("n", "<leader>t4", "<cmd>tabn 4<cr>", {
    desc = "Go To 4",
})
keymap("n", "<leader>t5", "<cmd>tabn 5<cr>", {
    desc = "Go To 5",
})
keymap("n", "<leader>t6", "<cmd>tabn 6<cr>", {
    desc = "Go To 6",
})
keymap("n", "<leader>t7", "<cmd>tabn 7<cr>", {
    desc = "Go To 7",
})
keymap("n", "<leader>t8", "<cmd>tabn 8<cr>", {
    desc = "Go To 8",
})
keymap("n", "<leader>t9", "<cmd>tabn 9<cr>", {
    desc = "Go To 9",
})
keymap("n", "<s-h>", "<cmd>-tabnext<cr>", {
    desc = "Previous Tab",
})
keymap("n", "<s-l>", "<cmd>+tabnext<cr>", {
    desc = "Next Tab",
})

-- Buffer --

-- -- Normal Mode -- --
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
keymap("n", "<leader><leader>", "<cmd>ToggleTerm<cr>", {
    desc = "Toggle Terminal",
})
keymap("n", "<leader>tt", "<cmd>ToggleTerm direction=tab<cr>", {
    desc = "Toggle Terminal in New Tab",
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
