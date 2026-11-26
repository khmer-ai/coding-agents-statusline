# Antigravity CLI status line — Windows-native port (PowerShell / pwsh).
# Ported from https://github.com/khmer-ai/coding-agents-statusline (antigravity-cli/statusline.sh).
# Reads session JSON on stdin.

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd()
$json = $null
if ($raw -and $raw.Trim()) {
    try { $json = $raw | ConvertFrom-Json } catch { $json = $null }
}

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

$modelObj = Get-Val $json @('model') $null
$ctxObj   = Get-Val $json @('context_window') $null
$costObj  = Get-Val $json @('cost') $null
$rlObj    = Get-Val $json @('rate_limits') $null
$quotaObj = Get-Val $json @('quota') $null
$wsObj    = Get-Val $json @('workspace') $null
$vcsObj   = Get-Val $json @('vcs') $null

$modelName = Get-Val $modelObj @('display_name') '?'
$modelId   = [string](Get-Val $modelObj @('id') '')
$inTok     = [double](Get-Val $ctxObj @('total_input_tokens') 0)
$ctxWin    = [double](Get-Val $ctxObj @('context_window_size') 1048576)
if ($ctxWin -le 0) { $ctxWin = 1048576 }

$costVal = Get-Val $costObj @('total_cost_usd') $null
if ($null -eq $costVal) { $costVal = Get-Val $costObj @('total_usd') 0 }
$cost = [double]$costVal

$added   = [int](Get-Val $costObj @('total_lines_added') 0)
$removed = [int](Get-Val $costObj @('total_lines_removed') 0)

$cwd = Get-Val $wsObj @('current_dir') $null
if (-not $cwd) { $cwd = Get-Val $json @('cwd') '' }
$targetDir = if ($cwd) { $cwd } else { (Get-Location).Path }
$dir = Get-DirName $targetDir

# --- Rate limits / Quota (Claude Code & Antigravity) -------------------------
$nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

$fivePct   = [double](Get-Val $rlObj @('five_hour', 'used_percentage') -1)
$fiveReset = [int64](Get-Val $rlObj @('five_hour', 'resets_at') 0)
if ($fivePct -eq -1 -and $null -ne $quotaObj) {
    $mLower = $modelId.ToLowerInvariant()
    $q5 = if ($mLower -like '*claude*' -or $mLower -like '*3p*') {
        $q = Get-Val $quotaObj @('3p-5h') $null
        if ($null -eq $q) { Get-Val $quotaObj @('gemini-5h') $null } else { $q }
    } else {
        $q = Get-Val $quotaObj @('gemini-5h') $null
        if ($null -eq $q) { Get-Val $quotaObj @('3p-5h') $null } else { $q }
    }
    if ($null -ne $q5) {
        $rem = Get-Val $q5 @('remaining_fraction') $null
        if ($null -ne $rem) {
            $fivePct = [Math]::Round((1.0 - [double]$rem) * 100.0, 1)
        }
        $resetSecs = [int64](Get-Val $q5 @('reset_in_seconds') 0)
        if ($resetSecs -gt 0) { $fiveReset = $nowEpoch + $resetSecs }
    }
}

$weekPct   = [double](Get-Val $rlObj @('seven_day', 'used_percentage') -1)
$weekReset = [int64](Get-Val $rlObj @('seven_day', 'resets_at') 0)
if ($weekPct -eq -1 -and $null -ne $quotaObj) {
    $mLower = $modelId.ToLowerInvariant()
    $qw = if ($mLower -like '*claude*' -or $mLower -like '*3p*') {
        $q = Get-Val $quotaObj @('3p-weekly') $null
        if ($null -eq $q) { Get-Val $quotaObj @('gemini-weekly') $null } else { $q }
    } else {
        $q = Get-Val $quotaObj @('gemini-weekly') $null
        if ($null -eq $q) { Get-Val $quotaObj @('3p-weekly') $null } else { $q }
    }
    if ($null -ne $qw) {
        $rem = Get-Val $qw @('remaining_fraction') $null
        if ($null -ne $rem) {
            $weekPct = [Math]::Round((1.0 - [double]$rem) * 100.0, 1)
        }
        $resetSecs = [int64](Get-Val $qw @('reset_in_seconds') 0)
        if ($resetSecs -gt 0) { $weekReset = $nowEpoch + $resetSecs }
    }
}

