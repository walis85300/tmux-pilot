# tmux-pilot

> Your tmux copilot. Never lose track of what's running where.

**tmux-pilot** uses [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to read your terminal output and name your tmux windows with what's actually happening in them — not just "bash" or "zsh".

Titles are generated **once** (5 minutes after a window opens) and stay put. No background daemon eating tokens. You're in control.

```
┌──────────────────────────┬───────────────────────────────────────────┐
│ ▸ work                   │                                           │
│   ▸ 1 pytest auth tests  │  $ pytest tests/auth/ -v                  │
│       3 failing, fixing…  │  FAILED test_jwt.py::test_refresh         │
│       ~/projects/api      │  ...                                      │
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
│ ↑↓/jk nav  ⏎ jump        │                                           │
│ q hide                    │                                           │
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
| `prefix + Alt-n` | Regenerate title for current window now |
| `prefix + Alt-r` | Manually rename + **pin** (never auto-overwritten) |
| Pinned window + scheduled generation | Skipped — your name wins |
| `prefix + Alt-n` on pinned window | Unpins and regenerates |

No daemon. No polling loop. One API call per window, ever.

## Requirements

- **tmux** >= 3.0
- **bash** >= 4.0
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** installed and authenticated

```sh
# Install Claude Code
npm install -g @anthropic-ai/claude-code

# Authenticate (one time)
claude
```

## Install

### With [TPM](https://github.com/tmux-plugins/tpm)

Add to `~/.tmux.conf` **after** the TPM `run` line:

```tmux
run '~/.tmux/plugins/tpm/tpm'

set -g @plugin 'walis85300/tmux-pilot'
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

| Key | Action |
|---|---|
| `prefix + Tab` | Toggle sidebar |
| `prefix + Alt-n` | Regenerate AI title for current window |
| `prefix + Alt-r` | Manually rename and pin current window |

### Sidebar navigation

| Key | Action |
|---|---|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `Enter` | Jump to window |
| `q` | Hide sidebar |

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
tmux-ai-nav.tmux            # Entry point: keybindings + hooks
scripts/
  schedule.sh                # Sleeps N seconds, then calls generate-title.sh
  generate-title.sh          # Captures pane → calls Claude → renames window
  refresh.sh                 # Manual trigger: regenerate title for current window
  rename.sh                  # Manual rename + pin (blocks auto-overwrite)
  toggle-sidebar.sh          # Show/hide the sidebar panel
  sidebar.sh                 # Interactive sidebar UI
lib/
  api.sh                     # claude -p --model haiku wrapper
```

**Cache** lives in `/tmp/tmux-ai-nav/`:
- `{session}_{window}.title` — AI-generated title
- `{session}_{window}.summary` — One-line summary
- `{session}_{window}.pinned` — Marker: this title was set manually

## Troubleshooting

```sh
# Check the log
cat /tmp/tmux-ai-nav/daemon.log

# Manually generate a title right now
bash ~/.tmux/plugins/tmux-pilot/scripts/refresh.sh

# Verify claude works
claude -p --model haiku "say hello"

# Reset everything
rm -rf /tmp/tmux-ai-nav && tmux source-file ~/.tmux.conf
```

**Keybinding lost after reload?** Make sure `run-shell` is **after** `run '~/.tmux/plugins/tpm/tpm'`.

## License

MIT
