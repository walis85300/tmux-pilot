# tmux-pilot

> Your tmux copilot. Never lose track of what's running where.

**tmux-pilot** uses [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to read your terminal output and name your tmux windows with what's actually happening in them — not just "bash" or "zsh".

A background daemon checks for untitled windows every 30 seconds and generates titles automatically. Each window is titled once and never again unless you ask. A built-in watchdog restarts the daemon if it ever dies.

```
┌──────────────────────────┬───────────────────────────────────────────┐
│ ▸ work                   │                                           │
│   ▸ ● 1 pytest auth [2] │  $ pytest tests/auth/ -v                  │
│       3 failing, fixing…  │  FAILED test_jwt.py::test_refresh         │
│       ~/projects/api      │  ...                                      │
│       ├─ ● 0 pytest       │                                           │
│       └─   1 vim          │                                           │
│                           │                                           │
│     2 docker compose up   │                                           │
│       All services green  │                                           │
│       ~/projects/app      │                                           │
│                           │                                           │
│   personal                │                                           │
│   ● 1 vim README.md      │                                           │
│       Drafting v2 docs    │                                           │
│       ~/oss/my-proj       │                                           │
│                           │                                           │
│                           │                                           │
│                    ? help │                                           │
└──────────────────────────┴───────────────────────────────────────────┘
 1  pytest auth tests    2  docker compose up            ← status bar
```

## Before & After

| Without tmux-pilot | With tmux-pilot |
|---|---|
| `1 bash  2 bash  3 bash` | `1 pytest auth  2 docker compose  3 vim README` |
| `prefix+w` shows "bash" everywhere | `prefix+w` shows meaningful names |
| You forgot what's in window 4 | The sidebar tells you instantly |

## How titles work

| Event | What happens |
|---|---|
| New window created | Daemon detects it within 30s and generates a title |
| `prefix + T` | Regenerate title for current window now |
| `prefix + R` | Manually rename + **pin** (never auto-overwritten) |
| Pinned window | Daemon skips it — your name wins |
| `prefix + T` on pinned window | Unpins and regenerates |
| Multi-pane window | All panes captured for a holistic title |
| Session closes | Daemon keeps running for other sessions |
| Daemon dies | Watchdog restarts it on next window switch |

Title generation uses Claude Sonnet with rich context: session name, CWD, git branch, and up to 60 lines of terminal output. Titles are sanitized (markdown stripped, truncated to 30 chars) before applying.

## Requirements

| Dependency | Required | Install |
|---|---|---|
| **tmux** >= 3.2 | Yes | `brew install tmux` |
| **bash** >= 3.2 | Yes | Ships with macOS |
| **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** | Yes | `npm install -g @anthropic-ai/claude-code` |
| **[fzf](https://github.com/junegunn/fzf)** | Optional (fuzzy finder) | `brew install fzf` |

```sh
# Install Claude Code
npm install -g @anthropic-ai/claude-code

# Authenticate (one time)
claude

# Install fzf (optional, for fuzzy finder)
brew install fzf
```

## Install

### With [TPM](https://github.com/tmux-plugins/tpm)

Add to `~/.tmux.conf` **after** the TPM `run` line:

```tmux
set -g @plugin 'walis85300/tmux-pilot'
run '~/.tmux/plugins/tpm/tpm'

run-shell '~/.tmux/plugins/tmux-pilot/pilot.tmux'
```

Press `prefix + I` to install, then reload:

```sh
tmux source-file ~/.tmux.conf
```

### Manual

```sh
git clone https://github.com/walis85300/tmux-pilot ~/.tmux/plugins/tmux-pilot
```

Add to `~/.tmux.conf` (after TPM if you use it):

```tmux
run-shell '~/.tmux/plugins/tmux-pilot/pilot.tmux'
```

## Keybindings

### Global (work anywhere)

| Key | Action |
|---|---|
| `prefix + Tab` | Toggle sidebar |
| `prefix + T` | Regenerate AI title for current window |
| `prefix + R` | Manually rename and pin current window |
| `prefix + F` | Fuzzy find windows (requires fzf) |

### Sidebar navigation

| Key | Action |
|---|---|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `Enter` | Jump to window / expand panes |
| `x` | Kill window or pane (with confirmation) |
| `:` | Fuzzy find windows |
| `/` | Command mode |
| `Esc` | Collapse expanded panes |
| `?` | Toggle help |
| `q` | Hide sidebar |

### Sidebar commands (press `/` then type)

| Command | Action |
|---|---|
| `/new <name>` | Create a new session |
| `/win` | New window in selected session |
| `/split` | Horizontal split |
| `/vs` | Vertical split |
| `/rename <title>` | Rename and pin window title |
| `/title` | Regenerate AI title |

## Configuration

### Keybindings

All keybindings are configurable via tmux user options. Add to `~/.tmux.conf` **before** the `run-shell` line:

```tmux
set -g @pilot-key-sidebar "Tab"   # Toggle sidebar (default: Tab)
set -g @pilot-key-title   "T"     # Regenerate AI title (default: T)
set -g @pilot-key-rename  "R"     # Manual rename & pin (default: R)
set -g @pilot-key-fuzzy   "F"     # Fuzzy find windows (default: F)
```

### Environment variables

```sh
# Custom claude binary (new naming)
export TMUX_PILOT_CLAUDE_BIN=claude

# Custom tmux binary
export TMUX_PILOT_TMUX_BIN=tmux

# Legacy naming (still supported)
export TMUX_AI_NAV_CLAUDE_BIN=claude
```

## Architecture

```
pilot.tmux                   # Entry point: keybindings + hooks + daemon + watchdog
scripts/
  daemon.sh                  # Background polling loop (30s), auto-titles new windows
  generate-title.sh          # Captures panes + context → Claude → sanitize → rename
  refresh.sh                 # Manual trigger: regenerate title for current window
  rename.sh                  # Manual rename + pin (blocks auto-overwrite)
  toggle-sidebar.sh          # Show/hide/move the sidebar panel
  sidebar.sh                 # Interactive sidebar: main loop + key dispatch
  sidebar-render.sh          # Sidebar tree rendering (sourced by sidebar.sh)
  sidebar-commands.sh         # Sidebar command mode (sourced by sidebar.sh)
  fuzzy-find.sh              # fzf-powered window search
  safe-split.sh              # Split proxy that protects sidebar
  relocate-sidebar.sh        # Move sidebar across windows/sessions
  fix-sidebar-split.sh       # Post-split hook to repair sidebar
  helpers.sh                 # Shared utilities (sourced, not executed)
lib/
  api.sh                     # claude -p --model sonnet wrapper (30s timeout)
  cache.sh                   # Cache key computation + read/write/migrate
```

**Cache** lives in `~/.local/state/tmux-pilot/` (XDG-compliant):
- `{session}::{window_id}.title` — AI-generated title
- `{session}::{window_id}.summary` — One-line summary
- `{session}::{window_id}.pinned` — Marker: this title was set manually
- `daemon.pid` — Daemon process for lifecycle management
- `sidebar.pid` / `sidebar.pane_id` — Sidebar process for signal-based redraws

## Troubleshooting

```sh
# Check the log
cat ~/.local/state/tmux-pilot/daemon.log

# Manually generate a title right now
bash ~/.tmux/plugins/tmux-pilot/scripts/refresh.sh

# Verify claude works
claude -p --model sonnet "say hello"

# Verify fzf works
echo "test" | fzf

# Reset everything
rm -rf ~/.local/state/tmux-pilot && tmux source-file ~/.tmux.conf
```

**Daemon not running?** The watchdog restarts it on window switch. Or force restart: `tmux source-file ~/.tmux.conf`

**Keybinding lost after reload?** Make sure `run-shell` is **after** `run '~/.tmux/plugins/tpm/tpm'`.

**Sidebar needs two presses?** The sidebar may have been left in another session. The plugin auto-moves it to your current window.

## License

MIT
