# Installer Claude Code Tokens Monitor
# Uso: powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "Claude Code Tokens Monitor - Installer" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

# 1. Checar PowerShell 5.1+
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "ERRO: PowerShell 5.1+ requerido. Atual: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    exit 1
}

# 2. Checar credenciais Claude Code
$cred_path = "$env:USERPROFILE\.claude\.credentials.json"
if (-not (Test-Path -LiteralPath $cred_path)) {
    Write-Host "ERRO: Credencial OAuth nao encontrada em $cred_path" -ForegroundColor Red
    Write-Host "Rode 'claude' uma vez e faca login antes de instalar." -ForegroundColor Yellow
    exit 1
}

# 3. Destino instalacao
$install_dir = Join-Path $env:USERPROFILE '.claude\statusline-tokens'
$settings    = Join-Path $env:USERPROFILE '.claude\settings.json'

if (-not (Test-Path -LiteralPath $install_dir)) {
    New-Item -ItemType Directory -Path $install_dir -Force | Out-Null
}

# 4. Copiar scripts
$scripts = @('statusline-tokens.ps1', 'usage-fetcher.ps1', 'refresh.ps1')
foreach ($s in $scripts) {
    $src = Join-Path $PSScriptRoot $s
    $dst = Join-Path $install_dir $s
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host "ERRO: $s nao encontrado em $PSScriptRoot" -ForegroundColor Red
        exit 1
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "  copiado: $s" -ForegroundColor Green
}

# 5. Patch settings.json (preservando JSON existente)
$statusline_script = Join-Path $install_dir 'statusline-tokens.ps1'
$command_str = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$statusline_script`""

$settings_obj = $null
if (Test-Path -LiteralPath $settings) {
    try {
        $settings_obj = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
    } catch {
        $backup = "$settings.bak"
        Copy-Item -LiteralPath $settings -Destination $backup -Force
        Write-Host "AVISO: settings.json invalido. Backup em $backup" -ForegroundColor Yellow
        $settings_obj = [pscustomobject]@{}
    }
} else {
    $settings_obj = [pscustomobject]@{}
}

# 5a. statusLine
$sl_value = [pscustomobject]@{
    type    = 'command'
    command = $command_str
    padding = 0
}

if ($settings_obj.PSObject.Properties.Name -contains 'statusLine') {
    $settings_obj.statusLine = $sl_value
} else {
    $settings_obj | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue $sl_value
}

# 5b. Cleanup hook UserPromptSubmit legado (install antigo registrava /monitor-refresh)
if (($settings_obj.PSObject.Properties.Name -contains 'hooks') -and
    ($settings_obj.hooks.PSObject.Properties.Name -contains 'UserPromptSubmit')) {
    $existing = @($settings_obj.hooks.UserPromptSubmit)
    $kept = @()
    foreach ($e in $existing) {
        $is_ours = $false
        if ($e.hooks) {
            foreach ($h in $e.hooks) {
                if ($h.command -and ($h.command -like '*monitor-refresh*')) { $is_ours = $true; break }
            }
        }
        if (-not $is_ours) { $kept += $e }
    }
    if ($kept.Count -lt $existing.Count) {
        if ($kept.Count -gt 0) {
            $settings_obj.hooks.UserPromptSubmit = $kept
        } else {
            $settings_obj.hooks.PSObject.Properties.Remove('UserPromptSubmit')
        }
        if ($settings_obj.hooks.PSObject.Properties.Count -eq 0) {
            $settings_obj.PSObject.Properties.Remove('hooks')
        }
        Write-Host "  legado removido: hook /monitor-refresh em settings.json" -ForegroundColor DarkGray
    }
}

$settings_obj | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settings -Encoding UTF8
Write-Host "  patch: $settings (statusLine)" -ForegroundColor Green

# 6. Cleanup: remover slash command .md legado
$legacy_cmd_md = Join-Path $env:USERPROFILE '.claude\commands\monitor-refresh.md'
if (Test-Path -LiteralPath $legacy_cmd_md) {
    try {
        Remove-Item -LiteralPath $legacy_cmd_md -Force
        Write-Host "  legado removido: $legacy_cmd_md" -ForegroundColor DarkGray
    } catch {}
}

# 7. Teste rapido do fetcher
Write-Host "Testando fetcher..." -ForegroundColor Cyan
$fetcher = Join-Path $install_dir 'usage-fetcher.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $fetcher
$cache = Join-Path $install_dir 'usage-cache.json'
if (Test-Path -LiteralPath $cache) {
    Write-Host "  fetcher OK -> $cache" -ForegroundColor Green
} else {
    Write-Host "  AVISO: fetcher falhou. Statusline mostrara 'usage:loading' ate proxima tentativa." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Instalado em: $install_dir" -ForegroundColor Cyan
Write-Host "Refresh manual: powershell -NoProfile -ExecutionPolicy Bypass -File `"$install_dir\refresh.ps1`"" -ForegroundColor Cyan
Write-Host "Abra/reinicie o Claude Code para ver statusline." -ForegroundColor Cyan
Write-Host ""
Write-Host "Desinstalar: powershell -ExecutionPolicy Bypass -File .\uninstall.ps1" -ForegroundColor DarkGray
