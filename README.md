# PAI statusline

Dense 2-line personal statusline for [PAI](https://github.com/danielmiessler/pai), using [Claude Code](https://claude.com/product/claude-code).

![PAI statusline screenshot](screenshot.png)

## What it shows

| Section | Symbol | Example | Info |
|---------|--------|---------|------|
| Header | <span style="color:rgb(30,58,138)">P</span><span style="color:rgb(59,130,246)">A</span><span style="color:rgb(147,197,253)">I</span> | 4.0.3 | PAI version |
| | <span style="color:rgb(217,119,87)">C</span><span style="color:rgb(191,87,59)">C</span> | 2.1.70 | Claude Code version |
| | <span style="color:rgb(70,175,95)">⬤</span> | ok | Claude Code service status |
| | ⏳ | 1h23m | Session wall-clock time |
| | 📍 | myproject | Current directory |
| | 🌳 | <span style="color:rgb(74,222,128)">clean</span> | Git tree state (clean/staged/unstaged/untracked) |
| Context | 🧮 | <span style="color:rgb(70,175,95)">▅▅▅▅</span><span style="color:rgb(99,99,99)">▁▁▁▁▁▁</span> <span style="color:rgb(70,175,95)">42%</span> | Context window usage |
| Usage | 🔋 | <span style="color:rgb(150,190,40)">65%</span> | 5-hour utilization |
| | 🔄 | 15:30 | Reset time (local clock) |
| Learning | ⭐ | 12 | Total ratings count |
| | 🧠 | <span style="color:rgb(150,190,40)">7.1</span> | All-time average |
| | | <span style="color:rgb(150,190,40)">▄</span><span style="color:rgb(255,193,7)">▃</span><span style="color:rgb(150,190,40)">▄</span><span style="color:rgb(70,175,95)">▅</span><span style="color:rgb(255,193,7)">▃</span><span style="color:rgb(150,190,40)">▄▄</span><span style="color:rgb(255,193,7)">▃</span><span style="color:rgb(70,175,95)">▅</span><span style="color:rgb(150,190,40)">▄</span><span style="color:rgb(255,193,7)">▃</span><span style="color:rgb(150,190,40)">▄</span><span style="color:rgb(235,130,45)">▂</span><span style="color:rgb(255,193,7)">▃</span><span style="color:rgb(150,190,40)">▄▄</span> | Rating sparkline (last 16) |
| | ✨ | <span style="color:rgb(150,190,40)">8</span> (exp) | Latest rating + source |
| | 🔎 | 3 | Research count |

## Responsive modes

Adapts to terminal width automatically:

| Mode | Width | Description |
|------|-------|-------------|
| `nano` | <35 cols | Minimal single-line essentials |
| `micro` | 35-54 | Compact with key metrics |
| `mini` | 55-79 | Balanced information density |
| `normal` | 80+ | Full display with sparklines |

## Installation

### Via PAI (recommended)

In any PAI session, say:

> Install codeberg.org/ljubitje/pai-statusline

PAI will clone the repo, read the setup instructions, and handle the rest.

### Manual

1. Copy the script:

```bash
cp statusline-command.sh $PAI_DIR/statusline-command.sh
chmod +x $PAI_DIR/statusline-command.sh
```

2. Add to `settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "$PAI_DIR/statusline-command.sh"
  }
}
```

3. Restart PAI/CC.

## Configuration

The statusline reads configuration from `settings.json`:

| Key | Default | Description |
|-----|---------|-------------|
| `contextDisplay.compactionThreshold` | `100` | Scale context bar so this % = 100%. Set to `62` if your compaction triggers at 62%. |
| `principal.timezone` | `UTC` | Your timezone for reset time display (e.g., `America/New_York`) |
| `daidentity.name` | `Assistant` | Your AI assistant's display name |
| `pai.version` | `--` | PAI version string |
| `counts.*` | `0` | Counts for skills, workflows, hooks, signals, etc. (populated by PAI stop hooks) |

## How it works

The script receives JSON from Claude Code via stdin containing session data (context window, model, tokens, etc.). It then:

1. Parses settings + input JSON in two `jq` calls (all data extracted upfront)
2. Launches git status in a background subshell
3. Sources pre-built `.sh` caches for usage and service status (instant, no parsing)
4. Detects terminal width (Kitty IPC > TTY > tput > cache > env)
5. Renders each section according to the responsive mode
6. Fire-and-forget: refreshes usage/status caches in background for next render

Typical render time: ~100ms.

## Dependencies

- `bash` (4.0+)
- `jq` (JSON processing)
- `date` (GNU coreutils, for timezone/time calculations)
- `git` (optional, for git status info)
- `curl` (for Claude Code service status + usage API)

## License

[AGPL-3.0](LICENSE)
