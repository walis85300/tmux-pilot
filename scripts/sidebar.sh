#!/usr/bin/env bash
# sidebar.sh — Persistent left panel showing all windows/panes with AI titles.
# Navigable with j/k/arrows, Enter to jump/expand. Sources sidebar-commands.sh
# and sidebar-render.sh for command execution and rendering respectively.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=helpers.sh
source "${SCRIPT_DIR}/helpers.sh"
# shellcheck source=../lib/cache.sh
source "${PLUGIN_DIR}/lib/cache.sh"

CACHE_DIR=$(get_state_dir)
MY_PANE_ID=$(cat "$CACHE_DIR/sidebar.pane_id" 2>/dev/null)

# Recalculated on every render cycle to respond to pane resizing
PANE_WIDTH=28
MAX_TEXT=20

refresh_dimensions() {
  PANE_WIDTH=$("$TMUX_BIN" display-message -p '#{pane_width}' 2>/dev/null || tput cols 2>/dev/null || echo 28)
  MAX_TEXT=$(( PANE_WIDTH - 8 ))
  [[ $MAX_TEXT -lt 10 ]] && MAX_TEXT=10
}
refresh_dimensions

selected=-1           # -1 = not yet initialized, will be set to current window
EXPANDED_LIST=""      # delimited string for Bash 3.2 compat
SHOW_HELP=0

# Colors — exported to sourced sidebar-commands.sh and sidebar-render.sh
# shellcheck disable=SC2034  # Vars used in sourced files
setup_colors() {
  BOLD=$(tput bold 2>/dev/null || true);  DIM=$(tput dim 2>/dev/null || true)
  REV=$(tput rev 2>/dev/null || true);    GREEN=$(tput setaf 2 2>/dev/null || true)
  CYAN=$(tput setaf 6 2>/dev/null || true); YELLOW=$(tput setaf 3 2>/dev/null || true)
  BLUE=$(tput setaf 4 2>/dev/null || true); MAGENTA=$(tput setaf 5 2>/dev/null || true)
  WHITE=$(tput setaf 7 2>/dev/null || true); BG_GREEN=$(tput setab 2 2>/dev/null || true)
  BLACK=$(tput setaf 0 2>/dev/null || true); RESET=$(tput sgr0 2>/dev/null || true)
}
setup_colors

# Source extracted modules (after variables and colors are set)
# shellcheck source=sidebar-commands.sh
source "${SCRIPT_DIR}/sidebar-commands.sh"
# shellcheck source=sidebar-render.sh
source "${SCRIPT_DIR}/sidebar-render.sh"

tput civis 2>/dev/null || true  # Hide cursor to avoid flicker
trap 'tput cnorm 2>/dev/null || true' EXIT

# SIGUSR1 interrupts the read timeout for immediate redraw
NEEDS_REDRAW=0
trap 'NEEDS_REDRAW=1' USR1

# Save our PID so hooks can signal us
echo $$ > "$CACHE_DIR/sidebar.pid"

