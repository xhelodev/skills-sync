# skillsync

Fuente única de **skills personales**, **skills de terceros** (manifest) y
**definiciones MCP**, sincronizada entre PCs (Windows/Linux) y todos los agentes:
**Claude Code, OpenCode, Cursor, Codex, Hermes y pi**.

## Instalación

### Prerrequisitos

| Herramienta | Obligatoria | Para qué | Verificar |
|---|---|---|---|
| git | sí | clonar y actualizar el repo | `git --version` |
| bash ≥ 4 | sí | corre `skillsync` | `bash --version` |
| python3 | sí | manifest, MCP y settings de pi | `python3 --version` |
| node + npx | si usás skills de terceros | `npx skills` | `npx --version` |
| gh | recomendado | clonar el repo privado sin líos | `gh auth status` |
| systemd (user) | no | el timer de auto-update | `systemctl --user status` |

El repo es **privado**: sin credenciales (`gh auth login` o SSH key) el clone falla.

### Flujo 1 — PC nueva (un comando)

Con `gh` autenticado (`gh auth login`) o tu clave SSH en GitHub:

```bash
curl -fsSL https://gist.githubusercontent.com/xhelodev/55815c662f8df075ff68151f5acc232b/raw/bootstrap.sh | bash
```

Clona el repo a `~/skillsync`, etiqueta la máquina, enlaza tus skills en
todos los agentes que encuentre y corre `skillsync install` (terceros del
manifest + MCP + herramientas). Sin terminal interactiva
(CI), los terceros quedan pendientes: `skillsync install` en una terminal los completa.

Opciones: `SKILLSYNC_MACHINE=vps` (etiqueta), `SKILLSYNC_TIMER=1` (timer),
destino custom: `... | bash -s -- ~/otra-ruta`.

### Flujo 2 — ya tenés el repo

```bash
git clone https://github.com/xhelodev/skills-shared.git ~/skillsync
~/skillsync/bin/skillsync install
```

### Qué se crea y dónde

| Ruta | Qué es |
|---|---|
| `~/skillsync` | el repo (skills + skills-local gitignored) |
| `~/.local/bin/skillsync` | symlink al comando |
| `~/.config/skillsync/machine` | etiqueta de máquina (`vps`, `pc`, …) |
| `~/.local/state/skillsync/` | resultado del último update |
| `~/.skillsync/backups/<agente>/` | backups de skills reemplazados (últimos 5) |
| `~/.claude/skills`, `~/.config/opencode/skills`, `~/.cursor/skills`, `~/.codex/skills`, `~/.hermes/skills` | symlinks por agente |
| `~/.pi/agent/settings.json` | pi: sin symlinks — agrega `skills: [...]` |

### Verificar que quedó bien

```bash
skillsync --help                                # el comando responde
skillsync check                                 # sin FALLA ni enlaces rotos
ls -l ~/.claude/skills | head                   # symlinks → ~/skillsync
systemctl --user list-timers | grep skillsync   # si activaste el timer
```

### Troubleshooting

| Síntoma | Causa | Solución |
|---|---|---|
| `skillsync: command not found` | `~/.local/bin` no está en el PATH | agregá `export PATH="$HOME/.local/bin:$PATH"` a tu `~/.bashrc` o `~/.zshrc` y reabrí la shell (o llamá directo `~/skillsync/bin/skillsync`) |
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
    [[ "$(readlink "$l")" == "$HOME/skillsync/"* ]] && rm "$l"
  done
done
rm -f ~/.local/bin/skillsync
# lo reemplazado por symlink está en ~/.skillsync/backups/
# borrá ~/skillsync recién cuando estés seguro: es tu única copia
```

Principios:

- **Una copia física por skill por máquina**: los agentes lo ven por symlink
  (pi: por settings). Editar una vez cambia para todos al instante.
- **Terceros los enlaza el CLI `npx skills`** (vercel-labs) en `~/.agents/skills`;
  acá solo se *manifiestan* y auditan. Nunca se auto-actualizan en silencio.
- `~/.claude/skills/synced/` lo gestiona claude.ai — **no se toca**.

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
skillsync repair [ruta]        rebase trabado por borrado upstream: acepta el borrado (con backup)
skillsync install              completo: link + terceros del manifest + MCP
skillsync link                 solo re-enlazar (huérfanos incluidos)
skillsync manifest             regenerar third-party.yaml (después de npx skills add/remove)
skillsync add <repo>           instalar skill de terceros (+ regenerar manifest)
skillsync pick                 elegir qué fuentes de terceros instalar en esta máquina
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
- **Un pull quedó trabado en conflicto** (upstream borró algo que tu commit
  tocaba): `skillsync repair` — acepta el borrado, guarda tus cambios en un tag
  `backup-pre-rebase-*` y termina el rebase. Si el conflicto es de contenido,
  no toca nada y te dice cómo resolverlo a mano.

## Skills de terceros

**Selección por máquina**: al correr `skillsync install` en una PC nueva con
terminal, te pregunta fuente por fuente qué querés instalar. La elección queda
en `~/.config/skillsync/third-party.local` (local, no se commitea) y no vuelve
a preguntar. Cambiala cuando quieras con `skillsync pick`.

Defaults commiteados por máquina: `third-party.machines` (TSV, mismo espíritu
que los `.machines` de los personales):

```
cloudflare/skills	vps,pc     # fuente entera
obra/superpowers	*
blader/humanizer/humanizer	vps          # un skill específico (gana sobre la fuente)
```

Precedencia: `third-party.local` > `third-party.machines` > todas. `skillsync
manifest` nunca toca estos archivos. Un skill instalado pero excluido en esta
máquina aparece como `INFO` en `check` (no es error).

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
- **Sin gate de seguridad**: los skills de terceros se instalan directo con
  `npx -y skills add <repo> -g -y` y quedan registrados con `skillsync manifest`.
  Revisá los repos a mano antes de agregarlos.
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
| pi | `~/.pi/agent` | `~/.pi/agent/settings.json` | settings (`skills: [~/skillsync/skills]`; también lee `~/.agents/skills` nativamente) |

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
