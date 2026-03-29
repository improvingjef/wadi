open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let run_oasis_with_env ~cwd ~env args =
  Process.run_capture ~cwd ~env (oasis_bin ()) args

let cases =
  [
    ( "prints merged build environments for compiler, action, and preprocess contexts",
      (fun () ->
        with_temp_dir "oasis-env-build" (fun workspace ->
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
              run_oasis_with_env ~cwd:workspace
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
    ( "prints the runtime environment for oasis run planning",
      (fun () ->
        with_temp_dir "oasis-env-run" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml" {|let () = print_endline "demo"|};
            let report =
              run_oasis_with_env ~cwd:workspace
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
    ( "prints machine-readable JSON env reports",
      (fun () ->
        with_temp_dir "oasis-env-json" (fun workspace ->
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
              run_oasis_with_env ~cwd:workspace
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
  ]
