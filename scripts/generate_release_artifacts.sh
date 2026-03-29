#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUTPUT_DIR=$ROOT_DIR
OASIS_BIN=${OASIS_BIN:-$ROOT_DIR/_bootstrap/bin/oasis}

usage() {
  cat <<'EOF'
Usage: generate_release_artifacts.sh [--output-dir DIR]

Render the public CLI reference and packaged shell-completion artifacts from
the live oasis binary.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --output-dir)
      if [ $# -lt 2 ]; then
        echo "generate_release_artifacts.sh: --output-dir requires a directory" >&2
        exit 2
      fi
      OUTPUT_DIR=$2
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "generate_release_artifacts.sh: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR/docs" "$OUTPUT_DIR/completions"

"$OASIS_BIN" docs >"$OUTPUT_DIR/docs/cli.md"
"$OASIS_BIN" completion bash >"$OUTPUT_DIR/completions/oasis.bash"
"$OASIS_BIN" completion zsh >"$OUTPUT_DIR/completions/_oasis"
"$OASIS_BIN" completion fish >"$OUTPUT_DIR/completions/oasis.fish"
