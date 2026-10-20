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
import json, os, subprocess, sys

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

for s in servers:
    name = s.get("name", "?")
    raw_env = s.get("env") or {}
    missing = [k for k, v in raw_env.items()
               if isinstance(v, str) and v.startswith("$") and v[1:] not in os.environ]
    if missing:
        print(f"MCP ⚠ {name}: faltan variables {missing} — expórtalas y re-ejecuta")
        continue
    if s.get("transport") == "http":
        cmd = ["claude", "mcp", "add", "--transport", "http", name, s["url"]]
    else:
        env_flags = []
        for k, v in raw_env.items():
            resolved = os.environ[v[1:]] if isinstance(v, str) and v.startswith("$") else v
            env_flags += ["-e", f"{k}={resolved}"]
        cmd = ["claude", "mcp", "add", *env_flags, name, "--", s["command"], *s.get("args", [])]
    subprocess.run(["claude", "mcp", "remove", "-s", "user", name], capture_output=True)
    r = subprocess.run(cmd, capture_output=True, text=True)
    mark = "✓" if r.returncode == 0 else "✗"
    print(f"MCP {mark} claude: {name}" + (f" · {r.stderr.strip()}" if r.returncode else ""))
    if s.get("transport") != "http":
        print(f"     · OpenCode: sección \"mcp\" de opencode.jsonc (manual por ahora)")
    print(f"     · Hermes: `hermes config set` (manual por ahora)")
PY
