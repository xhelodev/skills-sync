---
name: claude-code
description: Úsala para delegar tareas de código a Claude Code CLI (instalado en ~/.local/bin/claude, ≥2.1.x, autenticado con Claude Pro del usuario). Dispara con "usar Claude Code", "delegar a claude", "claude -p", "que lo haga Claude", "Claude Pro", "revisar con Claude". Cubre modo print (-p), permisos, sesiones, tmux interactivo y review de PRs.
---

# Delegar a Claude Code

Claude Code está instalado en `~/.local/bin/claude` (si `which claude` falla, usa la ruta absoluta). Auth por OAuth de Claude Pro: el límite es de suscripción, no de API key. Verifica con `claude --version` (≥2.1.x).

## Reglas

1. **Tareas acotadas → modo print (`-p`), nunca el TUI.** Un comando, resultado, exit. Sin diálogos.
   ```bash
   cd /ruta/repo && claude -p "Tarea concreta" --allowedTools "Read,Edit,Bash(git *)" --max-turns 10
   ```
   Siempre acotar: `--max-turns` (solo existe en `-p`) y `--allowedTools` al mínimo que la tarea necesita. Correr desde el directorio del repo.
2. **Permiso de escritura:** por defecto `-p` pide permiso y sin TUI no hay quién responda → falla o no escribe. Usar `--permission-mode acceptEdits` (acepta edits del directorio, lo demás sigue preguntando) o incluir las tools necesarias en `--allowedTools`. `--dangerously-skip-permissions` SOLO en worktree desechable, y avisarle al usuario de que se usó.
3. **Salida JSON para automatizar:** `--output-format json` devuelve `{result, session_id, num_turns, total_cost_usd, subtype}`. `subtype: "success"` = OK; `error_max_turns` = faltaron turnos.
4. **Continuar sesiones:** `--continue` (última del directorio) o `--resume <session_id>`. Requiere estar en el mismo directorio.
5. **Review por pipe (sin gastar turnos):**
   ```bash
   git diff main...feature | claude -p "Revisá este diff: bugs, seguridad, tests faltantes. Sé específico con archivo y línea." --max-turns 1
   ```
6. **Interactivo solo si hay iteración real:** dentro de tmux.
   ```bash
   tmux new-session -d -s claude-work -x 140 -y 40
   tmux send-keys -t claude-work 'cd /ruta/repo && claude' Enter
   sleep 5 && tmux send-keys -t claude-work Enter   # diálogo de trust (una vez por dir)
   tmux capture-pane -t claude-work -p -S -50        # monitorear
   ```
   Leer el prompt antes de mandar Enter; nunca aprobar a ciegas por timer. Al terminar: `tmux kill-session -t claude-work`.
7. **Smoke test antes de una sesión larga:**
   ```bash
   claude -p 'Respond with exactly: CLAUDE_SMOKE_OK'
   ```

## Trampas

- `--max-turns` y `--max-budget-usd` son solo de `-p`; en tmux interactivo se ignoran.
- `/exit` no aplica en `-p` (no hay slash commands en print mode).
- `--bare` requiere `ANTHROPIC_API_KEY` (acá se usa OAuth: no usar `--bare`).
- Contexto >70% degrada la calidad: sesiones largas, mejor partir en tareas nuevas.
- Si un comando de Claude tira error de rate limit/sobrecarga, reintentar con `--fallback-model haiku`.
- No matar una sesión tmux "lenta" sin antes mirar `capture-pane`: puede estar trabajando.

## Verificación

- Smoke test: output contiene `CLAUDE_SMOKE_OK`.
- Tareas de código: archivos cambiados esperados + tests pasan.
- Reportar siempre: qué hizo Claude, qué cambió, costo si se usó `--output-format json`.
