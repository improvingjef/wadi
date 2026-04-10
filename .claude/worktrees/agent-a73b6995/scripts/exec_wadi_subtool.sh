#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT_DIR/scripts/wadi_self_host.sh"

if [ "$#" -lt 1 ]; then
  echo "exec_wadi_subtool.sh: missing subtool name" >&2
  exit 2
fi

WADI_CMD=$(wadi_resolve_repo_binary "$ROOT_DIR")

cd "$ROOT_DIR"
exec "$WADI_CMD" "$@"
