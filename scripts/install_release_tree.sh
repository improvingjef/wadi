#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PACKAGE_ROOT=$ROOT_DIR/package
BINARY_PATH=${OASIS_BIN:-$ROOT_DIR/_bootstrap/bin/oasis}
PREFIX=

usage() {
  cat <<'EOF'
Usage: install_release_tree.sh --prefix DIR [--package-root DIR] [--binary PATH]

Install the staged release tree under DIR. This copies the generated
`package/share/...` payload and installs the oasis binary as `bin/oasis`.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)
      if [ $# -lt 2 ]; then
        echo "install_release_tree.sh: --prefix requires a directory" >&2
        exit 2
      fi
      PREFIX=$2
      shift 2
      ;;
    --package-root)
      if [ $# -lt 2 ]; then
        echo "install_release_tree.sh: --package-root requires a directory" >&2
        exit 2
      fi
      PACKAGE_ROOT=$2
      shift 2
      ;;
    --binary)
      if [ $# -lt 2 ]; then
        echo "install_release_tree.sh: --binary requires a path" >&2
        exit 2
      fi
      BINARY_PATH=$2
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "install_release_tree.sh: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

if [ -z "$PREFIX" ]; then
  echo "install_release_tree.sh: --prefix is required" >&2
  exit 2
fi

if [ ! -d "$PACKAGE_ROOT" ]; then
  echo "install_release_tree.sh: package root not found: $PACKAGE_ROOT" >&2
  exit 1
fi

if [ ! -f "$BINARY_PATH" ]; then
  echo "install_release_tree.sh: binary not found: $BINARY_PATH" >&2
  exit 1
fi

mkdir -p "$PREFIX/bin"
install -m 0755 "$BINARY_PATH" "$PREFIX/bin/oasis"
cp -R "$PACKAGE_ROOT"/. "$PREFIX"/
