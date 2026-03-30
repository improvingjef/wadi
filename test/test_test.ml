open Test_support

let write_source = write_workspace_file

let cases =
  [
    ( "runs discovered test targets",
      fun () ->
        with_temp_dir "wadi-test-run" (fun workspace ->
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
            let run = run_wadi ~cwd:workspace [ "test" ] in
            assert_int_equal 0 run.status "wadi test should succeed when all tests pass";
            assert_string_contains ~needle:"Built test greeting_suite" run.output
              "test builds should be reported explicitly";
            assert_string_contains ~needle:"greeting ok\n" run.output
              "test output should be surfaced";
            assert_string_contains ~needle:"ok - greeting_suite" run.output
              "passing tests should be summarized";
            assert_string_contains ~needle:"All 1 tests passed" run.output
              "successful test runs should print a final summary") );
    ( "runs only the requested test targets",
      fun () ->
        with_temp_dir "wadi-test-selective" (fun workspace ->
            write_manifest workspace
              {|
[test.first]
dir = "first"
main = "main"

[test.second]
dir = "second"
main = "main"
|};
            write_source workspace "first/main.ml" {|let () = print_endline "first-ran"|};
            write_source workspace "second/main.ml"
              {|let () = print_endline "second-ran"|};
            let run = run_wadi ~cwd:workspace [ "test"; "second" ] in
            assert_int_equal 0 run.status "selective test runs should succeed";
            assert_string_contains ~needle:"second-ran\n" run.output
              "requested tests should run";
            assert_string_not_contains ~needle:"first-ran" run.output
              "unrequested tests should not run";
            assert_string_not_contains ~needle:"Built test first" run.output
              "unrequested tests should not be built") );
    ( "rejects non-test targets for wadi test",
      fun () ->
        with_temp_dir "wadi-test-kind" (fun workspace ->
            write_manifest workspace {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml" {|let () = print_endline "demo"|};
            let run = run_wadi ~cwd:workspace [ "test"; "demo" ] in
            assert_true (run.status <> 0) "wadi test should reject executable targets";
            assert_string_contains
              ~needle:"target 'demo' is an executable; wadi test only supports tests"
              run.output "wadi test should explain invalid target kinds") );
    ( "reports failing tests with a summary",
      fun () ->
        with_temp_dir "wadi-test-failure" (fun workspace ->
            write_manifest workspace
              {|
[test.green]
dir = "green"
main = "main"

[test.red]
dir = "red"
main = "main"
|};
            write_source workspace "green/main.ml" {|let () = print_endline "green ok"|};
            write_source workspace "red/main.ml" {|let () = failwith "boom"|};
            let run = run_wadi ~cwd:workspace [ "test" ] in
            assert_true (run.status <> 0)
              "wadi test should fail when any test binary fails";
            assert_string_contains ~needle:"green ok\n" run.output
              "passing test output should still be shown";
            assert_string_contains ~needle:"ok - green" run.output
              "passing tests should still be reported";
            assert_string_contains ~needle:"not ok - red" run.output
              "failing tests should be identified";
            assert_string_contains ~needle:"1/2 tests failed" run.output
              "failing runs should report the aggregate summary";
            assert_string_contains ~needle:"Failed tests: red" run.output
              "failing runs should list the failing targets") );
    ( "reports member package paths in test summaries",
      fun () ->
        with_temp_dir "wadi-test-package-paths" (fun workspace ->
            write_manifest workspace
              {|
workspace = "demo"
version = 1
members = ["packages/app"]
|};
            write_workspace_file workspace "packages/app/wadi.toml"
              {|
[test.member_suite]
dir = "test"
main = "main"
|};
            write_source workspace "packages/app/test/main.ml"
              {|let () = failwith "member failure"|};
            let run = run_wadi ~cwd:workspace [ "test"; "member_suite" ] in
            assert_true (run.status <> 0)
              "member test failures should still return a non-zero status";
            assert_string_contains ~needle:"not ok - member_suite (packages/app)"
              run.output "test summaries should surface the member package path";
            assert_string_contains ~needle:"Failed tests: member_suite (packages/app)"
              run.output
              "aggregate failure summaries should retain the member package path") );
    ( "reports when a workspace has no tests",
      fun () ->
        with_temp_dir "wadi-test-none" (fun workspace ->
            write_manifest workspace {|
[library.core]
dir = "lib"
modules = ["core"]
|};
            write_source workspace "lib/core.ml" {|let value = 42|};
            let run = run_wadi ~cwd:workspace [ "test" ] in
            assert_true (run.status <> 0)
              "wadi test should fail clearly when no tests are defined";
            assert_string_contains ~needle:"workspace does not define any tests to run"
              run.output "missing tests should produce a direct error") );
    ( "runs tests concurrently with -j flag",
      fun () ->
        with_temp_dir "wadi-test-parallel" (fun workspace ->
            write_manifest workspace
              {|
[test.alpha]
dir = "alpha"
main = "main"

[test.beta]
dir = "beta"
main = "main"

[test.gamma]
dir = "gamma"
main = "main"
|};
            write_source workspace "alpha/main.ml" {|let () = print_endline "alpha-ran"|};
            write_source workspace "beta/main.ml" {|let () = print_endline "beta-ran"|};
            write_source workspace "gamma/main.ml" {|let () = print_endline "gamma-ran"|};
            let run = run_wadi ~cwd:workspace [ "test"; "-j"; "2" ] in
            assert_int_equal 0 run.status "parallel test execution should succeed";
            assert_string_contains ~needle:"alpha-ran\n" run.output
              "alpha test output should be present";
            assert_string_contains ~needle:"beta-ran\n" run.output
              "beta test output should be present";
            assert_string_contains ~needle:"gamma-ran\n" run.output
              "gamma test output should be present";
            assert_string_contains ~needle:"ok - alpha" run.output
              "alpha should be reported as passing";
            assert_string_contains ~needle:"ok - beta" run.output
              "beta should be reported as passing";
            assert_string_contains ~needle:"ok - gamma" run.output
              "gamma should be reported as passing";
            assert_string_contains ~needle:"All 3 tests passed" run.output
              "parallel runs should print a final summary") );
    ( "parallel execution reports failures correctly",
      fun () ->
        with_temp_dir "wadi-test-parallel-fail" (fun workspace ->
            write_manifest workspace
              {|
[test.pass_one]
dir = "pass_one"
main = "main"

[test.fail_one]
dir = "fail_one"
main = "main"

[test.pass_two]
dir = "pass_two"
main = "main"
|};
            write_source workspace "pass_one/main.ml"
              {|let () = print_endline "pass_one ok"|};
            write_source workspace "fail_one/main.ml" {|let () = failwith "boom"|};
            write_source workspace "pass_two/main.ml"
              {|let () = print_endline "pass_two ok"|};
            let run = run_wadi ~cwd:workspace [ "test"; "-j"; "3" ] in
            assert_true (run.status <> 0) "parallel run should fail when any test fails";
            assert_string_contains ~needle:"pass_one ok\n" run.output
              "passing test output should be shown";
            assert_string_contains ~needle:"pass_two ok\n" run.output
              "later passing test output should also be shown";
            assert_string_contains ~needle:"ok - pass_one" run.output
              "passing tests should be reported";
            assert_string_contains ~needle:"not ok - fail_one" run.output
              "failing tests should be reported";
            assert_string_contains ~needle:"1/3 tests failed" run.output
              "failure summary should be accurate";
            assert_string_contains ~needle:"Failed tests: fail_one" run.output
              "failure summary should name the failing test") );
    ( "rejects invalid -j values",
      fun () ->
        with_temp_dir "wadi-test-bad-j" (fun workspace ->
            write_manifest workspace {|
[test.suite]
dir = "test"
main = "main"
|};
            write_source workspace "test/main.ml" {|let () = print_endline "ok"|};
            let run_zero = run_wadi ~cwd:workspace [ "test"; "-j"; "0" ] in
            assert_true (run_zero.status <> 0) "-j 0 should be rejected";
            assert_string_contains ~needle:"positive integer" run_zero.output
              "-j 0 should explain the requirement";
            let run_neg = run_wadi ~cwd:workspace [ "test"; "-j"; "-1" ] in
            assert_true (run_neg.status <> 0) "-j -1 should be rejected";
            let run_word = run_wadi ~cwd:workspace [ "test"; "-j"; "abc" ] in
            assert_true (run_word.status <> 0) "-j abc should be rejected";
            assert_string_contains ~needle:"requires an integer" run_word.output
              "-j with non-numeric value should explain the requirement") );
    ( "preserves output order with parallel execution",
      fun () ->
        with_temp_dir "wadi-test-parallel-order" (fun workspace ->
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
              {|let () = print_endline "first-output"|};
            write_source workspace "second/main.ml"
              {|let () = print_endline "second-output"|};
            let run = run_wadi ~cwd:workspace [ "test"; "-j"; "2" ] in
            assert_int_equal 0 run.status "parallel ordered test should succeed";
            (* first-output should appear before second-output in the combined output *)
            let first_pos =
              let rec find i =
                if i + 12 > String.length run.output then -1
                else if String.sub run.output i 12 = "first-output" then i
                else find (i + 1)
              in
              find 0
            in
            let second_pos =
              let rec find i =
                if i + 13 > String.length run.output then -1
                else if String.sub run.output i 13 = "second-output" then i
                else find (i + 1)
              in
              find 0
            in
            assert_true (first_pos >= 0) "first-output should appear in output";
            assert_true (second_pos >= 0) "second-output should appear in output";
            assert_true (first_pos < second_pos)
              "output should preserve declaration order even with parallel execution") );
  ]
