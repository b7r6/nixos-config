-- ───────────────────────────────────────────────────────────────────
--             // theme engine // live wintermute channel // nvim //
-- ───────────────────────────────────────────────────────────────────
--
-- The in-editor face engine over lua/hypermodern/palette.lua (the
-- CI-pinned fifth implementation). Mirrors the emacs channel exactly:
--
--   :OnoSendaiHero N / :OnoSendaiAxis N   — wintermute's remote pokes
--   :OnoSendaiSync                        — read theme.state, apply, ack
--
-- The config never depends on the daemon: no state file means the
-- committed default vector (carbon, 211/201, facility). Every applied
-- generation is acknowledged into the wintermute ack ledger.

local palette = require("hypermodern.palette")

local M = {}

M.state = {
  hero = 211,
  axis = 201,
  family = "straylight",
  polarity = "dark",
  level = "carbon",
  ramp = 211,
  register = 1000, -- per-mille: affluent 0 … facility 1000
  generation = 0,
}

function M.compute()
  if M.state.polarity == "light" then
    return palette.compute_light(M.state.level, M.state.hero, M.state.axis, M.state.ramp)
  end
  return palette.compute_dark(M.state.level, M.state.hero, M.state.axis, M.state.family)
end

-- ── the face map ───────────────────────────────────────────────────

