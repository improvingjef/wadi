open Test_support

let executable_path workspace name =
  Filename.concat workspace ("_oasis/build/default/exe/" ^ name ^ "/" ^ name)

let library_archive_path workspace name =
  Filename.concat workspace
    ("_oasis/build/default/lib/" ^ name ^ "/lib" ^ name ^ ".cmxa")

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let write_executable workspace relative_path contents =
  let path = Filename.concat workspace relative_path in
  Fs.write_file path contents;
  Unix.chmod path 0o755;
  path

let resolve_command prog =
  let outcome = Process.run_capture "/bin/sh" [ "-c"; "command -v " ^ prog ] in
  assert_int_equal 0 outcome.status
    (Printf.sprintf "expected to find %s on PATH" prog);
  String.trim outcome.output

let write_wrapper workspace relative_path label log_path command_path =
  write_executable workspace relative_path
    (Printf.sprintf "#!/bin/sh\nprintf '%s\\n' >> %s\nexec %s \"$@\"\n" label
       (Filename.quote log_path) (Filename.quote command_path))

let cases =
  [
    ( "builds and runs the hello fixture",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status "hello fixture should build cleanly";
            assert_string_contains ~needle:"Built library greeting" build.output
              "library build output should be reported";
            let executable = executable_path workspace "hello" in
            assert_file_exists executable;
            let run = run_binary executable [] in
            assert_int_equal 0 run.status
              "built hello executable should run successfully";
            assert_string_equal "Hello, world!\n" run.output
              "built hello executable should print the greeting")) );
    ( "links transitive library dependencies",
      (fun () ->
        with_fixture "transitive" (fun workspace ->
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "transitive fixture should build cleanly";
            let executable = executable_path workspace "demo" in
            assert_file_exists executable;
            let run = run_binary executable [] in
            assert_int_equal 0 run.status
              "transitive executable should run successfully";
            assert_string_equal "Hello, transitive world!\n" run.output
              "transitive libraries should be linked in executable output")) );
    ( "builds a requested library without unrelated executables",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_oasis ~cwd:workspace [ "build"; "greeting" ] in
            assert_int_equal 0 build.status
              "selective library builds should succeed";
            assert_file_exists (library_archive_path workspace "greeting");
            assert_true
              (not (Fs.exists (executable_path workspace "hello")))
              "building a library target should not build unrelated executables")))
    ;
    ( "reports missing source files",
      (fun () ->
        with_temp_dir "oasis-missing" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_true (build.status <> 0)
              "missing source files should fail the build";
            assert_string_contains ~needle:"missing source file" build.output
              "missing source files should produce a direct error")) );
    ( "infers library module order from source dependencies",
      (fun () ->
        with_temp_dir "oasis-module-order" (fun workspace ->
            write_manifest workspace
              {|
[library.demo]
dir = "lib"
modules = ["consumer", "provider"]

[executable.app]
dir = "app"
main = "main"
deps = ["demo"]
|};
            write_source workspace "lib/provider.mli"
              {|
type t = string
val value : t
|};
            write_source workspace "lib/provider.ml"
              {|
type t = string
let value = "ordered"
|};
            write_source workspace "lib/consumer.ml"
              {|let render (value : Provider.t) = value|};
            write_source workspace "app/main.ml"
              {|let () = print_endline (Consumer.render Provider.value)|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "dependency-driven module sorting should allow declarative manifests";
            let run = run_binary (executable_path workspace "app") [] in
            assert_int_equal 0 run.status
              "ordered fixture executable should run successfully";
            assert_string_equal "ordered\n" run.output
              "inferred module order should produce a working executable")) );
    ( "reuses artifacts when inputs are unchanged",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let first_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 first_build.status
              "initial build should succeed before up-to-date checks";
            let second_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 second_build.status
              "rebuilding unchanged sources should still succeed";
            assert_string_contains ~needle:"Up to date library greeting"
              second_build.output
              "unchanged libraries should be reported as up to date";
            assert_string_contains ~needle:"Up to date executable hello"
              second_build.output
              "unchanged executables should be reported as up to date";
            assert_string_not_contains ~needle:"Built library greeting"
              second_build.output
              "unchanged libraries should not be recompiled";
            assert_string_not_contains ~needle:"Built executable hello"
              second_build.output
              "unchanged executables should not be relinked")) );
    ( "rebuilds changed targets and downstream dependents",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let first_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 first_build.status
              "initial build should succeed before incremental invalidation";
            write_source workspace "lib/greeting.ml"
              {|let message name = "Hello again, " ^ name ^ "!"|};
            let second_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 second_build.status
              "rebuild after a source edit should succeed";
            assert_string_contains ~needle:"Built library greeting"
              second_build.output
              "edited libraries should be rebuilt";
            assert_string_contains ~needle:"Built executable hello"
              second_build.output
              "dependents of edited libraries should be rebuilt";
            let run = run_binary (executable_path workspace "hello") [] in
            assert_int_equal 0 run.status
              "rebuilt executable should still run";
            assert_string_equal "Hello again, world!\n" run.output
              "rebuilt executable should reflect the updated library output")) );
    ( "builds against external packages and propagates them through dependencies",
      (fun () ->
        with_temp_dir "oasis-packages" (fun workspace ->
            write_manifest workspace
              {|
[library.patterns]
dir = "lib"
modules = ["patterns"]
packages = ["str"]

[executable.demo]
dir = "app"
main = "main"
deps = ["patterns"]
|};
            write_source workspace "lib/patterns.ml"
              {|
let contains_digit text =
  Str.string_match (Str.regexp ".*[0-9].*") text 0
|};
            write_source workspace "app/main.ml"
              {|
let () =
  print_endline (string_of_bool (Patterns.contains_digit "abc123"))
|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "external package builds should succeed";
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "package-backed executable should run successfully";
            assert_string_equal "true\n" run.output
              "package-backed executable should link transitive external packages")) );
    ( "reports unknown external packages directly",
      (fun () ->
        with_temp_dir "oasis-package-missing" (fun workspace ->
            write_manifest workspace
              {|
[library.patterns]
dir = "lib"
modules = ["patterns"]
packages = ["missing_pkg_demo"]
|};
            write_source workspace "lib/patterns.ml" {|let value = 1|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_true (build.status <> 0)
              "unknown packages should fail the build";
            assert_string_contains
              ~needle:"package 'missing_pkg_demo' is not available via ocamlfind"
              build.output
              "unknown packages should produce a direct resolver error")) );
    ( "orders modules from interface dependencies",
      (fun () ->
        with_temp_dir "oasis-interface-order" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["alpha", "beta"]

[executable.app]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "lib/alpha.mli" {|val value : Beta.t|};
            write_source workspace "lib/alpha.ml" {|let value = Beta.value|};
            write_source workspace "lib/beta.ml"
              {|
type t = string
let value = "interfaces count"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline Alpha.value|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "interface dependencies should participate in inferred module order";
            let run = run_binary (executable_path workspace "app") [] in
            assert_int_equal 0 run.status
              "interface-ordered executable should run successfully";
            assert_string_equal "interfaces count\n" run.output
              "interface-driven ordering should produce the expected output")) );
    ( "reports module dependency cycles with target context",
      (fun () ->
        with_temp_dir "oasis-module-cycle" (fun workspace ->
            write_manifest workspace
              {|
[library.cycle]
dir = "lib"
modules = ["alpha", "beta"]
|};
            write_source workspace "lib/alpha.ml" {|let value = Beta.value|};
            write_source workspace "lib/beta.ml" {|let value = Alpha.value|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_true (build.status <> 0)
              "cyclic modules should fail before compilation";
            assert_string_contains
              ~needle:"library 'cycle' failed module dependency inference"
              build.output
              "cycle failures should identify the target being ordered";
            assert_string_contains ~needle:"cycle in dependencies" build.output
              "cycle failures should preserve the dependency-scanner error")) );
    ( "honors toolchain command overrides during build",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let log_path = Filename.concat workspace "toolchain.log" in
            let ocamlopt_wrapper =
              write_wrapper workspace "bin/ocamlopt-wrapper" "ocamlopt"
                log_path (resolve_command "ocamlopt")
            in
            let ocamldep_wrapper =
              write_wrapper workspace "bin/ocamldep-wrapper" "ocamldep"
                log_path (resolve_command "ocamldep")
            in
            let build =
              with_env "OCAMLOPT" ocamlopt_wrapper (fun () ->
                  with_env "OCAMLDEP" ocamldep_wrapper (fun () ->
                      run_oasis ~cwd:workspace [ "build" ]))
            in
            assert_int_equal 0 build.status
              "build should succeed when compiler commands are overridden";
            let log = Fs.read_file log_path in
            assert_string_contains ~needle:"ocamlopt\n" log
              "build should invoke the overridden native compiler";
            assert_string_contains ~needle:"ocamldep\n" log
              "build should invoke the overridden dependency scanner")) );
    ( "resolves unix from a stdlib subdirectory",
      (fun () ->
        with_temp_dir "oasis-unix-subdir" (fun workspace ->
            let stdlib_dir = Filename.concat workspace "lib/ocaml" in
            let unix_dir = Filename.concat stdlib_dir "unix" in
            Fs.ensure_dir unix_dir;
            Fs.write_file (Filename.concat unix_dir "unix.cmi") "";
            match
              Toolchain.resolve_library_dir ~exists:Fs.exists ~stdlib_dir "unix"
            with
            | Some resolved ->
                assert_string_equal unix_dir resolved
                  "unix lookup should prefer the library subdirectory layout"
            | None -> fail "expected unix library resolution to succeed")) );
    ( "resolves unix from the stdlib root when needed",
      (fun () ->
        with_temp_dir "oasis-unix-root" (fun workspace ->
            let stdlib_dir = Filename.concat workspace "lib/ocaml" in
            Fs.ensure_dir stdlib_dir;
            Fs.write_file (Filename.concat stdlib_dir "unix.cmi") "";
            match
              Toolchain.resolve_library_dir ~exists:Fs.exists ~stdlib_dir "unix"
            with
            | Some resolved ->
                assert_string_equal stdlib_dir resolved
                  "unix lookup should fall back to the stdlib root layout"
            | None -> fail "expected unix library resolution to succeed")) );
  ]
