#!/usr/bin/env bash
# relocate-sidebar.sh — Move sidebar to the current window if it's alive elsewhere.
# Called automatically by tmux hooks on window/session change.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

CACHE_DIR=$(get_state_dir)
SIDEBAR_MARKER="$CACHE_DIR/sidebar.pane_id"

[[ -f "$SIDEBAR_MARKER" ]] || exit 0

sid=$(cat "$SIDEBAR_MARKER")

# Check sidebar process is alive
if [[ -f "$CACHE_DIR/sidebar.pid" ]]; then
  kill -0 "$(cat "$CACHE_DIR/sidebar.pid")" 2>/dev/null || exit 0
fi

# Check pane exists at all
"$TMUX_BIN" list-panes -a -F '#{pane_id}' 2>/dev/null | grep -q "^${sid}$" || exit 0

# Already in the current window? Nothing to do.
"$TMUX_BIN" list-panes -F '#{pane_id}' 2>/dev/null | grep -q "^${sid}$" && exit 0

# Move sidebar to current window (leftmost, horizontal split)
WINDOW_WIDTH=$("$TMUX_BIN" display-message -p '#{window_width}' 2>/dev/null || echo 120)
SIDEBAR_WIDTH=$(( WINDOW_WIDTH / 4 ))

"$TMUX_BIN" join-pane -hb -l "$SIDEBAR_WIDTH" -s "$sid" 2>/dev/null || exit 0

# Focus the main pane (first non-sidebar pane)
main_pane=$("$TMUX_BIN" list-panes -F '#{pane_id}' 2>/dev/null | grep -v "^${sid}$" | head -1)
[[ -n "$main_pane" ]] && "$TMUX_BIN" select-pane -t "$main_pane" 2>/dev/null

# Signal redraw
if [[ -f "$CACHE_DIR/sidebar.pid" ]]; then
  kill -USR1 "$(cat "$CACHE_DIR/sidebar.pid")" 2>/dev/null || true
fi
