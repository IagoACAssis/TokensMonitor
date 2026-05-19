# Uninstaller Claude Code Tokens Monitor
# Uso: powershell -ExecutionPolicy Bypass -File uninstall.ps1

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "Claude Code Tokens Monitor - Uninstaller" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$install_dir  = Join-Path $env:USERPROFILE '.claude\statusline-tokens'
$settings     = Join-Path $env:USERPROFILE '.claude\settings.json'
$commands_dir = Join-Path $env:USERPROFILE '.claude\commands'
$cmd_md       = Join-Path $commands_dir 'monitor-refresh.md'

# 1. Remover diretorio instalacao
if (Test-Path -LiteralPath $install_dir) {
    try {
        Remove-Item -LiteralPath $install_dir -Recurse -Force
        Write-Host "  removido: $install_dir" -ForegroundColor Green
    } catch {
        Write-Host "ERRO: nao consegui remover $install_dir" -ForegroundColor Red
        Write-Host "  Detalhe: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  Feche o Claude Code e tente de novo." -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "  nao encontrado: $install_dir (ja removido?)" -ForegroundColor DarkGray
}

# 2. Patch settings.json: remover statusLine + hook /monitor-refresh
if (Test-Path -LiteralPath $settings) {
    try {
        $settings_obj = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
        $changed = $false
        $backup_done = $false

        function Ensure-Backup {
            param($path)
            $bak = "$path.bak"
            Copy-Item -LiteralPath $path -Destination $bak -Force
            return $bak
        }

        # 2a. statusLine
        if ($settings_obj.PSObject.Properties.Name -contains 'statusLine') {
            $cmd_field = $settings_obj.statusLine.command
            $is_ours = $cmd_field -and ($cmd_field -like '*statusline-tokens.ps1*')

            if ($is_ours) {
                if (-not $backup_done) { $backup = Ensure-Backup $settings; $backup_done = $true }
                $settings_obj.PSObject.Properties.Remove('statusLine')
                $changed = $true
                Write-Host "  patch: statusLine removido" -ForegroundColor Green
            } else {
                Write-Host "  AVISO: statusLine existe mas nao aponta para statusline-tokens.ps1. Nao mexi." -ForegroundColor Yellow
            }
        }

        # 2b. Hook UserPromptSubmit -> /monitor-refresh
        if (($settings_obj.PSObject.Properties.Name -contains 'hooks') -and
            ($settings_obj.hooks.PSObject.Properties.Name -contains 'UserPromptSubmit')) {

            $existing = @($settings_obj.hooks.UserPromptSubmit)
            $kept = @()
            $removed = 0
            foreach ($e in $existing) {
                $is_ours = $false
                if ($e.hooks) {
                    foreach ($h in $e.hooks) {
                        if ($h.command -and ($h.command -like '*monitor-refresh*')) { $is_ours = $true; break }
                    }
                }
                if ($is_ours) { $removed++ } else { $kept += $e }
            }

            if ($removed -gt 0) {
                if (-not $backup_done) { $backup = Ensure-Backup $settings; $backup_done = $true }
                if ($kept.Count -gt 0) {
                    $settings_obj.hooks.UserPromptSubmit = $kept
                } else {
                    $settings_obj.hooks.PSObject.Properties.Remove('UserPromptSubmit')
                }
                # Limpar hooks vazio
                if ($settings_obj.hooks.PSObject.Properties.Count -eq 0) {
                    $settings_obj.PSObject.Properties.Remove('hooks')
                }
                $changed = $true
                Write-Host "  patch: hook /monitor-refresh removido ($removed entry)" -ForegroundColor Green
            }
        }

        if ($changed) {
            $settings_obj | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settings -Encoding UTF8
            Write-Host "  backup: $backup" -ForegroundColor DarkGray
        } else {
            Write-Host "  settings.json sem entries nossos. Nada a fazer." -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "ERRO ao processar settings.json: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Edite manualmente: remova chave 'statusLine' e hook UserPromptSubmit contendo 'monitor-refresh' de $settings" -ForegroundColor Yellow
    }
} else {
    Write-Host "  nao encontrado: $settings" -ForegroundColor DarkGray
}

# 3. Remover slash command .md legado (caso install antigo tenha criado)
if (Test-Path -LiteralPath $cmd_md) {
    try {
        Remove-Item -LiteralPath $cmd_md -Force
        Write-Host "  removido (legado): $cmd_md" -ForegroundColor Green
    } catch {
        Write-Host "AVISO: nao consegui remover $cmd_md" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Desinstalado." -ForegroundColor Cyan
Write-Host "Reinicie o Claude Code para statusline sumir." -ForegroundColor Cyan
