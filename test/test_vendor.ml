open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let write_member_manifest workspace contents =
  Fs.write_file (Filename.concat workspace "wadi.toml") contents

let git_env =
  [
    ("GIT_AUTHOR_NAME", "Wadi Tests");
    ("GIT_AUTHOR_EMAIL", "wadi@example.com");
    ("GIT_COMMITTER_NAME", "Wadi Tests");
    ("GIT_COMMITTER_EMAIL", "wadi@example.com");
  ]

let run_git ~cwd args = Process.run_capture ~cwd ~env:git_env "git" args

let init_git_repo source =
  let init = run_git ~cwd:source [ "init"; "-q" ] in
  assert_int_equal 0 init.status "git init should succeed for vendoring tests";
  let add = run_git ~cwd:source [ "add"; "." ] in
  assert_int_equal 0 add.status "git add should stage vendored fixtures";
  let commit = run_git ~cwd:source [ "commit"; "-q"; "-m"; "initial" ] in
  assert_int_equal 0 commit.status "git commit should snapshot vendored fixtures";
  let revision = run_git ~cwd:source [ "rev-parse"; "HEAD" ] in
  assert_int_equal 0 revision.status
    "git rev-parse should report the vendored fixture revision";
  String.trim revision.output

let sha256 path =
  let run prog args =
    let outcome = Process.run_capture ~env:[ ("LC_ALL", "C"); ("LANG", "C") ] prog args in
    assert_int_equal 0 outcome.status ("expected checksum helper to succeed for " ^ path);
    match String_util.split_whitespace outcome.output with
    | digest :: _ -> digest
    | [] -> fail ("missing checksum output for " ^ path)
  in
  match Toolchain.resolve_executable_path "shasum" with
  | Some prog -> run prog [ "-a"; "256"; path ]
  | None -> (
      match Toolchain.resolve_executable_path "sha256sum" with
      | Some prog -> run prog [ path ]
      | None -> fail "expected shasum or sha256sum to be available for vendoring tests")

