---
name: vps-personal
description: "Use when operating the personal Debian VPS."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [vps, infra, self-hosting]
    category: sysadmin
---

# VPS personal (Debian 13)

## When to Use (cuándo usarla)

- Cualquier operación en el VPS: desplegar, revisar puertos, tocar nginx, logs, contenedores.
- Antes de publicar un servicio nuevo o de culpar a un fallo raro.

## Reglas duras

- Publicar solo en la IP tailnet `100.85.208.44`. La pública `148.113.183.234` no se expone nunca.
- No tocar `/etc/systemd/system/docker.service.d/tailscale.conf`: AdGuard lo necesita.
- El nginx del gateway va horneado en la imagen: cualquier cambio en `nginx.conf` exige `cd /home/debian/app/home && ./build.sh`.
- `sudo` sin contraseña para `debian`. Los secretos se muestran como `***` al leerlos, pero están en el fichero.
- Apps en `/home/debian/app/<nombre>`. Índice de servicios en `src/data/services.ts` (Astro).

## Skills sincronizados (repo skills-shared)

Los skills personales (este incluido) viven en el repo `~/skills-shared`
(GitHub: `xhelodev/skills-shared`, privado) y se enlazan por symlink/junction a
Hermes, OpenCode y Claude Code con `install.sh` / `install.ps1`. Editar un skill
enlazado = editar el archivo del repo; al terminar, commit + push, y en las demás
PCs: `git pull && ./install.sh`. No crear skills personales fuera del repo.

## Mapa de servicios

- Gateway `home`: imagen `vps-index`, nginx con `network_mode: host`; proxy a AdGuard `:8443` y Hermes `:8642`/`:9119`.
- Traceway: contenedor `traceway`, `/home/debian/app/traceway`, vhost tailnet `:8445`, volumen `traceway_traceway-data`, tope 2 GB. Sustituyó a SignOz el 18 oct 2026.
- LiveSync (Obsidian): **eliminado 2026-10-26** a petición del usuario (lápida completa en skill `ovh` §8.1); el puerto 5984 y el nodo tailnet `web-livesync` (100.104.63.52) quedaron libres. Lección que sí aplica: los sidecars se llaman `web-*` para quedar al final y diferenciarse de dispositivos reales (renombrados a web-* oct 2026; el rename conserva IP y re-emite cert solo, pero `tailscale serve` puede tardar ~1 min en propagar el DNSName tras `set --hostname`).
- Puertos libres: `8444`, `127.0.0.1:8080`, OTLP `4317`/`4318`.
- Vigilante del índice: cron Hermes `index-servicios` (id `4457fa1e772b`, cada 30m, monitor `~/.hermes/scripts/services-monitor.sh`). Detecta servicios web nuevos en puertos del tailnet/contenedores; el agente agrega la entrada a `src/data/services.ts`, hace `./build.sh` y avisa en Telegram topic `alertas`. Servicios ambiguos (solo loopback, no web, transitorios) los consulta en vez de agregarlos.
- `opencode` ajeno en `127.0.0.1:3000`: ejecuta comandos con `sudo`. Si algo cambia sin explicación, revisar `journalctl` del usuario `debian` y sus `COMMAND=` antes de atribuirlo a un fallo.

Inventario detallado: `references/servicios.md`.

## Operaciones

```bash
docker ps --format '{{.Names}}\t{{.Ports}}\t{{.Status}}'
docker logs -f --tail=100 <contenedor>
cd /home/debian/app/home && ./build.sh   # tras tocar nginx.conf
curl -sI http://100.85.208.44:<puerto>   # comprobar desde el tailnet
journalctl _COMM=sudo --since "1 hour ago" | tail -50
```

## Deploy de servicios nuevos

