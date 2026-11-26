# Installs the custom Antigravity CLI statusline: copies statusline.ps1 into
# ~/.gemini/antigravity-cli/ and wires up the statusLine block in ~/.gemini/antigravity-cli/settings.json.
# Works in Windows PowerShell (5.1+) and PowerShell 7 (pwsh) — run from either
# a PowerShell prompt or the classic `cmd.exe` via:
#   powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"

$ScriptDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgyDir         = Join-Path $HOME ".gemini\antigravity-cli"
$SettingsFile   = Join-Path $AgyDir "settings.json"
$StatuslineDest = Join-Path $AgyDir "statusline.ps1"

New-Item -ItemType Directory -Force -Path $AgyDir | Out-Null
Copy-Item -Path (Join-Path $ScriptDir "statusline.ps1") -Destination $StatuslineDest -Force

# Prefer PowerShell 7 (pwsh) if installed, otherwise fall back to Windows PowerShell.
$psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }

# Omit quotes around the script path unless it contains whitespace:
# agy invokes statusLine.command via `cmd /c`, and inner double quotes can be
# passed literally to pwsh/powershell, causing exit status 64.
$fileArg = if ($StatuslineDest -match '\s') { "`"$StatuslineDest`"" } else { $StatuslineDest }
$commandLine = "$psExe -NoProfile -ExecutionPolicy Bypass -File $fileArg"

$statusLineBlock = [ordered]@{
    type    = "command"
    command = $commandLine
    padding = 1
}

if (Test-Path $SettingsFile) {
    $backup = "$SettingsFile.bak.$(Get-Date -Format yyyyMMddHHmmss)"
    Copy-Item $SettingsFile $backup
    $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
    $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLineBlock -Force
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsFile -Encoding UTF8
    Write-Host "Updated $SettingsFile (backup saved at $backup)."
} else {
    $settings = [ordered]@{ statusLine = $statusLineBlock }
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsFile -Encoding UTF8
    Write-Host "Created $SettingsFile."
}

Write-Host "Installed $StatuslineDest"
Write-Host "Restart agy (or start a new session) to see the new statusline."
