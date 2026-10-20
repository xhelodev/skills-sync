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

| Puerto tailnet | Servicio       | Backend interno   | Notas                     |
| -------------- | -------------- | ----------------- | ------------------------- |
| 443            | Landing        | estático (nginx `home`) | índice Astro; `/notas` y `/api` **no existen** hoy |
| 8080           | *(libre)*      | —                 | reservado/deprecated para OpenCode: hoy **no tiene vhost**, el server escucha solo en `127.0.0.1:3000` (túnel SSH). Ver skill `ovh` §6.1 para publicarlo |
| 9119           | Hermes         | 127.0.0.1:9119    | dashboard                 |
| 8642           | Hermes API     | 127.0.0.1:8642    | API OpenAI-compatible `/v1`; requiere `API_SERVER_KEY` (bearer); nativo systemd, no contenedor |
| 8443           | AdGuard Home   | 127.0.0.1:3001    | UI                        |
| 8445           | Traceway       | 127.0.0.1:5080    | UI + ingesta OTLP (`/api/otel/v1/*`); dashboard |
| 8446           | Traceway RUM   | 127.0.0.1:5080    | **loopback, NO tailnet**: única excepción pública aprobada (18 oct 2026), `https://otel.carpincho.dev/api/report` solo, vía Cloudflare Tunnel (`cloudflared`, solo salida). El resto del vhost devuelve 404 |
| 53             | AdGuard DNS    | bind directo a 100.85.208.44 | udp/tcp          |

> El registro se desvía del `nginx.conf` real: la landing es **estática** (nginx
> sirve los archivos, no hay upstream `:4000/4001`; `catcore` está parado) y
> **OpenCode no tiene vhost** (el 8080 quedó sin uso). El stack de Nextcloud
> (`/home/debian/app/nextcloud`, `127.0.0.1:8081`) también está **parado**.
> Verificar contra `home/nginx.conf` antes de dar por libre un puerto. El skill
> `ovh` documenta el estado real de todo el stack del VPS.

## Notas de red

- **Contenedor → IP Tailscale está bloqueado por ufw** (solo pasa por puertos
  publicados por Docker). Si una app dentro de un contenedor necesita llamar a su
  propia URL pública (p.ej. Nextcloud Office/Collabora, WOPI callbacks), hay que
  permitir la subred Docker hacia el puerto, nunca hacia internet:
  `sudo ufw allow from 172.16.0.0/12 to 100.85.208.44 port <PUERTO> proto tcp`
- Dentro de contenedores **MagicDNS no resuelve**; mapear el hostname con
  `extra_hosts: ["vps-9c2aefdf.tail3522d6.ts.net:100.85.208.44"]`.
- Con puertos **no estándar**, usar `proxy_set_header Host $http_host;` (incluye
  el puerto). `$host` lo omite y apps que generan URLs propias (p.ej. Collabora)
  las construyen mal (sin `:PUERTO`).

## Proyectos

- `/home/debian/app/home/` — gateway nginx + landing Astro.
- `/home/debian/app/nextcloud/` — stack Nextcloud (`.env` 0600, datos bind en `./data`).
- `/home/debian/app/catcore/`, `/home/debian/adguard/` — otros servicios.
