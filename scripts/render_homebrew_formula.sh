#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT_DIR/release/metadata.sh"

SOURCE_ARCHIVE=
SOURCE_SHA256=

usage() {
  cat <<'EOF'
Usage: render_homebrew_formula.sh [--source-archive PATH] [--source-sha256 SHA256]

Render the Homebrew formula for the current release metadata. Pass either a
prebuilt source archive path or an explicit sha256 value.
EOF
}

sha256_for_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source-archive)
      if [ "$#" -lt 2 ]; then
        echo "render_homebrew_formula.sh: --source-archive requires a path" >&2
        exit 2
      fi
      SOURCE_ARCHIVE=$2
      shift 2
      ;;
    --source-sha256)
      if [ "$#" -lt 2 ]; then
        echo "render_homebrew_formula.sh: --source-sha256 requires a value" >&2
        exit 2
      fi
      SOURCE_SHA256=$2
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "render_homebrew_formula.sh: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

if [ -n "$SOURCE_ARCHIVE" ]; then
  if [ ! -f "$SOURCE_ARCHIVE" ]; then
    echo "render_homebrew_formula.sh: source archive not found: $SOURCE_ARCHIVE" >&2
    exit 1
  fi
  SOURCE_SHA256=$(sha256_for_file "$SOURCE_ARCHIVE")
fi

if [ -z "$SOURCE_SHA256" ]; then
  echo "render_homebrew_formula.sh: provide --source-archive or --source-sha256" >&2
  exit 2
fi

cat <<EOF
class $OASIS_FORMULA_CLASS < Formula
  desc "$OASIS_SYNOPSIS"
  homepage "$OASIS_REPOSITORY_URL"
  url "$(oasis_release_source_archive_url)"
  sha256 "$SOURCE_SHA256"
  license "$OASIS_LICENSE"

  depends_on "ocaml"
  depends_on "ocaml-findlib"

  def install
    system "make", "release-artifacts"
    system "./scripts/install_release_tree.sh",
      "--package-root", "package",
      "--binary", "_bootstrap/bin/oasis",
      "--prefix", prefix
  end

  test do
    output = shell_output("#{bin}/oasis docs")
    assert_match "Oasis CLI", output
  end
end
EOF
