open Test_support

let executable_path workspace name =
  Layout.executable_binary workspace name

let profile_executable_path workspace profile name =
  Layout.executable_binary ~profile workspace name

let library_archive_path workspace name =
  Layout.library_archive workspace name

let wadi_root = Layout.artifact_root

let cases =
  [
    ( "removes the full workspace artifact tree",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "build should succeed before a workspace clean";
            assert_true (Fs.is_directory (wadi_root workspace))
              "build should create the workspace artifact directory";
            let clean = run_wadi ~cwd:workspace [ "clean" ] in
            assert_int_equal 0 clean.status
              "full workspace clean should succeed";
            assert_true (not (Fs.exists (wadi_root workspace)))
              "full workspace clean should remove the entire artifact tree";
            assert_string_contains ~needle:"Removed workspace artifacts"
              clean.output
              "full workspace clean should report the removed artifact root")) );
    ( "removes only the requested target artifacts",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "build should succeed before a selective clean";
            assert_file_exists (library_archive_path workspace "greeting");
            assert_file_exists (executable_path workspace "hello");
            let clean = run_wadi ~cwd:workspace [ "clean"; "hello" ] in
            assert_int_equal 0 clean.status
              "selective clean should succeed";
            assert_true (not (Fs.exists (executable_path workspace "hello")))
              "selective clean should remove the requested executable";
            assert_file_exists (library_archive_path workspace "greeting");
            assert_string_contains ~needle:"Removed executable hello"
              clean.output
              "selective clean should identify the removed target")) );
    ( "reports unknown clean targets clearly",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let clean = run_wadi ~cwd:workspace [ "clean"; "missing" ] in
            assert_true (clean.status <> 0)
              "clean should reject unknown targets";
            assert_string_contains ~needle:"unknown target 'missing'" clean.output
              "clean should report unknown targets directly")) );
    ( "reports when requested targets have no artifacts",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let clean = run_wadi ~cwd:workspace [ "clean"; "hello" ] in
            assert_int_equal 0 clean.status
              "clean should tolerate missing target artifacts";
            assert_string_contains ~needle:"No artifacts for executable hello"
              clean.output
              "clean should report when nothing exists for a requested target";
            assert_string_contains
              ~needle:"Nothing to clean for the requested targets" clean.output
              "clean should summarize when no requested targets were removed")) );
    ( "cleans only the requested profile root",
      (fun () ->
        with_temp_dir "wadi-clean-profile" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
profile = "release"

[profile.dev]
compile_flags = ["-annot"]

[executable.demo]
dir = "app"
main = "main"
|};
            write_workspace_file workspace "app/main.ml"
              {|let () = print_endline "profile-clean"|};
            let release_build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 release_build.status
              "the default profile should build before profile-specific cleaning";
            let dev_build =
              run_wadi ~cwd:workspace [ "build"; "--profile"; "dev" ]
            in
            assert_int_equal 0 dev_build.status
              "an alternate profile should build before selective cleaning";
            assert_file_exists (profile_executable_path workspace "release" "demo");
            assert_file_exists (profile_executable_path workspace "dev" "demo");
            let clean = run_wadi ~cwd:workspace [ "clean"; "--profile"; "dev" ] in
            assert_int_equal 0 clean.status
              "profile-specific cleaning should succeed";
            assert_true
              (not (Fs.exists (profile_executable_path workspace "dev" "demo")))
              "clean --profile should remove only the selected profile root";
            assert_file_exists (profile_executable_path workspace "release" "demo");
            assert_string_contains ~needle:"Removed profile dev artifacts"
              clean.output
              "profile-specific cleaning should report the removed profile root")) );
  ]
