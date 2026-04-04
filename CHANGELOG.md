# Changelog

## Unreleased

- Fixed release hygiene after the `oasis` to `wadi` rename so CI and release workflows now validate tags, package the right binary, and publish `wadi` metadata artifacts.
- Regenerated committed release metadata and CLI docs so `wadi.opam`, the Homebrew formula, and the packaged docs stay aligned with the live binary and current source archive.
- Improved `wadi explain --current` to show the exact output files used by freshness checks, including machine-readable JSON output.
- Added regressions for native executable freshness reporting so `wadi status` no longer reports missing `.cmx` and `.o` outputs after a successful unchanged build.
- Taught Wadi to recover from a mismatched configured `ocamlfind` by preferring the compiler switch copy when available, and to fail early with PATH guidance when OCaml tools still come from mixed installations.
- Made release source archives deterministic on macOS by disabling copyfile metadata and stripping extended attributes before archiving.
