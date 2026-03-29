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
- Generated files only feel civilized when they stay under `_oasis`; copying back only declared action outputs keeps sandboxes useful and avoids dirtying the source tree with codegen fallout.
- Sandbox execution immediately exposed a boring but critical filesystem detail: copied helper scripts have to preserve executable bits or the whole “declarative action” story collapses on first use.
- Profiles need to change artifact roots, not just flags. Reusing one build directory across `release` and `dev` would turn “profile” into a cache-corruption feature.
- Text preprocessors fit naturally as stdin/stdout transforms, while PPX support is cleaner when the builder treats rewriters as named tools and lets the compiler own the AST pipeline.
- Growing the manifest model triggered a wave of OCaml record-label ambiguity; explicit type annotations are a small price to pay for keeping a richer configuration format readable and type-safe.
- `ocamlfind printconf path`, `ocamlfind query ...`, and `ocamlc -where` were quietly happening far more often than the user-visible work justified; a per-build toolchain session buys real speed by collapsing those probes to one hit.
- Human-facing rebuild explanations only stay trustworthy if downstream fingerprints summarize dependencies at the dependency edge. Embedding raw dependency fingerprint text made `oasis explain` blame leaf source files in the wrong target.
- A cached target still needs first-class diagnostics. Persisting `.oasis-explain` next to `.oasis-stamp` turns “why did this rebuild?” from guesswork into a cheap read instead of another compile.
- The bootstrap path still has one embarrassing duplication seam: the generated makefile is manifest-driven, but `scripts/generate_bootstrap_makefile.ml` still carries a hand-maintained `#mod_use` list for core modules.

## 2026-03-29

- `oasis install` only feels real once it stages more than a binary. Copying compiler-consumable library artifacts, the source manifest, and a machine-readable install manifest turns a build output into something another tool can reason about.
- A command table is not actually a single source of truth if it only feeds `--help`. Generating markdown docs and shell completions from the same metadata is what makes the subtool split discoverable instead of aspirational.
- Persisting `.oasis-explain.json` beside the human report is cheap and worthwhile as long as both formats are emitted from the same builder data. Two renderers over one fact set are maintainable; two diagnostic code paths are not.
- The next install friction showed up immediately: local staging is pleasant, but downstream packaging still wants `META` export and `DESTDIR`-style relocation.
- Static shell completion is enough to prove the command-table design, but the moment the tool grows real workspace nouns, target-aware and profile-aware completion becomes part of usability rather than polish.
- `META` generation has to come from manifest intent, not just whichever artifacts happened to land in `lib/<name>`. The useful signal is direct workspace-library deps plus external package deps.
- `DESTDIR` is a two-path problem: package managers care about the logical prefix, while the filesystem cares about the realized stage root. Install metadata has to record both or the staging story stays ambiguous.
- `oasis explain --json` is most trustworthy when it prints the persisted payload directly. Automation should consume the exact sibling file the builder wrote, not a second renderer that might drift.
- macOS temp paths quietly canonicalize through `/private`; staging tests that care about installed roots need to compare normalized paths, not raw temp-directory strings.
- A useful dry-run diagnostic is just the build planner with the compiler and linker switched off. `oasis explain --current` only became credible once it reused the same fingerprint, dependency, and command-planning path as a real build.
- Relative `--prefix` plus `--destdir` needs two truths at once: preserve the logical prefix the user asked for, and stage under the physical root the filesystem needs. Rewriting `_stage` into an absolute workspace path is exactly the kind of packaging surprise that makes build tools feel hostile.
- Bootstrap generation has to reject duplicate module stems before it writes rules. A shared `_bootstrap/obj` directory turns same-stem library/app/test modules into silent overwrites unless the planner names the collision up front.
- Multi-package support stays understandable when the root manifest owns workspace-wide defaults, profiles, and tool registries while member manifests contribute rebased targets. Letting every package define its own workspace-level knobs immediately turns merge order and relative-path semantics into guesswork.
- `oasis install` has two separate notions of selection: what the user explicitly asked for and what must be staged so internal `META` references stay valid. Treating those as the same set quietly produces broken staging outputs.
- Dry-run diagnostics need the same backend control as real builds. If `oasis explain --current` cannot say “show me bytecode planning” or “show me native planning,” it is still leaking ambient toolchain state into something that should be inspectable on purpose.
- Generated sources cannot be allowed to silently outrank checked-in modules. Failing fast on `version.ml`-style collisions is much less hostile than compiling the wrong file and pretending nothing strange happened.
- Preprocessors and PPX rewriters stop feeling magical once their sidecar inputs are declared and fingerprinted. A tiny `deps = [...]` list turns “why did this rebuild?” from a guess into a direct answer.
- Install metadata needs provenance, not just inventory. Package tooling cares whether an artifact was explicitly requested or staged because another target’s `META` would otherwise dangle.
