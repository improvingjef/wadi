#!/bin/sh

OASIS_PACKAGE_NAME='oasis'
OASIS_FORMULA_CLASS='Oasis'
OASIS_RELEASE_VERSION='0.1.0'
OASIS_RELEASE_TAG_PREFIX='v'
OASIS_SYNOPSIS='Dune-free OCaml workspace toolbox'
OASIS_DESCRIPTION='oasis is a Dune-free OCaml workspace tool with cohesive subtools for build, test, run, bench, migration, install, diagnostics, and bootstrap workflows.'
OASIS_MAINTAINER_NAME='Jef Newsom'
OASIS_MAINTAINER_EMAIL='jef.newsom@gmail.com'
OASIS_AUTHORS='Jef Newsom'
OASIS_LICENSE='MIT'
OASIS_REPOSITORY_URL='https://github.com/jef/oasis'
OASIS_BUG_REPORTS_URL='https://github.com/jef/oasis/issues'
OASIS_DEV_REPO='git+https://github.com/jef/oasis.git'
OASIS_HOMEBREW_TAP='jef/oasis'

oasis_release_tag() {
  printf '%s%s\n' "$OASIS_RELEASE_TAG_PREFIX" "$OASIS_RELEASE_VERSION"
}

oasis_release_source_dir_name() {
  printf '%s-%s\n' "$OASIS_PACKAGE_NAME" "$OASIS_RELEASE_VERSION"
}

oasis_release_source_archive_name() {
  printf '%s-source.tar.gz\n' "$(oasis_release_source_dir_name)"
}

oasis_release_binary_dir_name() {
  os_name=$1
  arch_name=$2
  printf '%s-%s-%s-%s\n' "$OASIS_PACKAGE_NAME" "$OASIS_RELEASE_VERSION" \
    "$arch_name" "$os_name"
}

oasis_release_binary_archive_name() {
  os_name=$1
  arch_name=$2
  printf '%s.tar.gz\n' "$(oasis_release_binary_dir_name "$os_name" "$arch_name")"
}

oasis_release_download_base_url() {
  printf '%s/releases/download/%s\n' "$OASIS_REPOSITORY_URL" \
    "$(oasis_release_tag)"
}

oasis_release_archive_url() {
  archive_name=$1
  printf '%s/%s\n' "$(oasis_release_download_base_url)" "$archive_name"
}

oasis_release_source_archive_url() {
  oasis_release_archive_url "$(oasis_release_source_archive_name)"
}

oasis_homebrew_tap_owner() {
  printf '%s\n' "${OASIS_HOMEBREW_TAP%%/*}"
}

oasis_homebrew_tap_name() {
  printf '%s\n' "${OASIS_HOMEBREW_TAP#*/}"
}

oasis_homebrew_tap_repository_name() {
  printf 'homebrew-%s\n' "$(oasis_homebrew_tap_name)"
}

oasis_homebrew_tap_repository() {
  printf '%s/%s\n' "$(oasis_homebrew_tap_owner)" \
    "$(oasis_homebrew_tap_repository_name)"
}

oasis_homebrew_tap_repository_url() {
  printf 'https://github.com/%s\n' "$(oasis_homebrew_tap_repository)"
}