# --- Effort level ------------------------------------------------------------
$effort = Get-Val $modelObj @('effort') ''
if (-not $effort) {
    $effortRaw = Get-Val $json @('effort') $null
    if ($effortRaw -is [string]) {
        $effort = $effortRaw
    } elseif ($null -ne $effortRaw) {
        $effort = Get-Val $effortRaw @('level') ''
    }
}

# --- Git branch & diff stats -------------------------------------------------
$branch = Get-Val $wsObj @('git_worktree') ''
if (-not $branch) { $branch = Get-Val $wsObj @('branch') '' }
if (-not $branch) { $branch = Get-Val $vcsObj @('branch') '' }

if (-not $branch -and $targetDir -and (Test-Path $targetDir)) {
    try {
        $bOut = & git -C $targetDir rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $bOut) {
            $b = $bOut.Trim()
            if ($b -ne 'HEAD') { $branch = $b }
        }
    } catch { }
}

if ($added -eq 0 -and $removed -eq 0 -and $targetDir -and (Test-Path $targetDir)) {
    try {
        $diffLines = & git -C $targetDir diff --numstat HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $diffLines) {
            foreach ($line in $diffLines) {
                $parts = $line -split '\s+'
                if ($parts.Count -ge 2 -and $parts[0] -match '^\d+$' -and $parts[1] -match '^\d+$') {
                    $added += [int]$parts[0]
                    $removed += [int]$parts[1]
                }
            }
        }
    } catch { }
}

# --- Transcript path resolution ----------------------------------------------
$transcript = [string](Get-Val $json @('transcript_path') '')
if (-not $transcript -or -not (Test-Path $transcript)) {
    $convId = Get-Val $json @('conversation_id') ''
    if (-not $convId) { $convId = Get-Val $json @('session_id') '' }
    if (-not $convId) { $convId = Get-Val $json @('cascade_id') '' }
    if ($convId) {
        $alt = Join-Path $HOME ".gemini\antigravity-cli\brain\$convId\.system_generated\logs\transcript.jsonl"
        if (Test-Path $alt) { $transcript = $alt }
    }
}
if (-not $transcript -or -not (Test-Path $transcript)) {
    $brainDir = Join-Path $HOME ".gemini\antigravity-cli\brain"
    if (Test-Path $brainDir) {
        try {
            $latest = Get-ChildItem -Path $brainDir -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName ".system_generated\logs\transcript.jsonl" } |
                Where-Object { Test-Path $_ } |
                ForEach-Object { Get-Item $_ } |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1
            if ($latest) { $transcript = $latest.FullName }
        } catch { }
    }
}

# --- Context window size budget ----------------------------------------------
$mLowerId = $modelId.ToLowerInvariant()
$ctxSize = if ($mLowerId -like '*haiku*') {
    150000
} elseif ($mLowerId -like '*sonnet*' -or $mLowerId -like '*opus*') {
    700000
} else {
    $ctxWin
}

$ctxPct = 0
if ($inTok -gt 0 -and $ctxSize -gt 0) {
    $ctxPct = [int][Math]::Floor(($inTok * 100.0) / $ctxSize)
    if ($ctxPct -gt 100) { $ctxPct = 100 }
}

# --- ANSI primitives ---------------------------------------------------------
$ESC = [char]27
$R   = "${ESC}[0m"; $B = "${ESC}[1m"; $DIM = "${ESC}[2m"; $GREY = "${ESC}[90m"

