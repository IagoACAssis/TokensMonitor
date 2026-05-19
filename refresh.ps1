$ErrorActionPreference = 'SilentlyContinue'
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root         = $PSScriptRoot
$fetcher_path = Join-Path $root 'usage-fetcher.ps1'
$cache_path   = Join-Path $root 'usage-cache.json'
$refresh_flag = Join-Path $root 'usage-cache.refresh'

if (-not (Test-Path -LiteralPath $fetcher_path)) {
    Write-Host "fetcher not found: $fetcher_path" -ForegroundColor Red
    exit 1
}

Write-Host "Refreshing usage cache..." -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $fetcher_path
$code = $LASTEXITCODE

if ($code -eq 0 -and (Test-Path -LiteralPath $cache_path)) {
    Write-Host "OK -> $cache_path" -ForegroundColor Green
    try {
        $u = Get-Content -LiteralPath $cache_path -Raw | ConvertFrom-Json
        $p5 = [int][double]$u.five_hour.utilization
        $p7 = [int][double]$u.seven_day.utilization
        Write-Host ("  5h: {0}%   7d: {1}%" -f $p5, $p7) -ForegroundColor Gray
    } catch {}
} else {
    Write-Host "fetch failed (exit $code). Marking flag for next statusline render." -ForegroundColor Yellow
    New-Item -ItemType File -Path $refresh_flag -Force | Out-Null
}
