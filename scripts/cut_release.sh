#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
VERSION=
CREATE_TAG=0

usage() {
  cat <<'EOF'
Usage: cut_release.sh --version X.Y.Z [--tag]

Update the canonical release metadata, regenerate packaging manifests from a
fresh source archive, validate the generated package definitions, and
optionally create the matching git tag.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      if [ "$#" -lt 2 ]; then
        echo "cut_release.sh: --version requires a value" >&2
        exit 2
      fi
      VERSION=$2
      shift 2
      ;;
    --tag)
      CREATE_TAG=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "cut_release.sh: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "cut_release.sh: --version is required" >&2
  exit 2
fi

case "$VERSION" in
  *[!0-9.]* | .* | *.) 
    echo "cut_release.sh: version must look like X.Y.Z" >&2
    exit 2
    ;;
esac

if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "cut_release.sh: version must look like X.Y.Z" >&2
  exit 2
fi

if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "cut_release.sh: $ROOT_DIR is not a git repository" >&2
  exit 1
fi

METADATA_PATH=$ROOT_DIR/release/metadata.sh
tmp_metadata=$(mktemp "${TMPDIR:-/tmp}/oasis-release-metadata.XXXXXX")
trap 'rm -f "$tmp_metadata"' EXIT HUP INT TERM

sed "s/^OASIS_RELEASE_VERSION='[^']*'$/OASIS_RELEASE_VERSION='$VERSION'/" \
  "$METADATA_PATH" >"$tmp_metadata"

if ! grep -q "^OASIS_RELEASE_VERSION='$VERSION'$" "$tmp_metadata"; then
  echo "cut_release.sh: failed to update $METADATA_PATH" >&2
  exit 1
fi

mv "$tmp_metadata" "$METADATA_PATH"

"$ROOT_DIR/scripts/generate_packaging_manifests.sh" --source-archive-dir "$ROOT_DIR/dist"

ruby -c "$ROOT_DIR/Formula/oasis.rb" >/dev/null
opam lint "$ROOT_DIR/oasis.opam" >/dev/null

. "$ROOT_DIR/release/metadata.sh"
EXPECTED_TAG=$(oasis_release_tag)

if [ "$CREATE_TAG" -eq 1 ]; then
  if git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/$EXPECTED_TAG" >/dev/null 2>&1; then
    echo "cut_release.sh: git tag already exists: $EXPECTED_TAG" >&2
    exit 1
  fi
  git -C "$ROOT_DIR" \
    -c user.name="$OASIS_MAINTAINER_NAME" \
    -c user.email="$OASIS_MAINTAINER_EMAIL" \
    tag -a "$EXPECTED_TAG" -m "$OASIS_PACKAGE_NAME $VERSION"
fi

printf 'Release cut for %s refreshed release/metadata.sh, oasis.opam, Formula/oasis.rb, and dist/%s\n' \
  "$EXPECTED_TAG" "$(oasis_release_source_archive_name)"