# Brand palette — 24-bit ANSI foreground
$MODEL_CLR  = "${ESC}[38;2;0;110;0m"      # #006E00  dark green     model name
$USER_CLR   = "${ESC}[38;2;110;150;200m"  # #6E96C8  soft blue      username
$HOST_CLR   = "${ESC}[38;2;160;140;210m"  # #A08CD2  soft lavender  device / hostname
$DIR_CLR    = "${ESC}[38;2;194;153;64m"   # #C29940  warm gold      project / branch
$BAR_FILL   = "${ESC}[38;2;81;181;101m"   # #51B565  medium green   bar fill, %, added lines
$BAR_EMPTY  = "${ESC}[38;2;245;230;190m"  # #F5E6BE  cream          bar ░ slots
$WARN_CLR   = "${ESC}[38;2;194;153;64m"   # #C29940  gold           50–79% warning
$DANGER_CLR = "${ESC}[38;2;200;50;50m"    # #C83232  warm red       >=80% / removed lines

$SEP = "  ${GREY}│${R}  "

function Format-Tokens {
    param([double]$N)
    if ($N -ge 1000000) { return ("{0:0.0}M" -f ($N / 1000000.0)) }
    elseif ($N -ge 1000) { return ("{0:0}k" -f ($N / 1000.0)) }
    else { return "$([int]$N)" }
}

function Format-Cost {
    param([double]$C)
    return ("{0:0.000}" -f $C)
}

function Format-Secs {
    param([int]$S)
    $h = [int][Math]::Floor($S / 3600)
    $m = [int][Math]::Floor(($S % 3600) / 60)
    $sec = $S % 60
    if ($h -gt 0) { return ("{0}h {1:D2}m" -f $h, $m) }
    elseif ($m -gt 0) { return ("{0}m {1:D2}s" -f $m, $sec) }
    else { return "${sec}s" }
}

function Format-ResetIn {
    param([int64]$Target)
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $diff = $Target - $now
    if ($diff -lt 0) { $diff = 0 }
    $days = [int][Math]::Floor($diff / 86400)
    $h    = [int][Math]::Floor(($diff % 86400) / 3600)
    $m    = [int][Math]::Floor(($diff % 3600) / 60)
    if ($days -gt 0) { return ("{0}d {1}h" -f $days, $h) }
    elseif ($h -gt 0) { return ("{0}h {1:D2}m" -f $h, $m) }
    else { return "${m}m" }
}

function Get-LimitColor {
    param([double]$Pct)
    if ($Pct -ge 80) { return $DANGER_CLR }
    elseif ($Pct -ge 50) { return $WARN_CLR }
    else { return $BAR_FILL }
}

function New-ProgressBar {
    param([double]$Pct, [int]$Width, [string]$FillClr, [string]$EmptyClr)
    $p = [int][Math]::Floor($Pct)
    if ($p -gt 100) { $p = 100 }
    if ($p -lt 0) { $p = 0 }
    $filled = [int][Math]::Floor($p * $Width / 100)
    if ($p -gt 0 -and $filled -eq 0) { $filled = 1 }
    $empty = $Width - $filled
    return $FillClr + ('█' * $filled) + $EmptyClr + ('░' * $empty) + $R
}

# --- Wall-clock session timer ------------------------------------------------
$wallSecs = 0
if ($transcript -and (Test-Path $transcript)) {
    try {
        $created = (Get-Item $transcript).CreationTimeUtc
        $wallSecs = [int]([DateTimeOffset]::UtcNow - [DateTimeOffset]::new($created)).TotalSeconds
        if ($wallSecs -lt 0) { $wallSecs = 0 }
    } catch { $wallSecs = 0 }
}

# --- Model icon --------------------------------------------------------------
$mdlIcon = switch -Wildcard ($mLowerId) {
    '*opus*'   { '◆'; break }
    '*sonnet*' { '◈'; break }
    '*haiku*'  { '◇'; break }
    default    { '✦' }
}

