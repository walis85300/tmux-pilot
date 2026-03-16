#!/usr/bin/env bash
# tmux-ai-nav.tmux — Plugin entry point
#
# Keybindings:
#   prefix + Tab   → toggle sidebar
#   prefix + Alt-n → regenerate AI title for current window
#   prefix + Alt-r → manually rename and pin current window title
#
# A background daemon titles new windows automatically (once per window, never again).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_BIN="${TMUX_AI_NAV_TMUX_BIN:-$(command -v tmux || echo tmux)}"
CACHE_DIR="/tmp/tmux-ai-nav"
PID_FILE="$CACHE_DIR/daemon.pid"

mkdir -p "$CACHE_DIR"

"$TMUX_BIN" bind-key Tab run-shell "bash '${CURRENT_DIR}/scripts/toggle-sidebar.sh'"
"$TMUX_BIN" bind-key M-n run-shell "bash '${CURRENT_DIR}/scripts/refresh.sh'"
"$TMUX_BIN" bind-key M-r run-shell "bash '${CURRENT_DIR}/scripts/rename.sh'"

# Auto-start daemon if not already running
if ! { [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; }; then
  (
    trap '' HUP
    bash "${CURRENT_DIR}/scripts/daemon.sh" </dev/null >/dev/null 2>&1
  ) &
  disown $! 2>/dev/null || true
fi

# Cleanup on session close
"$TMUX_BIN" set-hook -g session-closed \
  "run-shell 'PF=${CACHE_DIR}/daemon.pid; [ -f \$PF ] && kill \$(cat \$PF) 2>/dev/null; rm -f \$PF'"
