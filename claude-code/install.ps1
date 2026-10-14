# Installs the custom Claude Code statusline: copies statusline.ps1 into
# ~/.claude/ and wires up the statusLine block in ~/.claude/settings.json.
# Works in Windows PowerShell (5.1+) and PowerShell 7 (pwsh) — run from either
# a PowerShell prompt or the classic `cmd.exe` via:
#   powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"

$ScriptDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir      = Join-Path $HOME ".claude"
$SettingsFile   = Join-Path $ClaudeDir "settings.json"
$StatuslineDest = Join-Path $ClaudeDir "statusline.ps1"

New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
Copy-Item -Path (Join-Path $ScriptDir "statusline.ps1") -Destination $StatuslineDest -Force

# Prefer PowerShell 7 (pwsh) if installed, otherwise fall back to Windows PowerShell.
$psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
# Use the resolved absolute path (not $env:USERPROFILE) so the command string
# doesn't depend on which shell Claude Code uses to launch it.
$commandLine = "$psExe -NoProfile -ExecutionPolicy Bypass -File `"$StatuslineDest`""

$statusLineBlock = [ordered]@{
    type            = "command"
    command         = $commandLine
    padding         = 1
    refreshInterval = 1
}

if (Test-Path $SettingsFile) {
    $backup = "$SettingsFile.bak.$(Get-Date -Format yyyyMMddHHmmss)"
    Copy-Item $SettingsFile $backup
    $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
    $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLineBlock -Force
    $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsFile
    Write-Host "Updated $SettingsFile (backup saved at $backup)."
} else {
    $settings = [ordered]@{ statusLine = $statusLineBlock }
    $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsFile
    Write-Host "Created $SettingsFile."
}

Write-Host "Installed $StatuslineDest"
Write-Host "Restart Claude Code (or start a new session) to see the new statusline."
