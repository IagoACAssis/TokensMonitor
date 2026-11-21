#!/usr/bin/env bash
# TokensMonitor (port bash para Linux/WSL) — statusline com contexto da sessão e uso 5h/7d.
#
# Fonte do uso 5h/7d:
#   1. `rate_limits` do JSON que o Claude Code manda no stdin (sem chamada de rede).
#   2. Se não vier, OAuth usage API com cache em disco (throttle de 60s; 5s gera 429).

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache="$dir/usage-cache.json"
flag="$dir/usage-cache.refresh"
cred="$HOME/.claude/.credentials.json"
min_refetch_sec=60

# Faixa de trabalho do contexto, em tokens: verde < warn, amarelo < crit, vermelho >= crit.
ctx_warn=120000
ctx_crit=140000

input=$(cat)

e=$'\e'; reset="$e[0m"; dim="$e[2m"
red="$e[31m"; yellow="$e[33m"; green="$e[32m"

color() { if [ "$1" -ge 80 ]; then printf '%s' "$red"; elif [ "$1" -ge 50 ]; then printf '%s' "$yellow"; else printf '%s' "$green"; fi; }

bar() {
  local p=$1 w=10 f
  [ "$p" -lt 0 ] && p=0; [ "$p" -gt 100 ] && p=100
  f=$(( p * w / 100 ))
  printf '%*s' "$f" '' | tr ' ' '#'; printf '%*s' "$((w - f))" '' | tr ' ' '-'
}

# Aceita epoch (segundos) ou data ISO 8601.
reset_in() {
  [ -n "$1" ] && [ "$1" != null ] || return
  local t d
  if [[ "$1" =~ ^[0-9]+$ ]]; then t=$1; else t=$(date -d "$1" +%s 2>/dev/null) || return; fi
  d=$(( t - $(date +%s) ))
  if [ "$d" -le 0 ]; then echo now
  elif [ "$d" -ge 86400 ]; then echo "$((d/86400))d$(( (d%86400)/3600 ))h"
  elif [ "$d" -ge 3600 ]; then echo "$((d/3600))h$(( (d%3600)/60 ))m"
  else echo "$((d/60))m"; fi
}

human() { if [ "$1" -ge 1000000 ]; then echo "$(( $1 / 1000000 ))M"; elif [ "$1" -ge 1000 ]; then echo "$(( $1 / 1000 ))k"; else echo "$1"; fi; }

fetch() {
  local tok body code now
  tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$cred" 2>/dev/null)
  [ -n "$tok" ] || return 1
  now=$(date -u +%FT%TZ)
  body=$(curl -s -m 5 -w '\n%{http_code}' \
    -H "Authorization: Bearer $tok" \
    -H "anthropic-beta: oauth-2025-04-20" \
    https://api.anthropic.com/api/oauth/usage 2>/dev/null)
  code=${body##*$'\n'}; body=${body%$'\n'*}
  if [ "$code" = 200 ]; then
    jq --arg at "$now" '{fetched_at: $at, five_hour, seven_day, extra_usage}' <<<"$body" >"$cache.tmp" 2>/dev/null \
      && mv -f "$cache.tmp" "$cache"
  else
    # Mantém o último cache bom; sem cache, grava só o erro (o mtime segura o throttle).
    [ -f "$cache" ] || echo '{}' >"$cache"
    jq --arg e "HTTP ${code:-000}" --arg at "$now" '. + {last_error: $e, last_error_at: $at}' "$cache" >"$cache.tmp" 2>/dev/null \
      && mv -f "$cache.tmp" "$cache"
    return 1
  fi
}

# --- Contexto da sessão ---
ctx_str=""
read -r used size pct < <(jq -r '.context_window // {} | [((.current_usage // {}) | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)), (.context_window_size // 0), (.used_percentage // 0)] | @tsv' <<<"$input" 2>/dev/null)
if [ -n "$size" ] && [ "$size" -gt 0 ] 2>/dev/null; then
  if [ "$used" -ge "$ctx_crit" ]; then cc="$red"; elif [ "$used" -ge "$ctx_warn" ]; then cc="$yellow"; else cc="$green"; fi
  ctx_str="${dim}ctx${reset} ${cc}$(human "$used")/$(human "$size") (${pct}%)${reset} ${dim}|${reset} "
fi

# --- Uso 5h/7d ---
read -r p5 r5 p7 r7 < <(jq -r '.rate_limits | select(.five_hour.used_percentage != null) |
  [(.five_hour.used_percentage | floor), (.five_hour.resets_at // "null"),
   (.seven_day.used_percentage // 0 | floor), (.seven_day.resets_at // "null")] | @tsv' <<<"$input" 2>/dev/null)

if [ -z "$p5" ]; then
  need_fetch=1
  if [ -f "$cache" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$cache") ))
    [ "$age" -lt "$min_refetch_sec" ] && need_fetch=0
  fi
  if [ -f "$flag" ]; then need_fetch=1; rm -f "$flag"; fi
  [ "$need_fetch" = 1 ] && fetch

  read -r p5 r5 p7 r7 < <(jq -r 'select(.five_hour.utilization != null) |
    [(.five_hour.utilization | floor), (.five_hour.resets_at // "null"),
     (.seven_day.utilization // 0 | floor), (.seven_day.resets_at // "null")] | @tsv' "$cache" 2>/dev/null)
fi

if [ -z "$p5" ]; then
  printf '%s' "${ctx_str}${dim}usage:loading${reset}"
  exit 0
fi

c5=$(color "$p5"); c7=$(color "$p7")
printf '%s' "${ctx_str}${dim}5h${reset} ${c5}[$(bar "$p5")] ${p5}%${reset} ${dim}($(reset_in "$r5"))${reset} ${dim}|${reset} ${dim}7d${reset} ${c7}[$(bar "$p7")] ${p7}%${reset} ${dim}($(reset_in "$r7"))${reset}"
