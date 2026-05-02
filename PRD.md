# PRD: Repository Owner Migration (fishbowl → ljubitje)

## Context

The `pai-statusline` repository on Codeberg has been transferred from the `fishbowl` organization back to the `ljubitje` user account. All references in project files and git configuration still point to `fishbowl` and must be updated.

**Current (incorrect):** `codeberg.org/fishbowl/pai-statusline`
**Target (correct):** `codeberg.org/ljubitje/pai-statusline`

## Scope

### Files requiring updates

| File | Lines | Reference |
|------|-------|-----------|
| `README.md` | 41 | Installation command: `codeberg.org/fishbowl/pai-statusline` |
| `README.md` | 76 | Auto-update curl URL in JSON example |
| `README.md` | 93 | Manual update command: `codeberg.org/fishbowl/pai-statusline` |
| `.claude/CLAUDE.md` | 38 | Auto-update hook curl URL in setup instructions |
| `.git/config` | — | Git remote origin URL |

### Files with NO changes needed

| File | Reason |
|------|--------|
| `statusline-command.sh` | No owner references (uses API URLs, not repo URLs) |
| `LICENSE` | No owner references |
| `.gitignore` | No owner references |

## Changes

1. **README.md** — Replace all 3 occurrences of `fishbowl` with `ljubitje`
2. **.claude/CLAUDE.md** — Replace 1 occurrence of `fishbowl` with `ljubitje`
3. **Git remote** — Update origin URL from `fishbowl` to `ljubitje`

## Verification

- [ ] `grep -r fishbowl` returns zero matches in tracked files
- [ ] `git remote -v` shows `ljubitje/pai-statusline`
- [ ] README install/update commands point to correct URL
- [ ] CLAUDE.md setup hook points to correct URL
