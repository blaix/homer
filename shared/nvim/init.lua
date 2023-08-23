vim.g.mapleader = ' '

vim.opt.undofile = true
vim.opt.number = true

-- Installed via home manager
vim.cmd [[colorscheme dracula]]

-- Ignore case in search
-- unless search contains an uppercase
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Tabs
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
