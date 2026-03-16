#!/usr/bin/env bash
# tmux-ai-nav.tmux — Plugin entry point
#
# Keybindings:
#   prefix + Tab   → toggle sidebar
#   prefix + Alt-n → regenerate AI title for current window
#   prefix + Alt-r → manually rename and pin current window title
#
# Hooks:
#   after-new-window → schedule AI title generation in 5 minutes

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_BIN="${TMUX_AI_NAV_TMUX_BIN:-$(command -v tmux || echo tmux)}"
CACHE_DIR="/tmp/tmux-ai-nav"

mkdir -p "$CACHE_DIR"

# prefix + Tab = toggle sidebar
"$TMUX_BIN" bind-key Tab run-shell "bash '${CURRENT_DIR}/scripts/toggle-sidebar.sh'"

# prefix + Alt-n = regenerate AI title for current window
"$TMUX_BIN" bind-key M-n run-shell "bash '${CURRENT_DIR}/scripts/refresh.sh'"

# prefix + Alt-r = manually rename and pin
"$TMUX_BIN" bind-key M-r run-shell "bash '${CURRENT_DIR}/scripts/rename.sh'"

# Hook: when a new window is created, schedule title generation after 5 min
"$TMUX_BIN" set-hook -g after-new-window \
  "run-shell -b 'bash \"${CURRENT_DIR}/scripts/schedule.sh\" \"#{session_name}\" \"#{window_index}\"'"

# Generate titles for all existing windows that don't have one yet
(
  trap '' HUP
  "$TMUX_BIN" list-windows -a -F '#{session_name} #{window_index}' 2>/dev/null | \
  while read -r sess win_idx; do
    cache_key="${sess}_${win_idx}"
    # Skip if already titled or pinned
    [[ -f "$CACHE_DIR/${cache_key}.title" ]] && continue
    [[ -f "$CACHE_DIR/${cache_key}.pinned" ]] && continue
    # Schedule with a short delay (stagger by 10s per window)
    bash "${CURRENT_DIR}/scripts/schedule.sh" "$sess" "$win_idx" &
  done
) </dev/null >/dev/null 2>&1 &
disown $! 2>/dev/null || true
