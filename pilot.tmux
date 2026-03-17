#!/usr/bin/env bash
# pilot.tmux — Plugin entry point
#
# Keybindings (configurable via @pilot-* options):
#   prefix + Tab   → toggle sidebar
#   prefix + T     → regenerate AI title for current window
#   prefix + R     → manually rename and pin current window title
#   prefix + F     → fuzzy find windows (standalone, no sidebar needed)
#
# A background daemon titles new windows automatically (once per window, never again).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared helpers
source "${CURRENT_DIR}/scripts/helpers.sh"

CACHE_DIR=$(get_state_dir)
PID_FILE="$CACHE_DIR/daemon.pid"

# Read keybindings from @pilot-* options with defaults
KEY_SIDEBAR=$(get_tmux_option "@pilot-key-sidebar" "Tab")
KEY_TITLE=$(get_tmux_option "@pilot-key-title" "T")
KEY_RENAME=$(get_tmux_option "@pilot-key-rename" "R")
KEY_FUZZY=$(get_tmux_option "@pilot-key-fuzzy" "F")

# Dependency checks
CLAUDE_BIN="${TMUX_AI_NAV_CLAUDE_BIN:-claude}"
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  "$TMUX_BIN" display-message "tmux-pilot: claude not found. Install: npm install -g @anthropic-ai/claude-code"
fi
if ! command -v fzf >/dev/null 2>&1; then
  "$TMUX_BIN" display-message "tmux-pilot: fzf not found (optional, for fuzzy finder). Install: brew install fzf"
fi

# Bind keys
"$TMUX_BIN" bind-key "$KEY_SIDEBAR" run-shell "bash '${CURRENT_DIR}/scripts/toggle-sidebar.sh'"
"$TMUX_BIN" bind-key "$KEY_TITLE"   run-shell "bash '${CURRENT_DIR}/scripts/refresh.sh'"
"$TMUX_BIN" bind-key "$KEY_RENAME"  run-shell "bash '${CURRENT_DIR}/scripts/rename.sh'"

# Fuzzy finder: use display-popup if tmux >= 3.2, otherwise fall back to run-shell
if tmux_version_ge "3.2"; then
  "$TMUX_BIN" bind-key "$KEY_FUZZY" display-popup -E -w 80% -h 60% -T " Jump to window " \
    "bash '${CURRENT_DIR}/scripts/fuzzy-find.sh' standalone"
else
  "$TMUX_BIN" bind-key "$KEY_FUZZY" run-shell "bash '${CURRENT_DIR}/scripts/fuzzy-find.sh' standalone"
fi

# Auto-start daemon if not already running
if ! { [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; }; then
  (
    trap '' HUP
    bash "${CURRENT_DIR}/scripts/daemon.sh" </dev/null >/dev/null 2>&1
  ) &
  disown $! 2>/dev/null || true
fi

# Signal sidebar to redraw on relevant events (non-blocking with -b)
SIDEBAR_SIGNAL="run-shell -b 'PF=${CACHE_DIR}/sidebar.pid; [ -f \$PF ] && kill -USR1 \$(cat \$PF) 2>/dev/null || true'"
"$TMUX_BIN" set-hook -g window-renamed       "$SIDEBAR_SIGNAL"
"$TMUX_BIN" set-hook -g after-select-window   "$SIDEBAR_SIGNAL"
"$TMUX_BIN" set-hook -g after-select-pane     "$SIDEBAR_SIGNAL"
"$TMUX_BIN" set-hook -g after-split-window    "$SIDEBAR_SIGNAL"
"$TMUX_BIN" set-hook -g after-kill-pane       "$SIDEBAR_SIGNAL"
"$TMUX_BIN" set-hook -g pane-focus-in         "$SIDEBAR_SIGNAL"

# Cleanup on session close (non-blocking with -b)
"$TMUX_BIN" set-hook -g session-closed \
  "run-shell -b 'PF=${CACHE_DIR}/daemon.pid; [ -f \$PF ] && kill \$(cat \$PF) 2>/dev/null; rm -f \$PF; \
              PF2=${CACHE_DIR}/sidebar.pid; [ -f \$PF2 ] && rm -f \$PF2'"
