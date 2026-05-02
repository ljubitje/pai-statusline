# PAI Status Line - Setup Agent

When a user asks you to "install the statusline", "set up the statusline", or similar, follow these steps:

## Installation Steps

1. **Ensure `~/.claude/` exists and copy the script:**
   ```bash
   mkdir -p ~/.claude
   cp statusline-command.sh ~/.claude/statusline-command.sh
   chmod +x ~/.claude/statusline-command.sh
   ```

2. **Ensure `~/.claude/settings.json` exists** (new CC installs may not have one):
   ```bash
   [ -f ~/.claude/settings.json ] || echo '{}' > ~/.claude/settings.json
   ```

3. **Back up settings.json:**
   ```bash
   cp ~/.claude/settings.json ~/.claude/settings.json.bak
   ```

4. **Add the statusLine config:**
   ```bash
   jq '.statusLine = {"type": "command", "command": "~/.claude/statusline-command.sh"}' \
     ~/.claude/settings.json > /tmp/sl-patch.json && mv /tmp/sl-patch.json ~/.claude/settings.json
   ```
   If the user has `PAI_DIR` set, use `"$PAI_DIR/statusline-command.sh"` instead.

5. **Add the auto-update hook** to SessionStart:
   ```bash
   jq '
     .hooks.SessionStart = (.hooks.SessionStart // [])
     | if (.hooks.SessionStart | length) == 0
       then .hooks.SessionStart = [{"hooks": []}]
       else . end
     | .hooks.SessionStart[0].hooks += [{"type": "command", "command": "curl -sf --connect-timeout 1 -o ~/.claude/statusline-command.sh \"https://codeberg.org/ljubitje/pai-statusline/raw/branch/main/statusline-command.sh?t=$(date +%s)\" && chmod +x ~/.claude/statusline-command.sh"}]
   ' ~/.claude/settings.json > /tmp/sl-patch.json && mv /tmp/sl-patch.json ~/.claude/settings.json
   ```
   If the user has `PAI_DIR` set, replace `~/.claude/statusline-command.sh` with `$PAI_DIR/statusline-command.sh` in the curl output path.

6. **Verify** the installation:
   - Confirm the script exists and is executable: `ls -la ~/.claude/statusline-command.sh`
   - Confirm settings.json has the statusLine entry: `jq '.statusLine' ~/.claude/settings.json`
   - Confirm the auto-update hook exists: `jq '.hooks.SessionStart[0].hooks[-1]' ~/.claude/settings.json`

7. **Tell the user** to restart Claude Code to see the statusline. It will auto-update on each session start.

## Important

- If `statusLine` already exists in settings.json, ask the user before overwriting.
- If the auto-update hook already exists (check for "pai-statusline" in the curl URL), skip adding it again.
- Do not modify the statusline script itself during installation.
