#!/usr/bin/env python3
"""Aplica mcp/servers.json a Claude Code (scope user). Sin secretos en el repo:
los valores "$VAR" se resuelven del entorno local; si falta una variable, ese
servidor se omite con aviso. OpenCode (opencode.jsonc) y Hermes (hermes config
set) quedan como paso manual por ahora.
"""
import json
import os
import re
import shutil
import subprocess
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "mcp/servers.json"
if not os.path.exists(path):
    sys.exit(0)
try:
    servers = json.load(open(path)).get("servers", [])
except Exception as e:
    print(f"MCP: WARN servers.json inválido: {e}")
    sys.exit(0)

if not servers:
    print("MCP: 0 servidores en servers.json — nada que aplicar")
    sys.exit(0)

claude = shutil.which("claude")
if claude is None:
    print(f"MCP: WARN claude no está en PATH — {len(servers)} servidor(es) sin aplicar")
    sys.exit(0)


def resolve(raw):
    """Devuelve (valores, faltantes). '$VAR' se toma del entorno local."""
    values, missing = {}, []
    for k, v in (raw or {}).items():
        if isinstance(v, str) and v.startswith("$"):
            if v[1:] in os.environ:
                values[k] = os.environ[v[1:]]
            else:
                missing.append(k)
        else:
            values[k] = str(v)
    return values, missing


def expand(text):
    """Sustituye $VAR en cualquier posición (ej: 'Bearer $TOKEN')."""
    missing = []

    def repl(m):
        name = m.group(1)
        if name not in os.environ:
            missing.append(name)
            return m.group(0)
        return os.environ[name]

    return re.sub(r"\$([A-Za-z_][A-Za-z0-9_]*)", repl, str(text)), missing


for s in servers:
    name = s.get("name", "?")
    env, missing = resolve(s.get("env"))
    if missing:
        print(f"MCP WARN {name}: faltan variables {missing} — expórtalas y re-ejecuta")
        continue
    headers, missing_h = {}, []
    for k, v in (s.get("headers") or {}).items():
        expanded, miss = expand(v)
        headers[k] = expanded
        missing_h += [f"{k}=${m}" for m in miss]
    if missing_h:
        print(f"MCP WARN {name}: faltan variables {missing_h} — expórtalas y re-ejecuta")
        continue

    # Orden importa: `-e` y `-H` son variádicos en `claude mcp add`.
    # Van después del nombre (y `-e` antes de `--`), nunca antes del nombre.
    if s.get("transport") == "http":
        cmd = [claude, "mcp", "add", "-s", "user", "--transport", "http", name, s["url"]]
        for k, v in headers.items():
            cmd += ["-H", f"{k}: {v}"]
    else:
        env_flags = [f for k, v in env.items() for f in ("-e", f"{k}={v}")]
        cmd = [claude, "mcp", "add", "-s", "user", name, *env_flags, "--",
               s["command"], *s.get("args", [])]

    subprocess.run([claude, "mcp", "remove", "-s", "user", name], capture_output=True)
    r = subprocess.run(cmd, capture_output=True, text=True)
    mark = "OK" if r.returncode == 0 else "FALLA"
    detail = (r.stderr or r.stdout).strip().replace("\n", " ")
    print(f"MCP {mark} claude: {name}" + (f" · {detail}" if r.returncode else ""))
    if s.get("transport") != "http":
        print('     · OpenCode: sección "mcp" de opencode.jsonc (manual por ahora)')
    print("     · Hermes: `hermes config set` (manual por ahora)")
