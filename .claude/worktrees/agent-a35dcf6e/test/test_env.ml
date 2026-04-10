open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let run_wadi_with_env ~cwd ~env args =
  Process.run_capture ~cwd ~env (wadi_bin ()) args

let cases =
  [
    ( "prints merged build environments for compiler, action, and preprocess contexts",
      (fun () ->
        with_temp_dir "wadi-env-build" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
env = ["MODE=default"]

[profile.release]
env = ["MODE=release", "PROFILE=release"]

[action.generate]
argv = ["./tools/generate.sh"]
outputs = ["version.ml"]
env = ["ACTION=generate"]

[preprocess.expand]
argv = ["./tools/expand.sh"]
env = ["PRE=expand"]

[library.core]
dir = "lib"
modules = ["core", "version"]
actions = ["generate"]
preprocess = ["expand"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
env = ["TARGET=demo"]
|};
            write_source workspace "lib/core.ml" {|let message = Version.value|};
            write_source workspace "app/main.ml" {|let () = print_endline Core.message|};
            let report =
              run_wadi_with_env ~cwd:workspace
                ~env:[ ("HOST_ONLY", "from-host") ]
                [ "env"; "--profile"; "release"; "build"; "demo" ]
            in
            assert_int_equal 0 report.status
              "env build should render successfully";
            assert_string_contains ~needle:"Subtool: build\n" report.output
              "env output should report the selected subtool";
            assert_string_contains ~needle:"Profile: release\n" report.output
              "env output should report the resolved profile";
            assert_string_contains ~needle:"Target: library core\n" report.output
              "env output should include the dependency library build context";
            assert_string_contains ~needle:"Context: compiler-linker\n" report.output
              "env output should include compiler/linker contexts";
            assert_string_contains ~needle:"HOST_ONLY=from-host\n" report.output
              "env output should include inherited host variables";
            assert_string_contains ~needle:"MODE=release\n" report.output
              "profile env bindings should flow into compiler contexts";
            assert_string_contains ~needle:"PROFILE=release\n" report.output
              "profile-only env bindings should be preserved";
            assert_string_contains ~needle:"Context: action generate\n" report.output
              "env output should include action-specific contexts";
            assert_string_contains ~needle:"ACTION=generate\n" report.output
              "action contexts should merge target and action env";
            assert_string_contains ~needle:"Context: preprocess expand\n"
              report.output
              "env output should include preprocessor contexts";
            assert_string_contains ~needle:"PRE=expand\n" report.output
              "preprocessor contexts should merge target and tool env";
            assert_string_contains ~needle:"Target: executable demo\n" report.output
              "env output should include the requested executable context";
            assert_string_contains ~needle:"TARGET=demo\n" report.output
              "target-local env bindings should appear in executable contexts")) );
    ( "prints focused action environments for wadi action planning",
      (fun () ->
        with_temp_dir "wadi-env-action" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
env = ["MODE=default"]

[profile.release]
env = ["MODE=release", "PROFILE=release"]

[action.generate]
argv = ["./tools/generate.sh"]
outputs = ["version.ml"]
env = ["ACTION=generate"]

[library.core]
dir = "lib"
modules = ["core", "version"]
actions = ["generate"]
env = ["TARGET=core"]
|};
            write_source workspace "lib/core.ml" {|let message = Version.value|};
            let report =
              run_wadi_with_env ~cwd:workspace
                ~env:[ ("HOST_ONLY", "from-host") ]
                [ "env"; "--profile"; "release"; "action"; "core" ]
            in
            assert_int_equal 0 report.status
              "env action should render successfully";
            assert_string_contains ~needle:"Subtool: action\n" report.output
              "env action should report the selected subtool";
            assert_string_contains ~needle:"Requested-targets: core\n" report.output
              "env action should report the selected target";
            assert_string_contains ~needle:"Target: library core\n" report.output
              "env action should include the selected library target";
            assert_string_contains ~needle:"Context: action generate\n"
              report.output
              "env action should include action-specific contexts";
            assert_string_contains ~needle:"ACTION=generate\n" report.output
              "env action should merge action-local bindings";
            assert_string_contains ~needle:"TARGET=core\n" report.output
              "env action should retain target-local bindings";
            assert_string_contains ~needle:"MODE=release\n" report.output
              "env action should apply profile bindings";
            assert_string_contains ~needle:"HOST_ONLY=from-host\n" report.output
              "env action should include inherited host bindings";
            assert_string_not_contains ~needle:"Context: compiler-linker\n"
              report.output
              "env action should stay focused on action execution contexts")) );
    ( "prints the runtime environment for wadi run planning",
      (fun () ->
        with_temp_dir "wadi-env-run" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml" {|let () = print_endline "demo"|};
            let report =
              run_wadi_with_env ~cwd:workspace
                ~env:[ ("RUNTIME_ONLY", "yes") ]
                [ "env"; "run"; "demo" ]
            in
            assert_int_equal 0 report.status
              "env run should render successfully";
            assert_string_contains ~needle:"Subtool: run\n" report.output
              "env run should report the selected subtool";
            assert_string_contains ~needle:"Requested-targets: demo\n" report.output
              "env run should report the selected executable target";
            assert_string_contains ~needle:"Target: executable demo\n" report.output
              "env run should include the executable build context";
            assert_string_contains ~needle:"Context: runtime\n" report.output
              "env run should include the launched runtime context";
            assert_string_contains ~needle:"RUNTIME_ONLY=yes\n" report.output
              "runtime contexts should include inherited host variables")) );
    ( "prints runtime contexts for benchmark planning",
      (fun () ->
        with_temp_dir "wadi-env-bench" (fun workspace ->
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
            let report =
              run_wadi_with_env ~cwd:workspace
                ~env:[ ("BENCH_ONLY", "yes") ]
                [ "env"; "bench"; "alpha"; "beta" ]
            in
            assert_int_equal 0 report.status
              "env bench should render successfully";
            assert_string_contains ~needle:"Subtool: bench\n" report.output
              "env bench should report the selected subtool";
            assert_string_contains ~needle:"Requested-targets: alpha, beta\n"
              report.output
              "env bench should report the selected executable targets";
            assert_string_contains ~needle:"Target: executable alpha\n" report.output
              "env bench should include the first executable build context";
            assert_string_contains ~needle:"Target: executable beta\n" report.output
              "env bench should include the second executable build context";
            assert_string_contains ~needle:"Context: runtime\n" report.output
              "env bench should include benchmark runtime contexts";
            assert_string_contains ~needle:"BENCH_ONLY=yes\n" report.output
              "benchmark runtime contexts should include inherited host variables")) );
    ( "prints declared bench runtime environments separately from executable build contexts",
      (fun () ->
        with_temp_dir "wadi-env-bench-declared" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"

[bench.quick]
executable = "demo"
env = ["BENCH_MODE=quick"]
|};
            write_source workspace "app/main.ml" {|let () = print_endline "demo"|};
            let report =
              run_wadi_with_env ~cwd:workspace
                ~env:[ ("BENCH_ONLY", "yes") ]
                [ "env"; "bench"; "quick" ]
            in
            assert_int_equal 0 report.status
              "env bench should resolve declared bench entries";
            assert_string_contains ~needle:"Requested-targets: quick\n"
              report.output
              "env bench should preserve the requested bench name";
            assert_string_contains ~needle:"Target: executable demo\n" report.output
              "env bench should still include the executable build context";
            assert_string_contains ~needle:"Target: bench quick\n" report.output
              "env bench should render a separate runtime context for the declared bench";
            assert_string_contains ~needle:"BENCH_MODE=quick\n" report.output
              "declared bench runtime env should be visible";
            assert_string_contains ~needle:"BENCH_ONLY=yes\n" report.output
              "declared bench runtime contexts should still include inherited host variables")) );
    ( "prints machine-readable JSON env reports",
      (fun () ->
        with_temp_dir "wadi-env-json" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
env = ["MODE=default"]

[profile.release]
env = ["MODE=release", "PROFILE=release"]

[executable.demo]
dir = "app"
main = "main"
env = ["TARGET=demo"]
|};
            write_source workspace "app/main.ml" {|let () = print_endline "demo"|};
            let report =
              run_wadi_with_env ~cwd:workspace
                ~env:[ ("HOST_ONLY", "from-host") ]
                [ "env"; "--json"; "--profile"; "release"; "run"; "demo" ]
            in
            assert_int_equal 0 report.status
              "env --json should render successfully";
            assert_string_contains ~needle:"\"workspace\": null" report.output
              "env JSON should encode an unnamed workspace as null";
            assert_string_contains ~needle:"\"subtool\": \"run\"" report.output
              "env JSON should include the selected subtool";
            assert_string_contains ~needle:"\"profile\": \"release\"" report.output
              "env JSON should include the resolved profile";
            assert_string_contains
              ~needle:"\"requested_targets\": [\"demo\"]"
              report.output
              "env JSON should report the requested target names";
            assert_string_contains
              ~needle:"\"target\": \"executable demo\""
              report.output
              "env JSON should include the build context target label";
            assert_string_contains ~needle:"\"context\": \"runtime\""
              report.output
              "env JSON should include the runtime context label";
            assert_string_contains
              ~needle:"\"HOST_ONLY\": \"from-host\""
              report.output
              "env JSON should include inherited environment bindings";
            assert_string_contains ~needle:"\"MODE\": \"release\""
              report.output
              "env JSON should include resolved profile bindings";
            assert_string_contains ~needle:"\"TARGET\": \"demo\""
              report.output
              "env JSON should include target-local bindings")) );
    ( "filters env reports down to changed bindings only",
      (fun () ->
        with_temp_dir "wadi-env-changed" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
env = ["MODE=default", "SHARED=default"]

[profile.release]
env = ["MODE=release", "PROFILE=release"]

[executable.demo]
dir = "app"
main = "main"
env = ["TARGET=demo"]
|};
            write_source workspace "app/main.ml" {|let () = print_endline "demo"|};
            let report =
              run_wadi_with_env ~cwd:workspace
                ~env:[ ("HOST_ONLY", "from-host"); ("SHARED", "default") ]
                [ "env"; "--changed-only"; "--profile"; "release"; "run"; "demo" ]
            in
            assert_int_equal 0 report.status
              "env --changed-only should render successfully";
            assert_string_contains ~needle:"View: changed-only\n" report.output
              "changed-only env output should label the filtered view";
            assert_string_contains ~needle:"MODE=release\n" report.output
              "changed-only env output should keep overridden profile bindings";
            assert_string_contains ~needle:"PROFILE=release\n" report.output
              "changed-only env output should keep added profile bindings";
            assert_string_contains ~needle:"TARGET=demo\n" report.output
              "changed-only env output should keep target-local bindings";
            assert_string_not_contains ~needle:"HOST_ONLY=from-host\n"
              report.output
              "changed-only env output should omit unchanged inherited host bindings";
            assert_string_not_contains ~needle:"SHARED=default\n" report.output
              "changed-only env output should omit bindings that match the inherited host value";
            assert_string_not_contains ~needle:"Context: runtime\n" report.output
              "empty runtime contexts should be omitted in changed-only mode")) );
  ]
