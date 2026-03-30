#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

if [ "$#" -lt 1 ]; then
  echo "exec_oasis_subtool.sh: missing subtool name" >&2
  exit 2
fi

if [ -n "${OASIS_BIN:-}" ]; then
  OASIS_CMD=$OASIS_BIN
elif [ -x "$ROOT_DIR/_bootstrap/bin/oasis" ]; then
  OASIS_CMD=$ROOT_DIR/_bootstrap/bin/oasis
elif command -v oasis >/dev/null 2>&1; then
  OASIS_CMD=$(command -v oasis)
else
  echo "exec_oasis_subtool.sh: set OASIS_BIN or build _bootstrap/bin/oasis first" >&2
  exit 1
fi

cd "$ROOT_DIR"
exec "$OASIS_CMD" "$@"
