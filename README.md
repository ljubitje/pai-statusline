# PAI statusline

Dense 2-line personal statusline for [PAI](https://github.com/danielmiessler/pai), using [Claude Code](https://claude.com/product/claude-code).

## What it shows

| Section | Symbol | Example | Info |
|---------|--------|---------|------|
| Header | PAI | `4.0.3` | PAI version |
| | CC | `1.0.32` | Claude Code version |
| | ⬤ | `ok` | Claude Code service status |
| | ⏳ | `1h23m` | Session wall-clock time |
| | 📍 | `myproject` | Current directory |
| | 🌳 | `clean` | Git tree state (clean/staged/unstaged/untracked) |
| Git | Stash: | `2` | Git stash count |
| | Sync: | `↑2↓1` | Commits ahead/behind remote |
| Context | 🧮 | `▅▅▅▅▁▁▁▁▁▁ 42%` | Gradient context bar + percentage |
| Usage | 🔋 | `65%` | 5-hour utilization |
| | 🔄 | `15:30` | Usage reset time (local clock) |
| | E: | `$2/$100` | Extra credits used/limit |
| Learning | ⭐ | `12` | Total ratings count |
| | 🧠 | `7.1` | All-time average + sparkline |
| | ✨ | `8 (exp)` | Latest rating + source |
| | 🔎 | `3` | Research count |

## Responsive modes

Adapts to terminal width automatically:

| Mode | Width | Description |
|------|-------|-------------|
| `nano` | <35 cols | Minimal single-line essentials |
| `micro` | 35-54 | Compact with key metrics |
| `mini` | 55-79 | Balanced information density |
| `normal` | 80+ | Full display with sparklines |

## Installation

### Via PAI

In any PAI session, say:

> Install codeberg.org/ljubitje/pai-statusline

PAI/CC will clone the repo, read the setup instructions, and handle the rest.

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

1. Parses the input JSON in a single `jq` call
2. Launches parallel background jobs for git, counts, usage API, and service status
3. Detects terminal width (Kitty IPC > TTY > tput > cache > env)
4. Renders each section according to the responsive mode

Total render time target: <200ms.

## Dependencies

- `bash` (4.0+)
- `jq` (JSON processing)
- `python3` (timezone/time calculations)
- `git` (optional, for git status info)
- `curl` (for Claude Code service status + usage API)

## License

[AGPL-3.0](LICENSE)
