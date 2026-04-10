#!/bin/sh
# run_afl.sh — Run AFL++ fuzzing against wadi parsers.
#
# Prerequisites:
#   brew install afl++
#   opam switch create 5.4.0+afl ocaml-variants.5.4.0+options ocaml-option-afl
#   opam install crowbar afl-persistent
#   make  # rebuild with AFL-instrumented compiler
#
# Usage:
#   ./fuzz/run_afl.sh manifest   # fuzz the TOML manifest parser
#   ./fuzz/run_afl.sh paths      # fuzz path/env/action validation
#   ./fuzz/run_afl.sh cli        # fuzz CLI argument parsing
#
# Without AFL (crowbar quickcheck mode):
#   _bootstrap/bin/fuzz_manifest
#   _bootstrap/bin/fuzz_paths
#   _bootstrap/bin/fuzz_cli

set -eu

TARGET="${1:-manifest}"
FUZZ_BIN="_bootstrap/bin/fuzz_${TARGET}"
CORPUS="fuzz/corpus/${TARGET}"
OUTPUT="fuzz/output/${TARGET}"

if [ ! -f "$FUZZ_BIN" ]; then
  echo "error: $FUZZ_BIN not found. Run 'make' first." >&2
  exit 1
fi

if ! command -v afl-fuzz >/dev/null 2>&1; then
  echo "afl-fuzz not found. Running in crowbar quickcheck mode instead." >&2
  exec "$FUZZ_BIN"
fi

mkdir -p "$OUTPUT"

if [ ! -d "$CORPUS" ] || [ -z "$(ls -A "$CORPUS" 2>/dev/null)" ]; then
  echo "error: no seed corpus at $CORPUS" >&2
  exit 1
fi

echo "Starting AFL++ fuzzing: $TARGET"
echo "  binary:  $FUZZ_BIN"
echo "  corpus:  $CORPUS"
echo "  output:  $OUTPUT"
echo ""

exec afl-fuzz -i "$CORPUS" -o "$OUTPUT" -- "$FUZZ_BIN" @@
