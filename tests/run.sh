#!/usr/bin/env bash
# Suite de tests de skillsync — sin dependencias (bash + python3 + git).
#   tests/run.sh              todo
#   tests/run.sh unit         solo unitarios (funciones, sin red)
#   tests/run.sh integ        solo integración (HOME aislado + origin local)
#
# Nada toca el HOME real ni GitHub: cada test corre con HOME de mentira y el
# remote apuntado a un repo bare local. `npx` se reemplaza por un shim.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
T="$(mktemp -d /tmp/opencode/skillsync-tests.XXXXXX)"
trap 'rm -rf "$T"' EXIT

pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
assert_eq() { [[ "$2" == "$3" ]] && pass "$1" || fail "$1 (esperado [$2] / obtuve [$3])"; }
assert_rc() { # desc expected_rc cmd args...
  local desc="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1
  local rc=$?
  [[ "$want" == "$rc" ]] && pass "$desc" || fail "$desc (esperado rc=$want / obtuve rc=$rc)"
}
ok_if() { [[ $2 == 0 ]] && pass "$1" || fail "$1"; }

# ══════════════════════════════════ UNIT ══════════════════════════════════
unit() {
  echo "── UNIT ──"
  sed 's/^main "\$@"$//; s/^exit$//' "$SRC/bin/skillsync" > "$T/lib.sh"
  ( set -euo pipefail
    source "$T/lib.sh"
    MACHINE=vps

    # machine_matches
    machine_matches "*" && pass "machine_matches: * aplica" || fail "machine_matches: *"
    machine_matches "vps,pc" && pass "machine_matches: vps en lista" || fail "machine_matches: vps"
    machine_matches " casa ,x" && fail "machine_matches: trim" || pass "machine_matches: casa no aplica a vps"
    machine_matches "pc" && fail "machine_matches: vps≠pc" || pass "machine_matches: vps≠pc"

    # fm_field
    D="$T/fix"; mkdir -p "$D"
    printf -- '---\nname: mi-skill\ndescription: "Descripcion de prueba suficientemente larga para pasar."\nversion: 1.0.0\n---\ncuerpo\n' > "$D/SKILL.md"
    assert_eq "fm_field name" "mi-skill" "$(fm_field "$D/SKILL.md" name)"
    assert_eq "fm_field description" "Descripcion de prueba suficientemente larga para pasar." "$(fm_field "$D/SKILL.md" description)"
    assert_eq "fm_field campo inexistente" "" "$(fm_field "$D/SKILL.md" nope)"

    # SECRET_RE
    TOK="ghp_aaaabbbbccccddddeeeeffffgggghhhh1234"
    [[ $TOK =~ $SECRET_RE ]] && pass "SECRET_RE: detecta ghp_" || fail "SECRET_RE: ghp_"
    [[ "hola descripcion normal" =~ $SECRET_RE ]] && fail "SECRET_RE: falso positivo en prosa" || pass "SECRET_RE: prosa limpia"
    [[ "-----BEGIN RSA PRIVATE KEY" =~ $SECRET_RE ]] && pass "SECRET_RE: detecta private key" || fail "SECRET_RE: private key"
  ) && pass "unit: script fuente cargable" || fail "unit: el source rompió (set -e)"

  # selección por máquina: sidecar + local + compare/counts
  MF="$T/mani-fix"; mkdir -p "$MF/lib"
  cp "$SRC/lib/manifest.py" "$MF/lib/manifest.py"
  printf 'version: 1\nsources:\n  - source: a/b\n    skills:\n      - x\n      - y\n  - source: c/d\n    skills:\n      - z\n' > "$MF/third-party.yaml"
  printf 'c/d\totra\na/b/y\totra\n' > "$MF/third-party.machines"
  MHOME="$T/mani-home2"; mkdir -p "$MHOME/.agents"
  python3 - "$MHOME" <<'PY'
import json, os, sys
mh = sys.argv[1]
json.dump({"version": 3, "skills": {
    "x": {"source": "a/b"}, "z": {"source": "c/d"}}},
    open(os.path.join(mh, ".agents", ".skill-lock.json"), "w"))
PY
  env HOME="$MHOME" python3 "$MF/lib/manifest.py" counts "$MF" vps > "$T/counts-vps.txt"
  assert_eq "counts vps: solo a/b con 1 (y excluida)" "a/b	1" "$(cat "$T/counts-vps.txt")"
  env HOME="$MHOME" python3 "$MF/lib/manifest.py" counts "$MF" otra > "$T/counts-otra.txt"
  assert_eq "counts otra: a/b 2 + c/d 1" "a/b	2
c/d	1" "$(cat "$T/counts-otra.txt")"
  # compare: en vps, z está instalado pero excluido → INFO, no error
  assert_rc "compare vps: excluido-instalado no es error" 0 env HOME="$MHOME" python3 "$MF/lib/manifest.py" compare "$MF" vps
  grep -q "INFO z" "$T/cmp-vps.txt" 2>/dev/null || env HOME="$MHOME" python3 "$MF/lib/manifest.py" compare "$MF" vps > "$T/cmp-vps.txt" 2>&1
  grep -q "INFO z" "$T/cmp-vps.txt" && pass "compare vps: INFO de excluido" || fail "compare vps: sin INFO"
  # en 'otra': y aplica pero no está instalado → exit 1 MISSING
  assert_rc "compare otra: y falta → exit 1" 1 env HOME="$MHOME" python3 "$MF/lib/manifest.py" compare "$MF" otra
  # local gana sobre sidecar: si la máquina solo quiere a/b, z pasa a INFO y y vuelve a aplicar
  mkdir -p "$MHOME/.config/skillsync"; echo "a/b" > "$MHOME/.config/skillsync/third-party.local"
  env HOME="$MHOME" python3 "$MF/lib/manifest.py" counts "$MF" vps > "$T/counts-local.txt"
  assert_eq "counts con local: solo a/b (2 skills)" "a/b	2" "$(cat "$T/counts-local.txt")"

  # pick_sources: escribe la selección local (a=todo el resto)
  PH="$T/pick-home"; mkdir -p "$PH/.config/skillsync"
  ( set -euo pipefail
    source "$T/lib.sh"
    LIB="$SRC/lib"; REPO="$MF"; MACHINE="vps"
    printf 's\nn\n' | HOME="$PH" pick_sources
  ) >/dev/null 2>&1
  grep -q "^a/b$" "$PH/.config/skillsync/third-party.local" \
    && pass "pick: a/b seleccionada" || fail "pick: a/b"
  grep -q "^c/d$" "$PH/.config/skillsync/third-party.local" \
    && fail "pick: c/d no debía entrar" || pass "pick: c/d quedó fuera"

  # manifest.py: gen/compare con HOME aislado (gen sobre COPIA, jamás sobre el repo real)
  MH="$T/mani-home"; mkdir -p "$MH"
  cp "$SRC/third-party.yaml" "$T/manifest-real.bak"
  assert_rc "manifest gen sin lock" 0 env HOME="$MH" python3 "$SRC/lib/manifest.py" gen "$SRC"
  # gen con lock vacío vació el manifest del repo → restaurar y verificar
  assert_rc "manifest restaurado tras gen destructivo" 0 python3 "$SRC/lib/manifest.py" gen "$SRC"
  cmp -s "$T/manifest-real.bak" "$SRC/third-party.yaml" && pass "gen: manifest real intacto tras regenerar" || fail "gen: manifest real cambió"
  assert_rc "compare lock vacío vs manifest lleno → exit 1 (falta instalar)" 1 env HOME="$MH" python3 "$SRC/lib/manifest.py" compare "$SRC"
  mkdir -p "$MH/.agents"
  REPO="$SRC" python3 - "$MH" <<'PY'
import json, os, sys
mh = sys.argv[1]
json.dump({"version": 3, "skills": {"no-existe": {"source": "fake/repo"}}},
          open(os.path.join(mh, ".agents", ".skill-lock.json"), "w"))
PY
  env HOME="$MH" python3 "$SRC/lib/manifest.py" compare "$SRC" >/dev/null 2>&1
  assert_rc "manifest compare desalineado: exit 1" 1 env HOME="$MH" python3 "$SRC/lib/manifest.py" compare "$SRC"

  # scan_gate con run_lint stub (los 4 caminos + yes-warn)
  ( set -euo pipefail
    source "$T/lib.sh"
    DRY=0
    run_lint() { echo "hallazgo fake"; return ${FAKE_RC:-0}; }
    FAKE_RC=0; scan_gate t/safe            && pass "gate rc0 → instala" || fail "gate rc0"
    FAKE_RC=1; scan_gate t/warn            && fail "gate rc1 sin TTY instaló" || pass "gate rc1 sin TTY → no instala"
    SCAN_ALLOW_WARN=1; FAKE_RC=1; scan_gate t/warn2 && pass "gate rc1 --yes-warn → instala" || fail "gate rc1 --yes-warn"
    SCAN_ALLOW_WARN=0; FAKE_RC=2; scan_gate t/toxic && fail "gate rc2 instaló" || pass "gate rc2 → bloquea"
    FAKE_RC=3; scan_gate t/err             && fail "gate rc3 instaló" || pass "gate rc3 → fail-closed"
    # bloqueados = warn-sin-tty + toxic (err va en GATE_ERR)
    [[ ${#GATE_BLOCKED[@]} -eq 2 && ${#GATE_ERR[@]} -eq 1 ]] \
      && pass "gate: resumen (2 bloqueados, 1 error)" || fail "gate: resumen bloqueados=${#GATE_BLOCKED[@]} err=${#GATE_ERR[@]}"
  ) && pass "gate: stub suite" || fail "gate: stub suite rompió"
}

# ═══════════════════════════════ INTEGRACIÓN ══════════════════════════════
integ() {
  echo "── INTEGRACIÓN (HOME aislado + origin local + npx shim) ──"
  local IR="$T/repo" IH="$T/home"
  git clone -q --bare "$SRC" "$T/origin.git"
  cp -a "$SRC" "$IR"
  git -C "$IR" remote set-url origin "$T/origin.git"
  git -C "$IR" config user.name test && git -C "$IR" config user.email t@t
  mkdir -p "$IH/.claude" "$IH/.config/opencode" "$IH/.config/skillsync" "$IH/.agents" "$T/shim"
  echo vps > "$IH/.config/skillsync/machine"
  printf '#!/usr/bin/env bash\n# shim: emula npx (skills add / skill-lint)\nif [[ "$*" == *skill-lint* ]]; then echo "hallazgo shim"; exit ${LINT_RC:-0}; fi\nif [[ "$*" == *skills* ]]; then echo "shim: installed"; exit 0; fi\nexit 0\n' > "$T/shim/npx"
  chmod +x "$T/shim/npx"
  # lock de mentira = manifest real (máquina "con terceros instalados")
  REPO="$IR" python3 - "$IH" "$IR" <<'PY'
import json, os, sys, importlib.util
mh, repo = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("m", os.path.join(repo, "lib", "manifest.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
out = {}
for src, sks in m.parse_manifest(repo).items():
    for sk in sks:
        out[sk] = {"source": src, "sourceType": "github"}
json.dump({"version": 3, "skills": out}, open(os.path.join(mh, ".agents", ".skill-lock.json"), "w"))
PY
  export HOME="$IH"
  export PATH="$T/shim:$PATH"
  local S="$IR/bin/skillsync"

  assert_rc "status corre" 0 "$S" status
  assert_rc "check verde (repo + lock coherentes)" 0 "$S" check

  # link: crea enlaces, idempotente
  local lout lrc
  lout="$("$S" link 2>&1)"; lrc=$?
  ok_if "link corre" "$lrc"
  [[ $lout == *"no existe ~/.local/bin"* ]] && pass "link: avisa PATH faltante" || fail "link: aviso PATH faltante"
  local n1
  n1="$(ls "$IH/.claude/skills" 2>/dev/null | wc -l)"
  ok_if "link: enlaces creados ($n1)" "$([[ $n1 -gt 0 ]] && echo 0 || echo 1)"
  local snap1 snap2
  snap1="$(ls -la "$IH/.claude/skills" | md5sum)"
  assert_rc "link 2ª corrida" 0 "$S" link
  snap2="$(ls -la "$IH/.claude/skills" | md5sum)"
  assert_eq "link: idempotente" "$snap1" "$snap2"

  # huérfanos: borrar skill del repo → link lo quita; symlink ajeno sobrevive
  ln -s "$IR/skills/no-existe" "$IH/.claude/skills/no-existe"
  ln -s /tmp "$IH/.claude/skills/ajeno"
  assert_rc "link con huérfanos" 0 "$S" link
  [[ ! -e "$IH/.claude/skills/no-existe" ]] && pass "huérfano eliminado" || fail "huérfano sigue"
  [[ -L "$IH/.claude/skills/ajeno" ]] && pass "symlink ajeno sobrevive" || fail "ajeno eliminado"

  # check detecta enlace roto (exit 1)
  ln -s "$IR/skills/claude-code/inexistente" "$IH/.claude/skills/roto"
  assert_rc "check: enlace roto → exit 1" 1 "$S" check
  rm "$IH/.claude/skills/roto"

  # frontmatter inválido → check exit 1
  mv "$IR/skills/claude-code/SKILL.md" "$IR/skills/claude-code/SKILL.md.keep"
  printf -- '---\nname: claude-code\n---\nx\n' > "$IR/skills/claude-code/SKILL.md"
  assert_rc "check: sin description → exit 1" 1 "$S" check
  mv "$IR/skills/claude-code/SKILL.md.keep" "$IR/skills/claude-code/SKILL.md"
  assert_rc "check: restaurado → exit 0" 0 "$S" check

  # adopt
  mkdir -p "$IH/.claude/skills/adoptame"
  printf -- '---\nname: adoptame\ndescription: Skill creado por un agente en su carpeta para el test de adopcion.\n---\nx\n' > "$IH/.claude/skills/adoptame/SKILL.md"
  assert_rc "adopt corre" 0 "$S" adopt adoptame --from claude
  [[ -f "$IR/skills/adoptame/.machines" && -L "$IH/.claude/skills/adoptame" ]] \
    && pass "adopt: mueve + .machines + symlink" || fail "adopt"
  # fijar el fixture: los tests de update/sync necesitan árbol limpio
  git -C "$IR" add -A && git -C "$IR" commit -qm "fixture: adoptame"

  # update --pull-only: al día / hace ff / sucio → 3
  assert_rc "update pull-only al día" 0 "$S" update --pull-only
  git -C "$IR" commit -q --allow-empty -m t && git -C "$IR" push -q origin main && git -C "$IR" reset -q --hard HEAD~1
  assert_rc "update pull-only hace ff" 0 "$S" update --pull-only
  echo x > "$IR/basura.tmp"
  assert_rc "update pull-only con árbol sucio → exit 3" 3 "$S" update --pull-only
  [[ -f "$IH/.local/state/skillsync/last-update.txt" ]] && pass "estado del update registrado" || fail "estado update"
  rm "$IR/basura.tmp"; git -C "$IR" reset -q --hard HEAD

  # sync: secreto bloquea, limpio commitea
  mkdir -p "$IR/skills/trampa"
  printf -- '---\nname: con-token\ndescription: Skill trampa del test con token ghp_aaaabbbbccccddddeeeeffffgggghhhh1234 pegado.\n---\nx\n' > "$IR/skills/trampa/SKILL.md"
  assert_rc "sync: secreto → exit 1" 1 "$S" sync
  git -C "$IR" log --oneline -1 | grep -q "trampa\|token" && fail "secreto quedó commiteado" || pass "secreto: NADA commiteado"
  git -C "$IR" reset -q --hard HEAD && rm -rf "$IR/skills/trampa"
  assert_rc "sync limpio corre" 0 "$S" sync
  git -C "$IR" fetch -q origin
  [[ -z "$(git -C "$IR" status --porcelain)" ]] && pass "sync: árbol limpio tras commit+push" || fail "sync: quedó sucio"

  # add con gate (shim): seguro instala; tóxico/aviso bloquean
  assert_rc "add: lint seguro → exit 0" 0 env LINT_RC=0 "$S" add fake/repo
  assert_rc "add: repo sigue consistente tras add" 0 "$S" check
  assert_rc "add: lint tóxico → exit 3" 3 env LINT_RC=2 "$S" add fake/toxic
  assert_rc "add: aviso sin TTY → exit 3" 3 env LINT_RC=1 "$S" add fake/warn
  assert_rc "add: aviso --yes-warn → exit 0" 0 env LINT_RC=1 "$S" add fake/warn2 --yes-warn

  # pi settings (método settings), idempotente
  mkdir -p "$IH/.pi"; echo '{"theme":"dark"}' > "$IH/.pi/settings.json"
  assert_rc "link con pi" 0 "$S" link
  grep -q "$IR/skills" "$IH/.pi/settings.json" && pass "pi: settings con skills del repo" || fail "pi settings"
  local n
  n="$(python3 -c "import json;d=json.load(open('$IH/.pi/settings.json'));print(len(d.get('skills',[])))")"
  assert_eq "pi: idempotente (2 entradas: skills + skills-local)" "2" "$n"
}

case "${1:-all}" in
  unit) unit ;;
  integ) integ ;;
  all) unit; integ ;;
  *) echo "uso: tests/run.sh [unit|integ|all]"; exit 2 ;;
esac

echo
echo "═══ RESULTADO: $PASS pass · $FAIL fail ═══"
[[ $FAIL -eq 0 ]] && echo "TODOS OK" || echo "HAY FALLOS"
exit $(( FAIL > 0 ? 1 : 0 ))
