## Wadi subtool split

`wadi` should feel like a toolbox, not a build-system kitchen sink. Each
subtool owns one job, prints direct facts, and composes through stable files and
exit codes rather than hidden global state.

### Bootstrap

- `wadi init`: scaffold a minimal workspace or package so the first buildable
  manifest is generated instead of hand-written.

### Build lifecycle

- `wadi build`: compile libraries, executables, and tests into predictable
  artifact roots.
- `wadi status`: summarize which targets are currently rebuilt, regenerated,
  or reused without compiling.
- `wadi clean`: remove the whole workspace artifact tree or just the requested
  targets.
- `wadi graph`: explain target and module dependency order.
- `wadi explain`: show compiler invocations, include paths, and why a target
  was rebuilt. Persist a machine-readable `.wadi-explain.json` sibling for
  editors and CI.
- `wadi watch`: poll the workspace and rerun a selected subtool when files
  change, without baking watch mode into every other command. Root workspaces
  can persist shared include/ignore globs under `[watch]`, and
  `.wadiwatchignore` can absorb local noisy trees without bloating shell
  aliases. Lock-aware delegated subtools also keep root metadata like
  `wadi.lock` visible even when include globs narrow the watched tree to
  source directories.

### Execution

- `wadi run`: build and launch executables with exact argv and signal
  semantics.
- `wadi test`: discover, build, run, and summarize test targets.
- `wadi bench`: build executable targets, run stable timing loops, and print
  machine-readable summaries.

### Dependencies and packages

- `wadi deps`: resolve external libraries, surface missing packages, and print
  the exact toolchain assumptions.
- `wadi vendor`: copy a local package or fetch a pinned git/archive source
  into `vendor/` and register it as a workspace member.
- `wadi lock`: snapshot resolved toolchain facts and external package paths
  into a machine-readable lock file and validate those facts during locked
  builds and installs.
- `wadi install`: stage installable binaries, libraries, and metadata.

### Discoverability

- `wadi release-artifacts`: render `docs/cli.md`, top-level completion
  scripts, and the packaged `package/share/...` install tree from the live
  binary.
- `wadi package`: derive `wadi.opam`, `Formula/wadi.rb`, `SHA256SUMS`, and
  `release-assets.json` from canonical release metadata without scraping shell
  scripts.
- `wadi docs`: render markdown CLI reference from the live command table.
- `wadi completion`: generate shell completion scripts from the live command
  table.
- `scripts/generate_packaging_manifests.sh`: derive `wadi.opam`,
  `Formula/wadi.rb`, `SHA256SUMS`, and `release-assets.json` from canonical
  release metadata so release automation consumes one asset generator instead of
  scraping workflow state.
- `wadi migrate`: scan `dune` and `dune-project` files and emit a reviewable
  `wadi.toml` starting point.

### Toolchain and environment

- `wadi toolchain`: discover `ocamlc`, `ocamlopt`, standard libraries, and
  platform quirks behind one portable driver.
- `wadi doctor`: validate manifest, target graph, toolchain, package
  resolution, and lock drift in one checklist.
- `wadi env`: print the environment a subtool would run under.
- `wadi repl`: launch a workspace-aware OCaml toplevel.

### Code generation and actions

- `wadi action`: run declared generated-file steps inside a sandboxed runner
  without paying a full compile/link.
- `wadi ppx`: compile and apply preprocessor pipelines with explicit ordering.
- `wadi promote`: copy declared generated outputs and explicit checked-in
  source snapshots back into the source tree on purpose, never by surprise.

## Dune feature mapping

- `dune init` maps to `wadi init`.
- `dune build` maps to `wadi build`.
- `dune exec` maps to `wadi run`.
- `dune runtest` maps to `wadi test`.
- `dune clean` maps to `wadi clean`.
- `dune describe`, `dune rules`, and parts of `dune diagnostics` map to
  `wadi graph` and `wadi explain`.
- `dune build -w`, `dune runtest -w`, and similar edit-run loops map to
  `wadi watch`.
- `dune external-lib-deps` maps to `wadi deps`.
- `dune install` maps to `wadi install`.
- `dune subst`, `dune promote`, and generated-file workflows map to
  `wadi action`, `wadi ppx`, and `wadi promote`.

## Design constraints

- Every subtool must be useful on its own and testable through black-box
  fixtures.
- Artifact layout belongs in a shared module so lifecycle commands never
  duplicate path logic.
- Command registration should come from one table so adding a subtool does not
  require touching usage text, parsing, dispatch, tests, and bootstrap rules in
  multiple places.
