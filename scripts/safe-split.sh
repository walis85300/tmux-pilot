#!/usr/bin/env bash
# safe-split.sh — Split a pane, but never inside the sidebar.
# If the active pane is the sidebar, split the first non-sidebar pane instead.
# Usage: safe-split.sh [-h|-v] (passed through to split-window)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

CACHE_DIR=$(get_state_dir)
SIDEBAR_MARKER="$CACHE_DIR/sidebar.pane_id"
SPLIT_FLAG="${1:--v}"

active_pane=$("$TMUX_BIN" display-message -p '#{pane_id}' 2>/dev/null)

# If no sidebar, just split normally
if [[ ! -f "$SIDEBAR_MARKER" ]]; then
  "$TMUX_BIN" split-window "$SPLIT_FLAG" -c '#{pane_current_path}' 2>/dev/null
  exit 0
fi

sidebar_id=$(cat "$SIDEBAR_MARKER")

if [[ "$active_pane" == "$sidebar_id" ]]; then
  # Active pane is the sidebar — find the main pane and split that instead
  main_pane=$("$TMUX_BIN" list-panes -F '#{pane_id}|#{pane_active}' 2>/dev/null | \
    grep -v "^${sidebar_id}|" | head -1 | cut -d'|' -f1)

  if [[ -n "$main_pane" ]]; then
    main_path=$("$TMUX_BIN" display-message -t "$main_pane" -p '#{pane_current_path}' 2>/dev/null)
    "$TMUX_BIN" split-window "$SPLIT_FLAG" -t "$main_pane" -c "$main_path" 2>/dev/null
  fi
else
  # Normal split
  "$TMUX_BIN" split-window "$SPLIT_FLAG" -c '#{pane_current_path}' 2>/dev/null
fi
