# PAI statusline

Dense personal statusline for **[PAI 5.0](https://github.com/danielmiessler/Personal_AI_Infrastructure)**, using [Claude Code](https://claude.com/product/claude-code). Renders identity + session on line 1, usage on line 2, and an optional learning + Telos-state row on line 3. A quote row is also available behind a flag.

> Built for the PAI 5.0 path layout: `CLAUDE_HOME` (`$HOME/.claude`) holds Claude-Code–managed files; `PAI_DIR` (`$CLAUDE_HOME/PAI`) holds PAI assets — including this script. Pre-5.0 layouts are not supported; see git history for the legacy script.

<img src="screenshot.png" alt="PAI statusline screenshot" width="810">

> ⚠️ Screenshots in this README are auto-generated (chromium headless render via Noto Color Emoji) — emoji aesthetics differ from a real terminal. Real terminal captures coming once the dev wakes up.

## What it shows

| Section | Symbol | Example | Info |
|---------|--------|---------|------|
| Identity | <span style="color:rgb(30,58,138)">P</span><span style="color:rgb(59,130,246)">A</span><span style="color:rgb(147,197,253)">I</span> | 5.0.0 | PAI version (hidden if latest, outdated segments dimmed) |
| | <span style="color:rgb(217,119,87)">C</span><span style="color:rgb(191,87,59)">C</span> | 2.1.<span style="color:rgb(99,99,99)">121</span> | Claude Code version (hidden if latest, outdated segments dimmed) |
| | <span style="color:rgb(70,175,95)">⬤</span> | ok | Claude Code service status |
| Thinking (line 1 left) | 💡 | 4h2m | All-time total thinking time across all sessions (model-busy wall-clock — API roundtrip + tool latency + extended thinking + token gen). On by default; opt-out with `statusline.showThinkingTime: false` |
| Session wall-clock (line 1 left) | ⏳ | 1h23m | Session wall-clock time. **Hidden by default**, opt-in with `SHOW_TIME=1` |
| Session | 📍 | myproject | Starting directory (locked at session start) |
| | 🌳 | <span style="color:rgb(74,222,128)">clean</span> | Git tree state (clean / staged / unstaged / untracked) |
| | 📂 / ✏️ | <span style="color:rgb(150,190,40)">3</span>r <span style="color:rgb(255,193,7)">2</span>w ↳ file.ts | Read / Edit+Write tool calls since the last user prompt; ↳ = last touched file (↗ if outside cwd) |
| Usage | 🌑🌘🌗🌖🌕 | <span style="color:rgb(255,193,7)">65%</span> | Context moon phase + % (fills as context grows) |
| | 🔋 | <span style="color:rgb(150,190,40)">97%</span> | 5-hour budget remaining % |
| | 🔄 | 4h50m | Time to reset (countdown) |
| | 🗓️ | 6d | Days (or hours, if <24h) until 7-day budget reset (Claude Code ≥2.1.x with native rate_limits) |
| Thinking (line 2 left) | ⏳ | 14m | Current-session thinking time — model-busy wall-clock for this session only |
| Learning | 🧠 | <span style="color:rgb(150,190,40)">7.1</span> <span style="color:rgb(150,190,40)">▄</span><span style="color:rgb(255,193,7)">▃</span><span style="color:rgb(150,190,40)">▄</span><span style="color:rgb(70,175,95)">▅</span><span style="color:rgb(150,190,40)">▄</span> | Average rating + sparkbar of last 5 ratings |
| | ✨ | <span style="color:rgb(150,190,40)">8</span>i | Last rating (i=implicit, e=explicit) |
| | ⭐/🌟 | 12 | Ratings count (🌟 if rated in last hour) |
| State | <span style="color:rgb(56,189,248)">❤️</span> <span style="color:rgb(147,197,253)">🪄</span> <span style="color:rgb(59,130,246)">🕊️</span> <span style="color:rgb(96,165,250)">🫂</span> <span style="color:rgb(37,99,235)">🪙</span> | 68% 31% 78% 84% 42% | Telos dimensions from `$PAI_DIR/USER/TELOS/PAI_STATE.json` — Health, Creative, Freedom, Relationships, Money. Missing dims render as `—` |
| Quote | "…" — | "Strive not to be a success…" —Albert Einstein | Off by default. Opt-in via `statusline.showQuote: true` in `~/.claude/settings.json`; sourced from `$PAI_DIR/.quote-cache` (ZenQuotes refresh) |

## Automatic resizing

The statusline adapts to your terminal width, picking the largest statusline that fits:

**full**<br>
<img src="tier-full.png" alt="full density" width="645">

**dense**<br>
<img src="tier-dense.png" alt="dense density" width="645">

**ultradense**<br>
<img src="tier-ultradense.png" alt="ultradense density" width="645">

## Installation via PAI (recommended)

In any PAI session, say:

> Install codeberg.org/ljubitje/pai-statusline

PAI will clone the repo, read the setup instructions, and handle the rest.

## Installation via manual labour

The statusline script lives under `$PAI_DIR` (default `$HOME/.claude/PAI`) — alongside the rest of your PAI-shipped assets. `$HOME/.claude` (`CLAUDE_HOME`) holds only Claude-Code–managed files (`settings.json`, `hooks/`).

1. Copy the script:

```bash
mkdir -p "${PAI_DIR:-$HOME/.claude/PAI}"
cp statusline-command.sh "${PAI_DIR:-$HOME/.claude/PAI}/statusline-command.sh"
chmod +x "${PAI_DIR:-$HOME/.claude/PAI}/statusline-command.sh"
```

2. Add to `~/.claude/settings.json` (create the file with `{}` if it doesn't exist). Use the absolute path that `${PAI_DIR:-$HOME/.claude/PAI}` resolves to on your system — Claude Code does not expand env vars in this field:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/absolute/path/to/PAI/statusline-command.sh"
  }
}
```

3. Add the auto-update hook to `~/.claude/settings.json` under `hooks.SessionStart`. The hook command runs in a shell, so `$PAI_DIR` does expand here:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "curl -fsS --retry 3 --retry-delay 2 --retry-all-errors --connect-timeout 5 --max-time 15 -o \"${PAI_DIR:-$HOME/.claude/PAI}/statusline-command.sh\" \"https://codeberg.org/ljubitje/pai-statusline/raw/branch/main/statusline-command.sh?t=$(date +%s)\" && chmod +x \"${PAI_DIR:-$HOME/.claude/PAI}/statusline-command.sh\" || { echo \"[statusline] codeberg fetch FAILED after 3 retries — update flow may be broken; using cached statusline\" >&2; echo \"$(date -Iseconds) statusline fetch failed\" >> \"${PAI_DIR:-$HOME/.claude/PAI}/MEMORY/STATE/statusline-fetch-failures.log\"; exit 1; }"
          }
        ]
      }
    ]
  }
}
```

