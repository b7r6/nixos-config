-- ───────────────────────────────────────────────────────────────────
--                       // plugins // the lean NvChad-inspired set //
-- ───────────────────────────────────────────────────────────────────
--
-- Eight plugins, chosen not accumulated. Theme, statusline, LSP, and
-- completion are all core-owned (init.lua + lua/hypermodern/) — this
-- layer is navigation, treesitter, and git decoration only, and the
-- session survives its total absence.

return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    main = "nvim-treesitter.configs",
    opts = {
      auto_install = true,
      highlight = { enable = true },
      indent = { enable = true },
    },
  },

  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = "Telescope",
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "Live grep" },
      { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "Help" },
      { "<leader>fr", "<cmd>Telescope oldfiles<CR>", desc = "Recent files" },
      { "<leader>fd", "<cmd>Telescope diagnostics<CR>", desc = "Diagnostics" },
      { "gd", "<cmd>Telescope lsp_definitions<CR>", desc = "Definitions" },
      { "grr", "<cmd>Telescope lsp_references<CR>", desc = "References" },
      { "<leader>fs", "<cmd>Telescope lsp_document_symbols<CR>", desc = "Symbols" },
    },
    opts = {
      defaults = {
        prompt_prefix = "▞ ",
        selection_caret = "▖ ",
        borderchars = { "─", "│", "─", "│", "┌", "┐", "┘", "└" },
        sorting_strategy = "ascending",
        layout_config = { prompt_position = "top" },
      },
    },
  },

  {
    "stevearc/oil.nvim",
    keys = { { "<leader>e", "<cmd>Oil<CR>", desc = "Edit directory" } },
    cmd = "Oil",
    opts = { view_options = { show_hidden = true } },
  },

  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "▁" },
        topdelete = { text = "▔" },
        changedelete = { text = "▎" },
      },
      on_attach = function(buf)
        local gs = require("gitsigns")
        vim.keymap.set("n", "]h", gs.next_hunk, { buffer = buf, desc = "Next hunk" })
        vim.keymap.set("n", "[h", gs.prev_hunk, { buffer = buf, desc = "Prev hunk" })
        vim.keymap.set("n", "<leader>hs", gs.stage_hunk, { buffer = buf, desc = "Stage hunk" })
        vim.keymap.set("n", "<leader>hr", gs.reset_hunk, { buffer = buf, desc = "Reset hunk" })
        vim.keymap.set("n", "<leader>hp", gs.preview_hunk, { buffer = buf, desc = "Preview hunk" })
        vim.keymap.set("n", "<leader>hb", gs.blame_line, { buffer = buf, desc = "Blame line" })
      end,
    },
  },

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = { preset = "helix", delay = 400 },
  },

  { "nvim-mini/mini.pairs", event = "InsertEnter", opts = {} },

  { "nvim-mini/mini.surround", event = "VeryLazy", opts = {} },
}
