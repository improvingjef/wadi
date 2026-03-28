1. [x] Define the workspace manifest format and the in-memory project model.
2. [x] Implement a Dune-free `oasis build` subtool for libraries and executables.
3. [x] Compile targets in dependency order with clear cycle detection and errors.
4. [x] Provide reproducible output directories and predictable artifact naming.
5. [x] Build a fixture-driven integration test harness that compiles real sample projects.
6. [x] Add unit tests for parsing, validation, dependency resolution, and command rendering.
7. [ ] Design a cohesive subtool split for the Dune feature surface.
8. [x] Implement `oasis test` for test discovery, execution, and failure summaries.
9. [x] Implement `oasis run` for building and launching executables with arguments.
10. [ ] Implement `oasis clean` with selective cache and artifact removal.
11. [ ] Add package and library resolution beyond the OCaml standard library.
12. [ ] Implement incremental rebuilds based on source and config changes.
13. [ ] Implement sandboxed action execution for generated files and codegen steps.
14. [ ] Add support for preprocessors, PPX pipelines, and generated modules.
15. [ ] Implement workspace-wide defaults, profiles, and per-target overrides.
16. [ ] Add developer-facing diagnostics explaining compiler invocations and resolution decisions.
17. [ ] Implement installable binaries, libraries, and metadata export.
18. [ ] Add multi-package workspace support with shared dependency analysis.
19. [ ] Write migration guidance for existing Dune projects.
20. [ ] Benchmark build latency and tighten startup and execution overhead.
21. [ ] Infer intra-target module compilation order from OCaml interface dependencies so manifests stay declarative.
22. [ ] Hide compiler-toolchain quirks like `-I +unix` and stdlib layout shifts behind a portable driver layer.
23. [ ] Add a bytecode/native backend switch so bootstrap builds still work when `ocamlopt` is unavailable.
24. [x] Replace shell-wrapped process execution with direct child-process spawning so `oasis run` preserves signals, streaming output, and exact exit semantics.
25. [ ] Eliminate the hand-maintained bootstrap `Makefile` object lists and rules by deriving bootstrap compilation from the workspace model or a tiny generator.
26. [ ] Extend the direct process driver with explicit environment and stdin plumbing so future action/codegen subtools never need shell fallbacks.
