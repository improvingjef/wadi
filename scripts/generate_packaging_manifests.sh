#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT_DIR/release/metadata.sh"

OUTPUT_DIR=$ROOT_DIR
SOURCE_ARCHIVE=
SOURCE_ARCHIVE_DIR=

usage() {
  cat <<'EOF'
Usage: generate_packaging_manifests.sh [--output-dir DIR] [--source-archive PATH | --source-archive-dir DIR]

Render packaging manifests that are derived from the canonical release
metadata, including oasis.opam and Formula/oasis.rb. Optionally reuse an
existing source archive or refresh one into a local directory so the generated
Homebrew checksum is inspectable.
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
    --source-archive)
      if [ "$#" -lt 2 ]; then
        echo "generate_packaging_manifests.sh: --source-archive requires a path" >&2
        exit 2
      fi
      SOURCE_ARCHIVE=$2
      shift 2
      ;;
    --source-archive-dir)
      if [ "$#" -lt 2 ]; then
        echo "generate_packaging_manifests.sh: --source-archive-dir requires a directory" >&2
        exit 2
      fi
      SOURCE_ARCHIVE_DIR=$2
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

if [ -n "$SOURCE_ARCHIVE" ] && [ -n "$SOURCE_ARCHIVE_DIR" ]; then
  echo "generate_packaging_manifests.sh: pass --source-archive or --source-archive-dir, not both" >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR/Formula"

"$ROOT_DIR/scripts/render_oasis_opam.sh" >"$OUTPUT_DIR/oasis.opam"
if [ -n "$SOURCE_ARCHIVE_DIR" ]; then
  mkdir -p "$SOURCE_ARCHIVE_DIR"
  "$ROOT_DIR/scripts/build_release_archives.sh" \
    --source-only \
    --output-dir "$SOURCE_ARCHIVE_DIR"
  SOURCE_ARCHIVE=$SOURCE_ARCHIVE_DIR/$(oasis_release_source_archive_name)
elif [ -z "$SOURCE_ARCHIVE" ]; then
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/oasis-release-manifests.XXXXXX")
  trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
  "$ROOT_DIR/scripts/build_release_archives.sh" \
    --source-only \
    --output-dir "$tmp_dir"
  SOURCE_ARCHIVE=$tmp_dir/$(oasis_release_source_archive_name)
fi

"$ROOT_DIR/scripts/render_homebrew_formula.sh" \
  --source-archive "$SOURCE_ARCHIVE" \
  >"$OUTPUT_DIR/Formula/oasis.rb"
