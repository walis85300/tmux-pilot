#!/usr/bin/env bash
# generate-title.sh — Generate an AI title for a single window.
# Usage: generate-title.sh <session_name> <window_index>
# Skips if the window has a pinned (manual) title.

set -uo pipefail

TMUX_BIN="${TMUX_AI_NAV_TMUX_BIN:-$(command -v tmux || echo tmux)}"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="/tmp/tmux-ai-nav"
LOG_FILE="$CACHE_DIR/daemon.log"

SESSION="$1"
WINDOW_IDX="$2"

mkdir -p "$CACHE_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE"
}

cache_key="${SESSION}_${WINDOW_IDX}"
pinned_file="$CACHE_DIR/${cache_key}.pinned"
title_file="$CACHE_DIR/${cache_key}.title"
summary_file="$CACHE_DIR/${cache_key}.summary"

# Never overwrite a pinned title
if [[ -f "$pinned_file" ]]; then
  log "Window ${SESSION}:${WINDOW_IDX} is pinned, skipping"
  exit 0
fi

# Check window still exists
if ! "$TMUX_BIN" list-windows -t "$SESSION" -F '#{window_index}' 2>/dev/null | grep -q "^${WINDOW_IDX}$"; then
  log "Window ${SESSION}:${WINDOW_IDX} no longer exists"
  exit 0
fi

# Get the active pane in this window
active_pane=$("$TMUX_BIN" list-panes -t "${SESSION}:${WINDOW_IDX}" \
  -F '#{pane_id} #{pane_active}' 2>/dev/null | grep ' 1$' | cut -d' ' -f1)

[[ -z "$active_pane" ]] && exit 0

# Capture last 30 lines
content=$("$TMUX_BIN" capture-pane -p -t "$active_pane" -S -30 2>/dev/null) || exit 0

log "Generating title for ${SESSION}:${WINDOW_IDX}..."

response=$(bash "$PLUGIN_DIR/lib/api.sh" "$content" 2>>"$LOG_FILE") || true

if [[ -n "$response" ]]; then
  title=$(echo "$response" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  summary=$(echo "$response" | tail -n +2 | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [[ -n "$title" ]]; then
    printf '%s' "$title" > "$title_file"
    printf '%s' "$summary" > "$summary_file"

    "$TMUX_BIN" rename-window -t "${SESSION}:${WINDOW_IDX}" "$title" 2>/dev/null || true
    "$TMUX_BIN" set-option -t "${SESSION}:${WINDOW_IDX}" automatic-rename off 2>/dev/null || true

    log "Titled ${SESSION}:${WINDOW_IDX} -> '$title' ($summary)"
  fi
else
  log "Claude failed for ${SESSION}:${WINDOW_IDX}"
fi
