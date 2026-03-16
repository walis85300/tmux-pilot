# tmux-pilot

> Your tmux copilot. Never lose track of what's running where.

**tmux-pilot** uses [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to read your terminal output and automatically name your tmux windows with what's actually happening in them — not just "bash" or "zsh".

It also adds a **persistent sidebar** you can toggle anytime, showing all your sessions and windows at a glance with AI-generated titles, one-line summaries, and working directories.

```
┌──────────────────────┬──────────────────────────────────────────────────┐
│ ▸ work               │                                                  │
│   ▸ 1 pytest auth    │  $ pytest tests/auth/ -v                         │
│       3 failing       │  FAILED tests/auth/test_jwt.py::test_refresh     │
│       ~/projects/api  │  FAILED tests/auth/test_jwt.py::test_expire      │
│                       │  ...                                             │
│     2 docker compose  │                                                  │
│       All services up │                                                  │
│       ~/projects/app  │                                                  │
│                       │                                                  │
│   personal            │                                                  │
│   ● 1 vim README.md  │                                                  │
│       Drafting v2 doc │                                                  │
│       ~/oss/my-proj   │                                                  │
│                       │                                                  │
│ ↑↓/jk nav ⏎ jump     │                                                  │
│ q hide                │                                                  │
└──────────────────────┴──────────────────────────────────────────────────┘
 1  pytest auth    2  docker compose                    ← AI-named status bar
```

## Before & After

| Without tmux-pilot | With tmux-pilot |
|---|---|
| `1 bash  2 bash  3 bash` | `1 pytest auth  2 docker compose  3 vim README` |
| `prefix+w` shows "bash" everywhere | `prefix+w` shows meaningful names |
| You forgot what's in window 4 | The sidebar tells you instantly |

## Requirements

- **tmux** >= 3.0
- **bash** >= 4.0
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** — installed and authenticated

```sh
# Install Claude Code (pick one)
npm install -g @anthropic-ai/claude-code
brew install claude-code

# Authenticate (one time)
claude
```

## Install

### With [TPM](https://github.com/tmux-plugins/tpm)

Add to `~/.tmux.conf`. **Must go after** the TPM `run` line:

```tmux
run '~/.tmux/plugins/tpm/tpm'

# tmux-pilot
set -g @plugin 'walis85300/tmux-pilot'
run-shell '~/.tmux/plugins/tmux-pilot/tmux-ai-nav.tmux'
```

Install with `prefix + I`, then reload:

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

Reload:

```sh
tmux source-file ~/.tmux.conf
```

That's it. The AI daemon starts automatically and begins renaming your windows.

## Usage

### Keybindings

| Key | Action |
|---|---|
| `prefix + Tab` | Toggle the sidebar |
| `prefix + Alt-n` | Turn AI daemon on/off |

### Sidebar navigation

| Key | Action |
|---|---|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `Enter` | Jump to window |
| `q` | Hide sidebar |

### How it works

1. A background daemon wakes up every 15 seconds
2. For each window, it captures the last 30 lines of the active pane
3. If the content changed since last check (via md5 hash), it calls `claude -p --model haiku`
4. Claude returns a short title + one-line summary
5. The daemon renames the window with `tmux rename-window`
6. Titles persist to disk and restore on tmux restart

The sidebar reads the same cached titles and renders them in a `choose-tree`-style panel on the left side of your terminal.

## Configuration

Optional environment variables (set in your shell profile):

```sh
# How often to refresh titles (default: 15 seconds)
export TMUX_AI_NAV_REFRESH=15

# Custom claude binary path
export TMUX_AI_NAV_CLAUDE_BIN=claude

# Custom tmux binary path
export TMUX_AI_NAV_TMUX_BIN=tmux
```

## Troubleshooting

**Titles not appearing?**

```sh
# Check if daemon is running
cat /tmp/tmux-ai-nav/daemon.pid && ps -p $(cat /tmp/tmux-ai-nav/daemon.pid)

# Check the log
cat /tmp/tmux-ai-nav/daemon.log

# Verify claude works
claude -p --model haiku "say hello"
```

**Sidebar keybinding lost after reload?**

Make sure the `run-shell` line is **after** `run '~/.tmux/plugins/tpm/tpm'` in your tmux.conf. TPM resets keybindings when it loads.

**Want to reset all titles?**

```sh
rm -rf /tmp/tmux-ai-nav
# Then prefix + Alt-n twice (off, then on) to restart the daemon
```

## Project structure

```
tmux-ai-nav.tmux           # Entry point: keybindings + auto-start daemon
scripts/
  daemon.sh                 # Background loop: capture → hash → claude → rename
  sidebar.sh                # Interactive sidebar UI (runs inside a tmux pane)
  toggle-sidebar.sh         # Open/close the sidebar
  toggle.sh                 # Start/stop the AI daemon
lib/
  api.sh                    # Claude Code headless wrapper
```

## License

MIT
