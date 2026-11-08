#!/usr/bin/env bash
# Thin wrapper: forwards all arguments to the Python installer. See install.py --help.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${PYTHON:-$(command -v python3 || command -v python)}"
exec "$PY" "$HERE/install.py" "$@"
