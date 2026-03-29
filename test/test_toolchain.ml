open Test_support

let cases =
  [
    ( "resolves executables from PATH and absolute paths",
      (fun () ->
        let shell_path =
          match Toolchain.resolve_executable_path "/bin/sh" with
          | Some path -> path
          | None -> fail "expected /bin/sh to resolve as an executable path"
        in
        assert_string_equal "/bin/sh" shell_path
          "absolute executable paths should round-trip";
        match Toolchain.resolve_executable_path "ocamlc" with
        | Some _ -> ()
        | None -> fail "expected ocamlc to resolve from PATH")) ;
    ( "prints a toolchain report without requiring a manifest",
      (fun () ->
        with_temp_dir "oasis-toolchain" (fun workspace ->
            let run = run_oasis ~cwd:workspace [ "toolchain" ] in
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
              "toolchain output should report ocamlfind package roots")) );
    ( "falls back to the bytecode backend when native compilation is unavailable",
      (fun () ->
        with_env "OCAMLOPT" "/definitely/missing/ocamlopt" (fun () ->
            match Toolchain.resolve_backend Toolchain.Auto with
            | Ok Toolchain.Bytecode -> ()
            | Ok backend ->
                fail
                  (Printf.sprintf
                     "expected bytecode fallback but resolved %s"
                     (Toolchain.backend_name backend))
            | Error message ->
                fail
                  ("expected bytecode fallback but resolution failed: " ^ message)))) ;
    ( "prints command-specific help for the toolchain subcommand",
      (fun () ->
        with_temp_dir "oasis-toolchain-help" (fun workspace ->
            let help = run_oasis ~cwd:workspace [ "toolchain"; "--help" ] in
            assert_true (help.status <> 0)
              "toolchain --help should short-circuit with usage";
            assert_string_contains ~needle:"oasis toolchain" help.output
              "toolchain help should include the toolchain signature";
            assert_string_not_contains
              ~needle:"oasis build [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET ...]"
              help.output
              "toolchain help should stay scoped to the requested command")) );
  ]
