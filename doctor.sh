#!/usr/bin/env bash
# Jarvis doctor. Same checks as `jarvis doctor`, runnable straight from a clone
# before anything is installed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$ROOT/bin/jarvis" ]; then
  JARVIS_ROOT="$ROOT" exec "$ROOT/bin/jarvis" doctor "$@"
fi
echo "doctor: bin/jarvis missing. Is this a complete checkout?" >&2
exit 1
