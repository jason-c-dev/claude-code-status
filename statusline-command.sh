#!/bin/bash
# Claude Code status line:  📁 <cwd> | <model> | 🌿 <branch> ✚n ↑n | ██████░░░░ 62% | 💰 $0.12
#
# Reads the session JSON Claude Code pipes on stdin. Every segment is optional —
# a missing field (or a cwd that isn't a git repo) drops the segment AND its
# separator rather than leaving an empty slot, so the line always reads cleanly.
#
# Which segments appear, in what order, and how they look is all controlled by
# the settings below. Override any of them in ~/.claude/statusline.conf rather
# than editing this file, so a `git pull` never clobbers your preferences.
# No network access unless you explicitly enable the `weather` segment, which is
# the sole exception and is off by default.

input=$(cat)

CYAN=$'\033[96m'; MAGENTA=$'\033[95m'; GREEN=$'\033[92m'; YELLOW=$'\033[93m'
BLUE=$'\033[94m'; RED=$'\033[91m'; WHITE=$'\033[97m'; DIM=$'\033[2;37m'; RESET=$'\033[0m'

# ---- settings (override in ~/.claude/statusline.conf) ------------------------

# Which segments to show, in display order. Available:
#   path model git context cost duration lines limit weather
SEGMENTS="path model git context cost"

SEPARATOR=" | "          # text between segments
SEP_COLOR="$DIM"

PATH_STYLE="tilde"       # tilde | full | basename
MODEL_SHOW_WINDOW=1      # append (1M)/(200K) to the model name
GIT_SHOW_DIRTY=1         # ✚n uncommitted-file count
GIT_SHOW_AHEAD_BEHIND=1  # ↑n/↓n vs upstream
BAR_WIDTH=10             # blocks in the context bar
BAR_WARN=30              # % at which the bar turns yellow
BAR_CRIT=60              # % at which the bar turns red
BAR_FILLED="█"
BAR_EMPTY="░"
CONTEXT_SHOW_TOKENS=1    # "· 620.2K tok" after the bar

# Weather. The ONLY segment that touches the network, and it's off unless you both
# add `weather` to SEGMENTS and set WEATHER_AIRPORT. Fetches happen in a detached
# background process and are cached; rendering only ever reads the cache, so the
# status line never blocks on the network.
#
# Airport codes only — a 3-letter IATA code, nothing else. City names geocode
# ambiguously and produce long, uneven labels; a code is exactly three characters
# and unambiguous, which is what keeps this segment short.
WEATHER_AIRPORT=""       # "SFO" / "LHR" / "SYD" — required, 3 letters
WEATHER_UNITS="C"        # C | F
WEATHER_TTL=900          # seconds before a background refresh is triggered

ICON_PATH="📁 "
ICON_GIT="🌿 "
ICON_COST="💰 "
ICON_DURATION="⏱️ "
ICON_LINES="±"
ICON_LIMIT="⏳ "
ICON_WEATHER="✈️ "

COLOR_PATH="$CYAN"
COLOR_MODEL="$MAGENTA"
COLOR_GIT="$GREEN"
COLOR_DIRTY="$YELLOW"
COLOR_SYNC="$BLUE"
COLOR_COST="$YELLOW"
COLOR_DURATION="$WHITE"
COLOR_LINES="$WHITE"
COLOR_LIMIT="$WHITE"
COLOR_WEATHER="$CYAN"

CONFIG="${CLAUDE_STATUSLINE_CONFIG:-$HOME/.claude/statusline.conf}"
[ -f "$CONFIG" ] && . "$CONFIG"

# ---- helpers -----------------------------------------------------------------

