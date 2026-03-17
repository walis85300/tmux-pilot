#!/usr/bin/env bash
# api.sh — Uses Claude Code headless to generate a window title + summary
# Usage: api.sh "<pane_content>"
# Outputs two lines: title, then summary

set -uo pipefail

CONTENT="$1"
CLAUDE_BIN="${TMUX_AI_NAV_CLAUDE_BIN:-claude}"

"$CLAUDE_BIN" -p \
  --model haiku \
  --max-turns 1 \
  --mcp-config '{"mcpServers":{}}' \
  --strict-mcp-config \
  "You summarize terminal panes. Given terminal output, respond with EXACTLY two lines:
Line 1: A 2-4 word title (used as tmux window name). Be specific and concise.
Line 2: A one-sentence summary (max 50 chars) adding context.

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
