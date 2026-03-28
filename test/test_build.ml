open Test_support

let executable_path workspace name =
  Filename.concat workspace ("_oasis/build/default/exe/" ^ name ^ "/" ^ name)

let library_archive_path workspace name =
  Filename.concat workspace
    ("_oasis/build/default/lib/" ^ name ^ "/lib" ^ name ^ ".cmxa")

let cases =
  [
    ( "builds and runs the hello fixture",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status "hello fixture should build cleanly";
            assert_string_contains ~needle:"Built library greeting" build.output
              "library build output should be reported";
            let executable = executable_path workspace "hello" in
            assert_file_exists executable;
            let run = run_binary executable [] in
            assert_int_equal 0 run.status
              "built hello executable should run successfully";
            assert_string_equal "Hello, world!\n" run.output
              "built hello executable should print the greeting")) );
    ( "links transitive library dependencies",
      (fun () ->
        with_fixture "transitive" (fun workspace ->
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "transitive fixture should build cleanly";
            let executable = executable_path workspace "demo" in
            assert_file_exists executable;
            let run = run_binary executable [] in
            assert_int_equal 0 run.status
              "transitive executable should run successfully";
            assert_string_equal "Hello, transitive world!\n" run.output
              "transitive libraries should be linked in executable output")) );
    ( "builds a requested library without unrelated executables",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_oasis ~cwd:workspace [ "build"; "greeting" ] in
            assert_int_equal 0 build.status
              "selective library builds should succeed";
            assert_file_exists (library_archive_path workspace "greeting");
            assert_true
              (not (Fs.exists (executable_path workspace "hello")))
              "building a library target should not build unrelated executables")))
    ;
    ( "reports missing source files",
      (fun () ->
        with_temp_dir "oasis-missing" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
|};
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_true (build.status <> 0)
              "missing source files should fail the build";
            assert_string_contains ~needle:"missing source file" build.output
              "missing source files should produce a direct error")) );
  ]
