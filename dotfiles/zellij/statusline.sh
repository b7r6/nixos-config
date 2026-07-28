#!/bin/sh
# ── the zellij bar's machine readout ───────────────────────────────────────
# On a DGX Spark the multiplexer should read like the console: live GPU
# utilization + power draw beside the load average. nvidia-smi returns nothing
# off-GPU, so that segment simply vanishes and only load remains — the same
# graceful degradation the quickshell telemetry cluster uses.
#
# Emits zjstatus #[...] format codes; the layout renders them (rendermode
# dynamic). Colours are the theme's named slots so this tracks the palette.
# NB: `black` (= base01, a surface tone) is near-invisible on LIGHT themes, so
# label text uses `white` (the foreground, readable on both poles) and the
# values pop with a saturated accent + bold.

smi=$(nvidia-smi --query-gpu=utilization.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null | head -1)
out=""
if [ -n "$smi" ]; then
  u=$(printf '%s' "$smi" | awk -F, '{printf "%d", $1}')
  p=$(printf '%s' "$smi" | awk -F, '{printf "%d", $2}')
  out="#[fg=white]gpu #[fg=green,bold]${u}%#[fg=white] #[fg=orange,bold]${p}#[fg=white]w #[fg=cyan]▞ "
fi

load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
printf '%s#[fg=white]load #[fg=white,bold]%s' "$out" "${load:-?}"
