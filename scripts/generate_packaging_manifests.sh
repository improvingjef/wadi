#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT_DIR/release/metadata.sh"

OUTPUT_DIR=$ROOT_DIR
SOURCE_ARCHIVE=
SOURCE_ARCHIVE_DIR=
REUSE_SOURCE_ARCHIVE_DIR=
FORMULA_OUTPUT=
CHECKSUMS_OUTPUT=
TEMP_DIR=
TEMP_CHECKSUMS=

usage() {
  cat <<'EOF'
Usage: generate_packaging_manifests.sh [--output-dir DIR] [--formula-output PATH] [--checksums-output PATH] [--source-archive PATH | --source-archive-dir DIR | --reuse-source-archive-dir DIR]

Render packaging manifests that are derived from the canonical release
metadata, including oasis.opam and Formula/oasis.rb. Optionally reuse an
existing source archive or refresh one into a local directory so the generated
Homebrew checksum is inspectable. The formula can also be emitted directly into
another asset layout, such as dist/oasis.rb for GitHub releases.
EOF
}

cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
  if [ -n "$TEMP_CHECKSUMS" ] && [ -f "$TEMP_CHECKSUMS" ]; then
    rm -f "$TEMP_CHECKSUMS"
  fi
}

trap cleanup EXIT HUP INT TERM

sha256_for_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
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
    --formula-output)
      if [ "$#" -lt 2 ]; then
        echo "generate_packaging_manifests.sh: --formula-output requires a path" >&2
        exit 2
      fi
      FORMULA_OUTPUT=$2
      shift 2
      ;;
    --checksums-output)
      if [ "$#" -lt 2 ]; then
        echo "generate_packaging_manifests.sh: --checksums-output requires a path" >&2
        exit 2
      fi
      CHECKSUMS_OUTPUT=$2
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
    --reuse-source-archive-dir)
      if [ "$#" -lt 2 ]; then
        echo "generate_packaging_manifests.sh: --reuse-source-archive-dir requires a directory" >&2
        exit 2
      fi
      REUSE_SOURCE_ARCHIVE_DIR=$2
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

selected_archive_inputs=0
for value in "$SOURCE_ARCHIVE" "$SOURCE_ARCHIVE_DIR" "$REUSE_SOURCE_ARCHIVE_DIR"; do
  if [ -n "$value" ]; then
    selected_archive_inputs=$((selected_archive_inputs + 1))
  fi
done

if [ "$selected_archive_inputs" -gt 1 ]; then
  echo "generate_packaging_manifests.sh: pass only one of --source-archive, --source-archive-dir, or --reuse-source-archive-dir" >&2
  exit 2
fi

if [ -z "$FORMULA_OUTPUT" ]; then
  FORMULA_OUTPUT=$OUTPUT_DIR/Formula/oasis.rb
fi

mkdir -p "$OUTPUT_DIR"
"$ROOT_DIR/scripts/render_oasis_opam.sh" >"$OUTPUT_DIR/oasis.opam"
if [ -n "$REUSE_SOURCE_ARCHIVE_DIR" ]; then
  SOURCE_ARCHIVE=$REUSE_SOURCE_ARCHIVE_DIR/$(oasis_release_source_archive_name)
  if [ ! -f "$SOURCE_ARCHIVE" ]; then
    echo "generate_packaging_manifests.sh: reusable source archive not found: $SOURCE_ARCHIVE" >&2
    exit 1
  fi
elif [ -n "$SOURCE_ARCHIVE_DIR" ]; then
  mkdir -p "$SOURCE_ARCHIVE_DIR"
  SOURCE_ARCHIVE=$SOURCE_ARCHIVE_DIR/$(oasis_release_source_archive_name)
  "$ROOT_DIR/scripts/build_release_archives.sh" \
    --source-only \
    --output-dir "$SOURCE_ARCHIVE_DIR"
elif [ -z "$SOURCE_ARCHIVE" ]; then
  TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oasis-release-manifests.XXXXXX")
  "$ROOT_DIR/scripts/build_release_archives.sh" \
    --source-only \
    --output-dir "$TEMP_DIR"
  SOURCE_ARCHIVE=$TEMP_DIR/$(oasis_release_source_archive_name)
fi

mkdir -p "$(dirname "$FORMULA_OUTPUT")"
"$ROOT_DIR/scripts/render_homebrew_formula.sh" \
  --source-archive "$SOURCE_ARCHIVE" \
  >"$FORMULA_OUTPUT"

if [ -n "$CHECKSUMS_OUTPUT" ]; then
  set -- "$OUTPUT_DIR"/*.tar.gz
  if [ "$1" = "$OUTPUT_DIR/*.tar.gz" ] || [ ! -e "$1" ]; then
    echo "generate_packaging_manifests.sh: no release archives found under $OUTPUT_DIR for --checksums-output" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$CHECKSUMS_OUTPUT")"
  TEMP_CHECKSUMS=$(mktemp "${TMPDIR:-/tmp}/oasis-release-checksums.XXXXXX")
  : >"$TEMP_CHECKSUMS"
  for archive in "$@"; do
    printf '%s  %s\n' "$(sha256_for_file "$archive")" "$archive" >>"$TEMP_CHECKSUMS"
  done
  mv "$TEMP_CHECKSUMS" "$CHECKSUMS_OUTPUT"
  TEMP_CHECKSUMS=
fi
