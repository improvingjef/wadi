# Oasis CLI

Generated from the live command table.

## build

Compile libraries, executables, and tests into predictable artifact roots.

Usage:

`oasis build [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let oasis auto-resolve it.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `oasis build`
- `oasis build hello`
- `oasis build --workspace examples/hello --profile release --verbose`

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

## env

Print the exact subprocess environment a build, run, test, bench, or install step would inherit.

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

`oasis install [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--prefix DIR] [--destdir DIR] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let oasis auto-resolve it.
- `--prefix DIR`: Stage installed files under DIR instead of the default profile root.
- `--destdir DIR`: Prepend DIR to the resolved install prefix for packaging-style staging.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `oasis install`
- `oasis install hello`
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
- `--stdout`: Print the generated manifest instead of writing a file.
- `--force`: Overwrite an existing output path.
- `--help`: Print command-specific usage text.

Examples:
- `oasis migrate --stdout`
- `oasis migrate --workspace ../old-project`
- `oasis migrate --output converted.oasis.toml --force`
