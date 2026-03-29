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
17. [ ] Implement installable binaries, libraries, and metadata export.
18. [ ] Add multi-package workspace support with shared dependency analysis.
19. [ ] Write migration guidance for existing Dune projects.
20. [ ] Benchmark build latency and tighten startup and execution overhead.
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
32. [ ] Generate docs and shell completions from the command table so new subtools stay discoverable without duplicating CLI metadata.
33. [x] Teach the bootstrap generator to honor `.mli` files so interface-heavy self-hosting builds stay aligned with `oasis build`.
34. [x] Drive bootstrap compile/link flags from target package metadata instead of the global `UNIX_FLAGS` fallback so the root workspace manifest becomes the single source of truth.
35. [x] Add a bootstrap smoke target or CI step that removes `_bootstrap`, regenerates the make fragment, and rebuilds from scratch to catch self-hosting regressions immediately.
36. [ ] Detect duplicate module stems across bootstrap library/executable/test groups before writing rules so the shared `_bootstrap/obj` directory never hides collisions behind overwritten artifacts.
37. [ ] Add CI coverage for both native and bytecode bootstrap smoke lanes so backend portability stays enforced outside local development.
38. [ ] Teach the bootstrap/self-hosted path about profiles, actions, preprocessors, and PPX so the manifest surface does not diverge between `oasis build` and `make test`.
39. [ ] Detect and explain collisions between generated outputs and checked-in source files before a build silently overrides one with the other.
40. [ ] Replace copy-heavy action sandboxes with a cheaper file-materialization strategy so workspace sandboxes stay fast on larger trees.
41. [ ] Track preprocessor/PPX auxiliary inputs and settings in rebuild diagnostics so transformed-source invalidations are explainable instead of implicit.
42. [ ] Drive `scripts/generate_bootstrap_makefile.ml` from the workspace model or generated metadata so adding a core module never requires editing a second hard-coded module list.
43. [ ] Persist a machine-readable sibling to `.oasis-explain` so editors and CI can consume rebuild reasons without scraping human-formatted text.
44. [ ] Add `oasis explain --current` or an equivalent dry-run diff so users can inspect why a target would rebuild before paying the build cost.
