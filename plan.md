1. [x] Define the workspace manifest format and the in-memory project model.
2. [x] Implement a Dune-free `oasis build` subtool for libraries and executables.
3. [x] Compile targets in dependency order with clear cycle detection and errors.
4. [x] Provide reproducible output directories and predictable artifact naming.
5. [x] Build a fixture-driven integration test harness that compiles real sample projects.
6. [x] Add unit tests for parsing, validation, dependency resolution, and command rendering.
7. [x] Design a cohesive subtool split for the Dune feature surface.
8. [x] Implement `oasis test` for test discovery, execution, and failure summaries.
9. [x] Implement `oasis run` for building and launching executables with arguments.
10. [x] Implement `oasis clean` with selective cache and artifact removal.
11. [x] Add package and library resolution beyond the OCaml standard library.
12. [x] Implement incremental rebuilds based on source and config changes.
13. [x] Implement sandboxed action execution for generated files and codegen steps.
14. [x] Add support for preprocessors, PPX pipelines, and generated modules.
15. [x] Implement workspace-wide defaults, profiles, and per-target overrides.
16. [x] Add developer-facing diagnostics explaining compiler invocations and resolution decisions.
21. [x] Infer intra-target module compilation order from OCaml interface dependencies so manifests stay declarative.
22. [x] Hide compiler-toolchain quirks like `-I +unix` and stdlib layout shifts behind a portable driver layer.
23. [x] Add a bytecode/native backend switch so bootstrap builds still work when `ocamlopt` is unavailable.
24. [x] Replace shell-wrapped process execution with direct child-process spawning so `oasis run` preserves signals, streaming output, and exact exit semantics.
25. [x] Eliminate the hand-maintained bootstrap `Makefile` object lists and rules by deriving bootstrap compilation from the workspace model or a tiny generator.
26. [x] Extend the direct process driver with explicit environment and stdin plumbing so future action/codegen subtools never need shell fallbacks.
27. [x] Extract `_oasis` artifact-layout path rules into a dedicated module shared by build, clean, install, and diagnostics subtools.
28. [x] Drive CLI help, argument parsing, and command dispatch from a single command table so new subtools do not require parallel edits across `cli.ml`, tests, and bootstrap rules.
29. [x] Add an `oasis toolchain` subtool that prints the resolved compiler, `ocamlfind`, stdlib, and package search roots so switch/path problems are debuggable without guesswork.
30. [x] Cache toolchain and package discovery within a build session so package-aware workspaces do not pay repeated probe subprocess costs.
31. [x] Persist rebuild reasons alongside target stamps and surface them through `oasis explain` so users can see exactly why a target rebuilt or was reused.
33. [x] Teach the bootstrap generator to honor `.mli` files so interface-heavy self-hosting builds stay aligned with `oasis build`.
34. [x] Drive bootstrap compile/link flags from target package metadata instead of the global `UNIX_FLAGS` fallback so the root workspace manifest becomes the single source of truth.
35. [x] Add a bootstrap smoke target or CI step that removes `_bootstrap`, regenerates the make fragment, and rebuilds from scratch to catch self-hosting regressions immediately.

