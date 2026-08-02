#!/bin/bash
# Claude Code status line:  <cwd> | <model> | ⎇ <branch> ✚n ↑n | ██████░░░░ 62%
#
# Reads the session JSON Claude Code pipes on stdin. Every segment is optional —
# a missing field (or a cwd that isn't a git repo) drops the segment AND its
# separator rather than leaving an empty slot, so the line always reads cleanly.
#
# Electric scheme: cyan path, magenta model, green git, context bar colored by
# usage (green <50%, yellow 50–80%, red >80%). Never touches the network.

input=$(cat)

rawdir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
model=$(echo "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
winsize=$(echo "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
tokens=$(echo "$input" | jq -r '(.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0) | if . > 0 then . else empty end' 2>/dev/null)

CYAN=$'\033[96m'; MAGENTA=$'\033[95m'; GREEN=$'\033[92m'; YELLOW=$'\033[93m'
BLUE=$'\033[94m'; RED=$'\033[91m'; WHITE=$'\033[97m'; DIM=$'\033[2;37m'; RESET=$'\033[0m'

# Abbreviate $HOME to ~, the way a shell prompt does. Full paths are long enough
# to push the model and context off a narrow pane.
dir="$rawdir"
case "$dir" in
  "$HOME") dir="~" ;;
  "$HOME"/*) dir="~${dir#"$HOME"}" ;;
esac

# Context window size as (1M) / (200K), appended to the model when available.
winlabel=""
if [ -n "$winsize" ] && [ "$winsize" -gt 0 ] 2>/dev/null; then
  if [ "$winsize" -ge 1000000 ]; then
    winlabel="$(( winsize / 1000000 ))M"
  else
    winlabel="$(( winsize / 1000 ))K"
  fi
fi

# --- git segment (skipped unless rawdir is inside a work tree) ---------------
git_seg=""
if [ -n "$rawdir" ] && git -C "$rawdir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$rawdir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ "$branch" = "HEAD" ] && branch=$(git -C "$rawdir" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    git_seg="${GREEN}⎇ ${branch}${RESET}"
    dirty=$(git -C "$rawdir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    [ "${dirty:-0}" -gt 0 ] && git_seg+=" ${YELLOW}✚${dirty}${RESET}"
    counts=$(git -C "$rawdir" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)
    if [ -n "$counts" ]; then
      behind=${counts%%[[:space:]]*}
      ahead=${counts##*[[:space:]]}
      [ "${ahead:-0}" -gt 0 ] && git_seg+=" ${BLUE}↑${ahead}${RESET}"
      [ "${behind:-0}" -gt 0 ] && git_seg+=" ${BLUE}↓${behind}${RESET}"
    fi
  fi
fi

# --- context bar --------------------------------------------------------------
bar_seg=""
if [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used" 2>/dev/null)
  [ "$pct" -lt 0 ] 2>/dev/null && pct=0
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  filled=$(( (pct + 5) / 10 ))
  [ "$filled" -gt 10 ] && filled=10
  if   [ "$pct" -ge 60 ]; then bar_color="$RED"
  elif [ "$pct" -ge 30 ]; then bar_color="$YELLOW"
  else                         bar_color="$GREEN"
  fi
  bar=""
  for ((i = 0; i < 10; i++)); do
    if [ "$i" -lt "$filled" ]; then bar+="█"; else bar+="░"; fi
  done
  bar_seg="${bar_color}${bar}${RESET} ${WHITE}${pct}%${RESET}"
  # Tokens currently in context, humanized (27.9K / 1.2M), after the bar.
  if [ -n "$tokens" ]; then
    toklabel=$(awk -v t="$tokens" 'BEGIN {
      if (t >= 1000000) printf "%.1fM", t/1000000
      else if (t >= 1000) printf "%.1fK", t/1000
      else printf "%d", t
    }')
    bar_seg+=" ${DIM}·${RESET} ${WHITE}${toklabel} tok${RESET}"
  fi
fi

segments=()
[ -n "$dir" ] && segments+=("${CYAN}${dir}${RESET}")
if [ -n "$model" ]; then
  # Some display names already embed the size ("Opus 5 (1M context)") — don't double it.
  case "$(echo "$model" | tr '[:upper:]' '[:lower:]')" in
    *"$(echo "$winlabel" | tr '[:upper:]' '[:lower:]')"*) ;;
    *) [ -n "$winlabel" ] && model="${model} (${winlabel})" ;;
  esac
  segments+=("${MAGENTA}${model}${RESET}")
fi
[ -n "$git_seg" ] && segments+=("$git_seg")
[ -n "$bar_seg" ] && segments+=("$bar_seg")

# Nothing resolved (malformed or empty stdin) — print nothing rather than a bare
# separator or a stray jq error.
[ ${#segments[@]} -eq 0 ] && exit 0

out=""
sep=""
for s in "${segments[@]}"; do
  out="${out}${sep}${s}"
  sep="${DIM} | ${RESET}"
done

printf '%s' "$out"
