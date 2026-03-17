#!/usr/bin/env bash
# generate-title.sh — Generate an AI title for a single window.
# Usage: generate-title.sh <session_name> <window_index>
# Skips if the window has a pinned (manual) title.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_DIR=$(get_state_dir)
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

# Get all panes in this window
pane_list=$("$TMUX_BIN" list-panes -t "${SESSION}:${WINDOW_IDX}" \
  -F '#{pane_id}|#{pane_index}|#{pane_active}' 2>/dev/null) || exit 0

pane_count=$(echo "$pane_list" | wc -l | tr -d ' ')

if [[ "$pane_count" -le 1 ]]; then
  # Single pane: capture 30 lines from active pane
  active_pane=$(echo "$pane_list" | grep '|1$' | cut -d'|' -f1)
  [[ -z "$active_pane" ]] && exit 0
  content=$("$TMUX_BIN" capture-pane -p -t "$active_pane" -S -30 2>/dev/null) || exit 0
else
  # Multiple panes: capture 15 lines from each for a holistic summary
  content="Window has ${pane_count} panes:"$'\n'
  while IFS='|' read -r pane_id pane_idx pane_active; do
    [[ -z "$pane_id" ]] && continue
    label="[Pane ${pane_idx}]"
    [[ "$pane_active" == "1" ]] && label="[Pane ${pane_idx} - active]"
    pane_content=$("$TMUX_BIN" capture-pane -p -t "$pane_id" -S -15 2>/dev/null) || pane_content="(empty)"
    content+=$'\n'"${label}"$'\n'"${pane_content}"$'\n'
  done <<< "$pane_list"
fi

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
