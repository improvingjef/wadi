# Migrating From Dune

`wadi` is intentionally smaller and more explicit than `dune`. The migration
work is mostly mechanical once you stop translating one dune stanza at a time
and instead map each concern to a dedicated subtool or manifest section.

If you want a first pass before doing anything by hand, start with:

```sh
wadi migrate --stdout
```

That command scans `dune-project` plus every `dune` file it can find, emits a
reviewable `wadi.toml`, translates common `preprocess`, `pps`, `public_name`,
`wrapped`, and `rule` forms into real wadi sections, and leaves review comments
only for the pieces it still cannot translate cleanly.

## Command Mapping

- `dune build` -> `wadi build`
- `dune exec` -> `wadi run`
- `dune runtest` -> `wadi test`
- `dune clean` -> `wadi clean`
- `dune install` -> `wadi install`
- `dune describe`, `dune rules`, and most rebuild-debugging work -> `wadi explain`
- explicit generated-file runs -> `wadi action`
- generated-file promotion workflows -> `wadi promote`

## Basic Stanza Translation

### Library

Dune:

```lisp
(library
 (name core)
 (modules alpha beta)
 (libraries unix str))
```

Wadi:

```toml
[library.core]
wrapped = true
dir = "lib"
public_name = "demo.core"
modules = ["alpha", "beta"]
packages = ["unix", "str"]
```

### Executable

Dune:

```lisp
(executable
 (name demo)
 (modules main)
 (libraries core))
```

Wadi:

```toml
[executable.demo]
dir = "app"
main = "main"
public_name = "demo-cli"
deps = ["core"]
```

### Tests

Dune:

```lisp
(test
 (name unit)
 (libraries core))
```

Wadi:

```toml
[test.unit]
dir = "test"
main = "unit"
deps = ["core"]
```

## Generated Sources, Preprocessors, and PPX

Wadi keeps these concerns explicit and fingerprinted.

```toml
[action.generate_version]
argv = ["./scripts/generate_version.sh"]
deps = ["templates/version.txt"]
outputs = ["version.ml"]

[preprocess.expand]
argv = ["./scripts/expand.sh"]
cwd = "scripts"
deps = ["templates/banner.txt"]

[ppx.rewrite]
argv = ["./ppx/rewrite.exe"]
deps = ["ppx/config.txt"]

[library.core]
dir = "lib"
modules = ["core", "version"]
actions = ["generate_version"]
preprocess = ["expand"]
ppx = ["rewrite"]
```

Important rules:

- Dune libraries are wrapped by default. `wadi migrate` preserves that with
  `wrapped = true` unless the dune stanza explicitly says `(wrapped false)`.
- `action.outputs` are relative to the target directory, not the workspace root.
- `preprocess.deps` and `ppx.deps` are explicit auxiliary inputs and participate
  in rebuild detection and `wadi explain`.
- `wadi migrate` resolves common dune `pps` forms through `ocamlfind printppx`
  and emits `ppx.*` sections with explicit argv.
- `wadi migrate` now infers `deps` for straightforward dune `action (run ...)`
  preprocessors and rules when the form names concrete file inputs directly,
  which cuts down the remaining review-only warnings.
- dune `with-stdin-from` and `with-stdout-to` wrappers now migrate to
  first-class `stdin_path` / `stdout` manifest fields when possible instead of
  always collapsing into shell-quoted `sh -c` fallbacks.
- dune `progn` rules now migrate to first-class `steps = [[...], [...]]`
  action sequences for straightforward multi-command flows, so copied-file and
  diff-style rules stay structured instead of turning into one shell string.
- common dune `rule` stanzas become `action.*` sections when wadi can map the
  targets, deps, and command form directly
- Generated `.ml` or `.mli` files may not collide with checked-in source files
  in the target directory unless the action lists them under
  `checked_in_sources = [...]`. Wadi still builds from the generated copy and
  leaves the workspace snapshot alone until `wadi promote`.
- dune `rule` stanzas with `(mode promote)` now migrate source-like targets to
  `checked_in_sources = [...]`, which preserves the snapshot intent without
  weakening the normal generated-source collision guard.
- Wrapped libraries may keep a checked-in `Foo.ml` and/or `Foo.mli` wrapper.
  When `wadi migrate` sees that wrapper in the source tree, it omits that
  wrapper stem from `modules = [...]` even if the dune stanza listed it
  explicitly, so the manifest matches the wrapped library surface instead of
  fighting it.

## Multi-Package Workspaces

Keep workspace-wide defaults and profiles in the root manifest, then let member
manifests own package-local targets and helper tools.

Root `wadi.toml`:

```toml
workspace = "demo"
version = 1
members = ["packages/core", "packages/app"]

[defaults]
profile = "dev"
```

Member `packages/core/wadi.toml`:

```toml
[action.generate_version]
argv = ["./scripts/generate_version.sh"]
cwd = "."
deps = ["templates/version.txt"]
outputs = ["version.ml"]

[library.core]
dir = "lib"
modules = ["core", "version"]
actions = ["generate_version"]
```

Member-local tool paths are rebased automatically under the member path. That
means `./scripts/generate_version.sh` above resolves under `packages/core/`
without forcing every helper to live in the root manifest.

Lookup rules are intentionally simple:

- a target resolves tools from its own package first
- if no package-local tool matches, wadi falls back to a root tool of the same
  name

## A Pragmatic Migration Sequence

1. Convert libraries, executables, and tests first.
2. Use `wadi migrate` for a first-pass manifest, then clean up the generated
   comments.
3. Get `wadi build`, `wadi run`, and `wadi test` green.
4. Translate generated-file actions, preprocessors, and PPX with explicit
   `deps`.
5. Run `wadi explain --current TARGET` until rebuild reasons are boring.
6. Use `wadi graph TARGET` and `wadi deps TARGET` to verify build order and
   external package closure before deleting dune files.
7. Move shared defaults and profiles into the root manifest.
8. Push package-local helpers down into member manifests where they belong.

## What Usually Feels Different

- Module order is inferred from OCaml dependencies. You list modules once; you
  do not hand-maintain compile order.
- Generated-file behavior is explicit. If an action writes a source file, that
  output has to be declared.
- Rebuild debugging is a first-class workflow. `wadi explain` shows package
  paths, tool scopes, commands, and invalidation reasons directly.
