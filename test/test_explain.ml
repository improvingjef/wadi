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
            let explain = run_oasis ~cwd:workspace [ "explain"; "greeting" ] in
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
              run_oasis ~cwd:workspace [ "explain"; "--current"; "greeting" ]
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
    ( "records rebuilt and reused target state in explain reports",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let first_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 first_build.status
              "initial build should succeed before explain reports are read";
            let first_explain = run_oasis ~cwd:workspace [ "explain"; "greeting" ] in
            assert_int_equal 0 first_explain.status
              "explain should read the persisted report after a build";
            assert_string_contains ~needle:"Target: greeting" first_explain.output
              "explain output should identify the requested target";
            assert_string_contains ~needle:"State: rebuilt" first_explain.output
              "the first build should record a rebuilt state";
            assert_string_contains ~needle:"previous build stamp missing"
              first_explain.output
              "fresh targets should explain that there was no prior stamp";
            let second_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 second_build.status
              "second build should succeed before checking the reused report";
            let second_explain =
              run_oasis ~cwd:workspace [ "explain"; "greeting" ]
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
    ( "persists a machine-readable explain sibling for automation",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_oasis ~cwd:workspace [ "build" ] in
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
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "build should succeed before explain JSON is requested";
            let report_path =
              Layout.explain_json_path (Layout.library_out_dir workspace "greeting")
            in
            let expected = String.trim (Fs.read_file report_path) in
            let explain = run_oasis ~cwd:workspace [ "explain"; "--json"; "greeting" ] in
            assert_int_equal 0 explain.status
              "explain --json should succeed for built targets";
            assert_string_equal expected (String.trim explain.output)
              "explain --json should print the persisted JSON payload verbatim";
            assert_string_not_contains ~needle:"Target: greeting" explain.output
              "JSON explain output should not fall back to the text renderer")) );
    ( "renders a JSON array when multiple explain targets are requested",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "build should succeed before explain JSON arrays are requested";
            let explain =
              run_oasis ~cwd:workspace [ "explain"; "--json"; "greeting"; "hello" ]
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
            let first_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 first_build.status
              "initial build should succeed before stale explain behavior is checked";
            let second_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 second_build.status
              "second build should persist a reused explain report";
            write_source workspace "lib/greeting.ml"
              {|let message name = "Hello again, " ^ name ^ "!"|};
            let persisted = run_oasis ~cwd:workspace [ "explain"; "hello" ] in
            assert_int_equal 0 persisted.status
              "persisted explain should still load after the source changes";
            assert_string_contains ~needle:"State: reused" persisted.output
              "persisted explain should remain stale until another build runs";
            let current =
              run_oasis ~cwd:workspace [ "explain"; "--current"; "hello" ]
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
              run_oasis ~cwd:workspace
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
    ( "surfaces rebuild reasons and planned compiler commands",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let first_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 first_build.status
              "baseline build should succeed before editing sources";
            write_source workspace "lib/greeting.ml"
              {|let message name = "Hello again, " ^ name ^ "!"|};
            let second_build = run_oasis ~cwd:workspace [ "build" ] in
            assert_int_equal 0 second_build.status
              "rebuild after editing a source should succeed";
            let library_explain =
              run_oasis ~cwd:workspace [ "explain"; "greeting" ]
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
              run_oasis ~cwd:workspace [ "explain"; "hello" ]
            in
            assert_int_equal 0 executable_explain.status
              "explain should load the rebuilt executable report";
            assert_string_contains ~needle:"dependency changed: greeting"
              executable_explain.output
              "downstream targets should explain dependency-triggered rebuilds")) );
    ( "caches package and toolchain discovery within one build session",
      (fun () ->
        with_temp_dir "oasis-explain-cache" (fun workspace ->
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
                      run_oasis ~cwd:workspace [ "build" ]))
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
            let explain = run_oasis ~cwd:workspace [ "explain"; "demo" ] in
            assert_int_equal 0 explain.status
              "explain should load reports for package-backed executables";
            assert_string_contains ~needle:"package: str ->" explain.output
              "explain should report resolved package paths";
            assert_string_contains ~needle:"ocamlfind:" explain.output
              "explain should report the package-aware driver resolution")) );
  ]
