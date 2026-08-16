-- ───────────────────────────────────────────────────────────────────
--                  // statusline // register-aware // pure lua //
-- ───────────────────────────────────────────────────────────────────
--
-- No plugin: one render function on vim.o.statusline. Wears the
-- computed palette (HmSl* groups from hypermodern.theme) and reads the
-- register axis — facility (>= 0.6) is UPPERCASE with the ▞ mark and
-- a GEN readout, affluent is soft lowercase. Same choreography as the
-- emacs SVG modeline and the quickshell bar.

local M = {}

local MODES = {
  n = "normal", i = "insert", v = "visual", V = "v·line", ["\022"] = "v·block",
  c = "command", R = "replace", s = "select", S = "s·line", t = "terminal",
}

local function diag_counts()
  local e = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
  local w = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })
  return e, w
end

function M.render()
  local theme = require("hypermodern.theme")
  local facility = (theme.state.register or 1000) >= 600
  local mode = MODES[vim.fn.mode()] or vim.fn.mode()
  local name = vim.fn.expand("%:t")
  if name == "" then name = "[scratch]" end
  local branch = vim.b.gitsigns_head
  local e, w = diag_counts()

  local left
  if facility then
    left = string.format("%%#HmSlMode# ▞ %s %%#HmSlFile# %s%s %%#HmSlBody#",
      mode:upper(), name:upper(), vim.bo.modified and " •" or "")
  else
    left = string.format("%%#HmSlMode# %s %%#HmSlFile# %s%s %%#HmSlBody#",
      mode, name, vim.bo.modified and " •" or "")
  end

  local mid = branch and (" %#HmSlDim#" .. (facility and branch:upper() or branch)) or ""
  local diags = (e > 0 and string.format(" %%#HmSlError#%d✗", e) or "")
    .. (w > 0 and string.format(" %%#HmSlWarn#%d△", w) or "")

  local right
  if facility then
    right = string.format("%%#HmSlAccent# GEN %d %%#HmSlBody# %%#HmSlDim#%%l:%%c %%p%%%% ",
      theme.state.generation or 0)
  else
    right = " %#HmSlDim#%l:%c · %p%% "
  end

  return left .. mid .. diags .. "%=" .. right
end

function M.setup()
  vim.o.laststatus = 3
  vim.o.statusline = "%!v:lua.require'hypermodern.statusline'.render()"
end

return M
