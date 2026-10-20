# Servicios del VPS

| Servicio | Puerto | Ruta | Notas |
|---|---|---|---|
| Gateway `home` | red host (nginx) | `/home/debian/app/home` | Imagen `vps-index`; `nginx.conf` horneado; rebuild con `./build.sh` |
| AdGuard | 8443 | contenedor `adguardhome` | Proxy del gateway; depende de `docker.service.d/tailscale.conf` |
| Hermes | 8642, 9119 | `~/.hermes` | API y gateway; proxy del gateway |
| Traceway | 8445 (tailnet) | `/home/debian/app/traceway` | APM OTLP; volumen `traceway_traceway-data`; tope 2 GB |
| OTLP | 4317, 4318 | — | Libres, para instrumentación |
| `opencode` (tercero) | 127.0.0.1:3000 | — | Ejecuta con `sudo`; revisar `journalctl` |
| `catcore`, `landing`, `nextcloud` | — | `/home/debian/app/<nombre>` | Directorios presentes; sin contenedor activo |
| Libres | 8444, 127.0.0.1:8080 | — | Disponibles |

Regla: todo se publica en `100.85.208.44`, nunca en la IP pública.
