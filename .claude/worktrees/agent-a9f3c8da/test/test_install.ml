open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let assert_one_file_exists paths message =
  if not (List.exists Fs.exists paths) then
    fail
      (Printf.sprintf "%s\nexpected one of:\n%s" message
         (String.concat "\n" paths))

let cases =
  [
    ( "installs libraries, executables, and metadata into a prefix",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let prefix = Filename.concat workspace "_stage" in
            let install =
              run_wadi ~cwd:workspace [ "install"; "--prefix"; prefix ]
            in
            assert_int_equal 0 install.status
              "install should stage the default installable targets";
            let installed_binary = Filename.concat prefix "bin/hello" in
            assert_file_exists installed_binary;
            assert_file_exists (Filename.concat prefix "lib/greeting/greeting.cmi");
            let meta_path = Filename.concat prefix "lib/greeting/META" in
            assert_file_exists meta_path;
            assert_one_file_exists
              [
                Filename.concat prefix "lib/greeting/libgreeting.cmxa";
                Filename.concat prefix "lib/greeting/libgreeting.cma";
              ]
              "install should stage a compiled library archive";
            let metadata_path =
              Filename.concat prefix "share/wadi/hello/install.json"
            in
            assert_file_exists metadata_path;
            assert_file_exists
              (Filename.concat prefix "share/wadi/hello/wadi.toml");
            let meta = Fs.read_file meta_path in
            assert_string_contains ~needle:"description = \"hello library greeting\"" meta
              "install should emit a findlib-friendly META description";
            assert_string_contains ~needle:"directory = \".\"" meta
              "install should emit a relative META directory";
            let metadata = Fs.read_file metadata_path in
            assert_string_contains ~needle:"\"workspace\": \"hello\"" metadata
              "install metadata should record the workspace name";
            assert_string_contains ~needle:"\"name\": \"greeting\"" metadata
              "install metadata should record installed libraries";
            assert_string_contains ~needle:"\"meta\": \"lib/greeting/META\"" metadata
              "install metadata should record library META paths";
            assert_string_contains ~needle:"\"path\": \"bin/hello\"" metadata
              "install metadata should record installed executables";
            assert_string_contains ~needle:"\"share_dir\": \"share/wadi/hello\"" metadata
              "install metadata should publish the staged share root";
            assert_string_contains ~needle:"\"ocamlpath\": [" metadata
              "install metadata should publish OCAMLPATH roots for consumers";
            let run = run_binary installed_binary [] in
            assert_int_equal 0 run.status
              "installed executables should remain runnable from the staged prefix";
            assert_string_equal "Hello, world!\n" run.output
              "the staged executable should preserve program behavior")) );
    ( "installs only the requested top-level targets",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let prefix = Filename.concat workspace "_exe-only" in
            let install =
              run_wadi ~cwd:workspace
                [ "install"; "--prefix"; prefix; "greeting" ]
            in
            assert_int_equal 0 install.status
              "install should allow targeted staging";
            assert_file_exists (Filename.concat prefix "lib/greeting/META");
            assert_true
              (not (Fs.exists (Filename.concat prefix "bin/hello")))
              "installing only a library should not stage unrelated executables";
            let metadata =
              Fs.read_file (Filename.concat prefix "share/wadi/hello/install.json")
            in
            assert_string_not_contains ~needle:"\"path\": \"bin/hello\"" metadata
              "install metadata should not list unrequested executables")) );
    ( "stages internal library dependencies needed by requested targets",
      (fun () ->
        with_temp_dir "wadi-install-closure" (fun workspace ->
            write_manifest workspace
              {|
[library.greeting]
dir = "lib"
modules = ["greeting"]

[library.unused]
dir = "unused"
modules = ["unused"]

[executable.hello]
dir = "app"
main = "main"
deps = ["greeting"]
|};
            write_source workspace "lib/greeting.ml"
              {|let message name = "Hello, " ^ name ^ "!"|};
            write_source workspace "unused/unused.ml" {|let value = 7|};
            write_source workspace "app/main.ml"
              {|let () = print_endline (Greeting.message "world")|};
            let prefix = Filename.concat workspace "_stage" in
            let install =
              run_wadi ~cwd:workspace [ "install"; "--prefix"; prefix; "hello" ]
            in
            assert_int_equal 0 install.status
              "install should stage the requested executable";
            assert_file_exists (Filename.concat prefix "bin/hello");
            assert_file_exists (Filename.concat prefix "lib/greeting/META");
            assert_true
              (not (Fs.exists (Filename.concat prefix "lib/unused")))
              "install closure should not stage unrelated libraries";
            let metadata =
              Fs.read_file (Filename.concat prefix "share/wadi/workspace/install.json")
            in
            assert_string_contains ~needle:"\"requested_targets\": [\"hello\"]"
              metadata
              "install metadata should record the explicit top-level install request";
            assert_string_contains ~needle:"\"selection\": \"requested\"" metadata
              "install metadata should preserve which artifacts were explicitly selected";
            assert_string_contains ~needle:"\"name\": \"greeting\"" metadata
              "install metadata should record required internal libraries";
            assert_string_contains ~needle:"\"selection\": \"dependency\"" metadata
              "install metadata should mark closure-added libraries as dependencies";
            assert_string_contains ~needle:"\"requested_by\": [\"hello\"]" metadata
              "install metadata should record which top-level target pulled a dependency in";
            assert_string_not_contains ~needle:"\"name\": \"unused\"" metadata
              "install metadata should omit unrelated internal libraries")) );
    ( "supports packaging-style staging with --destdir",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let destdir = Filename.concat workspace "_pkg" in
            let install =
              run_wadi ~cwd:workspace
                [ "install"; "--prefix"; "/usr/local"; "--destdir"; "_pkg" ]
            in
            assert_int_equal 0 install.status
              "install should support DESTDIR-style staging";
            let staged_root = Filename.concat destdir "usr/local" in
            assert_file_exists (Filename.concat staged_root "bin/hello");
            assert_file_exists (Filename.concat staged_root "lib/greeting/META");
            let metadata_path =
              Filename.concat staged_root "share/wadi/hello/install.json"
            in
            assert_file_exists metadata_path;
            let metadata = Fs.read_file metadata_path in
            assert_string_contains ~needle:"\"prefix\": \"/usr/local\"" metadata
              "install metadata should preserve the logical install prefix";
            assert_string_contains
              ~needle:(Printf.sprintf "\"stage_root\": %S" (Fs.realpath staged_root))
              metadata
              "install metadata should record the realized staging root";
            assert_string_contains
              ~needle:(Printf.sprintf "\"destdir\": %S" (Fs.realpath destdir))
              metadata
              "install metadata should record the resolved destdir")) );
    ( "keeps relative prefixes relative when combined with --destdir",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let destdir = Filename.concat workspace "_pkg" in
            let stage_root = Filename.concat destdir "_stage" in
            let install =
              run_wadi ~cwd:workspace
                [ "install"; "--prefix"; "_stage"; "--destdir"; "_pkg" ]
            in
            assert_int_equal 0 install.status
              "install should support relative prefixes inside a destdir stage";
            assert_file_exists (Filename.concat stage_root "bin/hello");
            assert_file_exists (Filename.concat stage_root "lib/greeting/META");
            let metadata =
              Fs.read_file
                (Filename.concat stage_root "share/wadi/hello/install.json")
            in
            assert_string_contains ~needle:"\"prefix\": \"_stage\"" metadata
              "install metadata should preserve a relative logical prefix";
            assert_string_not_contains
              ~needle:(Printf.sprintf "\"prefix\": %S"
                         (Fs.realpath (Filename.concat workspace "_stage")))
              metadata
              "install metadata should not rewrite a relative prefix to the workspace absolute path";
            assert_string_contains
              ~needle:(Printf.sprintf "\"stage_root\": %S" (Fs.realpath stage_root))
              metadata
              "install metadata should record the realized relative stage root")) );
    ( "records findlib requires in staged META files",
      (fun () ->
        with_temp_dir "wadi-install-meta" (fun workspace ->
            write_manifest workspace
              {|
[library.patterns]
dir = "lib"
modules = ["patterns"]
packages = ["str"]

[library.facade]
dir = "facade"
modules = ["facade"]
deps = ["patterns"]
|};
            write_source workspace "lib/patterns.ml"
              {|
let contains_digit text =
  Str.string_match (Str.regexp ".*[0-9].*") text 0
|};
            write_source workspace "facade/facade.ml"
              {|let contains_digit = Patterns.contains_digit|};
            let prefix = Filename.concat workspace "_stage" in
            let install =
              run_wadi ~cwd:workspace [ "install"; "--prefix"; prefix ]
            in
            assert_int_equal 0 install.status
              "install should succeed before META requires are inspected";
            let patterns_meta = Fs.read_file (Filename.concat prefix "lib/patterns/META") in
            assert_string_contains ~needle:"requires = \"str\"" patterns_meta
              "package-backed libraries should export external requires";
            let facade_meta = Fs.read_file (Filename.concat prefix "lib/facade/META") in
            assert_string_contains ~needle:"requires = \"patterns\"" facade_meta
              "dependent libraries should export internal library requires")) );
    ( "installs public names for libraries and executables",
      (fun () ->
        with_temp_dir "wadi-install-public-names" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
public_name = "demo.core"

[library.facade]
dir = "facade"
modules = ["facade"]
deps = ["core"]
public_name = "demo.facade"

[executable.cli]
dir = "app"
main = "main"
deps = ["facade"]
public_name = "demo-cli"
|};
            write_source workspace "lib/core.ml" {|let message = "public"|};
            write_source workspace "facade/facade.ml"
              {|let message = Core.message|};
            write_source workspace "app/main.ml"
              {|let () = print_endline Facade.message|};
            let prefix = Filename.concat workspace "_stage" in
            let install =
              run_wadi ~cwd:workspace [ "install"; "--prefix"; prefix ]
            in
            assert_int_equal 0 install.status
              "install should stage public names when present";
            assert_file_exists (Filename.concat prefix "lib/demo.core/META");
            assert_file_exists (Filename.concat prefix "lib/demo.facade/META");
            assert_file_exists (Filename.concat prefix "bin/demo-cli");
            let facade_meta =
              Fs.read_file (Filename.concat prefix "lib/demo.facade/META")
            in
            assert_string_contains ~needle:"requires = \"demo.core\"" facade_meta
              "META requires should follow staged public library names";
            let metadata =
              Fs.read_file (Filename.concat prefix "share/wadi/workspace/install.json")
            in
            assert_string_contains ~needle:"\"meta\": \"lib/demo.core/META\"" metadata
              "install metadata should point at the staged public library path";
            assert_string_contains ~needle:"\"path\": \"bin/demo-cli\"" metadata
              "install metadata should point at the staged public executable path")) );
    ( "does not stage stale wrapper artifacts after wrapped mode flips",
      (fun () ->
        with_temp_dir "wadi-install-prune-wrapper" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
wrapped = true
modules = ["greeting"]
|};
            write_source workspace "lib/greeting.ml"
              {|let message = "wrapped"|};
            let first_build = run_wadi ~cwd:workspace [ "build"; "core" ] in
            assert_int_equal 0 first_build.status
              "the initial wrapped build should succeed before stale-wrapper pruning is exercised";
            let wrapper_cmi =
              Filename.concat (Layout.library_out_dir workspace "core") "core.cmi"
            in
            assert_file_exists wrapper_cmi;
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["greeting"]
|};
            let prefix = Filename.concat workspace "_stage" in
            let install =
              run_wadi ~cwd:workspace
                [ "install"; "--prefix"; prefix; "core" ]
            in
            assert_int_equal 0 install.status
              "install should rebuild and stage the library after wrapped mode changes";
            assert_true (not (Fs.exists wrapper_cmi))
              "the stale generated wrapper interface should be pruned from the build directory";
            assert_true
              (not (Fs.exists (Filename.concat prefix "lib/core/core.cmi")))
              "install should not stage stale wrapper artifacts after wrapped mode flips";
            assert_file_exists (Filename.concat prefix "lib/core/greeting.cmi"))) );
    ( "reports member package paths in install summaries",
      (fun () ->
        with_temp_dir "wadi-install-package-paths" (fun workspace ->
            write_manifest workspace
              {|
workspace = "demo"
version = 1
members = ["packages/core", "packages/app"]
|};
            write_workspace_file workspace "packages/core/wadi.toml"
              {|
[library.core]
dir = "lib"
modules = ["core"]
|};
            write_workspace_file workspace "packages/app/wadi.toml"
              {|
[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "packages/core/lib/core.ml"
              {|let message = "installed member"|};
            write_source workspace "packages/app/app/main.ml"
              {|let () = print_endline Core.message|};
            let prefix = Filename.concat workspace "_stage" in
            let install =
              run_wadi ~cwd:workspace [ "install"; "--prefix"; prefix ]
            in
            assert_int_equal 0 install.status
              "member targets should install successfully";
            assert_string_contains
              ~needle:"Installed library core (packages/core) ->"
              install.output
              "install summaries should surface member library package paths";
            assert_string_contains
              ~needle:"Installed executable demo (packages/app) ->"
              install.output
              "install summaries should surface member executable package paths")) );
    ( "rejects test targets for install",
      (fun () ->
        with_temp_dir "wadi-install-tests" (fun workspace ->
            write_manifest workspace
              {|
[test.suite]
dir = "test"
main = "main"
|};
            write_source workspace "test/main.ml" {|let () = print_endline "suite"|};
            let install = run_wadi ~cwd:workspace [ "install"; "suite" ] in
            assert_true (install.status <> 0)
              "install should reject test-only targets";
            assert_string_contains
              ~needle:"target 'suite' is a test; wadi install only supports libraries and executables"
              install.output
              "install should report unsupported target kinds clearly")) );
  ]
