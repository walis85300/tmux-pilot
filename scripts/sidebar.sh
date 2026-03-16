#!/usr/bin/env bash
# sidebar.sh — Persistent left panel showing all windows/panes with AI titles.
# Renders in choose-tree style. Navigable with j/k/arrows, Enter to jump.
# Reads its own pane ID from the marker file.

set -uo pipefail

TMUX_BIN="${TMUX_AI_NAV_TMUX_BIN:-$(command -v tmux || echo tmux)}"
CACHE_DIR="/tmp/tmux-ai-nav"
MY_PANE_ID=$(cat "$CACHE_DIR/sidebar.pane_id" 2>/dev/null)

selected=0

# Colors
BOLD=$(tput bold 2>/dev/null || true)
DIM=$(tput dim 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
BLUE=$(tput setaf 4 2>/dev/null || true)
MAGENTA=$(tput setaf 5 2>/dev/null || true)
WHITE=$(tput setaf 7 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

# Collect navigable entries: session:window_index targets
# Each entry maps to a tmux target for jumping
declare -a TARGETS=()

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
  clear

  local current_session current_window
  current_session=$("$TMUX_BIN" display-message -p '#{session_name}' 2>/dev/null)
  current_window=$("$TMUX_BIN" display-message -p '#{window_index}' 2>/dev/null)

  # Get all sessions
  local sessions
  sessions=$("$TMUX_BIN" list-sessions -F '#{session_name}' 2>/dev/null) || return

  local idx=0

  while read -r sess; do
    # Session header
    local sess_marker=" "
    [[ "$sess" == "$current_session" ]] && sess_marker="${GREEN}▸${RESET}"
    printf '%s\n' "${sess_marker} ${BOLD}${CYAN}${sess}${RESET}"

    # Windows in this session
    local windows
    windows=$("$TMUX_BIN" list-windows -t "$sess" \
      -F '#{window_index}|#{window_name}|#{window_active}|#{pane_current_path}' 2>/dev/null) || continue

    while IFS='|' read -r win_idx win_name is_active pane_path; do
      local target="${sess}:${win_idx}"
      TARGETS+=("$target")

      # Get summary from cache
      local cache_key="${sess}_${win_idx}"
      local summary_file="$CACHE_DIR/${cache_key}.summary"
      local summary=""
      [[ -f "$summary_file" ]] && summary=$(cat "$summary_file")

      local sp
      sp=$(short_path "$pane_path" 20)

      # Truncate for sidebar width (28 cols, 6 indent = 22 usable)
      [[ ${#win_name} -gt 20 ]] && win_name="${win_name:0:19}…"
      [[ ${#summary} -gt 20 ]] && summary="${summary:0:19}…"

      # Active window marker
      local active_dot=""
      if [[ "$is_active" == "1" ]] && [[ "$sess" == "$current_session" ]]; then
        active_dot="${GREEN}● ${RESET}"
      fi

      if [[ $idx -eq $selected ]]; then
        printf '%s\n' "  ${BOLD}${WHITE}▸ ${active_dot}${win_idx} ${win_name}${RESET}"
        [[ -n "$summary" ]] && printf '%s\n' "      ${YELLOW}${summary}${RESET}"
        printf '%s\n' "      ${BLUE}${sp}${RESET}"
      else
        printf '%s\n' "    ${active_dot}${DIM}${win_idx} ${win_name}${RESET}"
        [[ -n "$summary" ]] && printf '%s\n' "      ${DIM}${summary}${RESET}"
        printf '%s\n' "      ${DIM}${sp}${RESET}"
      fi

      idx=$((idx + 1))
    done <<< "$windows"

    printf '\n'
  done <<< "$sessions"

  # Footer
  printf '%s\n' "${DIM}↑↓/jk nav  ⏎ jump  q hide${RESET}"
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
      '') # Enter — jump to selected window
        if [[ $selected -lt $total ]]; then
          target="${TARGETS[$selected]}"
          "$TMUX_BIN" select-window -t "$target" 2>/dev/null
        fi
        ;;
      'q')
        # Hide sidebar — signal toggle to close us
        "$TMUX_BIN" run-shell "bash '$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/toggle-sidebar.sh'" 2>/dev/null
        exit 0
        ;;
    esac
    build_and_render
  else
    # Timeout — refresh to pick up new titles
    build_and_render
  fi
done
