#!/usr/bin/env bash
# sidebar.sh — Persistent left panel showing all windows/panes with AI titles.
# Renders in choose-tree style. Navigable with j/k/arrows, Enter to jump.
# Reads its own pane ID from the marker file.

set -uo pipefail

TMUX_BIN="${TMUX_AI_NAV_TMUX_BIN:-$(command -v tmux || echo tmux)}"
CACHE_DIR="/tmp/tmux-ai-nav"
MY_PANE_ID=$(cat "$CACHE_DIR/sidebar.pane_id" 2>/dev/null)

# Dynamic truncation based on actual pane width (6 chars indent)
PANE_WIDTH=$(tput cols 2>/dev/null || echo 28)
MAX_TEXT=$(( PANE_WIDTH - 8 ))
[[ $MAX_TEXT -lt 10 ]] && MAX_TEXT=10

selected=-1  # -1 = not yet initialized, will be set to current window

# Colors
BOLD=$(tput bold 2>/dev/null || true)
DIM=$(tput dim 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
BLUE=$(tput setaf 4 2>/dev/null || true)
WHITE=$(tput setaf 7 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

# Hide cursor to avoid flicker
tput civis 2>/dev/null || true
trap 'tput cnorm 2>/dev/null || true' EXIT

declare -a TARGETS=()
LAST_OUTPUT=""

short_path() {
  local p="${1/#$HOME/\~}"
  local max="${2:-20}"
  if [[ ${#p} -gt $max ]]; then
    printf '…%s' "${p: -$((max - 1))}"
  else
    printf '%s' "$p"
  fi
}

build_and_render() {
  TARGETS=()

  local current_session current_window
  current_session=$("$TMUX_BIN" display-message -p '#{session_name}' 2>/dev/null)
  current_window=$("$TMUX_BIN" display-message -p '#{window_index}' 2>/dev/null)

  local sessions
  sessions=$("$TMUX_BIN" list-sessions -F '#{session_name}' 2>/dev/null) || return

  local output=""
  local idx=0

  while read -r sess; do
    local sess_marker=" "
    [[ "$sess" == "$current_session" ]] && sess_marker="${GREEN}▸${RESET}"
    output+="${sess_marker} ${BOLD}${CYAN}${sess}${RESET}"$'\n'

    local windows
    windows=$("$TMUX_BIN" list-windows -t "$sess" \
      -F '#{window_index}|#{window_name}|#{window_active}|#{pane_current_path}' 2>/dev/null) || continue

    while IFS='|' read -r win_idx win_name is_active pane_path; do
      local target="${sess}:${win_idx}"
      TARGETS+=("$target")

      # Auto-select current window on first render
      if [[ $selected -eq -1 ]] && [[ "$sess" == "$current_session" ]] && [[ "$win_idx" == "$current_window" ]]; then
        selected=$idx
      fi

      local cache_key="${sess}_${win_idx}"
      local summary_file="$CACHE_DIR/${cache_key}.summary"
      local summary=""
      [[ -f "$summary_file" ]] && summary=$(cat "$summary_file")

      local sp
      sp=$(short_path "$pane_path" "$MAX_TEXT")

      [[ ${#win_name} -gt $MAX_TEXT ]] && win_name="${win_name:0:$((MAX_TEXT - 1))}…"
      [[ ${#summary} -gt $MAX_TEXT ]] && summary="${summary:0:$((MAX_TEXT - 1))}…"

      local active_dot=""
      if [[ "$is_active" == "1" ]] && [[ "$sess" == "$current_session" ]]; then
        active_dot="${GREEN}● ${RESET}"
      fi

      if [[ $idx -eq $selected ]]; then
        output+="  ${BOLD}${WHITE}▸ ${active_dot}${win_idx} ${win_name}${RESET}"$'\n'
        [[ -n "$summary" ]] && output+="      ${YELLOW}${summary}${RESET}"$'\n'
        output+="      ${BLUE}${sp}${RESET}"$'\n'
      else
        output+="    ${active_dot}${DIM}${win_idx} ${win_name}${RESET}"$'\n'
        [[ -n "$summary" ]] && output+="      ${DIM}${summary}${RESET}"$'\n'
        output+="      ${DIM}${sp}${RESET}"$'\n'
      fi

      idx=$((idx + 1))
    done <<< "$windows"

    output+=$'\n'
  done <<< "$sessions"

  output+="${DIM}↑↓/jk nav  ⏎ jump  q hide${RESET}"

  # Fallback if selected was never set
  [[ $selected -eq -1 ]] && selected=0

  # Only redraw if content changed (prevents flicker)
  if [[ "$output" != "$LAST_OUTPUT" ]]; then
    LAST_OUTPUT="$output"
    tput home 2>/dev/null || printf '\033[H'
    tput ed 2>/dev/null || printf '\033[J'
    printf '%s\n' "$output"
  fi
}

build_and_render

while true; do
  if IFS= read -rsn1 -t 2 key; then
    total=${#TARGETS[@]}
    [[ $total -eq 0 ]] && { build_and_render; continue; }

    case "$key" in
      $'\x1b')
        read -rsn2 -t 0.1 seq || true
        case "$seq" in
          '[A') selected=$(( (selected - 1 + total) % total )) ;;
          '[B') selected=$(( (selected + 1) % total )) ;;
        esac
        ;;
      'k') selected=$(( (selected - 1 + total) % total )) ;;
      'j') selected=$(( (selected + 1) % total )) ;;
      '') # Enter — jump to selected window (works cross-session)
        if [[ $selected -lt $total ]]; then
          target="${TARGETS[$selected]}"
          "$TMUX_BIN" switch-client -t "$target" 2>/dev/null
          "$TMUX_BIN" select-window -t "$target" 2>/dev/null
        fi
        ;;
      'q')
        "$TMUX_BIN" run-shell "bash '$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/toggle-sidebar.sh'" 2>/dev/null
        exit 0
        ;;
    esac
    LAST_OUTPUT=""  # Force redraw on keypress
    build_and_render
  else
    build_and_render
  fi
done
