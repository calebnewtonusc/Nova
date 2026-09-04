#!/usr/bin/env bash
# Nova doctor. Same checks as `nova doctor`, runnable straight from a clone
# before anything is installed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$ROOT/bin/nova" ]; then
  NOVA_ROOT="$ROOT" exec "$ROOT/bin/nova" doctor "$@"
fi
echo "doctor: bin/nova missing. Is this a complete checkout?" >&2
exit 1
