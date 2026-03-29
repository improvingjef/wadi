#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT_DIR/release/metadata.sh"

OUTPUT_DIR=$ROOT_DIR

usage() {
  cat <<'EOF'
Usage: generate_packaging_manifests.sh [--output-dir DIR]

Render packaging manifests that are derived from the canonical release
metadata, including oasis.opam and Formula/oasis.rb.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-dir)
      if [ "$#" -lt 2 ]; then
        echo "generate_packaging_manifests.sh: --output-dir requires a directory" >&2
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
      echo "generate_packaging_manifests.sh: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR/Formula"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/oasis-release-manifests.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

bash "$ROOT_DIR/scripts/render_oasis_opam.sh" >"$OUTPUT_DIR/oasis.opam"
bash "$ROOT_DIR/scripts/build_release_archives.sh" \
  --source-only \
  --output-dir "$tmp_dir"
bash "$ROOT_DIR/scripts/render_homebrew_formula.sh" \
  --source-archive "$tmp_dir/$(oasis_release_source_archive_name)" \
  >"$OUTPUT_DIR/Formula/oasis.rb"
