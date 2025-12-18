-- Bootstrap lazy.nvim
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

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
-- This is also a good place to setup other settings (vim.opt)

-- Map leaders first
vim.g.mapleader = ";"        -- main leader key
vim.g.maplocalleader = ","  -- local leader key

-- ================================
-- General Editing Settings
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
vim.opt.clipboard = "unnamedplus"        -- use system clipboard by default
vim.opt.colorcolumn = "80"               -- show a vertical line at 80 chars
vim.opt.spelllang = { "en_us", "de_de" } -- spell checking languages

-- ================================
-- Filetype & Syntax
-- ================================
vim.cmd("filetype plugin indent on")        -- enable filetype detection and indentation
vim.cmd("syntax on")                        -- enable syntax highlighting

-- ================================
-- Command-line & Completion
-- ================================
vim.opt.wildmode = { "longest", "list" }   -- bash-like tab completions

-- ================================
-- Optional / Visual Enhancements
-- ================================
vim.opt.showmatch = true                     -- highlight matching brackets
-- vim.opt.compatible = false                -- unnecessary in Neovim; always off


-- Setup lazy.nvim
require("lazy").setup({
  spec = {
      -- Colorscheme
    { "rafi/awesome-vim-colorschemes", 
      lazy = false,
      init = function() 
        -- Set the colorscheme to jellybeans
        vim.cmd("colorscheme jellybeans") 
      end 
    },
  
    -- Comment quickly
    { "preservim/nerdcommenter", lazy = false },

    -- Surround quickly
    { "tpope/vim-surround", lazy = false },

    -- Parenthesis matching
    { "jiangmiao/auto-pairs"},

    -- Grammar and spelling
    { "rhysd/vim-grammarous"},

    -- Stan syntax highlighting
    { "eigenfoo/stan-vim" },

    -- Better syntax support
    { "sheerun/vim-polyglot" },

	-- GitHub Copilot
	{ "github/copilot.vim", lazy = false, },

   --Latex
    {
      "lervag/vimtex",
      lazy = false,
      init = function ()
        vim.g.vimtex_compiler_latexmk_engines = {
          _ = "-xelatex", -- use xelatex as the default engine
          --_ = "-pdf -pdflatex=pdflatex" 
          --_ = "-lualatex", 
        }
        --vim.g.vimtex_view_method = "skim"
        vim.g.vimtex_syntax_enabled = 0
      end
    },

    -- R programming 
    { "R-nvim/R.nvim",
     -- Only required if you also set defaults.lazy = true 
    lazy = false,
    -- R.nvim is still young and we may make some breaking changes from time
    -- to time (but also bug fixes all the time). If configuration stability
    -- is a high priority for you, pin to the latest minor version, but unpin
    -- it and try the latest version before reporting an issue:
    -- version = "~0.1.0"
    config = function()
        -- Create a table with the options to be passed to setup()
        ---@type RConfigUserOpts
        local opts = {
            hook = {
                on_filetype = function()
                    vim.api.nvim_buf_set_keymap(0, "n", "<Enter>", "<Plug>RDSendLine", {})
                    vim.api.nvim_buf_set_keymap(0, "v", "<Enter>", "<Plug>RSendSelection", {})
                end
            },
            R_args = {"--quiet", "--no-save"},
            min_editor_width = 72,
            rconsole_width = 78,
            objbr_mappings = { -- Object browser keymap
                c = 'class', -- Call R functions
                ['<localleader>gg'] = 'head({object}, n = 15)', -- Use {object} notation to write arbitrary R code.
                v = function()
                    -- Run lua functions
                    require('r.browser').toggle_view()
                end
            },
            disable_cmds = {
                "RClearConsole",
                "RCustomStart",
                "RSPlot",
                "RSaveClose",
            },
        }
        -- Check if the environment variable "R_AUTO_START" exists.
        -- If using fish shell, you could put in your config.fish:
        -- alias r "R_AUTO_START=true nvim"
        if vim.env.R_AUTO_START == "true" then
            opts.auto_start = "on startup"
            opts.objbr_auto_start = true
        end
        require("r").setup(opts)
    end,
    },
    -- R completion
    { "R-nvim/cmp-r",
      {
          "hrsh7th/nvim-cmp",
          config = function()
              require("cmp").setup({ sources = {{ name = "cmp_r" }}})
              require("cmp_r").setup({})
          end,
      },
    },
    -- R syntax highlighting
    { "nvim-treesitter/nvim-treesitter",
    run = ":TSUpdate",
    config = function ()
        require("nvim-treesitter.configs").setup({
            ensure_installed = { "markdown", "markdown_inline", "r", "rnoweb", "yaml", "latex", "csv" },
            highlight = { enable = true },
        })
    end
  },
},
  -- Configure any other settings here. See the documentation for more details.
  -- colorscheme that will be used when installing plugins.
  install = { colorscheme = { "habamax" } },
  -- automatically check for plugin updates
  checker = { enabled = true },
})

-- ================================
-- Neovide-specific settings
-- ================================
--
-- https://neovide.dev/faq.html#how-can-i-dynamically-change-the-scale-at-runtime
--
if vim.g.neovide then

  -- GUI font
  vim.opt.guifont = "FiraCode Nerd Font:h11"

  -- Initial scale factor
  vim.g.neovide_scale_factor = 1.0
  local change_scale_factor = function(delta)
    vim.g.neovide_scale_factor = vim.g.neovide_scale_factor * delta
  end
  -- Cmd + Shift + = → zoom in
  vim.keymap.set("n", "<D-+>", function()
    change_scale_factor(1.1)
  end)
  -- Cmd + - → zoom out
  vim.keymap.set("n", "<D-->", function()
    change_scale_factor(1/1.1)
  end)
  -- Cmd + 0 → reset zoom
  vim.keymap.set("n", "<D-0>", function()
    vim.g.neovide_scale_factor = 1.0
  end)
end