# Is a segment turned on? Everything below is computed lazily behind this check,
# so disabling `git` genuinely skips the git calls rather than just hiding them.
enabled() { case " $SEGMENTS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

j() { echo "$input" | jq -r "$1" 2>/dev/null; }

rawdir=$(j '.workspace.current_dir // .cwd // empty')

# ---- path --------------------------------------------------------------------
dir=""
if enabled path && [ -n "$rawdir" ]; then
  case "$PATH_STYLE" in
    full)     dir="$rawdir" ;;
    basename) dir="${rawdir##*/}" ;;
    *)        # tilde: abbreviate $HOME the way a shell prompt does, since full
              # paths are long enough to push later segments off a narrow pane.
              dir="$rawdir"
              case "$dir" in
                "$HOME")   dir="~" ;;
                "$HOME"/*) dir="~${dir#"$HOME"}" ;;
              esac ;;
  esac
fi

# ---- model -------------------------------------------------------------------
model=""
if enabled model; then
  model=$(j '.model.display_name // empty')
  if [ -n "$model" ] && [ "$MODEL_SHOW_WINDOW" = 1 ]; then
    winsize=$(j '.context_window.context_window_size // empty')
    winlabel=""
    if [ -n "$winsize" ] && [ "$winsize" -gt 0 ] 2>/dev/null; then
      if [ "$winsize" -ge 1000000 ]; then
        winlabel="$(( winsize / 1000000 ))M"
      else
        winlabel="$(( winsize / 1000 ))K"
      fi
    fi
    # Some display names already embed the size ("Opus 5 (1M context)") — don't double it.
    if [ -n "$winlabel" ]; then
      case "$(echo "$model" | tr '[:upper:]' '[:lower:]')" in
        *"$(echo "$winlabel" | tr '[:upper:]' '[:lower:]')"*) ;;
        *) model="${model} (${winlabel})" ;;
      esac
    fi
  fi
fi

# ---- git (skipped unless rawdir is inside a work tree) -----------------------
git_seg=""
if enabled git && [ -n "$rawdir" ] && git -C "$rawdir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$rawdir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ "$branch" = "HEAD" ] && branch=$(git -C "$rawdir" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    git_seg="${COLOR_GIT}${ICON_GIT}${branch}${RESET}"
    if [ "$GIT_SHOW_DIRTY" = 1 ]; then
      dirty=$(git -C "$rawdir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
      [ "${dirty:-0}" -gt 0 ] && git_seg+=" ${COLOR_DIRTY}✚${dirty}${RESET}"
    fi
    if [ "$GIT_SHOW_AHEAD_BEHIND" = 1 ]; then
      counts=$(git -C "$rawdir" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)
      if [ -n "$counts" ]; then
        behind=${counts%%[[:space:]]*}
        ahead=${counts##*[[:space:]]}
        [ "${ahead:-0}" -gt 0 ] && git_seg+=" ${COLOR_SYNC}↑${ahead}${RESET}"
        [ "${behind:-0}" -gt 0 ] && git_seg+=" ${COLOR_SYNC}↓${behind}${RESET}"
      fi
    fi
  fi
fi

# ---- context bar -------------------------------------------------------------
bar_seg=""
if enabled context; then
  used=$(j '.context_window.used_percentage // empty')
  if [ -n "$used" ]; then
    pct=$(printf '%.0f' "$used" 2>/dev/null)
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    filled=$(( (pct * BAR_WIDTH + 50) / 100 ))
    [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
    if   [ "$pct" -ge "$BAR_CRIT" ]; then bar_color="$RED"
    elif [ "$pct" -ge "$BAR_WARN" ]; then bar_color="$YELLOW"
    else                                  bar_color="$GREEN"
    fi
    bar=""
    for ((i = 0; i < BAR_WIDTH; i++)); do
      if [ "$i" -lt "$filled" ]; then bar+="$BAR_FILLED"; else bar+="$BAR_EMPTY"; fi
    done
    bar_seg="${bar_color}${bar}${RESET} ${WHITE}${pct}%${RESET}"
    # Tokens currently in context, humanized (27.9K / 1.2M), after the bar.
    if [ "$CONTEXT_SHOW_TOKENS" = 1 ]; then
      tokens=$(j '(.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0) | if . > 0 then . else empty end')
      if [ -n "$tokens" ]; then
        toklabel=$(awk -v t="$tokens" 'BEGIN {
          if (t >= 1000000) printf "%.1fM", t/1000000
          else if (t >= 1000) printf "%.1fK", t/1000
          else printf "%d", t
        }')
        bar_seg+=" ${DIM}·${RESET} ${WHITE}${toklabel} tok${RESET}"
      fi
    fi
  fi
fi

# ---- session cost ------------------------------------------------------------
# Claude Code computes this client-side and hands it over ready-made, so we don't
# price tokens ourselves: cache reads and cache writes bill at different rates
# from fresh input, and the token counts above are *current context*, not
# cumulative session usage — a tokens x rate estimate would be wrong on both counts.
cost_seg=""
if enabled cost; then
  cost=$(j '.cost.total_cost_usd // empty')
  if [ -n "$cost" ]; then
    costlabel=$(awk -v c="$cost" 'BEGIN {
      if (c >= 0.01 || c <= 0) printf "$%.2f", c
      else printf "$%.3f", c
    }')
    cost_seg="${COLOR_COST}${ICON_COST}${costlabel}${RESET}"
  fi
fi

# ---- session duration --------------------------------------------------------
dur_seg=""
if enabled duration; then
  ms=$(j '.cost.total_duration_ms // empty')
  if [ -n "$ms" ] && [ "$ms" -gt 0 ] 2>/dev/null; then
    h=$(( ms / 3600000 )); m=$(( (ms % 3600000) / 60000 )); s=$(( (ms % 60000) / 1000 ))
    if   [ "$h" -gt 0 ]; then durlabel="${h}h ${m}m"
    elif [ "$m" -gt 0 ]; then durlabel="${m}m ${s}s"
    else                      durlabel="${s}s"
    fi
    dur_seg="${COLOR_DURATION}${ICON_DURATION}${durlabel}${RESET}"
  fi
fi

# ---- lines changed -----------------------------------------------------------
lines_seg=""
if enabled lines; then
  added=$(j '.cost.total_lines_added // empty')
  removed=$(j '.cost.total_lines_removed // 0')
  if [ -n "$added" ] && { [ "$added" -gt 0 ] || [ "${removed:-0}" -gt 0 ]; } 2>/dev/null; then
    lines_seg="${COLOR_LINES}${ICON_LINES}${RESET}${GREEN}+${added}${RESET} ${RED}-${removed:-0}${RESET}"
  fi
fi

# ---- rate limit (Claude.ai Pro/Max only; absent otherwise) -------------------
limit_seg=""
if enabled limit; then
  five=$(j '.rate_limits.five_hour.used_percentage // empty')
  if [ -n "$five" ]; then
    fivepct=$(printf '%.0f' "$five" 2>/dev/null)
    if   [ "${fivepct:-0}" -ge 80 ]; then limit_color="$RED"
    elif [ "${fivepct:-0}" -ge 50 ]; then limit_color="$YELLOW"
    else                                  limit_color="$COLOR_LIMIT"
    fi
    limit_seg="${limit_color}${ICON_LIMIT}${fivepct}%${RESET}"
  fi
fi

# ---- weather -----------------------------------------------------------------
# The only segment that leaves the machine. Two rules keep it honest:
#   1. Rendering NEVER waits on the network — it reads a cache file and prints
#      whatever is there (nothing, on the very first run).
#   2. A refresh is a detached background process with every fd redirected, so
#      Claude Code's 300ms debounce can't be held open by a slow request.
# wttr.in does geocoding, condition->emoji and unit conversion server-side, so a
# reading costs one request and no API key.
weather_seg=""
# Normalise to an uppercase 3-letter code. Anything else — a city name, a typo, a
# code with punctuation — fails this check and the segment stays off, rather than
# silently querying something the user didn't intend.
wcode=""
case "$WEATHER_AIRPORT" in
  [A-Za-z][A-Za-z][A-Za-z]) wcode=$(printf '%s' "$WEATHER_AIRPORT" | tr '[:lower:]' '[:upper:]') ;;
esac

if enabled weather && [ -n "$wcode" ] && command -v curl >/dev/null 2>&1; then
  # Cache key covers code+units so changing either doesn't serve stale data from
  # the old settings.
  wcache="${TMPDIR:-/tmp}/claude-statusline-weather-${wcode}-${WEATHER_UNITS}"
  wstamp="${wcache}.stamp"

  # mtime in epoch seconds, BSD (macOS) and GNU (Linux) spellings.
  wmtime=$(stat -f %m "$wstamp" 2>/dev/null || stat -c %Y "$wstamp" 2>/dev/null || echo 0)
  wnow=$(date +%s)
  if [ $(( wnow - ${wmtime:-0} )) -ge "${WEATHER_TTL:-900}" ]; then
    # Stamp FIRST, so concurrent status line runs don't all fire a request while
    # one is already in flight.
    : > "$wstamp" 2>/dev/null
    case "$WEATHER_UNITS" in [Ff]*) wunit="u" ;; *) wunit="m" ;; esac
    (
      wtmp="${wcache}.$$"
      if curl -sf --max-time 8 "https://wttr.in/${wcode}?format=%c%t&${wunit}" -o "$wtmp" 2>/dev/null; then
        # Atomic swap so a render never sees a half-written file.
        mv -f "$wtmp" "$wcache" 2>/dev/null
      else
        rm -f "$wtmp" 2>/dev/null
      fi
    ) >/dev/null 2>&1 </dev/null &
    disown 2>/dev/null
  fi

  if [ -s "$wcache" ]; then
    # wttr.in returns e.g. "🌤️ +12°C" — drop the + and collapse whitespace.
    wraw=$(tr -d '\n' < "$wcache" | sed 's/+//g; s/  */ /g; s/^ *//; s/ *$//')
    if [ -n "$wraw" ]; then
      weather_seg="${COLOR_WEATHER}${ICON_WEATHER}${wcode}${RESET} ${WHITE}${wraw}${RESET}"
    fi
  fi
