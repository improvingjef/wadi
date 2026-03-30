open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let lock_path workspace = Filename.concat workspace "wadi.lock"

let replace_once ~needle ~replacement text =
  let needle_length = String.length needle in
  let text_length = String.length text in
  let rec find index =
    if index + needle_length > text_length then None
    else if String.sub text index needle_length = needle then Some index
    else find (index + 1)
  in
  match find 0 with
  | Some index ->
      String.sub text 0 index ^ replacement
      ^ String.sub text (index + needle_length) (text_length - index - needle_length)
  | None -> fail ("missing substring to replace: " ^ needle)

let resolve_package_path package_name =
  let outcome = Process.run_capture "ocamlfind" [ "query"; package_name ] in
  assert_int_equal 0 outcome.status ("expected ocamlfind query to resolve " ^ package_name);
  String.trim outcome.output

let resolve_compiler_version () =
  let outcome = Process.run_capture "ocamlc" [ "-version" ] in
  assert_int_equal 0 outcome.status "expected ocamlc -version to succeed";
  String.trim outcome.output

let resolve_package_roots () =
  let outcome = Process.run_capture "ocamlfind" [ "printconf"; "path" ] in
  assert_int_equal 0 outcome.status "expected ocamlfind printconf path to succeed";
  String_util.split_lines outcome.output

