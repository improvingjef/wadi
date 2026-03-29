#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT_DIR/release/metadata.sh"

cat <<EOF
opam-version: "2.0"
synopsis: "$OASIS_SYNOPSIS"
description: """
$OASIS_DESCRIPTION
"""
maintainer: ["$OASIS_MAINTAINER_NAME <$OASIS_MAINTAINER_EMAIL>"]
authors: ["$OASIS_AUTHORS"]
homepage: ["$OASIS_REPOSITORY_URL"]
bug-reports: "$OASIS_BUG_REPORTS_URL"
dev-repo: "$OASIS_DEV_REPO"
license: "$OASIS_LICENSE"
depends: [
  "ocaml" {>= "5.4.0"}
  "ocamlfind"
]
build: [
  [make "release-artifacts"]
]
install: [
  [
    "./scripts/install_release_tree.sh"
    "--package-root"
    "package"
    "--binary"
    "_bootstrap/bin/oasis"
    "--prefix"
    prefix
  ]
]
EOF
