---
name: ovh
description: Opera y diagnostica el VPS personal "ovh" (nodo Tailscale vps-9c2aefdf, 100.85.208.44, SSH alias `ovh`) y todo lo que corre ahí dentro - OpenCode (servidor y CLI), Hermes (gateway y dashboard), Traceway, AdGuard Home, Docker, el gateway nginx/landing de Astro y Tailscale. Úsala para chequear estado, leer logs, reiniciar o actualizar servicios, y para saber qué NO tocar. Dispara con "ovh", "vps", "vps-9c2aefdf", "100.85.208.44", "ssh ovh", "opencode serve", "servidor de opencode", "hermes", "traceway", "adguard", "tailnet", "puerto 3000/5080/8081/8446/9119", "sidecar", "web-adguard", "mate-tv". NO aplica a Cloudflare, Wrangler ni al opencode de la máquina local.
---

# Operar el VPS `ovh` (vps-9c2aefdf)

Servidor personal en OVH, accesible **solo por Tailscale**. Acá corre el stack
completo: OpenCode, Hermes, Traceway, AdGuard Home, un gateway nginx y la landing.
Esta skill explica cómo llegar, cómo chequear y operar cada pieza, y las reglas
que no se rompen.

> Regla de oro: **tailnet-only**. Nada se expone a internet público. La única
> excepción aprobada está documentada abajo. Ver también la skill
> `tailscale-service` para agregar servicios nuevos.

## 1. Acceso (y la trampa del PATH)

```bash
ssh ovh                       # alias ya definido en ~/.ssh/config
ssh ovh 'comando remoto'      # one-liner
```

| Dato | Valor |
| --- | --- |
| Alias SSH | `ovh` → puerto **10022**, usuario **debian** |
| IP Tailscale | **100.85.208.44** (`vps-9c2aefdf.tail3522d6.ts.net`) |
| IP pública | `148.113.183.234` (solo para el túnel SSH, no expone servicios) |
| SO | Debian 13 (`6.12.x`), disco ~74 G |

**Trampa #1 — `opencode: command not found`.** El binario vive en
`~/.opencode/bin` y solo se agrega al `PATH` en `.bashrc`, que **no** se evalúa en
shells no interactivos (`ssh ovh 'opencode ...'` y también `ssh ovh 'bash -lc ...'`
fallan). **Usá siempre la ruta absoluta** o exportá el PATH primero:

```bash
ssh ovh '$HOME/.opencode/bin/opencode --version'
ssh ovh 'export PATH=$HOME/.opencode/bin:$PATH; opencode --version'
```

Lo mismo con Hermes: su binario es
`/home/debian/.hermes/hermes-agent/.hermes/bin/hermes` (no está en el PATH).

**Trampa #2 — MagicDNS no resuelve desde el propio VPS.** Dentro del VPS,
`vps-9c2aefdf.tail3522d6.ts.net` **no** resuelve (`getent hosts` no devuelve nada).
Para probar el gateway desde ahí, usá la IP `100.85.208.44` y `curl -k` (el
certificado es para el hostname, no para la IP).

**Trampa #3 — secretos en los logs.** El server de opencode loguea la contraseña
en claro (`journalctl --user -u opencode-serve` y `~/.local/share/opencode/log/opencode.log`
imprimen `server password ...`), y `~/.config/opencode/service.json` la guarda.
**Nunca la copies a un mensaje, ticket o commit.** Enmascarala al reportar.

## 2. Chequeo rápido (un solo comando)

```bash
ssh ovh "bash -s" < ~/.config/opencode/skills/ovh/scripts/ovh-status.sh
```

`ovh-status.sh` es de **solo lectura** y resume host, opencode, Hermes, Docker y el
gateway, enmascarando secretos. Es el primer comando a correr ante "algo no anda en
el VPS". Si el skill se invoca desde el VPS, el script está en
`~/.config/opencode/skills/ovh/scripts/ovh-status.sh`.

## 3. OpenCode (lo principal)

| Dato | Valor |
| --- | --- |
| Binario | `/home/debian/.opencode/bin/opencode` (v2.x) |
| Server | `opencode serve --hostname 127.0.0.1 --port 3000` |
| Unit systemd | **user** `opencode-serve.service` (en `~/.config/systemd/user/`) |
| Datos | `~/.local/share/opencode/` |

### Salud