- Patrón Node/sencillo: Dockerfile `node:24-slim` (o slim de la versión usada), compose con `build: .`, publish `"127.0.0.1:<PUERTO>:3000"`, `HOST: 0.0.0.0` dentro del container, volúmenes para datos/estado y `restart: unless-stopped`.
- Acceso tailnet: cada servicio se publica con un sidecar `tailscale/tailscale` del repo `~/app/ts-urls` (hostname propio, `serve/<nombre>.json` que proxifica a `127.0.0.1:<puerto>`, estado en `state/<nombre>`). La URL queda `https://<nombre>.tail3522d6.ts.net/` con cert válido. Commit + push del repo tras tocarlo. (`tailscale serve --bg` en el nodo principal ya no se usa; `serve status` da vacío.)
- Verificar el serve con `curl --resolve <host.ts.net>:<puerto>:100.85.208.44 https://<host>.ts.net:<puerto>/`: curl contra `127.0.0.1:<puerto_serve>` da connection refused aunque el serve esté bien (solo escucha vía tailscaled, no en loopback).
- Lanzar el contenedor con `docker compose create && docker compose start`, NO `compose up`: el hook de `terminal` marca `compose up` como proceso long-lived y lo bloquea en foreground aunque `-d` devuelva al instante.

## Quirks del host

- Node se gestiona con nvm (`~/.nvm`): NO está en el PATH de sesiones no interactivas (scripts, cron, unit de systemd). Usar `source ~/.nvm/nvm.sh` o la ruta absoluta `~/.nvm/versions/node/<versión>/bin/node`. Default: v24 LTS.
- Chromium local roto (exit 127, falta `libnspr4.so`): `browser_exec` y las capturas fallan; usar `curl`/`web_extract`.
- Docker 29.9.1 activo, ~7 GB RAM: válido para servicios de prueba (comprobar disco con `df -h /` antes de algo grande).
- TTS: el proveedor edge por defecto da 403. Usar `~/.local/bin/edge-tts --voice es-ES-AlvaroNeural`, convertir con `~/.hermes/tools/ffmpeg-9.0.1-linux-x64/bin/ffmpeg` a ogg/opus y enviar como nota de voz.
- Hermes se auto-actualiza vía `vps-updates.sh` (crontab 05:30 diario): `hermes update --check` imprime `Up to date ... (stable vX)` también cuando está al día, así que detectar con `grep -qi 'up to date'`, nunca comparando versiones extraídas. Si hay versión nueva aplica `hermes update --yes` (instalación git; reinicia el gateway por defecto) y avisa por el hilo `updates` con `vX → vY`; si falla, avisa el error.

## Notificaciones Telegram

- Helper: `/usr/local/bin/tg-notify <alias> "texto (HTML)"`. Aliases en `/etc/tg/config.json` (bot @capy_notificator_bot, chat 589215): `alertas` (176817), `ssh` (176821, daemon ssh-notify.service), `seguridad` (176822), `uso` (176840, cuotas IA + vps-uso.sh), `updates` (176841, vps-updates + index-servicios), `github` (raíz 1763, PRs/auditorías).
- Modo de hilo según el separador del valor del alias: `chat:raiz` = `message_thread_id` (hilos legacy); `chat@raiz` = `reply_to_message_id` (hilos nuevos con raíz creada por bot, que Telegram NO acepta como thread). tg-notify resuelve el alias él mismo vía config.json.
- Alertas de servidor (crontab `~/scripts/vps-*.sh`, `disk-cleanup.sh`) van por `tg-notify`. Para avisos nuevos desde Hermes: enviar con `tg-notify` desde el script y dejar el delivery del cron en `local` (el deliver `telegram:chat:thread` de Hermes falla con threads que Telegram no tiene registrados).
- PRs/auditorías de repos: crons `b017e613ba0c` (pr-review-dispatch.sh) y `7f88bf75e629` (repo-audit-dispatch.sh) notifican con `tg-notify github`; delivery en `local`. Los informes completos van como comentarios/issues en GitHub, no por Telegram.
- Alerta cuotas IA: cron Hermes `09243f93eb87` (cada hora, no_agent) → `~/.hermes/scripts/quota-alert.sh` → hilo `uso`; vigila GLM Coding Plan (`api.z.ai/api/monitor/usage/quota/limit`) y OpenCode Go (`opencode.ai/zen/go/v1/usage`, key `OPENCODE_GO_API_KEY` en `.env` de Hermes); avisa solo si alguna ventana ≥ `UMBRAL` (10%). Log: `~/.hermes/scripts/quota-alert.log`.

## Verificación

- `docker ps` muestra `home` y `traceway` arriba.
- El servicio responde en `100.85.208.44` y no en la IP pública.
- Tras un rebuild, el cambio aparece en el HTML o en las cabeceras servidas.
- Si el cambio no aparece: confirmar que se reconstruyó la imagen, no solo el contenedor.
