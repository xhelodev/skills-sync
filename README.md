# skills-shared + skillsync

Fuente única de **skills personales**, **skills de terceros** (manifest) y
**definiciones MCP**, sincronizada entre PCs (Windows/Linux) y todos los agentes:
**Claude Code, OpenCode, Cursor, Codex, Hermes y pi**.

Principios:

- **Una copia física por skill por máquina**: los agentes lo ven por symlink
  (pi: por settings). Editar una vez cambia para todos al instante.
- **Terceros los enlaza el CLI `npx skills`** (vercel-labs) en `~/.agents/skills`;
  acá solo se *manifiestan* y auditan. Nunca se auto-actualizan en silencio.
- `~/.claude/skills/synced/` lo gestiona claude.ai — **no se toca**.

## Instalación

### Prerrequisitos

| Herramienta | Obligatoria | Para qué | Verificar |
|---|---|---|---|
| git | sí | clonar y actualizar el repo | `git --version` |
| bash ≥ 4 | sí | corre `skillsync` | `bash --version` |
| python3 | sí | manifest, MCP y settings de pi | `python3 --version` |
| node + npx | si usás skills de terceros | `npx skills`, `skill-lint` | `npx --version` |
| gh | recomendado | clonar el repo privado sin líos | `gh auth status` |
| systemd (user) | no | el timer de auto-update | `systemctl --user status` |

El repo es **privado**: sin credenciales (`gh auth login` o SSH key) el clone falla.

### Flujo 1 — PC nueva (desde cero)

```bash
# 1. autenticación GitHub (si no la tenés)
gh auth login

# 2. bootstrap: clona el repo a ~/skills-shared y corre install.sh (= skillsync link)
curl -fsSL https://gist.githubusercontent.com/xhelodev/55815c662f8df075ff68151f5acc232b/raw/bootstrap.sh | bash

# 3. instalar TODO: terceros del manifest (escaneados con skill-lint) + MCP + herramientas
skillsync install

# 4. etiquetar la máquina (una vez; el bootstrap nuevo ya lo hace)
echo vps > ~/.config/skillsync/machine

# 5. (opcional) auto-update cada 30 min
skillsync timer install
```

Qué hace `install`: `link` (symlinks en los agentes que detecte, backups de lo
que reemplace, symlink del comando en `~/.local/bin`) + aplica `third-party.yaml`
con el gate de skill-lint + MCP + herramientas faltantes.

### Flujo 2 — ya tenés el repo

```bash
git clone https://github.com/xhelodev/skills-shared.git ~/skills-shared
~/skills-shared/bin/skillsync install
```

### Qué se crea y dónde

| Ruta | Qué es |
|---|---|
| `~/skills-shared` | el repo (skills + skills-local gitignored) |
| `~/.local/bin/skillsync` | symlink al comando |
| `~/.config/skillsync/machine` | etiqueta de máquina (`vps`, `pc`, …) |
| `~/.local/state/skillsync/` | resultado del último update |
| `~/.skillsync/backups/<agente>/` | backups de skills reemplazados (últimos 5) |
| `~/.claude/skills`, `~/.config/opencode/skills`, `~/.cursor/skills`, `~/.codex/skills`, `~/.hermes/skills` | symlinks por agente |
| `~/.pi/settings.json` | pi: sin symlinks — agrega `skills: [...]` |

### Verificar que quedó bien

```bash
skillsync --help                                # el comando responde
skillsync check                                 # sin FALLA ni enlaces rotos
ls -l ~/.claude/skills | head                   # symlinks → ~/skills-shared
systemctl --user list-timers | grep skillsync   # si activaste el timer
```

### Troubleshooting

| Síntoma | Causa | Solución |
|---|---|---|
| `skillsync: command not found` | `~/.local/bin` no está en el PATH | agregá `export PATH="$HOME/.local/bin:$PATH"` a tu `~/.bashrc` o `~/.zshrc` y reabrí la shell (o llamá directo `~/skills-shared/bin/skillsync`) |
| `Permission denied (publickey)` / pide usuario y contraseña al clonar | sin credenciales para el repo privado | `gh auth login` (o SSH key en GitHub) |
| se cuelga o falla al preguntar | sin TTY (cron, script) | correr desde un terminal; los pasos interactivos son `install` (terceros faltantes) y `add` |
| `npx: command not found` | falta node | instalalo, o ignoralo si no querés skills de terceros |
| un agente no ve un skill | symlink roto o reemplazado | `skillsync check` y después `skillsync link` |

