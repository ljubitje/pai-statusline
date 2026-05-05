#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# PAI Status Line
# ═══════════════════════════════════════════════════════════════════════════════
#
# Dense 2-line statusline for PAI + Claude Code.
# Four sections: Identity, Session, Usage, Learning.
# Context shown as moon phase (🌑→🌕) scaled to compaction threshold if configured.
# ═══════════════════════════════════════════════════════════════════════════════

set -o pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

# PAI 5.0 path layout:
#   CLAUDE_HOME = Claude-Code-owned directory ($HOME/.claude)
#                 holds settings.json, hooks, statusline-command.sh itself
#   PAI_DIR     = PAI-owned subtree ($CLAUDE_HOME/PAI by default)
#                 holds MEMORY/, USER/, ALGORITHM/, etc.
# Pre-5.0 (legacy) had everything directly under $HOME/.claude — that breaks
# now because MEMORY moved to $HOME/.claude/PAI/MEMORY.
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
PAI_DIR="${PAI_DIR:-$CLAUDE_HOME/PAI}"
SETTINGS_FILE="$CLAUDE_HOME/settings.json"
RATINGS_FILE="$PAI_DIR/MEMORY/LEARNING/SIGNALS/ratings.jsonl"
MODEL_CACHE="$PAI_DIR/MEMORY/STATE/model-cache.txt"
USAGE_CACHE="$PAI_DIR/MEMORY/STATE/usage-cache.json"
STATUS_CACHE="$PAI_DIR/MEMORY/STATE/status-claude.json"
USAGE_CACHE_TTL=60       # 60 seconds (API recommends ≤1 poll/minute)
STATUS_CACHE_TTL=30

# Source .env for API keys
[ -f "${PAI_CONFIG_DIR:-$HOME/.config/PAI}/.env" ] && source "${PAI_CONFIG_DIR:-$HOME/.config/PAI}/.env"

# Cross-platform file mtime (seconds since epoch)
# macOS uses stat -f %m, Linux uses stat -c %Y
get_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# ─────────────────────────────────────────────────────────────────────────────
# PARSE INPUT (must happen before parallel block consumes stdin)
# ─────────────────────────────────────────────────────────────────────────────

input=$(cat)