local function apply_highlights(p)
  local hl = function(group, spec) vim.api.nvim_set_hl(0, group, spec) end
  local dark = p.variant == "dark"

  -- chrome
  hl("Normal", { fg = p.base05, bg = p.base00 })
  hl("NormalFloat", { fg = p.base05, bg = p.base01 })
  hl("FloatBorder", { fg = p.base0C, bg = p.base01 })
  hl("FloatTitle", { fg = p.base0A, bg = p.base01, bold = true })
  hl("WinSeparator", { fg = p.base02 })
  hl("CursorLine", { bg = p.base01 })
  hl("CursorColumn", { bg = p.base01 })
  hl("ColorColumn", { bg = p.base01 })
  hl("LineNr", { fg = p.base03 })
  hl("CursorLineNr", { fg = p.base0A, bold = true })
  hl("SignColumn", { bg = p.base00 })
  hl("Visual", { bg = p.base02 })
  hl("Search", { fg = p.base00, bg = p.base09 })
  hl("IncSearch", { fg = p.base00, bg = p.base0A })
  hl("CurSearch", { fg = p.base00, bg = p.base0A })
  hl("MatchParen", { fg = p.base0A, bg = p.base02, bold = true })
  hl("Pmenu", { fg = p.base05, bg = p.base01 })
  hl("PmenuSel", { fg = p.base00, bg = p.base0C })
  hl("PmenuSbar", { bg = p.base02 })
  hl("PmenuThumb", { bg = p.base0C })
  hl("WildMenu", { fg = p.base00, bg = p.base0A })
  hl("StatusLine", { fg = p.base04, bg = p.base01 })
  hl("StatusLineNC", { fg = p.base03, bg = p.base01 })
  hl("TabLine", { fg = p.base04, bg = p.base01 })
  hl("TabLineSel", { fg = p.base0A, bg = p.base00, bold = true })
  hl("TabLineFill", { bg = p.base01 })
  hl("Folded", { fg = p.base04, bg = p.base01 })
  hl("FoldColumn", { fg = p.base03, bg = p.base00 })
  hl("NonText", { fg = p.base02 })
  hl("Whitespace", { fg = p.base02 })
  hl("EndOfBuffer", { fg = p.base01 })
  hl("SpecialKey", { fg = p.base03 })
  hl("Directory", { fg = p.base0D })
  hl("Title", { fg = p.base0A, bold = true })
  hl("ErrorMsg", { fg = p.base08 })
  hl("WarningMsg", { fg = p.base09 })
  hl("ModeMsg", { fg = p.base04 })
  hl("MoreMsg", { fg = p.base0C })
  hl("Question", { fg = p.base0C })
  hl("QuickFixLine", { bg = p.base02 })
  hl("TermCursor", { fg = p.base00, bg = p.base0A })

  -- syntax (classic groups; treesitter links through these by default)
  hl("Comment", { fg = p.base03, italic = true })
  hl("Constant", { fg = p.base09 })
  hl("String", { fg = p.base0B })
  hl("Character", { fg = p.base0B })
  hl("Number", { fg = p.base09 })
  hl("Boolean", { fg = p.base09 })
  hl("Float", { fg = p.base09 })
  hl("Identifier", { fg = p.base05 })
  hl("Function", { fg = p.base0D })
  hl("Statement", { fg = p.base0E })
  hl("Conditional", { fg = p.base0E })
  hl("Repeat", { fg = p.base0E })
  hl("Label", { fg = p.base0A })
  hl("Operator", { fg = p.base04 })
  hl("Keyword", { fg = p.base0E })
  hl("Exception", { fg = p.base08 })
  hl("PreProc", { fg = p.base0A })
  hl("Include", { fg = p.base0D })
  hl("Define", { fg = p.base0E })
  hl("Macro", { fg = p.base0A })
  hl("Type", { fg = p.base0A })
  hl("StorageClass", { fg = p.base0A })
  hl("Structure", { fg = p.base0A })
  hl("Typedef", { fg = p.base0A })
  hl("Special", { fg = p.base0C })
  hl("SpecialChar", { fg = p.base0F })
  hl("Delimiter", { fg = p.base04 })
  hl("Underlined", { fg = p.base0D, underline = true })
  hl("Todo", { fg = p.base0A, bg = p.base01, bold = true })
  hl("Error", { fg = p.base08 })

  -- treesitter refinements beyond the classic links
  hl("@variable", { fg = p.base05 })
  hl("@variable.builtin", { fg = p.base08 })
  hl("@variable.parameter", { fg = p.base05, italic = true })
  hl("@field", { fg = p.base05 })
  hl("@property", { fg = p.base05 })
  hl("@constructor", { fg = p.base0A })
  hl("@tag", { fg = p.base0E })
  hl("@tag.attribute", { fg = p.base0A })
  hl("@punctuation.bracket", { fg = p.base04 })
  hl("@punctuation.delimiter", { fg = p.base04 })
  hl("@markup.heading", { fg = p.base0A, bold = true })
  hl("@markup.raw", { fg = p.base0B })
  hl("@markup.link", { fg = p.base0D, underline = true })

  -- diagnostics
  hl("DiagnosticError", { fg = p.base08 })
  hl("DiagnosticWarn", { fg = p.base09 })
  hl("DiagnosticInfo", { fg = p.base0C })
  hl("DiagnosticHint", { fg = p.base04 })
  hl("DiagnosticUnderlineError", { sp = p.base08, undercurl = true })
  hl("DiagnosticUnderlineWarn", { sp = p.base09, undercurl = true })
  hl("DiagnosticUnderlineInfo", { sp = p.base0C, undercurl = true })
  hl("DiagnosticUnderlineHint", { sp = p.base04, undercurl = true })
  hl("LspReferenceText", { bg = p.base02 })
  hl("LspReferenceRead", { bg = p.base02 })
  hl("LspReferenceWrite", { bg = p.base02, underline = true })
  hl("LspInlayHint", { fg = p.base03, bg = p.base01 })

  -- diff / git
  hl("DiffAdd", { fg = p.base0B, bg = dark and p.base01 or p.base01 })
  hl("DiffChange", { fg = p.base09, bg = p.base01 })
  hl("DiffDelete", { fg = p.base08, bg = p.base01 })
  hl("DiffText", { fg = p.base0A, bg = p.base02 })
  hl("Added", { fg = p.base0B })
  hl("Changed", { fg = p.base09 })
  hl("Removed", { fg = p.base08 })
  hl("GitSignsAdd", { fg = p.base0B })
  hl("GitSignsChange", { fg = p.base09 })
  hl("GitSignsDelete", { fg = p.base08 })

  -- plugin chrome (harmless when absent)
  hl("TelescopeBorder", { fg = p.base02, bg = p.base00 })
  hl("TelescopePromptBorder", { fg = p.base0C, bg = p.base00 })
  hl("TelescopeSelection", { bg = p.base01 })
  hl("TelescopeMatching", { fg = p.base0A, bold = true })
  hl("WhichKey", { fg = p.base0A })
  hl("WhichKeyGroup", { fg = p.base0D })
  hl("WhichKeyDesc", { fg = p.base05 })
  hl("WhichKeySeparator", { fg = p.base03 })
  hl("LazyNormal", { fg = p.base05, bg = p.base01 })
  hl("OilDir", { fg = p.base0D })

  -- statusline segments (consumed by hypermodern.statusline)
  hl("HmSlMode", { fg = p.base00, bg = p.base0C, bold = true })
  hl("HmSlFile", { fg = p.base06, bg = p.base02 })
  hl("HmSlBody", { fg = p.base04, bg = p.base01 })
  hl("HmSlAccent", { fg = p.base0A, bg = p.base01 })
  hl("HmSlDim", { fg = p.base03, bg = p.base01 })
  hl("HmSlError", { fg = p.base08, bg = p.base01 })
  hl("HmSlWarn", { fg = p.base09, bg = p.base01 })
end

-- ── apply / sync / ack ─────────────────────────────────────────────

