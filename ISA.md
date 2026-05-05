---
project: pai-statusline
task: Robustness audit and surgical fixes
effort: E3
phase: complete
progress: 11/12
mode: algorithm
started: 2026-05-06
updated: 2026-05-06
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

## Decisions

- **2026-05-06 — Show-your-math za delegation floor:** E3 soft floor je ≥2 delegations. Izbrani: Forge (mandatory). Drugi (Cato/Anvil/Explore) ne bi prinesel signala — script je single-file 965 lines, surgical edits, ekspertiza znotraj domene (bash). Cato je E4/E5 only. Drugi delegate bi dodal noise brez signal-a.
- **2026-05-06 — Project ISA at `<project>/ISA.md`:** Per v6.3.0 doctrine, persistent project = ISA živi z repo-jem.

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
