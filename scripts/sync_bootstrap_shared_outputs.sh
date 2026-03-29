#!/bin/sh
set -eu

MAKEFILE_PATH=
METADATA_PATH=
OBJ_DIR=
OBJ_EXT=

usage() {
  cat <<'EOF'
Usage: sync_bootstrap_shared_outputs.sh --makefile PATH --metadata PATH --obj-dir DIR --obj-ext EXT

Touch or prune shared bootstrap objects based on the generated bootstrap
makefile's COMMON_SEED_REUSE flag and the live seed metadata module list.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --makefile)
      if [ "$#" -lt 2 ]; then
        echo "sync_bootstrap_shared_outputs.sh: --makefile requires a path" >&2
        exit 2
      fi
      MAKEFILE_PATH=$2
      shift 2
      ;;
    --metadata)
      if [ "$#" -lt 2 ]; then
        echo "sync_bootstrap_shared_outputs.sh: --metadata requires a path" >&2
        exit 2
      fi
      METADATA_PATH=$2
      shift 2
      ;;
    --obj-dir)
      if [ "$#" -lt 2 ]; then
        echo "sync_bootstrap_shared_outputs.sh: --obj-dir requires a path" >&2
        exit 2
      fi
      OBJ_DIR=$2
      shift 2
      ;;
    --obj-ext)
      if [ "$#" -lt 2 ]; then
        echo "sync_bootstrap_shared_outputs.sh: --obj-ext requires a value" >&2
        exit 2
      fi
      OBJ_EXT=$2
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "sync_bootstrap_shared_outputs.sh: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

if [ -z "$MAKEFILE_PATH" ] || [ -z "$METADATA_PATH" ] || [ -z "$OBJ_DIR" ] || [ -z "$OBJ_EXT" ]; then
  usage >&2
  exit 2
fi

if [ ! -f "$MAKEFILE_PATH" ]; then
  echo "sync_bootstrap_shared_outputs.sh: generated makefile not found: $MAKEFILE_PATH" >&2
  exit 1
fi

if [ ! -f "$METADATA_PATH" ]; then
  echo "sync_bootstrap_shared_outputs.sh: seed metadata not found: $METADATA_PATH" >&2
  exit 1
fi

shared_stems=$(sed -n 's/^BOOTSTRAP_LIBRARY_MODULE_STEMS := //p' "$METADATA_PATH")
shared_outputs=

for stem in $shared_stems; do
  shared_outputs="$shared_outputs $OBJ_DIR/$stem.$OBJ_EXT $OBJ_DIR/$stem.cmi $OBJ_DIR/$stem.o"
done

if grep -q '^COMMON_SEED_REUSE := yes$' "$MAKEFILE_PATH"; then
  for path in $shared_outputs; do
    if [ -f "$path" ]; then
      touch "$path"
    fi
  done
else
  if [ -n "$shared_outputs" ]; then
    rm -f $shared_outputs
  fi
fi
