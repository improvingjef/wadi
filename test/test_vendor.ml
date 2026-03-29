open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let write_member_manifest workspace contents =
  Fs.write_file (Filename.concat workspace "oasis.toml") contents

let cases =
  [
    ( "vendors a local package into vendor/ and registers it as a member",
      fun () ->
        with_temp_dir "oasis-vendor-src" (fun source ->
            write_member_manifest source
              {|
[library.dep]
dir = "lib"
modules = ["dep"]
|};
            write_source source "lib/dep.ml" {|let message = "vendored"|};
            with_temp_dir "oasis-vendor-workspace" (fun workspace ->
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
                  run_oasis ~cwd:workspace
                    [ "vendor"; "--source"; source; "--name"; "dep" ]
                in
                assert_int_equal 0 vendor.status
                  "vendor should copy and register a local package";
                assert_file_exists (Filename.concat workspace "vendor/dep/oasis.toml");
                assert_string_contains ~needle:{|members = ["vendor/dep"]|}
                  (Fs.read_file (manifest_path workspace))
                  "vendor should register the new member in the root manifest";
                let run = run_oasis ~cwd:workspace [ "run"; "demo" ] in
                assert_int_equal 0 run.status
                  "the vendored package should participate in normal builds";
                assert_string_contains ~needle:"vendored\n" run.output
                  "the root workspace should resolve the vendored library")) );
    ( "rejects vendored manifests that are not member-compatible",
      fun () ->
        with_temp_dir "oasis-vendor-invalid" (fun source ->
            write_member_manifest source
              {|
workspace = "dep"
version = 1

[library.dep]
dir = "lib"
modules = ["dep"]
|};
            write_source source "lib/dep.ml" {|let message = "bad"|};
            with_temp_dir "oasis-vendor-root" (fun workspace ->
                write_manifest workspace
                  {|
workspace = "demo"
version = 1
|};
                let vendor =
                  run_oasis ~cwd:workspace
                    [ "vendor"; "--source"; source; "--name"; "dep" ]
                in
                assert_true (vendor.status <> 0)
                  "vendor should reject non-member-safe manifests";
                assert_string_contains
                  ~needle:"defines a top-level workspace name"
                  vendor.output
                  "vendor should explain the member-safety violation")) );
    ( "replaces an existing vendored checkout with force",
      fun () ->
        with_temp_dir "oasis-vendor-force-src" (fun source ->
            write_member_manifest source
              {|
[library.dep]
dir = "lib"
modules = ["dep"]
|};
            write_source source "lib/dep.ml" {|let message = "first"|};
            with_temp_dir "oasis-vendor-force-workspace" (fun workspace ->
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
                  run_oasis ~cwd:workspace
                    [ "vendor"; "--source"; source; "--name"; "dep" ]
                in
                assert_int_equal 0 first.status
                  "the first vendor command should succeed";
                write_source source "lib/dep.ml" {|let message = "second"|};
                let rejected =
                  run_oasis ~cwd:workspace
                    [ "vendor"; "--source"; source; "--name"; "dep" ]
                in
                assert_true (rejected.status <> 0)
                  "vendor should refuse to replace an existing checkout without force";
                assert_string_contains ~needle:"rerun with --force"
                  rejected.output
                  "vendor should explain how to replace an existing checkout";
                let forced =
                  run_oasis ~cwd:workspace
                    [ "vendor"; "--source"; source; "--name"; "dep"; "--force" ]
                in
                assert_int_equal 0 forced.status
                  "vendor --force should refresh an existing checkout";
                let run = run_oasis ~cwd:workspace [ "run"; "demo" ] in
                assert_int_equal 0 run.status
                  "the refreshed vendored package should still build";
                assert_string_contains ~needle:"second\n" run.output
                  "force should copy the updated vendored sources")) );
  ]
