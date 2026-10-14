# Claude Code status line — Windows-native port (PowerShell / pwsh).
# Mirrors statusline.sh exactly so the look is identical across OSes.
# Reads session JSON on stdin. Fields: https://code.claude.com/docs/en/statusline.md

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd()
$json = $null
try { $json = $raw | ConvertFrom-Json } catch { $json = $null }

function Get-Val {
    param($Obj, [string[]]$Path, $Default)
    $cur = $Obj
    foreach ($p in $Path) {
        if ($null -eq $cur) { return $Default }
        $cur = $cur.$p
    }
    if ($null -eq $cur -or $cur -eq "") { return $Default }
    return $cur
}

function Get-DirName {
    param([string]$Path)
    if (-not $Path) { return "" }
    $parts = $Path -split '[\\/]' | Where-Object { $_ -ne "" }
    if ($parts.Count -gt 0) { return $parts[-1] }
    return $Path
}

$modelName  = Get-Val $json @('model', 'display_name') '?'
$modelId    = Get-Val $json @('model', 'id') ''
$inTok      = [double](Get-Val $json @('context_window', 'total_input_tokens') 0)
$cost       = [double](Get-Val $json @('cost', 'total_cost_usd') 0)
$added      = [int](Get-Val $json @('cost', 'total_lines_added') 0)
$removed    = [int](Get-Val $json @('cost', 'total_lines_removed') 0)
$fivePct    = [double](Get-Val $json @('rate_limits', 'five_hour', 'used_percentage') -1)
$fiveReset  = [int64](Get-Val $json @('rate_limits', 'five_hour', 'resets_at') 0)
$weekPct    = [double](Get-Val $json @('rate_limits', 'seven_day', 'used_percentage') -1)
$weekReset  = [int64](Get-Val $json @('rate_limits', 'seven_day', 'resets_at') 0)
$branch     = Get-Val $json @('workspace', 'git_worktree') ''
$cwd        = Get-Val $json @('workspace', 'current_dir') $null
if (-not $cwd) { $cwd = Get-Val $json @('cwd') '' }
$dir        = Get-DirName $cwd
$effort     = Get-Val $json @('effort', 'level') ''
$transcript = Get-Val $json @('transcript_path') ''

# Custom practical context limits — Haiku 150k, Sonnet/Opus 700k.
$ctxSize = if ($modelId -like '*haiku*') { 150000 } else { 700000 }
$ctxPct = 0
if ($inTok -gt 0) {
    $ctxPct = [Math]::Floor(($inTok * 100.0) / $ctxSize)
    if ($ctxPct -gt 100) { $ctxPct = 100 }
}

# --- ANSI primitives ---------------------------------------------------------
$ESC = [char]27
${R} = "${ESC}[0m"; ${B} = "${ESC}[1m"; ${DIM} = "${ESC}[2m"; ${GREY} = "${ESC}[90m"

${MODEL_CLR}  = "${ESC}[38;2;0;110;0m"
${DIR_CLR}    = "${ESC}[38;2;194;153;64m"
${BAR_FILL}   = "${ESC}[38;2;81;181;101m"
${BAR_EMPTY}  = "${ESC}[38;2;245;230;190m"
${WARN_CLR}   = "${ESC}[38;2;194;153;64m"
${DANGER_CLR} = "${ESC}[38;2;200;50;50m"

${SEP} = "  ${GREY}│${R}  "

function Format-Tokens {
    param([double]$N)
    if ($N -ge 1000000) { return "{0:N1}M" -f ($N / 1000000) }
    elseif ($N -ge 1000) { return "{0:N0}k" -f ($N / 1000) }
    else { return "$([int]$N)" }
}

function Format-Cost { param([double]$C) return "{0:N3}" -f $C }

function Format-Secs {
    param([int]$S)
    $h = [int][Math]::Floor($S / 3600); $m = [int][Math]::Floor(($S % 3600) / 60); $sec = $S % 60
    if ($h -gt 0) { return "{0}h {1:D2}m" -f $h, $m }
    elseif ($m -gt 0) { return "{0}m {1:D2}s" -f $m, $sec }
    else { return "${S}s" }
}

function Format-ResetIn {
    param([int64]$Target)
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $diff = $Target - $now
    if ($diff -lt 0) { $diff = 0 }
    $days = [int][Math]::Floor($diff / 86400); $h = [int][Math]::Floor(($diff % 86400) / 3600); $m = [int][Math]::Floor(($diff % 3600) / 60)
    if ($days -gt 0) { return "{0}d {1}h" -f $days, $h }
    elseif ($h -gt 0) { return "{0}h {1:D2}m" -f $h, $m }
    else { return "${m}m" }
}

function Get-LimitColor {
    param($Pct)
    $p = [double]$Pct
    if ($p -ge 80) { return ${DANGER_CLR} }
    elseif ($p -ge 50) { return ${WARN_CLR} }
    else { return ${BAR_FILL} }
}

