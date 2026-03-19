# PAI statusline

Dense 2-line personal statusline for [PAI](https://github.com/danielmiessler/pai), using [Claude Code](https://claude.com/product/claude-code).

![PAI statusline screenshot](screenshot.png)

## What it shows

| Section | Symbol | Example | Info |
|---------|--------|---------|------|
| Identity | <span style="color:rgb(30,58,138)">P</span><span style="color:rgb(59,130,246)">A</span><span style="color:rgb(147,197,253)">I</span> | 4.0.3 | PAI version |
| | <span style="color:rgb(217,119,87)">C</span><span style="color:rgb(191,87,59)">C</span> | 2.1.70 | Claude Code version |
| | <span style="color:rgb(70,175,95)">⬤</span> | ok | Claude Code status |
| Session | ⏳ | 1h23m | Session time |
| | 📍 | myproject | Starting directory |
| | 🌳 | <span style="color:rgb(74,222,128)">clean</span> | Git tree state |
| Usage | 🧮 | <span style="color:rgb(70,175,95)">▅▅▅▅</span><span style="color:rgb(150,190,40)">▅▅</span><span style="color:rgb(255,193,7)">▅</span><span style="color:rgb(99,99,99)">▁▁▁</span> <span style="color:rgb(255,193,7)">72%</span> | Context bar + % |
| | 🔋 | <span style="color:rgb(150,190,40)">65%</span> | 5-hour utilization % |
| | 🔄 | 19h | Reset time (clock hour) |
| Learning | 🧠 | <span style="color:rgb(150,190,40)">7.1</span> <span style="color:rgb(150,190,40)">▄</span><span style="color:rgb(255,193,7)">▃</span><span style="color:rgb(150,190,40)">▄</span><span style="color:rgb(70,175,95)">▅</span><span style="color:rgb(255,193,7)">▃</span><span style="color:rgb(150,190,40)">▄▄</span><span style="color:rgb(255,193,7)">▃</span><span style="color:rgb(70,175,95)">▅</span><span style="color:rgb(150,190,40)">▄</span> | Average rating + ratings bar (last 10) |
| | ✨ | <span style="color:rgb(150,190,40)">8</span> (exp) | Last rating |
| | ⭐ | 12 | Ratings count |

## Density tiers

Adapts to terminal width automatically, picking the largest tier that fits:

| Tier | Statusline |
|------|------------|
| **full** | <span style="color:rgb(30,58,138)">P</span><span style="color:rgb(59,130,246)">A</span><span style="color:rgb(147,197,253)">I</span> 4.0.3 &ensp; <span style="color:rgb(217,119,87)">C</span><span style="color:rgb(191,87,59)">C</span> 2.1.70 &ensp; <span style="color:rgb(70,175,95)">⬤</span> ok &ensp; │ &ensp; ⏳ 1h23m &ensp; 📍 myproject &ensp; 🌳 <span style="color:rgb(74,222,128)">clean</span><br>🧮 <span style="color:rgb(70,175,95)">▅▅▅▅</span><span style="color:rgb(150,190,40)">▅▅</span><span style="color:rgb(255,193,7)">▅</span><span style="color:rgb(99,99,99)">▁▁▁</span> <span style="color:rgb(255,193,7)">72%</span> &ensp; 🔋 <span style="color:rgb(150,190,40)">65%</span> &ensp; 🔄 19h &ensp; │ &ensp; 🧠 <span style="color:rgb(150,190,40)">7.1</span> <span style="color:rgb(150,190,40)">▄</span><span style="color:rgb(255,193,7)">▃</span><span style="color:rgb(150,190,40)">▄</span><span style="color:rgb(70,175,95)">▅</span><span style="color:rgb(255,193,7)">▃</span><span style="color:rgb(150,190,40)">▄▄</span><span style="color:rgb(255,193,7)">▃</span><span style="color:rgb(70,175,95)">▅</span><span style="color:rgb(150,190,40)">▄</span> &ensp; ✨ <span style="color:rgb(150,190,40)">8</span> (exp) &ensp; ⭐ 12 |
| **dense** | <span style="color:rgb(30,58,138)">P</span><span style="color:rgb(59,130,246)">A</span><span style="color:rgb(147,197,253)">I</span>/<span style="color:rgb(217,119,87)">C</span><span style="color:rgb(191,87,59)">C</span> &ensp; <span style="color:rgb(70,175,95)">⬤</span> ok &ensp; │ &ensp; ⏳ 1h23m &ensp; 🌳 <span style="color:rgb(74,222,128)">clean</span><br>🧮 <span style="color:rgb(255,193,7)">72%</span> &ensp; 🔋 <span style="color:rgb(150,190,40)">65%</span> &ensp; 🔄 19h &ensp; │ &ensp; 🧠 <span style="color:rgb(150,190,40)">7.1</span> &ensp; ✨ <span style="color:rgb(150,190,40)">8</span> &ensp; ⭐ 12 |
| **ultradense** | <span style="color:rgb(217,119,87)">C</span><span style="color:rgb(191,87,59)">C</span> &ensp; <span style="color:rgb(70,175,95)">⬤</span> ok &ensp; │ &ensp; 🌳 <span style="color:rgb(74,222,128)">clean</span><br>🧮 <span style="color:rgb(255,193,7)">72%</span> &ensp; 🔋 <span style="color:rgb(150,190,40)">65%</span> &ensp; │ &ensp; 🧠 <span style="color:rgb(150,190,40)">7.1</span> |

## Installation via PAI (recommended)

In any PAI session, say:

> Install codeberg.org/ljubitje/pai-statusline

PAI will clone the repo, read the setup instructions, and handle the rest.

## Installation via manual labour

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

## Update

In any PAI session, say:

> Update statusline from codeberg.org/ljubitje/pai-statusline

## Configuration

The statusline reads configuration from `settings.json`:

| Key | Default | Description |
|-----|---------|-------------|
| `contextDisplay.compactionThreshold` | `100` | Scale context bar so this % = 100%. Set to `62` if your compaction triggers at 62%. |
| `principal.timezone` | `UTC` | Your timezone for reset time display (e.g., `America/New_York`) |
| `pai.version` | `--` | PAI version string |
| `counts.ratings` | `0` | Total ratings count (populated by PAI stop hooks) |

## How it works

The script receives JSON from Claude Code via stdin containing session data (context window, model, tokens, etc.). It then:

1. Parses settings + input JSON in two `jq` calls (all data extracted upfront)
2. Launches git status in a background subshell
3. Sources pre-built `.sh` caches for usage and service status (instant, no parsing)
4. Detects terminal width and picks the largest density that fits (full → dense → ultradense)
5. Renders four sections: Identity, Session, Usage, Learning
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
