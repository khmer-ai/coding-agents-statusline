#!/usr/bin/env bash
# Antigravity CLI status line — 4-line layout, brand colors, progress bars.
# Reads session JSON on stdin.
# Requires: bash 3.2+  python3  (no jq or other installs needed)
set -euo pipefail

input=$(cat)

# ── Parse JSON via python3 (built-in on macOS/Linux — replaces jq) ───────────
_tmpjson=$(mktemp)
_tmppython=$(mktemp)
trap 'rm -f "$_tmpjson" "$_tmppython"' EXIT

printf '%s' "$input" > "$_tmpjson"

cat > "$_tmppython" << 'PYEOF'
import json, sys, math, time, subprocess, os

try:
    with open(sys.argv[1]) as fp:
        raw = fp.read().strip()
        d = json.loads(raw) if raw else {}
except Exception:
    d = {}

if not isinstance(d, dict):
    d = {}

ctx    = d.get("context_window") or {}
cost   = d.get("cost")           or {}
model  = d.get("model")          or {}
rl     = d.get("rate_limits")    or {}
quota  = d.get("quota")          or {}
ws     = d.get("workspace")      or {}
effort = d.get("effort")         or {}
vcs    = d.get("vcs")            or {}

cdir      = ws.get("current_dir") or d.get("cwd") or ""
cdir_last = cdir.replace("\\", "/").rstrip("/").split("/")[-1] if cdir else ""
if not cdir_last:
    try:
        cdir_last = os.path.basename(os.getcwd())
    except Exception:
        cdir_last = ""

# Rate limits / Quota (Claude Code & Antigravity)
five_h  = rl.get("five_hour")
if not five_h and quota:
    model_id = str(model.get("id") or "").lower()
    if "claude" in model_id or "3p" in model_id:
        q5 = quota.get("3p-5h") or quota.get("gemini-5h")
    else:
        q5 = quota.get("gemini-5h") or quota.get("3p-5h")
    if isinstance(q5, dict):
        rem = q5.get("remaining_fraction")
        used = round((1.0 - rem) * 100, 1) if rem is not None else -1
        reset_secs = q5.get("reset_in_seconds") or 0
        resets_at = int(time.time() + reset_secs) if reset_secs > 0 else 0
        five_h = {"used_percentage": used, "resets_at": resets_at}

seven_d = rl.get("seven_day")
if not seven_d and quota:
    model_id = str(model.get("id") or "").lower()
    if "claude" in model_id or "3p" in model_id:
        qw = quota.get("3p-weekly") or quota.get("gemini-weekly")
    else:
        qw = quota.get("gemini-weekly") or quota.get("3p-weekly")
    if isinstance(qw, dict):
        rem = qw.get("remaining_fraction")
        used = round((1.0 - rem) * 100, 1) if rem is not None else -1
        reset_secs = qw.get("reset_in_seconds") or 0
        resets_at = int(time.time() + reset_secs) if reset_secs > 0 else 0
        seven_d = {"used_percentage": used, "resets_at": resets_at}

five_pct   = five_h.get("used_percentage")   if isinstance(five_h,  dict) else -1
five_pct   = -1 if five_pct is None else five_pct
five_reset = (five_h.get("resets_at") or 0)  if isinstance(five_h,  dict) else 0

week_pct   = seven_d.get("used_percentage")  if isinstance(seven_d, dict) else -1
week_pct   = -1 if week_pct is None else week_pct
week_reset = (seven_d.get("resets_at") or 0) if isinstance(seven_d, dict) else 0

