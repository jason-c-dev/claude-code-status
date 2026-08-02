# claude-code-status

A colorful, informative [status line](https://code.claude.com/docs/en/statusline) for
[Claude Code](https://claude.com/claude-code). Pure bash + `jq` + `git` — no other
dependencies, no network calls.

```
📁 ~/dev/my-project | Fable 5 (1M) | 🌿 main ✚3 ↑1 | ██████░░░░ 62% · 620.2K tok | 💰 $1.23
```

## What it shows

| Segment | Example | Details |
|---------|---------|---------|
| Path | `📁 ~/dev/my-project` | Bright cyan, folder icon, `$HOME` abbreviated to `~` |
| Model | `Fable 5 (1M)` | Bright magenta, with context window size appended (skipped if the model name already includes it, e.g. `Opus 5 (1M context)`) |
| Git | `🌿 main ✚3 ↑1` | Green branch (short SHA when detached), yellow `✚n` uncommitted-file count, blue `↑n`/`↓n` ahead/behind upstream. Only shown inside a git repo. Never runs `git fetch`. |
| Context bar | `██████░░░░ 62% · 620.2K tok` | 10-block usage bar — green &lt;30%, yellow 30–59%, red ≥60% — plus exact percentage and the live token count currently in context |
| Cost | `💰 $1.23` | Yellow. Claude Code's own client-side estimate of the session cost (`cost.total_cost_usd`), not a figure this script derives from tokens. Drops to 3 decimals under a cent. Resets when `/clear` starts a new session. |

Every segment is optional: if a field is missing from the session JSON (early in a
session, or outside a git repo), the segment **and its separator** drop cleanly
rather than leaving an empty slot.

## Setup

### Ask Claude to do it

Paste this into Claude Code:

> Clone https://github.com/jason-c-dev/claude-code-status to `~/dev/claude-code-status`
> and set my status line: in `~/.claude/settings.json`, set `statusLine` to
> `{"type": "command", "command": "bash ~/dev/claude-code-status/statusline-command.sh"}`.
> Then verify by piping a sample session JSON into the script.

### Manual

1. Clone the repo:

   ```bash
   git clone https://github.com/jason-c-dev/claude-code-status.git ~/dev/claude-code-status
   ```

2. Make sure `jq` is installed (`brew install jq` on macOS).

3. Point Claude Code at the script in `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/dev/claude-code-status/statusline-command.sh"
     }
   }
   ```

4. The status line picks up the change automatically — no restart needed.

### Test it without Claude Code

The script reads the session JSON Claude Code pipes on stdin, so you can preview any
state by hand:

```bash
echo '{
  "workspace": {"current_dir": "'$PWD'"},
  "model": {"display_name": "Fable 5"},
  "cost": {"total_cost_usd": 1.2345},
  "context_window": {
    "used_percentage": 62,
    "context_window_size": 1000000,
    "total_input_tokens": 615000,
    "total_output_tokens": 5200
  }
}' | bash ~/dev/claude-code-status/statusline-command.sh
```

## Customizing

Everything lives in one file, `statusline-command.sh`:

- **Colors** — the `CYAN`/`MAGENTA`/`GREEN`/… variables near the top (standard ANSI
  bright codes; swap in 256-color `\033[38;5;Nm` codes if you want finer control).
- **Bar thresholds** — the `-ge 60` / `-ge 30` checks in the context-bar block.
- **Bar width** — the two `10`s in the bar builder loop and the `filled` clamp.

## JSON fields used

From the [documented statusline input](https://code.claude.com/docs/en/statusline):
`workspace.current_dir`, `model.display_name`, `context_window.used_percentage`,
`context_window.context_window_size`, `context_window.total_input_tokens`,
`context_window.total_output_tokens`, `cost.total_cost_usd`. Git info comes from
running `git` locally against the current directory.
