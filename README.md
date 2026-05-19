# Claude Code Tokens Monitor

Statusline para [Claude Code](https://claude.com/claude-code) no Windows. Mostra utilização da janela de 5 horas e 7 dias em barras coloridas via OAuth API.

```
5h [####------] 19% (4h) | 7d [#---------] 13% (3d2h)
```

- **Verde** < 50% · **Amarelo** ≥ 50% · **Vermelho** ≥ 80%
- Fetch inline a cada render (throttle 5s). Sem daemon, sem agendamento, sem processo residente.
- Zero dependências externas. Só PowerShell nativo.

## Requisitos

- Windows 10/11
- PowerShell 5.1+ (já vem no Windows)
- Claude Code instalado e logado (`claude` rodado pelo menos uma vez — gera `~/.claude/.credentials.json`)

## Instalação

```powershell
git clone https://github.com/<seu-usuario>/claude-tokens-monitor.git
cd claude-tokens-monitor
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

O installer:

1. Copia scripts para `%USERPROFILE%\.claude\statusline-tokens\`.
2. Adiciona chave `statusLine` em `%USERPROFILE%\.claude\settings.json` (preserva o resto do JSON; se inválido, salva `.bak`).
3. Limpa resíduos de instalações antigas (hook `UserPromptSubmit` e `commands\monitor-refresh.md` legados, se existirem).
4. Roda o fetcher uma vez para popular `usage-cache.json`.

Reinicie o Claude Code. Pronto.

## Desinstalação

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Remove o diretório de instalação, retira `statusLine` do `settings.json` (com backup `.bak`) e limpa resíduos legados (hook `UserPromptSubmit` e `commands\monitor-refresh.md`, se existirem). Só mexe na chave `statusLine` se ela apontar para `statusline-tokens.ps1` — configs custom de outras ferramentas são preservadas.

## Como funciona

| Arquivo | Função |
|---------|--------|
| `statusline-tokens.ps1` | Entry point. Claude Code injeta JSON via stdin a cada render. |
| `usage-fetcher.ps1` | Lê OAuth token de `~/.claude/.credentials.json`, GET no usage endpoint, grava `usage-cache.json`. Timeout 5s. |
| `refresh.ps1` | Refresh manual. Roda o fetcher; se falhar, cria `usage-cache.refresh` para o próximo render tentar. |
| `usage-cache.json` | Cache da última resposta (`five_hour` / `seven_day` / `extra_usage`). |
| `usage-cache.refresh` | Flag opcional. Se existir, força refetch no próximo render. Deletada após uso. |

Fluxo por render:

1. Claude Code chama `statusline-tokens.ps1` via stdin JSON.
2. Script checa idade do `usage-cache.json`. Se > 5s **ou** flag `.refresh` presente → roda `usage-fetcher.ps1` inline (spawn child `powershell`, bloqueia até ~5s no pior caso).
3. Lê `usage-cache.json` → renderiza barras ANSI.
4. Sai. Nenhum processo residente.

Throttle de 5s (`$min_refetch_sec` em `statusline-tokens.ps1`) evita hammer quando o Claude Code chama statusline múltiplas vezes seguidas.

## Refresh manual

Rode no PowerShell (fora do Claude Code, ou via prefixo `!` numa sessão Claude Code):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\statusline-tokens\refresh.ps1"
```

Ou só criar a flag — o próximo render do statusline faz o fetch automaticamente:

```powershell
New-Item -ItemType File "$env:USERPROFILE\.claude\statusline-tokens\usage-cache.refresh" -Force
```

> Não existe slash command `/monitor-refresh`. Versões antigas registravam um, mas slashes desconhecidos são interceptados pelo Claude Code antes de qualquer hook — não havia como fazer funcionar de forma confiável. Use os comandos acima.

## Verificar estado

```powershell
cd $env:USERPROFILE\.claude\statusline-tokens
Get-Item .\usage-cache.json | Select LastWriteTime    # idade do último fetch
Get-Content .\usage-cache.json                        # conteúdo bruto
```

Nenhum processo persistente. Confirmar:

```powershell
Get-Process powershell -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -like '*usage-*' -or $_.Path -like '*statusline*' }
```

## Troubleshooting

**Statusline mostra `usage:loading`**
- `usage-cache.json` ainda não foi criado. Rode `refresh.ps1` (ver [Refresh manual](#refresh-manual)). Se persistir, OAuth pode estar expirado — rode `claude` e refaça login.

**Statusline mostra `usage:cache-err`**
- `usage-cache.json` corrompido. Delete e rode `refresh.ps1`.

**Statusline some sem motivo**
- Cheque `settings.json`: `Get-Content "$env:USERPROFILE\.claude\settings.json" | Select-String 'statusline-tokens'`. Se a chave sumiu, rode `install.ps1` de novo.

**Fetch falha silenciosamente**
- Fetcher mantém o último cache bom e grava `last_error` + `last_error_at` no JSON. Olhe `usage-cache.json` para a mensagem.

**Path do repo com caracteres especiais (parênteses, espaços)**
- O installer copia tudo para `%USERPROFILE%\.claude\statusline-tokens\`, então o path do clone não importa em runtime.

## Privacidade

- Token OAuth lido de `~/.claude/.credentials.json` (mesmo arquivo que o Claude Code já usa).
- Único endpoint chamado: `api.anthropic.com/api/oauth/usage`.
- Cache fica local em `%USERPROFILE%\.claude\statusline-tokens\usage-cache.json`. Nada é enviado para terceiros.

## Limitações conhecidas

- Token OAuth pode expirar — fetcher não faz refresh, só falha silenciosa (resolve com `claude` login novo).
- Sem retry/backoff no fetcher (timeout 5s, exit 1 em falha).
- Cada render gasta ~spawn powershell + HTTP quando o cache passa de 5s. Em renders rápidos consecutivos, o throttle absorve.
- Pricing/contexto detalhado removido — só render 5h/7d.

## Roadmap

- [ ] Port macOS/Linux (bash)
- [ ] Modo verboso opcional (tokens, custo, contexto)
- [ ] Refresh transparente do token OAuth

## Licença

MIT
