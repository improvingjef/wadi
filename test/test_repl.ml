open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let cases =
  [
    ( "launches a bytecode toplevel with workspace libraries and package dependencies",
      (fun () ->
        with_temp_dir "oasis-repl-library" (fun workspace ->
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
              {|let value = "linked-core"|};
            write_source workspace "app/main.ml"
              {|let () = print_endline Core.value|};
            let script_path = Filename.concat workspace "repl-script.ml" in
            Fs.write_file script_path
              {|print_endline Core.value;;
print_endline (string_of_int (Unix.getpid ()));;
exit 0;;
|};
            let repl =
              run_oasis ~cwd:workspace
                [ "repl"; "core"; "--"; "-noinit"; "-noprompt"; script_path ]
            in
            assert_int_equal 0 repl.status
              "repl should exit cleanly after running the script file";
            assert_string_contains ~needle:"Launching repl for library core ->"
              repl.output
              "repl should report the selected target and generated toplevel path";
            assert_string_contains ~needle:"linked-core" repl.output
              "repl should evaluate the linked workspace library value";
            assert_string_not_contains ~needle:"Unbound module Unix" repl.output
              "repl should make selected package dependencies available in the toplevel")) );
    ( "uses the only runnable target by default when no library is present",
      (fun () ->
        with_temp_dir "oasis-repl-runnable-default" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"
modules = ["helper"]
|};
            write_source workspace "app/helper.ml" {|let value = "helper"|};
            write_source workspace "app/main.ml"
              {|let () = print_endline Helper.value|};
            let script_path = Filename.concat workspace "repl-script.ml" in
            Fs.write_file script_path
              {|print_endline Helper.value;;
exit 0;;
|};
            let repl =
              run_oasis ~cwd:workspace
                [ "repl"; "--"; "-noinit"; "-noprompt"; script_path ]
            in
            assert_int_equal 0 repl.status
              "repl should infer the only runnable target by default";
            assert_string_contains
              ~needle:"Launching repl for executable demo ->"
              repl.output
              "repl should report the inferred executable target";
            assert_string_contains ~needle:"helper" repl.output
              "repl should link helper modules from runnable targets")) );
    ( "reuses cached toplevel binaries when repl inputs are unchanged",
      (fun () ->
        with_temp_dir "oasis-repl-cache" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
|};
            write_source workspace "lib/core.ml" {|let value = "cached"|};
            let script_path = Filename.concat workspace "repl-script.ml" in
            Fs.write_file script_path
              {|print_endline Core.value;;
exit 0;;
|};
            let first =
              run_oasis ~cwd:workspace
                [ "repl"; "core"; "--"; "-noinit"; "-noprompt"; script_path ]
            in
            assert_int_equal 0 first.status
              "the first repl launch should build a toplevel";
            assert_string_contains
              ~needle:"Built repl toplevel for library core ->"
              first.output
              "the first repl launch should report a built toplevel";
            let second =
              run_oasis ~cwd:workspace
                [ "repl"; "core"; "--"; "-noinit"; "-noprompt"; script_path ]
            in
            assert_int_equal 0 second.status
              "the second repl launch should still succeed";
            assert_string_contains
              ~needle:"Up to date repl toplevel for library core ->"
              second.output
              "unchanged repl launches should reuse the cached toplevel";
            assert_string_not_contains
              ~needle:"Built repl toplevel for library core ->"
              second.output
              "unchanged repl launches should skip the relink";
            assert_string_contains ~needle:"cached" second.output
              "reused repl launches should still execute the script successfully")) );
    ( "runs explicit --script input without depending on OCaml script-file argv handling",
      (fun () ->
        with_temp_dir "oasis-repl-explicit-script" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
packages = ["unix"]
|};
            write_source workspace "lib/core.ml"
              {|let value = "scripted"|};
            let script_path = Filename.concat workspace "repl-script.ml" in
            Fs.write_file script_path
              {|print_endline Core.value;;
print_endline (string_of_bool (Unix.getpid () > 0));;
exit 0;;
|};
            let repl =
              run_oasis ~cwd:workspace
                [ "repl"; "core"; "--script"; "repl-script.ml"; "--"; "-noinit"; "-noprompt" ]
            in
            assert_int_equal 0 repl.status
              "repl --script should execute scripted phrases successfully";
            assert_string_contains ~needle:"Built repl toplevel for library core ->"
              repl.output
              "repl --script should still build the target toplevel";
            assert_string_contains ~needle:"scripted" repl.output
              "repl --script should evaluate workspace-linked modules";
            assert_string_contains ~needle:"true" repl.output
              "repl --script should expose package-backed runtime code to the script")) );
    ( "renders machine-readable repl plans without launching the toplevel",
      (fun () ->
        with_temp_dir "oasis-repl-plan" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
packages = ["unix"]
env = ["REPL_MODE=plan"]
|};
            write_source workspace "lib/core.ml" {|let value = "planned"|};
            let script_path = Filename.concat workspace "plan-script.ml" in
            Fs.write_file script_path
              {|print_endline Core.value;;
exit 0;;
|};
            let plan =
              run_oasis ~cwd:workspace
                [
                  "repl";
                  "--plan";
                  "--json";
                  "core";
                  "--script";
                  "plan-script.ml";
                  "--";
                  "-noinit";
                  "-noprompt";
                ]
            in
            assert_int_equal 0 plan.status
              "repl --plan --json should print a machine-readable plan";
            assert_string_contains ~needle:"\"kind\": \"library\"" plan.output
              "the repl plan should identify the selected target kind";
            assert_string_contains ~needle:"\"name\": \"core\"" plan.output
              "the repl plan should identify the selected target name";
            assert_string_contains
              ~needle:(Printf.sprintf "\"script_path\": %S" (Fs.realpath script_path))
              plan.output
              "the repl plan should resolve and report the scripted stdin source";
            assert_string_contains
              ~needle:"\"toplevel_status\": \"build-needed\""
              plan.output
              "a fresh repl plan should report that the toplevel still needs to be built";
            assert_string_contains ~needle:"\"include_dirs\": [" plan.output
              "the repl plan should surface include paths for editor consumers";
            assert_string_contains ~needle:"\"link_inputs\": [" plan.output
              "the repl plan should surface linked archives and helper objects";
            assert_string_contains ~needle:"\"name\": \"REPL_MODE\"" plan.output
              "the repl plan should preserve explicit environment overrides";
            assert_string_not_contains ~needle:"Launching repl" plan.output
              "planning mode should not launch the repl";
            let repl =
              run_oasis ~cwd:workspace
                [
                  "repl";
                  "core";
                  "--script";
                  "plan-script.ml";
                  "--";
                  "-noinit";
                  "-noprompt";
                ]
            in
            assert_int_equal 0 repl.status
              "building the repl after planning should still succeed";
            let planned_again =
              run_oasis ~cwd:workspace
                [ "repl"; "--plan"; "--json"; "core" ]
            in
            assert_int_equal 0 planned_again.status
              "re-running repl planning after a launch should still succeed";
            assert_string_contains
              ~needle:"\"toplevel_status\": \"reusable\""
              planned_again.output
              "a warm repl plan should report that the cached toplevel can be reused")) );
    ( "rejects repl --json without planning mode",
      (fun () ->
        with_temp_dir "oasis-repl-json-without-plan" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
|};
            write_source workspace "lib/core.ml" {|let value = "core"|};
            let repl = run_oasis ~cwd:workspace [ "repl"; "--json"; "core" ] in
            assert_true (repl.status <> 0)
              "repl should reject JSON output without explicit planning mode";
            assert_string_contains ~needle:"repl --json requires --plan"
              repl.output
              "repl should explain how to request machine-readable planning")) );
  ]
