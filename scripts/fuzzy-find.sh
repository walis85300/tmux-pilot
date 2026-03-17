#!/usr/bin/env bash
# fuzzy-find.sh — Fuzzy finder for tmux windows using fzf.
# Searches across AI-generated titles and summaries.
# Writes result to $CACHE_DIR/fuzzy.result for the sidebar to read.
# Format: "JUMP:target" or "SELECT:target"

set -uo pipefail

TMUX_BIN="${TMUX_AI_NAV_TMUX_BIN:-$(command -v tmux || echo tmux)}"
CACHE_DIR="/tmp/tmux-ai-nav"
RESULT_FILE="$CACHE_DIR/fuzzy.result"

rm -f "$RESULT_FILE"

# Build candidate list from live tmux state + cached titles/summaries
candidates=""
while read -r sess; do
  windows=$("$TMUX_BIN" list-windows -t "$sess" \
    -F '#{window_index}|#{window_name}' 2>/dev/null) || continue
  while IFS='|' read -r win_idx win_name; do
    [[ -z "$win_idx" ]] && continue
    target="${sess}:${win_idx}"
    cache_key="${sess}_${win_idx}"
    title=$(cat "$CACHE_DIR/${cache_key}.title" 2>/dev/null) || title=""
    [[ -z "$title" ]] && title="$win_name"
    summary=$(cat "$CACHE_DIR/${cache_key}.summary" 2>/dev/null) || summary=""
    candidates+="$(printf '%s\t%s\t%s\t%s' "$target" "$sess" "$title" "$summary")"$'\n'
  done <<< "$windows"
done <<< "$("$TMUX_BIN" list-sessions -F '#{session_name}' 2>/dev/null)"

[[ -z "$candidates" ]] && exit 0

# Pipe into fzf
# Field 1: target (hidden), Fields 2+: session, title, summary (visible + searchable)
# MODE: "sidebar" writes to result file, "standalone" jumps directly
MODE="${1:-sidebar}"

selected=$(printf '%s' "$candidates" | fzf \
  --reverse \
  --delimiter='\t' \
  --with-nth=2.. \
  --expect=tab \
  --header='enter: jump  tab: select in sidebar' \
  --prompt='> ' \
  --no-info)

[[ -z "$selected" ]] && exit 0

# First line: key pressed (empty for enter, "tab" for tab)
key=$(echo "$selected" | head -1)
# Second line: the selected entry
entry=$(echo "$selected" | tail -1)
target=$(echo "$entry" | cut -f1)

if [[ -n "$target" ]]; then
  if [[ "$MODE" == "standalone" ]]; then
    # Jump directly — no sidebar involved
    "$TMUX_BIN" switch-client -t "$target" 2>/dev/null
    "$TMUX_BIN" select-window -t "$target" 2>/dev/null
  else
    # Write result for sidebar to read
    if [[ "$key" == "tab" ]]; then
      printf 'SELECT:%s' "$target" > "$RESULT_FILE"
    else
      printf 'JUMP:%s' "$target" > "$RESULT_FILE"
    fi
  fi
fi
