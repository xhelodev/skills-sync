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


def cmd_compare(repo):
    manifest = parse_manifest(repo)
    lock = read_lock()
    m_pairs = {(src, sk) for src, sks in manifest.items() for sk in sks}
    l_pairs = {(m.get("source", "?"), name) for name, m in lock.items()}
    missing = sorted(m_pairs - l_pairs)
    extra = sorted(l_pairs - m_pairs)
    for src, sk in missing:
        print(f"MISSING {sk} ({src}) — instalalo: skillsync install")
    for src, sk in extra:
        print(f"EXTRA {sk} ({src}) — no está en el manifest. Corré: skillsync manifest")
    if not missing and not extra:
        print(f"manifest OK: {len(m_pairs)} skills de terceros coinciden con el lock")
        return 0
    return 1


def cmd_list(repo):
    for src, sks in sorted(parse_manifest(repo).items()):
        for sk in sorted(sks):
            print(f"{src}\t{sk}")
    return 0


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("gen", "compare", "list"):
        print(__doc__, file=sys.stderr)
        return 2
    return {"gen": cmd_gen, "compare": cmd_compare, "list": cmd_list}[sys.argv[1]](sys.argv[2])


if __name__ == "__main__":
    sys.exit(main())