function M.apply()
  local p = M.compute()
  vim.o.termguicolors = true
  vim.o.background = p.variant
  vim.g.colors_name = "hypermodern"
  apply_highlights(p)
  M.palette = p
  vim.api.nvim_exec_autocmds("User", { pattern = "HypermodernThemeChanged" })
end

local function state_dir()
  return (vim.env.XDG_STATE_HOME and vim.env.XDG_STATE_HOME ~= "" and vim.env.XDG_STATE_HOME)
    or (vim.env.HOME .. "/.local/state")
end

--- Total parse of wintermute's theme.state (KV lines; unknown keys skipped).
function M.sync()
  local path = state_dir() .. "/wintermute/theme.state"
  local f = io.open(path, "r")
  if not f then return false end
  for line in f:lines() do
    local k, v = line:match("^(%S+)%s+(%S+)$")
    if k == "hero" then M.state.hero = (tonumber(v) or M.state.hero) % 360
    elseif k == "axis" then M.state.axis = (tonumber(v) or M.state.axis) % 360
    elseif k == "ramp" then M.state.ramp = (tonumber(v) or M.state.ramp) % 360
    elseif k == "register" then M.state.register = tonumber(v) or M.state.register
    elseif k == "generation" then M.state.generation = tonumber(v) or M.state.generation
    elseif k == "family" and palette.family_dark_ramp_hues[v] then M.state.family = v
    elseif k == "polarity" and (v == "dark" or v == "light") then M.state.polarity = v
    elseif k == "level" and (palette.black_levels[v] or palette.white_levels[v]) then
      M.state.level = v
    end
  end
  f:close()
  M.apply()
  -- accountability: acknowledge the applied generation (best-effort)
  pcall(function()
    local ack = state_dir() .. "/wintermute/ack"
    vim.fn.mkdir(ack, "p")
    local a = io.open(ack .. "/nvim", "w")
    if a then a:write(string.format("%d\n", M.state.generation)); a:close() end
  end)
  return true
end

-- ── the live poll — robust pickup on a timer ───────────────────────
--
-- Startup sync alone leaves the editor frozen on whatever the desktop
-- wore at launch. A libuv fs_event watch is fragile here: wintermute
-- writes theme.state atomically (write-temp + rename), so an inode watch
-- dies after the first reconcile. Instead poll the persisted GENERATION
-- counter: monotone, so comparing it never misses a reconcile, never
-- re-themes on a no-op tick, and self-heals on a failed read. It's one
-- tiny file read per tick. timer_start runs the callback on the main
-- loop, so calling the highlight API from M.sync() is safe (no schedule).

M.poll_interval_ms = 2000
M._poll_timer = nil

local function file_generation()
  local f = io.open(state_dir() .. "/wintermute/theme.state", "r")
  if not f then return nil end
  local gen = nil
  for line in f:lines() do
    local v = line:match("^generation%s+(%d+)$")
    if v then gen = tonumber(v); break end
  end
  f:close()
  return gen
end

function M.poll()
  local gen = file_generation()
  if gen and gen ~= M.state.generation then M.sync() end
end

function M.poll_start()
  if M._poll_timer then pcall(vim.fn.timer_stop, M._poll_timer) end
  M._poll_timer = vim.fn.timer_start(
    M.poll_interval_ms, function() pcall(M.poll) end, { ["repeat"] = -1 })
end

function M.poll_stop()
  if M._poll_timer then
    pcall(vim.fn.timer_stop, M._poll_timer)
    M._poll_timer = nil
  end
end

-- ── commands (the daemon's remote-send contract) ───────────────────

function M.boot()
  vim.api.nvim_create_user_command("OnoSendaiHero", function(o)
    M.state.hero = (tonumber(o.args) or M.state.hero) % 360
    M.apply()
  end, { nargs = 1, desc = "Set hero accent hue and reapply" })
  vim.api.nvim_create_user_command("OnoSendaiAxis", function(o)
    M.state.axis = (tonumber(o.args) or M.state.axis) % 360
    M.apply()
  end, { nargs = 1, desc = "Set axis accent hue and reapply" })
  vim.api.nvim_create_user_command("OnoSendaiSync", function()
    if not M.sync() then M.apply() end
  end, { desc = "Read wintermute theme.state, apply, ack" })
  vim.api.nvim_create_user_command("OnoSendaiPollStart", function() M.poll_start() end,
    { desc = "Start polling wintermute theme.state for live pickup" })
  vim.api.nvim_create_user_command("OnoSendaiPollStop", function() M.poll_stop() end,
    { desc = "Stop the wintermute live poll" })
  if not M.sync() then M.apply() end
  -- keep it live thereafter — the orbital pad retints this nvim within a
  -- poll. Headless (embedded/CI) runs need no timer and may exit early.
  if #vim.api.nvim_list_uis() > 0 then M.poll_start() end
end

return M
