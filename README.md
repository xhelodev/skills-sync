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

## Preparar una PC nueva (una línea)

Bootstrap público (gist): usa `SKILLSYNC_TOKEN` si está exportado, si no `gh auth token`
(si hay gh autenticado), si no pide un token fine-grained de solo lectura de este repo
por teclado — y nunca lo guarda (limpia la URL remota tras clonar).

```bash
# Linux / macOS
curl -fsSL https://gist.githubusercontent.com/xhelodev/55815c662f8df075ff68151f5acc232b/raw/bootstrap.sh | bash

# Windows (PowerShell)
irm https://gist.githubusercontent.com/xhelodev/55815c662f8df075ff68151f5acc232b/raw/bootstrap.ps1 | iex
```

Destino custom: `curl ... | bash -s -- ~/otra-ruta`. Sin gh en la máquina:
`SKILLSYNC_TOKEN=github_pat_xxx curl ... | bash` (PAT de solo lectura, solo este repo).

URLs fijadas a la revisión `6c5e70f7fb2adf8b1240ec8a6c3ab22ead4360c6` (inmutables):
- `https://gist.githubusercontent.com/xhelodev/55815c662f8df075ff68151f5acc232b/raw/6c5e70f7fb2adf8b1240ec8a6c3ab22ead4360c6/bootstrap.sh`
- `https://gist.githubusercontent.com/xhelodev/55815c662f8df075ff68151f5acc232b/raw/6c5e70f7fb2adf8b1240ec8a6c3ab22ead4360c6/bootstrap.ps1`

Alternativa manual (usa **SSH**, no HTTPS):

```bash
git clone git@github.com:xhelodev/skills-shared.git ~/skills-shared
cd ~/skills-shared && ./install.sh
```

> El repo es privado. Clonar por HTTPS (`https://github.com/...`) falla con
> `remote: Repository not found` si git no tiene credenciales: GitHub no acepta la
> contraseña de la cuenta para operaciones git. Si preferís HTTPS, configurá un PAT
> o `gh auth setup-git`. Con SSH solo necesitás la clave agregada a GitHub
> (`ssh -T git@github.com` debe saludarte como `xhelodev`).

El instalador autodetecta la máquina por hostname. Para forzar etiqueta:
`SKILLSYNC_MACHINE=vps ./install.sh` (Linux) / `$env:SKILLSYNC_MACHINE="vps"; .\install.ps1` (Windows).

Si ya existía un skill real en el destino, queda como backup `nombre.bak-<fecha>` junto al enlace.

## MCP

- `mcp/servers.json` **nunca lleva secretos**: un valor `"$MI_VAR"` se resuelve de las
  variables de entorno de cada PC al momento de aplicar. Nada de keys en el repo.
- Soporta `env` (stdio) y `headers` (http); en `headers` el `$VAR` puede ir embebido
  (`"Authorization": "Bearer $MI_TOKEN"`). Si falta la variable, ese servidor se omite.
- Se instalan en el scope `user` de Claude Code (sin tocar config por proyecto).
- v1 aplica automáticamente a **Claude Code** (`claude mcp add`).
  OpenCode (sección `mcp` de `opencode.jsonc`) y Hermes (`hermes config set`) quedan
  como paso manual hasta automatizarlos con un servidor real.

## Notas

- `~/.claude/skills/synced/` lo gestiona Claude.ai (skills de la cuenta) — **no se toca** ni se sincroniza.
- Los skills con `.machines: vps` solo se enlazan donde la máquina sea el VPS.
