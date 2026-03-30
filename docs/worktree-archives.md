# Worktree Source Archive Inclusion Boundary

The `build_release_archives.sh` script supports two source-archive modes,
controlled by `--source-archive-mode`: **tracked** (default) and **worktree**.
This document explains the file-inclusion rules under `worktree` mode and
their effect on archive checksums.

## Archive modes

### `tracked` mode (default)

Includes only files known to git:

```
git ls-files --cached --modified
```

This is the conservative baseline. The archive contains exactly the committed
and staged working-tree content. Untracked files of any kind are excluded.

### `worktree` mode

Starts with the same `--cached --modified` set, then adds untracked files
**only under directories that already contain tracked content**:

```
git ls-files --cached --modified
git ls-files --others --exclude-standard -- <tracked-root-dirs>
```

The list of tracked root directories is derived by extracting the first
path component of every tracked file:

```
git ls-files | awk -F/ 'NF > 1 { print $1 }' | sort -u
```

The two file lists are merged with `sort -u` to deduplicate.

## Why root-level untracked files are excluded

The `--others` query is scoped to the tracked root directories (`src/`,
`scripts/`, `docs/`, etc.) rather than the entire repository root. Files
that sit directly in the repo root (e.g. editor scratch files, `.log`
outputs, local scripts) are never passed as path arguments to the second
`git ls-files` call and therefore never appear in the archive.

This is intentional: root-level detritus is the most common source of
accidental content in a working tree, and including it would make archive
checksums unstable across developer machines for reasons unrelated to the
actual source.

## Why additions under tracked directories are captured

Generated or build-produced files that land inside already-tracked
directories (e.g. a new `.ml` file in `src/`, a new test fixture in
`test/`) *are* included. This is the purpose of `worktree` mode: it lets a
release archive reflect work-in-progress additions that have not yet been
committed, as long as those additions live inside the project's established
directory structure and are not excluded by `.gitignore`.

## Effect on checksums

Archive checksums are deterministic for a given set of included files
because timestamps are normalized (`touch -t 202601010000`), tar entries
are sorted, and gzip uses `-n` (no embedded filename/timestamp). Two
machines with the same file content and the same `--source-archive-mode`
will produce byte-identical archives.

Checksum differences between `tracked` and `worktree` mode are therefore
attributable to exactly one cause: untracked, non-ignored files under
tracked directories. If a checksum changes unexpectedly after switching to
`worktree` mode, run:

```
git ls-files --others --exclude-standard -- $(git ls-files | awk -F/ 'NF > 1 { print $1 }' | sort -u)
```

to see which extra files entered the archive.
