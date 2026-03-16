#!/usr/bin/env bash
# rename.sh — Manually rename the current window and pin it.
# Pinned titles are never auto-overwritten.
# Usage: rename.sh <title>

set -uo pipefail

TMUX_BIN="${TMUX_AI_NAV_TMUX_BIN:-$(command -v tmux || echo tmux)}"
CACHE_DIR="/tmp/tmux-ai-nav"

SESSION=$("$TMUX_BIN" display-message -p '#{session_name}')
WINDOW_IDX=$("$TMUX_BIN" display-message -p '#{window_index}')
TITLE="$*"

if [[ -z "$TITLE" ]]; then
  # No title given — open tmux's native rename prompt
  "$TMUX_BIN" command-prompt -p "Rename window:" \
    "run-shell \"bash '$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rename.sh' '%%'\""
  exit 0
fi

mkdir -p "$CACHE_DIR"
cache_key="${SESSION}_${WINDOW_IDX}"

# Rename and pin
"$TMUX_BIN" rename-window -t "${SESSION}:${WINDOW_IDX}" "$TITLE" 2>/dev/null
"$TMUX_BIN" set-option -t "${SESSION}:${WINDOW_IDX}" automatic-rename off 2>/dev/null

printf '%s' "$TITLE" > "$CACHE_DIR/${cache_key}.title"
touch "$CACHE_DIR/${cache_key}.pinned"

# Clear summary since this is manual
: > "$CACHE_DIR/${cache_key}.summary"

"$TMUX_BIN" display-message "Pinned: $TITLE" 2>/dev/null
