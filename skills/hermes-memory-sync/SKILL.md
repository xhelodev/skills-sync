---
name: hermes-memory-sync
description: "Memoria de Hermes sincronizada con GitHub (hermes-memory) y espejo solo lectura en catcore."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [memoria, sync, git, catcore, backup]
    related_skills: [skillsync, catcore-registry, vps-personal]
prerequisites:
  commands: [git, gh]
---

# Memoria de Hermes: git + espejo catcore

Arquitectura (desde 2026-10-26):

```
                 commit (Hermes) / edit+pull (usuario)
~/.hermes/memories/  ⇄  ~/hermes-memory (repo privado xhelodev/hermes-memory)
      │
      └── espejo solo lectura (cron horario) ──→ catcore (carpeta "Hermes")
```

## Reglas que no se rompen

- **catcore nunca escribe en `.hermes`**: las notas con tag `solo-lectura` se
  sobreescriben cada hora con la fuente. La edición externa es SOLO vía GitHub.
- **Nada con secretos** al repo ni a catcore: sin config.yaml, .env, keys, state.db.
- Deploys/sync manuales de memoria: NO — los crons lo hacen. Doble escritura = conflicto.

## Componentes

| Qué | Dónde |
| --- | --- |
| Sync bidireccional (cron `*/10`) | `~/scripts/hermes-sync.sh` → log `~/scripts/hermes-sync.log` |
| Espejo catcore (cron horario) | `~/scripts/catcore-mirror.sh` → log `~/scripts/catcore-mirror.log` |
| Repo | `~/hermes-memory` → `github.com/xhelodev/hermes-memory` (privado) |
| Notas en catcore | `Hermes · Memoria`, `Hermes · Perfil usuario`, `Hermes · Skills y crons` |
| Backup ampliado (2026-10-26) | además de memories/, `rsync -a --delete` one-way local→repo: `~/.hermes/{cron,scripts,plans}` y `profiles/pr-reviewer/{skills,cron,memories,plans,SOUL.md,*.sh}` → `backup/` en el repo. Excluye `*.db*`, `*.log`, `output/`, `cache/` (secretos y estado). Requiere `rsync` (instalado apt 2026-10-26). |

## Detalles operativos

- Conflicto (local y remoto cambiaron desde el último sync): gana el local, se
  copia remota queda en el historial del repo, aviso por TG (`tg-notify hermes`).
- Los cambios bajados de GitHub afectan a las **sesiones nuevas** de Hermes.
- Estado del sync: `~/hermes-memory/.state` (hashes; en `.gitignore`).
- El índice `generated/skills-index.md` se regenera en cada sync (no editar).
- Espejo catcore: cliente JSON-RPC mínimo sobre `http://127.0.0.1:4002/mcp`
  (handshake `initialize` → `notifications/initialized` → `tools/call`; las
  respuestas vienen envueltas en `{"ok","data"}`; `update_note` exige `content`
  junto a `tagIds`; la carpeta se cambia con `move_note`, no con `update_note`).

## Pitfalls

1. Editar una nota en catcore y esperar que propaguen: no propagan (por diseño).
2. Editar `memories/*.md` directamente en el repo entre dos ticks del cron:
   funciona, pero el conflicto se resuelve a favor del VPS — avisar a Hermes si
   la edición remota es importante.
3. Si `tg-notify` repite avisos de conflicto, revisar `git log` del repo antes
   de forzar nada: el estado `.state` marca qué hash se considera sincronizado.
