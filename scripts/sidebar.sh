#!/usr/bin/env bash
# sidebar.sh — Persistent left panel showing all windows/panes with AI titles.
# Renders in choose-tree style. Navigable with j/k/arrows, Enter to jump/expand.
# Multi-pane windows can be expanded to show individual panes.
# Reads its own pane ID from the marker file.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

CACHE_DIR=$(get_state_dir)
MY_PANE_ID=$(cat "$CACHE_DIR/sidebar.pane_id" 2>/dev/null)

# Dynamic truncation based on actual pane width (6 chars indent)
PANE_WIDTH=$("$TMUX_BIN" display-message -p '#{pane_width}' 2>/dev/null || tput cols 2>/dev/null || echo 28)
MAX_TEXT=$(( PANE_WIDTH - 8 ))
[[ $MAX_TEXT -lt 10 ]] && MAX_TEXT=10

selected=-1  # -1 = not yet initialized, will be set to current window
EXPANDED_LIST=""  # delimited string for Bash 3.2 compat (no associative arrays)
SHOW_HELP=0

# Colors
BOLD=$(tput bold 2>/dev/null || true)
DIM=$(tput dim 2>/dev/null || true)
REV=$(tput rev 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
BLUE=$(tput setaf 4 2>/dev/null || true)
MAGENTA=$(tput setaf 5 2>/dev/null || true)
WHITE=$(tput setaf 7 2>/dev/null || true)
BG_GREEN=$(tput setab 2 2>/dev/null || true)
BLACK=$(tput setaf 0 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

# Hide cursor to avoid flicker
tput civis 2>/dev/null || true
trap 'tput cnorm 2>/dev/null || true' EXIT

# SIGUSR1 interrupts the read timeout for immediate redraw
NEEDS_REDRAW=0
trap 'NEEDS_REDRAW=1' USR1

# Save our PID so hooks can signal us
echo $$ > "$CACHE_DIR/sidebar.pid"

declare -a TARGETS=()
LAST_OUTPUT=""
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Get hint for the current command being typed
cmd_hint() {
  local input="$1"
  local cmd="${input%% *}"
  case "$cmd" in
    new)    printf "${MAGENTA}new${RESET} ${YELLOW}<name>${RESET}  ${DIM}create session${RESET}" ;;
    rename) printf "${MAGENTA}rename${RESET} ${YELLOW}<title>${RESET}  ${DIM}rename & pin${RESET}" ;;
    win)    printf "${MAGENTA}win${RESET}  ${DIM}new window${RESET}" ;;
    split)  printf "${MAGENTA}split${RESET}  ${DIM}horizontal split${RESET}" ;;
    vs)     printf "${MAGENTA}vs${RESET}  ${DIM}vertical split${RESET}" ;;
    title)  printf "${MAGENTA}title${RESET}  ${DIM}regen AI title${RESET}" ;;
    *)      printf "${MAGENTA}new${RESET} ${DIM}·${RESET} ${MAGENTA}win${RESET} ${DIM}·${RESET} ${MAGENTA}split${RESET} ${DIM}·${RESET} ${MAGENTA}vs${RESET} ${DIM}·${RESET} ${MAGENTA}rename${RESET} ${DIM}·${RESET} ${MAGENTA}title${RESET}" ;;
  esac
}

# Read a line of input with a prompt. Shows cursor, returns input in CMD_INPUT.
read_command() {
  tput cnorm 2>/dev/null || true
  CMD_INPUT=""
  local prev_hint=""
  # Initial render
  printf '\033[H\033[J'
  printf "${GREEN}/${RESET} "
  printf '\n'"${DIM}$(cmd_hint "")${RESET}"
  printf '\033[1;4H'  # Move cursor back to input line after "/ "
  while true; do
    IFS= read -rsn1 ch
    case "$ch" in
      $'\x1b') # Escape — cancel
        CMD_INPUT=""
        break
        ;;
      '') # Enter — submit
        break
        ;;
      $'\x7f'|$'\b') # Backspace
        if [[ -n "$CMD_INPUT" ]]; then
          CMD_INPUT="${CMD_INPUT%?}"
          printf '\b \b'
        fi
        ;;
      *)
        CMD_INPUT+="$ch"
        printf '%s' "$ch"
        ;;
    esac
    # Update hint if it changed
    local hint
    hint=$(cmd_hint "$CMD_INPUT")
    if [[ "$hint" != "$prev_hint" ]]; then
      prev_hint="$hint"
      # Save cursor, go to line 2, clear it, print hint, restore cursor
      printf '\0337'
      printf '\033[2;1H\033[K'
      printf "${DIM}${hint}${RESET}"
      printf '\0338'
    fi
  done
  tput civis 2>/dev/null || true
}

