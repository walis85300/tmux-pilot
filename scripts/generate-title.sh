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

# --- Cache key (stable: uses window_id, not index) ---

target="${SESSION}:${WINDOW_IDX}"
window_id=$("$TMUX_BIN" display-message -p -t "$target" '#{window_id}' 2>/dev/null) || exit 0
cache_key="${SESSION}::${window_id}"
pinned_file="$CACHE_DIR/${cache_key}.pinned"
title_file="$CACHE_DIR/${cache_key}.title"
summary_file="$CACHE_DIR/${cache_key}.summary"

# Never overwrite a pinned title
if [[ -f "$pinned_file" ]]; then
  log "Window ${target} is pinned, skipping"
  exit 0
fi

# Check window still exists
if ! "$TMUX_BIN" list-windows -t "$SESSION" -F '#{window_index}' 2>/dev/null | grep -q "^${WINDOW_IDX}$"; then
  log "Window ${target} no longer exists"
  exit 0
fi

# --- Gather context ---

session_name="$SESSION"
cwd=$("$TMUX_BIN" display-message -p -t "$target" '#{pane_current_path}' 2>/dev/null) || cwd=""
git_branch=""
if [[ -n "$cwd" ]]; then
  git_branch=$(git -C "$cwd" branch --show-current 2>/dev/null) || git_branch=""
fi
cwd_short="${cwd/#$HOME/~}"

context="Session: ${session_name}"
[[ -n "$cwd_short" ]] && context+=", CWD: ${cwd_short}"
[[ -n "$git_branch" ]] && context+=", Branch: ${git_branch}"

# --- Capture pane content ---

pane_list=$("$TMUX_BIN" list-panes -t "$target" \
  -F '#{pane_id}|#{pane_index}|#{pane_active}' 2>/dev/null) || exit 0

pane_count=$(echo "$pane_list" | wc -l | tr -d ' ')

if [[ "$pane_count" -le 1 ]]; then
  active_pane=$(echo "$pane_list" | grep '|1$' | cut -d'|' -f1)
  [[ -z "$active_pane" ]] && exit 0
  content=$("$TMUX_BIN" capture-pane -p -t "$active_pane" -S -60 2>/dev/null) || exit 0
else
  content="Window has ${pane_count} panes:"$'\n'
  context+=", Panes: ${pane_count}"
  while IFS='|' read -r pane_id pane_idx pane_active; do
    [[ -z "$pane_id" ]] && continue
    label="[Pane ${pane_idx}]"
    [[ "$pane_active" == "1" ]] && label="[Pane ${pane_idx} - active]"
    pane_content=$("$TMUX_BIN" capture-pane -p -t "$pane_id" -S -30 2>/dev/null) || pane_content="(empty)"
    content+=$'\n'"${label}"$'\n'"${pane_content}"$'\n'
  done <<< "$pane_list"
fi

log "Generating title for ${target} (${context})..."

response=$(bash "$PLUGIN_DIR/lib/api.sh" "$context" "$content" 2>>"$LOG_FILE") || true

# --- Sanitize and validate ---

sanitize_title() {
  local raw="$1"
  # Take first line only
  raw=$(echo "$raw" | head -1)
  # Strip markdown formatting
  raw=$(echo "$raw" | sed 's/\*\*//g; s/__//g; s/`//g; s/\[//g; s/\]//g; s/#//g')
  # Strip surrounding quotes
  raw=$(echo "$raw" | sed "s/^[\"']//; s/[\"']$//")
  # Strip leading/trailing whitespace
  raw=$(echo "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  # Truncate to 30 chars
  echo "${raw:0:30}"
}

if [[ -n "$response" ]]; then
  title=$(sanitize_title "$(echo "$response" | head -1)")
  summary=$(echo "$response" | tail -n +2 | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [[ -n "$title" ]]; then
    printf '%s' "$title" > "$title_file"
    printf '%s' "$summary" > "$summary_file"

    "$TMUX_BIN" rename-window -t "$target" "$title" 2>/dev/null || true
    "$TMUX_BIN" set-option -t "$target" automatic-rename off 2>/dev/null || true

    log "Titled ${target} -> '$title' ($summary)"
  else
    # Fallback to CWD basename
    fallback=$(basename "${cwd:-unknown}")
    "$TMUX_BIN" rename-window -t "$target" "$fallback" 2>/dev/null || true
    log "Empty title for ${target}, fallback to '$fallback'"
  fi
else
  log "Claude failed for ${target}"
fi
