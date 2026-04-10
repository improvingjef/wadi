---
name: wadi
description: OCaml build tool. Use when building, testing, or managing OCaml projects. Wadi replaces dune — never use dune in projects that have a wadi.toml.
argument-hint: [build|test|clean|run|watch|doctor|init]
---

# Wadi — OCaml Build Tool

Wadi is the build tool for OCaml projects. It replaces dune entirely.
**Never use dune, opam, or ocamlfind in a wadi project.**
**Never try to install wadi — it is already installed globally.**

## Commands

| Command | What it does |
|---------|-------------|
| `wadi build` | Compile libraries, executables, and tests |
| `wadi test` | Build and run all test targets |
| `wadi test <name>` | Build and run a specific test |
| `wadi run` | Build and launch an executable |
| `wadi clean` | Remove build artifacts (`_wadi/`) |
| `wadi watch build` | Rebuild on file changes |
| `wadi watch test` | Retest on file changes |
| `wadi doctor` | Validate workspace config and toolchain |
| `wadi status` | Show what needs rebuilding |
| `wadi init` | Scaffold a new workspace |
| `wadi graph` | Show target build order |
| `wadi bench` | Run benchmarks |

## Manifest: wadi.toml

Every wadi project has a `wadi.toml` at its root. Structure:

```toml
workspace = "my_project"
version = 1

[library.my_lib]
dir = "src"
modules = ["module_a", "module_b", "module_c"]

[executable.my_app]
dir = "bin"
main = "main"
deps = ["my_lib"]

[test.my_tests]
dir = "test"
main = "test_main"
deps = ["my_lib"]
```

### Key rules

- `modules` entries are module STEMS only — no paths, no `.ml` extension
- `deps` reference workspace library names only
- `main` is a module stem, not a filename
- `dir` is relative to the workspace root
- `packages` lists opam packages (e.g., `["unix", "str"]`)
- Module order in `modules` determines compilation order

### Adding a new module

1. Create `src/new_module.ml`
2. Add `"new_module"` to the `modules` list in `wadi.toml`
3. Run `wadi build`

### Adding a new test

1. Create `test/test_new.ml`
2. Add a new test section to `wadi.toml`:
```toml
[test.test_new]
dir = "test"
main = "test_new"
deps = ["my_lib"]
```
3. Run `wadi test test_new`

## Build Artifacts

All build output goes to `_wadi/build/default/`. Never commit this directory.

```
_wadi/build/default/
  lib/<library>/          # .cmx, .cmi, .cmxa files
  exe/<executable>/       # compiled binary
  test/<test>/            # compiled test binary
```

## Common Issues

### "module not found" error
The module is missing from `modules` in `wadi.toml`, or it's listed
in the wrong order (dependencies must come before dependents).

### Stale build
Run `wadi clean` then `wadi build`. The `_wadi/` directory caches
everything — cleaning forces a full rebuild.

### Build fails after adding a new file
You must add it to `wadi.toml`. Wadi doesn't auto-discover modules.

### "wadi not found"
Wadi is installed at `~/.local/bin/wadi`. Ensure `~/.local/bin` is
on your PATH. **Do not try to install wadi via npm, pip, cargo, or
any package manager.**

## Flags

| Flag | Effect |
|------|--------|
| `--verbose` or `-v` | Show compiler commands |
| `--keep-going` | Continue after failures |
| `-j N` | Parallel test execution |
| `--workspace DIR` | Use a different workspace root |
| `--profile NAME` | Select build profile |
| `--backend native\|bytecode` | Choose compiler backend |
| `--locked` | Require wadi.lock to match |

## Advanced Features

### Wrapped libraries
```toml
[library.core]
wrapped = true
modules = ["alpha", "beta"]
```
Generates a namespace wrapper: `Core.Alpha`, `Core.Beta`.

### Actions (code generation)
```toml
[library.core]
actions = ["generate_version"]

[action.generate_version]
command = ["./gen_version.sh"]
inputs = ["VERSION"]
outputs = ["src/version.ml"]
```

### Benchmarks
```toml
[bench.quick]
executable = "my_app"
argv = ["--bench"]
warmup = 3
iterations = 100
```
Run with `wadi bench` or `wadi bench quick`.
