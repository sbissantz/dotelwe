-- bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
local lazyrepo = "https://github.com/folke/lazy.nvim.git"
local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
if vim.v.shell_error ~= 0 then
  vim.api.nvim_echo({
    { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
    { out, "WarningMsg" },
    { "\nPress any key to exit..." },
  }, true, {})
  vim.fn.getchar()
  os.exit(1)
end
end
vim.opt.rtp:prepend(lazypath)

-- make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
-- This is also a good place to setup other settings (vim.opt)

-- ================================
-- keymap and leader settings
-- ================================

-- map leaders first
vim.g.mapleader = ";"        -- main leader key
vim.g.maplocalleader = ","  -- local leader key

-- toggle between dark/light with <leader>tb
vim.keymap.set("n", "<leader>tb", function()
vim.o.background = (vim.o.background == "dark") and "light" or "dark"
pcall(function()
  require("lualine").refresh()
end)
end, { desc = "Toggle background (light/dark)" })

-- ================================
-- general editing settings
-- ================================
vim.opt.ignorecase = true                -- searches are case-insensitive
vim.opt.hlsearch = true                  -- highlight all search matches
vim.opt.number = true                    -- show line numbers
vim.opt.number = true                    -- show relative line numbers
vim.opt.autoindent = true                -- auto-indent new lines
vim.opt.tabstop = 4                      -- number of spaces a tab counts for
vim.opt.softtabstop = 4                  -- backspace deletes proper spaces
vim.opt.shiftwidth = 4                   -- width for auto-indents
vim.opt.expandtab = true                 -- convert tabs to spaces
vim.opt.mouse = "v"                      -- enable mouse (middle-click paste)
--vim.opt.clipboard = "unnamedplus"        -- use system clipboard by default
vim.opt.colorcolumn = "80"               -- show a vertical line at 80 chars
vim.opt.spelllang = { "en_us", "de_de" } -- spell checking languages

-- ================================
-- filetype & syntax
-- ================================
vim.cmd("filetype plugin indent on")        -- enable filetype detection and indentation
vim.cmd("syntax on")                        -- enable syntax highlighting

-- ================================
-- command-line & completion
-- ================================
vim.opt.wildmode = { "longest", "list" }   -- bash-like tab completions

-- ================================
-- optional / visual enhancements
-- ================================
vim.opt.showmatch = true                     -- highlight matching brackets
-- vim.opt.compatible = false                -- unnecessary in Neovim; always off

-- ================================
-- plug-in manager (lazy nvim)
-- ================================

require("lazy").setup({
spec = {

  -- Colorscheme
  { "wtfox/jellybeans.nvim", 
    lazy = false,
    priority = 1100,
    opts = {
      transparent = false,
      italics = true,
      bold = true,
      flat_ui = true,
      background = {
        dark = "jellybeans",
        light = "jellybeans_light",
      },
      plugins = {
        all = false,
        auto = true,
      },
    },
    config = function(_, opts)
      require("jellybeans").setup(opts)
      vim.cmd.colorscheme("jellybeans")
    end,
  },

  -- osc52 clipboard integration 
  -- Normal yanks (`y`) stay local on the remote machine
  -- <leader> y: in visual mode copies selection to the macOS clipboard
  -- <leader> y: in normal mode copies entire buffer to the macOS clipboard
  { "ojroques/nvim-osc52",
    config = function()
      local osc52 = require("osc52")
      osc52.setup({ max_length = 0, silent = true, trim = false })

      -- Visual select → ;y
      vim.keymap.set("v", "<leader>y", osc52.copy_visual, { desc = "OSC52 copy selection" })

      -- Whole file → ;Y
      vim.keymap.set("n", "<leader>Y", function()
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        osc52.copy(table.concat(lines, "\n"))
      end, { desc = "OSC52 copy whole file" })
    end,
  },

  -- comment quickly
  { "preservim/nerdcommenter", lazy = false },

  -- surround quickly
  { "tpope/vim-surround", lazy = false },

  -- parenthesis matching
  { "jiangmiao/auto-pairs"},

  -- grammar and spelling
  { "rhysd/vim-grammarous"},

  -- stan syntax highlighting
  { "eigenfoo/stan-vim" },

  -- better syntax support
  { "sheerun/vim-polyglot" },

  -- github copilot 
  { "github/copilot.vim", lazy = false, enabled = false},  -- disabled

  -- NVim-R (old school)
  -- important: does only work under R 4.4 (so module load R/4.4)
  { "jalvesaq/Nvim-R",
    ft = { "r", "rmd", "quarto" },

    -- pin to old verion v0.9.11 (has R_tmux_split)
    commit = "4e9981e",

    config = function()
      vim.g.R_in_buffer = 0
      vim.g.R_tmux_split = 1

      vim.keymap.set("n", "<localleader>rf", "<Plug>RStart", { remap = true, silent = true })
      vim.keymap.set("n", "<Space>", "<Plug>RDSendLine", { remap = true, silent = true })
      vim.keymap.set("v", "<Space>", "<Plug>RDSendSelection", { remap = true, silent = true })
    end,
  },
},
-- Configure any other settings here. See the documentation for more details.
-- colorscheme that will be used when installing plugins.
install = { colorscheme = { "habamax" } },
-- automatically check for plugin updates
checker = { enabled = true },
})
