---
name: statusline-config
description: Toggle, reorder, or restyle segments in the claude-code-status status line — the path/model/git/context/cost bar. Use when the user asks to turn a segment on or off ("hide the cost", "drop the token count", "show session duration"), reorder segments, change colors, icons, separators, the context-bar width or thresholds, or asks what the status line can display. Edits ~/.claude/statusline.conf, never the script itself.
---

# Status line configuration

Changes the [claude-code-status](https://github.com/jason-c-dev/claude-code-status)
status line by editing its config file.

## The one rule

**Edit `~/.claude/statusline.conf`. Never edit `statusline-command.sh`.**

The script holds the defaults; the conf file overrides them and is `.`-sourced at
the end of the settings block. Editing the script directly means the next `git pull`
in the repo clobbers the user's preferences. The conf file is not in the repo, so it
survives updates.

Create the conf file if it doesn't exist. Keep it **minimal** — only the keys being
changed, not a copy of every default. A conf that restates defaults silently pins
them, so the user stops receiving upstream improvements.

## Workflow

1. Read `~/.claude/statusline.conf` if it exists.
2. Write only the changed keys (preserve any keys already there).
3. **Always preview the result** by piping a sample payload through the script —
   see [Verifying](#verifying). Show the user the rendered line.
4. Tell the user it takes effect on the next status line update (a new assistant
   message); no restart needed.

## Segments

`SEGMENTS` is a space-separated list that controls **both which segments appear and
their order**. Default:

```sh
SEGMENTS="path model git context cost"
```

| Name | Renders | Notes |
|------|---------|-------|
| `path` | `📁 ~/dev/my-project` | |
| `model` | `Fable 5 (1M)` | |
| `git` | `🌿 main ✚3 ↑1` | Only inside a git repo |
| `context` | `██████░░░░ 62% · 620.2K tok` | |
| `cost` | `💰 \$1.23` | Claude Code's client-side estimate (the `\` is escaping, not literal) |
| `duration` | `⏱️ 1h 15m` | **Off by default.** Session wall-clock |
| `lines` | `±+156 -42` | **Off by default.** Lines added/removed |
| `limit` | `⏳ 24%` | **Off by default.** 5-hour rate limit; Claude.ai Pro/Max only, absent otherwise |
| `weather` | `🏙️ Austin, TX ☀️ 84°F` | **Off by default.** Needs `WEATHER_LOCATION` too — see [Weather](#weather) |

To turn a segment off, remove its name from the list. To add one, append it (or
insert it where the user wants it in the order).

`duration` and `limit` only change meaningfully while the session is *working*.
Because the status line is event-driven, they freeze while the session is idle — if
the user enables either, mention `refreshInterval` in their `statusLine` settings
block (see the repo README's "When it runs").

## All settings

| Key | Default | Effect |
|-----|---------|--------|
| `SEGMENTS` | `path model git context cost` | Which segments, in order |
| `SEPARATOR` | `" \| "` | Text between segments |
| `SEP_COLOR` | `$DIM` | Separator color |
| `PATH_STYLE` | `tilde` | `tilde` (`~/dev/x`), `full` (`/Users/…/x`), `basename` (`x`) |
| `MODEL_SHOW_WINDOW` | `1` | Append `(1M)`/`(200K)` to model name |
| `GIT_SHOW_DIRTY` | `1` | The `✚n` uncommitted count |
| `GIT_SHOW_AHEAD_BEHIND` | `1` | The `↑n`/`↓n` upstream counts |
| `BAR_WIDTH` | `10` | Blocks in the context bar |
| `BAR_WARN` | `30` | % where the bar turns yellow |
| `BAR_CRIT` | `60` | % where it turns red |
| `BAR_FILLED` / `BAR_EMPTY` | `█` / `░` | Bar characters |
| `CONTEXT_SHOW_TOKENS` | `1` | The `· 620.2K tok` suffix |
| `ICON_PATH` | `"📁 "` | Include the trailing space; set `""` to drop the icon |
| `ICON_GIT` | `"🌿 "` | |
| `ICON_COST` | `"💰 "` | |
| `ICON_DURATION` | `"⏱️ "` | |
| `ICON_LINES` | `"±"` | |
| `ICON_LIMIT` | `"⏳ "` | |
| `ICON_WEATHER` | `"🏙️ "` | |
| `COLOR_PATH` | `$CYAN` | |
| `COLOR_MODEL` | `$MAGENTA` | |
| `COLOR_GIT` | `$GREEN` | |
| `COLOR_DIRTY` | `$YELLOW` | |
| `COLOR_SYNC` | `$BLUE` | `↑n`/`↓n` |
| `COLOR_COST` | `$YELLOW` | |
| `COLOR_DURATION` / `COLOR_LINES` / `COLOR_LIMIT` | `$WHITE` | |
| `COLOR_WEATHER` | `$CYAN` | |

Color variables available: `$CYAN $MAGENTA $GREEN $YELLOW $BLUE $RED $WHITE $DIM`.
For anything outside those, use a raw 256-color escape:
`COLOR_PATH=$'\033[38;5;208m'` (note the `$'…'` quoting — plain `"\033"` won't
expand in bash).

The context bar's green/yellow/red are wired to `BAR_WARN`/`BAR_CRIT` rather than the
`COLOR_*` variables, since they signal severity.

## Weather

The only segment that uses the network. Enabling it takes **two** keys — adding
`weather` to `SEGMENTS` alone does nothing:

```sh
SEGMENTS="path model git context cost weather"
WEATHER_LOCATION="Austin,TX"   # required: city, "City,ST", or airport code
WEATHER_LABEL="Austin, TX"     # optional display text, defaults to WEATHER_LOCATION
WEATHER_UNITS="F"              # C | F
WEATHER_TTL=900                # seconds between background refreshes
```

Use `WEATHER_LABEL` when the user wants "City, ST" displayed but the lookup works
better with a different string.

**Tell the user the first render will show no weather.** The fetch is a detached
background process, so the segment only appears on the *second* update, once the
cache is populated. This is expected — don't debug it as a failure. When verifying,
run the preview once, `sleep 4`, then run it again to show the populated line.

If it never appears after a few seconds, check in this order: is `curl` installed;
is `WEATHER_LOCATION` actually set; does the location geocode
(`curl -sf 'https://wttr.in/<loc>?format=%c%t&m'`). A location wttr.in can't resolve
writes no cache and silently drops the segment.

Mention once, when first enabling it, that the configured location goes to wttr.in
every `WEATHER_TTL` seconds. Don't belabour it on later changes.

## Verifying

Always run this after a change and show the user the output:

```bash
echo '{
  "workspace": {"current_dir": "'$PWD'"},
  "model": {"display_name": "Fable 5"},
  "cost": {"total_cost_usd": 1.2345, "total_duration_ms": 4530000,
           "total_lines_added": 156, "total_lines_removed": 42},
  "context_window": {"used_percentage": 62, "context_window_size": 1000000,
                     "total_input_tokens": 615000, "total_output_tokens": 5200},
  "rate_limits": {"five_hour": {"used_percentage": 23.5}}
}' | bash ~/dev/claude-code-status/statusline-command.sh
```

To preview a config **without** committing to it, point the script at a scratch file
instead of writing the user's conf:

```bash
CLAUDE_STATUSLINE_CONFIG=/tmp/preview.conf  # script reads this env var if set
```

Use this when offering the user a choice between two looks.

## Notes

- **Empty output is a bug, not a no-op.** If the preview prints nothing, `SEGMENTS`
  probably contains a typo — unknown names are silently ignored. Check the spelling
  against the segment table.
- **Turning off `git` is the real performance lever.** Segments are computed lazily,
  so removing `git` skips the `git status --porcelain` call entirely: measured ~63ms
  → ~30ms per invocation. Worth suggesting if the user reports lag in a large repo.
- Icons are mostly double-width emoji. If the user reports boxes or misalignment,
  offer Nerd Font glyphs (``, ``) or plain ASCII (`>`, `@`) via the `ICON_*` keys.
- **If an icon looks cramped or half-width next to its neighbours, the cause is
  usually a missing variation selector, not a missing space.** Codepoints like
  U+1F3D9 (🏙) and U+23F1 (⏱) default to *text* presentation and render narrow;
  appending U+FE0F forces emoji presentation and full width. Check with
  `printf '%s' "$icon" | hexdump -C` and look for a trailing `ef b8 8f`. Adding a
  second space instead just over-pads on terminals that render it wide.
- The conf file is plain bash, `.`-sourced — so it can hold logic, but keep it to
  assignments unless the user asks otherwise. Anything it prints to stdout would
  corrupt the status line.
