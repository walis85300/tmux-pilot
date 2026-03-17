#!/usr/bin/env bash
# refresh.sh — Regenerate AI title for the current window (manual trigger).
# Ignores pinned status — if you ask for it, you get it.
# Usage: refresh.sh (no args, uses current window)

set -uo pipefail

TMUX_BIN="${TMUX_AI_NAV_TMUX_BIN:-$(command -v tmux || echo tmux)}"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="/tmp/tmux-ai-nav"

SESSION=$("$TMUX_BIN" display-message -p '#{session_name}')
WINDOW_IDX=$("$TMUX_BIN" display-message -p '#{window_index}')

cache_key="${SESSION}_${WINDOW_IDX}"

# Remove pin so generate-title.sh won't skip
rm -f "$CACHE_DIR/${cache_key}.pinned"

"$TMUX_BIN" display-message "Generating title..." 2>/dev/null

# Run fully detached so tmux's run-shell returns immediately
nohup bash "$PLUGIN_DIR/scripts/generate-title.sh" "$SESSION" "$WINDOW_IDX" </dev/null >/dev/null 2>&1 &
