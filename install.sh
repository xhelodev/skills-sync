#!/usr/bin/env bash
# Retrocompatible: el instalador ahora es bin/skillsync (subcomando link).
# PC nueva completa: bootstrap + `skillsync install && skillsync manifest && skillsync timer install`
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/bin/skillsync" link "$@"
