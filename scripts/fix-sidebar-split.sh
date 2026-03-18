#!/usr/bin/env bash
# fix-sidebar-split.sh — Safety net: if a split happened inside the sidebar,
# kill the accidental pane and restore sidebar width.
# Called by after-split-window hook.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

CACHE_DIR=$(get_state_dir)
SIDEBAR_MARKER="$CACHE_DIR/sidebar.pane_id"

[[ -f "$SIDEBAR_MARKER" ]] || exit 0

sidebar_id=$(cat "$SIDEBAR_MARKER")

# Check sidebar exists in current window
"$TMUX_BIN" list-panes -F '#{pane_id}' 2>/dev/null | grep -q "^${sidebar_id}$" || exit 0

# Get sidebar width — if it shrank, a split happened inside it
SIDEBAR_WIDTH=$(get_tmux_option "@pilot-sidebar-width" "35")
current_width=$("$TMUX_BIN" display-message -t "$sidebar_id" -p '#{pane_width}' 2>/dev/null) || exit 0

# If sidebar is still full width, the split was elsewhere — all good
[[ "$current_width" -ge "$SIDEBAR_WIDTH" ]] && exit 0

# Sidebar shrank — find and kill the intruder pane.
# The intruder is a new pane at x=0 (same column as sidebar) that is NOT the sidebar.
while IFS='|' read -r pane_id pane_left; do
  [[ "$pane_id" == "$sidebar_id" ]] && continue
  if [[ "$pane_left" == "0" ]]; then
    # This pane is in the sidebar column — kill it
    "$TMUX_BIN" kill-pane -t "$pane_id" 2>/dev/null || true
  fi
done <<< "$("$TMUX_BIN" list-panes -F '#{pane_id}|#{pane_left}' 2>/dev/null)"

# Restore sidebar width
"$TMUX_BIN" resize-pane -t "$sidebar_id" -x "$SIDEBAR_WIDTH" 2>/dev/null || true
