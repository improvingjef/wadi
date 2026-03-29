## 2026-03-28

- `ocamldep -sort` is enough to remove hand-maintained intra-target module ordering as long as the builder still keeps `main` last for runnable link order.
- Content digests on manifest, source files, dependency stamps, and toolchain facts are a much more trustworthy incremental signal than timestamps alone.
- Package support is not just `-package foo`; the build has to propagate external package requirements through workspace-library dependencies or downstream targets fail at compile/link time.
- Relying on `PATH` for `ocamlfind` is brittle even inside an opam switch. The builder now has to resolve tool locations intentionally instead of assuming shell state is correct.
- Every new source module still requires touching the bootstrap `Makefile`, which reinforces that task 25 is not cleanup vanity work; it is active friction on the project.
