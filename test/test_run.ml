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
            assert_string_contains
              ~needle:"oasis install [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--prefix DIR] [--verbose] [TARGET ...]"
              run.output "top-level usage should include the install command";
            assert_string_contains ~needle:"oasis docs" run.output
              "top-level usage should include the docs command";
            assert_string_contains ~needle:"oasis completion SHELL" run.output
              "top-level usage should include the completion command";
            assert_string_contains ~needle:"oasis toolchain" run.output
              "top-level usage should include the toolchain command";
            assert_string_contains
              ~needle:"oasis explain [--workspace DIR] [--profile NAME] [TARGET ...]"
              run.output "top-level usage should include the explain command")) );
    ( "prints command-specific help for explain from the command table",
      (fun () ->
        with_temp_dir "oasis-cli-explain-help" (fun workspace ->
            let help = run_oasis ~cwd:workspace [ "explain"; "--help" ] in
            assert_true (help.status <> 0)
              "explain --help should short-circuit with usage text";
            assert_string_contains
              ~needle:"oasis explain [--workspace DIR] [--profile NAME] [TARGET ...]"
              help.output "explain help should include the explain signature";
            assert_string_not_contains
              ~needle:"oasis build [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET ...]"
              help.output
              "command-specific help should not include unrelated commands")) );
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
    ( "renders markdown docs from the command table",
      (fun () ->
        with_temp_dir "oasis-cli-docs" (fun workspace ->
            let docs = run_oasis ~cwd:workspace [ "docs" ] in
            assert_int_equal 0 docs.status
              "docs should render markdown successfully";
            assert_string_contains ~needle:"# Oasis CLI" docs.output
              "docs output should start with the markdown title";
            assert_string_contains ~needle:"## install" docs.output
              "docs output should include the install command";
            assert_string_contains ~needle:"## completion" docs.output
              "docs output should include the completion command";
            assert_string_contains
              ~needle:"- `--prefix DIR`: Stage installed files under DIR instead of the default profile root."
              docs.output
              "docs output should include option descriptions from the command table")) );
    ( "renders bash completions from the command table",
      (fun () ->
        with_temp_dir "oasis-cli-bash-completion" (fun workspace ->
            let completion = run_oasis ~cwd:workspace [ "completion"; "bash" ] in
            assert_int_equal 0 completion.status
              "bash completion generation should succeed";
            assert_string_contains ~needle:"_oasis()" completion.output
              "bash completion output should define the completion function";
            assert_string_contains
              ~needle:"build run test clean install docs completion toolchain explain"
              completion.output
              "bash completion should include the command list from the table";
            assert_string_contains ~needle:"--prefix" completion.output
              "bash completion should include install flags";
            assert_string_contains ~needle:"bash zsh fish" completion.output
              "bash completion should include static shell names for the completion command")) );
    ( "renders zsh completions from the command table",
      (fun () ->
        with_temp_dir "oasis-cli-zsh-completion" (fun workspace ->
            let completion = run_oasis ~cwd:workspace [ "completion"; "zsh" ] in
            assert_int_equal 0 completion.status
              "zsh completion generation should succeed";
            assert_string_contains ~needle:"#compdef oasis" completion.output
              "zsh completion output should declare the compdef";
            assert_string_contains
              ~needle:"_values 'command' build run test clean install docs completion toolchain explain"
              completion.output
              "zsh completion should include the command list from the table";
            assert_string_contains ~needle:"bash zsh fish" completion.output
              "zsh completion should include static shell names for the completion command")) );
    ( "renders fish completions from the command table",
      (fun () ->
        with_temp_dir "oasis-cli-fish-completion" (fun workspace ->
            let completion = run_oasis ~cwd:workspace [ "completion"; "fish" ] in
            assert_int_equal 0 completion.status
              "fish completion generation should succeed";
            assert_string_contains
              ~needle:"complete -c oasis -f -n '__fish_use_subcommand' -a 'build run test clean install docs completion toolchain explain'"
              completion.output
              "fish completion should include the command list from the table";
            assert_string_contains
              ~needle:"__fish_seen_subcommand_from install"
              completion.output
              "fish completion should include install-specific options";
            assert_string_contains
              ~needle:"__fish_seen_subcommand_from completion"
              completion.output
              "fish completion should include completion-specific shell names")) );
    ( "rejects unknown completion shells clearly",
      (fun () ->
        with_temp_dir "oasis-cli-completion-error" (fun workspace ->
            let completion = run_oasis ~cwd:workspace [ "completion"; "pwsh" ] in
            assert_true (completion.status <> 0)
              "completion should reject unsupported shells";
            assert_string_contains
              ~needle:"unknown shell 'pwsh'; expected bash, fish, or zsh"
              completion.output
              "completion should report the supported shell names directly")) );
  ]
