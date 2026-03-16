#!/usr/bin/env bash
# toggle-sidebar.sh — Show/hide the left sidebar panel.
# The AI daemon (daemon.sh) runs independently and is NOT affected.

set -uo pipefail

TMUX_BIN="${TMUX_AI_NAV_TMUX_BIN:-$(command -v tmux || echo tmux)}"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="/tmp/tmux-ai-nav"
SIDEBAR_MARKER="$CACHE_DIR/sidebar.pane_id"

# 25% of current window width
WINDOW_WIDTH=$("$TMUX_BIN" display-message -p '#{window_width}' 2>/dev/null || echo 120)
SIDEBAR_WIDTH=$(( WINDOW_WIDTH / 4 ))

# Check if sidebar pane is alive
sidebar_alive() {
  [[ -f "$SIDEBAR_MARKER" ]] || return 1
  local pane_id
  pane_id=$(cat "$SIDEBAR_MARKER")
  "$TMUX_BIN" list-panes -a -F '#{pane_id}' 2>/dev/null | grep -q "^${pane_id}$"
}

if sidebar_alive; then
  sid=$(cat "$SIDEBAR_MARKER")
  "$TMUX_BIN" kill-pane -t "$sid" 2>/dev/null || true
  rm -f "$SIDEBAR_MARKER"
else
  mkdir -p "$CACHE_DIR"

  # split-window -P returns the new pane ID. We write it to the marker file
  # BEFORE the sidebar script reads it.
  new_pane=$("$TMUX_BIN" split-window -hbf -l "$SIDEBAR_WIDTH" -P -F '#{pane_id}' \
    "sleep 0.3 && exec bash '${PLUGIN_DIR}/scripts/sidebar.sh'")

  printf '%s' "$new_pane" > "$SIDEBAR_MARKER"
  "$TMUX_BIN" select-pane -t "$new_pane" 2>/dev/null || true
fi
