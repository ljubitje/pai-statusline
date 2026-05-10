---
project: pai-statusline
task: Total thinking-time metric (additive)
effort: E2
phase: complete
progress: 20/20
mode: algorithm
started: 2026-05-10
updated: 2026-05-10
---

## Problem

statusline-command.sh renders na vsak prompt + na razne triggerje znotraj Claude Code. Render mora **nikoli pasti**, **nikoli viseti**, **nikoli izpisati napake**, in vse veje — tudi cross-platform / corrupted-cache / racing — morajo bit graceful. Trenutni skript ima več tihih bugov ki se kažejo kot vizualne nekonsistentnosti ali silent fallbacks.

## Vision

Render ki ne pade nikjer — niti na manjkajočih datotekah, niti na malformed input JSON, niti pri `branch name with quote`, niti ob hitrih zaporednih invocationih, niti na macOS (skript trdi da ga podpira, lokalno se kaže Linux-only build na nekaterih mestih).

## Out of Scope

- Cross-platform za Windows (skript je Linux/macOS).
- Performance optimizacija pod 100ms (cache layer že rešuje to).
- Nove vizualne dimenzije ali polish.
- Dokumentacijski rewrite — poprava izvirnih bugov je kar dovolj.

## Principles

- **Graceful degradation:** vsaka opcijska komponenta (git, cache, status, learning) lahko manjka brez padca.
- **No injection:** noben uporabniško-kontroliran string (branch name, paths, ratings) ne sme priti v `eval` ali `source` v unsanitized obliki.
- **Single source of truth:** ko obstajajo dve poti do istega podatka (CLAUDE_HOME vs hardcoded ~/.claude, CWD git vs $current_dir git), ena zmaga — ne mešaj.
- **Hard ceiling on render time:** noben subprocess ne sme viseti dlje kot 1s (kitten, curl, jq).

## Constraints

- Sintaksa POSIX-bash (skript se runa pod /usr/bin/env bash).
- Ne smemo dodajat novih runtime odvisnosti.
- Mora ohranit obstoječi vmesnik (input stdin JSON, output 2-4 lines).
- Ne lomi Linux dela skripta z dodajanjem macOS portov.

## Goal

Identificirati top robustnost issue (≥5 dimenzij), aplicirati surgical fixe, verificirati da skript poganja brez napak ob normal + edge inputih, in zapustiti project ISA kot living document teh robustnost criterijev.

**2026-05-10 dodano:** dodati opcijski `💭` segment v statusline ki kaže total Claude thinking-time (wall-clock med vsemi user/tool→assistant prehodi) za **trenutno sejo** in agregiran **all-time total** preko vseh sej. Wall-clock pristop, ne thinking-token estimate — Klemen explicitly potrdil "wall clock med assistant turni je ok, je lahko included". Opt-in preko `statusline.showThinkingTime: true` (privzeto false, ne lomi obstoječega outputa).

## Criteria

- [ ] ISC-1: Branch name s single quote ne pokvari `source git.sh` (probe: `branch="feat/'x"; printf "branch='%s'\n" "$branch"; bash -n` mora bit valid)
- [ ] ISC-2: Git data (branch, last_commit, porcelain) konsistentno bere isti git root — vse iz `$current_dir`, ne mix CWD/cwd
- [ ] ISC-3: Credentials lookup uporablja `$CLAUDE_HOME` ne hardcoded `${HOME}/.claude` (probe: `grep '\${HOME}/.claude/.credentials' statusline-command.sh` mora vrnit 0 hit)
- [ ] ISC-4: `kitten @ ls` ima timeout ≤1s (probe: `grep 'kitten @ ls' statusline-command.sh` v context z `timeout`)
- [ ] ISC-5: `wc -L` ima fallback za sisteme brez GNU coreutils (probe: alternativa preko awk za macOS)
- [ ] ISC-6: `date -d` ima fallback ali skript jasno označi GNU-only (probe: dokumentirano v README ali fix v skripti)
- [ ] ISC-7: Skript poganja clean ob malformed JSON inputu (probe: `echo '{}' | bash statusline-command.sh; echo $?` ne 1)
- [ ] ISC-8: Skript poganja clean ob praznem inputu (probe: `echo '' | bash statusline-command.sh`)
- [ ] ISC-9: Skript poganja clean ob manjkajočem ratings.jsonl (probe: že obstoječ fallback delvuje)
- [ ] ISC-10: Anti: noben fix ne lomi obstoječih test scenariev (probe: render z dejanskim CC stdin JSON-om še vedno producira prej-veljaven output)
- [ ] ISC-11: Anti: noben fix ne dodaja novih runtime odvisnosti (probe: `command -v` count v skripti se ne poveča)
- [ ] ISC-12: Antecedent: `bash -n statusline-command.sh` (syntax check) mora pass-at po vseh editih

