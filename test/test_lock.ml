open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let lock_path workspace = Filename.concat workspace "oasis.lock"

let cases =
  [
    ( "writes a lock file with toolchain facts and package resolutions",
      fun () ->
        with_temp_dir "oasis-lock" (fun workspace ->
            write_manifest workspace
              {|
workspace = "demo"
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
            write_source workspace "lib/core.ml" {|let message = "locked"|};
            write_source workspace "app/main.ml" {|let () = print_endline Core.message|};
            let lock = run_oasis ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should write the default lock file";
            assert_string_contains ~needle:"Wrote lock file" lock.output
              "lock should report where it wrote the snapshot";
            assert_file_exists (lock_path workspace);
            let contents = Fs.read_file (lock_path workspace) in
            assert_string_contains ~needle:{|"workspace":"demo"|} contents
              "lock files should record the workspace name";
            assert_string_contains ~needle:{|"path":"oasis.toml"|} contents
              "lock files should record the root manifest path";
            assert_string_contains ~needle:{|"name":"demo"|} contents
              "lock files should record resolved targets";
            assert_string_contains ~needle:{|"external_packages":["unix"]|}
              contents
              "lock files should record external package closure";
            assert_string_contains ~needle:{|"selected_backend":{"ok":"|}
              contents
              "lock files should record the resolved backend") );
    ( "prints lock JSON to stdout without writing the default file",
      fun () ->
        with_fixture "hello" (fun workspace ->
            let lock = run_oasis ~cwd:workspace [ "lock"; "--stdout"; "hello" ] in
            assert_int_equal 0 lock.status
              "lock --stdout should emit JSON directly";
            assert_true (not (Fs.exists (lock_path workspace)))
              "lock --stdout should not create the default lock file";
            assert_string_contains ~needle:{|"requested_targets":["hello"]|}
              lock.output "stdout output should preserve the requested target list";
            assert_string_contains ~needle:{|"resolved_targets":["hello"]|}
              lock.output "stdout output should preserve the resolved target list") );
    ( "writes selected targets to a custom lock path",
      fun () ->
        with_temp_dir "oasis-lock-output" (fun workspace ->
            write_manifest workspace
              {|
workspace = "demo"
version = 1

[library.core]
dir = "lib"
modules = ["core"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]

[test.unit]
dir = "test"
main = "unit"
|};
            write_source workspace "lib/core.ml" {|let message = "core"|};
            write_source workspace "app/main.ml" {|let () = print_endline Core.message|};
            write_source workspace "test/unit.ml" {|let () = ()|};
            let output_path = Filename.concat workspace "custom.lock" in
            let lock =
              run_oasis ~cwd:workspace
                [ "lock"; "--output"; output_path; "demo" ]
            in
            assert_int_equal 0 lock.status
              "lock should support custom output paths";
            assert_file_exists output_path;
            let contents = Fs.read_file output_path in
            assert_string_contains ~needle:{|"resolved_targets":["demo"]|}
              contents "custom lock files should preserve the selected targets";
            assert_string_not_contains ~needle:{|"name":"unit"|} contents
              "custom lock files should omit unrelated targets") );
  ]