### Desinstalar

```bash
skillsync timer uninstall     # si activaste el timer
# borrar los symlinks que apuntan al repo, en cada agente:
for a in ~/.claude/skills ~/.config/opencode/skills ~/.cursor/skills ~/.codex/skills ~/.hermes/skills; do
  find "$a" -maxdepth 1 -type l 2>/dev/null | while read -r l; do
    [[ "$(readlink "$l")" == "$HOME/skills-shared/"* ]] && rm "$l"
  done
done
rm -f ~/.local/bin/skillsync
# lo reemplazado por symlink está en ~/.skillsync/backups/
# borrá ~/skills-shared recién cuando estés seguro: es tu única copia
```

## Estructura

```
bin/skillsync             el comando (ver abajo)
lib/agents.tsv            registro de agentes (nombre, dir-base, dir-skills, método)
                          — agregar un agente nuevo = una línea, sin tocar código
skills/<nombre>/SKILL.md  skills personales (.machines / .targets opcionales)
skills-local/             gitignored — skills privados: se enlazan pero NUNCA se commitean
third-party.yaml          manifest de terceros (generado: `skillsync manifest`)
mcp/servers.json          servidores MCP SIN secretos ("$VAR" del entorno local)
tests/run.sh              suite de tests (unit + integración, sin dependencias)
install.sh                wrapper retrocompatible → `skillsync link`
```

## Comandos

```
skillsync sync                 mis ediciones: check + secretos + commit + push + link
skillsync status               vista rápida: repo, enlaces, terceros, último update
skillsync check                auditoría: frontmatter, colisiones, manifest, enlaces
skillsync update [--pull-only] traer cambios del remoto (timer usa --pull-only)
skillsync install              completo: link + terceros del manifest + MCP
skillsync link                 solo re-enlazar (huérfanos incluidos)
skillsync manifest             regenerar third-party.yaml (después de npx skills add/remove)
skillsync add <repo>           gatear con skill-lint (0=ok 1=aviso 2=tóxico) + instalar
skillsync tools [--list|--yes] herramientas CLI que faltan: pregunta, muestra el comando e instala
skillsync adopt <n> [--from a] mover un skill que vive en la carpeta de un agente al repo
skillsync mcp                  aplicar mcp/servers.json (Claude Code)
skillsync timer install        timer systemd user cada 30 min (update --pull-only)
```

`skillsync` queda en `~/.local/bin` (lo enlaza `link` solo).

## Flujo diario

- **Edité un skill** (vos o un agente, da igual — es el mismo archivo):
  `skillsync sync`. Listo.
- **¿Cómo está todo?**: `skillsync status` (rápido) o `skillsync check` (completo).
- **En las otras máquinas**: el timer trae los cambios solo (cada 30 min en el VPS).
  A mano: `skillsync update`.

## PC nueva (2 pasos)

```bash
# 1. bootstrap (gist público; usa gh o pide PAT de solo lectura, nunca lo guarda)
curl -fsSL https://gist.githubusercontent.com/xhelodev/55815c662f8df075ff68151f5acc232b/raw/bootstrap.sh | bash

# 2. instalar todo (personales + terceros + MCP)
skillsync install && skillsync manifest && skillsync timer install
```

El instalador escribe la etiqueta de máquina (`~/.config/skillsync/machine`).
Forzar: `SKILLSYNC_MACHINE=vps skillsync …`. Las etiquetas actuales: `vps`,
`pc` (Windows).

## Skills de terceros

- Instalar: `npx -y skills add <fuente> --skill <nombre>` → después
  `skillsync manifest` (registra en third-party.yaml) y `skillsync sync`.
- Quitar: `npx skills remove` → `skillsync manifest` → `skillsync sync`.
- Actualizar: `skillsync update` pregunta y muestra cambios antes de aplicar
  (`npx skills update`). **Nunca automático**: un skill son instrucciones que tus
  agentes ejecutan con shell — siempre mirá el diff.