function New-ProgressBar {
    param([double]$Pct, [int]$Width, [string]$FillClr, [string]$EmptyClr)
    if ($Pct -gt 100) { $Pct = 100 }
    $filled = [int][Math]::Floor($Pct * $Width / 100)
    if ($Pct -gt 0 -and $filled -eq 0) { $filled = 1 }
    $empty = $Width - $filled
    return $FillClr + ('█' * $filled) + $EmptyClr + ('░' * $empty) + ${R}
}

# --- Wall-clock session timer -------------------------------------------------
# NTFS preserves genuine file-creation time, so this is exact on Windows.
$wallSecs = 0
if ($transcript -and (Test-Path $transcript)) {
    try {
        $created = (Get-Item $transcript).CreationTimeUtc
        $wallSecs = [int]([DateTimeOffset]::UtcNow - [DateTimeOffset]::new($created)).TotalSeconds
        if ($wallSecs -lt 0) { $wallSecs = 0 }
    } catch { $wallSecs = 0 }
}

# --- Model icon ----------------------------------------------------------------
$mdlIcon = switch -Wildcard ($modelId) {
    '*opus*'   { '◆'; break }
    '*sonnet*' { '◈'; break }
    '*haiku*'  { '◇'; break }
    default    { '✦' }
}

# --- Device model + username (cached — hardware queries are slow) --------------
$cacheDir  = Join-Path $HOME ".claude"
$cacheFile = Join-Path $cacheDir ".statusline-device-cache"
$userName  = if ($env:USERNAME) { $env:USERNAME } elseif ($env:USER) { $env:USER } else { "" }

$deviceModel = ""
if (Test-Path $cacheFile) {
    try { $deviceModel = (Get-Content $cacheFile -Raw -ErrorAction Stop).Trim() } catch { $deviceModel = "" }
}
if (-not $deviceModel) {
    try { $deviceModel = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Model } catch { $deviceModel = "" }
    if ($deviceModel) {
        try {
            New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
            Set-Content -Path $cacheFile -Value $deviceModel -NoNewline
        } catch { }
    }
}

# ─── LINE 1 ─ Model :effort │ 📂 Project 💻 Device 👤 User ⎇ Branch │ ✏️ ±lines ─
$L1 = "${MODEL_CLR}${B}${mdlIcon} ${modelName}${R}"
if ($effort) { $L1 += " ${GREY}:${effort}${R}" }
$L1 += "${SEP}${DIR_CLR}${B}📂 ${dir}${R}"
if ($deviceModel) { $L1 += "  ${DIR_CLR}💻 ${deviceModel}${R}" }
if ($userName) { $L1 += "  ${GREY}👤 ${userName}${R}" }
if ($branch) { $L1 += "  ${GREY}⎇${R}  ${DIR_CLR}${branch}${R}" }
if ($added -gt 0 -or $removed -gt 0) {
    $L1 += "${SEP}${GREY}✏️${R}  ${BAR_FILL}+${added}${R}${GREY} / ${R}${DANGER_CLR}−${removed}${R}"
}

# ─── LINE 2 ─ Context window progress bar ─────────────────────────────────────
$ctxBar = New-ProgressBar $ctxPct 24 ${BAR_FILL} ${BAR_EMPTY}
$L2 = "${GREY}📊 Context  ${R}${ctxBar}  ${BAR_FILL}${B}${ctxPct}%${R}  ${DIM}$(Format-Tokens $inTok) / $(Format-Tokens $ctxSize) tokens${R}"

# ─── LINE 3 ─ Timer   Cost ───────────────────────────────────────────────────
$L3 = "${GREY}⏱${R}  $(Format-Secs $wallSecs)   ${GREY}💰 `$${R}$(Format-Cost $cost)"

# ─── LINE 4 ─ Rate limits side-by-side ────────────────────────────────────────
$L4 = ""
if ($fivePct -ne -1 -or $weekPct -ne -1) {
    if ($fivePct -ne -1) {
        $fc = Get-LimitColor $fivePct
        $fiveBar = New-ProgressBar $fivePct 16 $fc ${BAR_EMPTY}
        $L4 = "${GREY}⚡ 5h       ${R}${fiveBar}  ${fc}${B}$([int]$fivePct)%${R}  ${DIM}⟳ $(Format-ResetIn $fiveReset)${R}"
    }
    if ($weekPct -ne -1) {
        $wc = Get-LimitColor $weekPct
        $weekBar = New-ProgressBar $weekPct 16 $wc ${BAR_EMPTY}
        $wk = "${GREY}🗓  Wk   ${R}${weekBar}  ${wc}${B}$([int]$weekPct)%${R}  ${DIM}⟳ $(Format-ResetIn $weekReset)${R}"
        if ($L4) { $L4 += "   ${GREY}│${R}   $wk" } else { $L4 = $wk }
    }
}

# --- Output --------------------------------------------------------------------
Write-Output $L1
Write-Output $L2
Write-Output $L3
if ($L4) { Write-Output $L4 }
