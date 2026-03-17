# tmux-pilot

> Your tmux copilot. Never lose track of what's running where.

**tmux-pilot** uses [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to read your terminal output and name your tmux windows with what's actually happening in them — not just "bash" or "zsh".

Titles are generated **once** (5 minutes after a window opens) and stay put. No background daemon eating tokens. You're in control.

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
| New window created | Title is generated **once**, 5 min later |
| `prefix + T` | Regenerate title for current window now |
| `prefix + R` | Manually rename + **pin** (never auto-overwritten) |
| Pinned window + scheduled generation | Skipped — your name wins |
| `prefix + T` on pinned window | Unpins and regenerates |
| Multi-pane window | All panes are captured for a holistic title |

No daemon. No polling loop. One API call per window, ever.

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

The plugin checks for dependencies at startup and shows a message if anything is missing.

## Install

### With [TPM](https://github.com/tmux-plugins/tpm)

Add to `~/.tmux.conf` **after** the TPM `run` line:

```tmux
set -g @plugin 'walis85300/tmux-pilot'
run '~/.tmux/plugins/tpm/tpm'

run-shell '~/.tmux/plugins/tmux-pilot/tmux-ai-nav.tmux'
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
run-shell '~/.tmux/plugins/tmux-pilot/tmux-ai-nav.tmux'
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

## Features

### AI-powered window titles
Windows are automatically named based on what's actually running in them. Multi-pane windows get a holistic summary covering all panes.

### Expandable pane tree
Windows with multiple panes show a `[N]` badge. Press Enter to expand and see individual panes with their commands and paths. Press Enter on a pane to jump directly to it.

### Fuzzy finder
Press `:` in the sidebar or `prefix + F` anywhere to search across all window titles and summaries with fzf. Enter jumps, Tab selects in the sidebar.

### Sidebar follows you
The sidebar automatically moves to your current window when you switch sessions — no need to close and reopen.

### Instant updates
tmux hooks trigger sidebar redraws immediately when you switch windows, split panes, or rename windows. No polling delay.

## Configuration

```sh
# Delay before auto-generating title (default: 300 = 5 min)
export TMUX_AI_NAV_DELAY=300

# Custom claude binary
export TMUX_AI_NAV_CLAUDE_BIN=claude

# Custom tmux binary
export TMUX_AI_NAV_TMUX_BIN=tmux
```

## Architecture

```
tmux-ai-nav.tmux            # Entry point: keybindings + hooks + dep checks
scripts/
  toggle-sidebar.sh          # Show/hide/move the sidebar panel
  sidebar.sh                 # Interactive sidebar UI with navigation
  fuzzy-find.sh              # fzf-powered window search
  schedule.sh                # Sleeps N seconds, then calls generate-title.sh
  generate-title.sh          # Captures pane(s) → calls Claude → renames window
  refresh.sh                 # Manual trigger: regenerate title for current window
  rename.sh                  # Manual rename + pin (blocks auto-overwrite)
  daemon.sh                  # Background process for auto-titling new windows
lib/
  api.sh                     # claude -p --model haiku wrapper
```

**Cache** lives in `/tmp/tmux-ai-nav/`:
- `{session}_{window}.title` — AI-generated title
- `{session}_{window}.summary` — One-line summary
- `{session}_{window}.pinned` — Marker: this title was set manually
- `sidebar.pane_id` — Sidebar pane ID for self-exclusion
- `sidebar.pid` — Sidebar process PID for signal-based redraws
- `fuzzy.result` — Temp file for fuzzy finder IPC

## Troubleshooting

```sh
# Check the log
cat /tmp/tmux-ai-nav/daemon.log

# Manually generate a title right now
bash ~/.tmux/plugins/tmux-pilot/scripts/refresh.sh

# Verify claude works
claude -p --model haiku "say hello"

# Verify fzf works
echo "test" | fzf

# Reset everything
rm -rf /tmp/tmux-ai-nav && tmux source-file ~/.tmux.conf
```

**Keybinding lost after reload?** Make sure `run-shell` is **after** `run '~/.tmux/plugins/tpm/tpm'`.

**Sidebar needs two presses?** The sidebar may have been left in another session. The plugin now auto-moves it to your current window.

## License

MIT
