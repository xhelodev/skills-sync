---
name: tailscale-service
description: Use ONLY when adding, exposing or "levantando" a service (Docker or local) on the Tailscale VPS, choosing a tailnet port, or editing the nginx gateway. Triggers on "servicio", "levantar", "puerto", "tailscale", "nginx gateway", "services.ts", "home/nginx.conf", "100.85.208.44", "vps-9c2aefdf.tail3522d6.ts.net", "publico", "internet", "funnel". Enforces tailnet-only access and registering every new tailnet port in the landing index.
---

# Exponer servicios solo por Tailscale (VPS vps-9c2aefdf)

## Reglas obligatorias

1. **NUNCA exponer a internet público.** Todo servicio vive únicamente dentro del
   tailnet. Prohibido `tailscale funnel`, túneles públicos, port-forwarding en el
   router/cloud, o bind a `0.0.0.0`/IP pública. Solo `tailscale serve` o bind
   directo a la IP Tailscale `100.85.208.44`.
2. **Registrar siempre en el índice.** Cada vez que se levanta un servicio
   accesible por un puerto del tailnet, ese servicio DEBE quedar agregado en la
   landing (`/home/debian/app/home/src/data/services.ts`) y en `home/nginx.conf`.
   La tarea no termina hasta reconstruir el gateway (`build.sh`).

Si alguna petición implica exponer hacia internet público, **detenerse y
consultar** antes de hacerlo.

## Arquitectura actual

- Nodo Tailscale: `vps-9c2aefdf.tail3522d6.ts.net` — IP `100.85.208.44`.
- Gateway: contenedor **`home`** (`/home/debian/app/home/`), `network_mode: host`,
  nginx que escucha **solo en `100.85.208.44`** (nunca `0.0.0.0`).
- TLS: certificado de `tailscale cert` en `/home/debian/app/home/certs/`
  (`cert.pem`, `key.pem`). Renovación: `/home/debian/app/home/renew-cert.sh`.
- Apps internas: publican **solo en `127.0.0.1:<puerto>`**, nunca directo a la red.
- Firewall: ufw solo permite `tailscale0`.

## Prohibido (anti-patrones)

- `ports: ["8081:80"]`, `-p 8081:80` o cualquier bind a `0.0.0.0` / IP pública.
- `tailscale funnel` o `tailscale serve` con funnel habilitado.
- Exponer la base de datos o Redis fuera de la red interna de Docker.
- Abrir puertos "temporalmente" para probar. Probar siempre por el tailnet o por loopback.

## Pasos al agregar un servicio

1. **Elegir un puerto tailnet libre** (ver registro abajo; no reusar).
2. **Docker/compose del servicio**: publicar solo en loopback, p.ej.
   `ports: ["127.0.0.1:8081:80"]`. PostgreSQL/MariaDB/Redis sin `ports` (solo red interna).
3. **Agregar un `server` en `/home/debian/app/home/nginx.conf`**:
   ```nginx
   # <Servicio> (puerto <PUBLIC_PORT>)
   server {
       listen 100.85.208.44:<PUBLIC_PORT> ssl;
       http2 on;
       server_name vps-9c2aefdf.tail3522d6.ts.net;

       ssl_certificate     /etc/nginx/certs/cert.pem;
       ssl_certificate_key /etc/nginx/certs/key.pem;

       location / {
           proxy_pass http://127.0.0.1:<LOCAL_PORT>;
           proxy_http_version 1.1;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
           proxy_set_header X-Forwarded-Host $host;
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection "upgrade";
           proxy_read_timeout 3600s;
           proxy_send_timeout 3600s;
       }
   }
   ```
   Si el servicio acepta subidas grandes, sumar `client_max_body_size 10g;`.
4. **Registrar en `/home/debian/app/home/src/data/services.ts`** (obligatorio):
   ```ts
   {
     name: "<Nombre>",
     description: "<descripción>",
     href: "https://{host}:<PUBLIC_PORT>",
     badge: ":<PUBLIC_PORT>",
     icon: "<emoji>",
     color: "sky", // sky | emerald | amber | violet | rose
     external: true,
   },
   ```
   Para rutas internas (mismo :443), usar `href: "/ruta"` y `health: "/ruta"`.
5. **Reconstruir el gateway**: `/home/debian/app/home/build.sh`.
6. **Verificar**:
   - `ss -tlnp | grep -E ':<PUBLIC_PORT>|<LOCAL_PORT>'` → solo IP tailscale / 127.0.0.1.
   - El servicio responde en `https://vps-9c2aefdf.tail3522d6.ts.net:<PUBLIC_PORT>`.
   - La landing muestra la tarjeta (índice con `cache-control: no-cache`).
7. **Actualizar el registro de puertos de esta skill.**

## Registro de puertos

> **Reescrito 2026-10-25 tras auditoría.** Estado verificado con `ss -tlnp`,
> `docker ps`, `tailscale serve status` y `tailscale status`. Fuente de verdad
> completa: skill `ovh` §8.

**Vía gateway nginx `home`** (bind `100.85.208.44`):

| Puerto tailnet | Servicio | Backend interno | Notas |
| -------------- | -------- | --------------- | ----- |
| 443            | Landing  | estático (nginx `home`) | índice Astro; `/notas` y `/api` **no existen** hoy |
| 80             | Landing (redirect a 443) | estático | |
| 53             | AdGuard DNS | bind directo a 100.85.208.44 | udp/tcp |
| 8446           | Traceway RUM | 127.0.0.1:5080 | **loopback, NO tailnet**: excepción pública, `https://otel.carpincho.dev/api/report` vía Cloudflare Tunnel (solo salida) |

