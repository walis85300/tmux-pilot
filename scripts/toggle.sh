#!/usr/bin/env bash
# toggle.sh — Start/stop the AI title daemon.
# When stopped, restores automatic-rename on all windows.

set -uo pipefail

TMUX_BIN="${TMUX_AI_NAV_TMUX_BIN:-$(command -v tmux || echo tmux)}"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="/tmp/tmux-ai-nav"
PID_FILE="$CACHE_DIR/daemon.pid"

is_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

if is_running; then
  # Stop the daemon
  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  rm -f "$PID_FILE"

  # Restore automatic-rename on all windows so tmux shows default names
  "$TMUX_BIN" list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null | while read -r target; do
    "$TMUX_BIN" set-option -t "$target" automatic-rename on 2>/dev/null || true
  done

  "$TMUX_BIN" display-message "AI Nav: OFF" 2>/dev/null
else
  # Start the daemon
  mkdir -p "$CACHE_DIR"

  (
    trap '' HUP
    bash "$PLUGIN_DIR/scripts/daemon.sh" </dev/null >/dev/null 2>&1
  ) &
  disown $! 2>/dev/null || true

  "$TMUX_BIN" display-message "AI Nav: ON" 2>/dev/null
fi
