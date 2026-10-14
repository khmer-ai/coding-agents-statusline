#!/usr/bin/env bash
# Claude Code status line — 3-line layout, brand colors, progress bars.
# Reads session JSON on stdin. Fields: https://code.claude.com/docs/en/statusline.md
set -euo pipefail

input=$(cat)

# --- Extract fields (newline-per-value — preserves spaces and empty entries) --
F=()
while IFS= read -r __line; do F+=("$__line"); done < <(printf '%s' "$input" | jq -r '
  [
    .model.display_name // "?",
    .model.id // "",
    (.context_window.used_percentage // 0 | floor),
    (.context_window.total_input_tokens // 0),
    (.context_window.context_window_size // 200000),
    (.cost.total_cost_usd // 0),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.rate_limits.five_hour.used_percentage // -1),
    (.rate_limits.five_hour.resets_at // 0),
    (.rate_limits.seven_day.used_percentage // -1),
    (.rate_limits.seven_day.resets_at // 0),
    (.workspace.git_worktree // ""),
    (.workspace.current_dir // .cwd // "" | split("/") | last // ""),
    (.effort.level // ""),
    (.transcript_path // "")
  ] | .[]')

# jq can emit fewer than 16 lines on malformed/incomplete stdin; bail clean
# instead of tripping `set -u` on ${F[N]} below (which aborts with zero output).
(( ${#F[@]} < 16 )) && exit 0

MODEL=${F[0]}; MODEL_ID=${F[1]}; IN_TOK=${F[3]}
COST=${F[5]}; ADDED=${F[6]}; REMOVED=${F[7]}
FIVE_PCT=${F[8]}; FIVE_RESET=${F[9]}; WEEK_PCT=${F[10]}; WEEK_RESET=${F[11]}
BRANCH=${F[12]}; DIR=${F[13]}; EFFORT=${F[14]}; TRANSCRIPT=${F[15]}

# Custom practical context limits — Haiku 150k, Sonnet/Opus 700k.
# We recalculate % against this cap rather than the model's hard technical max
# so the bar reflects a comfortable working budget, not the absolute ceiling.
case "$MODEL_ID" in
  *haiku*) CTX_SIZE=150000 ;;
  *)       CTX_SIZE=700000 ;;
esac
CTX_PCT=$(awk "BEGIN{ p = ($IN_TOK > 0) ? int($IN_TOK * 100 / $CTX_SIZE) : 0; print (p > 100 ? 100 : p) }")

# --- ANSI primitives ---------------------------------------------------------
R=$'\033[0m'; B=$'\033[1m'; DIM=$'\033[2m'; GREY=$'\033[90m'

# Brand palette — 24-bit ANSI foreground
MODEL_CLR=$'\033[38;2;0;110;0m'       # #006E00  dark green    model name
DIR_CLR=$'\033[38;2;194;153;64m'      # #C29940  warm gold     project / branch
BAR_FILL=$'\033[38;2;81;181;101m'     # #51B565  medium green  bar fill, %, added lines
BAR_EMPTY=$'\033[38;2;245;230;190m'   # #F5E6BE  cream         bar ░ slots
WARN_CLR=$'\033[38;2;194;153;64m'     # #C29940  gold          50–79 % warning
DANGER_CLR=$'\033[38;2;200;50;50m'    #           warm red      ≥80 % / removed lines

# Pipe separator used between line-1 segments
SEP="  ${GREY}│${R}  "

# --- Helpers -----------------------------------------------------------------
fmt_tokens() {
  local n=$1
  if   (( n >= 1000000 )); then awk "BEGIN{printf \"%.1fM\", $n/1000000}"
  elif (( n >= 1000 ));    then awk "BEGIN{printf \"%.0fk\", $n/1000}"
  else printf '%d' "$n"; fi
}

fmt_cost() { awk "BEGIN{printf \"%.3f\", $1}"; }

fmt_secs() {                           # wall-clock seconds → human string
  local s=$1 h m
  h=$(( s / 3600 )); m=$(( (s % 3600) / 60 )); s=$(( s % 60 ))
  if   (( h > 0 )); then printf '%dh %02dm' "$h" "$m"
  elif (( m > 0 )); then printf '%dm %02ds' "$m" "$s"
  else printf '%ds' "$s"; fi
}

reset_in() {                           # epoch → relative, days when > 23h59
  local target=$1 now diff days h m
  now=$(date +%s); diff=$(( target - now ))
  (( diff < 0 )) && diff=0
  days=$(( diff / 86400 )); h=$(( (diff % 86400) / 3600 )); m=$(( (diff % 3600) / 60 ))
  if   (( days > 0 )); then printf '%dd %dh' "$days" "$h"
  elif (( h > 0 ));    then printf '%dh %02dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}

limit_color() {                        # brand traffic-light for rate limit bars
  local p=${1%%.*}
  if   (( p >= 80 )); then printf '%s' "$DANGER_CLR"
  elif (( p >= 50 )); then printf '%s' "$WARN_CLR"
  else printf '%s' "$BAR_FILL"; fi
}

# progress_bar <pct> <width> <fill_clr> <empty_clr>
# Guarantees ≥ 1 filled block when pct > 0 (prevents floor-to-zero at low %)
progress_bar() {
  local pct=${1%%.*} width=$2 fill_clr=$3 empty_clr=$4
  (( pct > 100 )) && pct=100
  local filled=$(( pct * width / 100 ))
  (( pct > 0 && filled == 0 )) && filled=1
  local empty=$(( width - filled ))
  local bar="${fill_clr}" i
  for (( i=0; i<filled; i++ )); do bar+="█"; done
  bar+="${empty_clr}"
  for (( i=0; i<empty; i++ )); do bar+="░"; done
  bar+="${R}"
  printf '%s' "$bar"
}

# file_birth_epoch <path> — cross-platform "file created" time.
# Tries GNU birth time (linux/git-bash coreutils) first, then BSD birth time
# (mac), falling back to mtime on whichever stat dialect is present.
# GNU stat's `-f` flag means "report on the filesystem", not "format string"
# (that's BSD's meaning) — trying the BSD form first on Linux makes GNU stat
# print a multi-line filesystem report to *stdout*, which command substitution
# captures, contaminating $t with non-numeric text that later blows up the
# `(( sess_start > 0 ))` arithmetic check below under `set -u`.
file_birth_epoch() {
  local f=$1 t=""
  t=$(stat -c '%W' "$f" 2>/dev/null) || true
  { [ -z "$t" ] || [ "$t" = "0" ]; } && { t=$(stat -c '%Y' "$f" 2>/dev/null) || true; }
  { [ -z "$t" ] || [ "$t" = "0" ]; } && { t=$(stat -f '%B' "$f" 2>/dev/null) || true; }
  { [ -z "$t" ] || [ "$t" = "0" ]; } && { t=$(stat -f '%m' "$f" 2>/dev/null) || true; }
  [[ "$t" =~ ^[0-9]+$ ]] || t=0
  printf '%s' "$t"
}

# --- Wall-clock session timer ------------------------------------------------
# Reads the transcript file's birth time so the clock counts from the
# moment the session started, regardless of when Claude last responded.
wall_secs=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  sess_start=$(file_birth_epoch "$TRANSCRIPT")
  if (( sess_start > 0 )); then
    wall_secs=$(( $(date +%s) - sess_start ))
    (( wall_secs < 0 )) && wall_secs=0
  fi
fi

# --- Model icon --------------------------------------------------------------
case "$MODEL_ID" in
  *opus*)   MDL_ICON="◆" ;;
  *sonnet*) MDL_ICON="◈" ;;
  *haiku*)  MDL_ICON="◇" ;;
  *)        MDL_ICON="✦" ;;
esac

# --- Device model + username (cached — hardware queries are slow) ------------
# Cache survives across statusline refreshes (called every second); delete
# ~/.claude/.statusline-device-cache to force a re-detect.
CACHE_DIR="${HOME:-/tmp}/.claude"
CACHE_FILE="$CACHE_DIR/.statusline-device-cache"
USER_NAME="${USER:-${USERNAME:-$(whoami 2>/dev/null || echo "")}}"

DEVICE_MODEL=""
[ -f "$CACHE_FILE" ] && { DEVICE_MODEL=$(cat "$CACHE_FILE" 2>/dev/null) || true; }

if [ -z "$DEVICE_MODEL" ]; then
  OS_KIND=$(uname -s 2>/dev/null) || OS_KIND=""
  case "$OS_KIND" in
    Darwin)
      MODEL_NAME=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/{print $2; exit}') || true
      RES=$(system_profiler SPDisplaysDataType 2>/dev/null | awk '/Resolution:/{print $2"x"$4; exit}') || true
      case "$RES" in                                    # native-res → screen size
        3456x2234|3072x1920) SIZE=" 16" ;;
        3024x1964)           SIZE=" 14" ;;
        2880x1800|2880x1864) SIZE=" 15" ;;
        2560x1600|2560x1664) SIZE=" 13" ;;
        *)                   SIZE=""    ;;
      esac
      DEVICE_MODEL="${MODEL_NAME}${SIZE}"
      ;;
    Linux)
      DEVICE_MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null) || true
      ;;
    MINGW*|MSYS*|CYGWIN*)                               # Git Bash / MSYS on Windows
      DEVICE_MODEL=$(wmic csproduct get name 2>/dev/null | awk 'NR==2{$1=$1; print}') || true
      if [ -z "$DEVICE_MODEL" ]; then
        DEVICE_MODEL=$(powershell.exe -NoProfile -Command '(Get-CimInstance Win32_ComputerSystem).Model' 2>/dev/null | tr -d '\r') || true
      fi
      ;;
  esac
  if [ -n "$DEVICE_MODEL" ]; then
    mkdir -p "$CACHE_DIR" 2>/dev/null || true
    printf '%s' "$DEVICE_MODEL" > "$CACHE_FILE" 2>/dev/null || true
  fi
fi

# ─── LINE 1 ─ Model :effort │ 📂 Project 💻 Device 👤 User ⎇ Branch │ ✏️ ±lines ─
L1="${MODEL_CLR}${B}${MDL_ICON} ${MODEL}${R}"
[ -n "$EFFORT" ] && L1+=" ${GREY}:${EFFORT}${R}"
L1+="${SEP}${DIR_CLR}${B}📂 ${DIR}${R}"
[ -n "$DEVICE_MODEL" ] && L1+="  ${DIR_CLR}💻 ${DEVICE_MODEL}${R}"
[ -n "$USER_NAME" ] && L1+="  ${GREY}👤 ${USER_NAME}${R}"
[ -n "$BRANCH" ] && L1+="  ${GREY}⎇${R}  ${DIR_CLR}${BRANCH}${R}"
if (( ADDED > 0 || REMOVED > 0 )); then
  L1+="${SEP}${GREY}✏️${R}  ${BAR_FILL}+${ADDED}${R}${GREY} / ${R}${DANGER_CLR}−${REMOVED}${R}"
fi

# ─── LINE 2 ─ Context window progress bar ─────────────────────────────────────
# CTX_SIZE is the custom per-model practical limit (700k Sonnet/Opus, 150k Haiku)
ctx_bar=$(progress_bar "$CTX_PCT" 24 "$BAR_FILL" "$BAR_EMPTY")
L2="${GREY}📊 Context  ${R}${ctx_bar}  ${BAR_FILL}${B}${CTX_PCT}%${R}  ${DIM}$(fmt_tokens "$IN_TOK") / $(fmt_tokens "$CTX_SIZE") tokens${R}"

# ─── LINE 3 ─ Timer   Cost ───────────────────────────────────────────────────
L3="${GREY}⏱${R}  $(fmt_secs "$wall_secs")   ${GREY}💰 \$${R}$(fmt_cost "$COST")"

# ─── LINE 4 ─ Rate limits side-by-side (avoids stacking ░ rows visually) ─────
L4=""
if [ "$FIVE_PCT" != "-1" ] || [ "$WEEK_PCT" != "-1" ]; then
  if [ "$FIVE_PCT" != "-1" ]; then
    fc=$(limit_color "$FIVE_PCT")
    five_bar=$(progress_bar "${FIVE_PCT%%.*}" 16 "$fc" "$BAR_EMPTY")
    L4="${GREY}⚡ 5h       ${R}${five_bar}  ${fc}${B}${FIVE_PCT%%.*}%${R}  ${DIM}⟳ $(reset_in "$FIVE_RESET")${R}"
  fi
  if [ "$WEEK_PCT" != "-1" ]; then
    wc=$(limit_color "$WEEK_PCT")
    week_bar=$(progress_bar "${WEEK_PCT%%.*}" 16 "$wc" "$BAR_EMPTY")
    wk="${GREY}🗓  Wk   ${R}${week_bar}  ${wc}${B}${WEEK_PCT%%.*}%${R}  ${DIM}⟳ $(reset_in "$WEEK_RESET")${R}"
    [ -n "$L4" ] && L4+="   ${GREY}│${R}   $wk" || L4="$wk"
  fi
fi

# ─── Output ───────────────────────────────────────────────────────────────────
printf '%b\n' "$L1"
printf '%b\n' "$L2"
printf '%b\n' "$L3"
[ -n "$L4" ] && printf '%b\n' "$L4"

# Guarantee success exit status: the `[ -n "$L4" ]` test above is the last
# command run when L4 is empty (no rate-limit data yet), and its failure
# would otherwise become the script's exit code — Claude Code treats any
# non-zero exit as "blank the status line," discarding L1-L3 we already printed.
exit 0