```bash
ssh ovh 'systemctl --user status opencode-serve --no-pager | head -12'
ssh ovh 'curl -s -o /dev/null -w "GET / -> %{http_code}\n" http://127.0.0.1:3000/'
ssh ovh 'ss -lntp | grep 3000'
```

Esperado: unit `active (running)`, `GET / -> 200`, y escucha en `127.0.0.1:3000`
(nunca `0.0.0.0`). Ojo: además del server del unit, `opencode` levanta un
**servicio de fondo por directorio** (`opencode serve --service`) en un puerto
loopback efímero; suele verse con `ps aux | grep opencode`.

### Operar

```bash
ssh ovh 'systemctl --user restart opencode-serve'   # aplicar config/upgrade
ssh ovh 'systemctl --user stop opencode-serve'
ssh ovh 'systemctl --user start opencode-serve'
ssh ovh '$HOME/.opencode/bin/opencode service status'   # alternativa vía CLI
```

Si editaste la unit: `systemctl --user daemon-reload` antes del restart. La unit
está `disabled` pero symlinkeada en `default.target.wants`, así que arranca con
`user@1000.service`; si querés fijarla explícito: `systemctl --user enable opencode-serve`.

### Actualizar

```bash
ssh ovh '$HOME/.opencode/bin/opencode upgrade'
ssh ovh '$HOME/.opencode/bin/opencode --version'
ssh ovh 'systemctl --user restart opencode-serve'
```

### CLI útil

```bash
ssh ovh '$HOME/.opencode/bin/opencode debug paths'    # rutas (data/config/cache/state)
ssh ovh '$HOME/.opencode/bin/opencode debug config'   # fuentes de configuración
ssh ovh '$HOME/.opencode/bin/opencode debug agents'   # agentes disponibles
ssh ovh '$HOME/.opencode/bin/opencode models'         # modelos
ssh ovh '$HOME/.opencode/bin/opencode stats'          # uso
ssh ovh '$HOME/.opencode/bin/opencode session list'   # sesiones del proyecto
ssh ovh '$HOME/.opencode/bin/opencode api /global/health'  # petición al server
```

### Datos y logs

- DB: `~/.local/share/opencode/opencode.db` (+ `-shm`/`-wal`; el WAL puede crecer,
  se compacta solo al cerrar limpio).
- Log: `~/.local/share/opencode/log/opencode.log`.
- Otros: `shell/`, `tool-output/`, `repos/`, `auth.json`.

```bash
ssh ovh 'tail -50 ~/.local/share/opencode/log/opencode.log'
ssh ovh 'journalctl --user -u opencode-serve -n 100 --no-pager'
```

### Llegar a la web UI desde el laptop

Hoy no está publicada en el gateway, así que se llega por túnel:

```bash
ssh -L 3000:127.0.0.1:3000 ovh     # luego abrir http://localhost:3000
```

También: `opencode --server http://localhost:3000` para conectar el TUI.
Si querés publicarla de forma permanente en el tailnet, ver §6.1.

## 4. Hermes

| Servicio | Unit | Escucha | Endpoint |
| --- | --- | --- | --- |
| Gateway | `hermes-gateway.service` | `127.0.0.1:8642` | API OpenAI-compatible `/v1` (exige **bearer**) |
| Dashboard | `hermes-dashboard.service` | `127.0.0.1:9119` | Web UI |

```bash
ssh ovh '/home/debian/.hermes/hermes-agent/.hermes/bin/hermes status'
ssh ovh 'systemctl --user status hermes-gateway --no-pager | head -12'
ssh ovh 'journalctl --user -u hermes-gateway -n 100 --no-pager'
ssh ovh 'systemctl --user restart hermes-dashboard'
```

`HERMES_HOME=/home/debian/.hermes`. Un `401` en `/v1/models` es **normal** (falta
la API key). **`hermes-gateway` es el gateway de mensajería**: reiniciarlo corta
conversaciones en curso; avisar antes salvo que esté caído.

## 5. Traceway y AdGuard Home (Docker)

```bash
ssh ovh 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
ssh ovh 'docker logs --tail 100 traceway'
ssh ovh 'cd /home/debian/app/traceway && docker compose ps'
```

- **Traceway** (`/home/debian/app/traceway/docker-compose.yml`): UI+ingesta en
  `127.0.0.1:5080`, imagen fijada por digest, `mem_limit: 2g` y
  `DUCKDB_MEMORY_LIMIT=1GB` a propósito (evita OOM bajo ingesta). No subas esos límites sin medir.
