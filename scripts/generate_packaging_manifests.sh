#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT_DIR/release/metadata.sh"

OUTPUT_DIR=$ROOT_DIR
SOURCE_ARCHIVE=
SOURCE_ARCHIVE_DIR=
REUSE_SOURCE_ARCHIVE_DIR=
OPAM_OUTPUT=
FORMULA_OUTPUT=
CHECKSUMS_OUTPUT=
ASSET_INDEX_OUTPUT=
TEMP_DIR=
TEMP_CHECKSUMS=
TEMP_ARCHIVE_LIST=
TEMP_ASSET_RECORDS=
TEMP_ASSET_NAMES=
TEMP_ASSET_INDEX=
ASSET_KIND=
ASSET_OS=
ASSET_ARCH=

usage() {
  cat <<'EOF'
Usage: generate_packaging_manifests.sh [--output-dir DIR] [--opam-output PATH] [--formula-output PATH] [--checksums-output PATH] [--asset-index-output PATH] [--source-archive PATH | --source-archive-dir DIR | --reuse-source-archive-dir DIR]

Render packaging manifests that are derived from the canonical release
metadata, including oasis.opam and Formula/oasis.rb. Optionally reuse an
existing source archive or refresh one into a local directory so the generated
Homebrew checksum is inspectable. The formula can also be emitted directly into
another asset layout, such as dist/oasis.rb for GitHub releases. When
requested, also emit a machine-readable release asset index with filenames,
URLs, and checksums for downstream automation.
EOF
}

cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
  if [ -n "$TEMP_CHECKSUMS" ] && [ -f "$TEMP_CHECKSUMS" ]; then
    rm -f "$TEMP_CHECKSUMS"
  fi
  if [ -n "$TEMP_ARCHIVE_LIST" ] && [ -f "$TEMP_ARCHIVE_LIST" ]; then
    rm -f "$TEMP_ARCHIVE_LIST"
  fi
  if [ -n "$TEMP_ASSET_RECORDS" ] && [ -f "$TEMP_ASSET_RECORDS" ]; then
    rm -f "$TEMP_ASSET_RECORDS"
  fi
  if [ -n "$TEMP_ASSET_NAMES" ] && [ -f "$TEMP_ASSET_NAMES" ]; then
    rm -f "$TEMP_ASSET_NAMES"
  fi
  if [ -n "$TEMP_ASSET_INDEX" ] && [ -f "$TEMP_ASSET_INDEX" ]; then
    rm -f "$TEMP_ASSET_INDEX"
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

json_quote() {
  escaped=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '"%s"' "$escaped"
}

file_size_bytes() {
  wc -c <"$1" | tr -d '[:space:]'
}

ensure_asset_tracking_files() {
  if [ -z "$TEMP_ASSET_RECORDS" ]; then
    TEMP_ASSET_RECORDS=$(mktemp "${TMPDIR:-/tmp}/oasis-release-assets.XXXXXX")
    : >"$TEMP_ASSET_RECORDS"
  fi
  if [ -z "$TEMP_ASSET_NAMES" ]; then
    TEMP_ASSET_NAMES=$(mktemp "${TMPDIR:-/tmp}/oasis-release-asset-names.XXXXXX")
    : >"$TEMP_ASSET_NAMES"
  fi
}

asset_name_seen() {
  if [ -z "$TEMP_ASSET_NAMES" ] || [ ! -f "$TEMP_ASSET_NAMES" ]; then
    return 1
  fi
  grep -Fxq -- "$1" "$TEMP_ASSET_NAMES"
}

record_asset() {
  asset_path=$1
  asset_kind=$2
  asset_os=$3
  asset_arch=$4
  [ -f "$asset_path" ] || return 0
  ensure_asset_tracking_files
  asset_name=$(basename "$asset_path")
  if asset_name_seen "$asset_name"; then
    return 0
  fi
  printf '%s\n' "$asset_name" >>"$TEMP_ASSET_NAMES"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$asset_name" \
    "$asset_kind" \
    "$(oasis_release_asset_url "$asset_name")" \
    "$(sha256_for_file "$asset_path")" \
    "$(file_size_bytes "$asset_path")" \
    "$asset_os" \
    "$asset_arch" \
    >>"$TEMP_ASSET_RECORDS"
}

