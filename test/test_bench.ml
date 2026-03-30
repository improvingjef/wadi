open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let cases =
  [
    ( "benchmarks executable targets and prints a timing summary",
      fun () ->
        with_temp_dir "wadi-bench-text" (fun workspace ->
            write_manifest workspace
              {|
[executable.alpha]
dir = "app"
main = "alpha"

[executable.beta]
dir = "app"
main = "beta"
|};
            write_source workspace "app/alpha.ml" {|let () = ()|};
            write_source workspace "app/beta.ml" {|let () = ()|};
            let bench =
              run_wadi ~cwd:workspace [ "bench"; "--warmup"; "0"; "--iterations"; "2" ]
            in
            assert_int_equal 0 bench.status "bench should run all executables by default";
            assert_string_contains ~needle:"Benchmark alpha ->" bench.output
              "bench text output should include the first executable";
            assert_string_contains ~needle:"Benchmark beta ->" bench.output
              "bench text output should include the second executable";
            assert_string_contains ~needle:"iterations: 2" bench.output
              "bench text output should report the measured iteration count") );
    ( "emits machine-readable JSON benchmark summaries",
      fun () ->
        with_fixture "hello" (fun workspace ->
            let bench =
              run_wadi ~cwd:workspace
                [ "bench"; "--json"; "--warmup"; "0"; "--iterations"; "2"; "hello" ]
            in
            assert_int_equal 0 bench.status
              "bench --json should succeed for executable targets";
            assert_string_contains ~needle:"\"results\": [" bench.output
              "bench JSON should render a results array";
            assert_string_contains ~needle:"\"target\": \"hello\"" bench.output
              "bench JSON should record the benchmark target name";
            assert_string_contains ~needle:"\"iterations\": 2" bench.output
              "bench JSON should record the measured iteration count") );
    ( "benchmarks declared [bench.*] entries with custom argv and metadata by default",
      fun () ->
        with_temp_dir "wadi-bench-declared" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"

[bench.quick]
executable = "demo"
argv = ["--bench"]
warmup = 0
iterations = 2
description = "quick path"
|};
            write_source workspace "app/main.ml"
              {|
let () =
  if Array.length Sys.argv <> 2 || Sys.argv.(1) <> "--bench" then (
    prerr_endline "missing bench argv";
    exit 2)
|};
            let bench = run_wadi ~cwd:workspace [ "bench" ] in
            assert_int_equal 0 bench.status
              "bench should prefer declared bench entries when present";
            assert_string_contains ~needle:"Benchmark quick ->" bench.output
              "bench output should use the declared bench name";
            assert_string_contains ~needle:"  executable: demo\n" bench.output
              "bench output should report the underlying executable";
            assert_string_contains ~needle:"  description: quick path\n" bench.output
              "bench output should report bench metadata";
            assert_string_contains ~needle:"  argv: --bench\n" bench.output
              "bench output should report configured argv";
            assert_string_contains ~needle:"  warmup: 0\n" bench.output
              "bench output should honor declared warmup counts";
            assert_string_contains ~needle:"  iterations: 2\n" bench.output
              "bench output should honor declared iteration counts") );
    ( "lets command-line warmup and iteration flags override declared bench defaults",
      fun () ->
        with_temp_dir "wadi-bench-override" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"

[bench.quick]
executable = "demo"
argv = ["--bench"]
warmup = 0
iterations = 2
|};
            write_source workspace "app/main.ml"
              {|
let () =
  if Array.length Sys.argv <> 2 || Sys.argv.(1) <> "--bench" then exit 2
|};
            let bench =
              run_wadi ~cwd:workspace
                [ "bench"; "--warmup"; "1"; "--iterations"; "3"; "quick" ]
            in
            assert_int_equal 0 bench.status
              "bench should let explicit CLI counts override declaration defaults";
            assert_string_contains ~needle:"  warmup: 1\n" bench.output
              "bench output should reflect the explicit warmup count";
            assert_string_contains ~needle:"  iterations: 3\n" bench.output
              "bench output should reflect the explicit iteration count") );
    ( "rejects non-executable targets for bench",
      fun () ->
        with_fixture "hello" (fun workspace ->
            let bench = run_wadi ~cwd:workspace [ "bench"; "greeting" ] in
            assert_true (bench.status <> 0) "bench should reject library targets";
            assert_string_contains ~needle:"wadi bench only supports executables"
              bench.output "bench should explain that only executables can be benchmarked")
    );
    ( "reports failing benchmark executables directly",
      fun () ->
        with_temp_dir "wadi-bench-failure" (fun workspace ->
            write_manifest workspace {|
[executable.crash]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml" {|let () = prerr_endline "boom"; exit 3|};
            let bench = run_wadi ~cwd:workspace [ "bench"; "crash" ] in
            assert_true (bench.status <> 0)
              "bench should fail when a benchmark executable exits non-zero";
            assert_string_contains ~needle:"benchmark command failed" bench.output
              "bench should surface the failing command";
            assert_string_contains ~needle:"boom" bench.output
              "bench should preserve benchmark stderr for diagnosis") );
  ]
