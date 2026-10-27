#!/usr/bin/env python3
"""third-party.yaml ↔ ~/.agents/.skill-lock.json.

Uso: manifest.py {gen|compare|list} <repo>

- gen    : regenera third-party.yaml desde el lock del CLI (`npx skills`).
           Se corre después de `npx skills add/remove` para dejar registro.
- compare: manifest vs lock → MISSING (en manifest, no instalado),
           EXTRA (instalado, no en manifest). Exit 1 si hay diferencia.
- list   : imprime "source<TAB>skill" del manifest.

El yaml se escribe en formato estricto (lista simple), parseable también sin pyyaml.
"""
import json
import os
import re
import sys
from collections import defaultdict

VERSION = 1


def lock_path():
    return os.path.expanduser("~/.agents/.skill-lock.json")


def manifest_path(repo):
    return os.path.join(repo, "third-party.yaml")


def read_lock():
    p = lock_path()
    if not os.path.exists(p):
        return {}
    try:
        with open(p) as f:
            return json.load(f).get("skills", {})
    except (OSError, ValueError) as e:
        print(f"WARN lock inválido ({e}): {p}", file=sys.stderr)
        return {}


def render(by_source):
    lines = [
        "# Generado por `skillsync manifest` — no editar a mano: regenerar con ese comando.",
        "# Cada entrada equivale a: npx -y skills add <source> --skill <skill>",
        f"version: {VERSION}",
        "sources:",
    ]
    for source in sorted(by_source):
        lines.append(f"  - source: {source}")
        lines.append("    skills:")
        for skill in sorted(by_source[source]):
            lines.append(f"      - {skill}")
    return "\n".join(lines) + "\n"


def parse_manifest(repo):
    """Devuelve {source: [skills]}. Prueba pyyaml; si no, parser estricto del formato propio."""
    p = manifest_path(repo)
    if not os.path.exists(p):
        return {}
    text = open(p).read()
    try:
        import yaml  # type: ignore
        data = yaml.safe_load(text) or {}
        out = {}
        for entry in data.get("sources") or []:
            src = str(entry.get("source", "?"))
            out[src] = [str(s) for s in entry.get("skills") or []]
        return out
    except ImportError:
        pass
    except Exception as e:  # yaml presente pero roto
        raise SystemExit(f"WARN third-party.yaml inválido ({e}): {p}")
    out = defaultdict(list)
    source = None
    for line in text.splitlines():
        m = re.match(r"\s*-\s*source:\s*(\S+)\s*$", line)
        if m:
            source = m.group(1)
            continue
        m = re.match(r"\s*-\s*([a-z0-9][a-z0-9-]*)\s*$", line)
        if m and source:
            out[source].append(m.group(1))
    return dict(out)


def cmd_gen(repo):
    lock = read_lock()
    by_source = defaultdict(list)
    for name, meta in lock.items():
        by_source[meta.get("source", "?")].append(name)
    p = manifest_path(repo)
    old = open(p).read() if os.path.exists(p) else None
    new = render(by_source)
    if old == new:
        print(f"manifest sin cambios ({sum(len(v) for v in by_source.values())} skills)")
        return 0
    with open(p, "w") as f:
        f.write(new)
    n = sum(len(v) for v in by_source.values())
    print(f"third-party.yaml regenerado: {n} skills de {len(by_source)} fuentes")
    print("  → recordalo con: skillsync sync")
    return 0


def machines_path(repo):
    return os.path.join(repo, "third-party.machines")


def local_path():
    return os.path.expanduser("~/.config/skillsync/third-party.local")


def parse_sidecar(repo):
    """Selección commiteada: third-party.machines (TSV: clave <TAB> máquinas).
    Clave = fuente (a/b) o fuente/skill (a/b/c); la de skill gana sobre la de fuente."""
    src_lv, sk_lv = {}, {}
    p = machines_path(repo)
    if not os.path.exists(p):
        return src_lv, sk_lv
    for line in open(p):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        key, machines = parts[0].strip(), parts[1].strip()
        seg = key.split("/")
        if len(seg) >= 3:
            sk_lv[("/".join(seg[:2]), seg[-1])] = machines
        else:
            src_lv[key] = machines
    return src_lv, sk_lv


def parse_local():
    """Selección local de ESTA máquina: ~/.config/skillsync/third-party.local.
    Devuelve None si no existe (sin selección local) o el set de fuentes elegidas."""
    p = local_path()
    if not os.path.exists(p):
        return None
    out = set()
    for line in open(p):
        line = line.strip()
        if line and not line.startswith("#"):
            out.add(line)
    return out


def read_selection(repo, machine):
    """Devuelve fn(src, skill) → bool. Precedencia: local > sidecar > todas."""
    local = parse_local()
    if local is not None:
        return lambda src, sk: src in local
    src_lv, sk_lv = parse_sidecar(repo)

    def m(machines):
        return any(t.strip() in ("*", machine) for t in machines.split(",") if t.strip())

    def applies(src, sk):
        if (src, sk) in sk_lv:
            return m(sk_lv[(src, sk)])
        if src in src_lv:
            return m(src_lv[src])
        return True

    return applies


def cmd_compare(repo, machine=None):
    manifest = parse_manifest(repo)
    lock = read_lock()
    sel = read_selection(repo, machine) if machine else (lambda s, k: True)
    m_pairs = {(src, sk) for src, sks in manifest.items() for sk in sks}
    l_pairs = {(m.get("source", "?"), name) for name, m in lock.items()}
    missing = sorted(p for p in m_pairs - l_pairs if sel(*p))
    extra = sorted(l_pairs - m_pairs)
    # instalados pero excluidos en esta máquina: aviso, no error
    for src, sk in sorted(l_pairs & m_pairs):
        if not sel(src, sk):
            print(f"INFO {sk} ({src}) instalado pero excluido en esta máquina")
    for src, sk in missing:
        print(f"MISSING {sk} ({src}) — instalalo: skillsync install")
    for src, sk in extra:
        print(f"EXTRA {sk} ({src}) — no está en el manifest. Corré: skillsync manifest")
    if not missing and not extra:
        print(f"manifest OK: {len(m_pairs)} skills de terceros coinciden con el lock")
        return 0
    return 1


def cmd_list(repo, machine=None):
    sel = read_selection(repo, machine) if machine else (lambda s, k: True)
    for src, sks in sorted(parse_manifest(repo).items()):
        for sk in sorted(sks):
            if sel(src, sk):
                print(f"{src}\t{sk}")
    return 0


def cmd_counts(repo, machine=None):
    sel = read_selection(repo, machine) if machine else (lambda s, k: True)
    man = parse_manifest(repo)
    for src in man:
        n = sum(1 for sk in man[src] if sel(src, sk))
        if n:
            print(f"{src}\t{n}")
    return 0


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("gen", "compare", "list", "counts"):
        print(__doc__, file=sys.stderr)
        return 2
    machine = sys.argv[3] if len(sys.argv) > 3 else None
    return {"gen": cmd_gen, "compare": cmd_compare, "list": cmd_list,
            "counts": cmd_counts}[sys.argv[1]](sys.argv[2], machine) if sys.argv[1] != "gen" \
        else cmd_gen(sys.argv[2])


if __name__ == "__main__":
    sys.exit(main())
