open Test_support

let write_source = write_workspace_file

let cases =
  [
    ( "runs discovered test targets",
      (fun () ->
        with_temp_dir "oasis-test-run" (fun workspace ->
            write_manifest workspace
              {|
[library.greeting]
dir = "lib"
modules = ["greeting"]

[test.greeting_suite]
dir = "test"
main = "main"
deps = ["greeting"]
|};
            write_source workspace "lib/greeting.ml"
              {|let message name = "Hello, " ^ name ^ "!"|};
            write_source workspace "test/main.ml"
              {|
let () =
  if Greeting.message "world" <> "Hello, world!" then failwith "bad greeting";
  print_endline "greeting ok"
|};
            let run = run_oasis ~cwd:workspace [ "test" ] in
            assert_int_equal 0 run.status
              "oasis test should succeed when all tests pass";
            assert_string_contains ~needle:"Built test greeting_suite" run.output
              "test builds should be reported explicitly";
            assert_string_contains ~needle:"greeting ok\n" run.output
              "test output should be surfaced";
            assert_string_contains ~needle:"ok - greeting_suite" run.output
              "passing tests should be summarized";
            assert_string_contains ~needle:"All 1 tests passed" run.output
              "successful test runs should print a final summary")) );
    ( "runs only the requested test targets",
      (fun () ->
        with_temp_dir "oasis-test-selective" (fun workspace ->
            write_manifest workspace
              {|
[test.first]
dir = "first"
main = "main"

[test.second]
dir = "second"
main = "main"
|};
            write_source workspace "first/main.ml"
              {|let () = print_endline "first-ran"|};
            write_source workspace "second/main.ml"
              {|let () = print_endline "second-ran"|};
            let run = run_oasis ~cwd:workspace [ "test"; "second" ] in
            assert_int_equal 0 run.status
              "selective test runs should succeed";
            assert_string_contains ~needle:"second-ran\n" run.output
              "requested tests should run";
            assert_string_not_contains ~needle:"first-ran" run.output
              "unrequested tests should not run";
            assert_string_not_contains ~needle:"Built test first" run.output
              "unrequested tests should not be built")) );
    ( "rejects non-test targets for oasis test",
      (fun () ->
        with_temp_dir "oasis-test-kind" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "demo"|};
            let run = run_oasis ~cwd:workspace [ "test"; "demo" ] in
            assert_true (run.status <> 0)
              "oasis test should reject executable targets";
            assert_string_contains
              ~needle:"target 'demo' is an executable; oasis test only supports tests"
              run.output
              "oasis test should explain invalid target kinds")) );
    ( "reports failing tests with a summary",
      (fun () ->
        with_temp_dir "oasis-test-failure" (fun workspace ->
            write_manifest workspace
              {|
[test.green]
dir = "green"
main = "main"

[test.red]
dir = "red"
main = "main"
|};
            write_source workspace "green/main.ml"
              {|let () = print_endline "green ok"|};
            write_source workspace "red/main.ml"
              {|let () = failwith "boom"|};
            let run = run_oasis ~cwd:workspace [ "test" ] in
            assert_true (run.status <> 0)
              "oasis test should fail when any test binary fails";
            assert_string_contains ~needle:"green ok\n" run.output
              "passing test output should still be shown";
            assert_string_contains ~needle:"ok - green" run.output
              "passing tests should still be reported";
            assert_string_contains ~needle:"not ok - red" run.output
              "failing tests should be identified";
            assert_string_contains ~needle:"1/2 tests failed" run.output
              "failing runs should report the aggregate summary";
            assert_string_contains ~needle:"Failed tests: red" run.output
              "failing runs should list the failing targets")) );
    ( "reports when a workspace has no tests",
      (fun () ->
        with_temp_dir "oasis-test-none" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
|};
            write_source workspace "lib/core.ml" {|let value = 42|};
            let run = run_oasis ~cwd:workspace [ "test" ] in
            assert_true (run.status <> 0)
              "oasis test should fail clearly when no tests are defined";
            assert_string_contains
              ~needle:"workspace does not define any tests to run" run.output
              "missing tests should produce a direct error")) );
  ]
