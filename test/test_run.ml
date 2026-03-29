open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let write_executable workspace relative_path contents =
  let path = Filename.concat workspace relative_path in
  Fs.write_file path contents;
  Unix.chmod path 0o755;
  path

let path_with dir =
  match Sys.getenv_opt "PATH" with
  | Some path -> dir ^ ":" ^ path
  | None -> dir

let write_oasis_shim cwd =
  ignore
    (write_executable cwd "oasis"
       (Printf.sprintf "#!/bin/sh\nexec %s \"$@\"\n"
          (Filename.quote (oasis_bin ()))))

let run_bash_completion ~cwd script body =
  let script_path = Filename.concat cwd "oasis-completion.bash" in
  Fs.write_file script_path script;
  write_oasis_shim cwd;
  Process.run_capture ~cwd ~env:[ ("PATH", path_with cwd) ] "bash"
    [ "-lc"; Printf.sprintf "source %s\n%s" (Filename.quote script_path) body ]

let run_zsh_completion ~cwd script body =
  let script_path = Filename.concat cwd "oasis-completion.zsh" in
  Fs.write_file script_path script;
  write_oasis_shim cwd;
  Process.run_capture ~cwd ~env:[ ("PATH", path_with cwd) ] "zsh"
    [ "-lc"; Printf.sprintf "source %s\n%s" (Filename.quote script_path) body ]

