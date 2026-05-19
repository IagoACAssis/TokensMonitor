# TokensMonitor

Statusline PowerShell para Claude Code. Mostra utilização 5h/7d via OAuth Anthropic API. Fetch inline por render, sem daemon.

## Stack

- Windows PowerShell 5.1 (`powershell.exe`)
- Encoding UTF-8 forçado em stdin/stdout
- Sem deps externas. Tudo `Invoke-RestMethod` + IO nativo.
- Sem processos background. Sem locks. Nenhum handle preso após render.

## Arquivos

| Arquivo | Função |
|---------|--------|
| `statusline-tokens.ps1` | Entry point. Claude Code injeta JSON via stdin. Se cache > 5s ou flag `usage-cache.refresh` existe, chama fetcher inline. Renderiza barra ANSI. |
| `usage-fetcher.ps1` | Standalone. Lê OAuth token, GET usage endpoint, grava `usage-cache.json`. Timeout 5s. |
| `refresh.ps1` | Comando manual. Força fetcher. Se falhar, cria `usage-cache.refresh` pra próximo render tentar. |
| `usage-cache.json` | Cache `five_hour` / `seven_day` / `extra_usage`. |
| `usage-cache.refresh` | Flag opcional. Existência força refetch no próximo render. Deletada após uso. |

## Fluxo

1. Claude Code chama `statusline-tokens.ps1` via stdin JSON (`transcript_path`, `model.id`).
2. Script checa idade do cache. Se > 5s ou flag `.refresh` presente → roda `usage-fetcher.ps1` inline.
3. Lê `usage-cache.json` → barras 5h/7d.
4. Escreve string ANSI: `5h [bar] X% (Yh) | 7d [bar] Z% (Wd)`.
5. Sai. Nenhum processo permanece.

## Refresh manual

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\refresh.ps1
```

Ou crie a flag sem rodar nada (próximo render pega):

```powershell
New-Item -ItemType File .\usage-cache.refresh -Force
```

## Cores ANSI

- pct ≥ 80 → vermelho (`\e[31m`)
- pct ≥ 50 → amarelo (`\e[33m`)
- < 50 → verde (`\e[32m`)
- Dim (`\e[2m`) labels.

## Endpoint OAuth

`GET https://api.anthropic.com/api/oauth/usage`
Headers:
- `Authorization: Bearer <accessToken>`
- `anthropic-beta: oauth-2025-04-20`

Timeout 5s. Falha → fetcher mantém cache antigo, adiciona `last_error` + `last_error_at`.

## Throttle

`$min_refetch_sec = 5` em `statusline-tokens.ps1`. Evita hammer quando Claude Code chama statusline múltiplas vezes seguidas. Ajustar se quiser refetch mais agressivo/relaxado.

## Gotchas Windows / PowerShell 5.1

- Path do projeto contém `(((` — sempre `-LiteralPath`, nunca glob.
- `$ErrorActionPreference = 'SilentlyContinue'` em todos scripts. Erros silenciosos (statusline não pode travar Claude Code).
- Sem `&&` em PS 5.1 — usar `;` ou `if ($?)`.
- Encoding UTF-8 forçado (`[Console]::OutputEncoding`) para chars ANSI/acentos.
- Fetcher spawn como child `powershell` (não `Start-Process`). Bloqueia render por até ~5s no pior caso. Aceitável.

## Integração Claude Code

Referenciado em `~/.claude/settings.json` como `statusLine.command`. Verificar:

```powershell
Get-Content "$env:USERPROFILE\.claude\settings.json" | Select-String -Pattern 'statusline-tokens'
```

## Verificação rápida

```powershell
Get-Item .\usage-cache.json | Select LastWriteTime    # idade do último fetch
Get-Content .\usage-cache.json                        # conteúdo
```

Nenhum processo deve permanecer entre renders. Confirmar:

```powershell
Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*statusline*' -or $_.CommandLine -like '*usage-*' }
```

## Manutenção

- Cache stale → fetcher mantém último bom, adiciona `last_error`.
- Reset manual: deletar `usage-cache.json`.
- Forçar próximo refetch sem rodar: `New-Item .\usage-cache.refresh -Force`.

## TODO/Risco conhecido

- Pricing tabela removida do statusline atual (só render 5h/7d). Reintroduzir se quiser custo/contexto de volta.
- Token OAuth pode expirar — fetcher não faz refresh, só falha silenciosa.
- Sem retry/backoff no fetcher (timeout 5s, exit 1).
- Cada render gasta ~spawn powershell + HTTP. Custo perceptível se Claude Code chamar statusline em alta frequência.