let cases =
  [
    ( "vendors a local package into vendor/ and registers it as a member",
      fun () ->
        with_temp_dir "wadi-vendor-src" (fun source ->
            write_member_manifest source {|
[library.dep]
dir = "lib"
modules = ["dep"]
|};
            write_source source "lib/dep.ml" {|let message = "vendored"|};
            with_temp_dir "wadi-vendor-workspace" (fun workspace ->
                write_manifest workspace
                  {|
workspace = "demo"
version = 1

[executable.demo]
dir = "app"
main = "main"
deps = ["dep"]
|};
                write_source workspace "app/main.ml"
                  {|let () = print_endline Dep.message|};
                let vendor =
                  run_wadi ~cwd:workspace
                    [ "vendor"; "--source"; source; "--name"; "dep" ]
                in
                assert_int_equal 0 vendor.status
                  "vendor should copy and register a local package";
                assert_file_exists (Filename.concat workspace "vendor/dep/wadi.toml");
                assert_string_contains ~needle:{|members = ["vendor/dep"]|}
                  (Fs.read_file (manifest_path workspace))
                  "vendor should register the new member in the root manifest";
                let run = run_wadi ~cwd:workspace [ "run"; "demo" ] in
                assert_int_equal 0 run.status
                  "the vendored package should participate in normal builds";
                assert_string_contains ~needle:"vendored\n" run.output
                  "the root workspace should resolve the vendored library")) );
    ( "rejects vendored manifests that are not member-compatible",
      fun () ->
        with_temp_dir "wadi-vendor-invalid" (fun source ->
            write_member_manifest source
              {|
workspace = "dep"
version = 1

[library.dep]
dir = "lib"
modules = ["dep"]
|};
            write_source source "lib/dep.ml" {|let message = "bad"|};
            with_temp_dir "wadi-vendor-root" (fun workspace ->
                write_manifest workspace {|
workspace = "demo"
version = 1
|};
                let vendor =
                  run_wadi ~cwd:workspace
                    [ "vendor"; "--source"; source; "--name"; "dep" ]
                in
                assert_true (vendor.status <> 0)
                  "vendor should reject non-member-safe manifests";
                assert_string_contains ~needle:"defines a top-level workspace name"
                  vendor.output "vendor should explain the member-safety violation")) );
    ( "replaces an existing vendored checkout with force",
      fun () ->
        with_temp_dir "wadi-vendor-force-src" (fun source ->
            write_member_manifest source {|
[library.dep]
dir = "lib"
modules = ["dep"]
|};
            write_source source "lib/dep.ml" {|let message = "first"|};
            with_temp_dir "wadi-vendor-force-workspace" (fun workspace ->
                write_manifest workspace
                  {|
workspace = "demo"
version = 1

[executable.demo]
dir = "app"
main = "main"
deps = ["dep"]
|};
                write_source workspace "app/main.ml"
                  {|let () = print_endline Dep.message|};
                let first =
                  run_wadi ~cwd:workspace
                    [ "vendor"; "--source"; source; "--name"; "dep" ]
                in
                assert_int_equal 0 first.status "the first vendor command should succeed";
                write_source source "lib/dep.ml" {|let message = "second"|};
                let rejected =
                  run_wadi ~cwd:workspace
                    [ "vendor"; "--source"; source; "--name"; "dep" ]
                in
                assert_true (rejected.status <> 0)
                  "vendor should refuse to replace an existing checkout without force";
                assert_string_contains ~needle:"rerun with --force" rejected.output
                  "vendor should explain how to replace an existing checkout";
                let forced =
                  run_wadi ~cwd:workspace
                    [ "vendor"; "--source"; source; "--name"; "dep"; "--force" ]
                in
                assert_int_equal 0 forced.status
                  "vendor --force should refresh an existing checkout";
                let run = run_wadi ~cwd:workspace [ "run"; "demo" ] in
                assert_int_equal 0 run.status
                  "the refreshed vendored package should still build";
                assert_string_contains ~needle:"second\n" run.output
                  "force should copy the updated vendored sources")) );
    ( "vendors a git source with a pinned commit checksum",
      fun () ->
        with_temp_dir "wadi-vendor-git-src" (fun source ->
            write_member_manifest source {|
[library.dep]
dir = "lib"
modules = ["dep"]
|};
            write_source source "lib/dep.ml" {|let message = "git-vendored"|};
            let revision = init_git_repo source in
            with_temp_dir "wadi-vendor-git-workspace" (fun workspace ->
                write_manifest workspace
                  {|
workspace = "demo"
version = 1

[executable.demo]
dir = "app"
main = "main"
deps = ["dep"]
|};
                write_source workspace "app/main.ml"
                  {|let () = print_endline Dep.message|};
                let vendor =
                  run_wadi ~cwd:workspace
                    [ "vendor"; "--git"; source; "--checksum"; revision; "--name"; "dep" ]
                in
                assert_int_equal 0 vendor.status "vendor should clone a pinned git source";
                let run = run_wadi ~cwd:workspace [ "run"; "demo" ] in
                assert_int_equal 0 run.status
                  "git-vendored packages should participate in normal builds";
                assert_string_contains ~needle:"git-vendored\n" run.output
                  "the root workspace should resolve the git-vendored library")) );
    ( "vendors a source archive URL with a pinned checksum",
      fun () ->
        with_temp_dir "wadi-vendor-url-parent" (fun parent ->
            let source = Filename.concat parent "dep-src" in
            Unix.mkdir source 0o755;
            write_member_manifest source {|
[library.dep]
dir = "lib"
modules = ["dep"]
|};
            write_source source "lib/dep.ml" {|let message = "url-vendored"|};
            let archive_path = Filename.concat parent "dep-src.tar.gz" in
            let archive =
              Process.run_capture "tar" [ "-czf"; archive_path; "-C"; parent; "dep-src" ]
            in
            assert_int_equal 0 archive.status
              "tar should create a vendored source archive";
            let checksum = sha256 archive_path in
            with_temp_dir "wadi-vendor-url-workspace" (fun workspace ->
                write_manifest workspace
                  {|
workspace = "demo"
version = 1

[executable.demo]
dir = "app"
main = "main"
deps = ["dep"]
|};
                write_source workspace "app/main.ml"
                  {|let () = print_endline Dep.message|};
                let vendor =
                  run_wadi ~cwd:workspace
                    [
                      "vendor";
                      "--url";
                      "file://" ^ archive_path;
                      "--checksum";
                      "sha256:" ^ checksum;
                      "--name";
                      "dep";
                    ]
                in
                assert_int_equal 0 vendor.status
                  "vendor should fetch a pinned source archive";
                let run = run_wadi ~cwd:workspace [ "run"; "demo" ] in
                assert_int_equal 0 run.status
                  "archive-vendored packages should participate in normal builds";
                assert_string_contains ~needle:"url-vendored\n" run.output
                  "the root workspace should resolve the archive-vendored library")) );
    ( "rejects git vendoring when the pinned checksum does not match",
      fun () ->
        with_temp_dir "wadi-vendor-git-mismatch-src" (fun source ->
            write_member_manifest source {|
[library.dep]
dir = "lib"
modules = ["dep"]
|};
            write_source source "lib/dep.ml" {|let message = "bad"|};
            ignore (init_git_repo source);
            with_temp_dir "wadi-vendor-git-mismatch-workspace" (fun workspace ->
                write_manifest workspace {|
workspace = "demo"
version = 1
|};
                let vendor =
                  run_wadi ~cwd:workspace
                    [
                      "vendor"; "--git"; source; "--checksum"; "deadbeef"; "--name"; "dep";
                    ]
                in
                assert_true (vendor.status <> 0)
                  "vendor should reject mismatched git checksum pins";
                assert_string_contains ~needle:"git source checksum mismatch"
                  vendor.output "vendor should explain the checksum mismatch directly"))
    );
  ]
