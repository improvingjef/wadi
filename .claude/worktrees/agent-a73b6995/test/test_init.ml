open Test_support

let cases =
  [
    ( "initializes a runnable executable workspace",
      fun () ->
        with_temp_dir "wadi-init-exec" (fun parent ->
            let workspace = Filename.concat parent "demo" in
            let init =
              run_wadi ~cwd:parent
                [ "init"; "--dir"; workspace; "--name"; "demo" ]
            in
            assert_int_equal 0 init.status
              "init should scaffold a default executable workspace";
            assert_string_contains ~needle:"Initialized workspace demo at"
              init.output "init should report the scaffold root";
            assert_file_exists (Filename.concat workspace "wadi.toml");
            assert_file_exists (Filename.concat workspace "app/main.ml");
            let run = run_wadi ~cwd:workspace [ "run" ] in
            assert_int_equal 0 run.status
              "the default executable scaffold should build and run";
            assert_string_contains ~needle:"Hello from demo\n" run.output
              "the executable scaffold should print the generated greeting") );
    ( "initializes combined library and executable workspaces",
      fun () ->
        with_temp_dir "wadi-init-combo" (fun parent ->
            let workspace = Filename.concat parent "combo" in
            let init =
              run_wadi ~cwd:parent
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
            let run = run_wadi ~cwd:workspace [ "run"; "demo" ] in
            assert_int_equal 0 run.status
              "the combined scaffold should build and run";
            assert_string_contains ~needle:"Hello from combo\n" run.output
              "the executable scaffold should call into the generated library") );
    ( "refuses to overwrite existing scaffold paths without force",
      fun () ->
        with_temp_dir "wadi-init-force" (fun parent ->
            let workspace = Filename.concat parent "demo" in
            Fs.ensure_dir workspace;
            write_workspace_file workspace "app/main.ml" {|let () = print_endline "old"|};
            let first =
              run_wadi ~cwd:parent
                [ "init"; "--dir"; workspace; "--name"; "demo" ]
            in
            assert_true (first.status <> 0)
              "init should fail when scaffold files already exist";
            assert_string_contains ~needle:"rerun with --force" first.output
              "init should explain how to replace an existing scaffold";
            let second =
              run_wadi ~cwd:parent
                [ "init"; "--dir"; workspace; "--name"; "demo"; "--force" ]
            in
            assert_int_equal 0 second.status
              "init --force should replace existing scaffold files";
            let run = run_wadi ~cwd:workspace [ "run" ] in
            assert_int_equal 0 run.status
              "the forced scaffold should still build and run";
            assert_string_contains ~needle:"Hello from demo\n" run.output
              "force should replace old sources with the new scaffold") );
    ( "initializes bare workspaces without source files",
      fun () ->
        with_temp_dir "wadi-init-bare" (fun parent ->
            let workspace = Filename.concat parent "bare" in
            let init =
              run_wadi ~cwd:parent
                [ "init"; "--dir"; workspace; "--name"; "bare"; "--bare" ]
            in
            assert_int_equal 0 init.status
              "init --bare should write only the root manifest";
            assert_file_exists (Filename.concat workspace "wadi.toml");
            assert_true
              (not (Fs.exists (Filename.concat workspace "app/main.ml")))
              "bare scaffolds should not create executable sources";
            assert_true
              (not (Fs.exists (Filename.concat workspace "lib")))
              "bare scaffolds should not create library trees") );
    ( "initializes and registers member packages inside an existing workspace",
      fun () ->
        with_temp_dir "wadi-init-member" (fun parent ->
            let workspace = Filename.concat parent "mono" in
            let root =
              run_wadi ~cwd:parent
                [ "init"; "--dir"; workspace; "--name"; "mono"; "--bare" ]
            in
            assert_int_equal 0 root.status
              "the root workspace scaffold should succeed before member init";
            let init =
              run_wadi ~cwd:parent
                [
                  "init";
                  "--dir";
                  workspace;
                  "--member";
                  "packages/app";
                  "--executable";
                  "demo";
                ]
            in
            assert_int_equal 0 init.status
              "init --member should scaffold package-local targets";
            assert_string_contains ~needle:"Registered workspace member packages/app"
              init.output
              "member init should report root manifest registration";
            assert_file_exists (Filename.concat workspace "packages/app/wadi.toml");
            assert_file_exists (Filename.concat workspace "packages/app/app/main.ml");
            assert_string_contains ~needle:{|members = ["packages/app"]|}
              (Fs.read_file (manifest_path workspace))
              "member init should register the member path in the root manifest";
            let run = run_wadi ~cwd:workspace [ "run"; "demo" ] in
            assert_int_equal 0 run.status
              "member scaffolds should build from the workspace root immediately";
            assert_string_contains ~needle:"Hello from app\n" run.output
              "member executables should use the member scaffold greeting") );
    ( "can bootstrap a multi-package workspace root and member in one command",
      fun () ->
        with_temp_dir "wadi-init-member-root" (fun parent ->
            let workspace = Filename.concat parent "mono" in
            let init =
              run_wadi ~cwd:parent
                [
                  "init";
                  "--dir";
                  workspace;
                  "--name";
                  "mono";
                  "--member";
                  "packages/core";
                  "--library";
                  "core";
                ]
            in
            assert_int_equal 0 init.status
              "init --member should create a missing workspace root";
            assert_file_exists (manifest_path workspace);
            assert_file_exists (Filename.concat workspace "packages/core/wadi.toml");
            assert_string_contains ~needle:{|workspace = "mono"|}
              (Fs.read_file (manifest_path workspace))
              "member bootstrapping should still name the root workspace";
            assert_string_contains ~needle:{|members = ["packages/core"]|}
              (Fs.read_file (manifest_path workspace))
              "member bootstrapping should create the initial members list";
            assert_string_not_contains ~needle:"workspace ="
              (Fs.read_file (Filename.concat workspace "packages/core/wadi.toml"))
              "member manifests should stay package-local";
            let build = run_wadi ~cwd:workspace [ "build"; "core" ] in
            assert_int_equal 0 build.status
              "the bootstrapped member workspace should build immediately";
            assert_string_contains ~needle:"Built library core" build.output
              "the bootstrapped library member should compile from the root") );
  ]
