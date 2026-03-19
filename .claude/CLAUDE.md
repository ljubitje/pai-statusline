# PAI Status Line - Setup Agent

When a user asks you to "install the statusline", "set up the statusline", or similar, follow these steps:

## Installation Steps

1. **Copy the script:**
   ```bash
   cp statusline-command.sh ~/.claude/statusline-command.sh
   chmod +x ~/.claude/statusline-command.sh
   ```

2. **Patch settings.json** to add the statusLine config. Use `jq` to merge it safely:
   ```bash
   jq '. + {"statusLine": {"type": "command", "command": "$HOME/.claude/statusline-command.sh"}}' ~/.claude/settings.json > /tmp/settings-patched.json && mv /tmp/settings-patched.json ~/.claude/settings.json
   ```
   If the user has `PAI_DIR` set, use `$PAI_DIR/statusline-command.sh` instead of `$HOME/.claude/statusline-command.sh`.

3. **Verify** the installation:
   - Confirm the script exists and is executable: `ls -la ~/.claude/statusline-command.sh`
   - Confirm settings.json has the statusLine entry: `jq '.statusLine' ~/.claude/settings.json`

4. **Tell the user** to restart PAI to see the statusline.

## Important

- Always back up settings.json before modifying it: `cp ~/.claude/settings.json ~/.claude/settings.json.bak`
- If `statusLine` already exists in settings.json, ask the user before overwriting.
- Do not modify the statusline script itself during installation.
