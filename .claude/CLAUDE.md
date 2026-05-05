# PAI Status Line - Setup Agent

When a user asks you to "install the statusline", "set up the statusline", or similar, follow these steps:

## Installation Steps

The statusline lives under `$PAI_DIR` (default `$HOME/.claude/PAI`). `$HOME/.claude` (CLAUDE_HOME) holds only Claude-Code–managed files (`settings.json`, `hooks/`). Treat `${PAI_DIR:-$HOME/.claude/PAI}` as the canonical install root and resolve to its absolute path before writing into `settings.json`.

1. **Resolve the install path:**
   ```bash
   PAI_DIR="${PAI_DIR:-$HOME/.claude/PAI}"
   STATUSLINE_PATH="$PAI_DIR/statusline-command.sh"
   ```

2. **Copy the script:**
   ```bash
   mkdir -p "$PAI_DIR"
   cp statusline-command.sh "$STATUSLINE_PATH"
   chmod +x "$STATUSLINE_PATH"
   ```

3. **Ensure `~/.claude/settings.json` exists** (new CC installs may not have one):
   ```bash
   [ -f ~/.claude/settings.json ] || echo '{}' > ~/.claude/settings.json
   ```

4. **Back up settings.json:**
   ```bash
   cp ~/.claude/settings.json ~/.claude/settings.json.bak
   ```

5. **Add the statusLine config** (Claude Code does not expand env vars in this field, so write the resolved absolute path):
   ```bash
   jq --arg path "$STATUSLINE_PATH" \
     '.statusLine = {"type": "command", "command": $path}' \
     ~/.claude/settings.json > /tmp/sl-patch.json && mv /tmp/sl-patch.json ~/.claude/settings.json
   ```

6. **Add the auto-update hook** to SessionStart (the hook command runs in a shell, so `$PAI_DIR` expands at runtime):
   ```bash
   jq '
     .hooks.SessionStart = (.hooks.SessionStart // [])
     | if (.hooks.SessionStart | length) == 0
       then .hooks.SessionStart = [{"hooks": []}]
       else . end
     | .hooks.SessionStart[0].hooks += [{"type": "command", "command": "curl -sf --connect-timeout 1 -o \"${PAI_DIR:-$HOME/.claude/PAI}/statusline-command.sh\" \"https://codeberg.org/ljubitje/pai-statusline/raw/branch/main/statusline-command.sh?t=$(date +%s)\" && chmod +x \"${PAI_DIR:-$HOME/.claude/PAI}/statusline-command.sh\""}]
   ' ~/.claude/settings.json > /tmp/sl-patch.json && mv /tmp/sl-patch.json ~/.claude/settings.json
   ```

7. **Verify** the installation:
   - Confirm the script exists and is executable: `ls -la "$STATUSLINE_PATH"`
   - Confirm settings.json has the statusLine entry: `jq '.statusLine' ~/.claude/settings.json`
   - Confirm the auto-update hook exists: `jq '.hooks.SessionStart[0].hooks[-1]' ~/.claude/settings.json`

8. **Tell the user** to restart Claude Code to see the statusline. It will auto-update on each session start.

## Important

- If `statusLine` already exists in settings.json pointing to a different path (e.g. `~/.claude/statusline-command.sh` from an older install), ask the user before overwriting and offer to clean up the orphan file.
- If the auto-update hook already exists (check for "pai-statusline" in the curl URL), skip adding it again.
- Do not modify the statusline script itself during installation.
