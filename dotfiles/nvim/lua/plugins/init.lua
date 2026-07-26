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
    -- the MAIN-branch rewrite: no more nvim-treesitter.configs, no more
    -- module-level enable flags — setup() + vim.treesitter.start() per
    -- buffer, parsers installed on demand. Everything pcall'd: a box
    -- without a C compiler degrades to plain highlighting, silently.
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      local ts = require("nvim-treesitter")
      ts.setup({})
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("hypermodern-treesitter", { clear = true }),
        callback = function(ev)
          local lang = vim.treesitter.language.get_lang(vim.bo[ev.buf].filetype)
          if not lang then return end
          if pcall(vim.treesitter.start, ev.buf, lang) then
            vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
            return
          end
          local ok, task = pcall(ts.install, lang)
          if ok and task and task.await then
            task:await(function()
              pcall(vim.treesitter.start, ev.buf, lang)
            end)
          end
        end,
      })
      -- catch up buffers whose FileType already fired before we loaded.
      -- ONLY those: exec'ing FileType on a not-yet-detected buffer sets
      -- did_filetype, and the runtime's later `setf` no-ops against it —
      -- a blanket retrigger here silently killed ALL filetype detection.
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype ~= "" then
          vim.api.nvim_exec_autocmds("FileType",
            { group = "hypermodern-treesitter", buffer = buf })
        end
      end
    end,
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