let cases =
  [
    ( "writes a lock file with toolchain facts and package resolutions",
      fun () ->
        with_temp_dir "wadi-lock" (fun workspace ->
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
            let lock = run_wadi ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status "lock should write the default lock file";
            assert_string_contains ~needle:"Wrote lock file" lock.output
              "lock should report where it wrote the snapshot";
            assert_file_exists (lock_path workspace);
            let contents = Fs.read_file (lock_path workspace) in
            assert_string_contains ~needle:{|"workspace":"demo"|} contents
              "lock files should record the workspace name";
            assert_string_contains ~needle:{|"path":"wadi.toml"|} contents
              "lock files should record the root manifest path";
            assert_string_contains ~needle:{|"name":"demo"|} contents
              "lock files should record resolved targets";
            assert_string_contains ~needle:{|"external_packages":["unix"]|} contents
              "lock files should record external package closure";
            assert_string_contains ~needle:{|"selected_backend":{"ok":"|} contents
              "lock files should record the resolved backend") );
    ( "prints lock JSON to stdout without writing the default file",
      fun () ->
        with_fixture "hello" (fun workspace ->
            let lock = run_wadi ~cwd:workspace [ "lock"; "--stdout"; "hello" ] in
            assert_int_equal 0 lock.status "lock --stdout should emit JSON directly";
            assert_true
              (not (Fs.exists (lock_path workspace)))
              "lock --stdout should not create the default lock file";
            assert_string_contains ~needle:{|"requested_targets":["hello"]|} lock.output
              "stdout output should preserve the requested target list";
            assert_string_contains ~needle:{|"resolved_targets":["hello"]|} lock.output
              "stdout output should preserve the resolved target list") );
    ( "writes selected targets to a custom lock path",
      fun () ->
        with_temp_dir "wadi-lock-output" (fun workspace ->
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
              run_wadi ~cwd:workspace [ "lock"; "--output"; output_path; "demo" ]
            in
            assert_int_equal 0 lock.status "lock should support custom output paths";
            assert_file_exists output_path;
            let contents = Fs.read_file output_path in
            assert_string_contains ~needle:{|"resolved_targets":["demo"]|} contents
              "custom lock files should preserve the selected targets";
            assert_string_not_contains ~needle:{|"name":"unit"|} contents
              "custom lock files should omit unrelated targets") );
    ( "build --locked accepts a matching lock snapshot",
      fun () ->
        with_temp_dir "wadi-lock-build" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
packages = ["unix"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "lib/core.ml"
              {|let message = Unix.getcwd () |> Filename.basename|};
            write_source workspace "app/main.ml" {|let () = print_endline Core.message|};
            let lock = run_wadi ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should succeed before strict validation is exercised";
            let build = run_wadi ~cwd:workspace [ "build"; "--locked"; "demo" ] in
            assert_int_equal 0 build.status
              "build --locked should succeed when wadi.lock matches";
            assert_string_contains ~needle:"Built executable demo" build.output
              "build --locked should still perform the build") );
    ( "build --locked fails when package paths drift from the lock snapshot",
      fun () ->
        with_temp_dir "wadi-lock-drift" (fun workspace ->
            write_manifest workspace
              {|
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
            let lock = run_wadi ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should succeed before drift is introduced";
            let unix_path = resolve_package_path "unix" in
            let package_entry = Printf.sprintf {|"name":"unix","path":"%s"|} unix_path in
            let drifted =
              replace_once ~needle:package_entry
                ~replacement:{|"name":"unix","path":"/tmp/drifted-unix"|}
                (Fs.read_file (lock_path workspace))
            in
            Fs.write_file (lock_path workspace) drifted;
            let build = run_wadi ~cwd:workspace [ "build"; "--locked"; "demo" ] in
            assert_true (build.status <> 0)
              "build --locked should fail when a locked package path changes";
            assert_string_contains ~needle:"package 'unix' path drifted" build.output
              "strict lock validation should explain which package drifted";
            assert_string_contains ~needle:"Refresh the snapshot with `wadi lock`."
              build.output
              "strict lock validation should explain how to refresh the snapshot") );
    ( "build --locked fails when recorded toolchain facts drift from the lock snapshot",
      fun () ->
        with_temp_dir "wadi-lock-toolchain-drift" (fun workspace ->
            write_manifest workspace
              {|
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
            let lock = run_wadi ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should succeed before toolchain drift is introduced";
            let compiler_version = resolve_compiler_version () in
            let compiler_entry =
              Printf.sprintf {|"compiler_version":{"ok":"%s"}|} compiler_version
            in
            let drifted =
              replace_once ~needle:compiler_entry
                ~replacement:{|"compiler_version":{"ok":"0.0.0-drifted"}|}
                (Fs.read_file (lock_path workspace))
            in
            Fs.write_file (lock_path workspace) drifted;
            let build = run_wadi ~cwd:workspace [ "build"; "--locked"; "demo" ] in
            assert_true (build.status <> 0)
              "build --locked should fail when locked toolchain facts change";
            assert_string_contains ~needle:"toolchain compiler version drifted"
              build.output "strict lock validation should report toolchain drift directly";
            assert_string_contains ~needle:"Refresh the snapshot with `wadi lock`."
              build.output
              "strict lock validation should explain how to refresh toolchain drift") );
    ( "build --locked fails when package search roots drift from the lock snapshot",
      fun () ->
        with_temp_dir "wadi-lock-package-root-drift" (fun workspace ->
            write_manifest workspace
              {|
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
            let lock = run_wadi ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should succeed before package-root drift is introduced";
            let package_roots = resolve_package_roots () in
            let first_root =
              match package_roots with
              | root :: _ -> root
              | [] -> fail "expected ocamlfind printconf path to report at least one root"
            in
            let roots_prefix =
              Printf.sprintf {|"package_roots":{"ok":["%s"|} first_root
            in
            let drifted =
              replace_once ~needle:roots_prefix
                ~replacement:{|"package_roots":{"ok":["/tmp/drifted-package-root"|}
                (Fs.read_file (lock_path workspace))
            in
            Fs.write_file (lock_path workspace) drifted;
            let build = run_wadi ~cwd:workspace [ "build"; "--locked"; "demo" ] in
            assert_true (build.status <> 0)
              "build --locked should fail when locked package roots change";
            assert_string_contains ~needle:"toolchain package search roots drifted"
              build.output "strict lock validation should surface package-root drift") );
    ( "install --warn-locked reports drift but still stages artifacts",
      fun () ->
        with_fixture "hello" (fun workspace ->
            let lock = run_wadi ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should succeed before warning-mode validation is exercised";
            let drifted =
              replace_once ~needle:{|"path":"wadi.toml"|}
                ~replacement:{|"path":"stale.toml"|}
                (Fs.read_file (lock_path workspace))
            in
            Fs.write_file (lock_path workspace) drifted;
            let prefix = Filename.concat workspace "_warn-stage" in
            let install =
              run_wadi ~cwd:workspace
                [ "install"; "--warn-locked"; "--prefix"; prefix; "hello" ]
            in
            assert_int_equal 0 install.status
              "install --warn-locked should continue when the snapshot is stale";
            assert_string_contains ~needle:"warning: lock validation failed against"
              install.output "warning mode should surface the lock drift";
            assert_file_exists (Filename.concat prefix "bin/hello")) );
  ]
