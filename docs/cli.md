# Oasis CLI

Generated from the live command table.

## init

Scaffold a minimal oasis workspace without hand-writing the first manifest.

Usage:

`oasis init [--dir DIR] [--member PATH] [--name NAME] [--library NAME] [--executable NAME] [--bare] [--force]`

Options:
- `--dir DIR`: Create or update the scaffold in DIR instead of the current directory.
- `--member PATH`: Scaffold a package-local manifest at PATH and register it under members = [...].
- `--name NAME`: Set the generated workspace or vendor name explicitly.
- `--library NAME`: Scaffold a library target named NAME.
- `--executable NAME`: Scaffold an executable target named NAME.
- `--bare`: Write only a root manifest without any targets or source files.
- `--force`: Overwrite existing generated files or output paths.
- `--help`: Print command-specific usage text.

Examples:
- `oasis init`
- `oasis init --name demo`
- `oasis init --dir monorepo --member packages/core --library core`
- `oasis init --dir examples/demo --library core --executable demo`
- `oasis init --dir scratch --bare`

## build

Compile libraries, executables, and tests into predictable artifact roots.

Usage:

`oasis build [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--locked | --warn-locked] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let oasis auto-resolve it.
- `--locked`: Require oasis.lock to match the current manifest, recorded toolchain facts, and resolved package paths before continuing.
- `--warn-locked`: Warn when oasis.lock is missing or stale against the current manifest, toolchain facts, or resolved package paths, but continue with the build or install.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `oasis build`
- `oasis build hello`
- `oasis build --locked hello`
- `oasis build --workspace examples/hello --profile release --verbose`

## action

Run declared generated-file actions for selected targets without compiling or linking.

Usage:

`oasis action [--workspace DIR] [--profile NAME] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `oasis action`
- `oasis action core`
- `oasis action demo`
- `oasis action --profile release core demo`

## ppx

Inspect or dump the post-preprocess, post-PPX source for one target module.

Usage:

`oasis ppx [--workspace DIR] [--profile NAME] [--verbose] [--interface] [--plan] [--output PATH] TARGET [MODULE]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--interface`: Inspect or apply the target module interface (`.mli`) instead of the implementation.
- `--plan`: Print the resolved preprocessor and PPX pipeline without dumping transformed source.
- `--output PATH`: Write the transformed source to PATH instead of stdout.
- `--help`: Print command-specific usage text.

Examples:
- `oasis ppx demo`
- `oasis ppx demo main`
- `oasis ppx --interface core version`
- `oasis ppx --plan demo main`
- `oasis ppx --output _debug/main.ml demo main`

## graph

Show target build order, module order, and pipeline shape without compiling.

Usage:

