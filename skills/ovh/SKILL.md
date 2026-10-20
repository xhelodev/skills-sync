---
name: ovh
description: Opera y diagnostica el VPS personal "ovh" (nodo Tailscale vps-9c2aefdf, 100.85.208.44, SSH alias `ovh`) y todo lo que corre ahí dentro - OpenCode (servidor y CLI), Hermes (gateway y dashboard), Traceway, AdGuard Home, Docker, el gateway nginx/landing de Astro y Tailscale. Úsala para chequear estado, leer logs, reiniciar o actualizar servicios, y para saber qué NO tocar. Dispara con "ovh", "vps", "vps-9c2aefdf", "100.85.208.44", "ssh ovh", "opencode serve", "servidor de opencode", "hermes", "traceway", "adguard", "tailnet", "puerto 3000/5080/8443/8445/9119". NO aplica a Cloudflare, Wrangler ni al opencode de la máquina local.
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
  `network_mode: host`, escucha **solo** `100.85.208.44` (nunca `0.0.0.0`).
- Landing Astro (índice de tarjetas): `/home/debian/app/home/src/data/services.ts`.
- Certificado Tailscale: `/home/debian/app/home/certs/{cert,key}.pem`; se renueva con
  `/home/debian/app/home/renew-cert.sh` (y recarga nginx).
- Reconstruir tras editar: `/home/debian/app/home/build.sh` (build + up + ps).

Al agregar un servicio: usar el procedimiento de la skill `tailscale-service`
(elegir puerto tailnet libre, publicar en `127.0.0.1`, vhost en `nginx.conf`,
tarjeta en `services.ts`, `build.sh`, verificar).

### 6.1 Re-exponer OpenCode por el tailnet (puerto 8080)

Hoy opencode es solo loopback. Si el usuario pide alcanzarlo por el tailnet, el
puerto **8080 está libre** (verificado) y es el que usaba el registro viejo. Pasos:

1. **No hay que tocar opencode**: su server ya escucha en `127.0.0.1:3000`.

2. **Vhost en `/home/debian/app/home/nginx.conf`** (opencode usa SSE/websocket:
   hacen falta los headers de upgrade y timeouts largos):

   ```nginx
   # OpenCode (puerto 8080)
   server {
       listen 100.85.208.44:8080 ssl;
       http2 on;
       server_name vps-9c2aefdf.tail3522d6.ts.net;

       ssl_certificate     /etc/nginx/certs/cert.pem;
       ssl_certificate_key /etc/nginx/certs/key.pem;

       location / {
           proxy_pass http://127.0.0.1:3000;
           proxy_http_version 1.1;
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection "upgrade";
           proxy_set_header Host $http_host;          # conserva :8080
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
           proxy_read_timeout 3600s;
           proxy_send_timeout 3600s;
           proxy_buffering off;                        # SSE/streaming
       }
   }
   ```

3. **Tarjeta en `/home/debian/app/home/src/data/services.ts`**:

   ```ts
   {
     name: "OpenCode",
     description: "Servidor de agentes · sesiones y TUI web",
     href: "https://{host}:8080",
     badge: ":8080",
     icon: "⌨️",
     color: "violet",
     external: true,
   },
   ```

4. **Reconstruir**: `/home/debian/app/home/build.sh`.

5. **Verificar**:

   ```bash
   ssh ovh 'ss -lntp | grep 8080'                                  # solo 100.85.208.44
   ssh ovh 'curl -sk -o /dev/null -w "%{http_code}\n" https://100.85.208.44:8080/'
   ```

6. **Actualizar el registro de puertos** del skill `tailscale-service` (§8 de acá
   lista el estado real).

> Ojo: cualquiera en el tailnet podría alcanzarlo; el server sigue protegido por el
> password de `service.json`. Nunca lo expongas fuera del tailnet.

## 7. Tailnet, firewall y qué NO hacer

- **Prohibido**: `tailscale funnel`, túneles públicos, port-forwarding en el
  router/cloud, o bind a `0.0.0.0`/IP pública. ufw solo permite `tailscale0` + `41641/udp`.
- **Única excepción pública aprobada (18 oct 2026)**: la ingesta RUM web de Traceway
  `https://otel.carpincho.dev/api/report` → `127.0.0.1:8446` vía Cloudflare Tunnel
  (solo salida). `/api/otel`, el dashboard `:8445` y todo lo demás siguen tailnet-only.
  **No ampliar esa excepción.**
- **OpenCode NO está publicado en el gateway** (se quitó del índice a propósito);
  hoy es solo `127.0.0.1:3000` y se llega por túnel SSH. Para publicarlo, ver §6.1.
  El **§8 es la fuente de verdad** del uso de puertos; ante dudas, verificá contra
  `home/nginx.conf` antes de dar un puerto por libre.
- No borres `opencode.db`, `service.json` ni `auth.json`.
- Si un pedido implica exponer algo a internet público: **detenerse y consultar**.

## 8. Registro de puertos (estado real)

| Puerto | Qué | Backend | Alcance |
| --- | --- | --- | --- |
| 53 | AdGuard DNS | bind directo `100.85.208.44` | tailnet |
| 443, 80 | Landing Astro `/` | `127.0.0.1` (nginx `home`) | tailnet |
| 3000 | OpenCode server | `127.0.0.1:3000` | **loopback** (túnel SSH) |
| 3001 | AdGuard UI | contenedor adguardhome | loopback (vía gateway en 8443) |
| 5080 | Traceway | contenedor traceway | loopback (vía gateway en 8445) |
| 8080 | *(libre)* | OpenCode `127.0.0.1:3000` | **disponible**: puerto reservado para publicar opencode (§6.1) |
| 8443 | AdGuard UI | → `127.0.0.1:3001` | tailnet (nginx) |
| 8445 | Traceway UI/OTLP | → `127.0.0.1:5080` | tailnet (nginx) |
| 8446 | Traceway RUM | → `127.0.0.1:5080` | **público, solo `/api/report`** (CF Tunnel) |
| 8642 | Hermes API `/v1` | `127.0.0.1:8642` | tailnet (nginx) |
| 9119 | Hermes Dashboard | `127.0.0.1:9119` | tailnet (nginx) |

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
