---
name: skillsync
description: Instalar, sincronizar y auditar skills entre agentes (Claude Code, OpenCode, Cursor, Codex, Hermes, pi) y máquinas. Usar cuando el usuario pida instalar, sincronizar, chequear o actualizar skills, o mencione skillsync, skills-shared o third-party.
---

# skillsync — skills entre agentes y máquinas

Los skills personales viven en `~/skills-shared` (repo privado) y se ven en todos
los agentes por symlink. Los de terceros los instala `npx skills` y quedan
registrados en `third-party.yaml`.

## Qué correr según el pedido

| Pedido | Comando |
|---|---|
| "sincronizá / subí mis cambios" | `skillsync sync` |
| "cómo está todo / estado" | `skillsync status` (rápido) o `skillsync check` (auditoría) |
| "traé lo nuevo / actualizá" | `skillsync update` (terceros: pide confirmación y muestra diff) |
| "instalá todo en esta máquina" | `skillsync install` |
| "registrá un tercero nuevo" | `npx -y skills add <fuente> --skill <n>` → `skillsync manifest` → `skillsync sync` |
| "capturá este skill suelto" | `skillsync adopt <nombre> --from <agente>` |

## Reglas

- **Si editaste un skill bajo `~/skills-shared/`** (directamente o por un symlink),
  al terminar corré `skillsync sync`. No commitees a mano.
- **Nunca escribas tokens ni secretos** en skills — `sync` lo bloquea, pero no confíes.
- Skills privados van en `~/skills-shared/skills-local/` (gitignored: se enlazan,
  jamás se commitean).
- Terceros jamás se auto-actualizan: `update` muestra el diff antes de aplicar.
- No tocar `~/.claude/skills/synced/` (claude.ai) ni re-enlazar los de
  `~/.agents/skills` (los maneja el CLI `npx skills`).

## Detalle

- Máquina por etiqueta: `~/.config/skillsync/machine` (en el VPS: `vps`).
- `.machines` (etiquetas, `*` = todas) y `.targets` (agentes) por skill, opcionales.
- Timer systemd cada 30 min hace `update --pull-only`; si el árbol está sucio no
  toca nada y queda en `skillsync status`.
- Salidas: `OK` bien, `WARN` revisar, `FALLA` bloqueado. Exit 1 = problemas,
  3 = update no aplicado (sucio/divergente), 2 = uso incorrecto.
