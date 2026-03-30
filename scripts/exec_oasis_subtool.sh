#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT_DIR/scripts/oasis_self_host.sh"

if [ "$#" -lt 1 ]; then
  echo "exec_oasis_subtool.sh: missing subtool name" >&2
  exit 2
fi

OASIS_CMD=$(oasis_resolve_repo_binary "$ROOT_DIR")

cd "$ROOT_DIR"
exec "$OASIS_CMD" "$@"
