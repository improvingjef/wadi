open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let assert_one_file_exists paths message =
  if not (List.exists Fs.exists paths) then
    fail
      (Printf.sprintf "%s\nexpected one of:\n%s" message
         (String.concat "\n" paths))

let cases =
  [
    ( "installs libraries, executables, and metadata into a prefix",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let prefix = Filename.concat workspace "_stage" in
            let install =
              run_oasis ~cwd:workspace [ "install"; "--prefix"; prefix ]
            in
            assert_int_equal 0 install.status
              "install should stage the default installable targets";
            let installed_binary = Filename.concat prefix "bin/hello" in
            assert_file_exists installed_binary;
            assert_file_exists (Filename.concat prefix "lib/greeting/greeting.cmi");
            assert_one_file_exists
              [
                Filename.concat prefix "lib/greeting/libgreeting.cmxa";
                Filename.concat prefix "lib/greeting/libgreeting.cma";
              ]
              "install should stage a compiled library archive";
            let metadata_path =
              Filename.concat prefix "share/oasis/hello/install.json"
            in
            assert_file_exists metadata_path;
            assert_file_exists
              (Filename.concat prefix "share/oasis/hello/oasis.toml");
            let metadata = Fs.read_file metadata_path in
            assert_string_contains ~needle:"\"workspace\": \"hello\"" metadata
              "install metadata should record the workspace name";
            assert_string_contains ~needle:"\"name\": \"greeting\"" metadata
              "install metadata should record installed libraries";
            assert_string_contains ~needle:"\"path\": \"bin/hello\"" metadata
              "install metadata should record installed executables";
            let run = run_binary installed_binary [] in
            assert_int_equal 0 run.status
              "installed executables should remain runnable from the staged prefix";
            assert_string_equal "Hello, world!\n" run.output
              "the staged executable should preserve program behavior")) );
    ( "installs only the requested installable targets",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let prefix = Filename.concat workspace "_exe-only" in
            let install =
              run_oasis ~cwd:workspace
                [ "install"; "--prefix"; prefix; "hello" ]
            in
            assert_int_equal 0 install.status
              "install should allow targeted staging";
            assert_file_exists (Filename.concat prefix "bin/hello");
            assert_true
              (not (Fs.exists (Filename.concat prefix "lib/greeting")))
              "installing only an executable should not stage unrelated libraries";
            let metadata =
              Fs.read_file (Filename.concat prefix "share/oasis/hello/install.json")
            in
            assert_string_not_contains ~needle:"\"name\": \"greeting\"" metadata
              "install metadata should not list unrequested libraries")) );
    ( "rejects test targets for install",
      (fun () ->
        with_temp_dir "oasis-install-tests" (fun workspace ->
            write_manifest workspace
              {|
[test.suite]
dir = "test"
main = "main"
|};
            write_source workspace "test/main.ml" {|let () = print_endline "suite"|};
            let install = run_oasis ~cwd:workspace [ "install"; "suite" ] in
            assert_true (install.status <> 0)
              "install should reject test-only targets";
            assert_string_contains
              ~needle:"target 'suite' is a test; oasis install only supports libraries and executables"
              install.output
              "install should report unsupported target kinds clearly")) );
  ]
