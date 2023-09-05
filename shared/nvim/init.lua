---------------------------------------------------------------------
-- Basic settings
---------------------------------------------------------------------

vim.g.mapleader = ' '

-- Keep undo history when closing file
vim.opt.undofile = true

-- Show line numbers
vim.opt.number = true

-- Highlight current line
vim.opt.cursorline = true

-- Set theme (plugins installed via nix)
vim.cmd [[colorscheme catppuccin]]

-- Ignore case in search
vim.opt.ignorecase = true
-- unless search contains an uppercase
vim.opt.smartcase = true

-- Tabs
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2


---------------------------------------------------------------------
-- Plugin configs
-- Plugins are installed via nix home manager. See shared/home.nix
---------------------------------------------------------------------

require("nvim-tree").setup()


---------------------------------------------------------------------
-- Language Configs
---------------------------------------------------------------------

local autocmd = vim.api.nvim_create_autocmd

-- elm
autocmd("BufRead", {
  pattern = "*.elm",
  callback = function()
    local root_dir = vim.fs.dirname(
      vim.fs.find({'elm.json'}, { upward = true })[1]
    )
    local client = vim.lsp.start({
      name = 'elmls',
      cmd = {'elm-language-server'},
      root_dir = root_dir,
    })
    vim.lsp.buf_attach_client(0, client)
    vim.opt.tabstop = 4
    vim.opt.shiftwidth = 4
  end
})

-- gren
autocmd("BufRead", {
  pattern = "*.gren",
  callback = function()
    vim.opt.tabstop = 4
    vim.opt.shiftwidth = 4
  end
})


---------------------------------------------------------------------
-- Mappings
-- https://neovim.io/doc/user/lua-guide.html#lua-guide-mappings-set
---------------------------------------------------------------------

-- File navigation and search
vim.keymap.set('n', '<Leader>ff', '<cmd>Telescope find_files<cr>') -- [f]ind
vim.keymap.set('n', '<Leader>fe', '<cmd>NvimTreeToggle<cr>')       -- [e]xplore
vim.keymap.set('n', '<Leader>fs', '<cmd>Telescope live_grep<cr>')  -- [s]earch
