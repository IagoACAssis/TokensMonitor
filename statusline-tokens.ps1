$ErrorActionPreference = 'SilentlyContinue'
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$input_json = [Console]::In.ReadToEnd()
$ctx = $input_json | ConvertFrom-Json

$transcript = $ctx.transcript_path
$model_id   = $ctx.model.id

$cache_path   = Join-Path $PSScriptRoot 'usage-cache.json'
$fetcher_path = Join-Path $PSScriptRoot 'usage-fetcher.ps1'
$refresh_flag = Join-Path $PSScriptRoot 'usage-cache.refresh'

$min_refetch_sec = 5

$need_fetch = $true
if (Test-Path -LiteralPath $cache_path) {
    try {
        $age = ((Get-Date) - (Get-Item -LiteralPath $cache_path).LastWriteTime).TotalSeconds
        if ($age -lt $min_refetch_sec) { $need_fetch = $false }
    } catch {}
}
if (Test-Path -LiteralPath $refresh_flag) {
    $need_fetch = $true
    Remove-Item -LiteralPath $refresh_flag -Force -ErrorAction SilentlyContinue
}

if ($need_fetch -and (Test-Path -LiteralPath $fetcher_path)) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $fetcher_path | Out-Null
}

$esc   = [char]27
$reset = "$esc[0m"
$dim   = "$esc[2m"
$cyan  = "$esc[36m"

function Color-Pct($p) {
    if ($p -ge 80) { return "$esc[31m" }
    if ($p -ge 50) { return "$esc[33m" }
    return "$esc[32m"
}

function Build-Bar($pct, [int]$width = 10) {
    $p = [math]::Max(0, [math]::Min(100, $pct))
    $filled = [int][math]::Floor(($p / 100.0) * $width)
    if ($filled -gt $width) { $filled = $width }
    return ('#' * $filled) + ('-' * ($width - $filled))
}

function Fmt-ResetIn($iso) {
    if (-not $iso) { return '' }
    try {
        $t = [datetime]::Parse($iso).ToUniversalTime()
        $delta = $t - (Get-Date).ToUniversalTime()
        if ($delta.TotalSeconds -le 0) { return 'now' }
        if ($delta.TotalDays    -ge 1) { return ('{0}d{1}h' -f [int]$delta.TotalDays, $delta.Hours) }
        if ($delta.TotalHours   -ge 1) { return ('{0}h{1}m' -f [int]$delta.TotalHours, $delta.Minutes) }
        return ('{0}m' -f [int]$delta.TotalMinutes)
    } catch { return '' }
}

$usage_str = ''
if (Test-Path -LiteralPath $cache_path) {
    try {
        $u = Get-Content -LiteralPath $cache_path -Raw | ConvertFrom-Json
        $p5 = [double]$u.five_hour.utilization
        $p7 = [double]$u.seven_day.utilization
        $r5 = Fmt-ResetIn $u.five_hour.resets_at
        $r7 = Fmt-ResetIn $u.seven_day.resets_at
        $c5 = Color-Pct $p5
        $c7 = Color-Pct $p7
        $b5 = Build-Bar $p5
        $b7 = Build-Bar $p7
        $usage_str = "${dim}5h${reset} $c5[$b5] $([int]$p5)%$reset ${dim}($r5)${reset} ${dim}|${reset} ${dim}7d${reset} $c7[$b7] $([int]$p7)%$reset ${dim}($r7)${reset}"
    } catch { $usage_str = "${dim}usage:cache-err${reset}" }
} else {
    $usage_str = "${dim}usage:loading${reset}"
}

[Console]::Write($usage_str)