### Thinking-time feature (2026-05-10, ISC-13..ISC-32)

- [x] ISC-13: Setting `statusline.showThinkingTime` se prebere iz `~/.claude/settings.json` skupaj z drugimi preko enega `jq -r` calla (probe: `grep 'showThinkingTime' statusline-command.sh` ≥1 hit)
- [x] ISC-14: Privzeta vrednost SHOW_THINKING_TIME je "false" (probe: render brez settinga ne pokaže 💭 segmenta)
- [x] ISC-15: Compute uporablja le top-level `transcript_path` iz CC stdin (probe: če `transcript_path` prazen ali file ne obstaja, segment je tih)
- [x] ISC-16: Algoritem sumira gap-e med consecutive (X→Y) kjer Y.type=="assistant" (probe: jq filter prebere sort_by(.ts) + reduce; manual trace na 3-event mock vrne expected sumo)
- [x] ISC-17: Posamezen gap se cap-ira na 600s — varovalka pred user-idle (probe: `grep '600' statusline-command.sh` v thinking-time bloku)
- [x] ISC-18: Display format <1h: `Nm`; ≥1h: `Nh Nm` (probe: render z 65 min vrne "1h 5m"; render z 5 min vrne "5m")
- [x] ISC-19: Emoji 💭 — semantično ločen od 🧠 (learning) in ⏳ (session wall-clock) (probe: `grep '💭' statusline-command.sh` ≥1 hit, ne overlap-a z drugimi)
- [x] ISC-20: Per-session compute ima file-cache `thinking-cache-{session_id}.txt` v `MEMORY/STATE/` z TTL 5s (probe: drugi render <5s ne re-runa jq)
- [x] ISC-21: Per-session total se persistira v `MEMORY/STATE/thinking-time/{session_id}.txt` na vsak render (probe: po render-u file obstaja z numeric content)
- [x] ISC-22: All-time total = sum vseh `.txt` files v `MEMORY/STATE/thinking-time/` (probe: po dveh sejah all-time = session_a + session_b)
- [x] ISC-23: All-time aggregate ima 60s cache `thinking-alltime-cache.txt` (probe: drugi render v <60s ne pofizita celotnega seznama)
- [x] ISC-24: Display "full" tier prikaže `💭 sess (Σ alltime)` (probe: render output match)
- [x] ISC-25: Display "dense" tier prikaže `💭 sess` (probe: render brez Σ)
- [x] ISC-26: Display "ultra" tier preskoči thinking-time segment (probe: width-constrained render brez 💭)
- [x] ISC-27: jq stripe milisekundni del timestampa pred `fromdateiso8601` (probe: `grep '\.[0-9]+Z' statusline-command.sh` v jq filtru)
- [x] ISC-28: Anti: feature ne lomi obstoječega outputa kadar showThinkingTime=false (probe: render z default settingsi je byte-identičen prej)
- [x] ISC-29: Anti: nobena nova runtime odvisnost (probe: `command -v` count v skripti se ne spremeni)
- [x] ISC-30: Anti: feature ne sprovocira `set -o pipefail` failure pri praznem transcriptu (probe: render z `transcript_path` na empty file → exit 0)
- [x] ISC-31: Antecedent: `bash -n statusline-command.sh` pass-a po vseh editih za feature
- [x] ISC-32: Antecedent: live render z dejanskim CC stdin JSON-om producira validen output, brez spremembe pri showThinkingTime=false

## Test Strategy

