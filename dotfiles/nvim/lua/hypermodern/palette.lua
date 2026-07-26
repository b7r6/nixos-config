-- ───────────────────────────────────────────────────────────────────
--                     // theme engine // computed palettes // 211° //
-- ───────────────────────────────────────────────────────────────────
--
-- The FIFTH implementation of the ono-sendai palette math (Lean
-- generator, lib.nix, wintermute, elisp, and now lua) — pinned to the
-- same 66 conformance vectors by checks.ono-sendai-parity, which runs
-- lua/hypermodern/vectors.lua under `nvim -l`.  Integer HSL→RGB,
-- fixed-point ×1000, round-half-up: any drift from the Lean reference
-- is a CI failure.
--
-- Pure lua, zero nvim/plugin dependencies: require()-able from the
-- config, dofile()-able from CI, runnable under plain lua 5.1+ (uses
-- 5.1/LuaJIT-safe: math.floor division on non-negative operands
-- (every operand stays far below 2^53, so doubles are exact).

local M = {}

-- ── integer HSL → RGB (exact port of the Lean reference) ───────────

local function channel(base, m1000)
  local v = math.floor(((base + m1000) * 255 + 500) / 1000)
  return v < 255 and v or 255
end

--- Hex color at hue H (any integer), S and L clamped to [0, 100].
function M.hsl_to_hex(h, s, l)
  h = h % 360
  if s > 100 then s = 100 end
  if l > 100 then l = 100 end
  local s1000, l1000 = s * 10, l * 10
  local diff = l1000 * 2 - 1000
  if diff < 0 then diff = -diff end
  local c1000 = math.floor((1000 - diff) * s1000 / 1000)
  local sector = math.floor(h / 60)
  local pair = h % 120
  local abs_val = pair - 60
  if abs_val < 0 then abs_val = -abs_val end
  local x1000 = math.floor(c1000 * (60 - abs_val) / 60)
  local m1000 = l1000 - math.floor(c1000 / 2)
  local r, g, b
  if sector == 0 then r, g, b = c1000, x1000, 0
  elseif sector == 1 then r, g, b = x1000, c1000, 0
  elseif sector == 2 then r, g, b = 0, c1000, x1000
  elseif sector == 3 then r, g, b = 0, x1000, c1000
  elseif sector == 4 then r, g, b = x1000, 0, c1000
  else r, g, b = c1000, 0, x1000 end
  return string.format("#%02x%02x%02x",
    channel(r, m1000), channel(g, m1000), channel(b, m1000))
end

-- ── the slot tables ────────────────────────────────────────────────

M.black_levels = { void = 0, deep = 4, night = 8, carbon = 11, github = 16 }
M.white_levels = { tessier = 100, neoform = 97, ghost = 92 }
M.black_order = { "void", "deep", "night", "carbon", "github" }
M.white_order = { "tessier", "neoform", "ghost" }

--- Ono-sendai palette at black LEVEL (string); ramp hue-locked to 211.
function M.compute_dark(level, hero, axis)
  local L = M.black_levels[level] or 11
  hero = hero or 211
  axis = axis or 201
  local hex = M.hsl_to_hex
  return {
    name = "Ono-Sendai " .. level:sub(1, 1):upper() .. level:sub(2),
    variant = "dark",
    base00 = hex(211, 12, L + 0),
    base01 = hex(211, 16, L + 3),
    base02 = hex(211, 17, L + 8),
    base03 = hex(211, 15, L + 17),
    base04 = hex(211, 12, 48),
    base05 = hex(211, 28, 81),
    base06 = hex(211, 32, 89),
    base07 = hex(211, 36, 95),
    base08 = hex(axis, 100, 86),
    base09 = hex(axis, 100, 75),
    base0A = hex(hero, 100, 66),
    base0B = hex(hero, 100, 57),
    base0C = hex(hero, 94, 45),
    base0D = hex(hero, 100, 65),
    base0E = hex(hero, 100, 71),
    base0F = hex(hero, 86, 53),
  }
end

--- Maas palette at white LEVEL; RAMP unlocks the paper tint (bioptic = 36).
function M.compute_light(level, hero, axis, ramp)
  local W = M.white_levels[level] or 97
  hero = hero or 211
  axis = axis or 201
  ramp = ramp or 211
  local hex = M.hsl_to_hex
  return {
    name = "Maas " .. level:sub(1, 1):upper() .. level:sub(2),
    variant = "light",
    base00 = hex(ramp, 33, W - 0),
    base01 = hex(ramp, 28, W - 4),
    base02 = hex(ramp, 26, W - 10),
    base03 = hex(ramp, 15, 60),
    base04 = hex(ramp, 15, 43),
    base05 = hex(ramp, 23, 23),
    base06 = hex(ramp, 25, 15),
    base07 = hex(ramp, 28, 8),
    base08 = hex(axis, 90, 40),
    base09 = hex(axis, 100, 34),
    base0A = hex(hero, 94, 45),
    base0B = hex(hero, 100, 40),
    base0C = hex(hero, 100, 34),
    base0D = hex(hero, 86, 47),
    base0E = hex(hero, 100, 50),
    base0F = hex(hero, 86, 38),
  }
end

-- ── conformance vectors (CI: nvim -l vectors.lua) ──────────────────

M.vector_hues = {
  { 211, 201 }, { 36, 26 }, { 0, 350 },
  { 120, 110 }, { 262, 252 }, { 300, 290 },
}

local SLOTS = {
  "base00", "base01", "base02", "base03", "base04", "base05", "base06",
  "base07", "base08", "base09", "base0A", "base0B", "base0C", "base0D",
  "base0E", "base0F",
}
M.slots = SLOTS

local function vector_json(slug, hero, axis, ramp, palette)
  local parts = {
    string.format('{"slug": "%s", "heroHue": %d, "axisHue": %d, "rampHue": %d',
      slug, hero, axis, ramp),
  }
  for _, slot in ipairs(SLOTS) do
    parts[#parts + 1] = string.format(', "%s": "%s"', slot, palette[slot])
  end
  return table.concat(parts) .. "}"
end

--- The 66 conformance vectors as a JSON string (order matches Lean).
function M.emit_vectors()
  local vectors = {}
  for _, hu in ipairs(M.vector_hues) do
    for _, level in ipairs(M.black_order) do
      vectors[#vectors + 1] = vector_json(
        "ono-sendai-" .. level, hu[1], hu[2], 211,
        M.compute_dark(level, hu[1], hu[2]))
    end
  end
  for _, hu in ipairs(M.vector_hues) do
    for _, level in ipairs(M.white_order) do
      for _, ramp in ipairs({ 211, 36 }) do
        vectors[#vectors + 1] = vector_json(
          "maas-" .. level, hu[1], hu[2], ramp,
          M.compute_light(level, hu[1], hu[2], ramp))
      end
    end
  end
  return "[\n  " .. table.concat(vectors, ",\n  ") .. "\n]\n"
end

return M
