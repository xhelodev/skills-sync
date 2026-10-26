# Servicios del VPS

> Actualizado 2026-10-25. La publicación por vhosts del gateway nginx quedó
> mayormente sustituida por **sidecars Tailscale por servicio** (contenedores
> `ts-*` con nodo propio en el tailnet). Registro completo y fuente de verdad:
> skill `ovh` §8.

| Servicio | Puerto | Ruta | Notas |
|---|---|---|---|
| Gateway `home` (nginx) | 100.85.208.44:80/443 + 127.0.0.1:8446 | `/home/debian/app/home` | Solo landing Astro y RUM de Traceway; `nginx.conf` horneado; rebuild con `./build.sh` |
| AdGuard | DNS 53 (bind tailnet), UI 127.0.0.1:3001 | contenedor `adguardhome` | UI vía sidecar `ts-adguard` → nodo `web-adguard` (100.86.45.71) |
| Hermes API | 127.0.0.1:8642 | `~/.hermes` | Vía sidecar `ts-hermes-api` → `web-hermes-api` (100.72.215.102) |
| Hermes Dashboard | 127.0.0.1:9119 (+ proxy interno 9118) | `~/.hermes` | Vía sidecar `ts-hermes-dash` → `web-hermes-dash` (100.97.166.4) |
| Traceway | 127.0.0.1:5080 | `/home/debian/app/traceway` | Vía sidecar `ts-traceway` → `web-traceway` (100.111.61.44); RUM público solo `/api/report` por CF Tunnel (8446); tope 2 GB |
| Catcore | UI 127.0.0.1:4000, API 127.0.0.1:4001, MCP 127.0.0.1:4002 | `/home/debian/app/catcore` | Vía sidecar `ts-catcore` → `web-catcore` (100.106.180.64); handler `/api/` → `4001/api`. Auto-deploy desde GitHub |
| Hermes Admin | web 127.0.0.1:8444, API 127.0.0.1:8445 | `/home/debian/app/hermes-web` | Vía sidecar `ts-hermes-admin` → `web-hermes-admin` (100.68.234.18); handlers `/api/`+`/health/`+`/ws/v1` → 8445, resto → 8444. Requiere `api/.env` (credenciales dashboard). Auto-deploy desde GitHub |
| mate-tv (panel) | panel `0.0.0.0:8080` (ufw bloquea desde internet); API `127.0.0.1:8081` | `/home/debian/Dev/mate-tv` | Panel público vía `tv.chelo.xyz` (CF Tunnel); API solo loopback desde commit `eb70b7b`; sidecar `ts-mate-tv`. Auto-deploy desde GitHub |
| warp | 127.0.0.1:1080 (SOCKS) | contenedor `warp` | Solo loopback |
| opencode | 127.0.0.1:3000 | — | Unit de usuario `opencode-serve` (`systemctl --user`); NO usa sudo; revisar `journalctl --user` |
| OTLP | 4317, 4318 | — | Libres, para instrumentación |
| `catcore`, `landing`, `nextcloud`, `ts-urls` | — | `/home/debian/app/<nombre>` | Directorios presentes; `catcore`/`landing`/`nextcloud` sin contenedor activo |
| Libres | 4317/4318 (OTLP) | — | Verificar contra skill `ovh` §8 y `ss -tlnp` antes de usar (8080/8081 mate-tv, 8444/8445 hermes-admin, 3000 opencode, 3001 AdGuard) |

Regla: todo se publica en `100.85.208.44` o por sidecar tailnet, nunca en la IP pública.
