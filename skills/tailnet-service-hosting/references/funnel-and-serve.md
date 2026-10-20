# Reaching a tailnet-only service from outside the tailnet

Depth for Always-on rule 2. The gateway binds only the tailnet IP, so "exposing the ingest path" on this host means one of the two options below — never a public bind.

## Option A — Tailscale on the emitter (default)

Install Tailscale on the machine that sends data, tag it (e.g. `tag:otel-sender`), and grant that tag access to the single port it needs in the tailnet ACL. Nothing becomes public, there is no bandwidth ceiling, and the endpoint is the ordinary tailnet URL (`https://<host>:<port>/<path>`). Works on Linux/Windows/macOS, as a Docker sidecar, and on mobile. If several machines sit behind one network, one node advertises the subnet and the rest come along.

## Option B — Tailscale Funnel, scoped to one path

`funnel` is the only mechanism that accepts traffic from devices *not* in the tailnet, and it is per-path:

```bash
tailscale funnel --bg --set-path=/api/otel/ --https=10000 http://127.0.0.1:5080
tailscale serve status        # what is actually mounted
```

Constraints that decide whether it is even possible on a given host:

- **Ports:** Funnel listens only on **443, 8443 and 10000**, and only over TLS on the tailnet DNS name. If nginx already holds 443 and something else holds 8443 on the tailnet IP, Funnel must use 10000 — check `ss -tln` before promising anything.
- **Serve vs Funnel on one port:** a port ends up private (`serve`) or public (`funnel`) according to which command touched it last; they cannot coexist.
- **Prerequisites:** valid HTTPS certificates for the tailnet (already true when the gateway uses a `tailscale cert`), MagicDNS, and the `funnel` node attribute in the tailnet policy file (the CLI offers to add it on first enable).
- **Path matching:** mount points behave like Go `ServeMux`; a trailing slash (`/api/otel/`) covers the subtree, a bare prefix does not. Whatever you mount is world-visible, so expose one narrow path, never `/`.
- **No auth layer.** Funnel has no allowlist, no basic auth, no IP restriction — the application's own token is the only gate. A public ingest path is then protected by a long-lived bearer token copied into emitters, and anyone who finds the hostname can still spend CPU and bandwidth with junk POSTs.
- **Bandwidth:** Funnel traffic goes through Tailscale's relays under non-configurable limits; it is meant for low volume (webhooks, a handful of emitters), not for a firehose of traces.

**Verify the prefix, not just the reachability.** Whether the Funnel proxy forwards the request *with* the mounted prefix or strips it decides whether the backend sees `/api/otel/v1/traces` or `/v1/traces` (a 404). One `curl` against the Funnel URL settles it; if it strips the prefix, remap rather than rewriting the application.

## What not to do

- Do not bind the service, or a new vhost, to `0.0.0.0` "just for the emitters".
- Do not treat "it is behind nginx with TLS" as public exposure: it is still tailnet-only, which is the point.
- Do not reach for Funnel before asking whether the emitter can simply run Tailscale — for machines you own, a phone, a container or a CI runner, that is the cheaper answer with no bandwidth cap.
