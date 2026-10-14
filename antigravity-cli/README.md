# Antigravity CLI Statusline

A modern, informative 4-line statusline for the Google Antigravity CLI (`agy`), ported and adapted from the Claude Code statusline layout with full support for Gemini models, context windows, and quota tracking.

## Preview

```text
✦ Gemini 3.8 Flash (High) :high  │  👤 finte  │  💻 ftc-1  │  📂 nvtop  ⎇  master
📊 Context  █░░░░░░░░░░░░░░░░░░░░░░░  1%  12k / 1.0M tokens
⏱  0s   💰 $0.000
⚡ 5h       ██░░░░░░░░░░░░░░  15%  ⟳ 3h 28m   │   🗓  Wk   █░░░░░░░░░░░░░░░  5%  ⟳ 6d 17h
```

## Features

- **Line 1: Context & Environment**:
  - Model indicator with symbol (`✦` for Gemini, `◆` for Opus, `◈` for Sonnet, `◇` for Haiku) and effort level (e.g., `:high`).
  - Active user (`👤 <username>`) and machine hostname (`💻 <device>`) displayed separately.
  - Project directory name and active git branch (`📂 <dir>  ⎇  <branch>`).
  - Uncommitted git diff stats (`✏️  +<added> / −<removed>`).
- **Line 2: Context Window Progress Bar**:
  - Real-time token consumption progress bar calibrated to Gemini's 1.0M context window (or Anthropic model sizes).
  - Accurate token count display (`12k / 1.0M tokens`).
- **Line 3: Session Duration & Spend**:
  - Live session wall-clock timer (`⏱  3m 42s`).
  - Total session cost tracker (`💰 $0.000`).
- **Line 4: Quota & Rate Limit Meters**:
  - Side-by-side visual progress bars for 5-hour (`⚡ 5h`) and weekly (`🗓  Wk`) quota windows.
  - Color-coded thresholds: green (< 50%), warm gold (50–79%), and red (≥ 80%).
  - Real-time relative reset countdowns (`⟳ 3h 28m`, `⟳ 6d 17h`).

## Requirements

- `bash` (version 3.2+)
- `python3` (for fast JSON parsing without requiring `jq`)

## Installation

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

3. Launch or restart `agy`. Your custom statusline will render immediately at the bottom of the CLI window.
