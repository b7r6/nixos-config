#!/usr/bin/env bash
# ── zellij // the tab select screen ────────────────────────────────────────
# Bound to C-o w (config.kdl), opened in a floating pane. The house
# "choose-window": one row per tab, ENRICHED — not a useless "Tab #N" list.
#
# LATENCY. Source is `dump-layout` (~30ms) instead of `list-panes -a -j`
# (~200ms — it walks every pane's /proc for command+cwd). dump-layout already
# flags the active tab (focus=true), so this ONE call replaces two (list-panes
# + list-tabs). Per tab we surface the RUNNING command (claude, codex, an
# editor) over a focused bare shell, plus the cwd basename; you fuzzy-filter
# across command and directory. Parsed with awk — no jq. (Trade: dump-layout
# has no live pane TITLE, so command+cwd stands in for it; for these tabs it's
# already unambiguous.)
#
# There is no theming here on purpose. fzf wears wintermute's LIVE palette,
# passed on the command line from the fzf.opts channel, so this screen is
# palette-exact and follows the orbital pad the instant it moves. Chrome is
# house: ▞-railed prompt, bracketed border label, index badges, current row
# highlighted full-width (--highlight-line), cursor pre-placed on the tab you
# opened from.
#
# Enter jumps (by index, so duplicate tab names are unambiguous); Esc cancels.
# Degrades quietly: no dump-layout/awk falls back to bare tab names; no tabs /
# no fzf / a cancelled pick all just close the pane with no switch.

set -uo pipefail

# wintermute's live colour channel. We do NOT trust the environment for this:
# fzf lets FZF_DEFAULT_OPTS override the opts FILE, and something (stylix's fzf
# target, or a stale long-lived session) may still export a static
# FZF_DEFAULT_OPTS that would win over wintermute. So read the live fzf.opts
# ourselves and pass its --color on fzf's COMMAND LINE, which beats both env
# sources — and drop FZF_DEFAULT_OPTS entirely — so the picker always wears
# exactly what the desktop wears, retinting the instant the orbital pad moves.
: "${XDG_STATE_HOME:=$HOME/.local/state}"
unset FZF_DEFAULT_OPTS
theme_opts=()
opts_file="$XDG_STATE_HOME/wintermute/fzf.opts"
if [ -r "$opts_file" ]; then
  # one `--color=...` token today; split on whitespace for any future opts
  # shellcheck disable=SC2207
  theme_opts=($(cat "$opts_file"))
fi

# Parse dump-layout into rows. Per tab: prefer the RUNNING command over the
# focused bare shell; carry the cwd basename (dump-layout omits it for the home
# dir — fine). Emit <idx>\t<display>\t<active>. Skips the status-bar plugin pane
# (borderless) and split containers.
read -r -d '' tabs_awk <<'AWK'
function base(p,   n,a){ n=split(p,a,"/"); return a[n] }
function attr(line,key,   v){ if (line ~ (key "=\"")) { v=line; sub(".*" key "=\"","",v); sub(/".*/,"",v); return v } return "" }
function flush(){
  if (haveTab) {
    d = sprintf(" %d · %s", idx, (repcmd == "" ? "sh" : repcmd))
    if (repcwd != "") d = d "  · " repcwd
    printf "%d\t%s\t%s\n", idx, d, (tabactive ? "1" : "0")
  }
}
/^[ \t]*tab name=/ { flush(); idx++; haveTab=1; tabactive=($0 ~ /focus=true/); repcmd=""; repcwd=""; haveCmd=0; firstset=0; next }
/^[ \t]*pane/ {
  if ($0 ~ /split_direction/ || $0 ~ /borderless=true/) next
  cmd=attr($0,"command"); if (cmd != "") { cmd=base(cmd); sub(/ .*/,"",cmd) }
  cwd=attr($0,"cwd");     if (cwd != "") cwd=base(cwd)
  if (cmd != "" && !haveCmd)        { repcmd=cmd; repcwd=cwd; haveCmd=1 }
  else if (!firstset && !haveCmd)   { repcmd=cmd; repcwd=cwd; firstset=1 }
  next
}
END { flush() }
AWK

rows=()
active_ord=""
ord=0
while IFS=$'\t' read -r fidx fdisp factive; do
  ord=$((ord + 1))
  rows+=("$(printf '%s\t%s' "$fidx" "$fdisp")")
  [ "$factive" = "1" ] && active_ord=$ord
done < <(zellij action dump-layout 2>/dev/null | awk "$tabs_awk" 2>/dev/null)

# Fallback: bare tab names, still index-badged, if dump-layout/awk gave nothing.
if [ "${#rows[@]}" -eq 0 ]; then
  idx=0
  while IFS= read -r n; do
    idx=$((idx + 1))
    rows+=("$(printf '%d\t %2d · %s' "$idx" "$idx" "$n")")
  done < <(zellij action query-tab-names 2>/dev/null)
fi
[ "${#rows[@]}" -gt 0 ] || exit 0

# Cursor starts on the tab we were opened from — active_ord is that row's line
# number, straight from dump-layout's focus=true. --sync so start:pos fires
# after the (tiny, already-buffered) list loads.
pos_bind=()
[ -n "$active_ord" ] && pos_bind=(--sync --bind "start:pos($active_ord)")

fzf_args=(
  ${theme_opts[@]+"${theme_opts[@]}"}
  ${pos_bind[@]+"${pos_bind[@]}"}
  --delimiter=$'\t'
  --with-nth=2
  --layout=reverse
  --height=100%
  --min-height=6
  --highlight-line
  --info=inline:'  ▞ '
  --no-scrollbar
  --cycle
  --pointer='▸'
  --marker='▹'
  --border=rounded
  --border-label=' ▞ tabs '
  --border-label-pos=3
  --prompt='jump ❯ '
  --header='enter jump · C-n/C-p move · esc cancel'
)

sel=$(printf '%s\n' "${rows[@]}" | fzf "${fzf_args[@]}") || exit 0

[ -n "$sel" ] || exit 0
tab_idx=${sel%%$'\t'*}
case "$tab_idx" in
  '' | *[!0-9]*) exit 0 ;; # never pass a non-number to go-to-tab
  *) zellij action go-to-tab "$tab_idx" ;;
esac
