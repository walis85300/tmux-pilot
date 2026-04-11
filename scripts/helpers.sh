#!/usr/bin/env bash
# helpers.sh — Shared utility functions for tmux-pilot

# Read a TMUX_PILOT_* env var with backward compat to legacy TMUX_AI_NAV_* naming
get_pilot_env() {
  local key="$1"
  local default="$2"
  case "$key" in
    CLAUDE_BIN) echo "${TMUX_PILOT_CLAUDE_BIN:-${TMUX_AI_NAV_CLAUDE_BIN:-$default}}" ;;
    TMUX_BIN)   echo "${TMUX_PILOT_TMUX_BIN:-${TMUX_AI_NAV_TMUX_BIN:-$default}}" ;;
    *)          echo "$default" ;;
  esac
}

TMUX_BIN=$(get_pilot_env "TMUX_BIN" "$(command -v tmux || echo tmux)")

# Read a tmux user option with a default fallback
get_tmux_option() {
  local option_name="$1"
  local default_value="$2"
  local option_value
  option_value=$("$TMUX_BIN" show-option -gqv "$option_name" 2>/dev/null)
  if [ -z "$option_value" ]; then
    echo "$default_value"
  else
    echo "$option_value"
  fi
}

# Check if tmux version is >= required version
tmux_version_ge() {
  local required="$1"
  local current
  current=$("$TMUX_BIN" -V | sed 's/tmux //' | sed 's/[a-z]//g')
  [ "$(printf '%s\n' "$required" "$current" | sort -V | head -n1)" = "$required" ]
}

# XDG-aware state directory
get_state_dir() {
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/tmux-pilot"
  mkdir -p "$dir"
  echo "$dir"
}