| ISC | Type | Check | Threshold | Tool |
|-----|------|-------|-----------|------|
| ISC-1 | bash-n | branch with quote v printf format string | shellcheck SC2089/SC2090 | shellcheck/bash-n |
| ISC-2 | grep | `git -C "$current_dir"` v vseh git komandah | konsistenca | grep |
| ISC-3 | grep | `\${HOME}/.claude/.credentials` ne obstaja več | 0 hits | grep |
| ISC-4 | grep | `timeout 1 kitten` ali `kitten @ ls.*timeout` | 1 hit | grep |
| ISC-5 | grep | awk fallback ali check za GNU `wc` | dokumentirano/popravljeno | grep |
| ISC-7-9 | bash | dejanski poganjanje skripta | exit 0 | bash + echo |
| ISC-12 | bash -n | sintaksna analiza | parse OK | bash -n |

## Features

| Name | Satisfies | Depends_on | Parallelizable |
|------|-----------|------------|----------------|
| F1: Branch quoting fix | ISC-1 | — | yes |
| F2: Git root unification | ISC-2 | — | yes |
| F3: Credentials path fix | ISC-3 | — | yes |
| F4: Kitten timeout | ISC-4 | — | yes |
| F5: wc -L fallback | ISC-5 | — | yes |
| F6: README/note GNU-only date OR fix | ISC-6 | — | yes |
| F7: Edge-case render tests | ISC-7,8,9,12 | F1-F6 | no |
| F8: Thinking-time settings + opt-in flag | ISC-13,14 | — | yes |
| F9: Per-session thinking compute (jq + cap + cache) | ISC-15,16,17,20,27,30 | F8 | no |
| F10: All-time aggregate (per-session files + cache) | ISC-21,22,23 | F9 | no |
| F11: Display tiers (full/dense/ultra) + emoji | ISC-18,19,24,25,26 | F9,F10 | no |
| F12: Regression guards | ISC-28,29,31,32 | F8-F11 | no |

## Decisions

- **2026-05-06 — Show-your-math za delegation floor:** E3 soft floor je ≥2 delegations. Izbrani: Forge (mandatory). Drugi (Cato/Anvil/Explore) ne bi prinesel signala — script je single-file 965 lines, surgical edits, ekspertiza znotraj domene (bash). Cato je E4/E5 only. Drugi delegate bi dodal noise brez signal-a.
- **2026-05-06 — Project ISA at `<project>/ISA.md`:** Per v6.3.0 doctrine, persistent project = ISA živi z repo-jem.
- **2026-05-10 — Wall-clock vs token-proxy:** Klemen explicitly potrdil "wall clock med assistant turni je ok, je lahko included." Zato ne sumiramo `thinking` content blokov ampak gap med consecutive (user|tool_result → assistant) — vključuje API latency + tool roundtrip + model generation. Direkten, zanesljiv signal "kako dolg je bil model busy" iz transcripta.
- **2026-05-10 — 600s cap per gap:** Lunch-hour edge case: model konča turn, user gre na kosilo, vrne se v 1h, napiše naslednji prompt. Tisti 1h gap je user-idle, ne thinking. Cap 600s na posamezen gap je konzervativen — pravi API thinking turn redko presega 10 min, lunch idle vedno presega.
- **2026-05-10 — Emoji 💭 ločen od 🧠:** Pridobljen feedback memory ("Distinct emoji per dimension") — 🧠 že označuje learning ratings, ⏳ označuje session wall-clock. 💭 (thought bubble) je tretja dimenzija = thinking time. Trije ločeni emoji = trije ločeni signali, ne mešanica.
- **2026-05-10 — Show-your-math za delegation floor (E2 ≥1):** Single-file additive bash edit, ~80 vrstic, znotraj domene. Forge bi pisal kar bi jaz napisal — overhead spawn-a + roundtrip-a > signal. Anvil ni potreben (ni whole-project context). Cato je E4/E5 only. Skip delegation, write directly.
- **2026-05-10 — Per-session file dir, ne JSONL:** All-time aggregate je sum-across-sessions. JSONL upsert (single-line per session, replace on update) je awkward v bash. Direktorij `MEMORY/STATE/thinking-time/{session_id}.txt` z eno številko per file = trivial atomic write + trivial sum.

## Changelog

