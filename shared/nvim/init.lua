---------------------------------------------------------------------
-- Basic settings
---------------------------------------------------------------------

vim.g.mapleader = ' '

-- No wrapping by default
vim.opt.wrap = false

-- Keep undo history when closing file
vim.opt.undofile = true

-- Show line numbers
vim.opt.number = true

-- Highlight current line
vim.opt.cursorline = true

-- Use number column for diagnostics, etc.
-- (so everything doesn't jump around)
vim.opt.signcolumn = "number"

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

-- https://github.com/vimwiki/vimwiki/
vim.g.vimwiki_folding = 'expr' -- fold sections and code blocks
vim.g.vimwiki_list = {{
  path = "~/Sync/Wiki",
  path_html = "~/Sync/Wiki/html/",
  syntax = "markdown", 
  ext = ".md",
  custom_wiki2html = "vimwiki_markdown",
}}

-- https://github.com/nvim-lualine/lualine.nvim#configuring-lualine-in-initvim
require("lualine").setup({
  options = {
    icons_enabled = true,
    theme = 'auto',
    component_separators = { left = '', right = ''},
    section_separators = { left = '', right = ''},
    disabled_filetypes = {
      statusline = {},
      winbar = {},
    },
    ignore_focus = {},
    always_divide_middle = true,
    globalstatus = false,
    refresh = {
      statusline = 1000,
      tabline = 1000,
      winbar = 1000,
    }
  },
  sections = {
    lualine_a = {'mode'},
    lualine_b = {'branch', 'diff', 'diagnostics'},
    lualine_c = {'filename', 'lsp_progress'},
    lualine_x = {'encoding', 'fileformat', 'filetype'},
    lualine_y = {'progress'},
    lualine_z = {'location'}
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {'filename'},
    lualine_x = {'location'},
    lualine_y = {},
    lualine_z = {}
  },
  tabline = {},
  winbar = {},
  inactive_winbar = {},
  extensions = {}
})


---------------------------------------------------------------------
-- LSP & Language Configs
---------------------------------------------------------------------

local autocmd = vim.api.nvim_create_autocmd

-- Completion with https://github.com/hrsh7th/nvim-cmp
local cmp = require("cmp")
cmp.setup({
  window = {
    completion = cmp.config.window.bordered(),
    documentation = cmp.config.window.bordered(),
  },
  mapping = cmp.mapping.preset.insert({
    ['<C-b>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<TAB>'] = cmp.mapping.select_next_item(),
  }),
  sources = cmp.config.sources({
    { name = 'nvim_lsp' },
  })
})

-- Borders for floating windows
local _border = "single"
vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(
  vim.lsp.handlers.hover, {
    border = _border
  }
)
vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(
  vim.lsp.handlers.signature_help, {
    border = _border
  }
)
vim.diagnostic.config{
  float={border=_border}
}

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
vim.keymap.set('n', '<Leader>dd', vim.diagnostic.open_float)                -- [d]iagnostic (show in floating window)
vim.keymap.set('n', '<Leader>dn', vim.diagnostic.goto_next)                 -- [n]ext
vim.keymap.set('n', '<Leader>dp', vim.diagnostic.goto_prev)                 -- [p]rev

-- LSP
vim.keymap.set('n', '<Leader>la', vim.lsp.buf.code_action)                    -- [a]ction
vim.keymap.set('n', '<Leader>lf', vim.lsp.buf.format)                         -- [f]ormat
vim.keymap.set('n', '<Leader>lh', vim.lsp.buf.hover)                          -- [h]over
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
vim.keymap.set('n', '<Leader>vm', '<cmd>Telescope marks<cr>')         -- [m]arks
vim.keymap.set('n', '<Leader>vr', '<cmd>Telescope registers<cr>')     -- [r]egisters
