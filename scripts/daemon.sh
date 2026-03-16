#!/usr/bin/env bash
# daemon.sh — Background daemon that renames tmux windows with AI-generated titles.
# For each window: captures the active pane, calls Claude, renames the window.
# Usage: daemon.sh
# Runs for ALL sessions. Killed via toggle.sh or session-closed hook.

set -uo pipefail

TMUX_BIN="${TMUX_AI_NAV_TMUX_BIN:-$(command -v tmux || echo tmux)}"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="/tmp/tmux-ai-nav"
LOG_FILE="$CACHE_DIR/daemon.log"
REFRESH_INTERVAL="${TMUX_AI_NAV_REFRESH:-15}"

mkdir -p "$CACHE_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE"
}

echo $$ > "$CACHE_DIR/daemon.pid"
log "Daemon started pid=$$"

cleanup() {
  log "Daemon exiting"
  # Kill any child claude processes
  jobs -p 2>/dev/null | xargs kill 2>/dev/null || true
  rm -f "$CACHE_DIR/daemon.pid"
  exit 0
}
trap cleanup EXIT INT TERM

# Restore saved titles on startup
restore_titles() {
  local save_file="$CACHE_DIR/titles.saved"
  [[ ! -f "$save_file" ]] && return

  while IFS=$'\t' read -r session_name window_idx title summary; do
    if "$TMUX_BIN" has-session -t "$session_name" 2>/dev/null; then
      "$TMUX_BIN" rename-window -t "${session_name}:${window_idx}" "$title" 2>/dev/null || true
    fi
  done < "$save_file"
  log "Restored titles from $save_file"
}

# Save all current titles to disk for persistence
save_titles() {
  local save_file="$CACHE_DIR/titles.saved"
  : > "$save_file"
  for key_file in "$CACHE_DIR"/*.title; do
    [[ -f "$key_file" ]] || continue
    local base
    base=$(basename "$key_file" .title)
    local session_name="${base%%_*}"
    local window_idx="${base#*_}"
    local title summary_file
    title=$(cat "$key_file")
    summary_file="$CACHE_DIR/${base}.summary"
    local summary=""
    [[ -f "$summary_file" ]] && summary=$(cat "$summary_file")
    printf '%s\t%s\t%s\t%s\n' "$session_name" "$window_idx" "$title" "$summary" >> "$save_file"
  done
}

restore_titles

while true; do
  # List ALL windows across ALL sessions
  # Format: session_name|window_index|pane_id (active pane)|pane_current_command
  windows=$("$TMUX_BIN" list-windows -a \
    -F '#{session_name}|#{window_index}|#{pane_id}|#{pane_current_command}' 2>/dev/null) || {
    sleep "$REFRESH_INTERVAL"
    continue
  }

  while IFS='|' read -r session_name window_idx active_pane_id pane_cmd; do
    [[ -z "$session_name" ]] && continue

    # Capture last 30 lines of the active pane in this window
    content=$("$TMUX_BIN" capture-pane -p -t "$active_pane_id" -S -30 2>/dev/null) || continue

    # Hash content to detect changes
    new_hash=$(printf '%s' "$content" | md5 -q 2>/dev/null || printf '%s' "$content" | md5sum 2>/dev/null | cut -d' ' -f1)

    cache_key="${session_name}_${window_idx}"
    hash_file="$CACHE_DIR/${cache_key}.hash"
    title_file="$CACHE_DIR/${cache_key}.title"
    summary_file="$CACHE_DIR/${cache_key}.summary"

    old_hash=""
    [[ -f "$hash_file" ]] && old_hash=$(cat "$hash_file")

    # Skip if content hasn't changed
    if [[ "$new_hash" == "$old_hash" ]] && [[ -f "$title_file" ]]; then
      continue
    fi

    printf '%s' "$new_hash" > "$hash_file"
    log "Window ${session_name}:${window_idx} changed, calling Claude..."

    # Call Claude (synchronous per window, but the daemon loop handles timing)
    response=$(bash "$PLUGIN_DIR/lib/api.sh" "$content" 2>>"$LOG_FILE") || true

    if [[ -n "$response" ]]; then
      title=$(echo "$response" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      summary=$(echo "$response" | tail -n +2 | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      if [[ -n "$title" ]]; then
        printf '%s' "$title" > "$title_file"
        printf '%s' "$summary" > "$summary_file"

        # Rename the tmux window
        "$TMUX_BIN" rename-window -t "${session_name}:${window_idx}" "$title" 2>/dev/null || true
        # Prevent tmux from auto-renaming it back
        "$TMUX_BIN" set-option -t "${session_name}:${window_idx}" automatic-rename off 2>/dev/null || true

        log "Renamed ${session_name}:${window_idx} -> '$title' ($summary)"
      fi
    else
      # Fallback: use command name if no cached title
      if [[ ! -s "$title_file" ]]; then
        printf '%s' "$pane_cmd" > "$title_file"
        "$TMUX_BIN" rename-window -t "${session_name}:${window_idx}" "$pane_cmd" 2>/dev/null || true
      fi
      log "Claude failed for ${session_name}:${window_idx}, fallback to '$pane_cmd'"
    fi

  done <<< "$windows"

  # Persist titles after each full scan
  save_titles

  sleep "$REFRESH_INTERVAL"
done
