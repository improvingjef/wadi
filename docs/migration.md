# Migrating From Dune

`oasis` is intentionally smaller and more explicit than `dune`. The migration
work is mostly mechanical once you stop translating one dune stanza at a time
and instead map each concern to a dedicated subtool or manifest section.

If you want a first pass before doing anything by hand, start with:

```sh
oasis migrate --stdout
```

That command scans `dune-project` plus every `dune` file it can find, emits a
reviewable `oasis.toml`, translates common `preprocess`, `pps`, `public_name`,
`wrapped`, and `rule` forms into real oasis sections, and leaves review comments
only for the pieces it still cannot translate cleanly.

## Command Mapping

- `dune build` -> `oasis build`
- `dune exec` -> `oasis run`
- `dune runtest` -> `oasis test`
- `dune clean` -> `oasis clean`
- `dune install` -> `oasis install`
- `dune describe`, `dune rules`, and most rebuild-debugging work -> `oasis explain`

## Basic Stanza Translation

### Library

Dune:

```lisp
(library
 (name core)
 (modules alpha beta)
 (libraries unix str))
```

Oasis:

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

Oasis:

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

Oasis:

```toml
[test.unit]
dir = "test"
main = "unit"
deps = ["core"]
```

## Generated Sources, Preprocessors, and PPX

Oasis keeps these concerns explicit and fingerprinted.

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

- Dune libraries are wrapped by default. `oasis migrate` preserves that with
  `wrapped = true` unless the dune stanza explicitly says `(wrapped false)`.
- `action.outputs` are relative to the target directory, not the workspace root.
- `preprocess.deps` and `ppx.deps` are explicit auxiliary inputs and participate
  in rebuild detection and `oasis explain`.
- `oasis migrate` resolves common dune `pps` forms through `ocamlfind printppx`
  and emits `ppx.*` sections with explicit argv.
- `oasis migrate` now infers `deps` for straightforward dune `action (run ...)`
  preprocessors and rules when the form names concrete file inputs directly,
  which cuts down the remaining review-only warnings.
- common dune `rule` stanzas become `action.*` sections when oasis can map the
  targets, deps, and command form directly
- Generated `.ml` or `.mli` files may not collide with checked-in source files
  in the target directory. Oasis fails fast instead of silently choosing one.

## Multi-Package Workspaces

Keep workspace-wide defaults and profiles in the root manifest, then let member
manifests own package-local targets and helper tools.

Root `oasis.toml`:

```toml
workspace = "demo"
version = 1
members = ["packages/core", "packages/app"]

[defaults]
profile = "dev"
```

Member `packages/core/oasis.toml`:

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
- if no package-local tool matches, oasis falls back to a root tool of the same
  name

## A Pragmatic Migration Sequence

1. Convert libraries, executables, and tests first.
2. Use `oasis migrate` for a first-pass manifest, then clean up the generated
   comments.
3. Get `oasis build`, `oasis run`, and `oasis test` green.
4. Translate generated-file actions, preprocessors, and PPX with explicit
   `deps`.
5. Run `oasis explain --current TARGET` until rebuild reasons are boring.
6. Use `oasis graph TARGET` and `oasis deps TARGET` to verify build order and
   external package closure before deleting dune files.
7. Move shared defaults and profiles into the root manifest.
8. Push package-local helpers down into member manifests where they belong.

## What Usually Feels Different

- Module order is inferred from OCaml dependencies. You list modules once; you
  do not hand-maintain compile order.
- Generated-file behavior is explicit. If an action writes a source file, that
  output has to be declared.
- Rebuild debugging is a first-class workflow. `oasis explain` shows package
  paths, tool scopes, commands, and invalidation reasons directly.
