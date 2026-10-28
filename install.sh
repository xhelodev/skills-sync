#!/usr/bin/env bash
# Retrocompatible: el instalador ahora es bin/skillsync (subcomando link).
# PC nueva completa: bootstrap + `skillsync install && skillsync manifest && skillsync timer install`
# Telemetría de skills de terceros OFF por defecto (impeccable, skills CLI, etc.)
export DO_NOT_TRACK="${DO_NOT_TRACK:-1}"
for rc in ~/.bashrc ~/.profile; do
  grep -qx 'export DO_NOT_TRACK=1' "$rc" 2>/dev/null || echo 'export DO_NOT_TRACK=1' >> "$rc"
done
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/bin/skillsync" link "$@"
