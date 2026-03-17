#!/usr/bin/env bash
# sidebar.sh — Persistent left panel showing all windows/panes with AI titles.
# Renders in choose-tree style. Navigable with j/k/arrows, Enter to jump/expand.
# Multi-pane windows can be expanded to show individual panes.
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
declare -A EXPANDED=()

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
      -F '#{window_index}|#{window_name}|#{window_active}|#{pane_current_path}|#{window_panes}' 2>/dev/null) || continue

    while IFS='|' read -r win_idx win_name is_active pane_path pane_count; do
      local target="${sess}:${win_idx}"

      # Subtract sidebar pane from count if it lives in this window
      if [[ -n "$MY_PANE_ID" ]]; then
        local sidebar_in_window
        sidebar_in_window=$("$TMUX_BIN" list-panes -t "$target" -F '#{pane_id}' 2>/dev/null | grep -c "^${MY_PANE_ID}$")
        pane_count=$((pane_count - sidebar_in_window))
      fi

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

      # Pane count badge
      local badge=""
      [[ "$pane_count" -gt 1 ]] && badge=" ${DIM}[${pane_count}]${RESET}"

      local is_expanded="${EXPANDED[${target}]:-}"

      # Expand/collapse indicator for multi-pane windows
      local expand_icon=""
      if [[ "$pane_count" -gt 1 ]]; then
        if [[ "$is_expanded" == "1" ]]; then
          expand_icon="▾ "
        else
          expand_icon="▸ "
        fi
      fi

      if [[ $idx -eq $selected ]]; then
        output+="  ${BOLD}${WHITE}▸ ${active_dot}${expand_icon}${win_idx} ${win_name}${badge}${RESET}"$'\n'
        [[ -n "$summary" ]] && output+="      ${YELLOW}${summary}${RESET}"$'\n'
        output+="      ${BLUE}${sp}${RESET}"$'\n'
      else
        output+="    ${active_dot}${DIM}${expand_icon}${win_idx} ${win_name}${badge}${RESET}"$'\n'
        [[ -n "$summary" ]] && output+="      ${DIM}${summary}${RESET}"$'\n'
        output+="      ${DIM}${sp}${RESET}"$'\n'
      fi

      idx=$((idx + 1))

      # Render expanded panes
      if [[ "$is_expanded" == "1" ]] && [[ "$pane_count" -gt 1 ]]; then
        local panes
        panes=$("$TMUX_BIN" list-panes -t "$target" \
          -F '#{pane_id}|#{pane_index}|#{pane_current_command}|#{pane_current_path}|#{pane_active}' 2>/dev/null) || true

        local pane_lines=()
        while IFS='|' read -r p_id p_idx p_cmd p_path p_active; do
          [[ -z "$p_idx" ]] && continue
          # Skip the sidebar pane itself
          [[ -n "$MY_PANE_ID" ]] && [[ "$p_id" == "$MY_PANE_ID" ]] && continue
          pane_lines+=("${p_idx}|${p_cmd}|${p_path}|${p_active}")
        done <<< "$panes"

        local pane_total=${#pane_lines[@]}
        local pi=0
        for pline in "${pane_lines[@]}"; do
          IFS='|' read -r p_idx p_cmd p_path p_active <<< "$pline"
          local pane_target="${target}.${p_idx}"
          TARGETS+=("$pane_target")

          local connector="├─"
          [[ $pi -eq $((pane_total - 1)) ]] && connector="└─"

          local psp
          psp=$(short_path "$p_path" "$((MAX_TEXT - 10))")

          local pane_active_marker=""
          [[ "$p_active" == "1" ]] && pane_active_marker="${GREEN}●${RESET} "

          if [[ $idx -eq $selected ]]; then
            output+="      ${BOLD}${WHITE}${connector} ${pane_active_marker}${p_idx} ${p_cmd}  ${psp}${RESET}"$'\n'
          else
            output+="      ${DIM}${connector} ${pane_active_marker}${p_idx} ${p_cmd}  ${psp}${RESET}"$'\n'
          fi

          idx=$((idx + 1))
          pi=$((pi + 1))
        done
      fi

    done <<< "$windows"

    output+=$'\n'
  done <<< "$sessions"

  output+="${DIM}↑↓/jk nav  ⏎ expand/jump  Esc collapse  q hide${RESET}"

  # Fallback if selected was never set
  [[ $selected -eq -1 ]] && selected=0

  # Clamp selected if targets shrank (e.g. after collapse)
  local total_targets=${#TARGETS[@]}
  [[ $total_targets -gt 0 ]] && [[ $selected -ge $total_targets ]] && selected=$((total_targets - 1))

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
          '') # Bare Escape: collapse all expanded windows
            EXPANDED=()
            ;;
        esac
        ;;
      'k') selected=$(( (selected - 1 + total) % total )) ;;
      'j') selected=$(( (selected + 1) % total )) ;;
      '') # Enter — expand/collapse or jump
        if [[ $selected -lt $total ]]; then
          target="${TARGETS[$selected]}"
          if [[ "$target" == *.* ]]; then
            # Pane target: jump to that specific pane
            local_win="${target%%.*}"
            "$TMUX_BIN" switch-client -t "$local_win" 2>/dev/null
            "$TMUX_BIN" select-window -t "$local_win" 2>/dev/null
            "$TMUX_BIN" select-pane -t "$target" 2>/dev/null
          else
            # Window target: check pane count
            pane_count=$("$TMUX_BIN" list-panes -t "$target" 2>/dev/null | wc -l | tr -d ' ')
            if [[ "$pane_count" -gt 1 ]]; then
              # Toggle expand/collapse
              if [[ "${EXPANDED[${target}]:-}" == "1" ]]; then
                unset 'EXPANDED[${target}]'
              else
                EXPANDED["$target"]="1"
              fi
            else
              # Single pane: jump directly
              "$TMUX_BIN" switch-client -t "$target" 2>/dev/null
              "$TMUX_BIN" select-window -t "$target" 2>/dev/null
            fi
          fi
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
