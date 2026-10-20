# Publishing one prefix through a Cloudflare Tunnel

Use when an emitter cannot join the tailnet (a browser SDK, a CI runner, a third-party host) and one path prefix has to be public. Shape: `cloudflared` (systemd, token, **outbound only**) → ingress path regex → an nginx vhost bound to `127.0.0.1` → the app. No public listener ever appears on the VPS, so `ss -tln` stays clean and `ufw` is untouched.

## Verify a token-managed tunnel before changing anything

1. **Which tunnel does this connector serve?** The token is base64 JSON with `a` (account), `t` (tunnel id) and `s` (secret, never print it):
   `sudo python3 -c "import json,base64;d=json.loads(base64.b64decode(open('/etc/cloudflared/token').read()));print(d['a'],d['t'])"`
   Compare `t` against the UUID in the CNAME target the user quotes (`<uuid>.cfargotunnel.com`). `/etc/cloudflared/` holds only that token for a remotely-managed tunnel — nothing else to read there.
2. **Health:** `curl -s http://127.0.0.1:20241/ready` → `{"status":200,"readyConnections":4,...}`. A connector ID in that body is regenerated per start, not a stable identity.
3. **Live ingress rules:** `sudo journalctl -u cloudflared --no-pager | grep 'Updated to new configuration'`. The last line is the running config as JSON (`ingress` list, `version`). For `config_src: cloudflare` the dashboard owns it and a saved edit lands within seconds as a new `version=`. Log level `info` does not log individual requests — do not grep the journal for your own probes.
4. **Counters:** `curl -s http://127.0.0.1:20241/metrics | grep -E 'total_requests|response_by_code|request_errors|ha_connections'`. `cloudflared_tunnel_total_requests` must bump by exactly the number of probe requests you sent — that is what proves your public curls traverse *this* connector and not another tunnel on the same account. `cloudflared_tunnel_request_errors` counts failures proxying to the origin and must stay 0.
5. **Did it reach the origin?** Diff public against loopback: `curl -sD - https://<host>/<path> | head` vs `curl -sD - http://127.0.0.1:<port>/<path> | head`. Identical headers and body mean the same origin answered. This is the only reliable discriminator:
   - catch-all `http_status:404` from the ingress → empty body, **no** `content-type`;
   - 404 (or 401/302) from nginx or the app → body plus security headers (`content-security-policy`, `x-content-type-options`, …).
   A bare status code cannot tell you whether the request died at the edge or was rejected by the app.
6. **DNS:** `dig` is often not installed. Use `curl -s -H 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=<host>&type=A"` or python `socket.getaddrinfo`. For a proxied (orange-cloud) record DoH returns only the flattened proxy A records — the CNAME target is invisible, so prove the record from the token id plus a request arriving at the origin, not from DNS. Direct UDP queries to the zone's authoritative NS time out from this box; do not spend time there.

## The loopback vhost

```nginx
server {
    listen 127.0.0.1:8446;
    server_name _;
    set_real_ip_from 127.0.0.1;            # cloudflared is the only peer of this socket
    real_ip_header CF-Connecting-IP;        # trustworthy here, so limit_req/limit_conn are per real client
    client_max_body_size 8m;                # size to the payload class that actually flows

    location ^~ /api/otel/ {
        limit_req  zone=otlp burst=200 nodelay;
        limit_conn otlp_perip 32;
        proxy_pass http://127.0.0.1:5080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 60s;
    }

    location / { return 404; }
}
```

- Allowlist by **prefix** (`location ^~`) and keep the dashboard regex a prefix too (`^/api/otel/`) — **trailing slash, no `$`**. An anchored `^/api/otel$` matches only the bare path and sends every subpath to the catch-all 404; from outside that is indistinguishable from nginx not being wired up yet, so read the live pattern out of the journal line and compare it character by character before touching nginx.
- A prefix location makes nginx auto-301 the bare path (`/api/otel` → `/api/otel/`), and that `Location` header carries the internal port (`http://<host>:8446/api/otel/`). Keep the trailing slash in the ingress regex so the bare path never reaches the origin, and add `absolute_redirect off;` to the vhost so no internal port can escape through a redirect.
- The exact allowlist lives in nginx; the dashboard only decides the prefix that is let through. Two places, one meaning each.
- Lower `client_max_body_size` when the payload class changes: a cap inherited from a retired endpoint (25m for rrweb replays, say) is slack the new endpoint does not need.
- Rebuild as usual — the gateway config is baked into the image (`cd /home/debian/app/home && ./build.sh`), and the vhost stays inert until the dashboard regex points at it.

## Sequencing and handoff

The dashboard owns the ingress, the VPS owns nginx, and there is no Cloudflare API token or wrangler on this box — so the ingress edit is the user's, unless they hand you a token scoped to `Cloudflare Tunnel: Edit`. Do it in this order:

