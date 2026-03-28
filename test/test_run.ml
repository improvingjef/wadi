open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let cases =
  [
    ( "runs the only executable target in a workspace",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let run = run_oasis ~cwd:workspace [ "run" ] in
            assert_int_equal 0 run.status
              "run should build and execute the sole executable target";
            assert_string_contains ~needle:"Built library greeting" run.output
              "run should still report the build phase";
            assert_string_contains ~needle:"Built executable hello" run.output
              "run should build the executable before launching it";
            assert_string_contains ~needle:"Hello, world!\n" run.output
              "run should forward the program output")) );
    ( "forwards arguments to the selected executable",
      (fun () ->
        with_temp_dir "oasis-run-args" (fun workspace ->
            write_manifest workspace
              {|
[executable.echo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|
let () =
  Sys.argv
  |> Array.to_list
  |> List.tl
  |> String.concat ","
  |> print_endline
|};
            let run =
              run_oasis ~cwd:workspace
                [ "run"; "echo"; "--"; "red"; "blue"; "green" ]
            in
            assert_int_equal 0 run.status
              "run should succeed when forwarding argv";
            assert_string_contains ~needle:"red,blue,green\n" run.output
              "run should pass arguments through unchanged")) );
    ( "rejects ambiguous default executable selection",
      (fun () ->
        with_temp_dir "oasis-run-ambiguous" (fun workspace ->
            write_manifest workspace
              {|
[executable.first]
dir = "first"
main = "main"

[executable.second]
dir = "second"
main = "main"
|};
            write_source workspace "first/main.ml" {|let () = print_endline "first"|};
            write_source workspace "second/main.ml"
              {|let () = print_endline "second"|};
            let run = run_oasis ~cwd:workspace [ "run" ] in
            assert_true (run.status <> 0)
              "run should fail when a workspace has multiple executables";
            assert_string_contains
              ~needle:"workspace defines multiple executables; choose one: first, second"
              run.output
              "run should explain how to resolve ambiguous executable selection")) );
    ( "rejects library targets for run",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let run = run_oasis ~cwd:workspace [ "run"; "greeting" ] in
            assert_true (run.status <> 0)
              "run should reject non-executable targets";
            assert_string_contains
              ~needle:"target 'greeting' is a library; oasis run only supports executables"
              run.output
              "run should report invalid target kinds clearly")) );
  ]
