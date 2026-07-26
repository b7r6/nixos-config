-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                       // hypermodern // nvim // ono-sendai // 211° //
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- Portable-first: this directory is the config, wherever it lands —
-- git clone onto any box and `nvim` works. Nix pre-provides the editor
-- and PATH-resolved language servers; NOTHING here depends on it.
--
-- Degradation ladder, by construction:
--   zero plugins        → theme engine, statusline, LSP, keymaps all live
--   no network          → lazy.nvim bootstrap skips cleanly (or set
--                         HYPERMODERN_NVIM_NO_NET=1 to never try)
--   no wintermute state → committed default vector (carbon 211/201)
--
-- The theme is the CI-pinned fifth implementation of the palette math
-- (lua/hypermodern/palette.lua, checks.ono-sendai-parity), driven live
-- by the wintermute daemon via :OnoSendaiHero/:OnoSendaiAxis/:OnoSendaiSync.

-- ── options ────────────────────────────────────────────────────────

vim.g.mapleader = " "
vim.g.maplocalleader = ","

local o = vim.o
o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.cursorline = true
o.termguicolors = true
o.undofile = true
o.ignorecase = true
o.smartcase = true
o.splitright = true
o.splitbelow = true
o.updatetime = 250
o.timeoutlen = 400
o.scrolloff = 8
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true
o.wrap = false
o.mouse = "a"
o.completeopt = "menuone,noselect,popup"
o.pumheight = 12
o.shortmess = o.shortmess .. "cI"
o.fillchars = "eob: ,vert:│"
o.list = true
o.listchars = "tab:  ,trail:·,nbsp:␣"
-- Blinking block in every mode; in the TUI this compiles to DECSCUSR
-- escapes (multiplexer passes through). Millisecond values don't survive
-- translation — nonzero params just select the blinking variant.
o.guicursor = "a:block-blinkwait500-blinkon500-blinkoff500"
vim.schedule(function() o.clipboard = "unnamedplus" end)

-- ── keymaps (plugin-free layer) ────────────────────────────────────

local map = vim.keymap.set
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Terminal → normal mode" })
-- direction-first hjkl, same letters as hyprland/zellij/emacs; bare
-- C-hjkl is free here (zellij owns the C-o prefix one layer down)
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window up" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })
map("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, { desc = "Prev diagnostic" })
map("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, { desc = "Next diagnostic" })
map("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Diagnostics → loclist" })

-- ── autocmds ───────────────────────────────────────────────────────

local aug = vim.api.nvim_create_augroup("hypermodern", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  group = aug,
  callback = function() vim.hl.on_yank({ timeout = 120 }) end,
})
vim.api.nvim_create_autocmd("BufReadPost", {
  group = aug,
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lines = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= lines then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- ── LSP: PATH-resolved servers, builtin completion ─────────────────
-- Servers come from PATH (nix, direnv devshell, or the distro — the
-- config doesn't care). Absent binary = silently not enabled.

vim.api.nvim_create_autocmd("LspAttach", {
  group = aug,
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
    end
    map("n", "<leader>ca", vim.lsp.buf.code_action, { buffer = ev.buf, desc = "Code action" })
    map("n", "<leader>rn", vim.lsp.buf.rename, { buffer = ev.buf, desc = "Rename symbol" })
    map("n", "<leader>fm", function() vim.lsp.buf.format({ async = true }) end,
      { buffer = ev.buf, desc = "Format buffer" })
  end,
})

local servers = {
  nixd = { cmd = { "nixd" }, filetypes = { "nix" } },
  lua_ls = {
    cmd = { "lua-language-server" },
    filetypes = { "lua" },
    settings = { Lua = { runtime = { version = "LuaJIT" }, workspace = { checkThirdParty = false } } },
  },
  clangd = { cmd = { "clangd" }, filetypes = { "c", "cpp", "cuda" } },
  rust_analyzer = { cmd = { "rust-analyzer" }, filetypes = { "rust" } },
  basedpyright = { cmd = { "basedpyright-langserver", "--stdio" }, filetypes = { "python" } },
  ts_ls = {
    cmd = { "typescript-language-server", "--stdio" },
    filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
  },
  bashls = { cmd = { "bash-language-server", "start" }, filetypes = { "sh", "bash" } },
  yamlls = { cmd = { "yaml-language-server", "--stdio" }, filetypes = { "yaml" } },
  dhall_lsp = { cmd = { "dhall-lsp-server" }, filetypes = { "dhall" } },
}
for name, cfg in pairs(servers) do
  if vim.fn.executable(cfg.cmd[1]) == 1 then
    cfg.root_markers = { ".git", "flake.nix" }
    vim.lsp.config(name, cfg)
    vim.lsp.enable(name)
  end
end

-- ── theme + statusline (zero-plugin, always on) ────────────────────

require("hypermodern.theme").boot()
require("hypermodern.statusline").setup()

-- ── lazy.nvim: bootstrap if possible, degrade if not ───────────────

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  if vim.env.HYPERMODERN_NVIM_NO_NET == "1" or vim.fn.executable("git") ~= 1 then
    lazypath = nil
  else
    local out = vim.fn.system({
      "git", "clone", "--filter=blob:none", "--branch=stable",
      "https://github.com/folke/lazy.nvim.git", lazypath,
    })
    if vim.v.shell_error ~= 0 then
      vim.notify("hypermodern: lazy.nvim bootstrap failed (offline?) — plugin-free session\n" .. out,
        vim.log.levels.WARN)
      lazypath = nil
    end
  end
end
if lazypath then
  vim.opt.rtp:prepend(lazypath)
  local ok, err = pcall(function()
    require("lazy").setup("plugins", {
      install = { colorscheme = { "hypermodern" } },
      change_detection = { notify = false },
      ui = { border = "single" },
    })
  end)
  if not ok then
    vim.notify("hypermodern: lazy setup failed — plugin-free session\n" .. tostring(err),
      vim.log.levels.WARN)
  end
end
