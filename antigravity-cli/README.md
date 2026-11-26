# Antigravity CLI Statusline

A modern, informative 4-line statusline for the Google Antigravity CLI (`agy`), ported and adapted from the Claude Code statusline layout with full support for Gemini models, context windows, and quota tracking on macOS, Linux, and Windows.

## Preview

```text
✦ Gemini 3.8 Flash (High) :high  │  👤 lyheangung  │  💻 MacBook Pro 16  │  📂 nvtop  ⎇  main
📊 Context  █░░░░░░░░░░░░░░░░░░░░░░░  1%  12k / 1.0M tokens
⏱  0s   💰 $0.000
⚡ 5h       ██░░░░░░░░░░░░░░  15%  ⟳ 3h 28m   │   🗓  Wk   █░░░░░░░░░░░░░░░  5%  ⟳ 6d 17h
```

## Features

- **Line 1: Context & Environment**:
  - Model indicator with symbol (`✦` for Gemini, `◆` for Opus, `◈` for Sonnet, `◇` for Haiku) and effort level (e.g., `:high`).
  - Active user (`👤 <username>`) and device model (`💻 <device>`) displayed separately.
  - Device model detection: macOS (model + screen size via `system_profiler`), Linux (`/sys/class/dmi/id/product_name`), Windows (`wmic`/PowerShell), with fallback to hostname.
  - Cached at `~/.gemini/antigravity-cli/.statusline-device-cache` for instantaneous statusline refreshes.
  - Project directory name and active git branch (`📂 <dir>  ⎇  <branch>`).
  - Uncommitted git diff stats (`✏️  +<added> / −<removed>`).
- **Line 2: Context Window Progress Bar**:
  - Real-time token consumption progress bar calibrated to Gemini's 1.0M context window (or Anthropic model sizes).
  - Accurate token count display (`12k / 1.0M tokens`).
- **Line 3: Session Duration & Spend**:
  - Live session wall-clock timer (`⏱  3m 42s`) resolved across platforms (macOS BSD stat birth/mtime & Linux stat birth/mtime).
  - Total session cost tracker (`💰 $0.000`).
- **Line 4: Quota & Rate Limit Meters**:
  - Side-by-side visual progress bars for 5-hour (`⚡ 5h`) and weekly (`🗓  Wk`) quota windows.
  - Color-coded thresholds: green (< 50%), warm gold (50–79%), and red (≥ 80%).
  - Real-time relative reset countdowns (`⟳ 3h 28m`, `⟳ 6d 17h`).

## Requirements

- **macOS / Linux**:
  - `bash` (version 3.2+)
  - `python3` (built-in on macOS and Linux — no `jq` or external dependencies needed)
- **Windows**:
  - PowerShell — either PowerShell 7 (`pwsh`, preferred if installed) or Windows PowerShell 5.1 (built into Windows 10/11). No `bash`, `python3`, or `jq` required.

## Installation

### Automatic Install (macOS / Linux)

Run the included installer:

```bash
./install.sh
```

The installer copies `statusline.sh` into `~/.gemini/antigravity-cli/statusline.sh`, makes it executable, and merges the `statusLine` configuration into `~/.gemini/antigravity-cli/settings.json` (saving a timestamped backup of your existing settings).

### Automatic Install (Windows)

Run the included PowerShell installer from PowerShell or `cmd.exe`:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

The installer copies `statusline.ps1` into `%USERPROFILE%\.gemini\antigravity-cli\statusline.ps1` and merges the `statusLine` configuration into `%USERPROFILE%\.gemini\antigravity-cli\settings.json` (saving a timestamped backup of your existing settings).

### Manual Install

#### macOS / Linux

1. Copy `statusline.sh` to your Antigravity CLI directory:
   ```bash
   cp statusline.sh ~/.gemini/antigravity-cli/statusline.sh
   chmod +x ~/.gemini/antigravity-cli/statusline.sh
   ```

2. Add or update the `statusLine` configuration in `~/.gemini/antigravity-cli/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.gemini/antigravity-cli/statusline.sh",
       "padding": 1
     }
   }
   ```

#### Windows

1. Copy `statusline.ps1` to `%USERPROFILE%\.gemini\antigravity-cli\statusline.ps1`.
2. Add or update the `statusLine` configuration in `%USERPROFILE%\.gemini\antigravity-cli\settings.json` (omit quotes around the `.ps1` path if it has no spaces, since `agy` invokes `command` via `cmd /c` and inner quotes can be passed literally to `pwsh`/`powershell`):
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\YOU\\.gemini\\antigravity-cli\\statusline.ps1",
       "padding": 1
     }
   }
   ```

3. Launch or restart `agy`. Your custom statusline will render immediately at the bottom of the CLI window.
