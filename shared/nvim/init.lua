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

--
-- elm
--

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

autocmd("BufWritePre", {
  pattern = "*.elm",
  callback = function()
    vim.lsp.buf.format()
  end
})

--
-- gren
--

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

-- Diagnostics
vim.keymap.set('n', '<Leader>do', '<cmd>Telescope diagnostics bufnr=0<cr>') -- [o]pen (file)
vim.keymap.set('n', '<Leader>dO', '<cmd>Telescope diagnostics<cr>')         -- [O]pen (all)
vim.keymap.set('n', '<Leader>dn', vim.diagnostic.goto_next)                 -- [n]ext
vim.keymap.set('n', '<Leader>dp', vim.diagnostic.goto_prev)                 -- [p]rev

-- LSP
vim.keymap.set('n', '<Leader>la', vim.lsp.buf.code_action)                    -- [a]ction
vim.keymap.set('n', '<Leader>lf', vim.lsp.buf.format)                         -- [f]ormat
vim.keymap.set('n', '<Leader>ld', '<cmd>Telescope lsp_definitions<cr>')       -- [d]efinitions
vim.keymap.set('n', '<Leader>lr', '<cmd>Telescope lsp_references<cr>')        -- [r]eferences
vim.keymap.set('n', '<Leader>ls', '<cmd>Telescope lsp_document_symbols<cr>')  -- [s]ymbols (file)
vim.keymap.set('n', '<Leader>lS', '<cmd>Telescope lsp_workspace_symbols<cr>') -- [s]ymbols (all)

-- Git
vim.keymap.set('n', '<Leader>gc', '<cmd>Telescope git_bcommits<cr>')        -- [c]ommits (file)
vim.keymap.set('v', '<Leader>gc', '<cmd>Telescope git_bcommits_range<cr>')  -- [c]ommits (selection)
vim.keymap.set('n', '<Leader>gC', '<cmd>Telescope git_commits<cr>')         -- [C]ommits (all)
vim.keymap.set('n', '<Leader>gb', '<cmd>Telescope git_branches<cr>')        -- [b]ranches
vim.keymap.set('n', '<Leader>gs', '<cmd>Telescope git_status<cr>')          -- [s]status

-- Vim
vim.keymap.set('n', '<Leader>vs', '<cmd>Telescope spell_suggest<cr>') -- [s]pelling suggestions
vim.keymap.set('n', '<Leader>vm', '<cmd>Telescope spell_suggest<cr>') -- [m]arks
vim.keymap.set('n', '<Leader>vr', '<cmd>Telescope spell_suggest<cr>') -- [r]egisters