1. nginx first, rebuild, verify on loopback (`POST` to the published paths → the app's 401/200; neighbours → 404) and re-check the other vhosts so the rebuild is proven non-destructive.
2. Hand over the dashboard step as one field: Public Hostname `<host>` → path `^<prefix>/` → service `http://127.0.0.1:<port>`, catch-all 404 stays. Give the click path and the value, not prose.
3. State the interim truth: the public path 404s until that lands. Hand over the log line that confirms it (`Updated to new configuration … version=2`).
4. Only after the public probe passes, update the app README and the service card.

**Before retiring a public path, prove nothing uses it:** grep the app directories and read the backend's own request log (the GIN access lines carry method, path, status and client IP; nginx has `access_log` on that vhost by default). Requests you generated yourself during diagnosis are not usage.

## Giving yourself write access, or not needing it

Reading the ingress needs no credential (step 3 above), so an API token buys only the *write*. Say that before asking for one, then pick:

- **Account API token** (Manage account → Account API tokens, `cfat_` prefix; needs Super Admin or API Token Provisioning): durable, not tied to a person, rotatable by any admin. `Cloudflare Tunnel` is on the compatibility matrix, as are DNS and Rulesets, so one token covers ingress plus DNS/rate-limit inspection. Ask for `Account · Cloudflare Tunnel · Edit`, plus `Zone · DNS · Read` and `Zone · WAF · Read`; offer the `· Read` variant for "just tell me what to change".
- **State the scope caveat before they create it:** `Cloudflare Tunnel · Edit` cannot be limited to a single tunnel and lets its holder read any tunnel's token — equivalent to running them. It is per-account power, so IP-restrict it and give it an expiry.
- **IP allowlist: include the IPv6, and check what the edge sees first.** A dual-stack box prefers IPv6 outbound, so a filter listing only the IPv4 rejects every call with 403 while the token itself looks healthy. Confirm with `curl -s https://www.cloudflare.com/cdn-cgi/trace | grep '^ip='` and `curl -s -o /dev/null -w '%{local_ip}\n' https://api.cloudflare.com/client/v4/user/tokens/verify`. Allow the IPv4 `/32` **and** the routed IPv6 `/64`; the IPv6 is typically static in netplan and the IPv4 comes from DHCP, so the IPv4 is the fragile half and a 403 later usually means it moved.
- **Handling:** the token goes into a `chmod 600` file at a path the user chooses, never pasted into chat; read it inside `curl -H "Authorization: Bearer $(cat …)"`. If they paste it into chat anyway, write it to that file, never echo the value back, and say plainly that it is now in the message history and should be revoked once the work is done.
- **Verify the right endpoint — and then verify something real.** A `cfat_` account token answers `{"code":1000,"message":"Invalid API Token"}` on `GET /user/tokens/verify`: that is the wrong verifier for an account token, not a bad token — use `GET /accounts/<account_id>/tokens/verify`. That call passing still proves almost nothing, because it does not evaluate the token's IP condition: the same token returns `403` with `{"code":9109,"message":"Cannot use the access token from location: <ip>"}` on any real resource call from an excluded address. So validate with a real read (`GET /accounts/<id>/cfd_tunnel`), and to separate an allowlist failure from a missing permission repeat it once with `curl -4`: success on IPv4 while the default call fails means the filter, not the policy.
- **Audit any token you are handed before you use it.** `GET /accounts/<account_id>/tokens/<token_id>` returns the policies, resources and `condition`. A token assembled by ticking the permission list can carry hundreds of groups across every zone — Workers Admin, Access Keys, DNS Write, Secrets Store, SSL — while the job needs one. Print the count, state what it grants, and recommend replacing it with `Cloudflare Tunnel · Write` plus the read groups above rather than quietly using it.
- **No permissions at all:** switch that tunnel to locally-managed (`config_src: local`) — ingress becomes a YAML file on the box, every change is an edit plus `systemctl restart cloudflared`. Trade-off to state: the dashboard stops being the source of truth (Public Hostnames goes read-only), moving over means `cloudflared tunnel login` + `tunnel create` and repointing the hostname's CNAME once. Cloudflare recommends remote management; offer this only to someone who dislikes credentials on the box.

## Say this out loud

A public ingest prefix is protected only by the app's own token (401 without it) plus nginx limits and the zone's rate limiting. Ingest endpoints *write* data, so keep both caps tight. If the emitter can send an auth header, prefer the header to a query-string token — nginx records the full request line.

## Quick tunnel (trycloudflare) for a demo window

Same outbound-only shape, no account and no dashboard: `cloudflared` registers an anonymous tunnel and Cloudflare hands back a random `https://<words>.trycloudflare.com` with edge TLS. Nothing appears in the zone, because there is no zone.

```bash
cd ~/.hermes/cache/scratch
pgrep -af cloudflared                      # named tunnel already running? note its PID
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:<port>/login          # 200
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:<port>/api/projects   # 401 = auth is the wall
nohup cloudflared tunnel --url http://127.0.0.1:<port> --no-autoupdate > cloudflared.log 2>&1 &
sleep 10
grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' cloudflared.log | head -1
```

Then probe from the public side, not through the tailnet:

```bash
U=https://<words>.trycloudflare.com
for p in / /login /api/projects; do curl -s -o /dev/null -w "$p %{http_code}\n" "$U$p"; done
curl -s "$U/" | grep -oiE '<title>[^<]*</title>'
```

Expected: app routes `200` with the app's own title, protected API `401`. Anything else (502/530) means the connector has no origin, not that the app needs fixing.

Limits worth stating up front:

- **Random and single-use.** The subdomain cannot be chosen or reissued; restart the process and the URL changes. Dies with the process or a reboot.
- **No controls at the edge.** No allowlist, no Access, no rate limit — only the app's own login. The tunnel exposes exactly one origin (the port you named), never the rest of the tailnet.
- **Some corporate networks block `trycloudflare.com`**; if the viewer is behind such a proxy, switch to a named tunnel.
- **Aim at the loopback port, not the HTTPS vhost.** The gateway's cert is self-signed, so proxying to `https://<host>:8445` needs `--no-tls-verify`; proxying to `http://127.0.0.1:5080` skips the gateway entirely and is the less fragile choice. It also means the demo link does not test your nginx.
- **Long-lived or shared links deserve a wall:** run a small nginx on `127.0.0.1:<spare>` with `auth_basic` + proxy to the app, and point the quick tunnel at that port.

Teardown: `pkill -x cloudflared` kills the quick tunnel **and** any token-managed service, so use the PID when one is running. Prove it from outside — the URL must answer **530** (edge, no connector); a `1033` body from the edge means the same thing. The tunnel's own log is not proof.