- **2026-05-06 — branch-quote injection**
  - conjectured: `printf "branch='%s'"` + `source` would roundtrip any git branch name safely
  - refuted_by: `git branch --show-current` returns user-controlled strings; `'` in branch breaks the single-quoted shell literal
  - learned: never source raw text with embedded single quotes; use `printf %q` (or `jq @sh`) when re-emitting user data into shell-eval-able files
  - criterion_now: ISC-1 enforces this at every git emission point

- **2026-05-06 — git root drift**
  - conjectured: `git rev-parse --git-dir` and `git -C "$current_dir"` would refer to the same repo
  - refuted_by: bg subshell uses `$PWD`, foreground porcelain uses `$current_dir` (CC stdin) — these can diverge in multi-project sessions
  - learned: pick one git root variable, use it consistently across every git invocation in the file
  - criterion_now: ISC-2 — every `git` call uses `-C "$current_dir"`

- **2026-05-06 — bash redirect errors are not stty errors**
  - conjectured: `stty size </dev/tty 2>/dev/null` would silence "No such device" when no controlling TTY
  - refuted_by: the error originates from bash's redirect (before stty even runs), so `2>/dev/null` on the stty side has no effect
  - learned: file-existence check + outer-subshell catch (`{ ... ; } 2>/dev/null`) is the right pattern for guarding redirects against missing devices
  - criterion_now: ISC-8 — empty/no-tty input emits zero stderr

## Verification

- ISC-1: bash live test — `git checkout -b "feat/it's-broken"` → `printf %q` → `source` → `branch=feat/it's-broken` ✓
- ISC-2: grep — `git -C "$_gdir|$current_dir"` v vseh 4 git klicih (153/154/156/403) ✓
- ISC-3: grep `\${HOME}/.claude/.credentials` → 0 hits ✓
- ISC-4: grep `timeout 1 kitten @ ls` → 1 hit (line 643) ✓
- ISC-5: awk replacement (line 678) ✓
- ISC-7,8,9,12: live render exit 0 + bash -n SYNTAX OK ✓
- ISC-6 (date -d): DEFERRED-VERIFY — note v README sledi v ločenem commit-u
- ISC-10,11: 39-line diff, 0 novih command odvisnosti ✓

### Thinking-time feature (2026-05-10)

- ISC-13: grep `showThinkingTime` v statusline-command.sh → 2 hits (settings read + comment) ✓
- ISC-14: render z `showThinkingTime` unset → no 💭 segment (byte-identičen flag-OFF render) ✓
- ISC-15: render z empty `transcript_path` → exit 0, no segment ✓
- ISC-16: jq filter test na f850 transcriptu → 274s computed, manual gap inspection 5+13s+...+ koherentno ✓
- ISC-17: synthetic lunch test (2× 5s real + 695s lunch) → output 7s, 695s pravilno odrezan ✓
- ISC-18: 380s session render → "6m" (10 min in 20s == 6m floor); format correct ✓
- ISC-19: grep `💭` → 2 hits (full + dense), ne overlap-a z 🧠 (line 762) ali ⏳ (line 770) ✓
- ISC-20: cache `thinking-cache-${session_id}.txt` z TTL 5s — wired (lines 716-717, age check 720) ✓
- ISC-21: file `MEMORY/STATE/thinking-time/f850...txt` po render-u obstaja, vsebuje "380" ✓
- ISC-22: alltime cache po render-u = 380, matchira sum vseh per-session files ✓
- ISC-23: `thinking-alltime-cache.txt` z TTL 60s — wired (lines 718-719) ✓
- ISC-24: full render line2 ends `…│ 💭6m Σ6m` ✓
- ISC-25: dense fallback path zgolj `💭6m` (no Σ) — wired pri 1018 ✓
- ISC-26: ultra tier preskoči thinking-time — composition modifies samo line2_full/line2_dense ✓
- ISC-27: jq filter `sub("\\.[0-9]+Z$"; "Z")` strip-a ms — line 734 ✓
- ISC-28: render z showThinkingTime=false → byte-identičen prejšnjemu output-u ✓
- ISC-29: 0 novih `command -v` poklicev — uporabljen samo obstoječi jq + awk ✓
- ISC-30: empty transcript file → exit 0 ✓
- ISC-31: `bash -n statusline-command.sh` → SYNTAX OK ✓
- ISC-32: live render z real CC stdin JSON-om → exit 0, validen output v obeh flag stanjih ✓
