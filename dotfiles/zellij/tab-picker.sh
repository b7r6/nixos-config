#!/usr/bin/env bash
# ── zellij // the tab select screen ────────────────────────────────────────
# Bound to C-o w (config.kdl), opened in a floating pane. The house
# "choose-window": one row per tab, ENRICHED — not a useless "Tab #N" list.
#
# Per tab we read list-panes and surface the most telling pane: its title when
# it has a real one (an editor buffer, a running task like a model download or
# a build), else the command name; plus the cwd basename and the pane count.
# You fuzzy-filter across all of it — a title word, a command, a directory.
#
# There is no theming here on purpose. fzf wears wintermute's LIVE palette,
# passed on the command line from the fzf.opts channel, so this screen is
# palette-exact and follows the orbital pad the instant it moves. The chrome is
# house: ▞-railed prompt, bracketed border label, index badges, and the
# current row highlighted full-width (--highlight-line).
#
# Latency: list-panes resolves each pane's command/cwd from /proc (~130ms on a
# busy session), so we STREAM it into fzf rather than block — the picker frame
# is up instantly and the list fills a beat later. The cursor starts on the tab
# you opened from (load:pos, which needs no --sync so it doesn't delay paint).
#
# Enter jumps (by index, so duplicate tab names are unambiguous); Esc cancels.
# Everything degrades quietly: no jq/list-panes falls back to bare tab names;
# no tabs, no fzf, or a cancelled pick all just close the pane with no switch.

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

# Cursor starts on the tab we were opened from. list-tabs' `active` field is the
# reliable signal — a floating picker doesn't change the active tab, and the
# per-pane is_focused flag is per-TAB, not global. It's a cheap call (~8ms), so
# we do it up front; the ordinal is position+1 (one row per tab, in order).
active_pos=""
command -v jq >/dev/null 2>&1 && active_pos=$(
  zellij action list-tabs -j 2>/dev/null \
    | jq -r 'first(.[] | select(.active) | .position) // empty' 2>/dev/null
)
# load:pos (not start:pos) fires AFTER the streamed list is read, so it needs no
# --sync and doesn't hold up the first paint — the whole point below.
pos_bind=()
[ -n "$active_pos" ] && pos_bind=(--bind "load:pos($((active_pos + 1)))")

# The per-tab enrichment: group list-panes by tab, drop plugins and floating
# panes (the latter includes THIS picker's own pane), and per tab pick the most
# telling pane — a real title over a bare shell — for the label. Rows are
# <idx>\t<display>: fzf shows and searches the display column, the hidden idx
# drives go-to-tab (idx N === tab index N, 1-based, the go-to-tab order).
read -r -d '' tabs_filter <<'JQ'
[ .[] | select(.is_plugin == false and .is_floating == false) ]
| group_by(.tab_position)
| sort_by(.[0].tab_position)
| .[]
| (.[0].tab_position + 1) as $idx
| length                   as $n
| ( [ .[] | select((.title|test("^Pane #")|not) and .title != "") ] ) as $named
| ( ([$named[]|select(.is_focused)][0]) // $named[0] // ([.[]|select(.is_focused)][0]) // .[0] ) as $rep
| ($rep.title // "")                                              as $t
| (($rep.pane_command // "") | split("/") | last | split(" ")[0]) as $cmd
| (($rep.pane_cwd // "")     | split("/") | last)                 as $cwd
| ( if ($t|test("^Pane #")) or ($t=="") then $cmd else ($t|sub("^[^A-Za-z0-9/~._-]+";"")) end ) as $primary
| "\($idx)\t \($idx) · \($primary)  · \($cwd) · \($n)p"
JQ

# The chrome, built once so the enriched and fallback paths share it.
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

if command -v jq >/dev/null 2>&1; then
  # STREAM the slow part straight into fzf. list-panes resolves each pane's
  # command/cwd from /proc (~130ms on a busy session), so instead of blocking on
  # it and leaving the screen empty, we let fzf paint its frame IMMEDIATELY and
  # fill the list as rows arrive. The picker is up instantly; the enrichment
  # lands a beat later; load:pos then jumps the cursor to the active tab.
  sel=$(zellij action list-panes -a -j 2>/dev/null | jq -r "$tabs_filter" 2>/dev/null | fzf "${fzf_args[@]}") || exit 0
else
  # Fallback (no jq): bare tab names, still index-badged. Small and instant.
  names=()
  while IFS= read -r n; do names+=("$n"); done < <(zellij action query-tab-names 2>/dev/null)
  [ "${#names[@]}" -gt 0 ] || exit 0
  rows=()
  idx=0
  for n in "${names[@]}"; do
    idx=$((idx + 1))
    rows+=("$(printf '%d\t %2d · %s' "$idx" "$idx" "$n")")
  done
  sel=$(printf '%s\n' "${rows[@]}" | fzf "${fzf_args[@]}") || exit 0
fi

[ -n "$sel" ] || exit 0
tab_idx=${sel%%$'\t'*}
case "$tab_idx" in
  '' | *[!0-9]*) exit 0 ;; # never pass a non-number to go-to-tab
  *) zellij action go-to-tab "$tab_idx" ;;
esac