17. [x] Implement installable binaries, libraries, and metadata export.
18. [x] Add multi-package workspace support with shared dependency analysis.
19. [x] Write migration guidance for existing Dune projects.
32. [x] Generate docs and shell completions from the command table so new subtools stay discoverable without duplicating CLI metadata.
36. [x] Detect duplicate module stems across bootstrap library/executable/test groups before writing rules so the shared `_bootstrap/obj` directory never hides collisions behind overwritten artifacts.
37. [x] Add CI coverage for both native and bytecode bootstrap smoke lanes so backend portability stays enforced outside local development.
38. [x] Teach the bootstrap/self-hosted path about profiles, actions, preprocessors, and PPX so the manifest surface does not diverge between `oasis build` and `make test`.
39. [x] Detect and explain collisions between generated outputs and checked-in source files before a build silently overrides one with the other.
40. [x] Replace copy-heavy action sandboxes with a cheaper file-materialization strategy so workspace sandboxes stay fast on larger trees.
41. [x] Track preprocessor/PPX auxiliary inputs and settings in rebuild diagnostics so transformed-source invalidations are explainable instead of implicit.
42. [x] Drive `scripts/generate_bootstrap_makefile.ml` from the workspace model or generated metadata so adding a core module never requires editing a second hard-coded module list.
43. [x] Persist a machine-readable sibling to `.oasis-explain` so editors and CI can consume rebuild reasons without scraping human-formatted text.
44. [x] Add `oasis explain --current` or an equivalent dry-run diff so users can inspect why a target would rebuild before paying the build cost.
45. [x] Export findlib-friendly `META` files and install-layout metadata from `oasis install` so staged libraries can be consumed without bespoke `-I` wiring.
46. [x] Add `DESTDIR` or equivalent relocation support to `oasis install` so package-manager staging does not have to rewrite prefixes after the fact.
47. [x] Teach `oasis completion` to suggest workspace-local target names and profile names instead of only static flags and shell names.
48. [x] Add `oasis explain --json` so automation can print the persisted `.oasis-explain.json` payload directly instead of opening files by path.
49. [x] Generate release docs and packaged shell-completion artifacts from `oasis docs` and `oasis completion` in CI so shipped assets cannot drift from the command table.
50. [x] Close over transitive workspace-library dependencies during `oasis install` or warn when generated `META` files reference unstaged internal packages.
51. [x] Clarify and test relative `--prefix` plus `--destdir` semantics so local staging does not inherit surprising absolute workspace paths.
52. [x] Add an explicit `--backend` flag to `oasis explain --current` so dry-run answers can mirror non-default build requests instead of relying only on ambient backend selection.
53. [x] Separate pure explain planning from action/preprocess materialization so `oasis explain --current` stays side-effect-light even for generated-source targets.
54. [x] Allow member manifests to declare package-local actions, preprocessors, and PPX tools with automatic path rebasing so multi-package repos do not centralize every helper in the root manifest.
55. [x] Record which `oasis install` artifacts were explicitly requested versus added by dependency closure so packaging automation can explain why extra libraries were staged.
56. [x] Surface member package paths in diagnostics and future dynamic completions so globally unique target names stay navigable in larger workspaces.
57. [x] Add manifest reference and migration examples for preprocessor/PPX `deps` plus generated-source collision rules so users do not learn the new constraints by failing builds.
58. [x] Show declared auxiliary tool inputs in steady-state `oasis explain` output, not just rebuild reasons, so codegen and transform pipelines stay inspectable before anything changes.
59. [x] Replace generation-time workspace completion snapshots with a runtime completion query protocol so one sourced script stays accurate as users move between workspaces.
60. [x] Distinguish fully reused targets from action-only regeneration in build and explain reports so missing generated outputs do not look like a perfect cache hit after the tool repairs them.
61. [x] Restore shell-native path completion for `--workspace`, `--prefix`, and `--destdir` in the runtime completion protocol so dynamic queries do not regress directory-flag ergonomics.
62. [x] Teach bash completion to surface member package-path descriptions or another shell-appropriate fallback so package-aware target discovery is not limited to zsh and fish.
63. [x] Extend package-path annotations to `oasis run`, `oasis test`, and `oasis install` summaries so every user-facing subtool reports large-workspace target origin consistently.
64. [x] Add direct runtime execution tests for zsh and fish completion scripts so path-mode and described completions are exercised beyond string snapshots.
65. [x] Replace the ad hoc completion marker line with a structured or versioned completion-query response so future shell integrations are not coupled to one magic string.
66. [x] Decouple release-artifact generation from unrelated bootstrap test-source scans so refreshing `docs/cli.md` and packaged completions never depends on the whole test tree parsing cleanly.
67. [x] Replace the toplevel `#mod_use` bootstrap generator with a compiled or self-hosted planner path so root-library preprocessors and PPX can apply to the generator implementation itself, not just the binaries it emits rules for.


73. [x] Implement `oasis graph` so target build order, module order, and active action/preprocess/PPX pipelines are visible without compiling.
74. [x] Implement `oasis deps` so transitive external package requirements and `ocamlfind` search roots are inspectable without reverse-engineering compiler invocations.
75. [x] Implement `oasis migrate` to scan `dune-project` plus workspace `dune` files and emit a reviewable first-pass `oasis.toml`.
76. [x] Extend `oasis migrate` to translate common Dune fields like `preprocess`, `pps`, install/public metadata, and common unsupported stanzas into first-class oasis sections instead of warning comments.
77. [x] Add `oasis env` so users can print the exact environment a subtool would run under before executing it.
78. [x] Add `oasis repl` so workspaces can launch a package-aware OCaml toplevel without manually reconstructing include paths and package flags.