`oasis graph [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let oasis auto-resolve it.
- `--help`: Print command-specific usage text.

Examples:
- `oasis graph`
- `oasis graph hello`
- `oasis graph --profile release --backend bytecode hello`

## run

Build and launch an executable target with exact argv forwarding.

Usage:

`oasis run [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET] [-- ARG ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let oasis auto-resolve it.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `oasis run`
- `oasis run hello`
- `oasis run --profile release hello -- --loud`
- `oasis run -- --port 8080`

## test

Build and execute declared test targets with a direct failure summary.

Usage:

`oasis test [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let oasis auto-resolve it.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `oasis test`
- `oasis test unit`
- `oasis test unit integration`
- `oasis test --workspace examples/hello --profile ci --verbose`

## bench

Build executable targets and report stable benchmark timing summaries.

Usage:

`oasis bench [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [--json] [--warmup COUNT] [--iterations COUNT] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let oasis auto-resolve it.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--json`: Print machine-readable JSON output instead of the text report.
- `--warmup COUNT`: Run each benchmark target COUNT warmup times before measuring.
- `--iterations COUNT`: Run each benchmark target COUNT measured times.
- `--help`: Print command-specific usage text.

Examples:
- `oasis bench`
- `oasis bench demo`
- `oasis bench --warmup 1 --iterations 5 demo`
- `oasis bench --json demo`

## clean

Remove the whole artifact tree or only the requested target outputs.

Usage:

`oasis clean [--workspace DIR] [--profile NAME] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `oasis clean`
- `oasis clean hello`
- `oasis clean hello greeting`
- `oasis clean --workspace examples/hello --profile release --verbose`

## promote

Copy declared non-source action outputs back into the workspace on purpose.

Usage:

`oasis promote [--workspace DIR] [--profile NAME] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `oasis promote`
- `oasis promote snapshots`
- `oasis promote --profile release fixtures`

## deps

Resolve transitive external package requirements for selected targets.

Usage:

`oasis deps [--workspace DIR] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--help`: Print command-specific usage text.

Examples:
- `oasis deps`
- `oasis deps hello`
- `oasis deps --workspace examples/hello greeting hello`

## lock

Snapshot resolved toolchain facts and external package paths into a machine-readable lock file.

Usage:

`oasis lock [--workspace DIR] [--output PATH] [--stdout] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--output PATH`: Write the generated manifest to PATH instead of oasis.toml.
- `--stdout`: Print the generated output instead of writing a file.
- `--help`: Print command-specific usage text.

Examples:
- `oasis lock`
- `oasis lock demo`
- `oasis lock --stdout`
- `oasis lock --output oasis.lock.json demo`

## vendor

Copy or fetch a source dependency into vendor/ and register it as a workspace member.

Usage:

`oasis vendor [--workspace DIR] (--source DIR | --git URL | --url URL) [--ref REV] [--checksum VALUE] [--name NAME] [--force]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--source DIR`: Copy the vendored package from DIR into vendor/NAME.
- `--git URL`: Clone the vendored package from URL into vendor/NAME and verify the pinned commit checksum.
- `--url URL`: Download and extract the vendored source archive from URL into vendor/NAME and verify its checksum.
- `--ref REV`: Checkout REV after cloning --git before validating the pinned checksum.
- `--checksum VALUE`: Pin remote vendored sources. Git sources compare the resolved commit id; URL sources verify the downloaded archive digest (plain hex defaults to sha256:).
- `--name NAME`: Set the generated workspace or vendor name explicitly.
- `--force`: Overwrite existing generated files or output paths.
- `--help`: Print command-specific usage text.

Examples:
- `oasis vendor --source ../dep`
- `oasis vendor --git https://example.com/dep.git --checksum 0123abcd --name dep`
- `oasis vendor --url https://example.com/dep.tar.gz --checksum sha256:0123abcd --name dep`
- `oasis vendor --workspace examples/app --source ../core --force`

## env

Print the exact subprocess environment a build, action, run, test, bench, or install step would inherit.

Usage:

`oasis env [--workspace DIR] [--profile NAME] [--json] [--changed-only] SUBTOOL [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--json`: Print machine-readable JSON output instead of the text report.
- `--changed-only`: Show only environment bindings that differ from the inherited host environment.
- `--help`: Print command-specific usage text.

Examples:
- `oasis env build`
- `oasis env action core`
- `oasis env --profile release build demo`
- `oasis env --json run demo`
- `oasis env --changed-only build demo`
- `oasis env run demo`
- `oasis env test unit`
- `oasis env bench demo`

## repl

Build a bytecode toplevel with workspace libraries and packages already wired in.

Usage:

`oasis repl [--workspace DIR] [--profile NAME] [--verbose] [--plan] [--json] [--script PATH] [TARGET] [-- OCAML_ARG ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--plan`: Print the resolved REPL plan and exit without launching the toplevel.
- `--json`: Print machine-readable JSON output instead of the text report.
- `--script PATH`: Read noninteractive toplevel phrases from PATH via stdin instead of passing a script file as an OCaml argv.
- `--help`: Print command-specific usage text.

Examples:
- `oasis repl core`
- `oasis repl demo`
- `oasis repl --plan --json core`
- `oasis repl core --script scripts/session.ml -- -noinit -noprompt`
- `oasis repl --profile release core -- -noinit -noprompt`

## install

Stage installable libraries, executables, and metadata under a prefix.

Usage:

`oasis install [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--prefix DIR] [--destdir DIR] [--locked | --warn-locked] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let oasis auto-resolve it.
- `--prefix DIR`: Stage installed files under DIR instead of the default profile root.
- `--destdir DIR`: Prepend DIR to the resolved install prefix for packaging-style staging.
- `--locked`: Require oasis.lock to match the current manifest, recorded toolchain facts, and resolved package paths before continuing.
- `--warn-locked`: Warn when oasis.lock is missing or stale against the current manifest, toolchain facts, or resolved package paths, but continue with the build or install.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `oasis install`
- `oasis install hello`
- `oasis install --warn-locked --prefix _stage hello`
- `oasis install --prefix _stage hello greeting`
- `oasis install --prefix /usr/local --destdir _pkg hello`

## docs

Render markdown CLI reference directly from the live command table.

Usage:

`oasis docs`

Options:
- `--help`: Print command-specific usage text.

Examples:
- `oasis docs`

## completion

Generate shell completion scripts from the live command table.

Usage:

`oasis completion [--workspace DIR] SHELL`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--help`: Print command-specific usage text.

Examples:
- `oasis completion bash`
- `oasis completion zsh`
- `oasis completion fish`

## toolchain

Print the resolved OCaml toolchain, backend, and package search roots.

Usage:

`oasis toolchain`

Options:
- `--help`: Print command-specific usage text.

Examples:
- `oasis toolchain`

## explain

Show why a target rebuilt or reused artifacts and which commands were planned.

Usage:

`oasis explain [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--current] [--json] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let oasis auto-resolve it.
- `--current`: Compute a fresh rebuild explanation from current inputs without compiling, linking, or materializing generated sources.
- `--json`: Print machine-readable JSON output instead of the text report.
- `--help`: Print command-specific usage text.

Examples:
- `oasis explain`
- `oasis explain hello`
- `oasis explain --current hello`
- `oasis explain --current --backend bytecode hello`
- `oasis explain --json hello`
- `oasis explain --profile release greeting hello`

## migrate

Scan dune files and emit a first-pass oasis.toml manifest with review comments.

Usage:

`oasis migrate [--workspace DIR] [--output PATH] [--stdout] [--force]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--output PATH`: Write the generated manifest to PATH instead of oasis.toml.
- `--stdout`: Print the generated output instead of writing a file.
- `--force`: Overwrite existing generated files or output paths.
- `--help`: Print command-specific usage text.

Examples:
- `oasis migrate --stdout`
- `oasis migrate --workspace ../old-project`
- `oasis migrate --output converted.oasis.toml --force`
