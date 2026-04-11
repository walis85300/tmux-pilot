#!/usr/bin/env bash
# cache.sh — Shared cache key computation and file operations.
# Cache key format: {session}::{window_id} (:: is invalid in tmux session names)
# Uses stable window_id (@N) instead of window_index which changes on reorder.

# Build a cache key from session name and window id
# Usage: cache_key "my-session" "@5"
cache_key() {
  local session="$1"
  local window_id="$2"
  echo "${session}::${window_id}"
}

# Read a cache file value, or empty string if missing
# Usage: cache_read "$cache_dir" "$key" "title"
cache_read() {
  local dir="$1" key="$2" suffix="$3"
  local file="${dir}/${key}.${suffix}"
  [[ -f "$file" ]] && cat "$file" || true
}

# Write a value to a cache file
# Usage: cache_write "$cache_dir" "$key" "title" "My Title"
cache_write() {
  local dir="$1" key="$2" suffix="$3" value="$4"
  printf '%s' "$value" > "${dir}/${key}.${suffix}"
}

# Check if a cache file exists
# Usage: cache_exists "$cache_dir" "$key" "title"
cache_exists() {
  local dir="$1" key="$2" suffix="$3"
  [[ -f "${dir}/${key}.${suffix}" ]]
}

# Migrate old-format cache files (session_index.ext → session::@id.ext)
# Called once on daemon startup.
# Usage: cache_migrate "$cache_dir" "$tmux_bin"
cache_migrate() {
  local dir="$1" tmux_bin="$2"
  local migrated=0

  # Build a lookup of session:index → window_id
  local windows
  windows=$("$tmux_bin" list-windows -a -F '#{session_name} #{window_index} #{window_id}' 2>/dev/null) || return 0

  while read -r session idx wid; do
    [[ -z "$session" ]] && continue
    local old_key="${session}_${idx}"
    local new_key="${session}::${wid}"

    for ext in title summary pinned; do
      local old_file="${dir}/${old_key}.${ext}"
      local new_file="${dir}/${new_key}.${ext}"
      if [[ -f "$old_file" ]] && [[ ! -f "$new_file" ]]; then
        mv "$old_file" "$new_file" 2>/dev/null && migrated=$((migrated + 1))
      fi
    done
  done <<< "$windows"

  [[ "$migrated" -gt 0 ]] && echo "Migrated $migrated cache files to new format"
}
