open Test_support

let cases =
  [
    ( "initializes a runnable executable workspace",
      fun () ->
        with_temp_dir "oasis-init-exec" (fun parent ->
            let workspace = Filename.concat parent "demo" in
            let init =
              run_oasis ~cwd:parent
                [ "init"; "--dir"; workspace; "--name"; "demo" ]
            in
            assert_int_equal 0 init.status
              "init should scaffold a default executable workspace";
            assert_string_contains ~needle:"Initialized workspace demo at"
              init.output "init should report the scaffold root";
            assert_file_exists (Filename.concat workspace "oasis.toml");
            assert_file_exists (Filename.concat workspace "app/main.ml");
            let run = run_oasis ~cwd:workspace [ "run" ] in
            assert_int_equal 0 run.status
              "the default executable scaffold should build and run";
            assert_string_contains ~needle:"Hello from demo\n" run.output
              "the executable scaffold should print the generated greeting") );
    ( "initializes combined library and executable workspaces",
      fun () ->
        with_temp_dir "oasis-init-combo" (fun parent ->
            let workspace = Filename.concat parent "combo" in
            let init =
              run_oasis ~cwd:parent
                [
                  "init";
                  "--dir";
                  workspace;
                  "--name";
                  "combo";
                  "--library";
                  "core";
                  "--executable";
                  "demo";
                ]
            in
            assert_int_equal 0 init.status
              "init should scaffold linked library and executable targets";
            assert_file_exists (Filename.concat workspace "lib/core.ml");
            assert_file_exists (Filename.concat workspace "app/main.ml");
            let run = run_oasis ~cwd:workspace [ "run"; "demo" ] in
            assert_int_equal 0 run.status
              "the combined scaffold should build and run";
            assert_string_contains ~needle:"Hello from combo\n" run.output
              "the executable scaffold should call into the generated library") );
    ( "refuses to overwrite existing scaffold paths without force",
      fun () ->
        with_temp_dir "oasis-init-force" (fun parent ->
            let workspace = Filename.concat parent "demo" in
            Fs.ensure_dir workspace;
            write_workspace_file workspace "app/main.ml" {|let () = print_endline "old"|};
            let first =
              run_oasis ~cwd:parent
                [ "init"; "--dir"; workspace; "--name"; "demo" ]
            in
            assert_true (first.status <> 0)
              "init should fail when scaffold files already exist";
            assert_string_contains ~needle:"rerun with --force" first.output
              "init should explain how to replace an existing scaffold";
            let second =
              run_oasis ~cwd:parent
                [ "init"; "--dir"; workspace; "--name"; "demo"; "--force" ]
            in
            assert_int_equal 0 second.status
              "init --force should replace existing scaffold files";
            let run = run_oasis ~cwd:workspace [ "run" ] in
            assert_int_equal 0 run.status
              "the forced scaffold should still build and run";
            assert_string_contains ~needle:"Hello from demo\n" run.output
              "force should replace old sources with the new scaffold") );
    ( "initializes bare workspaces without source files",
      fun () ->
        with_temp_dir "oasis-init-bare" (fun parent ->
            let workspace = Filename.concat parent "bare" in
            let init =
              run_oasis ~cwd:parent
                [ "init"; "--dir"; workspace; "--name"; "bare"; "--bare" ]
            in
            assert_int_equal 0 init.status
              "init --bare should write only the root manifest";
            assert_file_exists (Filename.concat workspace "oasis.toml");
            assert_true
              (not (Fs.exists (Filename.concat workspace "app/main.ml")))
              "bare scaffolds should not create executable sources";
            assert_true
              (not (Fs.exists (Filename.concat workspace "lib")))
              "bare scaffolds should not create library trees") );
  ]
