#!/bin/sh

wadi_make_cmd() {
  printf '%s\n' "${WADI_MAKE:-make}"
}

wadi_bootstrap_binary() {
  root_dir=$1
  repo_bin=$root_dir/_bootstrap/bin/wadi
  target_path=_bootstrap/bin/wadi
  make_cmd=$(wadi_make_cmd)
  ocaml_cmd=${OCAML:-ocaml}
  ocamlc_cmd=${OCAMLC:-ocamlc}
  ocamlopt_cmd=${OCAMLOPT:-ocamlopt}
  ocamlfind_cmd=${OCAMLFIND:-ocamlfind}

  if ! command -v "$make_cmd" >/dev/null 2>&1; then
    echo "wadi: cannot self-bootstrap because '$make_cmd' is unavailable" >&2
    return 1
  fi

  echo "wadi: bootstrapping $repo_bin" >&2
  if MAKEFLAGS= MFLAGS= MAKELEVEL=0 \
    OCAML="$ocaml_cmd" OCAMLC="$ocamlc_cmd" OCAMLOPT="$ocamlopt_cmd" \
    OCAMLFIND="$ocamlfind_cmd" \
    "$make_cmd" -C "$root_dir" "$target_path" >&2; then
    :
  else
    echo "wadi: failed to bootstrap $repo_bin" >&2
    return 1
  fi
}

wadi_resolve_repo_binary() {
  root_dir=$1
  repo_bin=$root_dir/_bootstrap/bin/wadi

  if [ -n "${WADI_BIN:-}" ]; then
    if [ -x "$WADI_BIN" ]; then
      printf '%s\n' "$WADI_BIN"
      return 0
    fi
    echo "wadi: WADI_BIN is not executable: $WADI_BIN" >&2
    return 1
  fi

  if [ -f "$root_dir/Makefile" ]; then
    wadi_bootstrap_binary "$root_dir" || return 1
    if [ -x "$repo_bin" ]; then
      printf '%s\n' "$repo_bin"
      return 0
    fi
    echo "wadi: expected bootstrap binary at $repo_bin after self-host build" >&2
    return 1
  fi

  if [ -x "$repo_bin" ]; then
    printf '%s\n' "$repo_bin"
    return 0
  fi

  if command -v wadi >/dev/null 2>&1; then
    command -v wadi
    return 0
  fi

  echo "wadi: no repo-local or installed wadi binary found" >&2
  return 1
}
