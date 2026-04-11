# sidebar-commands.sh — Command-mode input and execution for the sidebar.
# Sourced by sidebar.sh. Relies on globals: TARGETS, selected, MY_PANE_ID,
# PLUGIN_DIR, TMUX_BIN, MAGENTA, YELLOW, GREEN, DIM, BOLD, RESET.

# shellcheck disable=SC2154  # Globals provided by sidebar.sh

# Get hint for the current command being typed
cmd_hint() {
  local input="$1"
  local cmd="${input%% *}"
  case "$cmd" in
    new)    printf '%s' "${MAGENTA}new${RESET} ${YELLOW}<name>${RESET}  ${DIM}create session${RESET}" ;;
    rename) printf '%s' "${MAGENTA}rename${RESET} ${YELLOW}<title>${RESET}  ${DIM}rename & pin${RESET}" ;;
    win)    printf '%s' "${MAGENTA}win${RESET}  ${DIM}new window${RESET}" ;;
    split)  printf '%s' "${MAGENTA}split${RESET}  ${DIM}horizontal split${RESET}" ;;
    vs)     printf '%s' "${MAGENTA}vs${RESET}  ${DIM}vertical split${RESET}" ;;
    title)  printf '%s' "${MAGENTA}title${RESET}  ${DIM}regen AI title${RESET}" ;;
    *)      printf '%s' "${MAGENTA}new${RESET} ${DIM}·${RESET} ${MAGENTA}win${RESET} ${DIM}·${RESET} ${MAGENTA}split${RESET} ${DIM}·${RESET} ${MAGENTA}vs${RESET} ${DIM}·${RESET} ${MAGENTA}rename${RESET} ${DIM}·${RESET} ${MAGENTA}title${RESET}" ;;
  esac
}

# Read a line of input with a prompt. Shows cursor, returns input in CMD_INPUT.
read_command() {
  tput cnorm 2>/dev/null || true
  CMD_INPUT=""
  local prev_hint=""
  # Initial render
  printf '\033[H\033[J'
  printf '%s' "${GREEN}/${RESET} "
  printf '\n%s' "${DIM}$(cmd_hint "")${RESET}"
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
      printf '%s' "${DIM}${hint}${RESET}"
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
  local target

  case "$cmd" in
    new)
      if [[ -n "$args" ]]; then
        "$TMUX_BIN" new-session -d -s "$args" 2>/dev/null && \
          "$TMUX_BIN" switch-client -t "$args" 2>/dev/null
      else
        printf '\033[H\033[J'
        printf '%s' "${YELLOW}Usage: new <session-name>${RESET}"
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
        printf '%s' "${YELLOW}Usage: rename <title>${RESET}"
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
        printf '%s' "${DIM}Generating title for ${win_target}...${RESET}"
        read -rsn1 -t 1
      fi
      ;;
    *)
      printf '\033[H\033[J'
      printf '%s\n' "${YELLOW}Unknown: ${cmd}${RESET}"
      printf '%s' "${DIM}Commands: new, win, split, vs, rename, title${RESET}"
      read -rsn1 -t 2
      ;;
  esac
}