# Execute a slash command
exec_command() {
  local input="$1"
  local cmd="${input%% *}"
  local args="${input#* }"
  [[ "$cmd" == "$args" ]] && args=""

  case "$cmd" in
    new)
      if [[ -n "$args" ]]; then
        "$TMUX_BIN" new-session -d -s "$args" 2>/dev/null && \
          "$TMUX_BIN" switch-client -t "$args" 2>/dev/null
      else
        printf '\033[H\033[J'
        printf "${YELLOW}Usage: new <session-name>${RESET}"
        read -rsn1 -t 2
      fi
      ;;
    win)
      local sess
      if [[ $selected -lt ${#TARGETS[@]} ]]; then
        target="${TARGETS[$selected]}"
        sess="${target%%:*}"
      else
        sess=$("$TMUX_BIN" display-message -p '#{session_name}' 2>/dev/null)
      fi
      "$TMUX_BIN" new-window -t "$sess" 2>/dev/null
      ;;
    split|vs)
      if [[ $selected -lt ${#TARGETS[@]} ]]; then
        target="${TARGETS[$selected]}"
        # Find the active non-sidebar pane in the target window
        local split_target=""
        if [[ "$target" == *.* ]]; then
          # Pane target: split that specific pane
          split_target="$target"
        else
          # Window target: find the active pane that isn't the sidebar
          split_target=$("$TMUX_BIN" list-panes -t "$target" \
            -F '#{pane_id}|#{pane_active}' 2>/dev/null | \
            grep -v "^${MY_PANE_ID}|" | grep '|1$' | head -1 | cut -d'|' -f1)
          # Fallback to any non-sidebar pane
          [[ -z "$split_target" ]] && split_target=$("$TMUX_BIN" list-panes -t "$target" \
            -F '#{pane_id}' 2>/dev/null | grep -v "^${MY_PANE_ID}$" | head -1)
        fi
        if [[ -n "$split_target" ]]; then
          local split_flag="-v"
          [[ "$cmd" == "vs" ]] && split_flag="-h"
          "$TMUX_BIN" split-window "$split_flag" -t "$split_target" 2>/dev/null
          [[ -n "$MY_PANE_ID" ]] && "$TMUX_BIN" select-pane -t "$MY_PANE_ID" 2>/dev/null
        fi
      fi
      ;;
    rename)
      if [[ -n "$args" ]] && [[ $selected -lt ${#TARGETS[@]} ]]; then
        target="${TARGETS[$selected]}"
        if [[ "$target" != *.* ]]; then
          bash "$PLUGIN_DIR/scripts/rename.sh" "$args"
        fi
      else
        printf '\033[H\033[J'
        printf "${YELLOW}Usage: rename <title>${RESET}"
        read -rsn1 -t 2
      fi
      ;;
    title)
      if [[ $selected -lt ${#TARGETS[@]} ]]; then
        target="${TARGETS[$selected]}"
        # Get the window target (strip pane if present)
        local win_target="${target%%.*}"
        local t_sess="${win_target%%:*}"
        local t_win="${win_target##*:}"
        nohup bash "$PLUGIN_DIR/scripts/generate-title.sh" "$t_sess" "$t_win" </dev/null >/dev/null 2>&1 &
        printf '\033[H\033[J'
        printf "${DIM}Generating title for ${win_target}...${RESET}"
        read -rsn1 -t 1
      fi
      ;;
    *)
      printf '\033[H\033[J'
      printf "${YELLOW}Unknown: ${cmd}${RESET}"$'\n'
      printf "${DIM}Commands: new, win, split, vs, rename, title${RESET}"
      read -rsn1 -t 2
      ;;
  esac
}

short_path() {
  local p="${1/#$HOME/~}"
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
  # When status bar is on top, first pane line can be clipped
  local status_pos
  status_pos=$("$TMUX_BIN" show-option -gv status-position 2>/dev/null || echo "bottom")
  [[ "$status_pos" == "top" ]] && output+=$'\n'

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

      local is_expanded=""
      [[ "$EXPANDED_LIST" == *"|${target}|"* ]] && is_expanded="1"

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

  # Build bottom bar (anchored to bottom using full window height)
  local pane_height
  pane_height=$("$TMUX_BIN" display-message -p '#{pane_height}' 2>/dev/null || tput lines 2>/dev/null || echo 24)
  local bottom_bar=""

  if [[ "$SHOW_HELP" -eq 1 ]]; then
    local sep="${DIM}$(printf '%.0s─' $(seq 1 "$PANE_WIDTH"))"
    bottom_bar+="${sep}${RESET}"$'\n'
    bottom_bar+=" ${GREEN}j/k${RESET}  ${DIM}navigate${RESET}"$'\n'
    bottom_bar+=" ${GREEN}⏎${RESET}    ${DIM}jump / expand${RESET}"$'\n'
    bottom_bar+=" ${GREEN}x${RESET}    ${DIM}kill${RESET}"$'\n'
    bottom_bar+=" ${GREEN}esc${RESET}  ${DIM}collapse${RESET}"$'\n'
    bottom_bar+=" ${GREEN}:${RESET}    ${DIM}fuzzy find${RESET}"$'\n'
    bottom_bar+=" ${GREEN}q${RESET}    ${DIM}hide sidebar${RESET}"$'\n'
    bottom_bar+=" ${GREEN}?${RESET}    ${DIM}close help${RESET}"$'\n'
    bottom_bar+="${sep}${RESET}"$'\n'
    bottom_bar+=" ${MAGENTA}/new${RESET} ${YELLOW}<name>${RESET}   ${DIM}session${RESET}"$'\n'
    bottom_bar+=" ${MAGENTA}/win${RESET}          ${DIM}window${RESET}"$'\n'
    bottom_bar+=" ${MAGENTA}/split${RESET}        ${DIM}h-split${RESET}"$'\n'
    bottom_bar+=" ${MAGENTA}/vs${RESET}           ${DIM}v-split${RESET}"$'\n'
    bottom_bar+=" ${MAGENTA}/rename${RESET} ${YELLOW}<t>${RESET}   ${DIM}pin title${RESET}"$'\n'
    bottom_bar+=" ${MAGENTA}/title${RESET}        ${DIM}AI regen${RESET}"
    local help_lines=16
    local help_row=$((pane_height - help_lines))
    [[ $help_row -lt 2 ]] && help_row=2
    output+="$(printf '\033[%d;1H' "$help_row")${bottom_bar}"
  else
    output+="$(printf '\033[%d;1H' "$pane_height")${DIM}: fuzzy  ? help${RESET}"
  fi

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
            printf "${BOLD}${YELLOW}Kill pane ${target}? (y/n)${RESET} "
            IFS= read -rsn1 confirm
            if [[ "$confirm" == "y" ]]; then
              "$TMUX_BIN" kill-pane -t "$target" 2>/dev/null
              # Return focus to the sidebar pane
              [[ -n "$MY_PANE_ID" ]] && "$TMUX_BIN" select-pane -t "$MY_PANE_ID" 2>/dev/null
            fi
          else
            # Window target
            printf '\033[H\033[J'
            printf "${BOLD}${YELLOW}Kill window ${target}? (y/n)${RESET} "
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
        "$TMUX_BIN" run-shell "bash '$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/toggle-sidebar.sh'" 2>/dev/null
        exit 0
        ;;
    esac
    LAST_OUTPUT=""  # Force redraw on keypress
    build_and_render
  else
    # Timeout or SIGUSR1 signal
    if [[ "$NEEDS_REDRAW" -eq 1 ]]; then
      NEEDS_REDRAW=0
      LAST_OUTPUT=""  # Force full redraw
    fi
    build_and_render
  fi
done