declare -a TARGETS=()
# shellcheck disable=SC2034
LAST_OUTPUT=""

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
            EXPANDED_LIST=""
            ;;
        esac
        ;;
      'k') selected=$(( (selected - 1 + total) % total )) ;;
      'j') selected=$(( (selected + 1) % total )) ;;
      '') # Enter — expand/collapse or jump
        if [[ $selected -lt $total ]]; then
          target="${TARGETS[$selected]}"
          # Check if target is already the active window (skip jump to avoid flicker)
          current_sess=$("$TMUX_BIN" display-message -p '#{session_name}' 2>/dev/null)
          current_win=$("$TMUX_BIN" display-message -p '#{window_index}' 2>/dev/null)
          current_target="${current_sess}:${current_win}"

          if [[ "$target" == *.* ]]; then
            # Pane target: jump to that specific pane
            local_win="${target%%.*}"
            if [[ "$local_win" != "$current_target" ]]; then
              "$TMUX_BIN" switch-client -t "$local_win" 2>/dev/null
              "$TMUX_BIN" select-window -t "$local_win" 2>/dev/null
            fi
            "$TMUX_BIN" select-pane -t "$target" 2>/dev/null
          else
            # Window target: check pane count (subtract sidebar if present)
            pane_count=$("$TMUX_BIN" list-panes -t "$target" 2>/dev/null | wc -l | tr -d ' ')
            if [[ -n "$MY_PANE_ID" ]]; then
              sidebar_here=$("$TMUX_BIN" list-panes -t "$target" -F '#{pane_id}' 2>/dev/null | grep -c "^${MY_PANE_ID}$")
              pane_count=$((pane_count - sidebar_here))
            fi
            if [[ "$pane_count" -gt 1 ]]; then
              # Toggle expand/collapse
              if [[ "$EXPANDED_LIST" == *"|${target}|"* ]]; then
                EXPANDED_LIST="${EXPANDED_LIST//|${target}|/}"
              else
                EXPANDED_LIST="${EXPANDED_LIST}|${target}|"
              fi
            else
              # Single pane: only jump if not already there
              if [[ "$target" != "$current_target" ]]; then
                "$TMUX_BIN" switch-client -t "$target" 2>/dev/null
                "$TMUX_BIN" select-window -t "$target" 2>/dev/null
              fi
            fi
          fi
        fi
        ;;
      'x') # Kill window or pane with confirmation
        if [[ $selected -lt $total ]]; then
          target="${TARGETS[$selected]}"
          if [[ "$target" == *.* ]]; then
            # Pane target
            printf '\033[H\033[J'
            printf '%s' "${BOLD}${YELLOW}Kill pane ${target}? (y/n)${RESET} "
            IFS= read -rsn1 confirm
            if [[ "$confirm" == "y" ]]; then
              "$TMUX_BIN" kill-pane -t "$target" 2>/dev/null
              # Return focus to the sidebar pane
              [[ -n "$MY_PANE_ID" ]] && "$TMUX_BIN" select-pane -t "$MY_PANE_ID" 2>/dev/null
            fi
          else
            # Window target
            printf '\033[H\033[J'
            printf '%s' "${BOLD}${YELLOW}Kill window ${target}? (y/n)${RESET} "
            IFS= read -rsn1 confirm
            if [[ "$confirm" == "y" ]]; then
              "$TMUX_BIN" kill-window -t "$target" 2>/dev/null
              EXPANDED_LIST="${EXPANDED_LIST//|${target}|/}"
              # Return focus to the sidebar pane
              [[ -n "$MY_PANE_ID" ]] && "$TMUX_BIN" select-pane -t "$MY_PANE_ID" 2>/dev/null
            fi
          fi
        fi
        ;;
      '/') # Command mode
        read_command
        if [[ -n "$CMD_INPUT" ]]; then
          exec_command "$CMD_INPUT"
        fi
        ;;
      ':') # Fuzzy finder
        FZF_BIN=$(command -v fzf 2>/dev/null)
        if [[ -z "$FZF_BIN" ]]; then
          "$TMUX_BIN" display-message "fzf required: brew install fzf" 2>/dev/null
        else
          rm -f "$CACHE_DIR/fuzzy.result"
          "$TMUX_BIN" display-popup -E -w 80% -h 60% -T " Jump to window " \
            "bash '${PLUGIN_DIR}/scripts/fuzzy-find.sh'"
          if [[ -f "$CACHE_DIR/fuzzy.result" ]]; then
            result=$(cat "$CACHE_DIR/fuzzy.result")
            action="${result%%:*}"
            fz_target="${result#*:}"
            if [[ "$action" == "JUMP" ]]; then
              "$TMUX_BIN" switch-client -t "$fz_target" 2>/dev/null
              "$TMUX_BIN" select-window -t "$fz_target" 2>/dev/null
            elif [[ "$action" == "SELECT" ]]; then
              # Find target index in TARGETS array and move cursor
              i=0
              for t in "${TARGETS[@]}"; do
                if [[ "$t" == "$fz_target" ]]; then
                  selected=$i
                  break
                fi
                i=$((i + 1))
              done
            fi
            rm -f "$CACHE_DIR/fuzzy.result"
          fi
        fi
        ;;
      '?') # Toggle help
        SHOW_HELP=$(( 1 - SHOW_HELP ))
        ;;
      'q')
        "$TMUX_BIN" run-shell "bash '${SCRIPT_DIR}/toggle-sidebar.sh'" 2>/dev/null
        exit 0
        ;;
    esac
    LAST_OUTPUT=""  # Force redraw on keypress
    build_and_render
  else
    # Timeout or SIGUSR1 signal
    if [[ "$NEEDS_REDRAW" -eq 1 ]]; then
      NEEDS_REDRAW=0
      # shellcheck disable=SC2034
      LAST_OUTPUT=""  # Force full redraw (used in sidebar-render.sh)
    fi
    build_and_render
  fi
done
