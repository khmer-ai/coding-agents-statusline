#!/usr/bin/env bash
# Installs the custom Antigravity CLI statusline: copies statusline.sh into
# ~/.gemini/antigravity-cli/ and wires up the statusLine block in ~/.gemini/antigravity-cli/settings.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGY_DIR="${HOME}/.gemini/antigravity-cli"
SETTINGS_FILE="$AGY_DIR/settings.json"
STATUSLINE_DEST="$AGY_DIR/statusline.sh"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required but not found."
  echo "  macOS:   xcode-select --install  (or brew install python3)"
  echo "  Linux:   sudo apt install python3  (or your distro's package manager)"
  exit 1
}

mkdir -p "$AGY_DIR"
cp "$SCRIPT_DIR/statusline.sh" "$STATUSLINE_DEST"
chmod +x "$STATUSLINE_DEST"

python3 - << 'PYEOF' "$SETTINGS_FILE" "$STATUSLINE_DEST"
import json, os, sys, time

settings_file = sys.argv[1]
statusline_cmd = sys.argv[2]
home = os.path.expanduser("~")
if statusline_cmd.startswith(home):
    statusline_cmd = "~" + statusline_cmd[len(home):]

data = {}
if os.path.isfile(settings_file):
    bak = f"{settings_file}.bak.{int(time.time())}"
    try:
        with open(settings_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        with open(bak, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        print(f"Backed up existing settings to {bak}")
    except Exception as e:
        print(f"Warning: could not backup existing settings: {e}")

if not isinstance(data, dict):
    data = {}

data["statusLine"] = {
    "type": "command",
    "command": statusline_cmd,
    "padding": 1
}

with open(settings_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"Updated {settings_file} with statusLine configuration.")
PYEOF

echo "Installed $STATUSLINE_DEST"
echo "Restart agy (or start a new session) to see the new statusline."
