#!/usr/bin/env bash
# ── zellij // the tab select screen ────────────────────────────────────────
# Bound to C-o w (config.kdl), opened in a floating pane. The house
# "choose-window": tab names in position order, index-badged, fuzzy-picked
# through fzf.
#
# There is no theming here on purpose. fzf already wears wintermute's LIVE
# palette via FZF_DEFAULT_OPTS_FILE — the exact channel Ctrl-R (atuin) and
# every other fzf ride — so this screen is palette-exact for free and follows
# the orbital pad the instant it moves. All this script adds is the house
# CHROME: the ▞-railed prompt, the bracketed border label, the index badges.
#
# Enter jumps (by index, so duplicate tab names are unambiguous); Esc cancels.
# Everything degrades quietly: no tabs, no fzf, or a cancelled pick all just
# close the floating pane with no switch and no error.

set -uo pipefail

# wintermute's fzf colour channel. The session normally exports this, but a
# floating pane spawned in an odd context might not inherit it — point fzf at
# the live file ourselves so the picker is never left un-themed.
: "${XDG_STATE_HOME:=$HOME/.local/state}"
if [ -z "${FZF_DEFAULT_OPTS_FILE:-}" ] && [ -r "$XDG_STATE_HOME/wintermute/fzf.opts" ]; then
  export FZF_DEFAULT_OPTS_FILE="$XDG_STATE_HOME/wintermute/fzf.opts"
fi

# Tab names in position order (line N === tab index N, 1-based — the same
# order zellij's go-to-tab counts in).
mapfile -t names < <(zellij action query-tab-names 2>/dev/null)
[ "${#names[@]}" -gt 0 ] || exit 0

# One row per tab: <idx>\t<display>\t<name>. fzf shows and searches the
# display column; the hidden idx column is what we act on.
rows=()
idx=0
for n in "${names[@]}"; do
  idx=$((idx + 1))
  rows+=("$(printf '%d\t %2d · %s\t%s' "$idx" "$idx" "$n" "$n")")
done

sel=$(
  printf '%s\n' "${rows[@]}" | fzf \
    --delimiter=$'\t' \
    --with-nth=2 \
    --layout=reverse \
    --height=100% \
    --min-height=6 \
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
