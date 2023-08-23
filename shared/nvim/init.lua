vim.g.mapleader = ' '

vim.opt.undofile = true
vim.opt.number = true

-- Themes plugins installed via home manager
vim.cmd [[colorscheme catppuccin]]

-- Ignore case in search
-- unless search contains an uppercase
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Tabs
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2

---------------------------------------------------------------------
-- Mappings
-- https://neovim.io/doc/user/lua-guide.html#lua-guide-mappings-set
---------------------------------------------------------------------

-- File and string search
vim.keymap.set('n', '<Leader>ff', '<cmd>Telescope find_files<cr>')
vim.keymap.set('n', '<Leader>fs', '<cmd>Telescope live_grep<cr>')