- **AdGuard Home** (`/home/debian/adguard/docker-compose.yml`): UI en
  `127.0.0.1:3001`, y **DNS en el puerto 53** bindeado a `100.85.208.44`.
- **`catcore`** y **`nextcloud`** tienen compose pero están **parados** (no aparecen en `docker ps`).
- Compose disponible: `docker compose` v5.x.

## 6. Gateway nginx + landing (índice)

- Gateway: `/home/debian/app/home/nginx.conf`, contenedor **`home`** con
  `network_mode: host`. Hoy escucha `100.85.208.44:80`, `100.85.208.44:443` y
  `127.0.0.1:8446` (RUM de Traceway) — nunca `0.0.0.0`. Los antiguos vhosts
  8443/8445 ya no existen: los servicios se publican con sidecars `ts-*` (ver §8).
- Landing Astro (índice de tarjetas): `/home/debian/app/home/src/data/services.ts`.
- Certificado Tailscale: `/home/debian/app/home/certs/{cert,key}.pem`; se renueva con
  `/home/debian/app/home/renew-cert.sh` (y recarga nginx).
- Reconstruir tras editar: `/home/debian/app/home/build.sh` (build + up + ps).

Al agregar un servicio: usar el procedimiento de la skill `tailscale-service`
(elegir puerto tailnet libre, publicar en `127.0.0.1`, vhost en `nginx.conf`,
tarjeta en `services.ts`, `build.sh`, verificar).

### 6.1 Re-exponer OpenCode por el tailnet

> **ACTUALIZADO 2026-10-25:** el puerto **8080 ya NO está libre** — lo ocupa el
> panel de mate-tv (`127.0.0.1:8080`, público vía `tv.chelo.xyz`). Si algún día
> se quiere publicar OpenCode, elegir un puerto tailnet libre consultando el
> §8 y `home/nginx.conf` (que ya solo escucha 80/443 y 127.0.0.1:8446), o
> mejor, seguir el patrón actual de **sidecar Tailscale** (`ts-<servicio>`)
> que usan adguard/traceway/hermes. El ejemplo histórico del vhost en
> 8080 quedó obsoleto y se retiró de esta skill para evitar colisiones.

> Ojo: cualquiera en el tailnet podría alcanzarlo; el server sigue protegido por el
> password de `service.json`. Nunca lo expongas fuera del tailnet.

## 7. Tailnet, firewall y qué NO hacer

- **Prohibido**: `tailscale funnel`, túneles públicos, port-forwarding en el
  router/cloud, o bind a `0.0.0.0`/IP pública. ufw solo permite `tailscale0` + `41641/udp`.
- **Excepciones públicas aprobadas**: (1, 18 oct 2026) la ingesta RUM web de Traceway
  `https://otel.carpincho.dev/api/report` → `127.0.0.1:8446` vía Cloudflare Tunnel
  (solo salida); (2) el panel de mate-tv `https://tv.chelo.xyz` → `127.0.0.1:8080`
  (verificado 2026-10-25, tunnel activo). Todo lo demás sigue tailnet-only; `/api/otel`
  se alcanza por el sidecar `ts-traceway` (nodo `web-traceway`).
  **No ampliar estas excepciones.**
- **OpenCode NO está publicado en el gateway** (se quitó del índice a propósito);
  hoy es solo `127.0.0.1:3000` y se llega por túnel SSH. Para publicarlo, ver §6.1.
  El **§8 es la fuente de verdad** del uso de puertos; ante dudas, verificá contra
  `home/nginx.conf` antes de dar un puerto por libre.
- No borres `opencode.db`, `service.json` ni `auth.json`.
- Si un pedido implica exponer algo a internet público: **detenerse y consultar**.

## 8. Registro de puertos (estado real, verificado 2026-10-25)

> La arquitectura de publicación cambió: nginx `home` ya solo sirve la landing
> (80/443) y el RUM de Traceway (127.0.0.1:8446). El resto de servicios se
> publica con **sidecars Tailscale por servicio** (contenedores `ts-*` con
> identidad propia en el tailnet): `ts-adguard` → nodo `web-adguard`
> (100.86.45.71), `ts-hermes-api` → `web-hermes-api` (100.72.215.102),
> `ts-hermes-dash` → `web-hermes-dash` (100.97.166.4), `ts-traceway` → `web-traceway`
> (100.111.61.44), `ts-catcore` → `web-catcore` (100.106.180.64) y `ts-mate-tv`
> (red de mate-tv). Los vhosts 8443 y 8445 **ya no existen**.

