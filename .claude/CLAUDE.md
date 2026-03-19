# PAI Status Line - Setup Agent

When a user asks you to "install the statusline", "set up the statusline", or similar, follow these steps:

## Installation Steps

1. **Copy the script:**
   ```bash
   cp statusline-command.sh ~/.claude/statusline-command.sh
   chmod +x ~/.claude/statusline-command.sh
   ```

2. **Patch settings.json** to add the statusLine config and auto-update hook. Use `jq` to merge safely:
   ```bash
   jq '
     .statusLine = {"type": "command", "command": "$HOME/.claude/statusline-command.sh"}
     | .hooks.SessionStart[0].hooks += [{"type": "command", "command": "curl -sf --connect-timeout 1 -z $HOME/.claude/statusline-command.sh -o $HOME/.claude/statusline-command.sh https://codeberg.org/ljubitje/pai-statusline/raw/branch/main/statusline-command.sh && chmod +x $HOME/.claude/statusline-command.sh"}]
   ' ~/.claude/settings.json > /tmp/settings-patched.json && mv /tmp/settings-patched.json ~/.claude/settings.json
   ```
   If the user has `PAI_DIR` set, use `$PAI_DIR/statusline-command.sh` instead of `$HOME/.claude/statusline-command.sh`.

3. **Verify** the installation:
   - Confirm the script exists and is executable: `ls -la ~/.claude/statusline-command.sh`
   - Confirm settings.json has the statusLine entry: `jq '.statusLine' ~/.claude/settings.json`
   - Confirm the auto-update hook exists: `jq '.hooks.SessionStart[0].hooks[-1]' ~/.claude/settings.json`

4. **Tell the user** to restart PAI to see the statusline. It will auto-update on each session start.

## Important

- Always back up settings.json before modifying it: `cp ~/.claude/settings.json ~/.claude/settings.json.bak`
- If `statusLine` already exists in settings.json, ask the user before overwriting.
- If the SessionStart hook array doesn't exist yet, create the full structure.
- Do not modify the statusline script itself during installation.
