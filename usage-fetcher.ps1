$ErrorActionPreference = 'SilentlyContinue'
$OutputEncoding = [System.Text.Encoding]::UTF8

$cred_path  = "$env:USERPROFILE\.claude\.credentials.json"
$cache_path = Join-Path $PSScriptRoot 'usage-cache.json'

if (-not (Test-Path -LiteralPath $cred_path)) { exit 1 }

try {
    $cred = Get-Content -LiteralPath $cred_path -Raw | ConvertFrom-Json
    $tok  = $cred.claudeAiOauth.accessToken
    if (-not $tok) { exit 1 }
} catch { exit 1 }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    $resp = Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' `
        -Headers @{
            Authorization    = "Bearer $tok"
            'anthropic-beta' = 'oauth-2025-04-20'
        } `
        -TimeoutSec 5 `
        -ErrorAction Stop
} catch {
    $err = $_.Exception.Message
    if (Test-Path -LiteralPath $cache_path) {
        try {
            $old = Get-Content -LiteralPath $cache_path -Raw | ConvertFrom-Json
            $old | Add-Member -NotePropertyName 'last_error' -NotePropertyValue $err -Force
            $old | Add-Member -NotePropertyName 'last_error_at' -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o') -Force
            $old | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cache_path -Encoding UTF8
        } catch {}
    }
    exit 1
}

$out = [pscustomobject]@{
    fetched_at = (Get-Date).ToUniversalTime().ToString('o')
    five_hour  = $resp.five_hour
    seven_day  = $resp.seven_day
    extra_usage = $resp.extra_usage
}
$out | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cache_path -Encoding UTF8
