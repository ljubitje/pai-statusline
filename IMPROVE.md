# Statusline Performance — Remaining Improvements

Baseline before any work: **256 ms** warm path. After harmless wins applied: **165 ms** warm. Cold spike (every 30 s while active): **~640 ms** from learning compute.

Already applied (in `statusline-command.sh`):

- Files block cache by `(session_id, transcript_size)` — eliminated ~50 ms warm.
- Porcelain detection: 3 × `grep -q` → 1 × `awk` — saved ~15 ms.
- `cat`/`basename` → bash builtin `read` / `${var##*/}` in startdir + session blocks — saved ~12 ms.
- Thinking session cache by `(session_id, transcript_size)` (replaced TTL=5 s) — saved ~30 ms warm, plus self-migrating from old cache format.
- Pipe before `PAI` in line 1 removed (cosmetic, separate change).
- Thought-balloon emoji replaced with light-bulb (💡) for thinking-time display.

---

## Remaining options

| # | Fix | Impact | Risk profile | Trade-off |
|---|---|---|---|---|
| 1 | Learning async pre-warm (background refresh, statusline reads cache only) | -640 ms cold spike (every 30 s) | LOW | One render after a new rating shows the previous average; sparkline barely shifts for a single point. |
| 2 | Width detection: lift `$_width_cache` to top of detection chain | -40 ms every warm render | LOW | After terminal resize, new width shows up only after cache TTL (~5–10 s). |
| 3 | Top two `jq` calls merged into one (`jq -r --rawfile s "$SETTINGS_FILE" '($s \| fromjson? // {}) as $settings \| ...'`) | -10–15 ms every render | VERY LOW | If main `$input` is malformed JSON, all fields default (currently only settings would default, input parses independently). In practice CC always sends valid JSON. |
| 4 | `$EPOCHSECONDS` instead of `date +%s` for `_NOW` | -5 ms every render | NONE on bash ≥ 5 (NixOS has it) | bash 4 doesn't expose it; if cross-platform support to old bash is needed, gate with version check. |
| 5 | Combine `SESSION_STARTDIR_FILE` + `SESSION_START_FILE` into one `SESSION_INIT_FILE` (two lines) | -5–10 ms every render | LOW with migration shim, ONE-TIME otherwise | In-flight session at upgrade moment loses accurate `session_time` for one render unless we read the old files when the combined file is missing and write the migrated values. |
| 6 | All-time thinking cache by `THINKING_DIR` mtime instead of TTL=60 s | -5 ms occasionally (when TTL would otherwise expire) | NONE | Pure refactor, identical computed value. Tiny win — keep as low-priority drive-by. |
| 7 | Learning incremental compute (only process new lines in `ratings.jsonl`, maintain running totals + sparkline buckets) | 640 ms → ~50 ms on cold | MEDIUM | Bigger refactor of the jq pipeline. Mutually exclusive with #1 and #8 (same target, different mechanism). |
| 8 | Pre-aggregate ratings into `ratings-summary.json` via a hook handler that runs on rating append; statusline just reads the summary | 640 ms → ~5 ms on cold | MEDIUM (touches `hooks/`) | Cleanest long-term architecture. Mutually exclusive with #1 and #7. |

---

## Decision for the learning spike

#1, #7, #8 all target the same 640 ms learning compute. **Pick exactly one** before implementing — combining wastes effort because only one path executes at runtime.

- Pick **#1** if minimum diff matters and we're OK with the existing heavy `jq` logic continuing to run, just off the render path.
- Pick **#7** if we want statusline to remain self-contained but want the `jq` work itself to scale better as ratings grow.
- Pick **#8** if we accept touching `hooks/` for the cleanest division of labor: producers maintain summary, consumers (statusline, anything else) just read.

---

## Suggested batch when revisiting

Best ROI in one pass, no learning-strategy decision required: **#2 + #4 + #6**. Combined estimate: ~50 ms shaved off every warm render with negligible risk. After that batch, warm path projection: ~115 ms (-55 % vs baseline).

Then pick a learning strategy (#1 / #7 / #8) and apply on its own commit.

#3 and #5 are marginal; pick up only if doing nearby cleanup.