# --- Device model + username (cached — hardware queries are slow) ------------
$cacheDir  = Join-Path $HOME ".gemini\antigravity-cli"
$cacheFile = Join-Path $cacheDir ".statusline-device-cache"
$userName  = if ($env:USERNAME) { $env:USERNAME } elseif ($env:USER) { $env:USER } else { "" }

$deviceModel = ""
if (Test-Path $cacheFile) {
    try { $deviceModel = (Get-Content $cacheFile -Raw -ErrorAction Stop).Trim() } catch { $deviceModel = "" }
}
if (-not $deviceModel) {
    try { $deviceModel = ((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Model).Trim() } catch { $deviceModel = "" }
    if (-not $deviceModel) {
        $deviceModel = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Net.Dns]::GetHostName() }
    }
    if ($deviceModel) {
        try {
            New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
            Set-Content -Path $cacheFile -Value $deviceModel -NoNewline
        } catch { }
    }
}

# ─── LINE 1 ─ Model :effort │ 👤 user │ 💻 device │ 📂 Project ⎇ Branch │ ✏️ +add/−rm ─
$L1 = "${MODEL_CLR}${B}${mdlIcon} ${modelName}${R}"
if ($effort)      { $L1 += " ${GREY}:${effort}${R}" }
if ($userName)    { $L1 += "${SEP}${USER_CLR}👤 ${userName}${R}" }
if ($deviceModel) { $L1 += "${SEP}${HOST_CLR}💻 ${deviceModel}${R}" }
if ($dir)         { $L1 += "${SEP}${DIR_CLR}${B}📂 ${dir}${R}" }
if ($branch)      { $L1 += "  ${GREY}⎇${R}  ${DIR_CLR}${branch}${R}" }
if ($added -gt 0 -or $removed -gt 0) {
    $L1 += "${SEP}${GREY}✏️${R}  ${BAR_FILL}+${added}${R}${GREY} / ${R}${DANGER_CLR}−${removed}${R}"
}

# ─── LINE 2 ─ Context window progress bar ─────────────────────────────────────
$ctxBar = New-ProgressBar $ctxPct 24 $BAR_FILL $BAR_EMPTY
$L2 = "${GREY}📊 Context  ${R}${ctxBar}  ${BAR_FILL}${B}${ctxPct}%${R}  ${DIM}$(Format-Tokens $inTok) / $(Format-Tokens $ctxSize) tokens${R}"

# ─── LINE 3 ─ Timer   Cost ───────────────────────────────────────────────────
$L3 = "${GREY}⏱${R}  $(Format-Secs $wallSecs)   ${GREY}💰 `$${R}$(Format-Cost $cost)"

# ─── LINE 4 ─ Rate limits side-by-side ────────────────────────────────────────
$L4 = ""
if ($fivePct -ne -1 -or $weekPct -ne -1) {
    if ($fivePct -ne -1) {
        $fc = Get-LimitColor $fivePct
        $fiveBar = New-ProgressBar $fivePct 16 $fc $BAR_EMPTY
        $L4 = "${GREY}⚡ 5h       ${R}${fiveBar}  ${fc}${B}$([int][Math]::Floor($fivePct))%${R}  ${DIM}⟳ $(Format-ResetIn $fiveReset)${R}"
    }
    if ($weekPct -ne -1) {
        $wc = Get-LimitColor $weekPct
        $weekBar = New-ProgressBar $weekPct 16 $wc $BAR_EMPTY
        $wk = "${GREY}🗓  Wk   ${R}${weekBar}  ${wc}${B}$([int][Math]::Floor($weekPct))%${R}  ${DIM}⟳ $(Format-ResetIn $weekReset)${R}"
        if ($L4) { $L4 += "   ${GREY}│${R}   $wk" } else { $L4 = $wk }
    }
}

# --- Output ------------------------------------------------------------------
Write-Output $L1
Write-Output $L2
Write-Output $L3
if ($L4) { Write-Output $L4 }
