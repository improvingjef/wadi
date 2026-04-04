open Test_support

let write_executable workspace relative_path contents =
  let path = Filename.concat workspace relative_path in
  Fs.write_file path contents;
  Unix.chmod path 0o755;
  path

let resolve_command prog =
  let outcome = Process.run_capture "/bin/sh" [ "-c"; "command -v " ^ prog ] in
  assert_int_equal 0 outcome.status (Printf.sprintf "expected to find %s on PATH" prog);
  String.trim outcome.output

let cases =
  [
    ( "resolves executables from PATH and absolute paths",
      fun () ->
        let shell_path =
          match Toolchain.resolve_executable_path "/bin/sh" with
          | Some path -> path
          | None -> fail "expected /bin/sh to resolve as an executable path"
        in
        assert_string_equal "/bin/sh" shell_path
          "absolute executable paths should round-trip";
        match Toolchain.resolve_executable_path "ocamlc" with
        | Some _ -> ()
        | None -> fail "expected ocamlc to resolve from PATH" );
    ( "prints a toolchain report without requiring a manifest",
      fun () ->
        with_temp_dir "wadi-toolchain" (fun workspace ->
            let run = run_wadi ~cwd:workspace [ "toolchain" ] in
            assert_int_equal 0 run.status
              "toolchain diagnostics should succeed without a workspace manifest";
            assert_string_contains ~needle:"ocamlc: " run.output
              "toolchain output should report ocamlc";
            assert_string_contains ~needle:"ocamlopt: " run.output
              "toolchain output should report ocamlopt";
            assert_string_contains ~needle:"ocamldep: " run.output
              "toolchain output should report ocamldep";
            assert_string_contains ~needle:"ocamlfind: " run.output
              "toolchain output should report ocamlfind";
            assert_string_contains ~needle:"selected-backend: " run.output
              "toolchain output should report the selected backend";
            assert_string_contains ~needle:"stdlib: " run.output
              "toolchain output should report the stdlib path";
            assert_string_contains ~needle:"package-roots:" run.output
              "toolchain output should report ocamlfind package roots";
            assert_string_contains
              ~needle:"toolchain-consistency: compiler and package roots agree"
              run.output "toolchain output should report toolchain consistency") );
    ( "falls back to the compiler switch ocamlfind when the configured driver is \
       inconsistent",
      fun () ->
        with_temp_dir "wadi-toolchain-ocamlfind-fallback" (fun workspace ->
            let inconsistent_ocamlfind =
              write_executable workspace "bin/ocamlfind-homebrew"
                "#!/bin/sh\n\
                 set -eu\n\
                 if [ \"$#\" -ge 2 ] && [ \"$1\" = \"printconf\" ] && [ \"$2\" = \
                 \"path\" ]; then\n\
                 \  printf '/opt/homebrew/lib/ocaml\\n'\n\
                 else\n\
                 \  echo unexpected invocation >&2\n\
                 \  exit 2\n\
                 fi\n"
            in
            let expected_ocamlfind = resolve_command "ocamlfind" in
            let run =
              with_env "OCAMLFIND" inconsistent_ocamlfind (fun () ->
                  run_wadi ~cwd:workspace [ "toolchain" ])
            in
            assert_int_equal 0 run.status
              "toolchain diagnostics should recover from an inconsistent configured \
               ocamlfind";
            assert_string_contains
              ~needle:
                (Printf.sprintf "ocamlfind: %s (configured as %s)" expected_ocamlfind
                   inconsistent_ocamlfind)
              run.output
              "toolchain diagnostics should prefer the compiler switch ocamlfind";
            assert_string_contains
              ~needle:"toolchain-consistency: compiler and package roots agree"
              run.output
              "toolchain diagnostics should report a healthy effective toolchain") );
    ( "falls back to the bytecode backend when native compilation is unavailable",
      fun () ->
        with_env "OCAMLOPT" "/definitely/missing/ocamlopt" (fun () ->
            match Toolchain.resolve_backend Toolchain.Auto with
            | Ok Toolchain.Bytecode -> ()
            | Ok backend ->
                fail
                  (Printf.sprintf "expected bytecode fallback but resolved %s"
                     (Toolchain.backend_name backend))
            | Error message ->
                fail ("expected bytecode fallback but resolution failed: " ^ message)) );
    ( "prints command-specific help for the toolchain subcommand",
      fun () ->
        with_temp_dir "wadi-toolchain-help" (fun workspace ->
            let help = run_wadi ~cwd:workspace [ "toolchain"; "--help" ] in
            assert_true (help.status <> 0)
              "toolchain --help should short-circuit with usage";
            assert_string_contains ~needle:"wadi toolchain" help.output
              "toolchain help should include the toolchain signature";
            assert_string_not_contains
              ~needle:
                "wadi build [--workspace DIR] [--profile NAME] [--backend \
                 auto|native|bytecode] [--locked | --warn-locked] [--keep-going] \
                 [--verbose] [TARGET ...]"
              help.output "toolchain help should stay scoped to the requested command") );
  ]
