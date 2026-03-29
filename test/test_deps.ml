open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let cases =
  [
    ( "reports transitive external packages for selected targets",
      (fun () ->
        with_temp_dir "oasis-deps-transitive" (fun workspace ->
            write_manifest workspace
              {|
workspace = "deps-demo"
version = 1

[library.core]
dir = "lib"
modules = ["core"]
packages = ["unix"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "lib/core.ml" {|let pid = Unix.getpid ()|};
            write_source workspace "app/main.ml" {|let () = print_int Core.pid|};
            let deps = run_oasis ~cwd:workspace [ "deps"; "demo" ] in
            assert_int_equal 0 deps.status
              "deps should resolve transitive external packages";
            assert_string_contains ~needle:"Workspace: deps-demo\n" deps.output
              "deps should report the workspace name";
            assert_string_contains ~needle:"Target: demo\n" deps.output
              "deps should report the selected target";
            assert_string_contains ~needle:"Workspace-deps: core\n" deps.output
              "deps should show direct workspace dependencies";
            assert_string_contains ~needle:"External-packages: unix\n" deps.output
              "deps should include transitive external packages";
            assert_string_contains ~needle:"Resolved-packages:\n- unix -> "
              deps.output
              "deps should show resolved ocamlfind paths")) );
    ( "reports missing external packages with target context",
      (fun () ->
        with_temp_dir "oasis-deps-missing" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
packages = ["definitely_missing_oasis_pkg"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "lib/core.ml" {|let value = "core"|};
            write_source workspace "app/main.ml" {|let () = print_endline Core.value|};
            let deps = run_oasis ~cwd:workspace [ "deps"; "demo" ] in
            assert_true (deps.status <> 0)
              "deps should fail when a required package is unavailable";
            assert_string_contains
              ~needle:"executable 'demo' requires package 'definitely_missing_oasis_pkg' is not available via ocamlfind"
              deps.output
              "deps should name the failing target and package")) );
  ]

