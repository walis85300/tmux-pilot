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

# Get current window ID to check if sidebar is local
CURRENT_WINDOW=$("$TMUX_BIN" display-message -p '#{window_id}' 2>/dev/null)

# Check if sidebar pane AND process are alive
sidebar_alive() {
  [[ -f "$SIDEBAR_MARKER" ]] || return 1
  local pane_id
  pane_id=$(cat "$SIDEBAR_MARKER")
  "$TMUX_BIN" list-panes -a -F '#{pane_id}' 2>/dev/null | grep -q "^${pane_id}$" || return 1
  local pid_file="$CACHE_DIR/sidebar.pid"
  if [[ -f "$pid_file" ]]; then
    kill -0 "$(cat "$pid_file")" 2>/dev/null || return 1
  fi
  return 0
}

# Check if sidebar pane is in the current window
sidebar_in_current_window() {
  [[ -f "$SIDEBAR_MARKER" ]] || return 1
  local pane_id
  pane_id=$(cat "$SIDEBAR_MARKER")
  "$TMUX_BIN" list-panes -F '#{pane_id}' 2>/dev/null | grep -q "^${pane_id}$"
}

kill_sidebar() {
  if [[ -f "$SIDEBAR_MARKER" ]]; then
    local sid
    sid=$(cat "$SIDEBAR_MARKER")
    "$TMUX_BIN" kill-pane -t "$sid" 2>/dev/null || true
  fi
  rm -f "$SIDEBAR_MARKER" "$CACHE_DIR/sidebar.pid"
}

create_sidebar() {
  mkdir -p "$CACHE_DIR"
  new_pane=$("$TMUX_BIN" split-window -hbf -l "$SIDEBAR_WIDTH" -P -F '#{pane_id}' \
    "sleep 0.3 && exec bash '${PLUGIN_DIR}/scripts/sidebar.sh'")
  printf '%s' "$new_pane" > "$SIDEBAR_MARKER"
  "$TMUX_BIN" select-pane -t "$new_pane" 2>/dev/null || true
}

if sidebar_alive; then
  if sidebar_in_current_window; then
    # Sidebar is here and visible — toggle it off
    kill_sidebar
  else
    # Sidebar is alive but in another window/session — move it here
    sid=$(cat "$SIDEBAR_MARKER")
    "$TMUX_BIN" join-pane -hb -l "$SIDEBAR_WIDTH" -s "$sid" 2>/dev/null || true
    "$TMUX_BIN" select-pane -t "$sid" 2>/dev/null || true
  fi
else
  # Clean up stale state if any
  kill_sidebar
  # Create fresh sidebar
  create_sidebar
fi
