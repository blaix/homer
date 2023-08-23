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

--
-- PLUGIN CONFIGS
-- Note: Plugins installed via home manager.
--

-- telescope-file-browser
vim.api.nvim_set_keymap(
   "n",
   "<leader>ff",
   "<cmd>lua require 'telescope'.extensions.file_browser.file_browser()<CR>",
   {noremap = true}
)
