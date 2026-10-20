#!/usr/bin/env bash
# skillsync — instala los skills de este repo en Hermes / OpenCode / Claude Code
# Uso:  ./install.sh                          (autodetecta máquina por hostname -s)
#       SKILLSYNC_MACHINE=vps ./install.sh    (forzar etiqueta de máquina)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACHINE="${SKILLSYNC_MACHINE:-$(hostname -s)}"

# raíz de skills de cada herramienta (clave, ruta)
TARGETS=(
  "hermes:$HOME/.hermes/skills"
  "opencode:$HOME/.config/opencode/skills"
  "claude:$HOME/.claude/skills"
)

echo "skillsync · máquina='$MACHINE' · repo='$REPO'"

installed=0
for skill_dir in "$REPO"/skills/*/; do
  name="$(basename "$skill_dir")"
  if [[ -f "$skill_dir/.machines" ]]; then machines="$(tr -d ' \n' < "$skill_dir/.machines")"; else machines='*'; fi
  targets_file="$skill_dir/.targets"
  if [[ -f "$targets_file" ]]; then wanted="$(tr -d ' \n' < "$targets_file")"; else wanted='hermes,opencode,claude'; fi

  # ¿corresponde a esta máquina?
  match=0
  IFS=',' read -ra tags <<< "$machines"
  for t in "${tags[@]}"; do
    [[ "$t" == "*" || "$t" == "$MACHINE" ]] && match=1
  done
  if [[ $match -ne 1 ]]; then
    echo "· $name → omitido (solo para: $machines)"
    continue
  fi

  # ¿va a esta herramienta?
  for entry in "${TARGETS[@]}"; do
    tool="${entry%%:*}"
    root="${entry#*:}"
    if [[ ",$wanted," != *",$tool,"* ]]; then continue; fi
    if [[ ! -d "$root" ]]; then
      echo "· $name → $tool no instalado ($root), salto"
      continue
    fi
    target="$root/$name"
    if [[ -L "$target" ]]; then
      rm -f "$target"
    elif [[ -e "$target" ]]; then
      bak="$target.bak-$(date +%Y%m%d-%H%M%S)"
      mv "$target" "$bak"
      echo "  · backup: $name → $(basename "$bak")"
    fi
    ln -s "$skill_dir" "$target"
    echo "✓ $name → $target"
    installed=$((installed+1))
  done
done
echo "Skills enlazados: $installed"

# ---------------- MCP ----------------
# Fuente: mcp/servers.json (SIN secretos: valores "$VAR" se resuelven del entorno local).
# v1 aplica automáticamente a Claude Code; OpenCode y Hermes quedan documentados como paso manual.
python3 - "$REPO/mcp/servers.json" <<'PY'
import json, os, re, shutil, subprocess, sys

path = sys.argv[1]
if not os.path.exists(path):
    sys.exit(0)
try:
    servers = json.load(open(path)).get("servers", [])
except Exception as e:
    print(f"MCP: ⚠ servers.json inválido: {e}"); sys.exit(0)

if not servers:
    print("MCP: 0 servidores en servers.json — nada que aplicar")
    sys.exit(0)

claude = shutil.which("claude")
if claude is None:
    print(f"MCP: ⚠ claude no está en PATH — {len(servers)} servidor(es) sin aplicar")
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
        print(f"MCP ⚠ {name}: faltan variables {missing} — expórtalas y re-ejecuta")
        continue
    headers, missing_h = {}, []
    for k, v in (s.get("headers") or {}).items():
        expanded, miss = expand(v)
        headers[k] = expanded
        missing_h += [f"{k}=${m}" for m in miss]
    if missing_h:
        print(f"MCP ⚠ {name}: faltan variables {missing_h} — expórtalas y re-ejecuta")
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
    mark = "✓" if r.returncode == 0 else "✗"
    detail = (r.stderr or r.stdout).strip().replace("\n", " ")
    print(f"MCP {mark} claude: {name}" + (f" · {detail}" if r.returncode else ""))
    if s.get("transport") != "http":
        print(f"     · OpenCode: sección \"mcp\" de opencode.jsonc (manual por ahora)")
    print(f"     · Hermes: `hermes config set` (manual por ahora)")
PY
