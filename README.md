# Wadi

I had Codex build this because of friction with Dune on a project. I'm new to OCaml and just vibing a new amazing programming language (haha). But the experience of working with dune was less pleasant than I preferred, so this is my offering back to the OCaml community for such a cool language. Claude made a pretty little website polished off a few items. I'm dogfooding this right now, and it seems pretty good, but caveat lector.

A fast, transparent OCaml build system. One manifest, zero guesswork.

Wadi replaces dune with a single `wadi.toml` manifest, content-based incremental builds, and a focused command set. It builds the [stir compiler](https://github.com/improvingjef/stir) — 2 libraries, 139 executables, menhir parsers, ocamllex lexers — in 45 seconds from a clean checkout and 0.2 seconds on incremental rebuilds.

## Quick start

```toml
# wadi.toml
workspace = "myproject"
version = 1

[library.core]
dir = "lib"
modules = ["engine", "types"]

[executable.app]
dir = "bin"
main = "main"
deps = ["core"]
```

```sh
wadi build        # compile everything
wadi run app      # build and launch
wadi test         # discover and run tests
wadi explain app  # see why it rebuilt
```

## Design choices

These are intentional. If they surprise you, this section explains why.

### 1. Target names must be unique across the workspace

Dune scopes names by directory — you can have `test_spill` in both `reggie/` and `test/`. Wadi requires globally unique names. This keeps dependency resolution unambiguous and makes commands like `wadi run test_spill` deterministic without requiring path qualifiers.

**Migration impact:** Rename duplicates (e.g., `test_spill_reggie`). The migrate tool will warn about collisions in a future release.

### 2. Library and executable names share the same namespace

You cannot have a library and an executable both named `fun_ir`. Dune allows this because it compiles them in separate build contexts. Wadi uses a single namespace so target references in deps, CLI arguments, and diagnostics are always unambiguous.

**Migration impact:** Rename the executable (e.g., `fun_ir_cli`).

### 3. Executables don't inherit "extra" source files from their directory

Dune's `(executables (names a b c))` stanza builds each name as a single-module executable, ignoring other `.ml` files in the directory. Wadi's `[executable.x]` with `main = "x"` does the same — but the migrate tool currently adds unmatched `.ml` files as `modules`. This is a migrate tool bug, not a design choice. The fix is to not add orphan files.

**Workaround:** Remove the spurious `modules` lines from migrated manifests.

### 4. Menhir and ocamllex require action definitions (for now)

Dune has built-in `(menhir)` and `(ocamllex)` stanzas. Wadi handles these through its general-purpose `[action]` system. First-class `.mll` auto-detection is implemented; first-class menhir with the two-phase `--infer` protocol is in progress.

**Migration impact:** Add `[action]` sections for each `.mly`/`.mll` file. The menhir action needs a shell wrapper to pre-compile dependency modules before `--infer` can run.

### 5. Module names are flat, not namespaced by default

By default, library modules are accessed directly (`Core_ir`, not `Fun_ir.Core_ir`). To match dune's wrapping behavior, set `wrapped = true` on the library — wadi generates a namespace wrapper module automatically. The migrate tool sets `wrapped = true` on all libraries since dune wraps by default.

**Migration impact:** None if using `wrapped = true`. If you prefer flat modules, remove the flag and update `open` statements.

## Commands

| Command | What it does |
|---------|-------------|
| `wadi build` | Compile targets with content-based incremental caching |
| `wadi run` | Build and launch an executable with exact signal semantics |
| `wadi test` | Build and run test targets with TAP-style output |
| `wadi clean` | Remove build artifacts |
| `wadi explain` | Show why a target rebuilt (fingerprint diffs, commands) |
| `wadi install` | Stage libraries, executables, and META files |
| `wadi toolchain` | Print resolved compiler paths and package roots |
| `wadi migrate` | Generate wadi.toml from dune files |
| `wadi format` | Format sources with ocamlformat |
| `wadi lint` | Check sources with strict compiler warnings |
| `wadi watch` | File-watching rebuild loop |
| `wadi init` | Scaffold a new project |
| `wadi repl` | Launch a workspace-aware OCaml toplevel |
| `wadi graph` | Show target and module dependency order |
| `wadi deps` | List transitive external package requirements |
| `wadi lock` | Snapshot resolved toolchain for reproducibility |
| `wadi doctor` | Check workspace health |
| `wadi completion` | Generate shell completions (bash/zsh/fish) |

See the [full guide](https://improvingjef.github.io/wadi/guide.html) for details.

## Install

```sh
opam install wadi
```

Or from source:

```sh
git clone https://github.com/improvingjef/wadi.git
cd wadi
make
# binary at _bootstrap/bin/wadi
```

## License

MIT
