open Test_support

let executable_path workspace name =
  Layout.executable_binary workspace name

let profile_executable_path workspace profile name =
  Layout.executable_binary ~profile workspace name

let library_archive_path workspace name =
  Layout.library_archive workspace name

let bytecode_library_archive_path workspace name =
  Layout.library_archive_for_backend workspace Toolchain.Bytecode name

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

let write_logging_wrapper workspace relative_path log_path command_path =
  write_executable workspace relative_path
    (Printf.sprintf
       "#!/bin/sh\nprintf 'BUILD_PROFILE=%%s\\n' \"${BUILD_PROFILE-}\" >> %s\nprintf \
        'ARGS=%%s\\n' \"$*\" >> %s\nexec %s \"$@\"\n"
       (Filename.quote log_path) (Filename.quote log_path)
       (Filename.quote command_path))

let compile_ppx workspace relative_path contents output_relative_path =
  let source_path = Filename.concat workspace relative_path in
  Fs.write_file source_path contents;
  let output_path = Filename.concat workspace output_relative_path in
  let outcome =
    Process.run_capture "ocamlfind"
      [
        "ocamlopt";
        "-package";
        "compiler-libs.common";
        "-linkpkg";
        "-o";
        output_path;
        source_path;
      ]
  in
  assert_int_equal 0 outcome.status
    "expected the helper ppx binary to compile successfully";
  output_path

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
    ( "builds a multi-package workspace with shared dependency analysis",
      (fun () ->
        with_temp_dir "oasis-multi-package" (fun workspace ->
            write_manifest workspace
              {|
workspace = "demo"
version = 1
members = ["packages/core", "packages/app"]

[library.shared]
dir = "shared"
modules = ["shared"]
|};
            write_workspace_file workspace "packages/core/oasis.toml"
              {|
[library.core]
dir = "lib"
modules = ["core"]
deps = ["shared"]
|};
            write_workspace_file workspace "packages/app/oasis.toml"
              {|
[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "shared/shared.ml" {|let prefix = "multi"|};
            write_source workspace "packages/core/lib/core.ml"
              {|let message () = Shared.prefix ^ "-package"|};
            write_source workspace "packages/app/app/main.ml"
              {|let () = print_endline (Core.message ())|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "multi-package workspaces should build from the root manifest";
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "executables spanning member packages should run successfully";
            assert_string_equal "multi-package\n" run.output
              "cross-member dependency analysis should produce a working executable")) );
    ( "uses package-local member actions, preprocessors, and ppx without leaking root tools",
      (fun () ->
        with_temp_dir "oasis-member-local-tools" (fun workspace ->
            write_manifest workspace
              {|
workspace = "demo"
version = 1
members = ["packages/core", "packages/app"]

[action.generate_version]
argv = ["./root-tools/generate.sh"]
outputs = ["version.ml"]

[preprocess.expand]
argv = ["./root-tools/expand.sh"]

[ppx.rewrite]
argv = ["./root-tools/rewrite.exe"]
|};
            write_workspace_file workspace "packages/core/oasis.toml"
              {|
[action.generate_version]
argv = ["./scripts/generate.sh"]
cwd = "."
deps = ["templates/version.txt"]
outputs = ["version.ml"]

[preprocess.expand]
argv = ["./scripts/expand.sh"]
cwd = "scripts"
deps = ["templates/banner.txt"]

[ppx.rewrite]
argv = ["./ppx/rewrite.exe"]
deps = ["ppx/config.txt"]

[library.core]
dir = "lib"
modules = ["core", "version"]
actions = ["generate_version"]
preprocess = ["expand"]
ppx = ["rewrite"]
|};
            write_workspace_file workspace "packages/app/oasis.toml"
              {|
[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "packages/core/templates/version.txt"
              "member-action\n";
            ignore
              (write_executable workspace "packages/core/scripts/generate.sh"
                 "#!/bin/sh\nset -eu\nversion=$(cat templates/version.txt)\nprintf 'let value = \"%s\"\\n' \"$version\" > lib/version.ml\n");
            write_source workspace "packages/core/templates/banner.txt"
              "member-pre";
            ignore
              (write_executable workspace "packages/core/scripts/expand.sh"
                 "#!/bin/sh\nset -eu\nbanner=$(cat ../templates/banner.txt)\nsed \"s/@@PREFIX@@/${banner}/g\"\n");
            write_source workspace "packages/core/ppx/config.txt" "member-ppx\n";
            let _ppx_binary =
              compile_ppx workspace "packages/core/ppx/rewrite.ml"
                {|
open Ast_helper
open Ast_mapper
open Parsetree

let expr mapper expression =
  match expression.pexp_desc with
  | Pexp_constant
      { pconst_desc = Pconst_string ("ppx-marker", _, delimiter); pconst_loc = loc } ->
      Exp.constant
        {
          pconst_desc = Pconst_string ("member-ppx", loc, delimiter);
          pconst_loc = loc;
        }
  | _ -> default_mapper.expr mapper expression

let () =
  run_main (fun _argv -> { default_mapper with expr })
|}
                "packages/core/ppx/rewrite.exe"
            in
            write_source workspace "packages/core/lib/core.ml"
              {|let message = "@@PREFIX@@" ^ ":" ^ Version.value ^ ":" ^ "ppx-marker"|};
            write_source workspace "packages/app/app/main.ml"
              {|let () = print_endline Core.message|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "member-local tools should build successfully without centralizing them in the root manifest";
            assert_string_contains ~needle:"Built library core (packages/core)"
              build.output
              "build output should surface the member package path for libraries";
            assert_string_contains ~needle:"Built executable demo (packages/app)"
              build.output
              "build output should surface the member package path for executables";
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "member-local tool builds should produce a runnable executable";
            assert_string_equal "member-pre:member-action:member-ppx\n" run.output
              "member-local actions, preprocessors, and ppx tools should apply within their package scope")) );
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
    ( "builds wrapped libraries with a generated namespace module",
      (fun () ->
        with_temp_dir "oasis-wrapped-library" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
wrapped = true
dir = "lib"
modules = ["greeting"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "lib/greeting.ml" {|let message = "wrapped"|};
            write_source workspace "app/main.ml"
              {|let () = print_endline Core.Greeting.message|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "wrapped libraries should build successfully";
            assert_file_exists
              (Filename.concat (Layout.library_out_dir workspace "core") "core.cmi");
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "executables should compile against the generated wrapper module";
            assert_string_equal "wrapped\n" run.output
              "wrapped libraries should expose child modules through the namespace wrapper")) );
    ( "builds wrapped libraries with a checked-in wrapper module and removes stale generated wrappers",
      (fun () ->
        with_temp_dir "oasis-wrapped-custom-wrapper" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
wrapped = true
dir = "lib"
modules = ["greeting"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "lib/greeting.ml" {|let message = "wrapped"|};
            write_source workspace "app/main.ml"
              {|let () = print_endline Core.Greeting.message|};
            let first_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 first_build.status
              "wrapped libraries should build before switching to a checked-in wrapper";
            let generated_wrapper =
              Filename.concat (Layout.library_out_dir workspace "core")
                "generated/core.ml"
            in
            assert_file_exists generated_wrapper;
            write_source workspace "lib/core.ml"
              {|
module Greeting = Greeting
let message = Greeting.message ^ " via wrapper"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline Core.message|};
            let second_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 second_build.status
              "wrapped libraries should accept a checked-in wrapper module";
            assert_true (not (Fs.exists generated_wrapper))
              "a checked-in wrapper should replace the generated wrapper source instead of competing with stale materialized files";
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "executables should compile against the checked-in wrapper module";
            assert_string_equal "wrapped via wrapper\n" run.output
              "checked-in wrapper modules should define the wrapped library surface")) );
    ( "builds wrapped libraries with a checked-in wrapper interface",
      (fun () ->
        with_temp_dir "oasis-wrapped-wrapper-interface" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
wrapped = true
dir = "lib"
modules = ["greeting"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "lib/core.mli"
              {|
module Greeting : sig
  val message : string
end
|};
            write_source workspace "lib/greeting.ml" {|let message = "interface"|};
            write_source workspace "app/main.ml"
              {|let () = print_endline Core.Greeting.message|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "wrapped libraries should support a checked-in wrapper interface";
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "executables should compile against the checked-in wrapper interface";
            assert_string_equal "interface\n" run.output
              "checked-in wrapper interfaces should constrain the generated wrapper implementation")) );
    ( "rejects wrapped libraries that reuse the reserved wrapper stem",
      (fun () ->
        with_temp_dir "oasis-wrapped-conflict" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
wrapped = true
dir = "lib"
modules = ["core"]
|};
            write_source workspace "lib/core.ml" {|let value = "conflict"|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_true (build.status <> 0)
              "wrapped libraries should reject module lists that collide with the generated wrapper";
            assert_string_contains
              ~needle:"reserved wrapper stem 'core'"
              build.output
              "wrapped-library collisions should explain the reserved stem")) );
    ( "prunes stale compiled outputs when a target's module list shrinks",
      (fun () ->
        with_temp_dir "oasis-prune-stale-modules" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core", "stale"]
|};
            write_source workspace "lib/core.ml" {|let value = "core"|};
            write_source workspace "lib/stale.ml" {|let value = "stale"|};
            let first_build = run_oasis ~cwd:workspace [ "build"; "core" ] in
            assert_int_equal 0 first_build.status
              "the initial build should succeed before stale-output pruning is exercised";
            let out_dir = Layout.library_out_dir workspace "core" in
            let stale_paths =
              List.map (Filename.concat out_dir)
                [ "stale.cmi"; "stale.cmo"; "stale.cmx"; "stale.o" ]
            in
            assert_true (List.exists Fs.exists stale_paths)
              "the initial build should leave compiled outputs for the removed module";
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
|};
            let second_build = run_oasis ~cwd:workspace [ "build"; "core" ] in
            assert_int_equal 0 second_build.status
              "rebuilding after the module list shrinks should still succeed";
            List.iter
              (fun path ->
                assert_true (not (Fs.exists path))
                  (Printf.sprintf
                     "stale compiled outputs should be removed after the target shape changes: %s"
                     path))
              stale_paths)) );
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
    ( "falls back to bytecode when ocamlopt is unavailable",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let log_path = Filename.concat workspace "toolchain.log" in
            let ocamlc_wrapper =
              write_wrapper workspace "bin/ocamlc-wrapper" "ocamlc" log_path
                (resolve_command "ocamlc")
            in
            let build =
              with_env "OCAMLOPT" "/definitely/missing/ocamlopt" (fun () ->
                  with_env "OCAMLC" ocamlc_wrapper (fun () ->
                      run_oasis ~cwd:workspace [ "build" ]))
            in
            assert_int_equal 0 build.status
              "build should fall back to bytecode when ocamlopt is unavailable";
            let log = Fs.read_file log_path in
            assert_string_contains ~needle:"ocamlc\n" log
              "bytecode fallback should invoke the bytecode compiler";
            assert_file_exists (bytecode_library_archive_path workspace "greeting");
            let run = run_binary (executable_path workspace "hello") [] in
            assert_int_equal 0 run.status
              "bytecode-built executables should still run successfully";
            assert_string_equal "Hello, world!\n" run.output
              "bytecode fallback should preserve executable behavior")) );
    ( "reports an unavailable native backend directly",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build =
              with_env "OCAMLOPT" "/definitely/missing/ocamlopt" (fun () ->
                  run_oasis ~cwd:workspace [ "build"; "--backend"; "native" ])
            in
            assert_true (build.status <> 0)
              "explicit native builds should fail when ocamlopt is unavailable";
            assert_string_contains
              ~needle:"native backend requested but /definitely/missing/ocamlopt is unavailable"
              build.output
              "backend selection failures should explain the missing compiler")) );
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
    ( "runs sandboxed actions to generate modules without leaking undeclared files",
      (fun () ->
        with_temp_dir "oasis-action-generate" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
actions = ["generate_version"]

[action.generate_version]
argv = ["./scripts/generate_version.sh"]
deps = ["scripts/template.txt"]
outputs = ["version.ml"]
stdin = "from-stdin"
sandbox = "target"

[executable.demo]
dir = "app"
main = "main"
modules = ["version"]
|};
            ignore
              (write_executable workspace "scripts/generate_version.sh"
                 "#!/bin/sh\nset -eu\ntemplate=$(cat ../scripts/template.txt)\nstdin_value=$(cat)\nprintf 'let message = \"%s %s\"\\n' \"$template\" \"$stdin_value\" > version.ml\nprintf 'should-not-leak\\n' > leak.txt\n");
            write_source workspace "scripts/template.txt" "from-template\n";
            write_source workspace "app/main.ml"
              {|let () = print_endline Version.message|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "sandboxed actions should run before source discovery";
            assert_true (not (Fs.exists (Filename.concat workspace "app/version.ml")))
              "generated modules should stay in the build root instead of the workspace";
            assert_true (not (Fs.exists (Filename.concat workspace "app/leak.txt")))
              "undeclared sandbox writes should not leak back into the workspace";
            assert_file_exists
              (Filename.concat (Layout.executable_out_dir workspace "demo")
                 "generated/version.ml");
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "generated-module executables should still run successfully";
            assert_string_equal "from-template from-stdin\n" run.output
              "generated modules should compile from declared action outputs")) );
    ( "runs workspace sandboxes from cloned materializations without leaking writes",
      (fun () ->
        with_temp_dir "oasis-action-workspace-sandbox" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
actions = ["snapshot"]

[action.snapshot]
argv = ["./scripts/snapshot.sh"]
deps = ["shared/message.txt"]
outputs = ["snapshot.ml"]
sandbox = "workspace"

[executable.demo]
dir = "app"
main = "main"
modules = ["snapshot"]
|};
            ignore
              (write_executable workspace "scripts/snapshot.sh"
                 "#!/bin/sh\nset -eu\nmessage=$(cat ../shared/message.txt)\nprintf 'let value = \"%s\"\\n' \"$message\" > snapshot.ml\nprintf 'should-not-leak\\n' > ../shared/extra.txt\n");
            write_source workspace "shared/message.txt" "workspace-sandbox";
            write_source workspace "app/main.ml"
              {|let () = print_endline Snapshot.value|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "workspace sandboxes should still build successfully";
            assert_true
              (not (Fs.exists (Filename.concat workspace "shared/extra.txt")))
              "workspace sandbox writes should stay isolated from the source tree";
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "workspace-sandbox executables should still run successfully";
            assert_string_equal "workspace-sandbox\n" run.output
              "workspace sandboxes should still expose declared workspace inputs")) );
    ( "regenerates missing action outputs without rebuilding unchanged targets",
      (fun () ->
        with_temp_dir "oasis-action-regenerate" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
actions = ["generate_version"]

[action.generate_version]
argv = ["./scripts/generate_version.sh"]
outputs = ["version.ml"]
sandbox = "target"

[executable.demo]
dir = "app"
main = "main"
modules = ["version"]
|};
            ignore
              (write_executable workspace "scripts/generate_version.sh"
                 "#!/bin/sh\nprintf 'let message = \"generated\"\\n' > version.ml\n");
            write_source workspace "app/main.ml"
              {|let () = print_endline Version.message|};
            let first_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 first_build.status
              "the initial action-backed build should succeed";
            let generated_version =
              Filename.concat (Layout.executable_out_dir workspace "demo")
                "generated/version.ml"
            in
            Fs.remove_tree generated_version;
            let second_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 second_build.status
              "rebuilding after deleting a generated source should still succeed";
            assert_file_exists generated_version;
            assert_string_contains
              ~needle:"Regenerated action outputs for executable demo"
              second_build.output
              "action-only repair should be reported distinctly from a full rebuild";
            assert_string_not_contains ~needle:"Built executable demo"
              second_build.output
              "action-only repair should not be reported as a rebuilt executable";
            assert_string_not_contains ~needle:"Up to date executable demo"
              second_build.output
              "action-only repair should not be reported as a perfect cache hit";
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "executables repaired through regenerated action outputs should still run";
            assert_string_equal "generated\n" run.output
              "action-only repair should preserve the executable behavior")) );
    ( "rejects generated source outputs that collide with checked-in files",
      (fun () ->
        with_temp_dir "oasis-action-collision" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
actions = ["generate_version"]

[action.generate_version]
argv = ["./scripts/generate_version.sh"]
outputs = ["version.ml"]

[executable.demo]
dir = "app"
main = "main"
modules = ["version"]
|};
            ignore
              (write_executable workspace "scripts/generate_version.sh"
                 "#!/bin/sh\nprintf 'let message = \"generated\"\\n' > version.ml\n");
            write_source workspace "app/version.ml"
              {|let message = "checked-in"|};
            write_source workspace "app/main.ml"
              {|let () = print_endline Version.message|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_true (build.status <> 0)
              "colliding generated source outputs should fail before the build runs";
            assert_string_contains ~needle:"collides with checked-in source"
              build.output
              "the build should explain why the generated output is unsafe";
            assert_string_contains ~needle:"app/version.ml" build.output
              "the collision report should point at the checked-in source path")) );
    ( "writes action stdout directly into declared generated outputs",
      (fun () ->
        with_temp_dir "oasis-action-stdout" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
actions = ["generate_version"]

[action.generate_version]
argv = ["./scripts/generate_version.sh"]
outputs = ["version.ml"]
stdout = "version.ml"
sandbox = "target"

[executable.demo]
dir = "app"
main = "main"
modules = ["version"]
|};
            ignore
              (write_executable workspace "scripts/generate_version.sh"
                 "#!/bin/sh\nprintf 'let message = \"stdout\"\\n'\n");
            write_source workspace "app/main.ml"
              {|let () = print_endline Version.message|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "actions should support redirecting stdout into declared outputs without a shell wrapper";
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "action stdout builds should produce a runnable executable";
            assert_string_equal "stdout\n" run.output
              "action stdout redirection should materialize compiler-readable generated modules")) );
    ( "runs multi-step actions without shell fallbacks",
      (fun () ->
        with_temp_dir "oasis-action-steps" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
actions = ["generate_version"]

[action.generate_version]
steps = [["./scripts/copy.sh", "../fixtures/version.txt", "version.txt"], ["./scripts/render.sh", "version.txt", "version.ml"]]
deps = ["fixtures/version.txt"]
outputs = ["version.ml"]
sandbox = "target"

[executable.demo]
dir = "app"
main = "main"
modules = ["version"]
|};
            ignore
              (write_executable workspace "scripts/copy.sh"
                 "#!/bin/sh\nset -eu\ncp \"$1\" \"$2\"\n");
            ignore
              (write_executable workspace "scripts/render.sh"
                 "#!/bin/sh\nset -eu\nprintf 'let message = \"%s\"\\n' \"$(cat \"$1\")\" > \"$2\"\n");
            write_source workspace "fixtures/version.txt" "steps\n";
            write_source workspace "app/main.ml"
              {|let () = print_endline Version.message|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "multi-step actions should build successfully";
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "multi-step action builds should produce runnable executables";
            assert_string_equal "steps\n" run.output
              "later action steps should be able to consume files produced by earlier steps in the sandbox")) );
    ( "feeds preprocessors from declared stdin_path inputs",
      (fun () ->
        with_temp_dir "oasis-preprocess-stdin-path" (fun workspace ->
            write_manifest workspace
              {|
[preprocess.seed]
argv = ["./scripts/cat.sh"]
stdin_path = "fixtures/main_template.ml"
deps = ["fixtures/main_template.ml"]

[executable.demo]
dir = "app"
main = "main"
preprocess = ["seed"]
|};
            ignore
              (write_executable workspace "scripts/cat.sh" "#!/bin/sh\ncat\n");
            write_source workspace "fixtures/main_template.ml"
              {|let () = print_endline "seeded"|};
            write_source workspace "app/main.ml" {|let () = failwith "ignored"|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "preprocessors should support stdin_path-backed transforms without shell indirection";
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "stdin_path preprocess builds should still produce runnable executables";
            assert_string_equal "seeded\n" run.output
              "stdin_path preprocessors should read from the declared file input instead of the original source contents")) );
    ( "applies named preprocessors in pipeline order",
      (fun () ->
        with_temp_dir "oasis-preprocess" (fun workspace ->
            write_manifest workspace
              {|
[preprocess.first]
argv = ["./scripts/first.sh"]

[preprocess.second]
argv = ["./scripts/second.sh"]

[executable.demo]
dir = "app"
main = "main"
preprocess = ["first", "second"]
|};
            ignore
              (write_executable workspace "scripts/first.sh"
                 "#!/bin/sh\nsed 's/__TOKEN__/stage_one/'\n");
            ignore
              (write_executable workspace "scripts/second.sh"
                 "#!/bin/sh\nsed 's/stage_one/pipeline/'\n");
            write_source workspace "app/main.ml"
              {|let () = print_endline "__TOKEN__"|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "preprocessed builds should compile successfully";
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "preprocessed executables should run successfully";
            assert_string_equal "pipeline\n" run.output
              "preprocessors should be applied in manifest order")) );
    ( "runs configured ppx rewriters during compilation",
      (fun () ->
        with_temp_dir "oasis-ppx" (fun workspace ->
            let _ppx_binary =
              compile_ppx workspace "ppx/rewrite.ml"
                {|
open Ast_helper
open Ast_mapper
open Parsetree

let expr mapper expression =
  match expression.pexp_desc with
  | Pexp_constant
      { pconst_desc = Pconst_string ("__PPX__", _, delimiter); pconst_loc = loc } ->
      Exp.constant
        {
          pconst_desc = Pconst_string ("rewritten by ppx", loc, delimiter);
          pconst_loc = loc;
        }
  | _ -> default_mapper.expr mapper expression

let () =
  run_main (fun _argv -> { default_mapper with expr })
|}
                "ppx/rewrite.exe"
            in
            write_manifest workspace
              {|
[ppx.rewrite]
argv = ["./ppx/rewrite.exe"]

[executable.demo]
dir = "app"
main = "main"
ppx = ["rewrite"]
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "__PPX__"|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "ppx-backed builds should compile successfully";
            let run = run_binary (executable_path workspace "demo") [] in
            assert_int_equal 0 run.status
              "ppx-backed executables should run successfully";
            assert_string_equal "rewritten by ppx\n" run.output
              "configured ppx rewriters should affect compiled output")) );
    ( "resolves default profiles and target overrides into separate build roots",
      (fun () ->
        with_temp_dir "oasis-profiles" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
profile = "release"
compile_flags = ["-principal"]
env = ["BUILD_PROFILE=default"]

[profile.release]
compile_flags = ["-strict-sequence"]
env = ["BUILD_PROFILE=release"]

[profile.release.executable.demo]
compile_flags = ["-rectypes"]
env = ["BUILD_PROFILE=demo"]

[profile.dev]
compile_flags = ["-annot"]
env = ["BUILD_PROFILE=dev"]

[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "profiled"|};
            let log_path = Filename.concat workspace "compiler.log" in
            let ocamlopt_wrapper =
              write_logging_wrapper workspace "bin/ocamlopt-wrapper" log_path
                (resolve_command "ocamlopt")
            in
            let release_build =
              with_env "OCAMLOPT" ocamlopt_wrapper (fun () ->
                  run_oasis ~cwd:workspace [ "build" ])
            in
            assert_int_equal 0 release_build.status
              "the default profile should build successfully";
            assert_file_exists (profile_executable_path workspace "release" "demo");
            let release_log = Fs.read_file log_path in
            assert_string_contains ~needle:"BUILD_PROFILE=demo\n" release_log
              "target-specific env overrides should reach compiler invocations";
            assert_string_contains ~needle:"-principal" release_log
              "default compile flags should reach the compiler";
            assert_string_contains ~needle:"-strict-sequence" release_log
              "profile compile flags should reach the compiler";
            assert_string_contains ~needle:"-rectypes" release_log
              "profile target compile flags should reach the compiler";
            Fs.write_file log_path "";
            let dev_build =
              with_env "OCAMLOPT" ocamlopt_wrapper (fun () ->
                  run_oasis ~cwd:workspace [ "build"; "--profile"; "dev" ])
            in
            assert_int_equal 0 dev_build.status
              "explicit alternate profiles should build successfully";
            assert_file_exists (profile_executable_path workspace "dev" "demo");
            let dev_log = Fs.read_file log_path in
            assert_string_contains ~needle:"BUILD_PROFILE=dev\n" dev_log
              "selected profile env should reach compiler invocations";
            assert_string_contains ~needle:"-annot" dev_log
              "alternate profile flags should reach the compiler";
            assert_string_not_contains ~needle:"-rectypes" dev_log
              "target overrides from other profiles should not leak into dev")) );
  ]
