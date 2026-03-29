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
  ]
