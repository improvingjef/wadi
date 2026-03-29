## 2026-03-28

- `ocamldep -sort` is enough to remove hand-maintained intra-target module ordering as long as the builder still keeps `main` last for runnable link order.
- Content digests on manifest, source files, dependency stamps, and toolchain facts are a much more trustworthy incremental signal than timestamps alone.
- Package support is not just `-package foo`; the build has to propagate external package requirements through workspace-library dependencies or downstream targets fail at compile/link time.
- Relying on `PATH` for `ocamlfind` is brittle even inside an opam switch. The builder now has to resolve tool locations intentionally instead of assuming shell state is correct.
- Every new source module still requires touching the bootstrap `Makefile`, which reinforces that task 25 is not cleanup vanity work; it is active friction on the project.
- Resolving `ocamlc -where` and then locating `unix.cmi` in either the stdlib root or a `unix/` subdirectory removes one more ambient toolchain assumption from the bootstrap path.
- A single command table is not just a cleanup refactor; it gives the CLI one source of truth for help text, parsing entry points, and dispatch, which is the prerequisite for generated docs and completions later.
- A dedicated layout module removes `_oasis` path drift across build, clean, tests, and future install/diagnostic subtools; the path scheme only counts as simple if it lives in one place.
- `oasis toolchain` is much more useful when it reports resolved executable paths and package roots, not just the configured command tokens; debugging switch issues starts with concrete paths.
- Driving bootstrap compilation from a real root `oasis.toml` removes the duplicated object graph, but it also exposed that the self-hosting path still lags the main builder on `.mli` handling and package-derived flags.
- A clean target that regenerates build metadata before deleting it is the exact kind of pointless friction that gives build tools a bad name; bootstrap plumbing has to respect lifecycle semantics too.
- Backend selection has to be a first-class concern, not an accidental consequence of whichever compiler happens to be installed; `auto|native|bytecode` only became trustworthy once the builder, toolchain report, and bootstrap path all resolved through the same switch.
- Generic bootstrap pattern rules looked simple, but they were hiding two real correctness gaps: `.mli` files need their own build edges, and package flags belong to specific target groups rather than a global `unix` escape hatch.
- Rebuilding `_bootstrap` from scratch on every `make test` is cheap insurance; self-hosting claims are not credible if the fast path never proves that generation, compilation, and linking still compose from an empty directory.
- Generating explicit bootstrap compile rules exposed a remaining sharp edge: a shared object directory means duplicate module stems across app/test/library slices should be rejected early instead of producing confusing overwrites.
