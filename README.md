# claude-code-status

A colorful, informative [status line](https://code.claude.com/docs/en/statusline) for
[Claude Code](https://claude.com/claude-code). Pure bash + `jq` + `git` — no other
dependencies, and no network calls unless you opt into the
[weather segment](#weather).

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

Four further segments ship **disabled** — `duration`, `lines`, `limit` and `weather`.
They cost nothing while off (each is computed lazily), and any of the nine can be
turned on, off, or reordered from a config file. See [Configuring](#configuring).

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

## When it runs

The script is **event-driven, not on a timer**. Claude Code runs it once when a session
starts (including on resume), then re-runs it when:

- a new assistant message arrives — in practice this is the one that fires constantly
- `/compact` finishes
- the permission mode changes
- vim mode toggles
- a `refreshInterval` timer elapses, if you've configured one (see below)

So it runs roughly **once per assistant turn** — not per tool call, not per token, and
not on a clock. Two consequences worth knowing:

- **Updates are debounced at 300ms.** Rapid changes batch into a single run, and if a
  new trigger fires while the script is still executing, Claude Code *cancels* the
  in-flight run. A slow script doesn't queue up — it gets killed and re-run.
- **Idle sessions go quiet.** With nothing on a timer, the line freezes while the main
  session sits idle, e.g. while it waits on background subagents. The git segment can
  go stale in exactly that window if a subagent commits something.

If that staleness bothers you — or if you add a clock or elapsed-time segment, which
can't work without it — add `refreshInterval` (in seconds, minimum `1`) to re-run on a
fixed timer *in addition to* the events:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/dev/claude-code-status/statusline-command.sh",
    "refreshInterval": 5
  }
}
```

Edits to the script take effect on the next trigger — no restart, no re-source.

### Performance

This script measures ~60ms per invocation on a small repo, comfortably inside the
300ms debounce window. Most of that is the six `jq` subshells plus the `git` calls.

The part that degrades on large repos is `git status --porcelain` (used for the `✚n`
count), since it stats the entire work tree. If your line starts feeling laggy in a
monorepo, the [official docs](https://code.claude.com/docs/en/statusline#cache-expensive-operations)
suggest caching git output to a temp file. Key that cache on the `session_id` field
from the input JSON — **not** `$$`, which changes on every invocation and defeats the
cache entirely.

## Configuring

Create `~/.claude/statusline.conf` — it's plain bash, sourced by the script, and
overrides any of its defaults. **Don't edit `statusline-command.sh` directly**, or
the next `git pull` clobbers your preferences. See
[`statusline.conf.example`](statusline.conf.example) for every key with its default.

Keep the file minimal: only the keys you're actually changing. Restating a default
pins it, so you'd stop picking up upstream changes.

```sh
# ~/.claude/statusline.conf
SEGMENTS="path git context cost duration"   # which segments, and in what order
PATH_STYLE=basename
BAR_WIDTH=20
CONTEXT_SHOW_TOKENS=0
```

`SEGMENTS` controls **both which segments appear and their order**. Five of the nine
segments are on by default (`path model git context cost`, the table at the top of
this README); these four are implemented but off:

| Name | Renders | Notes |
|------|---------|-------|
| `duration` | `⏱ 1h 15m` | Session wall-clock time |
| `lines` | `±+156 -42` | Lines added / removed this session |
| `limit` | `⏳ 24%` | 5-hour rate limit — Claude.ai Pro/Max only, absent otherwise |
| `weather` | `🏙 Austin, TX ☀️ 84°F` | Needs `WEATHER_LOCATION`. The only segment that uses the network — see [Weather](#weather) |

Since the line is event-driven, `duration` and `limit` freeze while the session is
idle. Pair either with `refreshInterval` (above) if you want them ticking.

### Weather

Off unless you both add `weather` to `SEGMENTS` **and** set a location:

```sh
SEGMENTS="path model git context cost weather"
WEATHER_LOCATION="Austin,TX"      # anything wttr.in geocodes: city, "City,ST", airport code
WEATHER_LABEL="Austin, TX"        # display text; defaults to WEATHER_LOCATION
WEATHER_UNITS="F"                 # C | F
WEATHER_TTL=900                   # seconds between refreshes
```

This is the one segment that leaves your machine. It's built so that never costs you
latency:

- **Rendering never waits on the network.** It reads a cache file and prints whatever
  is there. A reading takes ~850ms to fetch — far outside the 300ms debounce — so a
  blocking call would get the status line cancelled on nearly every render.
- **Refreshes are detached background processes** with every file descriptor
  redirected, written to a temp file and moved into place atomically, so a render
  never sees a half-written cache.
- **The first render after enabling shows nothing**, then the segment appears once
  the fetch lands. That's expected, not a failure.
- A stamp file is touched *before* the fetch starts, so concurrent sessions don't all
  fire requests at once.

Data comes from [wttr.in](https://wttr.in), which handles geocoding, the
condition-to-emoji mapping and unit conversion server-side — one request, no API key,
no account. A failed or garbage lookup writes no cache and simply drops the segment.
Your configured location is sent to that third party every `WEATHER_TTL` seconds;
if that's not acceptable, leave the segment off.

Requires `curl` (present by default on macOS and most Linux). Cache lives in
`$TMPDIR`, keyed on location and units.

Other keys cover the separator, path style, per-segment colors and icons, bar
width/characters, and the yellow/red thresholds — all listed in the example file.

### Let Claude do it

The repo ships a [skill](.claude/skills/statusline-config/SKILL.md) that teaches
Claude Code this config format, so you can just ask:

> hide the cost segment
> put git first and use the short folder name
> show session duration and make the bar 20 wide

To use it outside this repo, link it into your global skills directory:

```bash
ln -sfn ~/dev/claude-code-status/.claude/skills/statusline-config \
        ~/.claude/skills/statusline-config
```

### Performance lever

Segments are computed lazily, so dropping one genuinely skips its work rather than
just hiding the output. `git` is the expensive one — removing it from `SEGMENTS`
takes the script from ~63ms to ~30ms per invocation, since it skips the
`git status --porcelain` work-tree scan.

## JSON fields used

From the [documented statusline input](https://code.claude.com/docs/en/statusline):
`workspace.current_dir`, `model.display_name`, `context_window.used_percentage`,
`context_window.context_window_size`, `context_window.total_input_tokens`,
`context_window.total_output_tokens`, `cost.total_cost_usd`, and — for the
off-by-default segments — `cost.total_duration_ms`, `cost.total_lines_added`,
`cost.total_lines_removed`, `rate_limits.five_hour.used_percentage`. Only the fields
needed by the enabled segments are read. Git info comes from running `git` locally
against the current directory.
