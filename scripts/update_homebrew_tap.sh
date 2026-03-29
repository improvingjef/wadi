#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT_DIR/release/metadata.sh"

TAP_DIR=
FORMULA_PATH=
SOURCE_ARCHIVE=
DO_COMMIT=0
DO_PUSH=0

usage() {
  cat <<'EOF'
Usage: update_homebrew_tap.sh --tap-dir DIR [--formula PATH | --source-archive PATH] [--commit] [--push]

Update a checked-out Homebrew tap repository with the generated oasis formula.
Pass either an existing formula file or a source archive path so the script can
render a fresh formula with the correct sha256.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tap-dir)
      if [ "$#" -lt 2 ]; then
        echo "update_homebrew_tap.sh: --tap-dir requires a directory" >&2
        exit 2
      fi
      TAP_DIR=$2
      shift 2
      ;;
    --formula)
      if [ "$#" -lt 2 ]; then
        echo "update_homebrew_tap.sh: --formula requires a path" >&2
        exit 2
      fi
      FORMULA_PATH=$2
      shift 2
      ;;
    --source-archive)
      if [ "$#" -lt 2 ]; then
        echo "update_homebrew_tap.sh: --source-archive requires a path" >&2
        exit 2
      fi
      SOURCE_ARCHIVE=$2
      shift 2
      ;;
    --commit)
      DO_COMMIT=1
      shift
      ;;
    --push)
      DO_PUSH=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "update_homebrew_tap.sh: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

if [ -z "$TAP_DIR" ]; then
  echo "update_homebrew_tap.sh: --tap-dir is required" >&2
  exit 2
fi

if [ "$DO_PUSH" -eq 1 ] && [ "$DO_COMMIT" -eq 0 ]; then
  echo "update_homebrew_tap.sh: --push requires --commit" >&2
  exit 2
fi

if [ -n "$FORMULA_PATH" ] && [ -n "$SOURCE_ARCHIVE" ]; then
  echo "update_homebrew_tap.sh: pass --formula or --source-archive, not both" >&2
  exit 2
fi

if [ ! -d "$TAP_DIR/.git" ]; then
  echo "update_homebrew_tap.sh: tap dir is not a git checkout: $TAP_DIR" >&2
  exit 1
fi

tmp_formula=
trap 'if [ -n "$tmp_formula" ] && [ -f "$tmp_formula" ]; then rm -f "$tmp_formula"; fi' EXIT HUP INT TERM

if [ -n "$SOURCE_ARCHIVE" ]; then
  if [ ! -f "$SOURCE_ARCHIVE" ]; then
    echo "update_homebrew_tap.sh: source archive not found: $SOURCE_ARCHIVE" >&2
    exit 1
  fi
  tmp_formula=$(mktemp "${TMPDIR:-/tmp}/oasis-homebrew-formula.XXXXXX")
  bash "$ROOT_DIR/scripts/render_homebrew_formula.sh" \
    --source-archive "$SOURCE_ARCHIVE" >"$tmp_formula"
  FORMULA_PATH=$tmp_formula
fi

if [ -z "$FORMULA_PATH" ]; then
  echo "update_homebrew_tap.sh: provide --formula or --source-archive" >&2
  exit 2
fi

if [ ! -f "$FORMULA_PATH" ]; then
  echo "update_homebrew_tap.sh: formula not found: $FORMULA_PATH" >&2
  exit 1
fi

mkdir -p "$TAP_DIR/Formula"
cp "$FORMULA_PATH" "$TAP_DIR/Formula/oasis.rb"

if [ -z "$(git -C "$TAP_DIR" status --short -- Formula/oasis.rb)" ]; then
  printf 'Homebrew tap already up to date: %s\n' "$TAP_DIR/Formula/oasis.rb"
  exit 0
fi

if [ "$DO_COMMIT" -eq 1 ]; then
  git -C "$TAP_DIR" add Formula/oasis.rb
  git -C "$TAP_DIR" \
    -c user.name="$OASIS_MAINTAINER_NAME" \
    -c user.email="$OASIS_MAINTAINER_EMAIL" \
    commit -m "$OASIS_PACKAGE_NAME $(oasis_release_tag)"
fi

if [ "$DO_PUSH" -eq 1 ]; then
  git -C "$TAP_DIR" push origin HEAD
fi

printf 'Updated %s for brew tap %s && brew install %s\n' \
  "$TAP_DIR/Formula/oasis.rb" "$OASIS_HOMEBREW_TAP" "$OASIS_PACKAGE_NAME"