| Puerto | Qué | Backend | Alcance |
| --- | --- | --- | --- |
| 25 | SMTP local (postfix) | `127.0.0.1:25` | loopback, interno |
| 53 | AdGuard DNS | bind directo `100.85.208.44` | tailnet |
| 80, 443 | Landing Astro `/` | nginx `home` (network host) | tailnet |
| 1080 | proxy SOCKS `warp` | contenedor warp → `127.0.0.1:1080` | loopback |
| 3000 | OpenCode server | `127.0.0.1:3000` | **loopback** (túnel SSH) |
| 3001 | AdGuard UI | contenedor adguardhome → `127.0.0.1:3001` | sidecar `ts-adguard` (`web-adguard`) |
| 4000 | Catcore UI (notas, raíz) | contenedor catcore-web → `127.0.0.1:4000` | sidecar `ts-catcore` (`web-catcore`) |
| 4001 | Catcore API `/api/v1` | contenedor catcore-api → `127.0.0.1:4001` | sidecar `ts-catcore`, handler `/api/` |
| 4002 | Catcore MCP (http) | contenedor catcore-mcp → `127.0.0.1:4002` | loopback, sin publicar |
| 5080 | Traceway UI/OTLP | contenedor traceway → `127.0.0.1:5080` | sidecar `ts-traceway` (`web-traceway`) |
| 8080 | panel mate-tv (contenedor `mate-tv-mate-tv-1`) | bind `0.0.0.0:8080` (ufw bloquea desde internet) | **público** solo vía `tv.chelo.xyz` (Cloudflare Tunnel) |
| 8081 | API del panel mate-tv | `127.0.0.1:8081` | loopback (commit `eb70b7b` del repo lo movió desde la IP tailnet) |
| 8446 | Traceway RUM | nginx `home` → `127.0.0.1:5080` | **público, solo `/api/report`** (CF Tunnel `otel.carpincho.dev`) |
| 8642 | Hermes API `/v1` | `127.0.0.1:8642` | sidecar `ts-hermes-api` (`web-hermes-api`) |
| 9118 | `ts-dash-proxy` (nginx:alpine) | `127.0.0.1:9118` | loopback, interno |
| 9119 | Hermes Dashboard | `127.0.0.1:9119` | sidecar `ts-hermes-dash` (`web-hermes-dash`) |

### 8.1 Obsidian LiveSync (eliminado 2026-10-26)

> Desmontado a petición del usuario: contenedores (`livesync`, `ts-livesync`,
> `livesync-cli`), stack `~/app/obsidian-livesync`, repo `~/Dev/obsidian-livesync`,
> vault `~/segundo-cerebro`, skill `note-taking/obsidian` y el backup
> `~/backups/obsidian-20261025-234758` fueron borrados. No intentar reinstalarlo
> ni buscar sus rutas; el puerto 5984 y el nodo tailnet `web-livesync` quedaron libres.

## 9. Troubleshooting

| Síntoma | Chequeo / arreglo |
| --- | --- |
| `opencode: command not found` por SSH | Usá `$HOME/.opencode/bin/opencode` (ver §1). |
| `:3000` no responde | `systemctl --user status opencode-serve`; si está caído, `journalctl --user -u opencode-serve -n 50` y `systemctl --user restart opencode-serve`. |
| Puerto 3000 ocupado | `ss -lntp \| grep 3000` → ¿es el PID esperado? Matá sólo el proceso huérfano, no el del unit. |
| `opcode.db-wal` muy grande | Es normal con tráfico; se compacta al cerrar limpio. No borres archivos con el server corriendo. |
| Cambio en la unit no aplica | `systemctl --user daemon-reload` + `restart`. |
| No arranca al boot | `systemctl --user enable opencode-serve` (y `loginctl enable-linger debian`). |
| Hermes `/v1` da 401 | Falta la API key (bearer). Es esperado, no es una falla. |
| Traceway muere por OOM | Verificá `DUCKDB_MEMORY_LIMIT`/`mem_limit`; no los subas sin medir. |
| HTTPS roto / cert vencido | `/home/debian/app/home/renew-cert.sh`. |
| Servicio nuevo inalcanzable por tailnet | Falta el vhost en `nginx.conf` + tarjeta en `services.ts` + `build.sh`; dentro de contenedores MagicDNS **no** resuelve (usar `extra_hosts`). |
