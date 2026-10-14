#!/usr/bin/env bash
# Installs the custom Claude Code statusline: copies statusline.sh into
# ~/.claude/ and wires up the statusLine block in ~/.claude/settings.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
STATUSLINE_DEST="$CLAUDE_DIR/statusline.sh"

command -v jq >/dev/null 2>&1 || {
  echo "jq is required but not found."
  echo "  macOS:   brew install jq"
  echo "  Linux:   sudo apt install jq   (or your distro's package manager)"
  echo "  Windows: choco install jq      (or use Git Bash / WSL with jq installed)"
  exit 1
}

mkdir -p "$CLAUDE_DIR"
cp "$SCRIPT_DIR/statusline.sh" "$STATUSLINE_DEST"
chmod +x "$STATUSLINE_DEST"

if [ -f "$SETTINGS_FILE" ]; then
  cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak.$(date +%s)"
  jq '.statusLine = {"type":"command","command":"~/.claude/statusline.sh","padding":1,"refreshInterval":1}' \
    "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  echo "Updated $SETTINGS_FILE (backup saved alongside it)."
else
  cat > "$SETTINGS_FILE" <<'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 1,
    "refreshInterval": 1
  }
}
EOF
  echo "Created $SETTINGS_FILE."
fi

echo "Installed ~/.claude/statusline.sh"
echo "Restart Claude Code (or start a new session) to see the new statusline."
