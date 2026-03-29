# Manifest Reference

This is the working `oasis.toml` reference for the features currently shipped in
the repo.

## Top Level

```toml
workspace = "demo"              # optional
version = 1                     # optional, defaults to 1
members = ["packages/core"]     # optional
```

`members` entries are workspace-relative directories that contain their own
`oasis.toml`.

## Targets

### Library

```toml
[library.core]
dir = "lib"
modules = ["alpha", "beta"]
public_name = "demo.core"
wrapped = true
deps = ["base"]
packages = ["unix", "str"]
actions = ["generate_version"]
preprocess = ["expand"]
ppx = ["rewrite"]
compile_flags = ["-principal"]
link_flags = []
env = ["MODE=dev"]
sandbox = "target"
```

### Executable and Test

```toml
[executable.demo]
dir = "app"
main = "main"
public_name = "demo-cli"
modules = ["cli"]
deps = ["core"]

[test.unit]
dir = "test"
main = "test_main"
deps = ["core"]
```

Rules:

- `main` is a module stem, not a filename.
- `modules` entries are stems only. No paths. No extensions.
- `deps` may only reference workspace libraries.
- `public_name` controls the staged install name for libraries, `META` files, and executables.
- `wrapped = true` generates a namespace wrapper module named after the library
  stem, so `core` exposes `Core.Alpha`, `Core.Beta`, and so on.
- Wrapped libraries reserve the library-name stem for the generated wrapper. Do
  not list it in `modules`, generate it from an action, or check in
  `dir/<library>.ml` or `dir/<library>.mli`.

## Actions

```toml
[action.generate_version]
argv = ["./scripts/generate_version.sh"]
cwd = "."
deps = ["templates/version.txt"]
outputs = ["version.ml"]
env = ["MODE=release"]
stdin = "template input"
sandbox = "target"
```

Rules:

- `argv[0]` may be a relative program path.
- `cwd` and `deps` are workspace-relative in the root manifest.
- `outputs` are relative to the target directory.
- If an output is `.ml` or `.mli`, it may not collide with checked-in source in
  the target directory.
- `sandbox = "workspace"` copies the workspace into the sandbox; `target`
  limits materialization to the target tree plus declared tool inputs.

## Preprocessors

```toml
[preprocess.expand]
argv = ["./scripts/expand.sh"]
cwd = "scripts"
env = ["MODE=pre"]
deps = ["templates/banner.txt"]
```

Preprocessors are stdin/stdout transforms applied in declared order.

Why `deps` matters:

- they are fingerprinted for incremental rebuilds
- they show up in `oasis explain`
- missing auxiliary files fail early with a direct error

## PPX Tools

```toml
[ppx.rewrite]
argv = ["./ppx/rewrite.exe"]
deps = ["ppx/config.txt"]
```

PPX tools are passed to the compiler with `-ppx`. Their declared `deps` are
tracked the same way preprocessor inputs are.

## Defaults and Profiles

```toml
[defaults]
profile = "dev"
actions = ["generate_version"]
preprocess = ["expand"]
ppx = ["rewrite"]
compile_flags = ["-principal"]
env = ["MODE=default"]
sandbox = "workspace"

[profile.release]
compile_flags = ["-O3"]
env = ["MODE=release"]

[profile.release.executable.demo]
compile_flags = ["-unsafe"]
link_flags = ["-custom"]
env = ["MODE=demo"]
sandbox = "target"
```

Merge order:

1. workspace defaults
2. target-local settings
3. profile settings
4. profile target override

List-valued tool references are deduplicated in declaration order. Environment
bindings merge by name, with later scopes winning.

## Member Manifests

Member manifests may define:

- `library.*`
- `executable.*`
- `test.*`
- `action.*`
- `preprocess.*`
- `ppx.*`

Member manifests may not define workspace-wide sections such as `defaults` or
`profile.*`.

Package-local behavior:

- target `dir` values are rebased under the member path
- member action/preprocess/ppx program paths, `cwd`, and `deps` are rebased
- a target resolves tools from its own member package first, then falls back to
  the root manifest

Example member manifest:

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

With a member path of `packages/core`, the action program above resolves to
`packages/core/scripts/generate_version.sh`, and `cwd = "."` resolves to
`packages/core`.
