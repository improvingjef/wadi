## Oasis subtool split

`oasis` should feel like a toolbox, not a build-system kitchen sink. Each
subtool owns one job, prints direct facts, and composes through stable files and
exit codes rather than hidden global state.

### Bootstrap

- `oasis init`: scaffold a minimal workspace or package so the first buildable
  manifest is generated instead of hand-written.

### Build lifecycle

- `oasis build`: compile libraries, executables, and tests into predictable
  artifact roots.
- `oasis clean`: remove the whole workspace artifact tree or just the requested
  targets.
- `oasis graph`: explain target and module dependency order.
- `oasis explain`: show compiler invocations, include paths, and why a target
  was rebuilt. Persist a machine-readable `.oasis-explain.json` sibling for
  editors and CI.

### Execution

- `oasis run`: build and launch executables with exact argv and signal
  semantics.
- `oasis test`: discover, build, run, and summarize test targets.
- `oasis bench`: build executable targets, run stable timing loops, and print
  machine-readable summaries.

### Dependencies and packages

- `oasis deps`: resolve external libraries, surface missing packages, and print
  the exact toolchain assumptions.
- `oasis vendor`: copy a local package into `vendor/` and register it as a
  workspace member.
- `oasis lock`: snapshot resolved toolchain facts and external package paths
  into a machine-readable lock file.
- `oasis install`: stage installable binaries, libraries, and metadata.

### Discoverability

- `oasis docs`: render markdown CLI reference from the live command table.
- `oasis completion`: generate shell completion scripts from the live command
  table.
- `oasis migrate`: scan `dune` and `dune-project` files and emit a reviewable
  `oasis.toml` starting point.

### Toolchain and environment

- `oasis toolchain`: discover `ocamlc`, `ocamlopt`, standard libraries, and
  platform quirks behind one portable driver.
- `oasis env`: print the environment a subtool would run under.
- `oasis repl`: launch a workspace-aware OCaml toplevel.

### Code generation and actions

- `oasis action`: run declared generated-file steps inside a sandboxed runner
  without paying a full compile/link.
- `oasis ppx`: compile and apply preprocessor pipelines with explicit ordering.
- `oasis promote`: copy declared generated outputs and explicit checked-in
  source snapshots back into the source tree on purpose, never by surprise.

## Dune feature mapping

- `dune init` maps to `oasis init`.
- `dune build` maps to `oasis build`.
- `dune exec` maps to `oasis run`.
- `dune runtest` maps to `oasis test`.
- `dune clean` maps to `oasis clean`.
- `dune describe`, `dune rules`, and parts of `dune diagnostics` map to
  `oasis graph` and `oasis explain`.
- `dune external-lib-deps` maps to `oasis deps`.
- `dune install` maps to `oasis install`.
- `dune subst`, `dune promote`, and generated-file workflows map to
  `oasis action`, `oasis ppx`, and `oasis promote`.

## Design constraints

- Every subtool must be useful on its own and testable through black-box
  fixtures.
- Artifact layout belongs in a shared module so lifecycle commands never
  duplicate path logic.
- Command registration should come from one table so adding a subtool does not
  require touching usage text, parsing, dispatch, tests, and bootstrap rules in
  multiple places.
