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
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4

-- Default to no folds when opening file
vim.opt.foldlevelstart = 99

-- Always keep at least 5 lines under cursor when scrolling
vim.opt.scrolloff = 5

-- Subtle border at the 80th column
vim.opt.colorcolumn = "80"


---------------------------------------------------------------------
-- Plugin configs
-- Plugins are installed via nix home manager. See shared/home.nix
---------------------------------------------------------------------

require("nvim-tree").setup({})
require("neogit").setup({})
require("nvim-treesitter").setup({
    highlight = {enable = true},
})

--
-- bufferline
-- https://github.com/akinsho/bufferline.nvim
--

vim.opt.termguicolors = true
require("bufferline").setup({
  options = {
    diagnostics = "nvim_lsp",
  },
})

--
-- vim-markdown-toc (table of contents generator)
-- https://github.com/mzlogin/vim-markdown-toc
--

-- Only show 1 level of headings
vim.g.vmt_max_level = 2

--
-- vimwiki
-- https://github.com/vimwiki/vimwiki/
--

vim.g.vimwiki_list = {{
  path = "~",
  syntax = "markdown", 
  ext = ".md",
}}

-- Custom folding copied from :help vimwiki
-- Doesn't fold last blank line before a header.
vim.g.vimwiki_folding = "custom"
vim.cmd([[
  function! VimwikiFoldLevelCustom(lnum)
    let pounds = strlen(matchstr(getline(a:lnum), '^#\+'))
    if (pounds)
      return '>' . pounds  " start a fold level
    endif
    if getline(a:lnum) =~? '\v^\s*$'
      if (strlen(matchstr(getline(a:lnum + 1), '^#\+')))
        return '-1' " don't fold last blank line before header
      endif
    endif
    return '=' " return previous fold level
  endfunction
  augroup VimrcAuGroup
    autocmd!
    autocmd FileType vimwiki setlocal foldmethod=expr |
      \ setlocal foldenable | set foldexpr=VimwikiFoldLevelCustom(v:lnum)
  augroup END
]])

--
-- nvim-lualine (custom status line)
-- https://github.com/nvim-lualine/lualine.nvim#configuring-lualine-in-initvim
--

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

vim.lsp.set_log_level("debug")

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

-------------------------------------
-- TODO: move below to ftplugins?
-------------------------------------

--
-- elm
--

vim.lsp.enable("elmls")

autocmd("BufWritePre", {
  pattern = "*.elm",
  callback = function()
    vim.lsp.buf.format()
  end
})

---
-- gren
--

-- Setup gren language server
require('lspconfig.configs').grenls = {
  default_config = {
    cmd = { 'gren-language-server-unofficial' },
    filetypes = { 'gren' },
    root_dir = require('lspconfig.util').root_pattern('gren.json', '.git'),
    settings = {
      grenPath = 'gren',
      grenFormatPath = 'builtin',
    },
  },
}

require('lspconfig').grenls.setup({})

autocmd("FileType", {
  pattern = "gren",
  callback = function(args)
    vim.opt.tabstop = 4
    vim.opt.shiftwidth = 4
    
    -- enable mae's treesitter for syntax highlighting
    vim.treesitter.start(args.buf, "gren") 
  end
})

--
-- html
--

autocmd("BufEnter", {
  pattern = "*.html",
  callback = function()
    vim.opt.tabstop = 2
    vim.opt.shiftwidth = 2
  end
})

--
-- js
--

autocmd("BufEnter", {
  pattern = "*.js",
  callback = function()
    vim.opt.tabstop = 2
    vim.opt.shiftwidth = 2
  end
})

--
-- json
--

autocmd("BufEnter", {
  pattern = "*.json",
  callback = function()
    vim.opt.tabstop = 2
    vim.opt.shiftwidth = 2
  end
})

--
-- nix
--

autocmd("BufEnter", {
  pattern = "*.nix",
  callback = function()
    vim.opt.tabstop = 2
    vim.opt.shiftwidth = 2
  end
})

--
-- rust
--

vim.lsp.enable("rust_analyzer")

autocmd("BufWritePre", {
  pattern = "*.rs",
  callback = function()
    vim.lsp.buf.format()
  end
})

--
-- ts
--

autocmd("BufEnter", {
  pattern = "*.ts",
  callback = function()
    vim.opt.tabstop = 2
    vim.opt.shiftwidth = 2
  end
})