81. [x] Teach `oasis migrate` to infer auxiliary `deps` for translated dune preprocess actions and rules when the source form names concrete file inputs, reducing the remaining review-only warnings in generated manifests.
82. [x] Add `oasis env --json` or a changed-only mode so large inherited environments stay inspectable in editors and CI without forcing humans to diff hundreds of ambient variables by eye.
83. [x] Cache and fingerprint generated `oasis repl` toplevel binaries so repeated REPL launches do not pay an `ocamlmktop` relink after a no-op build.

## the single biggest blocker for real world migration
73a. [x] Implement library namespace wrapping so a library named `foo` generates a wrapper module that re-exports all child modules as `Foo.Child_module`. This is required for compatibility with any dune-built OCaml project that uses `(libraries ...)` namespacing and is the single biggest blocker for real-world migration.

20. [x] Benchmark build latency and tighten startup and execution overhead.
67. [x] Implement `oasis migrate` to parse dune/dune-project s-expressions and emit an equivalent `oasis.toml`, automating the migration path from Dune workspaces.
68. [x] Package generated shell completion scripts (bash, zsh, fish) for distribution so users can install them via opam or system package managers without running `oasis completion` manually.
69. [x] Publish an `oasis.opam` package to the opam repository so OCaml developers can install oasis through their existing toolchain with `opam install oasis`.
70. [x] Set up GitHub Releases with pre-built static binaries for macOS and Linux so users can install oasis without opam or a build toolchain.
71. [x] Create a Homebrew formula so macOS users can install oasis with `brew install oasis` without needing an opam setup.
72. [x] Add a `flake.nix` so Nix users can run oasis directly or add it to their development shells.
79. [x] Add `oasis bench` with stable benchmark target execution and machine-readable summaries so the execution subtool split covers Dune’s benchmarking workflows as well as builds and tests.
80. [x] Eliminate the remaining app-only interpreter seed from bootstrap generation so cold-start builds no longer depend on `scripts/generate_bootstrap_makefile.ml` loading source through the toplevel at all.
84. [x] Add an `oasis env repl` mode or equivalent machine-readable REPL plan output so editors can request include paths, linked units, and runtime env without launching the toplevel.
85. [x] Extend dune-action dependency inference beyond simple `run`/`copy` forms to `progn`, `with-stdin-from`, `diff`, and alias-driven workflows so fewer migrations fall back to review comments.
86. [x] Add an explicit `oasis repl --script` or generated-loader mode so noninteractive use does not depend on OCaml toplevel argument quirks like `-init` versus script-file execution.
87. [x] Allow wrapped libraries to provide an explicit checked-in wrapper module or interface so more custom Dune `Foo.ml` wrapper patterns migrate without disabling namespacing.
88. [x] Prune stale compiled module artifacts when a target’s module list shrinks or wrapping mode flips so `oasis install` never stages dead `.cmi`/`.cmo` files from an older build shape.
89. [x] Extend the completion protocol with a file-path mode so file-valued flags like `oasis repl --script` do not fall back to directory-only completion.
90. [x] Lower the shell-quoted noise in migrated composite dune actions by mapping `with-stdin-from`, `with-stdout-to`, and `progn` to more structured oasis action/preprocess fields when possible instead of emitting `sh -c` fallbacks.
91. [x] Feed the generated `package/share/...` completion tree into future opam/Homebrew/Nix packaging definitions so downstream installers reuse one canonical install layout instead of re-encoding shell-specific paths.
92. [x] Introduce first-class multi-step action sequences so migrated multi-command dune `progn` rules no longer need a shell fallback once command chaining deserves manifest-level structure.
93. [x] Teach `oasis migrate` to recognize explicit wrapped-library module lists that intentionally keep a checked-in `Foo.ml` wrapper, not just the source-inferred wrapper case.
94. [x] Extend `oasis env` with a `bench` mode so benchmark subprocess environments are inspectable with the same ergonomics as build, run, test, and install.
95. [x] Add dedicated `[bench.*]` target declarations if executable-only benchmarking becomes too limiting for real-world suites that need per-benchmark metadata or non-default argv.
96. [x] Replace the remaining `$(shell $(OCAML) scripts/render_bootstrap_mod_use.ml ...)` cold-start metadata probe with a compiled or cached helper so bootstrap source discovery no longer needs the OCaml interpreter even after the planner itself is compiled.
97. [x] Collapse duplicate cold-start compilation between `oasis-seed` and the subsequent app bootstrap build so removing the toplevel planner path does not replace one bootstrap tax with two full compiles of the core modules.
98. [x] Teach the compiled bootstrap planner to refresh `scripts/bootstrap_seed_metadata.mk` directly so the legacy metadata helper script can disappear instead of surviving as a generator-only maintenance path.
99. [x] Gate shared `oasis-seed` object reuse on profile-sensitive compile inputs so future bootstrap-profile flags, env, preprocessors, or PPX on the core library cannot silently reuse mismatched seed artifacts.
100. [x] Teach the bootstrap seed compiler itself to honor common-library actions, preprocessors, PPX, and profile env so safe shared-object reuse remains available even after `oasis_core` stops compiling from raw checked-in sources.
101. [x] Define one canonical release metadata source for archive URLs, checksums, homepage/bug-report links, and license so opam/Homebrew/GitHub release plumbing stops depending on repo-local placeholders.
102. [x] Publish the generated `Formula/oasis.rb` through a dedicated tap update flow so users can get from `brew install oasis` to a working binary without pointing Homebrew at this repo directly.
103. [x] Collapse release version bumps, source-archive refresh, and tag validation into one explicit release-cut command so the packaging metadata stops depending on a manually remembered sequence.
104. [x] Replace the hard-coded `LC_ALL=C.UTF-8` release-archive environment with a portable locale fallback so packaging commands stay warning-free on macOS and other hosts that do not ship that locale name.
105. [x] Teach `scripts/update_homebrew_tap.sh` to clone the tap repository directly from release metadata when no checkout is present so local release maintenance does not require a separate manual `git clone` step.
106. [x] Execute packaging entrypoints directly from shipped scripts and emit duplicate-free release archives that preserve helper/installer script presence and execute bits so source-tarball installs behave the same as a repo checkout.
107. [x] Support interface-only OCaml modules (`.mli` without `.ml`) across build, install, stale-artifact pruning, and rebuild explanations so migrated Dune projects do not need fake implementation files.
108. [x] Teach the bootstrap planner, generated makefile, and seed metadata path to model interface-only modules the same way as `oasis build`, keeping self-hosting parity for signature-heavy codebases.
109. [x] Teach `oasis migrate` to preserve Dune `modules_without_implementation` when inferring target module lists so signature-only APIs migrate without hand-editing the generated manifest.
110. [x] Implement `oasis action` so declared generated-file steps can run in dependency order without forcing a full compile/link cycle.
111. [x] Implement `oasis promote` for explicit non-source action outputs so checked-in snapshots and fixtures can be refreshed on purpose instead of through ad hoc shell scripts.
112. [x] Extend the command table, env reporting, completion queries, release docs, and packaged artifacts to cover the generated-source subtools so `action`/`promote` stay discoverable and testable.
113. [x] Add a first-class checked-in generated-source mode for `.ml`/`.mli` promotion so snapshotting source-like outputs does not collide with the build-time generated-source safety checks.
114. [x] Clear declared action outputs from the action sandbox before execution so stale checked-in snapshots or prior generated files cannot masquerade as freshly regenerated outputs.
115. [x] Exclude generated-source snapshots from bootstrap workspace-input tracking when the build actually compiles the generated copy, keeping self-hosting fingerprints aligned with real compile inputs.
116. [x] Teach `oasis migrate` to translate dune `rule (mode promote)` source targets into explicit `checked_in_sources` declarations instead of leaving them as manual follow-up.
117. [x] Implement `oasis init` so new workspaces stop starting with a blank `oasis.toml` and immediately scaffold into something that builds.
118. [x] Implement `oasis lock` so resolved toolchain facts plus external package paths can be snapshotted into a reviewable machine-readable file.
119. [x] Implement `oasis vendor` for local source dependencies so package-only manifests can be copied under `vendor/` and registered as workspace members without hand-editing the root manifest.
120. [x] Teach `oasis build` and `oasis install` to optionally consume `oasis.lock` and fail or warn when resolved package paths drift from the committed snapshot.
121. [x] Extend `oasis vendor` beyond local directories to git/url sources plus checksum pinning so vendoring does not depend on a manual checkout step.
122. [x] Add `oasis init --member` plus multi-package templates so package scaffolding does not fall back to hand-edited `members = [...]`.
123. [x] Implement `oasis ppx` as an explicit inspect/apply subtool so preprocess and PPX debugging is as decomposed as build/action/promote.
124. [x] Validate recorded `oasis.lock` toolchain facts like compiler version, stdlib/unix roots, and package search roots so snapshot drift cannot hide outside `package_paths`.
125. [x] Eliminate the remaining tracked `scripts/bootstrap_seed_metadata.mk` maintenance seam by deriving or refreshing seed metadata directly from the compiled planner during normal workflows.
126. [x] Add shared preprocess-plus-PPX fixture helpers for source-inspection tests so transform expectations follow real rewritten syntax instead of ad hoc test-only assumptions.
127. [x] Remove the remaining clean-checkout fallback dependency on tracked bootstrap seed metadata by deriving enough seed compile inputs before any compiled `oasis` binary exists.
128. [x] Move bootstrap seed metadata and transformed seed snapshots under `_bootstrap/` so normal first-build cache generation does not dirty tracked `scripts/` paths.
129. [x] Replace the one-time clean-checkout OCaml-toplevel fallback for seed metadata generation with a lighter metadata-only bootstrap path so the first `make` does not need to load the full planner through the interpreter.
130. [x] Add a single `make sync-generated` target that refreshes bootstrap seed metadata plus committed docs/completions/packaging manifests so generated-asset upkeep is one command instead of a scavenger hunt.
131. [x] Guard the first clean-checkout `oasis-seed` build with an explicit metadata refresh and recursive re-entry so the bootstrap path never emits a bogus empty-variable compile before the new metadata is loaded.
132. [x] Revisit the first clean-checkout bootstrap restart path so the original make process does not briefly generate app/full makefiles with empty shared-output touch lists before the reloaded metadata-driven pass takes over.
133. [x] Skip generated bootstrap makefile includes during the recursive `_bootstrap/bin/oasis-seed` self-build so a clean full bootstrap does not detour through an app-only planning pass before metadata is live.
134. [x] Derive bootstrap shared-output touch/prune work from the freshly written seed metadata instead of stale parse-time Make variables so clean full bootstraps never emit empty sync loops after metadata refresh.
135. [x] Teach `make release-manifests` and `make sync-generated` to refresh a local `dist/` source archive alongside `Formula/oasis.rb` so maintainers can inspect the exact tarball bytes behind the generated Homebrew checksum without a second manual step.
136. [x] Let `scripts/generate_packaging_manifests.sh` either reuse an explicit source archive or refresh one into a caller-chosen directory so packaging flows stop depending on throwaway temp tarballs.
137. [x] Skip bootstrap metadata and generated-makefile includes for shell-only maintenance goals like `release-manifests`, `release-cut`, and `update-homebrew-tap` so packaging upkeep does not compile `oasis` just to run shell scripts.
138. [x] Teach the GitHub release publish job to reuse `scripts/generate_packaging_manifests.sh` with the downloaded source archive, likely via a flat formula-output mode, so CI and local release maintenance converge on one packaging-manifest entrypoint.
139. [x] Let `scripts/generate_packaging_manifests.sh --reuse-source-archive-dir DIR` consume an already-downloaded release source archive so publish jobs can package downloaded artifacts without regenerating them.
140. [x] Let `scripts/generate_packaging_manifests.sh` emit flat release assets plus `SHA256SUMS` from one invocation so GitHub release packaging stops carrying ad hoc formula/checksum steps outside the shared generator.
141. [ ] Publish the generated `oasis.opam` alongside GitHub release tarballs and `oasis.rb` so release consumers can fetch canonical package metadata without cloning the repo.