# Extract all settings + counts in a single jq call (safe: no eval)
{
  IFS= read -r USER_TZ
  IFS= read -r PAI_VERSION
  IFS= read -r COMPACTION_THRESHOLD
  IFS= read -r ratings_count
  IFS= read -r skills_count
  IFS= read -r workflows_count
  IFS= read -r hooks_count
} < <(jq -r '
  (.principal.timezone // "UTC"),
  (.pai.version // "—"),
  (.contextDisplay.compactionThreshold // 100 | tostring),
  (.counts.ratings // 0 | tostring),
  (.counts.skills // 0 | tostring),
  (.counts.workflows // 0 | tostring),
  (.counts.hooks // 0 | tostring)
' "$SETTINGS_FILE" 2>/dev/null)
skills_count="${skills_count:-0}"
workflows_count="${workflows_count:-0}"
hooks_count="${hooks_count:-0}"
USER_TZ="${USER_TZ:-UTC}"
PAI_VERSION="${PAI_VERSION:-—}"
COMPACTION_THRESHOLD="${COMPACTION_THRESHOLD:-100}"

# Extract all data from JSON in single jq call (safe: no eval)
# Also extracts native rate_limits block (Claude Code ≥2.1.x) — when present,
# we skip the OAuth API roundtrip entirely (~50ms vs ~200ms, no 429 risk).
{
  IFS= read -r current_dir
  IFS= read -r session_id
  IFS= read -r model_name
  IFS= read -r cc_version_json
  IFS= read -r context_pct
  IFS= read -r has_native_rate_limits
  IFS= read -r native_usage_5h
  IFS= read -r native_usage_5h_reset
  IFS= read -r native_usage_7d
  IFS= read -r native_usage_7d_reset
} < <(echo "$input" | jq -r '
  (.workspace.current_dir // .cwd // "."),
  (.session_id // ""),
  (.model.display_name // "unknown"),
  (.version // ""),
  (.context_window.used_percentage // 0 | tostring),
  ((.rate_limits != null) | tostring),
  (.rate_limits.five_hour.used_percentage // .rate_limits.five_hour.utilization // 0 | tostring),
  (.rate_limits.five_hour.resets_at // ""),
  (.rate_limits.seven_day.used_percentage // .rate_limits.seven_day.utilization // 0 | tostring),
  (.rate_limits.seven_day.resets_at // "")
' 2>/dev/null)

# Ensure defaults for critical numeric values
context_pct=${context_pct:-0}
has_native_rate_limits="${has_native_rate_limits:-false}"

# Get Claude Code version
if [ -n "$cc_version_json" ] && [ "$cc_version_json" != "unknown" ]; then
    cc_version="$cc_version_json"
else
    cc_version=$(claude --version 2>/dev/null | head -1 | awk '{print $1}')
    cc_version="${cc_version:-unknown}"
fi

# Cache model name for other tools
mkdir -p "$(dirname "$MODEL_CACHE")" 2>/dev/null
echo "$model_name" > "$MODEL_CACHE" 2>/dev/null

# Session start dir — cache the cwd at first tick of the session and stick with it.
# Mirrors the SESSION_START_FILE pattern below; means an in-session `cd` doesn't
# change the displayed dir (statusline shows where the session began).
SESSION_STARTDIR_FILE="/tmp/pai-session-startdir-${session_id:-$$}"
if [ ! -f "$SESSION_STARTDIR_FILE" ]; then
    printf '%s' "${current_dir:-.}" > "$SESSION_STARTDIR_FILE"
fi
start_dir=$(cat "$SESSION_STARTDIR_FILE" 2>/dev/null)
[ -z "$start_dir" ] && start_dir="${current_dir:-.}"
dir_name=$(basename "$start_dir")

# ─────────────────────────────────────────────────────────────────────────────
# SESSION WALL-CLOCK TIME
# ─────────────────────────────────────────────────────────────────────────────
# Write start timestamp on first render, compute elapsed on each subsequent render.
# Cache epoch once — reused throughout the script to avoid repeated date forks
_NOW=$(date +%s)
SESSION_START_FILE="/tmp/pai-session-start-${session_id:-$$}"
if [ ! -f "$SESSION_START_FILE" ]; then
    echo "$_NOW" > "$SESSION_START_FILE"
fi
_session_start=$(cat "$SESSION_START_FILE")
_session_now=$_NOW
_session_elapsed=$((_session_now - _session_start))
_sess_h=$((_session_elapsed / 3600))
_sess_m=$((_session_elapsed % 3600 / 60))
if [ "$_sess_h" -gt 0 ]; then
    session_time="${_sess_h}h${_sess_m}m"
else
    session_time="${_sess_m}m"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PREFETCH - Single subshell for all I/O, cache reads are direct source
# ─────────────────────────────────────────────────────────────────────────────

_parallel_tmp="/tmp/pai-parallel-$$"
mkdir -p "$_parallel_tmp"

# Background subshell for git only (counts now extracted in settings jq above)
{
    if git rev-parse --git-dir > /dev/null 2>&1; then
        _branch=$(git branch --show-current 2>/dev/null)
        [ -z "$_branch" ] && _branch="detached"
        _last_epoch=$(git log -1 --format='%ct' 2>/dev/null)
        printf "branch='%s'\nlast_commit_epoch=%s\nis_git_repo=true\n" "$_branch" "${_last_epoch:-0}" > "$_parallel_tmp/git.sh"
    else
        echo "is_git_repo=false" > "$_parallel_tmp/git.sh"
    fi
} &

# Usage data — prefer native rate_limits (CC ≥2.1.x) over OAuth cache.
# Native path skips the OAuth roundtrip entirely; cache path remains as
# fallback for older CC versions that don't inject .rate_limits.
if [ "$has_native_rate_limits" = "true" ]; then
    usage_5h="$native_usage_5h"
    usage_5h_reset="$native_usage_5h_reset"
    usage_7d="$native_usage_7d"
    usage_7d_reset="$native_usage_7d_reset"
else
    USAGE_CACHE_SH="$PAI_DIR/MEMORY/STATE/usage-cache.sh"
    if [ -f "$USAGE_CACHE_SH" ]; then
        source "$USAGE_CACHE_SH"
    elif [ -f "$USAGE_CACHE" ]; then
        {
            IFS= read -r usage_5h
            IFS= read -r usage_5h_reset
            IFS= read -r usage_7d
            IFS= read -r usage_7d_reset
        } < <(jq -r '
            (.five_hour.utilization // 0 | tostring),
            (.five_hour.resets_at // ""),
            (.seven_day.utilization // 0 | tostring),
            (.seven_day.resets_at // "")
        ' "$USAGE_CACHE" 2>/dev/null)
    else
        usage_5h=0; usage_5h_reset=""
        usage_7d=0; usage_7d_reset=""
    fi
fi
usage_7d="${usage_7d:-0}"
usage_7d_reset="${usage_7d_reset:-}"

# Status cache — direct source from pre-built .sh (updated by fire-and-forget block)
STATUS_CACHE_SH="$PAI_DIR/MEMORY/STATE/status-cache.sh"
if [ -f "$STATUS_CACHE_SH" ]; then
    source "$STATUS_CACHE_SH"
else
    claude_status_indicator='unknown'; claude_status_desc='no cache'
fi

# Wait for git subshell
wait

# Source git results
[ -f "$_parallel_tmp/git.sh" ] && source "$_parallel_tmp/git.sh"
rm -rf "$_parallel_tmp" 2>/dev/null

LEARNING_CACHE="$PAI_DIR/MEMORY/STATE/learning-cache.sh"


# ─────────────────────────────────────────────────────────────────────────────
# COLOR PALETTE
# ─────────────────────────────────────────────────────────────────────────────
# Tailwind-inspired colors organized by usage

RESET='\033[0m'

# Structural (chrome, labels, separators)
SLATE_300='\033[38;2;229;229;229m'     # Match Claude output text
SLATE_400='\033[38;2;229;229;229m'     # Match Claude output text
SLATE_500='\033[38;2;229;229;229m'     # Match Claude output text
SLATE_600='\033[38;2;99;99;99m'        # Separators, empty bars

# Semantic colors
EMERALD='\033[38;2;74;222;128m'        # Positive/success
ROSE='\033[38;2;251;113;133m'          # Error/negative

# 5-color scale (used for all dynamic numbers: ratings, context%, usage%)
SCALE_GREEN='\033[38;2;70;175;95m'     # Great (bars)
SCALE_LIME='\033[38;2;150;190;40m'     # Good (bars)
SCALE_YELLOW='\033[38;2;255;193;7m'    # Neutral (bars) — matches ⭐
SCALE_ORANGE='\033[38;2;235;130;45m'   # Warning (bars)
SCALE_RED='\033[38;2;230;70;60m'       # Bad (bars)
# Text variants — same as bar colors
TEXT_GREEN="$SCALE_GREEN"
TEXT_LIME="$SCALE_LIME"
TEXT_YELLOW="$SCALE_YELLOW"
TEXT_ORANGE="$SCALE_ORANGE"
TEXT_RED="$SCALE_RED"

# Git age colors (sky/blue theme)
GIT_AGE_FRESH='\033[38;2;125;211;252m'
GIT_AGE_RECENT='\033[38;2;96;165;250m'
GIT_AGE_STALE='\033[38;2;59;130;246m'
GIT_AGE_OLD='\033[38;2;99;102;241m'

# PAI branding
PAI_P='\033[38;2;30;58;138m'          # Navy
PAI_A='\033[38;2;59;130;246m'         # Medium blue
PAI_I='\033[38;2;147;197;253m'        # Light blue
CC_C1='\033[38;2;217;119;87m'         # Claude terracotta/coral
CC_C2='\033[38;2;191;87;59m'          # Claude darker warm brown

# Version outdated dim (matches pipe separator color)
VERSION_DIM="$SLATE_600"

# ─────────────────────────────────────────────────────────────────────────────
# VERSION LATEST CHECK (cached by fire-and-forget block)
# ─────────────────────────────────────────────────────────────────────────────
VERSION_CACHE_SH="$PAI_DIR/MEMORY/STATE/version-cache.sh"
cc_latest=""; pai_latest=""
[ -f "$VERSION_CACHE_SH" ] && source "$VERSION_CACHE_SH"

# Format version: hide if latest, dim outdated segments if not
# Usage: format_version_display <current> <latest> <normal_color>
# Returns: empty string if latest, colored string if outdated
format_version_display() {
    local cur="${1#v}" lat="${2#v}" normal="$3"
    [ -z "$lat" ] && { printf ' %b%s%b' "$normal" "$1" "$RESET"; return; }
    [ "$cur" = "$lat" ] && return  # latest — hide
    IFS='.' read -ra c_parts <<< "$cur"
    IFS='.' read -ra l_parts <<< "$lat"
    local diverge=-1 i max=${#c_parts[@]}
    [ ${#l_parts[@]} -gt $max ] && max=${#l_parts[@]}
    for ((i=0; i<max; i++)); do
        [ "${c_parts[$i]:-0}" != "${l_parts[$i]:-0}" ] && { diverge=$i; break; }
    done
    [ $diverge -eq -1 ] && return  # match
    # Build output: matching segments in normal color, outdated in dim
    printf ' %b' "$normal"
    for ((i=0; i<${#c_parts[@]}; i++)); do
        [ $i -gt 0 ] && printf '.'
        [ $i -eq $diverge ] && printf '%b' "$VERSION_DIM"
        printf '%s' "${c_parts[$i]}"
    done
    printf '%b' "$RESET"
}

pai_ver_display=$(format_version_display "$PAI_VERSION" "$pai_latest" "$SLATE_500")
cc_ver_display=$(format_version_display "$cc_version" "$cc_latest" "$SLATE_500")

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Get color for rating value (handles "—" for no data)
get_rating_color() {
    local val="$1"
    [[ "$val" == "—" || -z "$val" ]] && { echo "$SLATE_400"; return; }
    local rating_int=${val%%.*}
    [[ ! "$rating_int" =~ ^[0-9]+$ ]] && { echo "$SLATE_400"; return; }

    if   [ "$rating_int" -ge 9 ]; then echo "$TEXT_GREEN"
    elif [ "$rating_int" -ge 7 ]; then echo "$TEXT_LIME"
    elif [ "$rating_int" -ge 5 ]; then echo "$TEXT_YELLOW"
    elif [ "$rating_int" -ge 3 ]; then echo "$TEXT_ORANGE"
    else echo "$TEXT_RED"
    fi
}

# Get color for usage percentage (green→yellow→orange→red)
get_usage_color() {
    local pct="$1"
    local pct_int=${pct%%.*}
    [ -z "$pct_int" ] && pct_int=0
    if   [ "$pct_int" -ge 90 ]; then echo "$TEXT_RED"
    elif [ "$pct_int" -ge 80 ]; then echo "$TEXT_ORANGE"
    elif [ "$pct_int" -ge 70 ]; then echo "$TEXT_YELLOW"
    elif [ "$pct_int" -ge 50 ]; then echo "$TEXT_LIME"
    else echo "$TEXT_GREEN"
    fi
}

# Parse ISO 8601 timestamp to epoch seconds using GNU date
# Handles Z suffix, timezone offsets (+00:00), and bare timestamps
parse_iso_epoch() {
    local ts="$1"
    [ -z "$ts" ] && return 1
    # GNU date -d handles ISO 8601 natively
    date -d "$ts" +%s 2>/dev/null
}

# Format reset time as countdown (e.g., "3h30m", "45m")
# Takes ISO timestamp, computes time remaining from now
format_reset_countdown() {
    local ts="$1"
    [ -z "$ts" ] && { echo "—"; return; }
    local reset_epoch
    reset_epoch=$(date -d "$ts" +%s 2>/dev/null) || { echo "—"; return; }
    local remaining=$(( reset_epoch - _NOW ))
    [ "$remaining" -le 0 ] && { echo "now"; return; }
    local rh=$(( remaining / 3600 ))
    local rm=$(( (remaining % 3600) / 60 ))
    if [ "$rh" -gt 0 ]; then
        rm=$(( (rm + 5) / 10 * 10 ))
        [ "$rm" -eq 60 ] && { rh=$((rh + 1)); rm=0; }
        [ "$rm" -gt 0 ] && echo "${rh}h${rm}m" || echo "${rh}h"
    else
        echo "${rm}m"
    fi
}

# Format reset time as day-of-week + clock (e.g., "TODAY@21:30", "SUN@21:30").
# Used for the 7d window where countdowns ("3d12h") are less actionable than
# the actual day the reset will land on. ISO timestamp in, "DAY@HH:MM" out.
format_reset_day() {
    local ts="$1"
    [ -z "$ts" ] && { echo "—"; return; }
    local reset_epoch
    reset_epoch=$(date -d "$ts" +%s 2>/dev/null) || { echo "—"; return; }
    [ "$reset_epoch" -le "$_NOW" ] && { echo "now"; return; }
    local reset_day reset_time reset_dow today_day dow
    reset_day=$(TZ="${USER_TZ:-UTC}" date -d "@$reset_epoch" +%Y-%m-%d 2>/dev/null) || { echo "—"; return; }
    reset_time=$(TZ="${USER_TZ:-UTC}" date -d "@$reset_epoch" +%H:%M 2>/dev/null)
    reset_dow=$(TZ="${USER_TZ:-UTC}" date -d "@$reset_epoch" +%w 2>/dev/null)
    today_day=$(TZ="${USER_TZ:-UTC}" date +%Y-%m-%d 2>/dev/null)
    if [ "$reset_day" = "$today_day" ]; then
        echo "TODAY@${reset_time}"
    else
        case "$reset_dow" in
            0) dow="SUN" ;; 1) dow="MON" ;; 2) dow="TUE" ;; 3) dow="WED" ;;
            4) dow="THU" ;; 5) dow="FRI" ;; 6) dow="SAT" ;; *) dow="—" ;;
        esac
        echo "${dow}@${reset_time}"
    fi
}

# Context moon phase indicator (5 levels)
# 🌑=empty 🌘=low 🌗=half 🌖=high 🌕=full
context_moon() {
    local pct=$1
    if   [ "$pct" -ge 80 ]; then echo "🌕"
    elif [ "$pct" -ge 60 ]; then echo "🌖"
    elif [ "$pct" -ge 40 ]; then echo "🌗"
    elif [ "$pct" -ge 20 ]; then echo "🌘"
    else echo "🌑"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# SESSION (session time, starting directory, git tree state)
# ═══════════════════════════════════════════════════════════════════════════════

# Check working tree state
TREE_COLOR_CLEAN="$EMERALD"
TREE_COLOR_STAGED='\033[38;2;250;204;21m'   # Yellow
TREE_COLOR_UNSTAGED="$ROSE"                 # Red (same as untracked)
TREE_COLOR_UNTRACKED="$ROSE"
tree_display=""
if [ "$is_git_repo" = "true" ]; then
    porcelain=$(git -C "$current_dir" status --porcelain 2>/dev/null)
    if [ -z "$porcelain" ]; then
        tree_display="${TREE_COLOR_CLEAN}clean${RESET}"
    else
        has_staged=false; has_unstaged=false; has_untracked=false
        echo "$porcelain" | grep -q '^[MADRC]' && has_staged=true
        echo "$porcelain" | grep -q '^.[MDRC]' && has_unstaged=true
        echo "$porcelain" | grep -q '^??' && has_untracked=true
        # Priority: untracked > unstaged > staged
        if [ "$has_untracked" = true ]; then
            tree_display="${TREE_COLOR_UNTRACKED}untracked${RESET}"
        elif [ "$has_unstaged" = true ]; then
            tree_display="${TREE_COLOR_UNSTAGED}unstaged${RESET}"
        elif [ "$has_staged" = true ]; then
            tree_display="${TREE_COLOR_STAGED}staged${RESET}"
        fi
    fi
fi

# Calculate age display from prefetched last_commit_epoch
if [ "$is_git_repo" = "true" ] && [ -n "$last_commit_epoch" ]; then
    now_epoch=$_NOW
    age_seconds=$((now_epoch - last_commit_epoch))
    age_minutes=$((age_seconds / 60))
    age_hours=$((age_seconds / 3600))
    age_days=$((age_seconds / 86400))

    if   [ "$age_minutes" -lt 1 ];  then age_display="now";         age_color="$GIT_AGE_FRESH"
    elif [ "$age_hours" -lt 1 ];    then age_display="${age_minutes}m"; age_color="$GIT_AGE_FRESH"
    elif [ "$age_hours" -lt 24 ];   then age_display="${age_hours}h";   age_color="$GIT_AGE_RECENT"
    elif [ "$age_days" -lt 7 ];     then age_display="${age_days}d";    age_color="$GIT_AGE_STALE"
    else age_display="${age_days}d"; age_color="$GIT_AGE_OLD"
    fi
fi


# ═══════════════════════════════════════════════════════════════════════════════
# LEARNING (ratings count, average rating, ratings bar, last rating)
# ═══════════════════════════════════════════════════════════════════════════════

LEARNING_CACHE_TTL=30  # seconds

if [ -f "$RATINGS_FILE" ] && [ -s "$RATINGS_FILE" ]; then
    now=$_NOW

    # Check cache validity (by mtime and ratings file mtime)
    cache_valid=false
    if [ -f "$LEARNING_CACHE" ]; then
        cache_mtime=$(get_mtime "$LEARNING_CACHE")
        ratings_mtime=$(get_mtime "$RATINGS_FILE")
        cache_age=$((now - cache_mtime))
        # Cache valid if: cache newer than ratings AND cache age < TTL
        if [ "$cache_mtime" -gt "$ratings_mtime" ] && [ "$cache_age" -lt "$LEARNING_CACHE_TTL" ]; then
            cache_valid=true
        fi
    fi

    if [ "$cache_valid" = true ]; then
        # Use cached values
        source "$LEARNING_CACHE"
    else
        # Compute fresh and cache
        # Extract RGB from SCALE_ vars for jq (single source of truth)
        # Vars are like '\033[38;2;R;G;Bm' — extract R;G;B, swap ; for ,
        _rgb() { echo "$1" | sed 's/.*38;2;\([0-9]*;[0-9]*;[0-9]*\)m.*/\1/' | tr ';' ','; }
        _sc_green=$(_rgb "$SCALE_GREEN")
        _sc_lime=$(_rgb "$SCALE_LIME")
        _sc_yellow=$(_rgb "$SCALE_YELLOW")
        _sc_orange=$(_rgb "$SCALE_ORANGE")
        _sc_red=$(_rgb "$SCALE_RED")
        _sc_empty=$(_rgb "$SLATE_600")
        eval "$(grep -a '^{' "$RATINGS_FILE" | jq -rs --argjson now "$now" \
          --arg sc_green "$_sc_green" --arg sc_lime "$_sc_lime" --arg sc_yellow "$_sc_yellow" \
          --arg sc_orange "$_sc_orange" --arg sc_red "$_sc_red" --arg sc_empty "$_sc_empty" '
      # Parse ISO timestamp to epoch (handles timezone offsets)
      def to_epoch:
        (capture("(?<sign>[-+])(?<h>[0-9]{2}):(?<m>[0-9]{2})$") // {sign: "+", h: "00", m: "00"}) as $tz |
        gsub("[-+][0-9]{2}:[0-9]{2}$"; "Z") | gsub("\\.[0-9]+"; "") | fromdateiso8601 |
        . + (if $tz.sign == "-" then 1 else -1 end) * (($tz.h | tonumber) * 3600 + ($tz.m | tonumber) * 60);

      # Filter valid ratings and add epoch
      [.[] | select(.rating != null) | . + {epoch: (.timestamp | to_epoch)}] |

      # Time boundaries
      ($now - 900) as $q15_start | ($now - 3600) as $hour_start | ($now - 86400) as $today_start |
      ($now - 604800) as $week_start | ($now - 2592000) as $month_start |

      # Calculate averages
      (map(select(.epoch >= $q15_start) | .rating) | if length > 0 then (add / length | . * 10 | floor / 10 | tostring) else "—" end) as $q15_avg |
      (map(select(.epoch >= $hour_start) | .rating) | if length > 0 then (add / length | . * 10 | floor / 10 | tostring) else "—" end) as $hour_avg |
      (map(select(.epoch >= $today_start) | .rating) | if length > 0 then (add / length | . * 10 | floor / 10 | tostring) else "—" end) as $today_avg |
      (map(select(.epoch >= $week_start) | .rating) | if length > 0 then (add / length | . * 10 | floor / 10 | tostring) else "—" end) as $week_avg |
      (map(select(.epoch >= $month_start) | .rating) | if length > 0 then (add / length | . * 10 | floor / 10 | tostring) else "—" end) as $month_avg |
      (map(.rating) | if length > 0 then (add / length | . * 10 | floor / 10 | tostring) else "—" end) as $all_avg |

      # Sparkline: diverging from 5, symmetric heights, color = direction
      def to_bar:
        floor |
        if . >= 9 then "\u001b[38;2;\($sc_green | gsub(",";";"))m▅\u001b[0m"
        elif . >= 7 then "\u001b[38;2;\($sc_lime | gsub(",";";"))m▄\u001b[0m"
        elif . >= 5 then "\u001b[38;2;\($sc_yellow | gsub(",";";"))m▃\u001b[0m"
        elif . >= 3 then "\u001b[38;2;\($sc_orange | gsub(",";";"))m▂\u001b[0m"
        else "\u001b[38;2;\($sc_red | gsub(",";";"))m▁\u001b[0m" end;            # red

      def make_sparkline($period_start):
        . as $all | ($now - $period_start) as $dur | ($dur / 52) as $sz |
        [range(52) | . as $i | ($period_start + ($i * $sz)) as $s | ($s + $sz) as $e |
          [$all[] | select(.epoch >= $s and .epoch < $e) | .rating] |
          if length == 0 then "\u001b[38;2;45;50;60m \u001b[0m" else (add / length) | to_bar end
        ] | join("");

      # Last 16 ratings sparkline, padded with underscores for empty slots
      (5 as $cap |
        (if length > $cap then .[-$cap:] else . end) as $recent |
        [range($cap - ($recent | length)) | null] + $recent |
        map(if . == null then "\u001b[38;2;\($sc_empty | gsub(",";";"))m▁\u001b[0m" else .rating | to_bar end) |
        join("")
      ) as $all_sparkline |

      (make_sparkline($q15_start)) as $q15_sparkline |
      (make_sparkline($hour_start)) as $hour_sparkline |
      (make_sparkline($today_start)) as $day_sparkline |
      (make_sparkline($week_start)) as $week_sparkline |
      (make_sparkline($month_start)) as $month_sparkline |

      # Trend calculation helper
      def calc_trend($data):
        if ($data | length) >= 2 then
          (($data | length) / 2 | floor) as $half |
          ($data[-$half:] | add / length) as $recent |
          ($data[:$half] | add / length) as $older |
          ($recent - $older) | if . > 0.5 then "up" elif . < -0.5 then "down" else "stable" end
        else "stable" end;

      # Friendly summary helper (8 words max)
      def friendly_summary($avg; $trend; $period):
        if $avg == "—" then "No data yet for \($period)"
        elif ($avg | tonumber) >= 8 then
          if $trend == "up" then "Excellent and improving" elif $trend == "down" then "Great but cooling slightly" else "Smooth sailing, all good" end
        elif ($avg | tonumber) >= 6 then
          if $trend == "up" then "Good and getting better" elif $trend == "down" then "Okay but trending down" else "Solid, steady performance" end
        elif ($avg | tonumber) >= 4 then
          if $trend == "up" then "Recovering, headed right direction" elif $trend == "down" then "Needs attention, declining" else "Mixed results, room to improve" end
        else
          if $trend == "up" then "Rough but improving now" elif $trend == "down" then "Struggling, needs focus" else "Challenging period, stay sharp" end
        end;

      # Hour and day trends
      ([.[] | select(.epoch >= $hour_start) | .rating]) as $hour_data |
      ([.[] | select(.epoch >= $today_start) | .rating]) as $day_data |
      (calc_trend($hour_data)) as $hour_trend |
      (calc_trend($day_data)) as $day_trend |

      # Generate friendly summaries
      (friendly_summary($hour_avg; $hour_trend; "hour")) as $hour_summary |
      (friendly_summary($today_avg; $day_trend; "day")) as $day_summary |

      # Overall trend
      length as $total |
      (if $total >= 4 then
        (($total / 2) | floor) as $half |
        (.[- $half:] | map(.rating) | add / length) as $recent |
        (.[:$half] | map(.rating) | add / length) as $older |
        ($recent - $older) | if . > 0.3 then "up" elif . < -0.3 then "down" else "stable" end
      else "stable" end) as $trend |

      (last | .rating | tostring) as $latest |
      (last | .source // "explicit") as $latest_source |

      "latest=\($latest | @sh)\nlatest_source=\($latest_source | @sh)\n" +
      "q15_avg=\($q15_avg | @sh)\nhour_avg=\($hour_avg | @sh)\ntoday_avg=\($today_avg | @sh)\n" +
      "week_avg=\($week_avg | @sh)\nmonth_avg=\($month_avg | @sh)\nall_avg=\($all_avg | @sh)\n" +
      "q15_sparkline=\($q15_sparkline | @sh)\nhour_sparkline=\($hour_sparkline | @sh)\nday_sparkline=\($day_sparkline | @sh)\n" +
      "week_sparkline=\($week_sparkline | @sh)\nmonth_sparkline=\($month_sparkline | @sh)\n" +
      "all_sparkline=\($all_sparkline | @sh)\n" +
      "hour_trend=\($hour_trend | @sh)\nday_trend=\($day_trend | @sh)\n" +
      "hour_summary=\($hour_summary | @sh)\nday_summary=\($day_summary | @sh)\n" +
      "trend=\($trend | @sh)\ntotal_count=\($total)"
    ' 2>/dev/null)"

        # Save to cache for next time
        cat > "$LEARNING_CACHE" << CACHE_EOF
latest='$latest'
latest_source='$latest_source'
q15_avg='$q15_avg'
hour_avg='$hour_avg'
today_avg='$today_avg'
week_avg='$week_avg'
month_avg='$month_avg'
all_avg='$all_avg'
q15_sparkline='$q15_sparkline'
hour_sparkline='$hour_sparkline'
day_sparkline='$day_sparkline'
week_sparkline='$week_sparkline'
month_sparkline='$month_sparkline'
all_sparkline='$all_sparkline'
hour_trend='$hour_trend'
day_trend='$day_trend'
hour_summary='$hour_summary'
day_summary='$day_summary'
trend='$trend'
total_count=$total_count
CACHE_EOF
    fi  # end cache computation

    if [ "$total_count" -gt 0 ] 2>/dev/null; then
        ALL_COLOR=$(get_rating_color "$all_avg")
        LATEST_COLOR=$(get_rating_color "${latest:-5}")
        [ "$latest_source" = "explicit" ] && src_suffix="e" || src_suffix="i"
        [ "$hour_avg" != "—" ] && star_icon="🌟" || star_icon="⭐"

        # Build Learning at 3 densities
        printf -v learn_full '%b' "🧠${ALL_COLOR}${all_avg}${RESET} ${all_sparkline} ✨${LATEST_COLOR}${latest}${src_suffix}${RESET} ${star_icon}${SLATE_300}${ratings_count}${RESET}"
        printf -v learn_dense '%b' "🧠${ALL_COLOR}${all_avg}${RESET} ✨${LATEST_COLOR}${latest}${src_suffix}${RESET} ${star_icon}${SLATE_300}${ratings_count}${RESET}"
        printf -v learn_ultra '%b' "🧠${ALL_COLOR}${all_avg}${RESET}"
    else
        # No ratings yet — show placeholder
        printf -v learn_full '%b' "🧠${SLATE_400}?${RESET} ${SLATE_300}no ratings${RESET} ✨${SLATE_400}-${RESET} ⭐${SLATE_300}0${RESET}"
        printf -v learn_dense '%b' "🧠${SLATE_400}?${RESET} ✨${SLATE_400}-${RESET} ⭐${SLATE_300}0${RESET}"
        printf -v learn_ultra '%b' "🧠${SLATE_400}?${RESET}"
    fi
else
    # No ratings file — show placeholder
    printf -v learn_full '%b' "🧠${SLATE_400}?${RESET} ${SLATE_300}no ratings${RESET} ✨${SLATE_400}-${RESET} ⭐${SLATE_300}0${RESET}"
    printf -v learn_dense '%b' "🧠${SLATE_400}?${RESET} ✨${SLATE_400}-${RESET} ⭐${SLATE_300}0${RESET}"
    printf -v learn_ultra '%b' "🧠${SLATE_400}?${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TERMINAL WIDTH + DISPLAY MEASUREMENT
# ═══════════════════════════════════════════════════════════════════════════════

_width_cache="/tmp/pai-term-width-${KITTY_WINDOW_ID:-default}"

detect_terminal_width() {
    local width=""
    # Tier 1: Kitty IPC (most accurate for Kitty panes)
    if [ -n "$KITTY_WINDOW_ID" ] && command -v kitten >/dev/null 2>&1; then
        width=$(kitten @ ls 2>/dev/null | jq -r --argjson wid "$KITTY_WINDOW_ID" \
            '.[].tabs[].windows[] | select(.id == $wid) | .columns' 2>/dev/null)
    fi
    # Tier 2: Direct TTY query
    [ -z "$width" ] || [ "$width" = "0" ] || [ "$width" = "null" ] && \
        width=$(stty size </dev/tty 2>/dev/null | awk '{print $2}')
    # Tier 3: tput fallback
    [ -z "$width" ] || [ "$width" = "0" ] && width=$(tput cols 2>/dev/null)
    # Cache if valid
    if [ -n "$width" ] && [ "$width" != "0" ] && [ "$width" -gt 0 ] 2>/dev/null; then
        echo "$width" > "$_width_cache" 2>/dev/null
        echo "$width"
        return
    fi
    # Tier 4: Read cached width
    if [ -f "$_width_cache" ]; then
        local cached=$(cat "$_width_cache" 2>/dev/null)
        [ "$cached" -gt 0 ] 2>/dev/null && { echo "$cached"; return; }
    fi
    # Tier 5: Default
    echo "${COLUMNS:-80}"
}

term_width=$(detect_terminal_width)

# Max display width of two lines (strip ANSI escapes, count display columns)
display_max_width() {
    printf '%s\n%s' "$1" "$2" | sed 's/\x1b\[[0-9;]*m//g' | wc -L
}

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD SECTIONS (full, dense, ultradense)
# ═══════════════════════════════════════════════════════════════════════════════

# Claude service status indicator
case "${claude_status_indicator:-unknown}" in
    none)        _status_icon="⬤"; _status_color="$TEXT_GREEN" ;;
    minor)       _status_icon="⬤"; _status_color="$TEXT_YELLOW" ;;
    major|critical) _status_icon="⬤"; _status_color="$TEXT_RED" ;;
    maintenance) _status_icon="⬤"; _status_color="$GIT_AGE_RECENT" ;;
    *)           _status_icon="◯"; _status_color="$SLATE_600" ;;
esac
_status_display=" ${_status_color}${_status_icon}${RESET} ${SLATE_400}${claude_status_desc:-fetch failed}${RESET}"

# IDENTITY (PAI version, CC version, Claude Code status)
# Version displays: empty if latest, space+dimmed if outdated
printf -v id_full '%b' "${PAI_P}P${PAI_A}A${PAI_I}I${RESET}${pai_ver_display} ${SLATE_600}│${RESET} ${CC_C1}C${CC_C2}C${RESET}${cc_ver_display}${_status_display}"
printf -v id_dense '%b' "${PAI_P}P${PAI_A}A${PAI_I}I${RESET} ${SLATE_600}│${RESET} ${CC_C1}C${CC_C2}C${RESET}${cc_ver_display}${_status_display}"
printf -v id_ultra '%b' "${CC_C1}C${CC_C2}C${RESET}${_status_display}"

# SESSION (session time, starting directory, git tree state)
printf -v sess_full '%b' "⏳${SLATE_400}${session_time}${RESET} 📍${SLATE_300}${dir_name}${RESET} 🌳${tree_display:-${SLATE_400}no repo${RESET}}"
printf -v sess_dense '%b' "⏳${SLATE_400}${session_time}${RESET} 🌳${tree_display:-${SLATE_400}no repo${RESET}}"
printf -v sess_ultra '%b' "🌳${tree_display:-${SLATE_400}no repo${RESET}}"

# USAGE (context bar + %, 5h utilization %, reset time)
raw_pct="${context_pct%%.*}"
[ -z "$raw_pct" ] && raw_pct=0

if [ "$COMPACTION_THRESHOLD" -lt 100 ] && [ "$COMPACTION_THRESHOLD" -gt 0 ]; then
    display_pct=$((raw_pct * 100 / COMPACTION_THRESHOLD))
    [ "$display_pct" -gt 100 ] && display_pct=100
else
    display_pct="$raw_pct"
fi

if   [ "$display_pct" -ge 90 ]; then pct_color="$TEXT_RED"
elif [ "$display_pct" -ge 80 ]; then pct_color="$TEXT_ORANGE"
elif [ "$display_pct" -ge 70 ]; then pct_color="$TEXT_YELLOW"
elif [ "$display_pct" -ge 50 ]; then pct_color="$TEXT_LIME"
else pct_color="$TEXT_GREEN"
fi

moon=$(context_moon $display_pct)
usage_5h_int=${usage_5h%%.*}
[ -z "$usage_5h_int" ] && usage_5h_int=0
usage_5h_remaining=$((100 - usage_5h_int))
[ "$usage_5h_remaining" -lt 0 ] && usage_5h_remaining=0

if [ "$usage_5h_int" -gt 0 ] || [ -f "$USAGE_CACHE" ]; then
    # Color based on remaining: low remaining = red, high remaining = green
    if   [ "$usage_5h_remaining" -le 10 ]; then usage_5h_color="$TEXT_RED"
    elif [ "$usage_5h_remaining" -le 20 ]; then usage_5h_color="$TEXT_ORANGE"
    elif [ "$usage_5h_remaining" -le 30 ]; then usage_5h_color="$TEXT_YELLOW"
    elif [ "$usage_5h_remaining" -le 50 ]; then usage_5h_color="$TEXT_LIME"
    else usage_5h_color="$TEXT_GREEN"
    fi
    battery_icon="🔋"
    [ "$usage_5h_remaining" -lt 20 ] && battery_icon="🪫"
    if [ -n "$usage_5h_reset" ]; then
        reset_5h_time=$(format_reset_countdown "$usage_5h_reset")
    else
        reset_5h_time="—"
    fi

    # 7d window — only renders when native rate_limits provided it (pre-2.1.x
    # OAuth path didn't expose 7d at all, so this stays empty for old CCs).
    usage_7d_block=""
    usage_7d_block_dense=""
    if [ -n "$usage_7d_reset" ] || [ "${usage_7d:-0}" != "0" ]; then
        usage_7d_int=${usage_7d%%.*}
        [ -z "$usage_7d_int" ] && usage_7d_int=0
        usage_7d_remaining=$((100 - usage_7d_int))
        [ "$usage_7d_remaining" -lt 0 ] && usage_7d_remaining=0
        if   [ "$usage_7d_remaining" -le 10 ]; then usage_7d_color="$TEXT_RED"
        elif [ "$usage_7d_remaining" -le 20 ]; then usage_7d_color="$TEXT_ORANGE"
        elif [ "$usage_7d_remaining" -le 30 ]; then usage_7d_color="$TEXT_YELLOW"
        elif [ "$usage_7d_remaining" -le 50 ]; then usage_7d_color="$TEXT_LIME"
        else usage_7d_color="$TEXT_GREEN"
        fi
        if [ -n "$usage_7d_reset" ]; then
            reset_7d_day=$(format_reset_day "$usage_7d_reset")
        else
            reset_7d_day="—"
        fi
        printf -v usage_7d_block '%b' " ${SLATE_600}│${RESET} ${SLATE_500}7d${RESET} ${usage_7d_color}${usage_7d_remaining}%${RESET} 🗓️${SLATE_500}${reset_7d_day}${RESET}"
        printf -v usage_7d_block_dense '%b' " ${SLATE_600}│${RESET} ${SLATE_500}7d${RESET} ${usage_7d_color}${usage_7d_remaining}%${RESET}"
    fi

    printf -v usage_full '%b' "${moon}${pct_color}${raw_pct}%${RESET} ${battery_icon}${usage_5h_color}${usage_5h_remaining}%${RESET} 🔄${SLATE_500}${reset_5h_time}${RESET}${usage_7d_block}"
    printf -v usage_dense '%b' "${moon}${pct_color}${raw_pct}%${RESET} ${battery_icon}${usage_5h_color}${usage_5h_remaining}%${RESET} 🔄${SLATE_500}${reset_5h_time}${RESET}${usage_7d_block_dense}"
    printf -v usage_ultra '%b' "${moon}${pct_color}${raw_pct}%${RESET} ${battery_icon}${usage_5h_color}${usage_5h_remaining}%${RESET}"
else
    printf -v usage_full '%b' "${moon}${pct_color}${raw_pct}%${RESET}"
    printf -v usage_dense '%b' "${moon}${pct_color}${raw_pct}%${RESET}"
    printf -v usage_ultra '%b' "${moon}${pct_color}${raw_pct}%${RESET}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STATE METER (B1 v5.0-style row) — reads PAI_STATE.json, renders dimensions
# ─────────────────────────────────────────────────────────────────────────────
# Format: STATE: HEALTH 68% │ CREATIVE 31% │ FREEDOM 78% │ RELATIONS 84% │ FIN 42%
# Missing dimensions render as "—" (per ISC-24 — never null or 0).
state_line=""
_PAI_STATE_JSON="$PAI_DIR/USER/TELOS/PAI_STATE.json"
if [ -f "$_PAI_STATE_JSON" ]; then
    _dim_color() {
        case "$1" in
            health)        printf '\033[38;2;56;189;248m' ;;
            money)         printf '\033[38;2;37;99;235m' ;;
            freedom)       printf '\033[38;2;59;130;246m' ;;
            relationships) printf '\033[38;2;96;165;250m' ;;
            creative)      printf '\033[38;2;147;197;253m' ;;
            *)             printf '%b' "$SLATE_400" ;;
        esac
    }
    _tier_color() {
        local pct="${1%%.*}"
        case "$pct" in
            ''|*[!0-9]*) printf '\033[38;2;100;116;139m'; return ;;
        esac
        if   [ "$pct" -ge 75 ]; then printf '\033[38;2;219;234;254m'
        elif [ "$pct" -ge 50 ]; then printf '\033[38;2;96;165;250m'
        else                         printf '\033[38;2;100;116;139m'
        fi
    }
    _dims=(health creative freedom relationships money)
    _labels=(HEALTH CREATIVE FREEDOM RELATIONS FIN)
    declare -a _pcts=(— — — — —)
    IFS=$'\t' read -r _state_h _state_c _state_f _state_r _state_m <<< "$(
        jq -r '[.dimensions.health.pct // "", .dimensions.creative.pct // "", .dimensions.freedom.pct // "", .dimensions.relationships.pct // "", .dimensions.money.pct // ""] | @tsv' "$_PAI_STATE_JSON" 2>/dev/null
    )"
    [ -n "$_state_h" ] && [ "$_state_h" != "null" ] && _pcts[0]="${_state_h%%.*}"
    [ -n "$_state_c" ] && [ "$_state_c" != "null" ] && _pcts[1]="${_state_c%%.*}"
    [ -n "$_state_f" ] && [ "$_state_f" != "null" ] && _pcts[2]="${_state_f%%.*}"
    [ -n "$_state_r" ] && [ "$_state_r" != "null" ] && _pcts[3]="${_state_r%%.*}"
    [ -n "$_state_m" ] && [ "$_state_m" != "null" ] && _pcts[4]="${_state_m%%.*}"

    _state_raw="${SLATE_500}STATE:${RESET} "
    for _i in "${!_dims[@]}"; do
        _dc=$(_dim_color "${_dims[$_i]}")
        _tc=$(_tier_color "${_pcts[$_i]}")
        _val="${_pcts[$_i]}"
        case "$_val" in
            ''|*[!0-9]*) _suffix="" ;;
            *)           _suffix="%" ;;
        esac
        _state_raw+="${_dc}${_labels[$_i]}${RESET} ${_tc}${_val}${_suffix}${RESET}"
        [ "$_i" -lt $((${#_dims[@]} - 1)) ] && _state_raw+=" ${SLATE_600}│${RESET} "
    done
    printf -v state_line '%b' "$_state_raw"
fi

# ─────────────────────────────────────────────────────────────────────────────
# COUNTS ROW (B2 v5.0-style) — skills (public🌐 / private🏠), workflows, hooks
# ─────────────────────────────────────────────────────────────────────────────
# settings.json counts.{skills,workflows,hooks} populated by SessionStart hook.
# Counts.skills is a single number; we render it as public + 0 private (mirrors
# v5.0 visual). When a private-skills dimension is added later, plug in here.
WIELD_ACCENT='\033[38;2;217;119;87m'
WIELD_WORKFLOWS='\033[38;2;180;140;60m'
WIELD_HOOKS='\033[38;2;125;211;252m'
counts_line=""
if [ "${skills_count:-0}" != "0" ] || [ "${workflows_count:-0}" != "0" ] || [ "${hooks_count:-0}" != "0" ]; then
    _counts_raw="${WIELD_ACCENT}SK:${RESET} ${SLATE_300}${skills_count}${RESET}${SLATE_600}🌐${RESET} ${SLATE_500}0${RESET}${SLATE_600}🏠${RESET}"
    _counts_raw+=" ${SLATE_600}│${RESET} ${WIELD_WORKFLOWS}WF:${RESET} ${SLATE_300}${workflows_count}${RESET}"
    _counts_raw+=" ${SLATE_600}│${RESET} ${WIELD_HOOKS}HK:${RESET} ${SLATE_300}${hooks_count}${RESET}"
    printf -v counts_line '%b' "$_counts_raw"
fi

# ─────────────────────────────────────────────────────────────────────────────
# QUOTE LINE (F10 — optional 5th line) — reuses .quote-cache from v5.0 upstream
# ─────────────────────────────────────────────────────────────────────────────
QUOTE_CACHE="$PAI_DIR/.quote-cache"
QUOTE_AUTHOR='\033[38;2;180;140;60m'
quote_line=""
if [ -f "$QUOTE_CACHE" ]; then
    IFS='|' read -r quote_text quote_author < "$QUOTE_CACHE" 2>/dev/null
    if [ -n "$quote_text" ] && [ -n "$quote_author" ]; then
        printf -v quote_line '%b' "${SLATE_400}\"${quote_text}\"${RESET} ${QUOTE_AUTHOR}—${quote_author}${RESET}"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# RENDER (pick largest density that fits terminal width)
# ═══════════════════════════════════════════════════════════════════════════════

printf -v sep '%b' " ${SLATE_600}│${RESET} "

# Compose lines at each density
line1_full="${id_full}${sep}${sess_full}"
line1_dense="${id_dense}${sep}${sess_dense}"
line1_ultra="${id_ultra}${sep}${sess_ultra}"

line2_full="${usage_full}"
line2_dense="${usage_dense}"
line2_ultra="${usage_ultra}"
[ -n "$learn_full" ] && line2_full="${line2_full}${sep}${learn_full}"
[ -n "$learn_dense" ] && line2_dense="${line2_dense}${sep}${learn_dense}"
[ -n "$learn_ultra" ] && line2_ultra="${line2_ultra}${sep}${learn_ultra}"

# Extra lines (state, counts, quote) — emitted after the chosen-tier line1+line2.
# Each is non-empty only when its source data exists; missing rows simply skip.
emit_extras() {
    [ -n "$state_line" ] && printf '%s\n' "$state_line"
    [ -n "$counts_line" ] && printf '%s\n' "$counts_line"
    [ -n "$quote_line" ] && printf '%s\n' "$quote_line"
}

# Try full → dense → ultradense (pick largest that fits)
_max_w=$(display_max_width "$line1_full" "$line2_full")
if [ "$_max_w" -le "$term_width" ]; then
    printf '%s\n%s\n' "$line1_full" "$line2_full"
    emit_extras
else
    _max_w=$(display_max_width "$line1_dense" "$line2_dense")
    if [ "$_max_w" -le "$term_width" ]; then
        printf '%s\n%s\n' "$line1_dense" "$line2_dense"
        emit_extras
    else
        printf '%s\n%s\n' "$line1_ultra" "$line2_ultra"
        # ultradense skips extras — narrow terminal can't fit the state row anyway
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# FIRE-AND-FORGET: Background cache refreshes (never block render)
# ─────────────────────────────────────────────────────────────────────────────
# All output is already printed above. These update cache files for the NEXT
# render. Lock file prevents overlapping fetches from concurrent calls.

_bg_lock="/tmp/pai-bg-fetch.lock"
if ! [ -f "$_bg_lock" ] || [ $(($(date +%s) - $(get_mtime "$_bg_lock"))) -gt 10 ]; then
    touch "$_bg_lock" 2>/dev/null
    (
        # Usage API refresh — SKIP entirely when CC injected native rate_limits.
        # No need to ping /api/oauth/usage if the data is already in stdin.
        _usage_age=999999
        [ -f "$USAGE_CACHE" ] && _usage_age=$(($(date +%s) - $(get_mtime "$USAGE_CACHE")))
        if [ "$has_native_rate_limits" != "true" ] && [ "$_usage_age" -gt "$USAGE_CACHE_TTL" ]; then
            if [ "$(uname -s)" = "Darwin" ]; then
                _cred_json=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
            else
                _cred_json=$(cat "${HOME}/.claude/.credentials.json" 2>/dev/null)
            fi
            _token=$(echo "$_cred_json" | jq -r '.claudeAiOauth.accessToken // ""' 2>/dev/null)
            if [ -n "$_token" ]; then
                _usage_json=$(curl -s --max-time 3 \
                    -H "Authorization: Bearer $_token" \
                    -H "Content-Type: application/json" \
                    -H "anthropic-beta: oauth-2025-04-20" \
                    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
                if [ -n "$_usage_json" ] && echo "$_usage_json" | jq -e '.five_hour' >/dev/null 2>&1; then
                    if [ -f "$USAGE_CACHE" ]; then
                        _ws_cost=$(jq -r '.workspace_cost // empty' "$USAGE_CACHE" 2>/dev/null)
                        if [ -n "$_ws_cost" ] && [ "$_ws_cost" != "null" ]; then
                            _usage_json=$(echo "$_usage_json" | jq --argjson ws "$_ws_cost" '. + {workspace_cost: $ws}' 2>/dev/null || echo "$_usage_json")
                        fi
                    fi
                    echo "$_usage_json" | jq '.' > "$USAGE_CACHE" 2>/dev/null
                    # Pre-build .sh cache for instant source on next render
                    echo "$_usage_json" | jq -r '
                        "usage_5h=" + (.five_hour.utilization // 0 | tostring) + "\n" +
                        "usage_5h_reset=" + (.five_hour.resets_at // "" | @sh) + "\n" +
                        "usage_7d=" + (.seven_day.utilization // 0 | tostring) + "\n" +
                        "usage_7d_reset=" + (.seven_day.resets_at // "" | @sh) + "\n" +
                        "usage_opus=" + (if .seven_day_opus then (.seven_day_opus.utilization // 0 | tostring) else "null" end) + "\n" +
                        "usage_sonnet=" + (if .seven_day_sonnet then (.seven_day_sonnet.utilization // 0 | tostring) else "null" end) + "\n" +
                        "usage_ws_cost_cents=" + (.workspace_cost.month_used_cents // 0 | tostring)
                    ' > "$PAI_DIR/MEMORY/STATE/usage-cache.sh" 2>/dev/null
                    # Countdown is always computed live from usage_5h_reset (changes every render)
                fi
            fi
        fi

        # Claude service status refresh
        _status_age=999999
        [ -f "$STATUS_CACHE" ] && _status_age=$(($(date +%s) - $(get_mtime "$STATUS_CACHE")))
        if [ "$_status_age" -gt "$STATUS_CACHE_TTL" ]; then
            _status_body=$(curl -s --max-time 3 "https://status.claude.com/api/v2/status.json" 2>/dev/null)
            if [ -n "$_status_body" ] && echo "$_status_body" | jq -e '.status.indicator' >/dev/null 2>&1; then
                echo "$_status_body" > "$STATUS_CACHE"
                # Pre-build .sh cache for instant source on next render
                _s_ind=$(echo "$_status_body" | jq -r '.status.indicator // "unknown"')
                case "$_s_ind" in
                    none)        _s_desc="ok" ;;
                    minor)       _s_desc="degraded" ;;
                    major)       _s_desc="outage" ;;
                    critical)    _s_desc="outage" ;;
                    maintenance) _s_desc="maintenance" ;;
                    *)           _s_desc="unknown" ;;
                esac
                printf "claude_status_indicator='%s'\nclaude_status_desc='%s'\n" "$_s_ind" "$_s_desc" > "$PAI_DIR/MEMORY/STATE/status-cache.sh"
            fi
        fi

        # Latest version cache refresh (CC from npm, PAI from GitHub)
        _ver_age=999999
        [ -f "$VERSION_CACHE_SH" ] && _ver_age=$(($(date +%s) - $(get_mtime "$VERSION_CACHE_SH")))
        if [ "$_ver_age" -gt 3600 ]; then
            _cc_lat=$(curl -s --max-time 3 "https://registry.npmjs.org/@anthropic-ai/claude-code/latest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)
            _pai_lat=$(curl -sL --max-time 3 "https://api.github.com/repos/danielmiessler/PAI/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null)
            _pai_lat="${_pai_lat#v}"  # strip leading v
            if [ -n "$_cc_lat" ] || [ -n "$_pai_lat" ]; then
                printf "cc_latest='%s'\npai_latest='%s'\n" "${_cc_lat:-}" "${_pai_lat:-}" > "$VERSION_CACHE_SH" 2>/dev/null
            fi
        fi

        rm -f "$_bg_lock" 2>/dev/null
    ) &
    disown 2>/dev/null
fi
