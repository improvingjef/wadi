#!/bin/sh

oasis_make_cmd() {
  printf '%s\n' "${OASIS_MAKE:-make}"
}

oasis_bootstrap_binary() {
  root_dir=$1
  repo_bin=$root_dir/_bootstrap/bin/oasis
  target_path=_bootstrap/bin/oasis
  make_cmd=$(oasis_make_cmd)
  ocaml_cmd=${OCAML:-ocaml}
  ocamlc_cmd=${OCAMLC:-ocamlc}
  ocamlopt_cmd=${OCAMLOPT:-ocamlopt}
  ocamlfind_cmd=${OCAMLFIND:-ocamlfind}

  if ! command -v "$make_cmd" >/dev/null 2>&1; then
    echo "oasis: cannot self-bootstrap because '$make_cmd' is unavailable" >&2
    return 1
  fi

  echo "oasis: bootstrapping $repo_bin" >&2
  if MAKEFLAGS= MFLAGS= MAKELEVEL=0 \
    OCAML="$ocaml_cmd" OCAMLC="$ocamlc_cmd" OCAMLOPT="$ocamlopt_cmd" \
    OCAMLFIND="$ocamlfind_cmd" \
    "$make_cmd" -C "$root_dir" "$target_path" >&2; then
    :
  else
    echo "oasis: failed to bootstrap $repo_bin" >&2
    return 1
  fi
}

oasis_resolve_repo_binary() {
  root_dir=$1
  repo_bin=$root_dir/_bootstrap/bin/oasis

  if [ -n "${OASIS_BIN:-}" ]; then
    if [ -x "$OASIS_BIN" ]; then
      printf '%s\n' "$OASIS_BIN"
      return 0
    fi
    echo "oasis: OASIS_BIN is not executable: $OASIS_BIN" >&2
    return 1
  fi

  if [ -f "$root_dir/Makefile" ]; then
    oasis_bootstrap_binary "$root_dir" || return 1
    if [ -x "$repo_bin" ]; then
      printf '%s\n' "$repo_bin"
      return 0
    fi
    echo "oasis: expected bootstrap binary at $repo_bin after self-host build" >&2
    return 1
  fi

  if [ -x "$repo_bin" ]; then
    printf '%s\n' "$repo_bin"
    return 0
  fi

  if command -v oasis >/dev/null 2>&1; then
    command -v oasis
    return 0
  fi

  echo "oasis: no repo-local or installed oasis binary found" >&2
  return 1
}
