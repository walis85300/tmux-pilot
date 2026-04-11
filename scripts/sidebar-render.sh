#!/usr/bin/env bash
# sidebar-render.sh — Data fetching, tree construction, and ANSI rendering.
# Sourced by sidebar.sh. Relies on globals: TARGETS, selected, EXPANDED_LIST,
# CACHE_DIR, MY_PANE_ID, MAX_TEXT, PANE_WIDTH, SHOW_HELP, LAST_OUTPUT,
# TMUX_BIN, and all color vars (BOLD, DIM, REV, GREEN, CYAN, YELLOW, BLUE,
# MAGENTA, WHITE, BG_GREEN, BLACK, RESET).
# Also requires lib/cache.sh functions: cache_key, cache_read.

# shellcheck disable=SC2154  # Globals provided by sidebar.sh

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
  refresh_dimensions
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
      -F '#{window_index}|#{window_name}|#{window_active}|#{pane_current_path}|#{window_panes}|#{window_id}' 2>/dev/null) || continue

    while IFS='|' read -r win_idx win_name is_active pane_path pane_count win_id; do
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

      local ck
      ck=$(cache_key "$sess" "$win_id")
      local summary
      summary=$(cache_read "$CACHE_DIR" "$ck" "summary")

      # Truncation widths account for indent depth per line type:
      #   window name line: 4-6 chars prefix ("  ▸ " or "    ") + index + space
      #   summary/path line: 6 chars indent ("      ")
      local line_max=$((PANE_WIDTH - 6))
      [[ $line_max -lt 10 ]] && line_max=10
      local sp
      sp=$(short_path "$pane_path" "$line_max")

      [[ ${#win_name} -gt $line_max ]] && win_name="${win_name:0:$((line_max - 1))}…"
      [[ ${#summary} -gt $line_max ]] && summary="${summary:0:$((line_max - 1))}…"

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
          psp=$(short_path "$p_path" "$((PANE_WIDTH - 16))")

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
    local sep
    sep="${DIM}$(printf '%.0s─' $(seq 1 "$PANE_WIDTH"))"
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