---------------------------------------------------------------------
-- Mappings
-- https://neovim.io/doc/user/lua-guide.html#lua-guide-mappings-set
---------------------------------------------------------------------

-- double space to save
vim.keymap.set('n', '<Leader><Leader>', '<cmd>w<cr>')

-- a: append stuff
-- i: insert stuff
vim.keymap.set('n', '<Leader>id', 'i<c-r>=strftime("%F")<cr><esc>') -- [i]nsert [d]date (YYYY-MM-DD)
vim.keymap.set('n', '<Leader>ad', 'a<c-r>=strftime("%F")<cr><esc>') -- [a]ppend [d]date (YYYY-MM-DD)

-- b: Bufferline: https://github.com/akinsho/bufferline.nvim
vim.keymap.set('n', '<Leader>bc', '<cmd>BufferLinePick<cr>')      -- [c]hoose tab
vim.keymap.set('n', '<Leader>bn', '<cmd>BufferLineCycleNext<cr>') -- [n]ext tab
vim.keymap.set('n', '<Leader>bp', '<cmd>BufferLineCyclePrev<cr>') -- [p]rev tab
vim.keymap.set('n', '<Leader>bo', '<cmd>%bd|e#|bd#<cr>') -- [o]nly this tab (close all others)
                                                         -- %db delete all buffers
                                                         -- e# edit last open buffer
                                                         -- bd# delete the No Name buffer that gets opened automatically
-- d: Diagnostics
vim.keymap.set('n', '<Leader>do', '<cmd>Telescope diagnostics bufnr=0<cr>') -- [o]pen (file)
vim.keymap.set('n', '<Leader>dO', '<cmd>Telescope diagnostics<cr>')         -- [O]pen (all)
vim.keymap.set('n', '<Leader>dd', vim.diagnostic.open_float)                -- [d]iagnostic (show in floating window)
vim.keymap.set('n', '<Leader>dn', vim.diagnostic.goto_next)                 -- [n]ext
vim.keymap.set('n', '<Leader>dp', vim.diagnostic.goto_prev)                 -- [p]rev

-- f: File navigation and search
vim.keymap.set('n', '<Leader>ff', '<cmd>Telescope find_files<cr>') -- [f]ind
vim.keymap.set('n', '<Leader>fe', '<cmd>NvimTreeToggle<cr>')       -- [e]xplore
vim.keymap.set('n', '<Leader>fs', '<cmd>Telescope live_grep<cr>')  -- [s]earch

-- g: Git
vim.keymap.set('n', '<Leader>gc', '<cmd>Telescope git_bcommits<cr>')        -- [c]ommits (file)
vim.keymap.set('v', '<Leader>gc', '<cmd>Telescope git_bcommits_range<cr>')  -- [c]ommits (selection)
vim.keymap.set('n', '<Leader>gC', '<cmd>Telescope git_commits<cr>')         -- [C]ommits (all)
vim.keymap.set('n', '<Leader>gb', '<cmd>Telescope git_branches<cr>')        -- [b]ranches
vim.keymap.set('n', '<Leader>gs', '<cmd>Telescope git_status<cr>')          -- [s]status

-- l: LSP
vim.keymap.set('n', '<Leader>la', vim.lsp.buf.code_action)                    -- [a]ction
vim.keymap.set('n', '<Leader>lf', vim.lsp.buf.format)                         -- [f]ormat
vim.keymap.set('n', '<Leader>lh', vim.lsp.buf.hover)                          -- [h]over
vim.keymap.set('n', '<Leader>ld', '<cmd>Telescope lsp_definitions<cr>')       -- [d]efinitions
vim.keymap.set('n', '<Leader>lr', '<cmd>Telescope lsp_references<cr>')        -- [r]eferences
vim.keymap.set('n', '<Leader>ls', '<cmd>Telescope lsp_document_symbols<cr>')  -- [s]ymbols (file)
vim.keymap.set('n', '<Leader>lS', '<cmd>Telescope lsp_workspace_symbols<cr>') -- [s]ymbols (all)

-- v: Vim
vim.keymap.set('n', '<Leader>vs', '<cmd>Telescope spell_suggest<cr>') -- [s]pelling suggestions
vim.keymap.set('n', '<Leader>vm', '<cmd>Telescope marks<cr>')         -- [m]arks
vim.keymap.set('n', '<Leader>vr', '<cmd>Telescope registers<cr>')     -- [r]egisters