**Vía sidecars Tailscale** (cada servicio con nodo propio en el tailnet; ya no
hay vhosts 8443/8445 en el gateway):

| Nodo tailnet | Servicio | Backend interno | Notas |
| ------------ | -------- | --------------- | ----- |
| `web-adguard` (100.86.45.71) | AdGuard UI | 127.0.0.1:3001 | sidecar `ts-adguard` |
| `web-traceway` (100.111.61.44) | Traceway UI+OTLP | 127.0.0.1:5080 | sidecar `ts-traceway` |
| `web-hermes-api` (100.72.215.102) | Hermes API | 127.0.0.1:8642 | sidecar `ts-hermes-api`; requiere `API_SERVER_KEY` (bearer) |
| `web-hermes-dash` (100.97.166.4) | Hermes Dashboard | 127.0.0.1:9119 | sidecar `ts-hermes-dash` |
| `web-catcore` (100.106.180.64) | Catcore (notas) | 127.0.0.1:4000 UI, 4001 API | sidecar `ts-catcore`; handler `/api/` → `4001/api` |
| `web-hermes-admin` (100.68.234.18) | Hermes Admin (cliente web de Hermes) | 127.0.0.1:8444 web, 8445 API | sidecar `ts-hermes-admin`; handler `/ws/v1` → `8445/ws/v1` (websocket); requiere `api/.env` completo para arrancar |
| `ts-mate-tv` | mate-tv | red `mate-tv_default` | panel en `0.0.0.0:8080` (público vía `tv.chelo.xyz`, CF Tunnel; ufw bloquea 8080 desde internet) y API en `127.0.0.1:8081` (loopback, commit `eb70b7b` lo movió desde la IP tailnet) |
| `web-docmost` (100.66.43.20) | Docmost (wiki colaborativa) | 127.0.0.1:3100 | sidecar `ts-docmost`; stack en `/home/debian/app/docmost` (Postgres+Redis solo red interna) |

**Loopback / otros**:

| Puerto | Servicio | Notas |
| ------ | -------- | ----- |
| 3000 | OpenCode server | túnel SSH; sin publicar a propósito |
| 1080 | proxy SOCKS `warp` | solo loopback |
| 9118 | `ts-dash-proxy` (nginx:alpine) | interno |
| 8080 / 8081 | panel / API de mate-tv | **NO libres** |

> **Eliminado del registro (verificado inexistente el 25 oct 2026):** Lotion
> (8443), Linkbio (8444/8447), Zammad (8448) — no hay contenedores, directorios
> en `/home/debian/app/`, `tailscale serve` config ni listeners. El antiguo
> acceso a AdGuard/Traceway por 8443/8445 del gateway también desapareció.
> El stack de Nextcloud (`/home/debian/app/nextcloud`) sigue **parado**.
> Verificar contra `home/nginx.conf` y `ss -tlnp` antes de dar por libre un
> puerto. El skill `ovh` documenta el estado real de todo el stack del VPS.

## Notas de red

- **Contenedor → IP Tailscale está bloqueado por ufw** (solo pasa por puertos
  publicados por Docker). Si una app dentro de un contenedor necesita llamar a su
  propia URL pública (p.ej. Nextcloud Office/Collabora, WOPI callbacks), hay que
  permitir la subred Docker hacia el puerto, nunca hacia internet:
  `sudo ufw allow from 172.16.0.0/12 to 100.85.208.44 port <PUERTO> proto tcp`
- Dentro de contenedores **MagicDNS no resuelve**; mapear el hostname con
  `extra_hosts: ["vps-9c2aefdf.tail3522d6.ts.net:100.85.208.44"]`.
- hermes-admin (api) llama al dashboard en otro nodo: `extra_hosts:
  ["web-hermes-dash.tail3522d6.ts.net:100.97.166.4"]` + regla ufw
  `allow from 172.16.0.0/12 to 100.97.166.4 port 443 proto tcp` (contenedor →
  tailnet, nunca hacia internet).
- hermes-admin: las rutas de API (`/api/`, `/health/`, `/ws/v1`) van **directo
  al Fastify (8445) por el sidecar**, NO vía rewrites de Next (los rewrites
  rompieron POST por el proxy: 500). Websockets solo suben por HTTP/1.1: con
  h2 (negociado por defecto) el upgrade da 404, un navegador wss funciona
  normal. Probar con `curl --http1.1`.
- Con puertos **no estándar**, usar `proxy_set_header Host $http_host;` (incluye
  el puerto). `$host` lo omite y apps que generan URLs propias (p.ej. Collabora)
  las construyen mal (sin `:PUERTO`).
- `tailscale serve` con handler de **path** quita el prefijo al proxificar:
  `/api/ → http://127.0.0.1:4001` llega al backend como `/v1/...`. Para
  conservarlo, repetir el path en el destino: `"Proxy": "http://127.0.0.1:4001/api"`.
  (Los handlers de puerto `:PUERTO` sí preservan el path completo.)

## Proyectos

- `/home/debian/app/home/` — gateway nginx + landing Astro.
- `/home/debian/app/nextcloud/` — stack Nextcloud (`.env` 0600, datos bind en `./data`).
- `/home/debian/app/catcore/`, `/home/debian/adguard/` — otros servicios.