let run_fish_completion ~cwd script body =
  let script_path = Filename.concat cwd "oasis-completion.fish" in
  Fs.write_file script_path script;
  write_oasis_shim cwd;
  Process.run_capture ~cwd ~env:[ ("PATH", path_with cwd) ] "fish"
    [ "-c"; Printf.sprintf "source %s\n%s" (Filename.quote script_path) body ]

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
    ( "reports member package paths in run summaries",
      (fun () ->
        with_temp_dir "oasis-run-package-path" (fun workspace ->
            write_manifest workspace
              {|
workspace = "demo"
version = 1
members = ["packages/app"]
|};
            write_workspace_file workspace "packages/app/oasis.toml"
              {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "packages/app/app/main.ml"
              {|let () = print_endline "member run"|};
            let run = run_oasis ~cwd:workspace [ "run"; "demo" ] in
            assert_int_equal 0 run.status
              "member executables should still run successfully";
            assert_string_contains
              ~needle:"Running executable demo (packages/app) ->"
              run.output
              "run summaries should surface the member package path";
            assert_string_contains ~needle:"member run\n" run.output
              "run should still stream the executable output")) );
    ( "inspects preprocessor and ppx pipelines for a selected module",
      (fun () ->
        with_temp_dir "oasis-ppx-plan" (fun workspace ->
            let _ppx_binary =
              Test_build.compile_ppx workspace "ppx/rewrite.ml"
                {|
open Ast_helper
open Ast_mapper
open Parsetree

let replace_ppx_marker value =
  let marker = "__PPX__" in
  let marker_length = String.length marker in
  let value_length = String.length value in
  let rec find index =
    if index + marker_length > value_length then None
    else if String.sub value index marker_length = marker then Some index
    else find (index + 1)
  in
  match find 0 with
  | None -> None
  | Some index ->
      Some
        (String.sub value 0 index ^ "rewritten by ppx"
       ^ String.sub value (index + marker_length)
           (value_length - index - marker_length))

let expr mapper expression =
  match expression.pexp_desc with
  | Pexp_constant
      {
        pconst_desc = Pconst_string (value, _, delimiter);
        pconst_loc = loc;
      }
    -> (
      match replace_ppx_marker value with
      | Some rewritten ->
      Exp.constant
        {
          pconst_desc = Pconst_string (rewritten, loc, delimiter);
          pconst_loc = loc;
        }
      | None -> default_mapper.expr mapper expression )
  | _ -> default_mapper.expr mapper expression

let () =
  run_main (fun _argv -> { default_mapper with expr })
|}
                "ppx/rewrite.exe"
            in
            ignore
              (write_executable workspace "tools/expand.sh"
                 "#!/bin/sh\nset -eu\nsed 's/__PRE__/pre/g'\n");
            write_manifest workspace
              {|
[preprocess.expand]
argv = ["./tools/expand.sh"]

[ppx.rewrite]
argv = ["./ppx/rewrite.exe"]

[executable.demo]
dir = "app"
main = "main"
preprocess = ["expand"]
ppx = ["rewrite"]
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "__PRE__:__PPX__"|};
            let plan =
              run_oasis ~cwd:workspace [ "ppx"; "--plan"; "demo"; "main" ]
            in
            assert_int_equal 0 plan.status
              "ppx --plan should inspect the selected target module";
            assert_string_contains ~needle:"Target: demo" plan.output
              "ppx plans should identify the selected target";
            assert_string_contains ~needle:"Preprocessors:" plan.output
              "ppx plans should list configured preprocessors";
            assert_string_contains ~needle:"tools/expand.sh" plan.output
              "ppx plans should show the resolved preprocessor command";
            assert_string_contains ~needle:"PPX:" plan.output
              "ppx plans should list configured ppx tools";
            assert_string_contains ~needle:"ppx/rewrite.exe" plan.output
              "ppx plans should show the resolved ppx executable";
            assert_string_contains ~needle:"Selected-module: main" plan.output
              "ppx plans should show the selected module";
            assert_string_contains ~needle:"Prepared-source:" plan.output
              "ppx plans should show the transformed input path";
            assert_string_contains ~needle:"Compiler-command:" plan.output
              "ppx plans should show the exact dump command")) );
    ( "dumps transformed source for a module after preprocessors and ppx",
      (fun () ->
        with_temp_dir "oasis-ppx-apply" (fun workspace ->
            let _ppx_binary =
              Test_build.compile_ppx workspace "ppx/rewrite.ml"
                {|
open Ast_helper
open Ast_mapper
open Parsetree

let replace_ppx_marker value =
  let marker = "__PPX__" in
  let marker_length = String.length marker in
  let value_length = String.length value in
  let rec find index =
    if index + marker_length > value_length then None
    else if String.sub value index marker_length = marker then Some index
    else find (index + 1)
  in
  match find 0 with
  | None -> None
  | Some index ->
      Some
        (String.sub value 0 index ^ "rewritten by ppx"
       ^ String.sub value (index + marker_length)
           (value_length - index - marker_length))

let expr mapper expression =
  match expression.pexp_desc with
  | Pexp_constant
      {
        pconst_desc = Pconst_string (value, _, delimiter);
        pconst_loc = loc;
      }
    -> (
      match replace_ppx_marker value with
      | Some rewritten ->
      Exp.constant
        {
          pconst_desc = Pconst_string (rewritten, loc, delimiter);
          pconst_loc = loc;
        }
      | None -> default_mapper.expr mapper expression )
  | _ -> default_mapper.expr mapper expression

let () =
  run_main (fun _argv -> { default_mapper with expr })
|}
                "ppx/rewrite.exe"
            in
            ignore
              (write_executable workspace "tools/expand.sh"
                 "#!/bin/sh\nset -eu\nsed 's/__PRE__/pre/g'\n");
            write_manifest workspace
              {|
[preprocess.expand]
argv = ["./tools/expand.sh"]

[ppx.rewrite]
argv = ["./ppx/rewrite.exe"]

[executable.demo]
dir = "app"
main = "main"
preprocess = ["expand"]
ppx = ["rewrite"]
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "__PRE__:__PPX__"|};
            let dump = run_oasis ~cwd:workspace [ "ppx"; "demo"; "main" ] in
            assert_int_equal 0 dump.status
              "ppx should dump transformed source for the requested module";
            assert_string_contains ~needle:"pre:rewritten by ppx" dump.output
              "ppx output should reflect both preprocessor and ppx rewrites";
            assert_string_not_contains ~needle:"__PRE__" dump.output
              "ppx output should not leave the preprocessor marker behind";
            assert_string_not_contains ~needle:"__PPX__" dump.output
              "ppx output should not leave the ppx marker behind")) );
    ( "runs declared actions without compiling target artifacts",
      (fun () ->
        with_temp_dir "oasis-action" (fun workspace ->
            write_manifest workspace
              {|
[action.generate]
argv = ["./tools/generate.sh"]
deps = ["templates/version.txt"]
outputs = ["version.ml"]

[library.core]
dir = "lib"
modules = ["core", "version"]
actions = ["generate"]
|};
            write_source workspace "lib/core.ml" {|let message = Version.value|};
            write_source workspace "templates/version.txt" "action-only\n";
            ignore
              (write_executable workspace "tools/generate.sh"
                 "#!/bin/sh\nset -eu\nvalue=$(cat ../templates/version.txt)\nprintf 'let value = \"%s\"\\n' \"$value\" > version.ml\n");
            let first = run_oasis ~cwd:workspace [ "action"; "core" ] in
            assert_int_equal 0 first.status
              "action should execute declared target actions successfully";
            assert_string_contains
              ~needle:"Generated action outputs for library core ->"
              first.output
              "action should report generated outputs";
            assert_file_exists
              (Filename.concat (Layout.library_out_dir workspace "core")
                 "generated/version.ml");
            assert_true
              (not (Fs.exists (Layout.library_archive workspace "core")))
              "action should not compile library archives while materializing actions";
            let second = run_oasis ~cwd:workspace [ "action"; "core" ] in
            assert_int_equal 0 second.status
              "re-running action should still succeed";
            assert_string_contains ~needle:"Up to date actions for library core ->"
              second.output
              "action should report cached outputs when nothing changed")) );
    ( "runs dependency actions when targeting a downstream executable",
      (fun () ->
        with_temp_dir "oasis-action-dependency" (fun workspace ->
            write_manifest workspace
              {|
[action.generate]
argv = ["./tools/generate.sh"]
deps = ["templates/version.txt"]
outputs = ["version.ml"]

[library.core]
dir = "lib"
modules = ["core", "version"]
actions = ["generate"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "lib/core.ml" {|let message = Version.value|};
            write_source workspace "app/main.ml" {|let () = print_endline Core.message|};
            write_source workspace "templates/version.txt" "dependency\n";
            ignore
              (write_executable workspace "tools/generate.sh"
                 "#!/bin/sh\nset -eu\nvalue=$(cat ../templates/version.txt)\nprintf 'let value = \"%s\"\\n' \"$value\" > version.ml\n");
            let run = run_oasis ~cwd:workspace [ "action"; "demo" ] in
            assert_int_equal 0 run.status
              "action should resolve dependency closures before running actions";
            assert_string_contains
              ~needle:"Generated action outputs for library core ->"
              run.output
              "action should report dependency-library actions when they run";
            assert_file_exists
              (Filename.concat (Layout.library_out_dir workspace "core")
                 "generated/version.ml"))) );
    ( "promotes declared non-source action outputs back into the workspace",
      (fun () ->
        with_temp_dir "oasis-promote" (fun workspace ->
            write_manifest workspace
              {|
[action.snapshot]
argv = ["./tools/snapshot.sh"]
outputs = ["snapshot.txt"]

[library.core]
dir = "lib"
modules = ["core"]
actions = ["snapshot"]
|};
            write_source workspace "lib/core.ml" {|let value = "core"|};
            ignore
              (write_executable workspace "tools/snapshot.sh"
                 "#!/bin/sh\nset -eu\nprintf 'snapshot\\n' > snapshot.txt\n");
            let promote = run_oasis ~cwd:workspace [ "promote"; "core" ] in
            assert_int_equal 0 promote.status
              "promote should materialize and copy declared outputs";
            let promoted_path = Filename.concat workspace "lib/snapshot.txt" in
            let normalized_promoted_path = Fs.realpath promoted_path in
            assert_file_exists promoted_path;
            assert_string_equal "snapshot\n" (Fs.read_file promoted_path)
              "promote should copy generated output contents into the workspace";
            assert_string_contains
              ~needle:(Printf.sprintf
                         "Promoted action snapshot output snapshot.txt for library core -> %s\n"
                         normalized_promoted_path)
              promote.output
              "promote should report each copied output directly")) );
    ( "promotes explicit checked-in generated source outputs back into the workspace",
      (fun () ->
        with_temp_dir "oasis-promote-checked-in-source" (fun workspace ->
            write_manifest workspace
              {|
[action.generate]
argv = ["./tools/generate.sh"]
outputs = ["version.ml"]
checked_in_sources = ["version.ml"]

[library.core]
dir = "lib"
modules = ["core", "version"]
actions = ["generate"]
|};
            write_source workspace "lib/core.ml" {|let message = Version.value|};
            write_source workspace "lib/version.ml" {|let value = "checked-in"|};
            ignore
              (write_executable workspace "tools/generate.sh"
                 "#!/bin/sh\nset -eu\nprintf 'let value = \"generated\"\\n' > version.ml\n");
            let promote = run_oasis ~cwd:workspace [ "promote"; "core" ] in
            assert_int_equal 0 promote.status
              "promote should allow explicitly checked-in generated OCaml sources";
            let promoted_path = Filename.concat workspace "lib/version.ml" in
            let normalized_promoted_path = Fs.realpath promoted_path in
            assert_string_equal "let value = \"generated\"\n"
              (Fs.read_file promoted_path)
              "promote should refresh the checked-in OCaml snapshot";
            assert_string_contains
              ~needle:(Printf.sprintf
                         "Promoted action generate output version.ml for library core -> %s\n"
                         normalized_promoted_path)
              promote.output
              "promote should report checked-in generated source snapshots like other promoted outputs")) );
    ( "rejects promoting source-like action outputs",
      (fun () ->
        with_temp_dir "oasis-promote-source-like" (fun workspace ->
            write_manifest workspace
              {|
[action.generate]
argv = ["./tools/generate.sh"]
outputs = ["version.ml"]

[library.core]
dir = "lib"
modules = ["core", "version"]
actions = ["generate"]
|};
            write_source workspace "lib/core.ml" {|let message = Version.value|};
            ignore
              (write_executable workspace "tools/generate.sh"
                 "#!/bin/sh\nset -eu\nprintf 'let value = \"nope\"\\n' > version.ml\n");
            let promote = run_oasis ~cwd:workspace [ "promote"; "core" ] in
            assert_true (promote.status <> 0)
              "promote should reject source-like outputs that would break future builds";
            assert_string_contains
              ~needle:"declare it under checked_in_sources = [...]"
              promote.output
              "promote should explain how to opt source-like outputs into safe promotion";
            assert_true
              (not (Fs.exists (Filename.concat workspace "lib/version.ml")))
              "promote should not copy rejected source-like outputs into the workspace")) );
    ( "prints top-level usage from the command table",
      (fun () ->
        with_temp_dir "oasis-cli-usage" (fun workspace ->
            let run = run_oasis ~cwd:workspace [] in
            assert_true (run.status <> 0)
              "invoking oasis without a command should print usage";
            assert_string_contains
              ~needle:"oasis init [--dir DIR] [--member PATH] [--name NAME] [--library NAME] [--executable NAME] [--bare] [--force]"
              run.output "top-level usage should include the init command";
            assert_string_contains
              ~needle:"oasis build [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--locked | --warn-locked] [--verbose] [TARGET ...]"
              run.output "top-level usage should include the build command";
            assert_string_contains
              ~needle:"oasis action [--workspace DIR] [--profile NAME] [--verbose] [TARGET ...]"
              run.output "top-level usage should include the action command";
            assert_string_contains
              ~needle:"oasis ppx [--workspace DIR] [--profile NAME] [--verbose] [--interface] [--plan] [--output PATH] TARGET [MODULE]"
              run.output "top-level usage should include the ppx command";
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
              ~needle:"oasis promote [--workspace DIR] [--profile NAME] [--verbose] [TARGET ...]"
              run.output "top-level usage should include the promote command";
            assert_string_contains
              ~needle:"oasis graph [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [TARGET ...]"
              run.output "top-level usage should include the graph command";
            assert_string_contains
              ~needle:"oasis deps [--workspace DIR] [TARGET ...]"
              run.output "top-level usage should include the deps command";
            assert_string_contains
              ~needle:"oasis lock [--workspace DIR] [--output PATH] [--stdout] [TARGET ...]"
              run.output "top-level usage should include the lock command";
            assert_string_contains
              ~needle:"oasis vendor [--workspace DIR] (--source DIR | --git URL | --url URL) [--ref REV] [--checksum VALUE] [--name NAME] [--force]"
              run.output "top-level usage should include the vendor command";
            assert_string_contains
              ~needle:"oasis env [--workspace DIR] [--profile NAME] [--json] [--changed-only] SUBTOOL [TARGET ...]"
              run.output "top-level usage should include the env command";
            assert_string_contains
              ~needle:"oasis repl [--workspace DIR] [--profile NAME] [--verbose] [--plan] [--json] [--script PATH] [TARGET] [-- OCAML_ARG ...]"
              run.output "top-level usage should include the repl command";
            assert_string_contains
              ~needle:"oasis install [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--prefix DIR] [--destdir DIR] [--locked | --warn-locked] [--verbose] [TARGET ...]"
              run.output "top-level usage should include the install command";
            assert_string_contains ~needle:"oasis docs" run.output
              "top-level usage should include the docs command";
            assert_string_contains
              ~needle:"oasis completion [--workspace DIR] SHELL"
              run.output
              "top-level usage should include the completion command";
            assert_string_contains ~needle:"oasis toolchain" run.output
              "top-level usage should include the toolchain command";
            assert_string_contains
              ~needle:"oasis explain [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--current] [--json] [TARGET ...]"
              run.output "top-level usage should include the explain command";
            assert_string_contains
              ~needle:"oasis migrate [--workspace DIR] [--output PATH] [--stdout] [--force]"
              run.output "top-level usage should include the migrate command")) );
    ( "prints command-specific help for explain from the command table",
      (fun () ->
        with_temp_dir "oasis-cli-explain-help" (fun workspace ->
            let help = run_oasis ~cwd:workspace [ "explain"; "--help" ] in
            assert_true (help.status <> 0)
              "explain --help should short-circuit with usage text";
            assert_string_contains
              ~needle:"oasis explain [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--current] [--json] [TARGET ...]"
              help.output "explain help should include the explain signature";
            assert_string_not_contains
              ~needle:"oasis build [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--locked | --warn-locked] [--verbose] [TARGET ...]"
              help.output
              "command-specific help should not include unrelated commands")) );
    ( "prints command-specific help from the command table",
      (fun () ->
        with_temp_dir "oasis-cli-help" (fun workspace ->
            let help = run_oasis ~cwd:workspace [ "build"; "--help" ] in
            assert_true (help.status <> 0)
              "build --help should short-circuit with usage text";
            assert_string_contains
              ~needle:"oasis build [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--locked | --warn-locked] [--verbose] [TARGET ...]"
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
            assert_string_contains ~needle:"## init" docs.output
              "docs output should include the init command";
            assert_string_contains ~needle:"## graph" docs.output
              "docs output should include the graph command";
            assert_string_contains ~needle:"## action" docs.output
              "docs output should include the action command";
            assert_string_contains ~needle:"## ppx" docs.output
              "docs output should include the ppx command";
            assert_string_contains ~needle:"## deps" docs.output
              "docs output should include the deps command";
            assert_string_contains ~needle:"## lock" docs.output
              "docs output should include the lock command";
            assert_string_contains ~needle:"## vendor" docs.output
              "docs output should include the vendor command";
            assert_string_contains ~needle:"## env" docs.output
              "docs output should include the env command";
            assert_string_contains ~needle:"## install" docs.output
              "docs output should include the install command";
            assert_string_contains ~needle:"## promote" docs.output
              "docs output should include the promote command";
            assert_string_contains ~needle:"## migrate" docs.output
              "docs output should include the migrate command";
            assert_string_contains ~needle:"## completion" docs.output
              "docs output should include the completion command";
            assert_string_contains
              ~needle:"- `--prefix DIR`: Stage installed files under DIR instead of the default profile root."
              docs.output
              "docs output should include option descriptions from the command table";
            assert_string_contains
              ~needle:"- `--destdir DIR`: Prepend DIR to the resolved install prefix for packaging-style staging."
              docs.output
              "docs output should include the install destdir description";
            assert_string_contains
              ~needle:"- `--json`: Print machine-readable JSON output instead of the text report."
              docs.output
              "docs output should include the explain JSON description";
            assert_string_contains
              ~needle:"- `--current`: Compute a fresh rebuild explanation from current inputs without compiling, linking, or materializing generated sources."
              docs.output
              "docs output should include the current explain description";
            assert_string_contains
              ~needle:"- `--output PATH`: Write the generated manifest to PATH instead of oasis.toml."
              docs.output
              "docs output should include the migrate output-path description";
            assert_string_contains
              ~needle:"- `--member PATH`: Scaffold a package-local manifest at PATH and register it under members = [...]."
              docs.output
              "docs output should include the member init description";
            assert_string_contains
              ~needle:"- `--locked`: Require oasis.lock to match the current manifest, recorded toolchain facts, and resolved package paths before continuing."
              docs.output
              "docs output should include the strict lock description";
            assert_string_contains
              ~needle:"- `--warn-locked`: Warn when oasis.lock is missing or stale against the current manifest, toolchain facts, or resolved package paths, but continue with the build or install."
              docs.output
              "docs output should include the warning lock description";
            assert_string_contains
              ~needle:"- `--output PATH`: Write the transformed source to PATH instead of stdout."
              docs.output
              "docs output should include the ppx output description";
            assert_string_contains
              ~needle:"- `--stdout`: Print the generated output instead of writing a file."
              docs.output
              "docs output should include the migrate stdout description";
            assert_string_contains
              ~needle:"- `oasis env action core`"
              docs.output
              "docs output should include env action examples from the command table";
            assert_string_contains
              ~needle:"- `oasis env run demo`"
              docs.output
              "docs output should include env examples from the command table")) );
    ( "generates release docs and distributable completion artifacts from the live binary",
      (fun () ->
        with_temp_dir "oasis-cli-release-artifacts" (fun output_dir ->
            let repo_root = Sys.getcwd () in
            let script_path =
              Filename.concat repo_root "scripts/generate_release_artifacts.sh"
            in
            let generated =
              Process.run_capture ~cwd:repo_root
                ~env:[ ("OASIS_BIN", oasis_bin ()) ]
                "bash" [ script_path; "--output-dir"; output_dir ]
            in
            assert_int_equal 0 generated.status
              "release artifact generation should succeed";
            let docs = run_oasis ~cwd:repo_root [ "docs" ] in
            let bash_completion =
              run_oasis ~cwd:repo_root [ "completion"; "bash" ]
            in
            let zsh_completion =
              run_oasis ~cwd:repo_root [ "completion"; "zsh" ]
            in
            let fish_completion =
              run_oasis ~cwd:repo_root [ "completion"; "fish" ]
            in
            assert_int_equal 0 docs.status
              "docs should render successfully before comparing release artifacts";
            assert_int_equal 0 bash_completion.status
              "bash completion should render successfully before comparing release artifacts";
            assert_int_equal 0 zsh_completion.status
              "zsh completion should render successfully before comparing release artifacts";
            assert_int_equal 0 fish_completion.status
              "fish completion should render successfully before comparing release artifacts";
            assert_string_equal docs.output
              (Fs.read_file (Filename.concat output_dir "docs/cli.md"))
              "release docs should come directly from oasis docs";
            assert_string_equal docs.output
              (Fs.read_file
                 (Filename.concat output_dir "package/share/doc/oasis/cli.md"))
              "release artifacts should also stage docs under a package-manager install tree";
            assert_string_equal bash_completion.output
              (Fs.read_file (Filename.concat output_dir "completions/oasis.bash"))
              "packaged bash completion should come directly from oasis completion bash";
            assert_string_equal zsh_completion.output
              (Fs.read_file (Filename.concat output_dir "completions/_oasis"))
              "packaged zsh completion should come directly from oasis completion zsh";
            assert_string_equal fish_completion.output
              (Fs.read_file (Filename.concat output_dir "completions/oasis.fish"))
              "packaged fish completion should come directly from oasis completion fish";
            assert_string_equal bash_completion.output
              (Fs.read_file
                 (Filename.concat output_dir
                    "package/share/bash-completion/completions/oasis"))
              "release artifacts should also stage bash completion under a package-manager install tree";
            assert_string_equal zsh_completion.output
              (Fs.read_file
                 (Filename.concat output_dir
                    "package/share/zsh/site-functions/_oasis"))
              "release artifacts should also stage zsh completion under a package-manager install tree";
            assert_string_equal fish_completion.output
              (Fs.read_file
                 (Filename.concat output_dir
                    "package/share/fish/vendor_completions.d/oasis.fish"))
              "release artifacts should also stage fish completion under a package-manager install tree")) );
    ( "keeps committed release artifacts in sync with the command table",
      (fun () ->
        let repo_root = Sys.getcwd () in
        let docs = run_oasis ~cwd:repo_root [ "docs" ] in
        let bash_completion = run_oasis ~cwd:repo_root [ "completion"; "bash" ] in
        let zsh_completion = run_oasis ~cwd:repo_root [ "completion"; "zsh" ] in
        let fish_completion = run_oasis ~cwd:repo_root [ "completion"; "fish" ] in
        assert_int_equal 0 docs.status
          "docs should render successfully before checking committed artifacts";
        assert_int_equal 0 bash_completion.status
          "bash completion should render successfully before checking committed artifacts";
        assert_int_equal 0 zsh_completion.status
          "zsh completion should render successfully before checking committed artifacts";
        assert_int_equal 0 fish_completion.status
          "fish completion should render successfully before checking committed artifacts";
        assert_string_equal docs.output
          (Fs.read_file (Filename.concat repo_root "docs/cli.md"))
          "the committed CLI reference should stay synced with oasis docs";
        assert_string_equal docs.output
          (Fs.read_file
             (Filename.concat repo_root "package/share/doc/oasis/cli.md"))
          "the committed packaged doc copy should stay synced with oasis docs";
        assert_string_equal bash_completion.output
          (Fs.read_file (Filename.concat repo_root "completions/oasis.bash"))
          "the committed bash completion should stay synced with oasis completion bash";
        assert_string_equal zsh_completion.output
          (Fs.read_file (Filename.concat repo_root "completions/_oasis"))
          "the committed zsh completion should stay synced with oasis completion zsh";
        assert_string_equal fish_completion.output
          (Fs.read_file (Filename.concat repo_root "completions/oasis.fish"))
          "the committed fish completion should stay synced with oasis completion fish";
        assert_string_equal bash_completion.output
          (Fs.read_file
             (Filename.concat repo_root
                "package/share/bash-completion/completions/oasis"))
          "the committed packaged bash completion should stay synced with oasis completion bash";
        assert_string_equal zsh_completion.output
          (Fs.read_file
             (Filename.concat repo_root "package/share/zsh/site-functions/_oasis"))
          "the committed packaged zsh completion should stay synced with oasis completion zsh";
        assert_string_equal fish_completion.output
          (Fs.read_file
             (Filename.concat repo_root
                "package/share/fish/vendor_completions.d/oasis.fish"))
          "the committed packaged fish completion should stay synced with oasis completion fish") );
    ( "queries workspace-local targets and profiles at completion time",
      (fun () ->
        with_temp_dir "oasis-cli-workspace-completion" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
profile = "release"

[profile.dev]

[library.core]
dir = "lib"
modules = ["core"]

[executable.demo]
dir = "app"
main = "main"

[bench.quick]
executable = "demo"

[test.demo_suite]
dir = "test"
main = "main"
|};
            write_source workspace "lib/core.ml" {|let value = "core"|};
            write_source workspace "app/main.ml" {|let () = print_endline "demo"|};
            write_source workspace "test/main.ml" {|let () = print_endline "suite"|};
            with_temp_dir "oasis-cli-workspace-completion-cwd" (fun outside ->
                let target_query =
                  run_oasis ~cwd:outside
                    [ "completion"; "--workspace"; workspace; "--query"; "--current"; ""; "--"; "build" ]
                in
                assert_int_equal 0 target_query.status
                  "completion queries should load workspace-local targets when asked";
                assert_string_contains
                  ~needle:"__oasis_completion\t1\tcandidates\n"
                  target_query.output
                  "completion queries should announce the protocol version";
                assert_string_contains ~needle:"candidate\tcore\n" target_query.output
                  "completion queries should suggest library targets";
                assert_string_contains ~needle:"candidate\tdemo\n" target_query.output
                  "completion queries should suggest executable targets";
                assert_string_contains
                  ~needle:"candidate\tdemo_suite\n" target_query.output
                  "completion queries should suggest test targets";
                let action_query =
                  run_oasis ~cwd:outside
                    [ "completion"; "--workspace"; workspace; "--query"; "--current"; ""; "--"; "action" ]
                in
                assert_int_equal 0 action_query.status
                  "action completion queries should load workspace-local targets";
                assert_string_contains ~needle:"candidate\tcore\n" action_query.output
                  "action completion queries should suggest libraries";
                assert_string_contains ~needle:"candidate\tdemo\n" action_query.output
                  "action completion queries should suggest executables";
                let promote_query =
                  run_oasis ~cwd:outside
                    [ "completion"; "--workspace"; workspace; "--query"; "--current"; ""; "--"; "promote" ]
                in
                assert_int_equal 0 promote_query.status
                  "promote completion queries should load workspace-local targets";
                assert_string_contains ~needle:"candidate\tcore\n"
                  promote_query.output
                  "promote completion queries should suggest libraries";
                let bench_query =
                  run_oasis ~cwd:outside
                    [ "completion"; "--workspace"; workspace; "--query"; "--current"; ""; "--"; "bench" ]
                in
                assert_int_equal 0 bench_query.status
                  "bench completion queries should load declared benchmarks";
                assert_string_contains ~needle:"candidate\tquick\n" bench_query.output
                  "bench completion queries should suggest dedicated bench names";
                assert_string_contains ~needle:"candidate\tdemo\n" bench_query.output
                  "bench completion queries should still suggest executable targets";
                let profile_query =
                  run_oasis ~cwd:outside
                    [
                      "completion";
                      "--workspace";
                      workspace;
                      "--query";
                      "--current";
                      "";
                      "--";
                      "build";
                      "--profile";
                    ]
                in
                assert_int_equal 0 profile_query.status
                  "completion queries should load profile values when asked";
                assert_string_contains
                  ~needle:"candidate\trelease\n" profile_query.output
                  "completion queries should suggest the default profile name";
                assert_string_contains ~needle:"candidate\tdev\n" profile_query.output
                  "completion queries should suggest additional profile names")) ));
    ( "completes env subtools and workspace-local targets",
      (fun () ->
        with_temp_dir "oasis-cli-env-completion" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]

[executable.demo]
dir = "app"
main = "main"

[test.unit]
dir = "test"
main = "main"
|};
            write_source workspace "lib/core.ml" {|let value = "core"|};
            write_source workspace "app/main.ml" {|let () = print_endline "demo"|};
            write_source workspace "test/main.ml" {|let () = print_endline "unit"|};
            let subtools =
              run_oasis ~cwd:workspace
                [ "completion"; "--query"; "--current"; ""; "--"; "env" ]
            in
            assert_int_equal 0 subtools.status
              "env completion should suggest subtools before a target";
            assert_string_contains ~needle:"candidate\tbuild\n" subtools.output
              "env completion should suggest build";
            assert_string_contains ~needle:"candidate\taction\n" subtools.output
              "env completion should suggest action";
            assert_string_contains ~needle:"candidate\trun\n" subtools.output
              "env completion should suggest run";
            let action_targets =
              run_oasis ~cwd:workspace
                [ "completion"; "--query"; "--current"; ""; "--"; "env"; "action" ]
            in
            assert_int_equal 0 action_targets.status
              "env action completion should suggest workspace targets";
            assert_string_contains ~needle:"candidate\tcore\n" action_targets.output
              "env action completion should include libraries";
            assert_string_contains ~needle:"candidate\tdemo\n" action_targets.output
              "env action completion should include executables";
            let run_targets =
              run_oasis ~cwd:workspace
                [ "completion"; "--query"; "--current"; ""; "--"; "env"; "run" ]
            in
            assert_int_equal 0 run_targets.status
              "env run completion should suggest executable targets";
            assert_string_contains ~needle:"candidate\tdemo\n" run_targets.output
              "env run completion should suggest executables";
            assert_string_not_contains ~needle:"candidate\tcore\n" run_targets.output
              "env run completion should not suggest libraries";
            let install_targets =
              run_oasis ~cwd:workspace
                [ "completion"; "--query"; "--current"; ""; "--"; "env"; "install" ]
            in
            assert_int_equal 0 install_targets.status
              "env install completion should suggest installable targets";
            assert_string_contains ~needle:"candidate\tcore\n" install_targets.output
              "env install completion should include libraries";
            assert_string_contains ~needle:"candidate\tdemo\n" install_targets.output
              "env install completion should include executables";
            assert_string_not_contains ~needle:"candidate\tunit\n"
              install_targets.output
              "env install completion should not include tests")) );
    ( "returns versioned directory and file completion protocol headers for path flags",
      (fun () ->
        with_temp_dir "oasis-cli-path-query" (fun workspace ->
            let workspace_query =
              run_oasis ~cwd:workspace
                [ "completion"; "--query"; "--current"; "wo"; "--"; "build"; "--workspace" ]
            in
            assert_int_equal 0 workspace_query.status
              "workspace-directory completion queries should succeed";
            assert_string_equal "__oasis_completion\t1\tdirectories\n"
              workspace_query.output
              "workspace-directory completion should use the versioned directory response";
            let prefix_query =
              run_oasis ~cwd:workspace
                [ "completion"; "--query"; "--current"; "st"; "--"; "install"; "--prefix" ]
            in
            assert_int_equal 0 prefix_query.status
              "prefix completion queries should succeed";
            assert_string_equal "__oasis_completion\t1\tdirectories\n"
              prefix_query.output
              "prefix completion should use the versioned directory response";
            let destdir_query =
              run_oasis ~cwd:workspace
                [ "completion"; "--query"; "--current"; "pk"; "--"; "install"; "--destdir" ]
            in
            assert_int_equal 0 destdir_query.status
              "destdir completion queries should succeed";
            assert_string_equal "__oasis_completion\t1\tdirectories\n"
              destdir_query.output
              "destdir completion should use the versioned directory response";
            let output_query =
              run_oasis ~cwd:workspace
                [ "completion"; "--query"; "--current"; "co"; "--"; "migrate"; "--output" ]
            in
            assert_int_equal 0 output_query.status
              "output-path completion queries should succeed";
            assert_string_equal "__oasis_completion\t1\tfiles\n"
              output_query.output
              "output-path completion should use the versioned file response";
            let script_query =
              run_oasis ~cwd:workspace
                [ "completion"; "--query"; "--current"; "se"; "--"; "repl"; "--script" ]
            in
            assert_int_equal 0 script_query.status
              "script-path completion queries should succeed";
            assert_string_equal "__oasis_completion\t1\tfiles\n"
              script_query.output
              "script-path completion should use the versioned file response")) );
    ( "returns member package paths in described completion queries",
      (fun () ->
        with_temp_dir "oasis-cli-completion-describe" (fun workspace ->
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
            write_source workspace "shared/shared.ml" {|let value = "shared"|};
            write_source workspace "packages/core/lib/core.ml"
              {|let value = Shared.value|};
            write_source workspace "packages/app/app/main.ml"
              {|let () = print_endline Core.value|};
            with_temp_dir "oasis-cli-completion-describe-cwd" (fun outside ->
                let query =
                  run_oasis ~cwd:outside
                    [
                      "completion";
                      "--workspace";
                      workspace;
                      "--query";
                      "--describe";
                      "--current";
                      "";
                      "--";
                      "build";
                    ]
                in
                assert_int_equal 0 query.status
                  "described completion queries should succeed";
                assert_string_contains
                  ~needle:"__oasis_completion\t1\tcandidates\n"
                  query.output
                  "described completion queries should announce the protocol version";
                assert_string_contains ~needle:"candidate\tshared\n" query.output
                  "root targets should still be listed plainly";
                assert_string_contains
                  ~needle:"candidate\tcore\tpackages/core\n"
                  query.output
                  "member library completions should include their package path";
                assert_string_contains
                  ~needle:"candidate\tdemo\tpackages/app\n"
                  query.output
                  "member executable completions should include their package path")) ));
    ( "queries top-level command names outside a workspace",
      (fun () ->
        with_temp_dir "oasis-cli-query-top-level" (fun workspace ->
            let query =
              run_oasis ~cwd:workspace
                [ "completion"; "--query"; "--current"; "bu" ]
            in
            assert_int_equal 0 query.status
              "top-level completion queries should succeed without a manifest";
            assert_string_contains
              ~needle:"__oasis_completion\t1\tcandidates\n"
              query.output
              "top-level completion queries should announce the protocol version";
            assert_string_contains ~needle:"candidate\tbuild\n" query.output
              "top-level completion queries should suggest command names";
            assert_string_not_contains ~needle:"candidate\trun\n" query.output
              "query filtering should preserve the current prefix")) );
    ( "renders bash completions from the command table",
      (fun () ->
        with_temp_dir "oasis-cli-bash-completion" (fun workspace ->
            let completion = run_oasis ~cwd:workspace [ "completion"; "bash" ] in
            assert_int_equal 0 completion.status
              "bash completion generation should succeed";
            assert_string_contains ~needle:"_oasis()" completion.output
              "bash completion output should define the completion function";
            assert_string_contains ~needle:"oasis completion --query"
              completion.output
              "bash completion should query the live workspace at runtime";
            assert_string_contains ~needle:"--describe"
              completion.output
              "bash completion should request described runtime suggestions";
            assert_string_contains
              ~needle:"COMP_WORDS[@]:1:$((COMP_CWORD-1))"
              completion.output
              "bash completion should forward the live command line to the query protocol";
            assert_string_contains ~needle:"_oasis_query" completion.output
              "bash completion should route through a shared runtime query helper";
            assert_string_contains ~needle:"_oasis_show_descriptions"
              completion.output
              "bash completion should provide a description fallback helper";
            assert_string_contains ~needle:"__oasis_completion"
              completion.output
              "bash completion should recognize the versioned completion protocol";
            assert_string_contains ~needle:"read -r protocol version kind"
              completion.output
              "bash completion should parse protocol headers before reading suggestions";
            assert_string_contains ~needle:"compgen -V COMPREPLY -d -- \"$cur\""
              completion.output
              "bash completion should fall back to shell-native directory completion";
            assert_string_contains ~needle:"compgen -V COMPREPLY -f -- \"$cur\""
              completion.output
              "bash completion should fall back to shell-native file completion")) );
    ( "bash completion uses shell-native directory completion for path flags",
      (fun () ->
        with_temp_dir "oasis-cli-bash-paths" (fun workspace ->
            Fs.ensure_dir (Filename.concat workspace "project");
            Fs.ensure_dir (Filename.concat workspace "prefix-dir");
            Fs.write_file (Filename.concat workspace "session.ml") "let () = ()\n";
            let completion = run_oasis ~cwd:workspace [ "completion"; "bash" ] in
            assert_int_equal 0 completion.status
              "bash completion script generation should succeed before runtime checks";
            let bash =
              run_bash_completion ~cwd:workspace completion.output
                "COMP_WORDS=(oasis build --workspace pr)\nCOMP_CWORD=3\n_oasis\nprintf 'reply:%s\\n' \"${COMPREPLY[@]}\"\nCOMP_WORDS=(oasis repl --script se)\nCOMP_CWORD=3\n_oasis\nprintf 'file:%s\\n' \"${COMPREPLY[@]}\"\n"
            in
            assert_int_equal 0 bash.status
              "the bash completion function should succeed for directory flags";
            assert_string_contains ~needle:"reply:project\n" bash.output
              "directory completion should surface matching directories";
            assert_string_contains ~needle:"reply:prefix-dir\n" bash.output
              "directory completion should reuse bash's native directory matcher";
            assert_string_contains ~needle:"file:session.ml\n" bash.output
              "file completion should reuse bash's native file matcher";
            assert_string_not_contains ~needle:"__oasis_completion"
              bash.output
              "the protocol header should stay internal to the completion function")) );
    ( "bash completion prints package-path hints while completing plain target names",
      (fun () ->
        with_temp_dir "oasis-cli-bash-descriptions" (fun workspace ->
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
            write_source workspace "shared/shared.ml" {|let value = "shared"|};
            write_source workspace "packages/core/lib/core.ml"
              {|let value = Shared.value|};
            write_source workspace "packages/app/app/main.ml"
              {|let () = print_endline Core.value|};
            let completion = run_oasis ~cwd:workspace [ "completion"; "bash" ] in
            assert_int_equal 0 completion.status
              "bash completion script generation should succeed before hint checks";
            let bash =
              run_bash_completion ~cwd:workspace completion.output
                "COMP_WORDS=(oasis build \"\")\nCOMP_CWORD=2\n_oasis\nprintf 'reply:%s\\n' \"${COMPREPLY[@]}\"\n"
            in
            assert_int_equal 0 bash.status
              "the bash completion function should succeed for target queries";
            assert_string_contains ~needle:"core\tpackages/core\n" bash.output
              "bash completion should surface member package hints";
            assert_string_contains ~needle:"demo\tpackages/app\n" bash.output
              "bash completion should print executable package hints as fallback descriptions";
            assert_string_contains ~needle:"reply:core\n" bash.output
              "bash completion should still complete plain target names";
            assert_string_contains ~needle:"reply:demo\n" bash.output
              "bash completion should keep completion values separate from descriptions";
            assert_string_not_contains ~needle:"reply:core\tpackages/core"
              bash.output
              "bash completion should not inject package hints into inserted words")) );
    ( "renders zsh completions from the command table",
      (fun () ->
        with_temp_dir "oasis-cli-zsh-completion" (fun workspace ->
            let completion = run_oasis ~cwd:workspace [ "completion"; "zsh" ] in
            assert_int_equal 0 completion.status
              "zsh completion generation should succeed";
            assert_string_contains ~needle:"#compdef oasis" completion.output
              "zsh completion output should declare the compdef";
            assert_string_contains ~needle:"oasis completion --query"
              completion.output
              "zsh completion should query the live workspace at runtime";
            assert_string_contains ~needle:"--describe"
              completion.output
              "zsh completion should request described runtime suggestions";
            assert_string_contains ~needle:"words[2,CURRENT-1]" completion.output
              "zsh completion should forward prior words to the query protocol";
            assert_string_contains ~needle:"_describe 'value' suggestions"
              completion.output
              "zsh completion should describe runtime query suggestions";
            assert_string_contains ~needle:"read -r protocol version kind"
              completion.output
              "zsh completion should parse protocol headers before describing suggestions";
            assert_string_contains ~needle:"_files -/"
              completion.output
              "zsh completion should delegate directory-valued flags to native path completion";
            assert_string_contains ~needle:"if [[ \"$kind\" == files ]]; then"
              completion.output
              "zsh completion should recognize file-valued path queries")) );
    ( "renders fish completions from the command table",
      (fun () ->
        with_temp_dir "oasis-cli-fish-completion" (fun workspace ->
            let completion = run_oasis ~cwd:workspace [ "completion"; "fish" ] in
            assert_int_equal 0 completion.status
              "fish completion generation should succeed";
            assert_string_contains
              ~needle:"complete -c oasis -f -a '(__oasis_complete)'"
              completion.output
              "fish completion should delegate to the runtime query helper";
            assert_string_contains
              ~needle:"commandline -opc"
              completion.output
              "fish completion should forward committed words to the query protocol";
            assert_string_contains ~needle:"oasis completion --query"
              completion.output
              "fish completion should query the live workspace at runtime";
            assert_string_contains ~needle:"--describe"
              completion.output
              "fish completion should request described runtime suggestions";
            assert_string_contains ~needle:"set -l tab (printf '\\t')"
              completion.output
              "fish completion should define a tab separator for protocol parsing";
            assert_string_contains ~needle:"string split $tab -- $response[1]"
              completion.output
              "fish completion should parse protocol headers before forwarding results";
            assert_string_contains ~needle:"__fish_complete_directories"
              completion.output
              "fish completion should delegate directory-valued flags to native path completion";
            assert_string_contains ~needle:"__fish_complete_path"
              completion.output
              "fish completion should delegate file-valued flags to native path completion")) );
    ( "executes zsh completion runtime branches for described, directory, and file completions",
      (fun () ->
        with_temp_dir "oasis-cli-zsh-runtime" (fun workspace ->
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
            write_source workspace "shared/shared.ml" {|let value = "shared"|};
            write_source workspace "packages/core/lib/core.ml"
              {|let value = Shared.value|};
            write_source workspace "packages/app/app/main.ml"
              {|let () = print_endline Core.value|};
            Fs.ensure_dir (Filename.concat workspace "project");
            Fs.write_file (Filename.concat workspace "session.ml") "let () = ()\n";
            let completion = run_oasis ~cwd:workspace [ "completion"; "zsh" ] in
            assert_int_equal 0 completion.status
              "zsh completion script generation should succeed before runtime checks";
            let zsh =
              run_zsh_completion ~cwd:workspace completion.output
                "function _describe() {\n  local tag=\"$1\"\n  local array_name=\"$2\"\n  local -a items\n  items=(\"${(@P)array_name}\")\n  printf 'tag:%s\\n' \"$tag\"\n  printf 'suggestion:%s\\n' \"$items[@]\"\n}\nfunction _files() {\n  printf 'files:%s\\n' \"$*\"\n}\nwords=(oasis build '')\nCURRENT=3\n_oasis\nwords=(oasis build --workspace pr)\nCURRENT=4\n_oasis\nwords=(oasis repl --script se)\nCURRENT=4\n_oasis\n"
            in
            assert_int_equal 0 zsh.status
              "the zsh completion function should execute successfully";
            assert_string_contains ~needle:"tag:value\n" zsh.output
              "zsh completion should route described candidates through _describe";
            assert_string_contains ~needle:"suggestion:core:packages/core\n"
              zsh.output
              "zsh runtime completion should surface member package hints";
            assert_string_contains ~needle:"suggestion:demo:packages/app\n"
              zsh.output
              "zsh runtime completion should include executable package hints";
            assert_string_contains ~needle:"files:-/\n" zsh.output
              "zsh runtime completion should delegate directory path flags to _files";
            assert_string_contains ~needle:"files:\n" zsh.output
              "zsh runtime completion should delegate file path flags to _files without the directory filter")) );
    ( "executes fish completion runtime branches for described, directory, and file completions",
      (fun () ->
        with_temp_dir "oasis-cli-fish-runtime" (fun workspace ->
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
            write_source workspace "shared/shared.ml" {|let value = "shared"|};
            write_source workspace "packages/core/lib/core.ml"
              {|let value = Shared.value|};
            write_source workspace "packages/app/app/main.ml"
              {|let () = print_endline Core.value|};
            Fs.ensure_dir (Filename.concat workspace "project");
            Fs.write_file (Filename.concat workspace "session.ml") "let () = ()\n";
            let completion = run_oasis ~cwd:workspace [ "completion"; "fish" ] in
            assert_int_equal 0 completion.status
              "fish completion script generation should succeed before runtime checks";
            let fish =
              run_fish_completion ~cwd:workspace completion.output
                "set -g oasis_mode described\nfunction commandline\n  switch $argv[1]\n    case -opc\n      switch $oasis_mode\n        case described\n          echo oasis\n          echo build\n        case path\n          echo oasis\n          echo build\n          echo --workspace\n        case file\n          echo oasis\n          echo repl\n          echo --script\n      end\n    case -ct\n      switch $oasis_mode\n        case described\n          echo ''\n        case path\n          echo pr\n        case file\n          echo se\n      end\n  end\nend\nfunction __fish_complete_directories\n  printf 'dir:%s\\n' $argv\nend\nfunction __fish_complete_path\n  printf 'file:%s\\n' $argv\nend\n__oasis_complete\nset -g oasis_mode path\n__oasis_complete\nset -g oasis_mode file\n__oasis_complete\n"
            in
            assert_int_equal 0 fish.status
              "the fish completion function should execute successfully";
            assert_string_contains ~needle:"core\tpackages/core\n" fish.output
              "fish runtime completion should surface member package hints";
            assert_string_contains ~needle:"demo\tpackages/app\n" fish.output
              "fish runtime completion should include executable package hints";
            assert_string_contains ~needle:"dir:pr\n" fish.output
              "fish runtime completion should delegate directory flags to the native directory completer";
            assert_string_contains ~needle:"file:se\n" fish.output
              "fish runtime completion should delegate file flags to the native file completer")) );
    ( "binds generated completion scripts to an explicit workspace when requested",
      (fun () ->
        with_temp_dir "oasis-cli-completion-workspace-script" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
|};
            write_source workspace "lib/core.ml" {|let value = 1|};
            with_temp_dir "oasis-cli-completion-workspace-script-cwd" (fun outside ->
                let completion =
                  run_oasis ~cwd:outside
                    [ "completion"; "--workspace"; workspace; "bash" ]
                in
                assert_int_equal 0 completion.status
                  "workspace-bound completion script generation should succeed";
                assert_string_contains
                  ~needle:("--workspace " ^ Filename.quote workspace)
                  completion.output
                  "generated completion scripts should preserve the requested workspace binding";
                assert_string_not_contains ~needle:"core\n" completion.output
                  "runtime completion scripts should not snapshot workspace nouns into the script body")) ));
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
