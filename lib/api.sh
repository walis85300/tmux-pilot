#!/usr/bin/env bash
# api.sh — Uses Claude Code headless to generate a window title + summary
# Usage: api.sh "<context_json>" "<pane_content>"
# Outputs two lines: title, then summary

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/helpers.sh"

CONTEXT="$1"
CONTENT="$2"
CLAUDE_BIN=$(get_pilot_env "CLAUDE_BIN" "claude")
API_TIMEOUT=30

# Portable timeout: try timeout/gtimeout, fall back to background+kill
run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$API_TIMEOUT" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$API_TIMEOUT" "$@"
  else
    # POSIX fallback: run in background, kill after timeout
    "$@" &
    local pid=$!
    (sleep "$API_TIMEOUT" && kill "$pid" 2>/dev/null) &
    local watchdog=$!
    wait "$pid" 2>/dev/null
    local rc=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    return $rc
  fi
}

run_with_timeout "$CLAUDE_BIN" -p \
  --model sonnet \
  --max-turns 1 \
  --mcp-config '{"mcpServers":{}}' \
  --strict-mcp-config \
  "You summarize terminal panes. Given terminal output and context, respond with EXACTLY two lines:
Line 1: A 2-4 word title (used as tmux window name). Be specific and concise.
Line 2: A one-sentence summary (max 50 chars) adding context.

Context:
${CONTEXT}

If multiple panes are shown, generate a holistic title and summary covering the main activity across all panes.

Good examples:
pytest auth tests
3 failing, fixing JWT validation

vim api/routes.py
Adding pagination to /users endpoint

zsh ~/projects/app
Idle shell, last ran docker compose

Auth feature dev
Editing controller, API on :3000, tests passing

ONLY output the two lines. No formatting, no quotes, no explanation.

Terminal output:
${CONTENT}" 2>/dev/null
