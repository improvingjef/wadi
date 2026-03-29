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