fi

# ---- render ------------------------------------------------------------------
segments=()
for name in $SEGMENTS; do
  case "$name" in
    path)     [ -n "$dir" ]       && segments+=("${COLOR_PATH}${ICON_PATH}${dir}${RESET}") ;;
    model)    [ -n "$model" ]     && segments+=("${COLOR_MODEL}${model}${RESET}") ;;
    git)      [ -n "$git_seg" ]   && segments+=("$git_seg") ;;
    context)  [ -n "$bar_seg" ]   && segments+=("$bar_seg") ;;
    cost)     [ -n "$cost_seg" ]  && segments+=("$cost_seg") ;;
    duration) [ -n "$dur_seg" ]   && segments+=("$dur_seg") ;;
    lines)    [ -n "$lines_seg" ] && segments+=("$lines_seg") ;;
    limit)    [ -n "$limit_seg" ] && segments+=("$limit_seg") ;;
    weather)  [ -n "$weather_seg" ] && segments+=("$weather_seg") ;;
  esac
done

# Nothing resolved (malformed or empty stdin) — print nothing rather than a bare
# separator or a stray jq error.
[ ${#segments[@]} -eq 0 ] && exit 0

out=""
sep=""
for s in "${segments[@]}"; do
  out="${out}${sep}${s}"
  sep="${SEP_COLOR}${SEPARATOR}${RESET}"
done

printf '%s' "$out"
