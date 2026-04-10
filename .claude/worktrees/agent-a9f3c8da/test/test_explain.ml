open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let write_executable workspace relative_path contents =
  let path = Filename.concat workspace relative_path in
  Fs.write_file path contents;
  Unix.chmod path 0o755;
  path

let resolve_command prog =
  let outcome = Process.run_capture "/bin/sh" [ "-c"; "command -v " ^ prog ] in
  assert_int_equal 0 outcome.status
    (Printf.sprintf "expected to find %s on PATH" prog);
  String.trim outcome.output

let write_logging_wrapper workspace relative_path label log_path command_path =
  write_executable workspace relative_path
    (Printf.sprintf
       "#!/bin/sh\nprintf '%s %%s\\n' \"$*\" >> %s\nexec %s \"$@\"\n" label
       (Filename.quote log_path) (Filename.quote command_path))

let count_exact_line expected lines =
  List.length (List.filter (fun line -> line = expected) lines)

let cases =
  [
    ( "reports when explain data is missing",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let explain = run_wadi ~cwd:workspace [ "explain"; "greeting" ] in
            assert_true (explain.status <> 0)
              "explain should fail before a target has been built";
            assert_string_contains
              ~needle:"no explain data for library 'greeting' in profile 'default'; build it first"
              explain.output
              "explain should direct users to build the target first")) );
    ( "computes current explain data before the first build without compiling",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let out_dir = Layout.library_out_dir workspace "greeting" in
            let explain =
              run_wadi ~cwd:workspace [ "explain"; "--current"; "greeting" ]
            in
            assert_int_equal 0 explain.status
              "explain --current should work before any target has been built";
            assert_string_contains ~needle:"Target: greeting" explain.output
              "current explain should identify the requested target";
            assert_string_contains ~needle:"State: rebuilt" explain.output
              "fresh current explain should report a rebuild";
            assert_string_contains ~needle:"previous build stamp missing"
              explain.output
              "current explain should report the missing prior stamp";
            assert_string_contains ~needle:"missing output:" explain.output
              "current explain should report missing artifacts before the first build";
            assert_true (not (Fs.exists (Layout.stamp_path out_dir)))
              "current explain should not write a target stamp when it only plans work")) );
    ( "accepts explicit backend selection for current explain",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let explain =
              run_wadi ~cwd:workspace
                [ "explain"; "--current"; "--backend"; "bytecode"; "hello" ]
            in
            assert_int_equal 0 explain.status
              "current explain should accept an explicit backend selection";
            assert_string_contains ~needle:"backend-request: bytecode"
              explain.output
              "current explain should report the explicit backend request";
            assert_string_contains ~needle:"selected-backend: bytecode"
              explain.output
              "current explain should plan commands for the requested backend")) );
    ( "rejects explicit backend selection without current explain",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let explain =
              run_wadi ~cwd:workspace [ "explain"; "--backend"; "bytecode"; "hello" ]
            in
            assert_true (explain.status <> 0)
              "persisted explain should reject backend selection";
            assert_string_contains ~needle:"--backend is only supported with --current"
              explain.output
              "explain should explain that backend selection only applies to dry-run planning")) );
    ( "records rebuilt and reused target state in explain reports",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let first_build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 first_build.status
              "initial build should succeed before explain reports are read";
            let first_explain = run_wadi ~cwd:workspace [ "explain"; "greeting" ] in
            assert_int_equal 0 first_explain.status
              "explain should read the persisted report after a build";
            assert_string_contains ~needle:"Target: greeting" first_explain.output
              "explain output should identify the requested target";
            assert_string_contains ~needle:"State: rebuilt" first_explain.output
              "the first build should record a rebuilt state";
            assert_string_contains ~needle:"previous build stamp missing"
              first_explain.output
              "fresh targets should explain that there was no prior stamp";
            let second_build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 second_build.status
              "second build should succeed before checking the reused report";
            let second_explain =
              run_wadi ~cwd:workspace [ "explain"; "greeting" ]
            in
            assert_int_equal 0 second_explain.status
              "explain should still succeed after an up-to-date build";
            assert_string_contains ~needle:"State: reused"
              second_explain.output
              "unchanged targets should record a reused state";
            assert_string_contains
              ~needle:"inputs and outputs matched the recorded fingerprint"
              second_explain.output
              "reused targets should explain the cache hit")) );
    ( "surfaces member package paths and local tool scopes in explain output",
      (fun () ->
        with_temp_dir "wadi-explain-member-paths" (fun workspace ->
            write_manifest workspace
              {|
workspace = "demo"
version = 1
members = ["packages/core", "packages/app"]
|};
            write_workspace_file workspace "packages/core/wadi.toml"
              {|
[action.generate_version]
argv = ["./scripts/generate.sh"]
cwd = "."
deps = ["templates/version.txt"]
outputs = ["version.ml"]

[preprocess.expand]
argv = ["./scripts/expand.sh"]
cwd = "scripts"
deps = ["templates/banner.txt"]

[ppx.rewrite]
argv = ["./ppx/rewrite.exe"]
deps = ["ppx/config.txt"]

[library.core]
dir = "lib"
modules = ["core", "version"]
actions = ["generate_version"]
preprocess = ["expand"]
ppx = ["rewrite"]
|};
            write_workspace_file workspace "packages/app/wadi.toml"
              {|
[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "packages/core/templates/version.txt"
              "member-action\n";
            ignore
              (write_executable workspace "packages/core/scripts/generate.sh"
                 "#!/bin/sh\nset -eu\nversion=$(cat templates/version.txt)\nprintf 'let value = \"%s\"\\n' \"$version\" > lib/version.ml\n");
            write_source workspace "packages/core/templates/banner.txt"
              "member-pre";
            ignore
              (write_executable workspace "packages/core/scripts/expand.sh"
                 "#!/bin/sh\nset -eu\nbanner=$(cat ../templates/banner.txt)\nsed \"s/@@PREFIX@@/${banner}/g\"\n");
            write_source workspace "packages/core/ppx/config.txt" "member-ppx\n";
            let _ppx_binary =
              Test_transforms.compile_string_marker_ppx workspace
                ~relative_path:"packages/core/ppx/rewrite.ml"
                ~output_relative_path:"packages/core/ppx/rewrite.exe"
                ~marker:"ppx-marker"
                (Test_transforms.Literal "member-ppx")
            in
            write_source workspace "packages/core/lib/core.ml"
              {|let message = "@@PREFIX@@" ^ ":" ^ Version.value ^ ":" ^ "ppx-marker"|};
            write_source workspace "packages/app/app/main.ml"
              {|let () = print_endline Core.message|};
            let build = run_wadi ~cwd:workspace [ "build"; "core" ] in
            assert_int_equal 0 build.status
              "member-local tool targets should build before explain is read";
            let explain = run_wadi ~cwd:workspace [ "explain"; "core" ] in
            assert_int_equal 0 explain.status
              "explain should succeed for a built member target";
            assert_string_contains ~needle:"Package-path: packages/core"
              explain.output
              "text explain output should surface the member package path";
            assert_string_contains
              ~needle:"actions: generate_version (packages/core)"
              explain.output
              "text explain output should show the scoped member action name";
            assert_string_contains
              ~needle:"preprocessors: expand (packages/core)"
              explain.output
              "text explain output should show the scoped member preprocessor name";
            assert_string_contains ~needle:"ppx: rewrite (packages/core)"
              explain.output
              "text explain output should show the scoped member ppx name";
            let json_explain =
              run_wadi ~cwd:workspace [ "explain"; "--json"; "core" ]
            in
            assert_int_equal 0 json_explain.status
              "JSON explain should succeed for a built member target";
            assert_string_contains ~needle:"\"package_path\": \"packages/core\""
              json_explain.output
              "JSON explain output should record the member package path")) );
    ( "persists a machine-readable explain sibling for automation",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "build should succeed before checking machine-readable explain data";
            let report_path =
              Layout.explain_json_path (Layout.library_out_dir workspace "greeting")
            in
            assert_file_exists report_path;
            let report = Fs.read_file report_path in
            assert_string_contains ~needle:"\"target\": \"greeting\"" report
              "machine-readable explain should record the target name";
            assert_string_contains ~needle:"\"state\": \"rebuilt\"" report
              "machine-readable explain should record the build state";
            assert_string_contains
              ~needle:"\"reasons\": [\"previous build stamp missing\""
              report
              "machine-readable explain should preserve rebuild reasons";
            assert_string_contains ~needle:"\"commands\": [" report
              "machine-readable explain should preserve planned commands")) );
    ( "prints persisted explain JSON directly for automation",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "build should succeed before explain JSON is requested";
            let report_path =
              Layout.explain_json_path (Layout.library_out_dir workspace "greeting")
            in
            let expected = String.trim (Fs.read_file report_path) in
            let explain = run_wadi ~cwd:workspace [ "explain"; "--json"; "greeting" ] in
            assert_int_equal 0 explain.status
              "explain --json should succeed for built targets";
            assert_string_equal expected (String.trim explain.output)
              "explain --json should print the persisted JSON payload verbatim";
            assert_string_not_contains ~needle:"Target: greeting" explain.output
              "JSON explain output should not fall back to the text renderer")) );
    ( "renders a JSON array when multiple explain targets are requested",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "build should succeed before explain JSON arrays are requested";
            let explain =
              run_wadi ~cwd:workspace [ "explain"; "--json"; "greeting"; "hello" ]
            in
            assert_int_equal 0 explain.status
              "explain --json should support multiple targets";
            assert_string_contains ~needle:"[\n{" explain.output
              "multiple JSON explain targets should be wrapped in an array";
            assert_string_contains ~needle:"\"target\": \"greeting\"" explain.output
              "the JSON array should include the first requested target";
            assert_string_contains ~needle:"\"target\": \"hello\"" explain.output
              "the JSON array should include the second requested target")) );
    ( "recomputes current explain from edited inputs instead of loading stale reports",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let first_build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 first_build.status
              "initial build should succeed before stale explain behavior is checked";
            let second_build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 second_build.status
              "second build should persist a reused explain report";
            write_source workspace "lib/greeting.ml"
              {|let message name = "Hello again, " ^ name ^ "!"|};
            let persisted = run_wadi ~cwd:workspace [ "explain"; "hello" ] in
            assert_int_equal 0 persisted.status
              "persisted explain should still load after the source changes";
            assert_string_contains ~needle:"State: reused" persisted.output
              "persisted explain should remain stale until another build runs";
            let current =
              run_wadi ~cwd:workspace [ "explain"; "--current"; "hello" ]
            in
            assert_int_equal 0 current.status
              "current explain should succeed after a source edit";
            assert_string_contains ~needle:"State: rebuilt" current.output
              "current explain should recompute rebuild status from live inputs";
            assert_string_contains ~needle:"dependency changed: greeting"
              current.output
              "current explain should propagate dependency-triggered rebuild reasons";
            assert_string_not_contains ~needle:"Up to date executable"
              current.output
              "current explain should not run the build itself")) );
    ( "renders current explain JSON without requiring persisted report files",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let explain =
              run_wadi ~cwd:workspace
                [ "explain"; "--current"; "--json"; "greeting"; "hello" ]
            in
            assert_int_equal 0 explain.status
              "current explain JSON should work before a build";
            assert_string_contains ~needle:"[\n{" explain.output
              "multiple current explain reports should render as a JSON array";
            assert_string_contains ~needle:"\"target\": \"greeting\"" explain.output
              "current explain JSON should include the library target";
            assert_string_contains ~needle:"\"target\": \"hello\"" explain.output
              "current explain JSON should include the executable target";
            assert_string_contains ~needle:"\"state\": \"rebuilt\"" explain.output
              "current explain JSON should report the planned rebuild state")) );
    ( "keeps current explain side-effect-light for generated and preprocessed sources",
      (fun () ->
        with_temp_dir "wadi-explain-current-dry-run" (fun workspace ->
            write_manifest workspace
              {|
[action.generate_version]
argv = ["./scripts/generate_version.sh"]
deps = ["config/version.txt"]
outputs = ["version.ml"]

[preprocess.trace]
argv = ["./scripts/trace.sh"]
deps = ["config/banner.txt"]

[executable.demo]
dir = "app"
main = "main"
modules = ["version"]
actions = ["generate_version"]
preprocess = ["trace"]
|};
            ignore
              (write_executable workspace "scripts/generate_version.sh"
                 "#!/bin/sh\nversion=$(cat ../config/version.txt)\nprintf 'let message = \"%s\"\\n' \"$version\" > version.ml\n");
            ignore
              (write_executable workspace "scripts/trace.sh"
                 "#!/bin/sh\ncat\n");
            write_source workspace "config/version.txt" "v1";
            write_source workspace "config/banner.txt" "banner";
            write_source workspace "app/main.ml"
              {|let () = print_endline Version.message|};
            let out_dir = Layout.executable_out_dir workspace "demo" in
            let generated_output = Filename.concat (Filename.concat out_dir "generated") "version.ml" in
            let preprocessed_main =
              Filename.concat (Filename.concat out_dir "preprocessed") "main.ml"
            in
            let explain =
              run_wadi ~cwd:workspace [ "explain"; "--current"; "demo" ]
            in
            assert_int_equal 0 explain.status
              "current explain should succeed for generated-source targets before a build";
            assert_true (not (Fs.exists generated_output))
              "current explain should not materialize action outputs";
            assert_true (not (Fs.exists preprocessed_main))
              "current explain should not materialize preprocessed sources";
            assert_string_contains ~needle:"missing generated output:"
              explain.output
              "current explain should report that declared generated sources are absent")) );
    ( "distinguishes action-only regeneration from a full rebuild in explain reports",
      (fun () ->
        with_temp_dir "wadi-explain-action-regeneration" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
actions = ["generate_version"]

[action.generate_version]
argv = ["./scripts/generate_version.sh"]
outputs = ["version.ml"]
sandbox = "target"

[executable.demo]
dir = "app"
main = "main"
modules = ["version"]
|};
            ignore
              (write_executable workspace "scripts/generate_version.sh"
                 "#!/bin/sh\nprintf 'let message = \"generated\"\\n' > version.ml\n");
            write_source workspace "app/main.ml"
              {|let () = print_endline Version.message|};
            let first_build = run_wadi ~cwd:workspace [ "build"; "demo" ] in
            assert_int_equal 0 first_build.status
              "the initial action-backed build should succeed";
            let generated_version =
              Filename.concat (Layout.executable_out_dir workspace "demo")
                "generated/version.ml"
            in
            let generated_version = Fs.realpath generated_version in
            Fs.remove_tree generated_version;
            let current =
              run_wadi ~cwd:workspace [ "explain"; "--current"; "demo" ]
            in
            assert_int_equal 0 current.status
              "current explain should succeed after a generated output is removed";
            assert_string_contains ~needle:"State: regenerated" current.output
              "current explain should distinguish action-only repair from a full rebuild";
            assert_string_contains
              ~needle:("missing generated output: " ^ generated_version ^ " (generate_version)")
              current.output
              "current explain should identify the missing generated output";
            assert_string_contains ~needle:"action generate_version: planned"
              current.output
              "current explain should show that the action would rerun";
            let second_build = run_wadi ~cwd:workspace [ "build"; "demo" ] in
            assert_int_equal 0 second_build.status
              "the follow-up build should repair the missing generated output";
            let persisted = run_wadi ~cwd:workspace [ "explain"; "demo" ] in
            assert_int_equal 0 persisted.status
              "persisted explain should load after action-only regeneration";
            assert_string_contains ~needle:"State: regenerated" persisted.output
              "persisted explain should retain the action-only regeneration state";
            assert_string_contains ~needle:"action generate_version: ran"
              persisted.output
              "persisted explain should report that the action reran";
            assert_string_contains
              ~needle:("missing generated output: " ^ generated_version ^ " (generate_version)")
              persisted.output
              "persisted explain should preserve the generated-output repair reason")) );
    ( "shows declared action and preprocessor inputs in persisted explain output",
      (fun () ->
        with_temp_dir "wadi-explain-steady-action-inputs" (fun workspace ->
            write_manifest workspace
              {|
[action.generate_version]
argv = ["./scripts/generate_version.sh"]
deps = ["config/version.txt"]
outputs = ["version.ml"]

[preprocess.trace]
argv = ["./scripts/trace.sh"]
deps = ["config/banner.txt"]

[executable.demo]
dir = "app"
main = "main"
modules = ["version"]
actions = ["generate_version"]
preprocess = ["trace"]
|};
            ignore
              (write_executable workspace "scripts/generate_version.sh"
                 "#!/bin/sh\nversion=$(cat ../config/version.txt)\nprintf 'let message = \"%s\"\\n' \"$version\" > version.ml\n");
            ignore
              (write_executable workspace "scripts/trace.sh"
                 "#!/bin/sh\ncat\n");
            write_source workspace "config/version.txt" "v1";
            write_source workspace "config/banner.txt" "banner";
            write_source workspace "app/main.ml"
              {|let () = print_endline Version.message|};
            let build = run_wadi ~cwd:workspace [ "build"; "demo" ] in
            assert_int_equal 0 build.status
              "the generated-source build should succeed before reading explain data";
            let explain = run_wadi ~cwd:workspace [ "explain"; "demo" ] in
            assert_int_equal 0 explain.status
              "persisted explain should load after a generated-source build";
            assert_string_contains
              ~needle:"action generate_version outputs: version.ml" explain.output
              "persisted explain should show declared action outputs";
            assert_string_contains
              ~needle:"action generate_version deps: config/version.txt"
              explain.output
              "persisted explain should show declared action auxiliary inputs";
            assert_string_contains
              ~needle:"preprocess trace deps: config/banner.txt" explain.output
              "persisted explain should show declared preprocessor auxiliary inputs")) );
    ( "shows declared ppx inputs in persisted explain output",
      (fun () ->
        with_temp_dir "wadi-explain-steady-ppx-inputs" (fun workspace ->
            let _ppx_binary =
              Test_transforms.compile_string_marker_ppx workspace
                ~relative_path:"ppx/rewrite.ml"
                ~output_relative_path:"ppx/rewrite.exe" ~marker:"__PPX__"
                (Test_transforms.First_line_of_file "ppx/message.txt")
            in
            write_manifest workspace
              {|
[ppx.rewrite]
argv = ["./ppx/rewrite.exe"]
deps = ["ppx/message.txt"]

[executable.demo]
dir = "app"
main = "main"
ppx = ["rewrite"]
|};
            write_source workspace "ppx/message.txt" "first";
            write_source workspace "app/main.ml"
              {|let () = print_endline "__PPX__"|};
            let build = run_wadi ~cwd:workspace [ "build"; "demo" ] in
            assert_int_equal 0 build.status
              "the ppx-backed build should succeed before reading explain data";
            let explain = run_wadi ~cwd:workspace [ "explain"; "demo" ] in
            assert_int_equal 0 explain.status
              "persisted explain should load after a ppx-backed build";
            assert_string_contains
              ~needle:"ppx rewrite deps: ppx/message.txt" explain.output
              "persisted explain should show declared ppx auxiliary inputs")) );
    ( "surfaces rebuild reasons and planned compiler commands",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let first_build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 first_build.status
              "baseline build should succeed before editing sources";
            write_source workspace "lib/greeting.ml"
              {|let message name = "Hello again, " ^ name ^ "!"|};
            let second_build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 second_build.status
              "rebuild after editing a source should succeed";
            let library_explain =
              run_wadi ~cwd:workspace [ "explain"; "greeting" ]
            in
            assert_int_equal 0 library_explain.status
              "explain should load the rebuilt library report";
            assert_string_contains ~needle:"State: rebuilt"
              library_explain.output
              "edited libraries should record a rebuilt state";
            assert_string_contains ~needle:"source changed: lib/greeting.ml"
              library_explain.output
              "the explain report should identify the edited source";
            assert_string_contains ~needle:"backend-request: auto"
              library_explain.output
              "the explain report should include resolution decisions";
            assert_string_contains ~needle:"compile greeting.ml:"
              library_explain.output
              "the explain report should include planned compile commands";
            assert_string_contains ~needle:"link:" library_explain.output
              "the explain report should include the planned link command";
            let executable_explain =
              run_wadi ~cwd:workspace [ "explain"; "hello" ]
            in
            assert_int_equal 0 executable_explain.status
              "explain should load the rebuilt executable report";
            assert_string_contains ~needle:"dependency changed: greeting"
              executable_explain.output
              "downstream targets should explain dependency-triggered rebuilds")) );
    ( "explains when a module becomes interface-only",
      (fun () ->
        with_temp_dir "wadi-explain-interface-only" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["api"]
|};
            write_source workspace "lib/api.ml" {|let greeting = "hello"|};
            let first_build = run_wadi ~cwd:workspace [ "build"; "core" ] in
            assert_int_equal 0 first_build.status
              "the initial implementation-backed build should succeed";
            Fs.remove_tree (Filename.concat workspace "lib/api.ml");
            write_source workspace "lib/api.mli" {|val greeting : string|};
            let explain =
              run_wadi ~cwd:workspace [ "explain"; "--current"; "core" ]
            in
            assert_int_equal 0 explain.status
              "current explain should succeed after a module loses its implementation";
            assert_string_contains ~needle:"State: rebuilt" explain.output
              "changing a module from implementation-backed to interface-only should force a rebuild";
            assert_string_contains
              ~needle:"implementation availability changed: lib/api.ml"
              explain.output
              "current explain should describe the implementation-availability change directly")) );
    ( "explains preprocessor auxiliary input changes",
      (fun () ->
        with_temp_dir "wadi-explain-preprocess-deps" (fun workspace ->
            write_manifest workspace
              {|
[preprocess.expand]
argv = ["./scripts/expand.sh"]
deps = ["config/banner.txt"]

[executable.demo]
dir = "app"
main = "main"
preprocess = ["expand"]
|};
            ignore
              (write_executable workspace "scripts/expand.sh"
                 "#!/bin/sh\nbanner=$(cat config/banner.txt)\nsed \"s/__TOKEN__/$banner/\"\n");
            write_source workspace "config/banner.txt" "first";
            write_source workspace "app/main.ml"
              {|let () = print_endline "__TOKEN__"|};
            let first_build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 first_build.status
              "the initial preprocessor-backed build should succeed";
            write_source workspace "config/banner.txt" "second";
            let current =
              run_wadi ~cwd:workspace [ "explain"; "--current"; "demo" ]
            in
            assert_int_equal 0 current.status
              "current explain should succeed after a preprocessor input edit";
            assert_string_contains
              ~needle:"preprocessor auxiliary input changed: config/banner.txt (expand)"
              current.output
              "current explain should call out the edited preprocessor input";
            let second_build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 second_build.status
              "the edited preprocessor input should trigger a rebuild";
            assert_string_contains ~needle:"Built executable demo" second_build.output
              "the executable should rebuild after a preprocessor input edit";
            let run = run_binary (Layout.executable_binary workspace "demo") [] in
            assert_int_equal 0 run.status
              "the rebuilt executable should still run";
            assert_string_equal "second\n" run.output
              "the rebuilt executable should reflect the updated preprocessor input")) );
    ( "explains ppx auxiliary input changes",
      (fun () ->
        with_temp_dir "wadi-explain-ppx-deps" (fun workspace ->
            let _ppx_binary =
              Test_transforms.compile_string_marker_ppx workspace
                ~relative_path:"ppx/rewrite.ml"
                ~output_relative_path:"ppx/rewrite.exe" ~marker:"__PPX__"
                (Test_transforms.First_line_of_file "ppx/message.txt")
            in
            write_manifest workspace
              {|
[ppx.rewrite]
argv = ["./ppx/rewrite.exe"]
deps = ["ppx/message.txt"]

[executable.demo]
dir = "app"
main = "main"
ppx = ["rewrite"]
|};
            write_source workspace "ppx/message.txt" "first";
            write_source workspace "app/main.ml"
              {|let () = print_endline "__PPX__"|};
            let first_build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 first_build.status
              "the initial ppx-backed build should succeed";
            write_source workspace "ppx/message.txt" "second";
            let current =
              run_wadi ~cwd:workspace [ "explain"; "--current"; "demo" ]
            in
            assert_int_equal 0 current.status
              "current explain should succeed after a ppx input edit";
            assert_string_contains
              ~needle:"ppx auxiliary input changed: ppx/message.txt (rewrite)"
              current.output
              "current explain should call out the edited ppx input";
            let second_build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 second_build.status
              "the edited ppx input should trigger a rebuild";
            assert_string_contains ~needle:"Built executable demo" second_build.output
              "the executable should rebuild after a ppx input edit";
            let run = run_binary (Layout.executable_binary workspace "demo") [] in
            assert_int_equal 0 run.status
              "the rebuilt executable should still run";
            assert_string_equal "second\n" run.output
              "the rebuilt executable should reflect the updated ppx input")) );
    ( "caches package and toolchain discovery within one build session",
      (fun () ->
        with_temp_dir "wadi-explain-cache" (fun workspace ->
            write_manifest workspace
              {|
[library.patterns]
dir = "lib"
modules = ["patterns"]
packages = ["str"]

[executable.demo]
dir = "app"
main = "main"
deps = ["patterns"]

[test.patterns_suite]
dir = "test"
main = "main"
deps = ["patterns"]
|};
            write_source workspace "lib/patterns.ml"
              {|
let contains_digit text =
  Str.string_match (Str.regexp ".*[0-9].*") text 0
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline (string_of_bool (Patterns.contains_digit "abc123"))|};
            write_source workspace "test/main.ml"
              {|let () = print_endline (string_of_bool (Patterns.contains_digit "suite123"))|};
            let log_path = Filename.concat workspace "toolchain.log" in
            let ocamlfind_wrapper =
              write_logging_wrapper workspace "bin/ocamlfind-wrapper" "ocamlfind"
                log_path (resolve_command "ocamlfind")
            in
            let ocamlc_wrapper =
              write_logging_wrapper workspace "bin/ocamlc-wrapper" "ocamlc"
                log_path (resolve_command "ocamlc")
            in
            let build =
              with_env "OCAMLFIND" ocamlfind_wrapper (fun () ->
                  with_env "OCAMLC" ocamlc_wrapper (fun () ->
                      run_wadi ~cwd:workspace [ "build" ]))
            in
            assert_int_equal 0 build.status
              "package-backed builds should succeed with wrapped tool probes";
            let lines = Fs.read_lines log_path in
            assert_int_equal 1 (count_exact_line "ocamlfind printconf path" lines)
              "ocamlfind validation should be cached for the whole build session";
            assert_int_equal 1 (count_exact_line "ocamlfind query str" lines)
              "package lookup should be cached across targets in one build session";
            assert_int_equal 1 (count_exact_line "ocamlc -where" lines)
              "stdlib discovery should be cached for the whole build session";
            let explain = run_wadi ~cwd:workspace [ "explain"; "demo" ] in
            assert_int_equal 0 explain.status
              "explain should load reports for package-backed executables";
            assert_string_contains ~needle:"package: str ->" explain.output
              "explain should report resolved package paths";
            assert_string_contains ~needle:"ocamlfind:" explain.output
              "explain should report the package-aware driver resolution")) );
  ]