classify_archive_name() {
  archive_name=$1
  ASSET_KIND=archive
  ASSET_OS=
  ASSET_ARCH=
  if [ "$archive_name" = "$(oasis_release_source_archive_name)" ]; then
    ASSET_KIND=source_archive
    return 0
  fi
  prefix="$(oasis_release_source_dir_name)-"
  suffix=".tar.gz"
  case "$archive_name" in
    "$prefix"*"$suffix")
      remainder=${archive_name#"$prefix"}
      remainder=${remainder%"$suffix"}
      asset_arch=${remainder%%-*}
      asset_os=${remainder#"$asset_arch"-}
      if [ -n "$asset_arch" ] && [ -n "$asset_os" ] && [ "$asset_os" != "$remainder" ]; then
        ASSET_KIND=binary_archive
        ASSET_OS=$asset_os
        ASSET_ARCH=$asset_arch
      fi
      ;;
  esac
}

record_archive_asset() {
  archive_path=$1
  classify_archive_name "$(basename "$archive_path")"
  record_asset "$archive_path" "$ASSET_KIND" "$ASSET_OS" "$ASSET_ARCH"
}

append_unique_archive_path() {
  archive_path=$1
  [ -f "$archive_path" ] || return 0
  if grep -Fxq -- "$archive_path" "$TEMP_ARCHIVE_LIST"; then
    return 0
  fi
  printf '%s\n' "$archive_path" >>"$TEMP_ARCHIVE_LIST"
}

render_asset_index() {
  mkdir -p "$(dirname "$ASSET_INDEX_OUTPUT")"
  ensure_asset_tracking_files
  if [ -f "$SOURCE_ARCHIVE" ]; then
    record_archive_asset "$SOURCE_ARCHIVE"
  fi
  TEMP_ARCHIVE_LIST=$(mktemp "${TMPDIR:-/tmp}/oasis-release-asset-archives.XXXXXX")
  find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.tar.gz' | sort >"$TEMP_ARCHIVE_LIST"
  while IFS= read -r archive; do
    [ -n "$archive" ] || continue
    record_archive_asset "$archive"
  done <"$TEMP_ARCHIVE_LIST"
  record_asset "$OPAM_OUTPUT" "opam_metadata" "" ""
  record_asset "$FORMULA_OUTPUT" "homebrew_formula" "" ""
  if [ -n "$CHECKSUMS_OUTPUT" ] && [ -f "$CHECKSUMS_OUTPUT" ]; then
    record_asset "$CHECKSUMS_OUTPUT" "checksums" "" ""
  fi
  asset_count=$(wc -l <"$TEMP_ASSET_RECORDS" | tr -d '[:space:]')
  TEMP_ASSET_INDEX=$(mktemp "${TMPDIR:-/tmp}/oasis-release-asset-index.XXXXXX")
  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "package": %s,\n' "$(json_quote "$OASIS_PACKAGE_NAME")"
    printf '  "version": %s,\n' "$(json_quote "$OASIS_RELEASE_VERSION")"
    printf '  "tag": %s,\n' "$(json_quote "$(oasis_release_tag)")"
    printf '  "base_url": %s,\n' "$(json_quote "$(oasis_release_download_base_url)")"
    printf '  "assets": [\n'
    index=0
    while IFS="$(printf '\t')" read -r asset_name asset_kind asset_url asset_sha256 asset_size asset_os asset_arch; do
      [ -n "$asset_name" ] || continue
      index=$((index + 1))
      printf '    {\n'
      printf '      "name": %s,\n' "$(json_quote "$asset_name")"
      printf '      "kind": %s,\n' "$(json_quote "$asset_kind")"
      if [ -n "$asset_os" ]; then
        printf '      "os": %s,\n' "$(json_quote "$asset_os")"
      fi
      if [ -n "$asset_arch" ]; then
        printf '      "arch": %s,\n' "$(json_quote "$asset_arch")"
      fi
      printf '      "url": %s,\n' "$(json_quote "$asset_url")"
      printf '      "sha256": %s,\n' "$(json_quote "$asset_sha256")"
      printf '      "size_bytes": %s\n' "$asset_size"
      if [ "$index" -lt "$asset_count" ]; then
        printf '    },\n'
      else
        printf '    }\n'
      fi
    done <"$TEMP_ASSET_RECORDS"
    printf '  ]\n'
    printf '}\n'
  } >"$TEMP_ASSET_INDEX"
  mv "$TEMP_ASSET_INDEX" "$ASSET_INDEX_OUTPUT"
  TEMP_ASSET_INDEX=
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
    --opam-output)
      if [ "$#" -lt 2 ]; then
        echo "generate_packaging_manifests.sh: --opam-output requires a path" >&2
        exit 2
      fi
      OPAM_OUTPUT=$2
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
    --asset-index-output)
      if [ "$#" -lt 2 ]; then
        echo "generate_packaging_manifests.sh: --asset-index-output requires a path" >&2
        exit 2
      fi
      ASSET_INDEX_OUTPUT=$2
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

if [ -z "$OPAM_OUTPUT" ]; then
  OPAM_OUTPUT=$OUTPUT_DIR/oasis.opam
fi

mkdir -p "$OUTPUT_DIR"
mkdir -p "$(dirname "$OPAM_OUTPUT")"
"$ROOT_DIR/scripts/render_oasis_opam.sh" >"$OPAM_OUTPUT"
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
  TEMP_ARCHIVE_LIST=$(mktemp "${TMPDIR:-/tmp}/oasis-release-archives.XXXXXX")
  : >"$TEMP_ARCHIVE_LIST"
  if [ -f "$SOURCE_ARCHIVE" ]; then
    append_unique_archive_path "$SOURCE_ARCHIVE"
  fi
  find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.tar.gz' | sort \
    | while IFS= read -r archive; do
        [ -n "$archive" ] || continue
        append_unique_archive_path "$archive"
      done
  if [ ! -s "$TEMP_ARCHIVE_LIST" ]; then
    echo "generate_packaging_manifests.sh: no release archives found under $OUTPUT_DIR for --checksums-output" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$CHECKSUMS_OUTPUT")"
  TEMP_CHECKSUMS=$(mktemp "${TMPDIR:-/tmp}/oasis-release-checksums.XXXXXX")
  : >"$TEMP_CHECKSUMS"
  while IFS= read -r archive; do
    printf '%s  %s\n' "$(sha256_for_file "$archive")" "$archive" >>"$TEMP_CHECKSUMS"
  done <"$TEMP_ARCHIVE_LIST"
  rm -f "$TEMP_ARCHIVE_LIST"
  TEMP_ARCHIVE_LIST=
  for asset in "$OPAM_OUTPUT" "$FORMULA_OUTPUT"; do
    if [ -f "$asset" ]; then
      printf '%s  %s\n' "$(sha256_for_file "$asset")" "$asset" >>"$TEMP_CHECKSUMS"
    fi
  done
  mv "$TEMP_CHECKSUMS" "$CHECKSUMS_OUTPUT"
  TEMP_CHECKSUMS=
fi

if [ -n "$ASSET_INDEX_OUTPUT" ]; then
  render_asset_index
fi
