#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# PAI Status Line
# ═══════════════════════════════════════════════════════════════════════════════
#
# Responsive status line with 4 display modes based on terminal width:
#   - nano   (<35 cols): Minimal single-line displays
#   - micro  (35-54):    Compact with key metrics
#   - mini   (55-79):    Balanced information density
#   - normal (80+):      Full display with sparklines
#
# Output order: Greeting → Wielding → Git → Learning → Signal → Context → Quote
#
# Context percentage scales to compaction threshold if configured in settings.json.
# When contextDisplay.compactionThreshold is set (e.g., 62), the bar shows 62% as 100%.
# Set threshold to 100 or remove the setting to show raw 0-100% from Claude Code.
# ═══════════════════════════════════════════════════════════════════════════════

set -o pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

PAI_DIR="${PAI_DIR:-$HOME/.claude}"
SETTINGS_FILE="$PAI_DIR/settings.json"
RATINGS_FILE="$PAI_DIR/MEMORY/LEARNING/SIGNALS/ratings.jsonl"
TREND_CACHE="$PAI_DIR/MEMORY/STATE/trending-cache.json"
MODEL_CACHE="$PAI_DIR/MEMORY/STATE/model-cache.txt"
QUOTE_CACHE="$PAI_DIR/.quote-cache"
LOCATION_CACHE="$PAI_DIR/MEMORY/STATE/location-cache.json"
WEATHER_CACHE="$PAI_DIR/MEMORY/STATE/weather-cache.json"
USAGE_CACHE="$PAI_DIR/MEMORY/STATE/usage-cache.json"

# NOTE: context_window.used_percentage provides raw context usage from Claude Code.
# Scaling to compaction threshold is applied if configured in settings.json.

# Temperature unit preference (fahrenheit or celsius) — DISABLED: external API
# TEMP_UNIT=$(jq -r '.preferences.temperatureUnit // "fahrenheit"' "$SETTINGS_FILE" 2>/dev/null)
# [ "$TEMP_UNIT" != "celsius" ] && TEMP_UNIT="fahrenheit"

# Cache TTL in seconds
# LOCATION_CACHE_TTL=3600  # 1 hour (IP rarely changes) — DISABLED: external API
# WEATHER_CACHE_TTL=900    # 15 minutes — DISABLED: external API
COUNTS_CACHE_TTL=30      # 30 seconds (file counts rarely change mid-session)
USAGE_CACHE_TTL=60       # 60 seconds (API recommends ≤1 poll/minute)

# Additional cache files
COUNTS_CACHE="$PAI_DIR/MEMORY/STATE/counts-cache.sh"
STATUS_CACHE="$PAI_DIR/MEMORY/STATE/status-claude.json"
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

