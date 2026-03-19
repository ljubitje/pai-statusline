# PAI statusline

Dense personal statusline for [PAI](https://github.com/danielmiessler/pai), using [Claude Code](https://claude.com/product/claude-code).

## What it shows

| Section | Info |
|---------|------|
| **Header** | PAI version, Claude Code version, Claude service status, session time, directory, git tree state |
| **Git** | Stash count, ahead/behind remote |
| **Learning** | Rating sparklines, averages (15m/1h/1d/1w/1m/all-time), trend direction |
| **Context** | Gradient progress bar, raw percentage, compaction threshold scaling |
| **Usage** | 5-hour utilization %, reset time, extra credits |

## Responsive modes

Adapts to terminal width automatically:

| Mode | Width | Description |
|------|-------|-------------|
| `nano` | <35 cols | Minimal single-line essentials |
| `micro` | 35-54 | Compact with key metrics |
| `mini` | 55-79 | Balanced information density |
| `normal` | 80+ | Full display with sparklines |

## Dependencies

- `bash` (4.0+)
- `jq` (JSON processing)
- `python3` (timezone/time calculations)
- `git` (optional, for git status info)
- `curl` (for Claude service status + usage API)

## Installation

### Via PAI / Claude Code

In any PAI/CC session, say:

> Install codeberg.org/ljubitje/pai-statusline

PAI/CC will clone the repo, read the setup instructions, and handle the rest.

### Manual

1. Copy the script to your Claude Code config directory:

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

2. Add the statusline config to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "$HOME/.claude/statusline-command.sh"
  }
}
```

If you have a `PAI_DIR` environment variable set, use that path instead:

```json
{
  "statusLine": {
    "type": "command",
    "command": "$PAI_DIR/statusline-command.sh"
  }
}
```

3. Restart Claude Code. The statusline appears at the bottom of your terminal.

## Configuration

The statusline reads configuration from `settings.json`:

| Key | Default | Description |
|-----|---------|-------------|
| `contextDisplay.compactionThreshold` | `100` | Scale context bar so this % = 100%. Set to `62` if your compaction triggers at 62%. |
| `principal.timezone` | `UTC` | Your timezone for reset time display (e.g., `America/New_York`) |
| `daidentity.name` | `Assistant` | Your AI assistant's display name |
| `pai.version` | `--` | PAI version string |
| `counts.*` | `0` | Counts for skills, workflows, hooks, signals, etc. (populated by PAI stop hooks) |

### PAI-specific features

Some features require the broader PAI infrastructure:

- **Learning signals & sparklines** -- requires `ratings.jsonl` from PAI's learning system
- **Counts** (skills, workflows, hooks) -- populated by PAI's stop hooks
- **DA identity** -- reads from PAI's `daidentity` config

Without PAI, these sections gracefully show defaults or are skipped.

## How it works

The script receives JSON from Claude Code via stdin containing session data (context window, model, tokens, etc.). It then:

1. Parses the input JSON in a single `jq` call
2. Launches parallel background jobs for git, counts, usage API, and service status
3. Detects terminal width (Kitty IPC > TTY > tput > cache > env)
4. Renders each section according to the responsive mode

Total render time target: <200ms.

## License

[AGPL-3.0](LICENSE)
