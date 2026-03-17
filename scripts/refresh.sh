#!/usr/bin/env bash
# refresh.sh — Regenerate AI title for the current window (manual trigger).
# Ignores pinned status — if you ask for it, you get it.
# Usage: refresh.sh (no args, uses current window)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_DIR=$(get_state_dir)

SESSION=$("$TMUX_BIN" display-message -p '#{session_name}')
WINDOW_IDX=$("$TMUX_BIN" display-message -p '#{window_index}')

cache_key="${SESSION}_${WINDOW_IDX}"

# Remove pin so generate-title.sh won't skip
rm -f "$CACHE_DIR/${cache_key}.pinned"

"$TMUX_BIN" display-message "Generating title..." 2>/dev/null

# Run fully detached so tmux's run-shell returns immediately
nohup bash "$PLUGIN_DIR/scripts/generate-title.sh" "$SESSION" "$WINDOW_IDX" </dev/null >/dev/null 2>&1 &
