#!/usr/bin/env bash
# daemon.sh — Background process that titles NEW windows once, then never again.
# Checks every 30s for untitled windows. Once a window gets a title, it's done forever.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${PLUGIN_DIR}/lib/cache.sh"

CACHE_DIR=$(get_state_dir)
LOG_FILE="$CACHE_DIR/daemon.log"
CHECK_INTERVAL=30

mkdir -p "$CACHE_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE"
}

# Atomic PID file write
printf '%s' $$ > "$CACHE_DIR/daemon.pid.tmp"
mv "$CACHE_DIR/daemon.pid.tmp" "$CACHE_DIR/daemon.pid"
log "Daemon started pid=$$"

cleanup() {
  log "Daemon exiting"
  rm -f "$CACHE_DIR/daemon.pid"
  exit 0
}
trap cleanup EXIT INT TERM

# One-time migration of old cache format
cache_migrate "$CACHE_DIR" "$TMUX_BIN" | while read -r msg; do log "$msg"; done

while true; do
  # List all windows across all sessions (include window_id for stable cache keys)
  windows=$("$TMUX_BIN" list-windows -a \
    -F '#{session_name} #{window_index} #{window_id}' 2>/dev/null) || {
    sleep "$CHECK_INTERVAL"
    continue
  }

  while read -r session_name window_idx window_id; do
    [[ -z "$session_name" ]] && continue

    key=$(cache_key "$session_name" "$window_id")

    # Already titled or pinned — skip forever
    cache_exists "$CACHE_DIR" "$key" "title" && continue
    cache_exists "$CACHE_DIR" "$key" "pinned" && continue

    # Generate title (pass index for tmux targeting, id for caching)
    bash "$PLUGIN_DIR/scripts/generate-title.sh" "$session_name" "$window_idx"

  done <<< "$windows"

  sleep "$CHECK_INTERVAL"
done
