#!/bin/sh

WADI_PACKAGE_NAME='wadi'
WADI_FORMULA_CLASS='Wadi'
WADI_RELEASE_VERSION='0.1.0'
WADI_RELEASE_TAG_PREFIX='v'
WADI_SYNOPSIS='Dune-free OCaml workspace toolbox'
WADI_DESCRIPTION='wadi is a Dune-free OCaml workspace tool with cohesive subtools for build, test, run, bench, migration, install, diagnostics, and bootstrap workflows.'
WADI_MAINTAINER_NAME='Jef Newsom'
WADI_MAINTAINER_EMAIL='jef.newsom@gmail.com'
WADI_AUTHORS='Jef Newsom'
WADI_LICENSE='MIT'
WADI_REPOSITORY_URL='https://github.com/jef/wadi'
WADI_BUG_REPORTS_URL='https://github.com/jef/wadi/issues'
WADI_DEV_REPO='git+https://github.com/jef/wadi.git'
WADI_HOMEBREW_TAP='jef/wadi'
WADI_HOMEBREW_TAP_REMOTE_URL=''

wadi_release_tag() {
  printf '%s%s\n' "$WADI_RELEASE_TAG_PREFIX" "$WADI_RELEASE_VERSION"
}

wadi_release_source_dir_name() {
  printf '%s-%s\n' "$WADI_PACKAGE_NAME" "$WADI_RELEASE_VERSION"
}

wadi_release_source_archive_name() {
  printf '%s-source.tar.gz\n' "$(wadi_release_source_dir_name)"
}

wadi_release_asset_index_name() {
  printf 'release-assets.json\n'
}

wadi_release_binary_dir_name() {
  os_name=$1
  arch_name=$2
  printf '%s-%s-%s-%s\n' "$WADI_PACKAGE_NAME" "$WADI_RELEASE_VERSION" \
    "$arch_name" "$os_name"
}

wadi_release_binary_archive_name() {
  os_name=$1
  arch_name=$2
  printf '%s.tar.gz\n' "$(wadi_release_binary_dir_name "$os_name" "$arch_name")"
}

wadi_release_download_base_url() {
  printf '%s/releases/download/%s\n' "$WADI_REPOSITORY_URL" \
    "$(wadi_release_tag)"
}

wadi_release_asset_url() {
  asset_name=$1
  printf '%s/%s\n' "$(wadi_release_download_base_url)" "$asset_name"
}

wadi_release_archive_url() {
  archive_name=$1
  wadi_release_asset_url "$archive_name"
}

wadi_release_source_archive_url() {
  wadi_release_archive_url "$(wadi_release_source_archive_name)"
}

wadi_homebrew_tap_owner() {
  printf '%s\n' "${WADI_HOMEBREW_TAP%%/*}"
}

wadi_homebrew_tap_name() {
  printf '%s\n' "${WADI_HOMEBREW_TAP#*/}"
}

wadi_homebrew_tap_repository_name() {
  printf 'homebrew-%s\n' "$(wadi_homebrew_tap_name)"
}

wadi_homebrew_tap_repository() {
  printf '%s/%s\n' "$(wadi_homebrew_tap_owner)" \
    "$(wadi_homebrew_tap_repository_name)"
}

wadi_homebrew_tap_repository_url() {
  printf 'https://github.com/%s\n' "$(wadi_homebrew_tap_repository)"
}

wadi_homebrew_tap_clone_url() {
  if [ -n "${WADI_HOMEBREW_TAP_REMOTE_URL:-}" ]; then
    printf '%s\n' "$WADI_HOMEBREW_TAP_REMOTE_URL"
  else
    wadi_homebrew_tap_repository_url
  fi
}