## Herramientas requeridas por skills

`lib/tools.tsv` (TAB): `skill | herramienta | chequeo | instalación`.
`skill=*` = global (se ofrece en cualquier máquina). Ejemplo:

```
*	agent-browser	command -v agent-browser	npm install -g agent-browser
```

- `skillsync tools` — por cada faltante: muestra quién la pide y **el comando exacto**,
  pregunta `¿Instalar? [s/N]` y lo ejecuta al confirmar; re-verifica después.
- `skillsync tools --list` solo informa; `--yes` instala sin preguntar (bootstrap).
- `skillsync check` avisa las faltantes (WARN).

## Seguridad

- Repo **privado**. Los skills "medio privados" van en `skills-local/` (gitignored;
  `sync` falla si algo de ahí entra al índice).
- `sync` bloquea el commit si detecta patrones de secretos (`ghp_`, `sk-`,
  `AKIA`, `BEGIN PRIVATE KEY`…) en `skills/` o `mcp/`. Es una red de seguridad,
  no una garantía — si está `gitleaks`, sumalo a mano.
- **Gate de skill-lint**: todo tercero pasa por `npx skill-lint <repo>` antes de
  instalarse (`skillsync add` / `skillsync install`). SEGURO instala; AVISO pide
  confirmación; TÓXICO se bloquea en rojo y queda para revisión manual — si la
  revisión lo aprueba, se instala a mano con `npx -y skills add <repo> -g -y`
  y queda registrado con `skillsync manifest`. El scanner es estricto y escanea
  el repo entero (tests incluidos): los bloqueados hay que revisarlos uno por uno.
- Bootstrap con PAT fine-grained de solo lectura que nunca se persiste.

## Timer (VPS)

`systemctl --user list-timers | grep skillsync` · estado: `skillsync timer status`.
Corre `update --pull-only`: si el árbol está sucio o divergió, **no toca nada** y
queda registrado en `status` (resolver con `skillsync sync`).

## Agentes

`lib/agents.tsv` — el agente cuenta como instalado si su dir-base existe:

| agente | dir-base | skills | método |
|---|---|---|---|
| claude | `~/.claude` | `~/.claude/skills` | symlink |
| opencode | `~/.config/opencode` | `~/.config/opencode/skills` | symlink (además lee `~/.claude/skills` y `~/.agents/skills` nativamente) |
| cursor | `~/.cursor` | `~/.cursor/skills` | symlink |
| codex | `~/.codex` | `~/.codex/skills` | symlink |
| hermes | `~/.hermes` | `~/.hermes/skills` | symlink (hermes gestiona su dir: solo enlaces planos, no reordenar) |
| pi | `~/.pi` | `~/.pi/settings.json` | settings (`skills: [~/skills-shared/skills]`; también lee `~/.agents/skills` nativamente) |

## MCP

`mcp/servers.json` sin secretos (`"$MI_VAR"` se resuelve del entorno al aplicar).
`skillsync mcp` los aplica a Claude Code (scope user). OpenCode y Hermes: manual.

## Tests

```bash
tests/run.sh          # todo (35 tests)
tests/run.sh unit     # funciones: gate, machine_matches, fm_field, SECRET_RE, manifest
tests/run.sh integ    # link/check/adopt/update/sync/add/pi con HOME aislado + origin local
```

Sin dependencias y sin red: cada test corre con un `HOME` falso, el remote
apuntado a un repo bare local y `npx` reemplazado por un shim. Si tocás
`bin/skillsync`, corrí la suite antes de pushear.

## Notas

- Si un skill ya existía como carpeta real en el destino, se respalda en
  `~/.skillsync/backups/<agente>/` (retención: últimos 5) y se reemplaza por symlink.
- Windows: sin instalador propio por ahora. Cuando vuelvas a una PC Windows:
  mismo bootstrap (gist) clonando el repo y `skillsync` no corre ahí sin un
  `skillsync.ps1` — pendiente si se vuelve a necesitar.
- Backups viejos del install.sh anterior: `~/.skillsync/backups/`.
