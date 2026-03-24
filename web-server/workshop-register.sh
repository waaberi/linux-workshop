#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PYTHON_BIN="$ROOT/.venv/bin/python"

if [ ! -x "$PYTHON_BIN" ]; then
    echo "Web server virtualenv is missing. Re-run ./install-host-broker.sh." >&2
    exit 1
fi

exec "$PYTHON_BIN" -m uvicorn app:app --app-dir "$ROOT" --host "${WORKSHOP_REGISTRATION_BIND:-0.0.0.0}" --port "${WORKSHOP_REGISTRATION_PORT:-8088}"
