#!/usr/bin/env bash
# schedule.sh — Schedules title generation for a window after a delay.
# Called by the after-new-window hook. Sleeps, then generates.
# Usage: schedule.sh <session_name> <window_index>

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DELAY="${TMUX_AI_NAV_DELAY:-300}"  # 5 minutes default

SESSION="$1"
WINDOW_IDX="$2"

sleep "$DELAY"

exec bash "$PLUGIN_DIR/scripts/generate-title.sh" "$SESSION" "$WINDOW_IDX"
