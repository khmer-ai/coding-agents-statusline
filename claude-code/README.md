# Claude Code statusline

A 4-line custom statusline for Claude Code: model + project + device + user + git
branch on line 1, a context-window usage bar on line 2, session timer/cost on
line 3, and 5-hour/weekly rate-limit bars on line 4 when available.

```
◈ Sonnet 5 :high │ 📂 myproject 💻 MacBook Pro 16 👤 alex ⎇ main │ ✏️ +5 / −2
📊 Context  ████░░░░░░░░░░░░░░░░░░░░  7%  50k / 700k tokens
⏱ 12m 04s   💰 $1.234
⚡ 5h ████░░░░░░░░░░░░  22%  ⟳ 3h 10m │ 🗓 Wk ██░░░░░░░░░░░░░░  9%  ⟳ 4d 2h
```

There are two implementations that render identically: `statusline.sh` (bash)
and `statusline.ps1` (PowerShell) — pick whichever matches how you run Claude
Code.

## Requirements

- A terminal that renders 24-bit ANSI color and emoji (most modern terminals —
  iTerm2, Windows Terminal, GNOME Terminal, VS Code's integrated terminal, etc.)
- **macOS / Linux**: `bash` + `jq` (both ship on macOS/Linux, or `jq` via your
  package manager)
- **Windows**: PowerShell — either Windows PowerShell 5.1 (built into every
  Windows 10/11 install) or PowerShell 7 (`pwsh`, preferred if present). No
  `bash` or `jq` required. Git Bash/WSL users can use the bash version instead
  if they prefer.

## Install

**macOS / Linux:**

```bash
./install.sh
```

**Windows (PowerShell or cmd.exe):**

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

(Works run from a PowerShell prompt, from `cmd.exe`, or by right-clicking
`install.ps1` → *Run with PowerShell*.)

Either installer copies the matching script into `~/.claude/` (or
`%USERPROFILE%\.claude\` on Windows) and adds/updates the `statusLine` block
in `settings.json` — existing settings are backed up first, and re-running is
safe (won't duplicate the block). Restart Claude Code to see it.

### Manual install

If you'd rather not run the installer, do it by hand:

1. Copy `statusline.sh` (or `statusline.ps1` on Windows) into your `.claude`
   folder. On macOS/Linux, `chmod +x` it.
2. Add this to `settings.json` (merge it in if the file already has other keys
   — don't overwrite them):

**macOS/Linux:**
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 1,
    "refreshInterval": 1
  }
}
```

**Windows:**
```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\YOU\\.claude\\statusline.ps1\"",
    "padding": 1,
    "refreshInterval": 1
  }
}
```
(Replace the path with your actual `.claude` folder location, or swap
`powershell` for `pwsh` if you have PowerShell 7.)

## Notes

- **Device model + username** (line 1) are detected once per machine and
  cached at `~/.claude/.statusline-device-cache` — hardware lookups are slow
  (~1s), so caching keeps the 1-second refresh snappy. Delete that file to
  force a re-detect (e.g. after moving to new hardware).
- Device-model detection: macOS (model + screen size via `system_profiler`),
  Linux (`/sys/class/dmi/id/product_name`), Windows (`Get-CimInstance
  Win32_ComputerSystem`, via `statusline.ps1`).
- Both scripts are functionally identical (same colors, icons, layout,
  caching) — kept as two files so neither needs an interpreter the other
  platform doesn't have.
- Colors are defined near the top of each script (`Brand palette` in
  `statusline.sh`, the `ANSI primitives` section in `statusline.ps1`) — edit
  those values to change the look. Keep them in sync if you customize both.
- Practical context-window caps (line 2) are hardcoded per model family
  (150k Haiku / 700k Sonnet & Opus) — adjust in the `case "$MODEL_ID"`
  block (bash) or the `-like '*haiku*'` check (PowerShell) if you want
  different thresholds.
