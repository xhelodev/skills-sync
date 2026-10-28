---
name: pi
description: Úsala para delegar tareas de código a pi CLI (~/.local/bin/pi, ≥1.4.0, ejecución directa sin permisos ni max-turns). Dispara con "usar pi", "delegar a pi", "pi -p", "que lo haga pi", "mandale a pi". Cubre modo print, acotación por timeout, recorte de contexto, sesiones, sandbox por flags, solo-lectura, paralelismo con worktrees y parseo de salida json.
---

# Delegar a pi (ejecución directa)

pi está instalado en `~/.local/bin/pi` (si `which pi` falla, usa la ruta absoluta). Verificar con `pi --version` (≥1.4.0). Auth por API key en `~/.pi/agent/auth.json`; provider/model default en `~/.pi/agent/settings.json`.

## Diferencia clave con Claude Code

- **Sin gates de permiso**: `bash`/`edit`/`write` ejecutan directo, también en `-p`. No existe `--permission-mode` ni `--allowedTools`. La red de seguridad es **verificar después** (`git diff` + tests), no negociar antes.
- **Sin `--max-turns`**: la acotación es por prompt concreto con criterio de éxito + `timeout` del shell.
- **Contexto inicial pesado**: carga todos los skills instalados (decenas). `-ns -nc -ne` recorta para tareas mecánicas.
- **Piensa largo por defecto**: `--thinking off` (o `low`) acelera y abarata tareas mecánicas.

## Reglas

1. **Tarea acotada → modo print con timeout.** Un comando, criterio de éxito explícito, resultado:
   ```bash
   cd /ruta/repo && timeout 600 pi -p "Hacer pasar npm test sin tocar tests. Criterio: npm test exit 0." --thinking low -ns
   ```
   Correr siempre desde el dir del repo. El criterio de éxito va EN el prompt ("debe pasar X", "el diff debe tocar solo Y").
2. **Sandbox por flags** (no hay permisos: esto es lo único):
   - `-xt write,edit` → solo lectura (análisis, reviews, logs)
   - `-t read,bash` → toolbox mínima
   - `-nt` → sin tools
   - `-na` (`--no-approve`) → ignorar extensiones/skills locales del proyecto (usar en código desconocido)
3. **Sesiones**: `--no-session` one-shot (default en scripts); `-c` continúa la última del dir; `--session-id <id>` reusa o crea una sesión fija (ideal para ejecución por pasos). `-r` abre TUI: NUNCA en scripts.
4. **Capturar salida**:
   - Humano: modo `text` default → `| tail -20`.
   - Automatizado: `--mode json` es un stream NDJSON; la respuesta final es el último `message_end` con `role=assistant`. jq puede no estar instalado → parser python3 (abajo). El costo va en `.message.usage.cost.total`.
5. **Verificar SIEMPRE después**: `git status`, `git diff`, tests. Reportar qué hizo pi, qué cambió, y costo si se usó json.
6. **No lanzar pi sobre cambios sin commitear** que no quieras tocar: escribe sin preguntar. Si hay trabajo en curso: `git stash` primero, o `-xt write,edit`.

## Parser de salida json

```bash
cd /ruta/repo && timeout 600 pi -p "tarea" --mode json | python3 -c '
import sys, json
last = None
for line in sys.stdin:
    try: e = json.loads(line)
    except: continue
    if e.get("type") == "message_end" and e.get("message", {}).get("role") == "assistant":
        last = e
if last:
    m = last["message"]
    print("".join(b.get("text", "") for b in m.get("content", []) if b.get("type") == "text"))
    print("COST:", m.get("usage", {}).get("cost", {}).get("total"))
'
```

## Recetas

### Ejecución por pasos (ejecutar un plan)

Un `pi -p` por paso, mismo `--session-id` para contexto acumulativo, verificar entre pasos:

```bash
cd /ruta/repo
SID=plan-$(date +%s)
timeout 900 pi -p "Paso 1: ... Criterio: ..." --session-id "$SID" && git diff --stat
timeout 900 pi -p "Paso 2: ... Criterio: ..." --session-id "$SID" && git diff --stat
```

Si un paso no cumple su criterio: no seguir. Revisar `git diff`, y re-delegar pegando el diff en el prompt o corregir a mano.

### Tasks típicas de código