# Extract all settings in a single jq call (was 4 separate calls)
eval "$(jq -r '
  "DA_NAME=" + (.daidentity.name // .daidentity.displayName // .env.DA // "Assistant" | @sh) + "\n" +
  "USER_TZ=" + (.principal.timezone // "UTC" | @sh) + "\n" +
  "PAI_VERSION=" + (.pai.version // "—" | @sh) + "\n" +
  "COMPACTION_THRESHOLD=" + (.contextDisplay.compactionThreshold // 100 | tostring)
' "$SETTINGS_FILE" 2>/dev/null)"
DA_NAME="${DA_NAME:-Assistant}"
USER_TZ="${USER_TZ:-UTC}"
PAI_VERSION="${PAI_VERSION:-—}"
COMPACTION_THRESHOLD="${COMPACTION_THRESHOLD:-100}"

# Extract all data from JSON in single jq call
eval "$(echo "$input" | jq -r '
  "current_dir=" + (.workspace.current_dir // .cwd // "." | @sh) + "\n" +
  "session_id=" + (.session_id // "" | @sh) + "\n" +
  "model_name=" + (.model.display_name // "unknown" | @sh) + "\n" +
  "cc_version_json=" + (.version // "" | @sh) + "\n" +
  "duration_ms=" + (.cost.total_duration_ms // 0 | tostring) + "\n" +
  "context_max=" + (.context_window.context_window_size // 200000 | tostring) + "\n" +
  "context_pct=" + (.context_window.used_percentage // 0 | tostring) + "\n" +
  "context_remaining=" + (.context_window.remaining_percentage // 100 | tostring) + "\n" +
  "total_input=" + (.context_window.total_input_tokens // 0 | tostring) + "\n" +
  "total_output=" + (.context_window.total_output_tokens // 0 | tostring)
' 2>/dev/null)"

# Ensure defaults for critical numeric values
context_pct=${context_pct:-0}
context_max=${context_max:-200000}
context_remaining=${context_remaining:-100}
total_input=${total_input:-0}
total_output=${total_output:-0}

# NOTE: Removed fallback that calculated context_pct from total_input + total_output
# when used_percentage was 0. total_input/output_tokens are CUMULATIVE session totals
# (like an odometer) — they can far exceed context_window_size. After /clear,
# used_percentage is null (jq defaults to 0) but totals retain pre-clear values,
# producing inflated percentages capped to 100%. See PR #806.

# NOTE: Removed self-calibrating startup estimate block. It cached the previous
# session's context base tokens and used it to display an estimate before the first
# API call. Problem: deep sessions (e.g., 66k cached base) inflated fresh session
# displays (41% instead of real ~19%). Context shows 0% for a few seconds until
# the first API response, which is honest. See community feedback on #754.

# ─────────────────────────────────────────────────────────────────────────────
# SESSION COST ESTIMATION — DISABLED: not actionable
# Pricing: platform.claude.com/docs/en/about-claude/pricing
# Note: 1M context >200K tokens bills at 2x input ($6) and 1.5x output ($22.50)
#        We use base rates here as a floor estimate.
# ─────────────────────────────────────────────────────────────────────────────
session_cost_str=""
# if [ "$total_input" -gt 0 ] || [ "$total_output" -gt 0 ]; then
#     case "$model_name" in
#         *"Opus 4"*|*"opus-4"*)   input_mtok="15.00"; output_mtok="75.00" ;;
#         *"Sonnet 4"*)             input_mtok="3.00";  output_mtok="15.00" ;;
#         *"Haiku 4"*|*"haiku-4"*) input_mtok="0.80";  output_mtok="4.00"  ;;
#         *)                        input_mtok="3.00";  output_mtok="15.00" ;;
#     esac
#     session_cost_str=$(python3 -c "
# cost = ($total_input * $input_mtok + $total_output * $output_mtok) / 1_000_000
# if cost < 0.01:
#     print(f'\${cost:.4f}')
# elif cost < 1.00:
#     print(f'\${cost:.3f}')
# else:
#     print(f'\${cost:.2f}')
# " 2>/dev/null)
# fi

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

dir_name=$(basename "$current_dir" 2>/dev/null || echo ".")

# Session label lookup removed — session name no longer displayed in statusline

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

# Single background subshell for git + counts (the only ops that need forking)
{
    # Git — index-only ops
    if git rev-parse --git-dir > /dev/null 2>&1; then
        _branch=$(git branch --show-current 2>/dev/null)
        [ -z "$_branch" ] && _branch="detached"
        _last_epoch=$(git log -1 --format='%ct' 2>/dev/null)
        printf "branch='%s'\nlast_commit_epoch=%s\nis_git_repo=true\n" "$_branch" "${_last_epoch:-0}" > "$_parallel_tmp/git.sh"
    else
        echo "is_git_repo=false" > "$_parallel_tmp/git.sh"
    fi

    # Counts from settings.json
    jq -r '
        "skills_count=" + (.counts.skills // 0 | tostring) + "\n" +
        "workflows_count=" + (.counts.workflows // 0 | tostring) + "\n" +
        "hooks_count=" + (.counts.hooks // 0 | tostring) + "\n" +
        "learnings_count=" + (.counts.signals // 0 | tostring) + "\n" +
        "files_count=" + (.counts.files // 0 | tostring) + "\n" +
        "work_count=" + (.counts.work // 0 | tostring) + "\n" +
        "sessions_count=" + (.counts.sessions // 0 | tostring) + "\n" +
        "research_count=" + (.counts.research // 0 | tostring) + "\n" +
        "ratings_count=" + (.counts.ratings // 0 | tostring)
    ' "$SETTINGS_FILE" > "$_parallel_tmp/counts.sh" 2>/dev/null || cat > "$_parallel_tmp/counts.sh" << 'COUNTSEOF'
skills_count=0
workflows_count=0
hooks_count=0
learnings_count=0
files_count=0
work_count=0
sessions_count=0
research_count=0
ratings_count=0
COUNTSEOF
} &

# Usage cache — direct source from pre-built .sh (updated by fire-and-forget block)
USAGE_CACHE_SH="$PAI_DIR/MEMORY/STATE/usage-cache.sh"
if [ -f "$USAGE_CACHE_SH" ]; then
    source "$USAGE_CACHE_SH"
else
    usage_5h=0; usage_7d=0; usage_5h_reset=""; usage_7d_reset=""
    usage_opus="null"; usage_sonnet="null"; usage_ws_cost_cents=0
fi

# Status cache — direct source from pre-built .sh (updated by fire-and-forget block)
STATUS_CACHE_SH="$PAI_DIR/MEMORY/STATE/status-cache.sh"
if [ -f "$STATUS_CACHE_SH" ]; then
    source "$STATUS_CACHE_SH"
else
    claude_status_indicator='unknown'; claude_status_desc='no cache'
fi

# Wait for git + counts subshell only
wait

# Source parallel results
[ -f "$_parallel_tmp/git.sh" ] && source "$_parallel_tmp/git.sh"
[ -f "$_parallel_tmp/counts.sh" ] && source "$_parallel_tmp/counts.sh"
rm -rf "$_parallel_tmp" 2>/dev/null

# Pre-load learning cache (used by LEARNING section)
LEARNING_CACHE="$PAI_DIR/MEMORY/STATE/learning-cache.sh"

learning_count="$learnings_count"

# ─────────────────────────────────────────────────────────────────────────────
# TERMINAL WIDTH DETECTION
# ─────────────────────────────────────────────────────────────────────────────
# Hooks don't inherit terminal context. Try multiple methods.

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

    # If we got a real width, cache it for subprocess re-renders
    if [ -n "$width" ] && [ "$width" != "0" ] && [ "$width" -gt 0 ] 2>/dev/null; then
        echo "$width" > "$_width_cache" 2>/dev/null
        echo "$width"
        return
    fi

    # Tier 4: Read cached width from previous successful detection
    if [ -f "$_width_cache" ]; then
        local cached
        cached=$(cat "$_width_cache" 2>/dev/null)
        if [ "$cached" -gt 0 ] 2>/dev/null; then
            echo "$cached"
            return
        fi
    fi

    # Tier 5: Environment variable / default
    echo "${COLUMNS:-80}"
}

term_width=$(detect_terminal_width)

if [ "$term_width" -lt 35 ]; then
    MODE="nano"
elif [ "$term_width" -lt 55 ]; then
    MODE="micro"
elif [ "$term_width" -lt 80 ]; then
    MODE="mini"
else
    MODE="normal"
fi

# NOTE: DA_NAME, PAI_VERSION, input JSON, cc_version, model_name
# are all already parsed above (lines 59-113). No duplicate parsing needed.

dir_name=$(basename "$current_dir")

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

# Line 1: Greeting (violet theme)
GREET_PRIMARY='\033[38;2;167;139;250m'
GREET_SECONDARY='\033[38;2;139;92;246m'
GREET_ACCENT='\033[38;2;196;181;253m'

# Line 2: Wielding (cyan/teal theme)
WIELD_PRIMARY='\033[38;2;34;211;238m'
WIELD_SECONDARY='\033[38;2;45;212;191m'
WIELD_ACCENT='\033[38;2;103;232;249m'
WIELD_WORKFLOWS='\033[38;2;94;234;212m'
WIELD_HOOKS='\033[38;2;6;182;212m'
WIELD_LEARNINGS='\033[38;2;20;184;166m'

# Line 3: Git (sky/blue theme)
GIT_PRIMARY='\033[38;2;56;189;248m'
GIT_VALUE='\033[38;2;186;230;253m'
GIT_DIR='\033[38;2;147;197;253m'
GIT_CLEAN='\033[38;2;125;211;252m'
GIT_MODIFIED='\033[38;2;96;165;250m'
GIT_ADDED='\033[38;2;59;130;246m'
GIT_STASH='\033[38;2;165;180;252m'
GIT_AGE_FRESH='\033[38;2;125;211;252m'
GIT_AGE_RECENT='\033[38;2;96;165;250m'
GIT_AGE_STALE='\033[38;2;59;130;246m'
GIT_AGE_OLD='\033[38;2;99;102;241m'

# Line 4: Learning (purple theme)
LEARN_PRIMARY='\033[38;2;167;139;250m'
LEARN_SECONDARY='\033[38;2;196;181;253m'
# LEARN_WORK removed — Work section dropped from statusline
LEARN_SIGNALS='\033[38;2;139;92;246m'
LEARN_RESEARCH='\033[38;2;79;90;198m'
# LEARN_SESSIONS removed — Sessions section dropped from statusline

# Line 5: Learning Signal (green theme for RATING label)
SIGNAL_LABEL='\033[38;2;56;189;248m'
SIGNAL_COLOR='\033[38;2;96;165;250m'
SIGNAL_PERIOD='\033[38;2;229;229;229m'
LEARN_LABEL='\033[38;2;21;128;61m'    # Dark green for RATING:

# Line 6: Context (indigo theme)
CTX_PRIMARY='\033[38;2;129;140;248m'
CTX_SECONDARY='\033[38;2;165;180;252m'
CTX_ACCENT='\033[38;2;139;92;246m'
CTX_BUCKET_EMPTY='\033[38;2;99;99;99m'

# Line: Usage (amber/orange theme)
USAGE_PRIMARY='\033[38;2;251;191;36m'     # Amber icon
USAGE_LABEL='\033[38;2;217;163;29m'       # Amber label
USAGE_VALUE='\033[38;2;253;224;71m'       # Yellow-gold values
USAGE_RESET='\033[38;2;229;229;229m'      # Match Claude output text

# Line 7: Quote (gold theme)
QUOTE_PRIMARY='\033[38;2;252;211;77m'
QUOTE_AUTHOR='\033[38;2;180;140;60m'

# PAI Branding (matches banner colors)
PAI_P='\033[38;2;30;58;138m'          # Navy
PAI_A='\033[38;2;59;130;246m'         # Medium blue
PAI_I='\033[38;2;147;197;253m'        # Light blue
PAI_LABEL='\033[38;2;229;229;229m'    # Match Claude output text
CC_C1='\033[38;2;217;119;87m'          # Claude terracotta/coral
CC_C2='\033[38;2;191;87;59m'           # Claude darker warm brown
PAI_CITY='\033[38;2;147;197;253m'     # Light blue for city
PAI_STATE='\033[38;2;229;229;229m'    # Match Claude output text
PAI_TIME='\033[38;2;96;165;250m'      # Medium-light blue for time
PAI_WEATHER='\033[38;2;135;206;235m'  # Sky blue for weather
# PAI_SESSION removed — session name no longer displayed

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

# Get gradient color for context bar bucket
# Green(74,222,128) → Yellow(250,204,21) → Orange(251,146,60) → Red(239,68,68)
get_bucket_color() {
    local pos=$1 max=$2
    local pct=$((pos * 100 / max))
    local r g b

    if [ "$pct" -le 33 ]; then
        r=$((74 + (250 - 74) * pct / 33))
        g=$((222 + (204 - 222) * pct / 33))
        b=$((128 + (21 - 128) * pct / 33))
    elif [ "$pct" -le 66 ]; then
        local t=$((pct - 33))
        r=$((250 + (251 - 250) * t / 33))
        g=$((204 + (146 - 204) * t / 33))
        b=$((21 + (60 - 21) * t / 33))
    else
        local t=$((pct - 66))
        r=$((251 + (239 - 251) * t / 34))
        g=$((146 + (68 - 146) * t / 34))
        b=$((60 + (68 - 60) * t / 34))
    fi
    printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
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

# Calculate human-readable time until reset from epoch
format_time_until() {
    local reset_epoch="$1"
    [ -z "$reset_epoch" ] && { echo "—"; return; }
    local now_epoch=$_NOW
    local diff=$((reset_epoch - now_epoch))
    [ "$diff" -le 0 ] && { echo "now"; return; }
    local h=$((diff / 3600)) m=$(((diff % 3600) / 60))
    if [ "$h" -ge 24 ]; then
        local d=$((h / 24)) rh=$((h % 24))
        [ "$rh" -gt 0 ] && echo "${d}d${rh}h" || echo "${d}d"
    elif [ "$h" -gt 0 ]; then
        echo "${h}h${m}m"
    else
        echo "${m}m"
    fi
}

# Convert ISO 8601 timestamp to local clock time (e.g., "15:30" or "15h")
format_clock_time() {
    local ts="$1"
    [ -z "$ts" ] && return
    local minute=$(TZ="$USER_TZ" date -d "$ts" +"%M" 2>/dev/null) || return
    if [ "$minute" = "00" ]; then
        TZ="$USER_TZ" date -d "$ts" +"%-Hh" 2>/dev/null
    else
        TZ="$USER_TZ" date -d "$ts" +"%-H:%M" 2>/dev/null
    fi
}

# Render context bar - gradient progress bar (always 10 buckets)
render_context_bar() {
    local pct=$1
    local output=""
    local filled=$((pct * 10 / 100))
    [ "$filled" -lt 0 ] && filled=0
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if [ "$i" -le "$filled" ]; then
            local pos_pct=$((i * 10))
            if [ "$pos_pct" -ge 90 ]; then output="${output}${SCALE_RED}▅${RESET}"
            elif [ "$pos_pct" -ge 80 ]; then output="${output}${SCALE_ORANGE}▅${RESET}"
            elif [ "$pos_pct" -ge 70 ]; then output="${output}${SCALE_YELLOW}▅${RESET}"
            elif [ "$pos_pct" -ge 50 ]; then output="${output}${SCALE_LIME}▅${RESET}"
            else output="${output}${SCALE_GREEN}▅${RESET}"
            fi
        else
            output="${output}${CTX_BUCKET_EMPTY}▁${RESET}"
        fi
    done
    echo "$output"
}

# ═══════════════════════════════════════════════════════════════════════════════
# LINE 0: PAI BRANDING — moved to MEMORY line; session name removed
# ═══════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════════
# LINE 4: GIT STATUS (tree, stash, sync — no PWD or branch)
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

case "$MODE" in
    nano)
        if [ "$is_git_repo" = true ]; then
            [ -n "$tree_display" ] && printf "${tree_display}"
        fi
        printf "\n"
        ;;
    micro)
        if [ "$is_git_repo" = true ]; then
            [ -n "$tree_display" ] && printf "🌳${tree_display}"
        fi
        printf "\n"
        ;;
    mini)
        if [ "$is_git_repo" = true ]; then
            [ -n "$tree_display" ] && printf "🌳${tree_display}"
        fi
        printf "\n"
        ;;
esac

# Format duration (needed by both PAI and context lines)
duration_sec=$((duration_ms / 1000))
if   [ "$duration_sec" -ge 3600 ]; then time_display="$((duration_sec / 3600))h$((duration_sec % 3600 / 60))m"
elif [ "$duration_sec" -ge 60 ];   then time_display="$((duration_sec / 60))m$((duration_sec % 60))s"
else time_display="${duration_sec}s"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# LINE 6: LEARNING (with sparklines in normal mode)
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
        eval "$(grep '^{' "$RATINGS_FILE" | jq -rs --argjson now "$now" \
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
      (16 as $cap |
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
        # Trend icon/color
        case "$trend" in
            up)   trend_icon="↗"; trend_color="$EMERALD" ;;
            down) trend_icon="↘"; trend_color="$ROSE" ;;
            *)    trend_icon="→"; trend_color="$SLATE_400" ;;
        esac

        # Get colors
        [ "$q15_avg" != "—" ] && pulse_base="$q15_avg" || { [ "$hour_avg" != "—" ] && pulse_base="$hour_avg" || { [ "$today_avg" != "—" ] && pulse_base="$today_avg" || pulse_base="$all_avg"; }; }
        PULSE_COLOR=$(get_rating_color "$pulse_base")
        LATEST_COLOR=$(get_rating_color "${latest:-5}")
        Q15_COLOR=$(get_rating_color "${q15_avg:-5}")
        HOUR_COLOR=$(get_rating_color "${hour_avg:-5}")
        TODAY_COLOR=$(get_rating_color "${today_avg:-5}")
        WEEK_COLOR=$(get_rating_color "${week_avg:-5}")
        MONTH_COLOR=$(get_rating_color "${month_avg:-5}")
        ALL_COLOR=$(get_rating_color "$all_avg")

        [ "$latest_source" = "explicit" ] && src_label="exp" || src_label="imp"

        # Build rating suffix for context line (normal mode)
        rating_suffix=$(printf "⭐${SLATE_300}${ratings_count}${RESET} 🧠${ALL_COLOR}${all_avg}${RESET} %s ✨${LATEST_COLOR}${latest}${RESET} ${SLATE_300}(${src_label})${RESET}" "$all_sparkline")

        case "$MODE" in
            nano)
                printf "${PAI_P}P${PAI_A}A${PAI_I}I${RESET} ${SLATE_500}${PAI_VERSION}${RESET} ${_status_color}${_status_icon}${RESET} ${LATEST_COLOR}${latest}${RESET} ${SIGNAL_PERIOD}1d:${RESET} ${TODAY_COLOR}${today_avg}${RESET}\n"
                ;;
            micro)
                printf "${PAI_P}P${PAI_A}A${PAI_I}I${RESET} ${SLATE_500}${PAI_VERSION}${RESET}${_status_display} ${SLATE_600}│${RESET} ${LATEST_COLOR}${latest}${RESET} ${SIGNAL_PERIOD}1h:${RESET} ${HOUR_COLOR}${hour_avg}${RESET} ${SIGNAL_PERIOD}1d:${RESET} ${TODAY_COLOR}${today_avg}${RESET} ${SIGNAL_PERIOD}1w:${RESET} ${WEEK_COLOR}${week_avg}${RESET}\n"
                ;;
            mini)
                printf "${PAI_P}P${PAI_A}A${PAI_I}I${RESET} ${SLATE_500}${PAI_VERSION}${RESET}${_status_display} ${SLATE_600}│${RESET} "
                printf "${LATEST_COLOR}${latest}${RESET} "
                printf "${SIGNAL_PERIOD}1h:${RESET} ${HOUR_COLOR}${hour_avg}${RESET} "
                printf "${SIGNAL_PERIOD}1d:${RESET} ${TODAY_COLOR}${today_avg}${RESET} "
                printf "${SIGNAL_PERIOD}1w:${RESET} ${WEEK_COLOR}${week_avg}${RESET}\n"
                ;;
            normal)
                ;;
        esac
    fi
fi

# Claude service status indicator
case "${claude_status_indicator:-unknown}" in
    none)     _status_icon="⬤"; _status_color="$TEXT_GREEN" ;;
    minor)    _status_icon="⬤"; _status_color="$TEXT_YELLOW" ;;
    major|critical) _status_icon="⬤"; _status_color="$TEXT_RED" ;;
    *)        _status_icon="◯"; _status_color="$SLATE_600" ;;
esac
_status_display=" ${_status_color}${_status_icon}${RESET} ${SLATE_400}${claude_status_desc:-fetch failed}${RESET}"

# PAI line (always shown in normal mode)
if [ "$MODE" = "normal" ]; then
    dir_name=$(basename "${current_dir:-.}")
    printf "${PAI_P}P${PAI_A}A${PAI_I}I${RESET} ${SLATE_500}${PAI_VERSION}${RESET} ${CC_C1}C${CC_C2}C${RESET} ${SLATE_500}${cc_version}${RESET}${_status_display} ${SLATE_600}│${RESET} ⏳${SLATE_400}${session_time}${RESET} 📍${SLATE_300}${dir_name}${RESET} 🌳${tree_display:-${SLATE_400}no repo${RESET}}\n"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# LINE 1: CONTEXT
# ═══════════════════════════════════════════════════════════════════════════════

# Context display - scale to compaction threshold if configured
context_max="${context_max:-200000}"
max_k=$((context_max / 1000))

# COMPACTION_THRESHOLD already extracted in consolidated settings jq call above

# Get raw percentage from Claude Code
raw_pct="${context_pct%%.*}"  # Remove decimals
[ -z "$raw_pct" ] && raw_pct=0

# Scale percentage: if threshold is 62, then 62% raw = 100% displayed
# Formula: display_pct = (raw_pct * 100) / threshold
if [ "$COMPACTION_THRESHOLD" -lt 100 ] && [ "$COMPACTION_THRESHOLD" -gt 0 ]; then
    display_pct=$((raw_pct * 100 / COMPACTION_THRESHOLD))
    # Cap at 100% (could exceed if past compaction point)
    [ "$display_pct" -gt 100 ] && display_pct=100
else
    display_pct="$raw_pct"
fi

# Color based on scaled percentage (same thresholds work for scaled 0-100%)
if [ "$display_pct" -ge 90 ]; then
    pct_color="$TEXT_RED"
elif [ "$display_pct" -ge 80 ]; then
    pct_color="$TEXT_ORANGE"
elif [ "$display_pct" -ge 70 ]; then
    pct_color="$TEXT_YELLOW"
elif [ "$display_pct" -ge 50 ]; then
    pct_color="$TEXT_LIME"
else
    pct_color="$TEXT_GREEN"
fi

# Context bar + usage are combined on a single line (see usage section below)

# ═══════════════════════════════════════════════════════════════════════════════
# LINE: ACCOUNT USAGE (Claude API limits)
# ═══════════════════════════════════════════════════════════════════════════════
# NOTE: usage_5h, usage_5h_reset populated by PARALLEL PREFETCH

usage_5h_int=${usage_5h%%.*}
[ -z "$usage_5h_int" ] && usage_5h_int=0

# Only show usage line if we have data (token was valid)
if [ "$usage_5h_int" -gt 0 ] || [ -f "$USAGE_CACHE" ]; then
    usage_5h_color=$(get_usage_color "$usage_5h_int")

    # Compute 5h reset time using GNU date (no python3)
    _reset_epoch=$(parse_iso_epoch "$usage_5h_reset")
    reset_5h=$(format_time_until "$_reset_epoch")
    clock_5h=$(format_clock_time "$usage_5h_reset")

    # Reset time: just use clock time directly (no countdown, no parens)
    reset_5h_time="${clock_5h:-${reset_5h}}"

    # Build usage suffix (plain text for length calculation)
    case "$MODE" in
        nano)
            usage_plain="USE: ${usage_5h_int}% │ ${reset_5h_time}"
            usage_fmt="🔋${usage_5h_color}${usage_5h_int}%%${RESET} 🔄${USAGE_RESET}${reset_5h_time}${RESET}"
            ;;
        micro)
            usage_plain="USE: ${usage_5h_int}% │ ${reset_5h_time}"
            usage_fmt="🔋${usage_5h_color}${usage_5h_int}%%${RESET} 🔄${USAGE_RESET}${reset_5h_time}${RESET}"
            ;;
        mini)
            usage_plain="USE: ${usage_5h_int}% │ ${reset_5h_time}"
            usage_fmt="🔋${usage_5h_color}${usage_5h_int}%%${RESET} 🔄${SLATE_500}${reset_5h_time}${RESET}"
            ;;
        normal)
            usage_plain="USE: ${usage_5h_int}% │ ${reset_5h_time}"
            usage_fmt="🔋${usage_5h_color}${usage_5h_int}%%${RESET} 🔄${SLATE_500}${reset_5h_time}${RESET}"
            ;;
    esac

    # Calculate context bar width accounting for all right-side content
    # "Context: " (9) + bar + " XX%" (4) + " │ " usage + " │ " PAI suffix
    usage_plain_len=${#usage_plain}
    # Account for session time prefix (e.g. "1h23m │ " = time_len + 3)
    time_prefix_len=$((${#session_time} + 3))
    case "$MODE" in
        nano|micro) suffix_len=0 ;;
        mini)       suffix_len=7 ;;   # " │ ◇ 0"
        normal)     suffix_len=16 ;;  # " │ Research 0"
    esac
    bar=$(render_context_bar $display_pct)

    # Combined line: Context + Usage + Rating
    case "$MODE" in
        nano)
            printf "⏳${SLATE_400}${session_time}${RESET} 🧮${bar} ${pct_color}${raw_pct}%%${RESET} ${usage_fmt}\n"
            ;;
        micro)
            printf "⏳${SLATE_400}${session_time}${RESET} ${SLATE_600}│${RESET} 🧮${bar} ${pct_color}${raw_pct}%%${RESET} ${usage_fmt}\n"
            ;;
        mini)
            printf "⏳${SLATE_400}${session_time}${RESET} ${SLATE_600}│${RESET} 🧮${bar} ${pct_color}${raw_pct}%%${RESET} ${usage_fmt} ${SLATE_600}│${RESET} ${LEARN_RESEARCH}◇${RESET} ${SLATE_300}${research_count}${RESET}\n"
            ;;
        normal)
            printf "🧮${bar} ${pct_color}${raw_pct}%%${RESET} ${usage_fmt}"
            [ -n "$rating_suffix" ] && printf " ${SLATE_600}│${RESET} ${rating_suffix}"
            printf " ${SLATE_600}│${RESET} 🔎${SLATE_300}${research_count}${RESET}\n"
            ;;
    esac
else
    # No usage data — Context only
    bar=$(render_context_bar $display_pct)

    case "$MODE" in
        nano|micro)
            printf "⏳${SLATE_400}${session_time}${RESET} 🧮${bar} ${pct_color}${raw_pct}%%${RESET}\n"
            ;;
        mini)
            printf "⏳${SLATE_400}${session_time}${RESET} ${SLATE_600}│${RESET} 🧮${bar} ${pct_color}${raw_pct}%%${RESET} ${SLATE_600}│${RESET} ${LEARN_RESEARCH}◇${RESET} ${SLATE_300}${research_count}${RESET}\n"
            ;;
        normal)
            printf "🧮${bar} ${pct_color}${raw_pct}%%${RESET}"
            [ -n "$rating_suffix" ] && printf " ${SLATE_600}│${RESET} ${rating_suffix}"
            printf " ${SLATE_600}│${RESET} 🔎${SLATE_300}${research_count}${RESET}\n"
            ;;
    esac
