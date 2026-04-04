#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT_DIR/release/metadata.sh"
. "$ROOT_DIR/scripts/release_locale.sh"
. "$ROOT_DIR/scripts/wadi_self_host.sh"

export COPYFILE_DISABLE=1

wadi_apply_release_archive_env

OUTPUT_DIR=$ROOT_DIR/dist
BINARY_PATH=${WADI_BIN:-$ROOT_DIR/_bootstrap/bin/wadi}
BINARY_PATH_EXPLICIT=0
BUILD_SOURCE=1
BUILD_BINARY=1
OS_NAME=
ARCH_NAME=
SOURCE_ARCHIVE_MODE=tracked

usage() {
  cat <<'EOF'
Usage: build_release_archives.sh [--output-dir DIR] [--binary PATH] [--os OS --arch ARCH] [--source-only] [--binary-only] [--source-archive-mode tracked|worktree]

Build deterministic source and/or binary release archives from the current
workspace tree.
EOF
}

tracked_worktree_roots() {
  src_root=$1
  git -C "$src_root" ls-files \
    | awk -F/ 'NF > 1 { print $1 }' \
    | sort -u
}

list_source_paths() {
  src_root=$1
  case "$SOURCE_ARCHIVE_MODE" in
    tracked)
      git -C "$src_root" ls-files --cached --modified
      ;;
    worktree)
      git -C "$src_root" ls-files --cached --modified
      tracked_roots=$(tracked_worktree_roots "$src_root")
      if [ -n "$tracked_roots" ]; then
        # shellcheck disable=SC2086
        git -C "$src_root" ls-files --others --exclude-standard -- $tracked_roots
      fi
      ;;
    *)
      echo "build_release_archives.sh: unknown source archive mode '$SOURCE_ARCHIVE_MODE'" >&2
      exit 2
      ;;
  esac | sort -u
}

copy_tree_files() {
  src_root=$1
  dst_root=$2
  list_source_paths "$src_root" \
    | while IFS= read -r relative_path; do
        [ -n "$relative_path" ] || continue
        if [ "$relative_path" = "Formula/wadi.rb" ]; then
          continue
        fi
        src_path=$src_root/$relative_path
        dst_path=$dst_root/$relative_path
        if [ -f "$src_path" ]; then
          mkdir -p "$(dirname "$dst_path")"
          cp "$src_path" "$dst_path"
        fi
      done
}

strip_extended_attributes() {
  tree_root=$1
  if command -v xattr >/dev/null 2>&1; then
    xattr -c -r "$tree_root" 2>/dev/null || true
  fi
}

normalize_tree() {
  tree_root=$1
  strip_extended_attributes "$tree_root"
  find "$tree_root" -exec touch -t 202601010000 {} +
}

create_archive() {
  parent_dir=$1
  root_name=$2
  archive_path=$3
  tmp_tar=$(mktemp "${TMPDIR:-/tmp}/wadi-release-tar.XXXXXX")
  file_list=$(mktemp "${TMPDIR:-/tmp}/wadi-release-files.XXXXXX")
  (
    cd "$parent_dir"
    {
      find "$root_name" -type d -empty -print
      find "$root_name" \( -type f -o -type l \) -print
    } | sort >"$file_list"
    tar -cf "$tmp_tar" -T "$file_list"
  )
  gzip -n -c "$tmp_tar" >"$archive_path"
  rm -f "$tmp_tar" "$file_list"
}

build_source_archive() {
  archive_name=$(wadi_release_source_archive_name)
  root_name=$(wadi_release_source_dir_name)
  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/wadi-release-source.XXXXXX")
  trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
  stage_root=$work_dir/$root_name
  mkdir -p "$stage_root"
  copy_tree_files "$ROOT_DIR" "$stage_root"
  normalize_tree "$stage_root"
  create_archive "$work_dir" "$root_name" "$OUTPUT_DIR/$archive_name"
  rm -rf "$work_dir"
  trap - EXIT HUP INT TERM
}

build_binary_archive() {
  if [ -z "$OS_NAME" ] || [ -z "$ARCH_NAME" ]; then
    echo "build_release_archives.sh: binary archives require --os and --arch" >&2
    exit 2
  fi
  if [ "$BINARY_PATH_EXPLICIT" -eq 0 ]; then
    BINARY_PATH=$(wadi_resolve_repo_binary "$ROOT_DIR")
  fi
  if [ ! -f "$BINARY_PATH" ]; then
    echo "build_release_archives.sh: binary not found: $BINARY_PATH" >&2
    exit 1
  fi
  archive_name=$(wadi_release_binary_archive_name "$OS_NAME" "$ARCH_NAME")
  root_name=$(wadi_release_binary_dir_name "$OS_NAME" "$ARCH_NAME")
  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/wadi-release-binary.XXXXXX")
  trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
  package_dir=$work_dir/package-root
  install_root=$work_dir/$root_name
  WADI_BIN=$BINARY_PATH "$ROOT_DIR/scripts/generate_release_artifacts.sh" \
    --output-dir "$package_dir"
  "$ROOT_DIR/scripts/install_release_tree.sh" \
    --package-root "$package_dir/package" \
    --binary "$BINARY_PATH" \
    --prefix "$install_root"
  normalize_tree "$install_root"
  create_archive "$work_dir" "$root_name" "$OUTPUT_DIR/$archive_name"
  rm -rf "$work_dir"
  trap - EXIT HUP INT TERM
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-dir)
      if [ "$#" -lt 2 ]; then
        echo "build_release_archives.sh: --output-dir requires a directory" >&2
        exit 2
      fi
      OUTPUT_DIR=$2
      shift 2
      ;;
    --binary)
      if [ "$#" -lt 2 ]; then
        echo "build_release_archives.sh: --binary requires a path" >&2
        exit 2
      fi
      BINARY_PATH=$2
      BINARY_PATH_EXPLICIT=1
      shift 2
      ;;
    --os)
      if [ "$#" -lt 2 ]; then
        echo "build_release_archives.sh: --os requires a value" >&2
        exit 2
      fi
      OS_NAME=$2
      shift 2
      ;;
    --arch)
      if [ "$#" -lt 2 ]; then
        echo "build_release_archives.sh: --arch requires a value" >&2
        exit 2
      fi
      ARCH_NAME=$2
      shift 2
      ;;
    --source-only)
      BUILD_SOURCE=1
      BUILD_BINARY=0
      shift
      ;;
    --binary-only)
      BUILD_SOURCE=0
      BUILD_BINARY=1
      shift
      ;;
    --source-archive-mode)
      if [ "$#" -lt 2 ]; then
        echo "build_release_archives.sh: --source-archive-mode requires tracked or worktree" >&2
        exit 2
      fi
      SOURCE_ARCHIVE_MODE=$2
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "build_release_archives.sh: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR"

if [ "$BUILD_SOURCE" -eq 1 ]; then
  build_source_archive
fi

if [ "$BUILD_BINARY" -eq 1 ]; then
  build_binary_archive
fi