```bash
# Arreglar tests
timeout 900 pi -p "Hacer pasar npm test. No modificar tests, solo el código. Criterio: npm test exit 0." --thinking low -ns && npm test

# Refactor acotado
timeout 900 pi -p "Extraer la lógica de X de a.ts a b.ts sin cambiar comportamiento. Criterio: tests siguen pasando." --thinking low && npm test

# Escribir tests
timeout 900 pi -p "Escribir tests para src/foo.ts cubriendo casos borde. Criterio: npx vitest run exit 0." --thinking low
```

### Solo-lectura / análisis

```bash
# Review de diff por pipe (sin gastar lectura de repo)
git diff main...feature | timeout 120 pi -p "Revisá este diff: bugs, seguridad, tests faltantes. Sé específico con archivo y línea." -xt write,edit --thinking off --no-session

# Análisis de logs
timeout 300 pi -p "Errores en app.log de las últimas 24h: resumí causa probable con líneas de evidencia" -xt write,edit -ns --thinking low
```

### Paralelismo (N tasks en worktrees)

```bash
for t in fix-a fix-b fix-c; do
  git worktree add "/tmp/wt-$t" -b "feat-$t"
  ( cd "/tmp/wt-$t" && timeout 900 pi -p "Task $t: ... Criterio: ..." -ns -ne --thinking low > "/tmp/pi-$t.log" 2>&1 ) &
done
wait
# verificar cada uno antes de mergear: git -C /tmp/wt-$t diff --stat + tests
```

Cada corrida paga el context inicial completo: `-ns -ne` acá es obligatorio, no opcional.

## Costo de la cadena agente→pi (medido)

Delegar en cadena (ej. OpenCode→pi) NUNCA ahorra tokens. Medido 2026-10-28, misma tarea (branding page) y mismo modelo (glm-5.3): **pi directo ~8.6k tokens/$0.017** (contexto base ~2k, primer turno input=196) < **OpenCode directo ~64k/$0.010** (contexto ~18k/turno) < **OpenCode→pi ~133k/$0.032**. El ahorro de pi es su contexto delgado y solo existe corriendo SOLO (Hermes→pi); en cadena lo sepulta el contexto del orquestador. Causas: el orquestador re-paga su contexto en cada turno extra, y pi suma su propio arranque + regenerar output encima. La cadena solo vale para aislar ejecución, sandbox o paralelismo — nunca por economía. En USD pi directo puede costar más pese a usar menos tokens (tarifas Z.ai vs OpenRouter; el output facturable pesa). Tokens por corrida: OpenCode en SQLite ~/.local/share/opencode/opencode.db (tabla message → data.tokens); pi en ~/.pi/agent/sessions/<dir>/*.jsonl (message_end assistant → usage.cost.total). Costo del skill mismo (mismo prompt, skill pi visible vs oculto): con skill ~133k (6+3 turnos, skill carga + verificación obligatoria = +2 turnos del orquestador) vs sin skill ~90k (4+2) → skill = +48% tokens en tareas triviales; lo que compra es disciplina (flags -ns -ne --thinking low para pi y verificación post-ejecución), no ahorro.

## Trampas

- Sin `--max-turns` ni presupuesto: task abierta = puede dar vueltas largo. Acotar por prompt + `timeout`; si el timeout mata el proceso, la sesión queda y se retoma con `--session-id`.
- Primer arranque lento (descubre skills, extensiones, MCP): `-ns -ne --no-mcp` para tareas mecánicas.
- Sin `--fallback-model`: si rate limit o sobrecarga, reintentar con `--model <otro>`.
- `-r` abre TUI de selección: nunca en scripts (usar `--session-id` o `-c`).
- jq puede no estar: parsear con python3.
- `-nc` omite AGENTS.md/CLAUDE.md del repo: no usar si el repo depende de esas instrucciones.
- Contexto >70% degrada la calidad: tasks largas, mejor partir en sesiones nuevas (`--session-id` nuevo).

## Smoke test

```bash
timeout 120 pi -p 'Respond with exactly: PI_SMOKE_OK' --no-session --thinking off
```

OK si el output contiene `PI_SMOKE_OK`.

## Verificación

- Tasks de código: archivos cambiados esperados + tests pasan + `git diff` revisado.
- Reportar siempre: qué hizo pi, qué cambió, costo si se usó `--mode json`.
