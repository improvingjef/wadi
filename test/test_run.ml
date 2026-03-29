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
    ( "forwards signaled executable exits",
      (fun () ->
        with_temp_dir "oasis-run-signal" (fun workspace ->
            write_manifest workspace
              {|
[executable.sigterm]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|let () = ignore (Sys.command "kill -TERM $PPID")|};
            let run = run_oasis ~cwd:workspace [ "run" ] in
            assert_int_equal (128 + Sys.sigterm) run.status
              "run should surface shell-compatible status codes for signals";
            assert_wait_status_signaled Sys.sigterm run.unix_status
              "run should terminate with the same signal as the executable";
            assert_string_contains ~needle:"Built executable sigterm"
              run.output
              "run should still surface the build phase before the executable exits")) );
    ( "prints top-level usage from the command table",
      (fun () ->
        with_temp_dir "oasis-cli-usage" (fun workspace ->
            let run = run_oasis ~cwd:workspace [] in
            assert_true (run.status <> 0)
              "invoking oasis without a command should print usage";
            assert_string_contains
              ~needle:"oasis build [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET ...]"
              run.output "top-level usage should include the build command";
            assert_string_contains
              ~needle:"oasis run [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET] [-- ARG ...]"
              run.output "top-level usage should include the run command";
            assert_string_contains
              ~needle:"oasis test [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET ...]"
              run.output "top-level usage should include the test command";
            assert_string_contains
              ~needle:"oasis clean [--workspace DIR] [--profile NAME] [--verbose] [TARGET ...]"
              run.output "top-level usage should include the clean command";
            assert_string_contains ~needle:"oasis toolchain" run.output
              "top-level usage should include the toolchain command")) );
    ( "prints command-specific help from the command table",
      (fun () ->
        with_temp_dir "oasis-cli-help" (fun workspace ->
            let help = run_oasis ~cwd:workspace [ "build"; "--help" ] in
            assert_true (help.status <> 0)
              "build --help should short-circuit with usage text";
            assert_string_contains
              ~needle:"oasis build [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET ...]"
              help.output "build help should include the build signature";
            assert_string_not_contains
              ~needle:"oasis run [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET] [-- ARG ...]"
              help.output
              "command-specific help should not include unrelated commands")) );
  ]
