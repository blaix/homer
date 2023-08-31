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
