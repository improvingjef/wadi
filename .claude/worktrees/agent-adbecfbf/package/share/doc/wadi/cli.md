# Wadi CLI

Generated from the live command table.

## init

Scaffold a minimal wadi workspace without hand-writing the first manifest.

Usage:

`wadi init [--dir DIR] [--member PATH] [--name NAME] [--library NAME] [--executable NAME] [--bare] [--force]`

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
- `wadi init`
- `wadi init --name demo`
- `wadi init --dir monorepo --member packages/core --library core`
- `wadi init --dir examples/demo --library core --executable demo`
- `wadi init --dir scratch --bare`

## build

Compile libraries, executables, and tests into predictable artifact roots.

Usage:

`wadi build [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--locked | --warn-locked] [--keep-going] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let wadi auto-resolve it.
- `--locked`: Require wadi.lock to match the current manifest, recorded toolchain facts, and resolved package paths before continuing.
- `--warn-locked`: Warn when wadi.lock is missing or stale against the current manifest, toolchain facts, or resolved package paths, but continue with the build or install.
- `--keep-going`: Continue building remaining targets after a failure instead of stopping at the first error.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `wadi build`
- `wadi build hello`
- `wadi build --locked hello`
- `wadi build --keep-going`
- `wadi build --workspace examples/hello --profile release --verbose`

## status

Summarize which targets are rebuilt, regenerated, or reused without compiling.

Usage:

`wadi status [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--json] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let wadi auto-resolve it.
- `--json`: Print machine-readable JSON output instead of the text report.
- `--help`: Print command-specific usage text.

Examples:
- `wadi status`
- `wadi status hello`
- `wadi status --backend bytecode hello`
- `wadi status --json --profile release`

## doctor

Validate workspace configuration, toolchain health, package resolution, and lock drift.

Usage:

`wadi doctor [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--json] [--locked | --warn-locked] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let wadi auto-resolve it.
- `--json`: Print machine-readable JSON output instead of the text report.
- `--locked`: Require wadi.lock to match the current manifest, recorded toolchain facts, and resolved package paths before continuing.
- `--warn-locked`: Warn when wadi.lock is missing or stale against the current manifest, toolchain facts, or resolved package paths, but continue with the build or install.
- `--help`: Print command-specific usage text.

Examples:
- `wadi doctor`
- `wadi doctor hello`
- `wadi doctor --locked hello`
- `wadi doctor --json --backend bytecode`

## watch

Poll the workspace and rerun a selected wadi subtool whenever inputs change.

Usage:

`wadi watch [--workspace DIR] [--poll-ms COUNT] [--debounce-ms COUNT] [--max-runs COUNT] [--keep-going] [--include GLOB] [--ignore GLOB] SUBTOOL [ARG ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--poll-ms COUNT`: Poll the workspace for file changes every COUNT milliseconds.
- `--debounce-ms COUNT`: Wait COUNT milliseconds after the first detected change before rerunning the watched subtool.
- `--max-runs COUNT`: Exit after COUNT watched executions instead of running until interrupted.
- `--keep-going`: Keep watching after a failed run instead of exiting with the first non-zero status.
- `--include GLOB`: Watch only paths matching GLOB. Repeat to narrow large workspaces to the relevant source trees.
- `--ignore GLOB`: Ignore paths matching GLOB in addition to the built-in .git, _wadi, and _bootstrap exclusions.
- `--help`: Print command-specific usage text.

Examples:
- `wadi watch build`
- `wadi watch test unit`
- `wadi watch --keep-going --max-runs 2 build hello`
- `wadi watch --include 'lib/**' --include 'app/**' run demo`
- `wadi watch --ignore 'vendor/**' build`
- `wadi watch run demo -- --port 8080`

## action

Run declared generated-file actions for selected targets without compiling or linking.

Usage:

`wadi action [--workspace DIR] [--profile NAME] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `wadi action`
- `wadi action core`
- `wadi action demo`
- `wadi action --profile release core demo`

## ppx

Inspect or dump the post-preprocess, post-PPX source for one target module.

Usage:

`wadi ppx [--workspace DIR] [--profile NAME] [--verbose] [--interface] [--plan] [--output PATH] TARGET [MODULE]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--interface`: Inspect or apply the target module interface (`.mli`) instead of the implementation.
- `--plan`: Print the resolved preprocessor and PPX pipeline without dumping transformed source.
- `--output PATH`: Write the transformed source to PATH instead of stdout.
- `--help`: Print command-specific usage text.

Examples:
- `wadi ppx demo`
- `wadi ppx demo main`
- `wadi ppx --interface core version`
- `wadi ppx --plan demo main`
- `wadi ppx --output _debug/main.ml demo main`

## graph

Show target build order, module order, and pipeline shape without compiling.

Usage:

`wadi graph [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let wadi auto-resolve it.
- `--help`: Print command-specific usage text.

Examples:
- `wadi graph`
- `wadi graph hello`
- `wadi graph --profile release --backend bytecode hello`

## run

Build and launch an executable target with exact argv forwarding.

Usage:

`wadi run [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET] [-- ARG ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let wadi auto-resolve it.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `wadi run`
- `wadi run hello`
- `wadi run --profile release hello -- --loud`
- `wadi run -- --port 8080`

## test

Build and execute declared test targets with a direct failure summary.

Usage:

`wadi test [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let wadi auto-resolve it.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `wadi test`
- `wadi test unit`
- `wadi test unit integration`
- `wadi test --workspace examples/hello --profile ci --verbose`

## bench

Build executable targets and report stable benchmark timing summaries.

Usage:

`wadi bench [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [--json] [--warmup COUNT] [--iterations COUNT] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let wadi auto-resolve it.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--json`: Print machine-readable JSON output instead of the text report.
- `--warmup COUNT`: Run each benchmark target COUNT warmup times before measuring.
- `--iterations COUNT`: Run each benchmark target COUNT measured times.
- `--help`: Print command-specific usage text.

Examples:
- `wadi bench`
- `wadi bench demo`
- `wadi bench --warmup 1 --iterations 5 demo`
- `wadi bench --json demo`

## clean

Remove the whole artifact tree or only the requested target outputs.

Usage:

`wadi clean [--workspace DIR] [--profile NAME] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `wadi clean`
- `wadi clean hello`
- `wadi clean hello greeting`
- `wadi clean --workspace examples/hello --profile release --verbose`

## promote

Copy declared non-source action outputs back into the workspace on purpose.

Usage:

`wadi promote [--workspace DIR] [--profile NAME] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `wadi promote`
- `wadi promote snapshots`
- `wadi promote --profile release fixtures`

## deps

Resolve transitive external package requirements for selected targets.

Usage:

`wadi deps [--workspace DIR] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--help`: Print command-specific usage text.

Examples:
- `wadi deps`
- `wadi deps hello`
- `wadi deps --workspace examples/hello greeting hello`

## lock

Snapshot resolved toolchain facts and external package paths into a machine-readable lock file.

Usage:

`wadi lock [--workspace DIR] [--output PATH] [--stdout] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--output PATH`: Write the generated manifest to PATH instead of wadi.toml.
- `--stdout`: Print the generated output instead of writing a file.
- `--help`: Print command-specific usage text.

Examples:
- `wadi lock`
- `wadi lock demo`
- `wadi lock --stdout`
- `wadi lock --output wadi.lock.json demo`

## vendor

Copy or fetch a source dependency into vendor/ and register it as a workspace member.

Usage:

`wadi vendor [--workspace DIR] (--source DIR | --git URL | --url URL) [--ref REV] [--checksum VALUE] [--name NAME] [--force]`

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
- `wadi vendor --source ../dep`
- `wadi vendor --git https://example.com/dep.git --checksum 0123abcd --name dep`
- `wadi vendor --url https://example.com/dep.tar.gz --checksum sha256:0123abcd --name dep`
- `wadi vendor --workspace examples/app --source ../core --force`

## env

Print the exact subprocess environment a build, action, run, test, bench, or install step would inherit.

Usage:

`wadi env [--workspace DIR] [--profile NAME] [--json] [--changed-only] SUBTOOL [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--json`: Print machine-readable JSON output instead of the text report.
- `--changed-only`: Show only environment bindings that differ from the inherited host environment.
- `--help`: Print command-specific usage text.

Examples:
- `wadi env build`
- `wadi env action core`
- `wadi env --profile release build demo`
- `wadi env --json run demo`
- `wadi env --changed-only build demo`
- `wadi env run demo`
- `wadi env test unit`
- `wadi env bench demo`

## repl

Build a bytecode toplevel with workspace libraries and packages already wired in.

Usage:

`wadi repl [--workspace DIR] [--profile NAME] [--verbose] [--plan] [--json] [--script PATH] [TARGET] [-- OCAML_ARG ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--plan`: Print the resolved REPL plan and exit without launching the toplevel.
- `--json`: Print machine-readable JSON output instead of the text report.
- `--script PATH`: Read noninteractive toplevel phrases from PATH via stdin instead of passing a script file as an OCaml argv.
- `--help`: Print command-specific usage text.

Examples:
- `wadi repl core`
- `wadi repl demo`
- `wadi repl --plan --json core`
- `wadi repl core --script scripts/session.ml -- -noinit -noprompt`
- `wadi repl --profile release core -- -noinit -noprompt`

## install

Stage installable libraries, executables, and metadata under a prefix.

Usage:

`wadi install [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--prefix DIR] [--destdir DIR] [--locked | --warn-locked] [--verbose] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let wadi auto-resolve it.
- `--prefix DIR`: Stage installed files under DIR instead of the default profile root.
- `--destdir DIR`: Prepend DIR to the resolved install prefix for packaging-style staging.
- `--locked`: Require wadi.lock to match the current manifest, recorded toolchain facts, and resolved package paths before continuing.
- `--warn-locked`: Warn when wadi.lock is missing or stale against the current manifest, toolchain facts, or resolved package paths, but continue with the build or install.
- `--verbose, -v`: Print detailed process execution as commands run.
- `--help`: Print command-specific usage text.

Examples:
- `wadi install`
- `wadi install hello`
- `wadi install --warn-locked --prefix _stage hello`
- `wadi install --prefix _stage hello greeting`
- `wadi install --prefix /usr/local --destdir _pkg hello`

## release-artifacts

Render CLI docs, shell completions, and packaged install-tree payloads from the live binary.

Usage:

`wadi release-artifacts [--output-dir DIR]`

Options:
- `--output-dir DIR`: Write generated files under DIR instead of the current directory.
- `--help`: Print command-specific usage text.

Examples:
- `wadi release-artifacts`
- `wadi release-artifacts --output-dir dist`

## package

Render opam, Homebrew, checksum, and release-asset metadata from canonical release facts.

Usage:

`wadi package [--output-dir DIR] [--opam-output PATH] [--formula-output PATH] [--checksums-output PATH] [--asset-index-output PATH] [--source-archive PATH | --source-archive-dir DIR | --reuse-source-archive-dir DIR] [--source-archive-mode tracked|worktree]`

Options:
- `--output-dir DIR`: Write generated files under DIR instead of the current directory.
- `--opam-output PATH`: Write the generated opam package metadata to PATH.
- `--formula-output PATH`: Write the generated Homebrew formula to PATH.
- `--checksums-output PATH`: Write SHA256SUMS-style checksum lines for generated release assets.
- `--asset-index-output PATH`: Write a machine-readable release asset index with names, URLs, sizes, and checksums.
- `--source-archive PATH`: Reuse an explicit source archive when rendering packaging metadata instead of rebuilding one.
- `--source-archive-dir DIR`: Refresh the canonical source archive into DIR before rendering packaging metadata.
- `--reuse-source-archive-dir DIR`: Reuse the canonical source archive already present in DIR without rebuilding it.
- `--source-archive-mode tracked|worktree`: Choose whether rebuilt source archives come from tracked git paths only or from the live non-ignored worktree.
- `--help`: Print command-specific usage text.

Examples:
- `wadi package`
- `wadi package --output-dir dist`
- `wadi package --source-archive-dir dist --asset-index-output dist/release-assets.json`
- `wadi package --source-archive dist/wadi-source.tar.gz --checksums-output dist/SHA256SUMS`
- `wadi package --source-archive-dir dist --source-archive-mode worktree`

## sync-generated

Refresh bootstrap seed metadata, CLI docs, shell completions, and packaging manifests together.

Usage:

`wadi sync-generated`

Options:
- `--help`: Print command-specific usage text.

Examples:
- `wadi sync-generated`

## release-cut

Bump the canonical release version, refresh packaging metadata, validate it, and optionally tag the repo.

Usage:

`wadi release-cut --version X.Y.Z [--tag]`

Options:
- `--version X.Y.Z`: Set the canonical release version to X.Y.Z before regenerating metadata.
- `--tag`: Create the annotated git tag that matches the refreshed release version.
- `--help`: Print command-specific usage text.

Examples:
- `wadi release-cut --version 0.2.0`
- `wadi release-cut --version 0.2.0 --tag`

## update-homebrew-tap

Clone or update the canonical Homebrew tap with the rendered wadi formula.

Usage:

`wadi update-homebrew-tap --tap-dir DIR [--formula PATH | --source-archive PATH] [--commit] [--push]`

Options:
- `--tap-dir DIR`: Update the Homebrew tap checkout rooted at DIR.
- `--formula PATH`: Reuse an existing Homebrew formula file instead of rendering one.
- `--source-archive PATH`: Reuse an explicit source archive when rendering packaging metadata instead of rebuilding one.
- `--commit`: Commit the rendered Homebrew formula into the tap checkout.
- `--push`: Push the Homebrew tap checkout after committing the rendered formula.
- `--help`: Print command-specific usage text.

Examples:
- `wadi update-homebrew-tap --tap-dir ../homebrew-wadi --formula Formula/wadi.rb --commit`
- `wadi update-homebrew-tap --tap-dir ../homebrew-wadi --source-archive dist/wadi-0.1.0-source.tar.gz --commit --push`

## docs

Render markdown CLI reference directly from the live command table.

Usage:

`wadi docs`

Options:
- `--help`: Print command-specific usage text.

Examples:
- `wadi docs`

## completion

Generate shell completion scripts from the live command table.

Usage:

`wadi completion [--workspace DIR] SHELL`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--help`: Print command-specific usage text.

Examples:
- `wadi completion bash`
- `wadi completion zsh`
- `wadi completion fish`

## toolchain

Print the resolved OCaml toolchain, backend, and package search roots.

Usage:

`wadi toolchain`

Options:
- `--help`: Print command-specific usage text.

Examples:
- `wadi toolchain`

## explain

Show why a target rebuilt or reused artifacts and which commands were planned.

Usage:

`wadi explain [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--current] [--json] [TARGET ...]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--profile NAME`: Select the workspace profile to resolve and build.
- `--backend auto|native|bytecode`: Choose the compiler backend or let wadi auto-resolve it.
- `--current`: Compute a fresh rebuild explanation from current inputs without compiling, linking, or materializing generated sources.
- `--json`: Print machine-readable JSON output instead of the text report.
- `--help`: Print command-specific usage text.

Examples:
- `wadi explain`
- `wadi explain hello`
- `wadi explain --current hello`
- `wadi explain --current --backend bytecode hello`
- `wadi explain --json hello`
- `wadi explain --profile release greeting hello`

## migrate

Scan dune files and emit a first-pass wadi.toml manifest with review comments.

Usage:

`wadi migrate [--workspace DIR] [--output PATH] [--stdout] [--force]`

Options:
- `--workspace DIR`: Read the workspace manifest from DIR.
- `--output PATH`: Write the generated manifest to PATH instead of wadi.toml.
- `--stdout`: Print the generated output instead of writing a file.
- `--force`: Overwrite existing generated files or output paths.
- `--help`: Print command-specific usage text.

Examples:
- `wadi migrate --stdout`
- `wadi migrate --workspace ../old-project`
- `wadi migrate --output converted.wadi.toml --force`
