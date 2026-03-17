#!/usr/bin/env bash
# daemon.sh — Background process that titles NEW windows once, then never again.
# Checks every 30s for untitled windows. Once a window gets a title, it's done forever.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_DIR=$(get_state_dir)
LOG_FILE="$CACHE_DIR/daemon.log"
CHECK_INTERVAL=30

mkdir -p "$CACHE_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE"
}

echo $$ > "$CACHE_DIR/daemon.pid"
log "Daemon started pid=$$"

cleanup() {
  log "Daemon exiting"
  rm -f "$CACHE_DIR/daemon.pid"
  exit 0
}
trap cleanup EXIT INT TERM

while true; do
  # List all windows across all sessions
  windows=$("$TMUX_BIN" list-windows -a \
    -F '#{session_name} #{window_index}' 2>/dev/null) || {
    sleep "$CHECK_INTERVAL"
    continue
  }

  while read -r session_name window_idx; do
    [[ -z "$session_name" ]] && continue

    cache_key="${session_name}_${window_idx}"
    title_file="$CACHE_DIR/${cache_key}.title"
    pinned_file="$CACHE_DIR/${cache_key}.pinned"

    # Already titled or pinned — skip forever
    [[ -f "$title_file" ]] && continue
    [[ -f "$pinned_file" ]] && continue

    # Generate title
    bash "$PLUGIN_DIR/scripts/generate-title.sh" "$session_name" "$window_idx"

  done <<< "$windows"

  sleep "$CHECK_INTERVAL"
done
