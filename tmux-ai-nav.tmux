#!/usr/bin/env bash
# tmux-ai-nav.tmux — Plugin entry point
# prefix+Tab  = toggle sidebar panel
# prefix+M-n  = toggle AI daemon on/off
# Auto-starts the daemon on tmux load.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_BIN="${TMUX_AI_NAV_TMUX_BIN:-$(command -v tmux || echo tmux)}"
CACHE_DIR="/tmp/tmux-ai-nav"
PID_FILE="$CACHE_DIR/daemon.pid"

# prefix + Tab = toggle sidebar
"$TMUX_BIN" bind-key Tab run-shell "bash '${CURRENT_DIR}/scripts/toggle-sidebar.sh'"

# prefix + M-n = toggle AI daemon
"$TMUX_BIN" bind-key M-n run-shell "bash '${CURRENT_DIR}/scripts/toggle.sh'"

# Auto-start daemon if not running
if ! { [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; }; then
  mkdir -p "$CACHE_DIR"
  (
    trap '' HUP
    bash "${CURRENT_DIR}/scripts/daemon.sh" </dev/null >/dev/null 2>&1
  ) &
  disown $! 2>/dev/null || true
fi

# Cleanup on session close
"$TMUX_BIN" set-hook -g session-closed \
  "run-shell 'PF=${CACHE_DIR}/daemon.pid; [ -f \$PF ] && kill \$(cat \$PF) 2>/dev/null; rm -f \$PF ${CACHE_DIR}/sidebar.pane_id'"
