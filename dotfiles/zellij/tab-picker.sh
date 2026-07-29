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

# Rows are <idx>\t<display>: fzf shows and searches the display column (line N
# === tab index N, 1-based — the order go-to-tab counts in); the hidden idx
# column is what we act on.
#
# Enriched path: group list-panes by tab, drop plugins and floating panes (the
# latter includes THIS picker's own pane), and per tab pick the most telling
# pane — a real title over a bare shell — for the label.
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

rows=()
if command -v jq >/dev/null 2>&1; then
  while IFS= read -r line; do rows+=("$line"); done < <(
    zellij action list-panes -a -j 2>/dev/null | jq -r "$tabs_filter" 2>/dev/null
  )
fi
# Fallback: bare tab names, still index-badged, if jq/list-panes gave nothing.
if [ "${#rows[@]}" -eq 0 ]; then
  idx=0
  while IFS= read -r n; do
    idx=$((idx + 1))
    rows+=("$(printf '%d\t %2d · %s' "$idx" "$idx" "$n")")
  done < <(zellij action query-tab-names 2>/dev/null)
fi
[ "${#rows[@]}" -gt 0 ] || exit 0

# Start the cursor on the tab we were opened from. list-tabs' `active` field is
# the reliable signal — a floating picker doesn't change the active tab, and
# per-pane is_focused is per-TAB, not global. Map that tab's index to its row
# ordinal (rows are in tab order) and hand fzf a start:pos() bind. Best-effort:
# no jq, no active tab, or no matching row just leaves the cursor at the top.
start_bind=()
if command -v jq >/dev/null 2>&1; then
  active_idx=$(zellij action list-tabs -j 2>/dev/null \
    | jq -r 'first(.[] | select(.active) | .position) // empty | . + 1' 2>/dev/null)
  if [ -n "${active_idx:-}" ]; then
    ord=0
    for r in "${rows[@]}"; do
      ord=$((ord + 1))
      if [ "${r%%$'\t'*}" = "$active_idx" ]; then
        # --sync is REQUIRED: without it the `start` event fires before the
        # list is loaded and pos() is a no-op. The tab list is tiny, so
        # loading up front before first paint is imperceptible.
        start_bind=(--sync --bind "start:pos($ord)")
        break
      fi
    done
  fi
fi

sel=$(
  printf '%s\n' "${rows[@]}" | fzf \
    ${theme_opts[@]+"${theme_opts[@]}"} \
    ${start_bind[@]+"${start_bind[@]}"} \
    --delimiter=$'\t' \
    --with-nth=2 \
    --layout=reverse \
    --height=100% \
    --min-height=6 \
    --highlight-line \
    --info=inline:'  ▞ ' \
    --no-scrollbar \
    --cycle \
    --pointer='▸' \
    --marker='▹' \
    --border=rounded \
    --border-label=' ▞ tabs ' \
    --border-label-pos=3 \
    --prompt='jump ❯ ' \
    --header='enter jump · C-n/C-p move · esc cancel'
) || exit 0

[ -n "$sel" ] || exit 0
tab_idx=${sel%%$'\t'*}
case "$tab_idx" in
  '' | *[!0-9]*) exit 0 ;; # never pass a non-number to go-to-tab
  *) zellij action go-to-tab "$tab_idx" ;;
esac