This downloads the latest version on every session start. The `?t=` cache-buster bypasses Codeberg's CDN cache (5-min TTL). Each fetch has a 5-second connect timeout and a 15-second total cap, and **retries up to 3 times** (2s apart, `--retry-all-errors`) to ride out transient Codeberg latency spikes.

It does **not** fail silently. If all retries are exhausted, the hook prints a clear error to stderr, appends a timestamped line to `$PAI_DIR/MEMORY/STATE/statusline-fetch-failures.log`, and exits non-zero — so a genuinely broken update flow surfaces as a visible session-start hook error instead of rotting unnoticed. The previously-cached `statusline-command.sh` keeps rendering in the meantime, so a failed fetch never breaks your statusline.

## Auto-update

The statusline auto-updates only on **session start**, via the `SessionStart` hook above. There is no mid-session background polling — existing long-running sessions keep the version they started with. To pull a fresh version into a running session, restart Claude Code.

To update manually in any PAI session, say:

> Update statusline from codeberg.org/ljubitje/pai-statusline

## Configuration

The statusline reads configuration from `settings.json`:

| Key | Default | Description |
|-----|---------|-------------|
| `contextDisplay.compactionThreshold` | `100` | Scale context % so this threshold = 100%. Set to `62` if your compaction triggers at 62%. |
| `principal.timezone` | `UTC` | Your timezone for reset time display (e.g., `America/New_York`) |
| `pai.version` | `--` | PAI version string |
| `counts.ratings` | `0` | Total ratings count (populated by PAI stop hooks) |
| `statusline.showThinkingTime` | `true` | Show 💡 (all-time) and ⏳ (session) thinking-time segments. Set to `false` to disable both. |
| `statusline.showQuote` | `false` | Render an extra row with the quote from `$PAI_DIR/.quote-cache`. |

### PAI v5.0 path layout

The statusline follows the PAI v5.0 split between Claude-Code–managed files and PAI-shipped files:

| Variable | Default | Holds |
|----------|---------|-------|
| `CLAUDE_HOME` | `$HOME/.claude` | `settings.json`, `hooks/` — Claude-Code–managed only |
| `PAI_DIR` | `$CLAUDE_HOME/PAI` | `MEMORY/`, `USER/`, `ALGORITHM/`, **`statusline-command.sh`**, and other PAI assets |

The statusline script is a PAI-shipped, PAI-updated asset, so it lives under `PAI_DIR` alongside the rest. Both vars can be overridden via env. Pre-5.0 layouts (everything directly under `$HOME/.claude`) are not supported by this version — see git history for the legacy script.

### Telos state file

If you populate `$PAI_DIR/USER/TELOS/PAI_STATE.json` with dimension percentages, the statusline renders a STATE row showing your distance from ideal across HEALTH / CREATIVE / FREEDOM / RELATIONSHIPS / MONEY. Missing dimensions render as `—`. Run `/interview` (Phase 2) in PAI to populate.

## How it works

The script receives JSON from Claude Code via stdin containing session data (context window, model, tokens, etc.). It then:

1. Parses settings + input JSON in two `jq` calls (all data extracted upfront — including the native `.rate_limits` block when CC ≥2.1.x injects it, skipping the OAuth API call entirely)
2. Launches git rev-parse / branch / last-commit in a background subshell
3. Sources pre-built `.sh` caches for usage and service status (instant, no parsing)
4. Caches per-render heavy work (files block, session thinking-time) by `(session_id, transcript_size)` — append-only JSONL means same size ⇒ same content ⇒ same value, so warm renders skip the jq pass entirely
5. Detects terminal width and picks the largest density that fits (full → dense → ultradense)
6. Renders core sections (Identity, Session, Usage, Learning) plus optional rows (State, Quote) when their source data exists
7. Fire-and-forget: refreshes usage / service status / version caches in background for next render — gated to skip when native rate_limits already supplied the data

Typical render time: ~165 ms warm path on a multi-MB transcript; ratings-recompute spike (every 30 s while ratings change) is the remaining cold cost. See `IMPROVE.md` for the queued performance candidates and their trade-offs.

## Dependencies

- `bash` (4.0+)
- `jq` (JSON processing)
- `date` (GNU coreutils, for timezone/time calculations)
- `git` (optional, for git status info)
- `curl` (for Claude Code service status + usage API)

## License

[AGPL-3.0](LICENSE)
