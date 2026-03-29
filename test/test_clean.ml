open Test_support

let executable_path workspace name =
  Layout.executable_binary workspace name

let library_archive_path workspace name =
  Layout.library_archive workspace name

let oasis_root = Layout.artifact_root

let cases =
  [
    ( "removes the full workspace artifact tree",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "build should succeed before a workspace clean";
            assert_true (Fs.is_directory (oasis_root workspace))
              "build should create the workspace artifact directory";
            let clean = run_oasis ~cwd:workspace [ "clean" ] in
            assert_int_equal 0 clean.status
              "full workspace clean should succeed";
            assert_true (not (Fs.exists (oasis_root workspace)))
              "full workspace clean should remove the entire artifact tree";
            assert_string_contains ~needle:"Removed workspace artifacts"
              clean.output
              "full workspace clean should report the removed artifact root")) );
    ( "removes only the requested target artifacts",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "build should succeed before a selective clean";
            assert_file_exists (library_archive_path workspace "greeting");
            assert_file_exists (executable_path workspace "hello");
            let clean = run_oasis ~cwd:workspace [ "clean"; "hello" ] in
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
            let clean = run_oasis ~cwd:workspace [ "clean"; "missing" ] in
            assert_true (clean.status <> 0)
              "clean should reject unknown targets";
            assert_string_contains ~needle:"unknown target 'missing'" clean.output
              "clean should report unknown targets directly")) );
    ( "reports when requested targets have no artifacts",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let clean = run_oasis ~cwd:workspace [ "clean"; "hello" ] in
            assert_int_equal 0 clean.status
              "clean should tolerate missing target artifacts";
            assert_string_contains ~needle:"No artifacts for executable hello"
              clean.output
              "clean should report when nothing exists for a requested target";
            assert_string_contains
              ~needle:"Nothing to clean for the requested targets" clean.output
              "clean should summarize when no requested targets were removed")) );
  ]
