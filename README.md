# skills-shared

Fuente única de mis **skills personales** y **definiciones MCP**, sincronizada entre PCs
(Windows/Linux) y tres herramientas: **Hermes**, **OpenCode** y **Claude Code**
(los tres leen el mismo formato `SKILL.md` de Anthropic).

## Estructura

```
skills/<nombre>/SKILL.md   el skill (con sus references/ si tiene)
skills/<nombre>/.machines  opcional: máquinas donde aplica, separadas por coma
                           (ej: "vps", o "*" = todas; default "*")
skills/<nombre>/.targets   opcional: herramientas destino (hermes,opencode,claude;
                           default: todas las instaladas)
mcp/servers.json           servidores MCP SIN secretos
install.sh                 instalador Linux/macOS (symlinks)
install.ps1                instalador Windows (junctions, sin admin)
```

## Agregar un skill

1. `mkdir skills/mi-skill` + escribir `SKILL.md` (frontmatter `name` y `description` con triggers).
2. Si no aplica a todas las máquinas: `.machines` con la etiqueta (ej: `vps`).
3. `git add -A && git commit -m "..." && git push` → en cada PC: `git pull && ./install.sh`.

## Preparar una PC nueva

```bash
# Linux/macOS
git clone https://github.com/xhelodev/skills-shared.git ~/skills-shared
cd ~/skills-shared && ./install.sh

# Windows (PowerShell)
git clone https://github.com/xhelodev/skills-shared.git "$HOME\skills-shared"
cd "$HOME\skills-shared"; .\install.ps1
```

El instalador autodetecta la máquina por hostname. Para forzar etiqueta:
`SKILLSYNC_MACHINE=vps ./install.sh` (Linux) / `$env:SKILLSYNC_MACHINE="vps"; .\install.ps1` (Windows).

Si ya existía un skill real en el destino, queda como backup `nombre.bak-<fecha>` junto al enlace.

## MCP

- `mcp/servers.json` **nunca lleva secretos**: un valor `"$MI_VAR"` se resuelve de las
  variables de entorno de cada PC al momento de aplicar. Nada de keys en el repo.
- v1 aplica automáticamente a **Claude Code** (`claude mcp add`).
  OpenCode (sección `mcp` de `opencode.jsonc`) y Hermes (`hermes config set`) quedan
  como paso manual hasta automatizarlos con un servidor real.

## Notas

- `~/.claude/skills/synced/` lo gestiona Claude.ai (skills de la cuenta) — **no se toca** ni se sincroniza.
- Los skills con `.machines: vps` solo se enlazan donde la máquina sea el VPS.
