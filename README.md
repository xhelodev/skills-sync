# skillsync

Fuente única de **skills personales**, **skills de terceros** (manifest) y
**definiciones MCP**, sincronizada entre PCs (Windows/Linux) y todos los
agentes (**Claude Code, OpenCode, Cursor, Codex, Hermes y pi**) por symlinks.

## Instalación

**PC nueva (un comando)** — con `gh` autenticado o tu clave SSH:

```bash
curl -fsSL https://gist.githubusercontent.com/xhelodev/55815c662f8df075ff68151f5acc232b/raw/bootstrap.sh | bash
```

Clona el repo a `~/skillsync`, etiqueta la máquina, enlaza los skills en todos
los agentes que encuentre y corre `skillsync install`.

**Manual**:

```bash
git clone https://github.com/xhelodev/skills-sync.git ~/skillsync
~/skillsync/bin/skillsync install
```

El repo es **privado**: sin credenciales (`gh auth login` o SSH key) el clone falla.

## Flujo diario

- **Edité un skill** → `skillsync sync`. Listo.
- **¿Cómo está todo?** → `skillsync status` (rápido) o `check` (completo).
- **En las otras máquinas**: el timer trae los cambios solo
  (`update --pull-only`, cada 30 min en el VPS) o `skillsync update` a mano.
- **Un pull quedó trabado por borrado upstream** → `skillsync repair`
  (acepta el borrado y guarda backup en un tag).

## Comandos

```
skillsync sync                 mis ediciones: check + secretos + commit + push + link
skillsync status               vista rápida: repo, enlaces, terceros, último update
skillsync check                auditoría: frontmatter, colisiones, manifest, enlaces
skillsync update [--pull-only] traer cambios del remoto (timer usa --pull-only)
skillsync repair [ruta]        rebase trabado por borrado upstream: acepta el borrado (con backup)
skillsync install              completo: link + terceros del manifest + MCP
skillsync link                 solo re-enlazar (huérfanos incluidos)
skillsync add <repo>           instalar skill de terceros (+ regenerar manifest)
```

`skillsync` queda en `~/.local/bin`.

## Principios

- **Una copia física por skill por máquina**: los agentes lo ven por symlink
  (pi, por settings). Editar una vez cambia para todos al instante.
- **Los terceros se instalan con `npx skills`** y NUNCA se auto-actualizan
  en silencio: siempre mirá el diff antes de aplicar.
- `skills-local/` es gitignored y NUNCA se commitea (`sync` lo bloquea).
