#!/usr/bin/env bash
# ovh-status.sh — Diagnóstico de solo lectura del VPS "ovh" (vps-9c2aefdf).
#
# Pensado para ejecutarse EN el VPS, normalmente así desde el laptop:
#   ssh ovh "bash -s" < ~/.config/opencode/skills/ovh/scripts/ovh-status.sh
#
# NO modifica nada: solo consulta estado. Enmascara secretos.
# Salida: informe legible en stdout.

set -uo pipefail

OC="$HOME/.opencode/bin/opencode"
DATA="$HOME/.local/share/opencode"
# OJO: MagicDNS NO resuelve desde el propio VPS, por eso usamos la IP.
# El cert es para el hostname del tailnet => -k en los checks HTTPS del gateway.
TS_IP="100.85.208.44"

hr() { printf '\n=== %s ===\n' "$1"; }

# Código HTTP sin seguir redirecciones (para ver el código inicial del vhost).
http_code() {
  local c
  c=$(curl -sk -o /dev/null -m 6 -w '%{http_code}' "$1" 2>/dev/null) || true
  case "$c" in ""|000) c="sin respuesta" ;; esac
  printf '%s' "$c"
}

# Puerto en escucha (y proceso dueño, si lo podemos ver).
port_line() {
  ss -lntp 2>/dev/null | awk -v p=":$1\$" '$4 ~ p {
    proc = $6; sub(/^users:\(\(/, "", proc); sub(/\)\)$/, "", proc)
    printf "  %-24s %s\n", $4, proc
  }' || true
}

unit_state() {
  local a e
  a=$(systemctl --user is-active "$1" 2>/dev/null); a=${a:-desconocido}
  e=$(systemctl --user is-enabled "$1" 2>/dev/null); e=${e:-desconocido}
  printf '%s/%s' "$a" "$e"
}

hr "HOST"
printf '  hostname : %s\n' "$(hostname)"
printf '  tailnet  : %s\n' "$(tailscale ip -4 2>/dev/null | head -1 || echo '?')"
printf '  uptime   : %s\n' "$(uptime -p 2>/dev/null || uptime)"
printf '  disco /  : %s\n' "$(df -h / | awk 'NR==2 {print $3" usados de "$2" ("$5"), "$4" libres"}')"
printf '  mem      : %s\n' "$(free -h | awk 'NR==2 {print $3" usados de "$2}')"

hr "OPENCODE"
if [ -x "$OC" ]; then
  printf '  version  : %s\n' "$("$OC" --version 2>/dev/null | head -1)"
  printf '  sesiones : %s (en el proyecto actual)\n' "$("$OC" session list 2>/dev/null | grep -c . )"
else
  printf '  version  : NO ENCONTRADO en %s\n' "$OC"
fi
printf '  unit     : %s\n' "$(unit_state opencode-serve.service)"
printf '  :3000    : HTTP %s\n' "$(http_code http://127.0.0.1:3000/)"
port_line 3000
if [ -f "$DATA/opencode.db" ]; then
  printf '  db       : %s (wal %s)\n' \
    "$(du -h "$DATA/opencode.db" 2>/dev/null | cut -f1)" \
    "$(du -h "$DATA/opencode.db-wal" 2>/dev/null | cut -f1 || echo '-')"
fi

hr "HERMES"
printf '  gateway  : %s\n' "$(unit_state hermes-gateway.service)"
printf '  dashboard: %s\n' "$(unit_state hermes-dashboard.service)"
printf '  :9119    : HTTP %s\n' "$(http_code http://127.0.0.1:9119/)"
printf '  :8642/v1 : HTTP %s (401 = ok: exige bearer)\n' "$(http_code http://127.0.0.1:8642/v1/models)"
port_line 9119
port_line 8642

hr "DOCKER"
if command -v docker >/dev/null 2>&1; then
  docker ps --format '  {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo "  (docker sin permisos o caído)"
else
  echo "  docker no instalado"
fi

hr "GATEWAY / TAILNET"
printf '  :443   landing : HTTP %s (esperado 200)\n' "$(http_code "https://$TS_IP/")"
printf '  :8443  adguard : HTTP %s (esperado 302 -> login)\n' "$(http_code "https://$TS_IP:8443/")"
printf '  :8445  traceway: HTTP %s (esperado 200)\n' "$(http_code "https://$TS_IP:8445/")"
printf '  :9119  hermes  : HTTP %s (esperado 200)\n' "$(http_code "https://$TS_IP:9119/")"
printf '  :8642  /v1     : HTTP %s (esperado 401: exige bearer)\n' "$(http_code "https://$TS_IP:8642/v1/models")"
printf '  :8446  RUM     : HTTP %s (loopback, POST)\n' \
  "$(curl -s -o /dev/null -m 6 -w '%{http_code}' -X POST "http://127.0.0.1:8446/api/report" -d '{}' 2>/dev/null || echo 'sin respuesta')"
for p in 8443 8445 8642 9119 5080 3001 8446; do port_line "$p"; done
printf '  funnel         : %s\n' "$(tailscale funnel status 2>&1 | head -1)"
printf '  ufw            : %s\n' "$(sudo -n ufw status 2>/dev/null | head -1 || echo '(sudo -n no disponible)')"

hr "LOGS (ERROR/WARN recientes, secretos enmascarados)"
if [ -f "$DATA/log/opencode.log" ]; then
  grep -E 'level=(ERROR|FATAL|WARN|WARNING)' "$DATA/log/opencode.log" 2>/dev/null \
    | tail -5 \
    | cut -c1-200 \
    | sed -E 's/(password|token|api[_-]?key|secret)[=: ]+[^ "\\]+/\1=***REDACTED***/Ig' \
    | sed 's/^/  /'
  [ "${PIPESTATUS[0]}" -eq 0 ] || echo "  (sin ERROR/WARN recientes)"
else
  echo "  (sin $DATA/log/opencode.log)"
fi

printf '\n'
