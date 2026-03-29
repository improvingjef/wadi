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

20. [ ] Benchmark build latency and tighten startup and execution overhead.
67. [ ] Implement `oasis migrate` to parse dune/dune-project s-expressions and emit an equivalent `oasis.toml`, automating the migration path from Dune workspaces.
68. [x] Package generated shell completion scripts (bash, zsh, fish) for distribution so users can install them via opam or system package managers without running `oasis completion` manually.
69. [ ] Publish an `oasis.opam` package to the opam repository so OCaml developers can install oasis through their existing toolchain with `opam install oasis`.
70. [ ] Set up GitHub Releases with pre-built static binaries for macOS and Linux so users can install oasis without opam or a build toolchain.
71. [ ] Create a Homebrew formula so macOS users can install oasis with `brew install oasis` without needing an opam setup.
72. [ ] Add a `flake.nix` so Nix users can run oasis directly or add it to their development shells.
79. [ ] Add `oasis bench` with stable benchmark target execution and machine-readable summaries so the execution subtool split covers Dune’s benchmarking workflows as well as builds and tests.
80. [ ] Eliminate the remaining app-only interpreter seed from bootstrap generation so cold-start builds no longer depend on `scripts/generate_bootstrap_makefile.ml` loading source through the toplevel at all.
84. [x] Add an `oasis env repl` mode or equivalent machine-readable REPL plan output so editors can request include paths, linked units, and runtime env without launching the toplevel.
85. [x] Extend dune-action dependency inference beyond simple `run`/`copy` forms to `progn`, `with-stdin-from`, `diff`, and alias-driven workflows so fewer migrations fall back to review comments.
86. [x] Add an explicit `oasis repl --script` or generated-loader mode so noninteractive use does not depend on OCaml toplevel argument quirks like `-init` versus script-file execution.
87. [ ] Allow wrapped libraries to provide an explicit checked-in wrapper module or interface so more custom Dune `Foo.ml` wrapper patterns migrate without disabling namespacing.
88. [x] Prune stale compiled module artifacts when a target’s module list shrinks or wrapping mode flips so `oasis install` never stages dead `.cmi`/`.cmo` files from an older build shape.
89. [x] Extend the completion protocol with a file-path mode so file-valued flags like `oasis repl --script` do not fall back to directory-only completion.
90. [ ] Lower the shell-quoted noise in migrated composite dune actions by mapping `with-stdin-from`, `with-stdout-to`, and `progn` to more structured oasis action/preprocess fields when possible instead of emitting `sh -c` fallbacks.
91. [ ] Feed the generated `package/share/...` completion tree into future opam/Homebrew/Nix packaging definitions so downstream installers reuse one canonical install layout instead of re-encoding shell-specific paths.