# Git branch resolution
branch = ws.get("git_worktree") or ws.get("branch") or vcs.get("branch") or ""
target_dir = cdir or os.getcwd()
if not branch and target_dir:
    try:
        r = subprocess.run(["git", "-C", target_dir, "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True, timeout=0.5)
        if r.returncode == 0:
            b = r.stdout.strip()
            if b != "HEAD":
                branch = b
    except Exception:
        branch = ""

# Effort level
effort_level = ""
if isinstance(model.get("effort"), str):
    effort_level = model.get("effort")
elif isinstance(effort, dict):
    effort_level = effort.get("level") or ""
elif isinstance(effort, str):
    effort_level = effort

# Lines added / removed
added = cost.get("total_lines_added") or 0
removed = cost.get("total_lines_removed") or 0
if added == 0 and removed == 0 and target_dir:
    try:
        r = subprocess.run(["git", "-C", target_dir, "diff", "--numstat", "HEAD"], capture_output=True, text=True, timeout=0.5)
        if r.returncode == 0:
            for line in r.stdout.splitlines():
                parts = line.split()
                if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
                    added += int(parts[0])
                    removed += int(parts[1])
    except Exception:
        pass

# Transcript path resolution
t_path = d.get("transcript_path") or ""
if not os.path.exists(t_path):
    conv_id = d.get("conversation_id") or d.get("session_id") or d.get("cascade_id") or ""
    if conv_id:
        alt = os.path.expanduser(f"~/.gemini/antigravity-cli/brain/{conv_id}/.system_generated/logs/transcript.jsonl")
        if os.path.exists(alt):
            t_path = alt
if not os.path.exists(t_path):
    brain_dir = os.path.expanduser("~/.gemini/antigravity-cli/brain")
    if os.path.isdir(brain_dir):
        try:
            candidates = [
                os.path.join(brain_dir, c, ".system_generated", "logs", "transcript.jsonl")
                for c in os.listdir(brain_dir)
            ]
            valid = [p for p in candidates if os.path.isfile(p)]
            if valid:
                t_path = max(valid, key=os.path.getmtime)
        except Exception:
            pass

rows = [
    model.get("display_name")       or "?",
    model.get("id")                 or "",
    int(math.floor(ctx.get("used_percentage") or 0)),
    ctx.get("total_input_tokens")   or 0,
    ctx.get("context_window_size")  or 1048576,
    cost.get("total_cost_usd")      or cost.get("total_usd") or 0,
    added,
    removed,
    five_pct,
    five_reset,
    week_pct,
    week_reset,
    branch,
    cdir_last,
    effort_level,
    t_path,
]
print("\n".join(str(r) for r in rows))
PYEOF

F=()
while IFS= read -r __line; do F+=("$__line"); done < <(python3 "$_tmppython" "$_tmpjson")

(( ${#F[@]} < 16 )) && exit 0

MODEL=${F[0]}; MODEL_ID=${F[1]}; IN_TOK=${F[3]}; CTX_WIN=${F[4]}
COST=${F[5]}; ADDED=${F[6]}; REMOVED=${F[7]}
FIVE_PCT=${F[8]}; FIVE_RESET=${F[9]}; WEEK_PCT=${F[10]}; WEEK_RESET=${F[11]}
BRANCH=${F[12]}; DIR=${F[13]}; EFFORT=${F[14]}; TRANSCRIPT=${F[15]}

# Context window size budget
case "$MODEL_ID" in
  *haiku*)          CTX_SIZE=150000 ;;
  *sonnet*|*opus*)  CTX_SIZE=700000 ;;
  *)                CTX_SIZE=${CTX_WIN:-1048576} ;;
esac
CTX_PCT=$(awk "BEGIN{ p = ($IN_TOK > 0) ? int($IN_TOK * 100 / $CTX_SIZE) : 0; print (p > 100 ? 100 : p) }")

# --- ANSI primitives ---------------------------------------------------------
R=$'\033[0m'; B=$'\033[1m'; DIM=$'\033[2m'; GREY=$'\033[90m'

# Brand palette — 24-bit ANSI foreground
MODEL_CLR=$'\033[38;2;0;110;0m'       # #006E00  dark green    model name
USER_CLR=$'\033[38;2;110;150;200m'    # #6E96C8  soft blue     username
HOST_CLR=$'\033[38;2;160;140;210m'    # #A08CD2  soft lavender device / hostname
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

# file_birth_epoch <path> — cross-platform "file created" time
file_birth_epoch() {
  local f=$1 t=""
  t=$(stat -c '%W' "$f" 2>/dev/null) || true
  { [ -z "$t" ] || [ "$t" = "0" ]; } && { t=$(stat -c '%Y' "$f" 2>/dev/null) || true; }
  { [ -z "$t" ] || [ "$t" = "0" ]; } && { t=$(stat -f '%B' "$f" 2>/dev/null) || true; }
  { [ -z "$t" ] || [ "$t" = "0" ]; } && { t=$(stat -f '%m' "$f" 2>/dev/null) || true; }
  [[ "$t" =~ ^[0-9]+$ ]] || t=0
  printf '%s' "$t"
}

# --- Wall-clock session timer (cross-platform) --------------------------------
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
CACHE_DIR="${HOME:-/tmp}/.gemini/antigravity-cli"
CACHE_FILE="$CACHE_DIR/.statusline-device-cache"
USER_NAME="${USER:-${USERNAME:-$(whoami 2>/dev/null || id -un 2>/dev/null || echo "")}}"

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
  # Fallback to hostname if device model could not be determined
  if [ -z "$DEVICE_MODEL" ]; then
    DEVICE_MODEL=$(hostname -s 2>/dev/null || uname -n 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "${HOSTNAME:-}")
    DEVICE_MODEL=${DEVICE_MODEL%%.*}
  fi
  if [ -n "$DEVICE_MODEL" ]; then
    mkdir -p "$CACHE_DIR" 2>/dev/null || true
    printf '%s' "$DEVICE_MODEL" > "$CACHE_FILE" 2>/dev/null || true
  fi
fi

# ─── LINE 1 ─ Model :effort │ 👤 user │ 💻 device │ 📂 Project ⎇ Branch │ ✏️ +add/−rm ─
L1="${MODEL_CLR}${B}${MDL_ICON} ${MODEL}${R}"
[ -n "$EFFORT" ] && L1+=" ${GREY}:${EFFORT}${R}"
[ -n "$USER_NAME" ] && L1+="${SEP}${USER_CLR}👤 ${USER_NAME}${R}"
[ -n "$DEVICE_MODEL" ] && L1+="${SEP}${HOST_CLR}💻 ${DEVICE_MODEL}${R}"
[ -n "$DIR" ] && L1+="${SEP}${DIR_CLR}${B}📂 ${DIR}${R}"
[ -n "$BRANCH" ] && L1+="  ${GREY}⎇${R}  ${DIR_CLR}${BRANCH}${R}"
if (( ADDED > 0 || REMOVED > 0 )); then
  L1+="${SEP}${GREY}✏️${R}  ${BAR_FILL}+${ADDED}${R}${GREY} / ${R}${DANGER_CLR}−${REMOVED}${R}"
fi

# ─── LINE 2 ─ Context window progress bar ─────────────────────────────────────
ctx_bar=$(progress_bar "$CTX_PCT" 24 "$BAR_FILL" "$BAR_EMPTY")
L2="${GREY}📊 Context  ${R}${ctx_bar}  ${BAR_FILL}${B}${CTX_PCT}%${R}  ${DIM}$(fmt_tokens "$IN_TOK") / $(fmt_tokens "$CTX_SIZE") tokens${R}"

# ─── LINE 3 ─ Timer   Cost ───────────────────────────────────────────────────
L3="${GREY}⏱${R}  $(fmt_secs "$wall_secs")   ${GREY}💰 \$${R}$(fmt_cost "$COST")"

# ─── LINE 4 ─ Rate limits side-by-side ───────────────────────────────────────
L4=""
if [ "$FIVE_PCT" != "-1" ] || [ "$WEEK_PCT" != "-1" ]; then
  if [ "$FIVE_PCT" != "-1" ]; then
    fc=$(limit_color "$FIVE_PCT")
    five_bar=$(progress_bar "${FIVE_PCT%%.*}" 16 "$fc" "$BAR_EMPTY")
    L4="${GREY}⚡ 5h       ${R}${five_bar}  ${fc}${B}${FIVE_PCT%%.*}%${R}  ${DIM}⟳ $(reset_in "$FIVE_RESET")${R}"
  fi
  if [ "$WEEK_PCT" != "-1" ]; then
    wk_clr=$(limit_color "$WEEK_PCT")
    week_bar=$(progress_bar "${WEEK_PCT%%.*}" 16 "$wk_clr" "$BAR_EMPTY")
    wk="${GREY}🗓  Wk   ${R}${week_bar}  ${wk_clr}${B}${WEEK_PCT%%.*}%${R}  ${DIM}⟳ $(reset_in "$WEEK_RESET")${R}"
    [ -n "$L4" ] && L4+="   ${GREY}│${R}   $wk" || L4="$wk"
  fi
fi

# ─── Output ───────────────────────────────────────────────────────────────────
printf '%b\n' "$L1"
printf '%b\n' "$L2"
printf '%b\n' "$L3"
[ -n "$L4" ] && printf '%b\n' "$L4"

exit 0