fi

# ═══════════════════════════════════════════════════════════════════════════════
# LINE 7: QUOTE (normal mode only)
# ═══════════════════════════════════════════════════════════════════════════════

# DISABLED: external API (zenquotes.io)
if false && [ "$MODE" = "normal" ]; then
    printf '\033[2;38;2;136;136;136m'; printf '─%.0s' $(seq 1 "$term_width"); printf '\033[0m\n'

    # Quote was prefetched in parallel block — just read the cache
    if [ -f "$QUOTE_CACHE" ]; then
        IFS='|' read -r quote_text quote_author < "$QUOTE_CACHE"
        author_suffix="\" —${quote_author}"
        author_len=${#author_suffix}
        quote_len=${#quote_text}
        max_line=72

        # Full display: ✦ "quote text" —Author
        full_len=$((quote_len + author_len + 4))  # 4 for ✦ "

        if [ "$full_len" -le "$max_line" ]; then
            # Fits on one line
            printf "${QUOTE_PRIMARY}✦${RESET} ${SLATE_400}\"${quote_text}\"${RESET} ${QUOTE_AUTHOR}—${quote_author}${RESET}\n"
        else
            # Need to wrap - target ~10 words (55-60 chars) on first line
            # Line 1 gets: "✦ \"" (4) + text
            line1_text_max=60  # ~10 words worth

            # Only wrap if there's substantial content left for line 2
            min_line2=12

            # Target: put ~60 chars on line 1
            target_line1=$line1_text_max
            [ "$target_line1" -gt "$quote_len" ] && target_line1=$((quote_len - min_line2))

            # Find word boundary near target
            first_part="${quote_text:0:$target_line1}"
            remaining="${quote_text:$target_line1}"

            # If we're not at a space, find the last space in first_part
            if [ -n "$remaining" ] && [ "${remaining:0:1}" != " " ]; then
                # Find last space position
                temp="$first_part"
                last_space_pos=0
                pos=0
                while [ $pos -lt ${#temp} ]; do
                    [ "${temp:$pos:1}" = " " ] && last_space_pos=$pos
                    pos=$((pos + 1))
                done
                if [ $last_space_pos -gt 10 ]; then
                    first_part="${quote_text:0:$last_space_pos}"
                fi
            fi

            second_part="${quote_text:${#first_part}}"
            second_part="${second_part# }"  # trim leading space

            # Only wrap if second part is substantial (more than just a few words)
            if [ ${#second_part} -lt 10 ]; then
                # Too little for line 2, just print on one line (may overflow slightly)
                printf "${QUOTE_PRIMARY}✦${RESET} ${SLATE_400}\"${quote_text}\"${RESET} ${QUOTE_AUTHOR}—${quote_author}${RESET}\n"
            else
                printf "${QUOTE_PRIMARY}✦${RESET} ${SLATE_400}\"${first_part}${RESET}\n"
                printf "  ${SLATE_400}${second_part}\"${RESET} ${QUOTE_AUTHOR}—${quote_author}${RESET}\n"
            fi
        fi
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
        # Usage API refresh
        _usage_age=999999
        [ -f "$USAGE_CACHE" ] && _usage_age=$(($(date +%s) - $(get_mtime "$USAGE_CACHE")))
        if [ "$_usage_age" -gt "$USAGE_CACHE_TTL" ]; then
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
                _s_desc=$(echo "$_status_body" | jq -r '.status.description // "fetch failed" | ascii_downcase | if . == "all systems operational" then "ok" else . end')
                printf "claude_status_indicator='%s'\nclaude_status_desc='%s'\n" "$_s_ind" "$_s_desc" > "$PAI_DIR/MEMORY/STATE/status-cache.sh"
            fi
        fi

        rm -f "$_bg_lock" 2>/dev/null
    ) &
    disown 2>/dev/null
fi
