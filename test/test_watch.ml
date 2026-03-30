open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let write_executable workspace relative_path contents =
  let path = Filename.concat workspace relative_path in
  Fs.write_file path contents;
  Unix.chmod path 0o755;
  path

let spawn_delayed_script ?(delay_s = 1) workspace name body =
  let script_name =
    "watch-script-"
    ^ (name |> String.map (function '/' | '.' | ' ' -> '_' | ch -> ch))
    ^ "-"
    ^ string_of_int delay_s
    ^ ".sh"
  in
  let script_path =
    write_executable workspace script_name
      (Printf.sprintf "#!/bin/sh\nset -eu\nsleep %d\n%s\n" delay_s body)
  in
  Process.spawn ~cwd:workspace script_path []

let spawn_delayed_write ?(delay_s = 1) workspace relative_path contents =
  let script_name =
    "rewrite-"
    ^
    (relative_path |> String.map (function '/' | '.' -> '_' | ch -> ch))
    ^ "-"
    ^ string_of_int delay_s
    ^ ".sh"
  in
  let script_path =
    write_executable workspace script_name
      (Printf.sprintf
         "#!/bin/sh\nsleep %d\ncat <<'EOF' > %s\n%s\nEOF\n"
         delay_s
         (Filename.quote (Filename.concat workspace relative_path))
         contents)
  in
  Process.spawn ~cwd:workspace script_path []

let write_demo_workspace ?(watch_block = "") workspace =
  write_manifest workspace
    (Printf.sprintf
       {|
%s
[executable.demo]
dir = "app"
main = "main"
|}
       watch_block);
  write_source workspace "app/main.ml" {|let () = print_endline "demo"|}

let cases =
  [
    ( "reruns a selected subtool when workspace inputs change",
      (fun () ->
        with_temp_dir "wadi-watch-rerun" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "first"|};
            let mutator =
              spawn_delayed_write workspace "app/main.ml"
                {|let () = print_endline "second"|}
            in
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--poll-ms";
                  "50";
                  "--debounce-ms";
                  "20";
                  "--max-runs";
                  "2";
                  "run";
                  "demo";
                ]
            in
            ignore (Unix.waitpid [] mutator);
            assert_int_equal 0 watch.status
              "watch should exit successfully after two successful runs";
            assert_string_contains ~needle:"Watch-run 1: run demo" watch.output
              "watch should announce the first execution";
            assert_string_contains ~needle:"first\n" watch.output
              "watch should include output from the first run";
            assert_string_contains ~needle:"Watch-change: rerunning" watch.output
              "watch should announce that a file change triggered a rerun";
            assert_string_contains ~needle:"Watch-run 2: run demo" watch.output
              "watch should execute the selected subtool a second time";
            assert_string_contains ~needle:"second\n" watch.output
              "watch should include output from the rerun")) );
    ( "reloads .wadiwatchignore changes without restarting the watcher",
      (fun () ->
        with_temp_dir "wadi-watch-ignore-reload" (fun workspace ->
            write_manifest workspace
              {|
[watch]
include = ["app/**", "docs/**"]

[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "demo"|};
            write_source workspace "docs/notes.txt" "notes\n";
            write_workspace_file workspace ".wadiwatchignore" {|
docs/**
|};
            let reload_ignore =
              spawn_delayed_write workspace ".wadiwatchignore" ""
            in
            let relevant_change =
              spawn_delayed_write ~delay_s:3 workspace "docs/notes.txt"
                "updated notes\n"
            in
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--poll-ms";
                  "50";
                  "--debounce-ms";
                  "20";
                  "--max-runs";
                  "2";
                  "run";
                  "demo";
                ]
            in
            ignore (Unix.waitpid [] reload_ignore);
            ignore (Unix.waitpid [] relevant_change);
            assert_int_equal 0 watch.status
              "watch should keep running long enough for ignore-file reloads to matter";
            assert_string_contains ~needle:"Watch-config: reloaded" watch.output
              "watch should report that the ignore-file policy reloaded";
            assert_string_contains ~needle:"Watch-run 2: run demo" watch.output
              "watch should rerun after a newly unignored path changes")) );
    ( "reloads manifest watch globs even when includes were previously narrower",
      (fun () ->
        with_temp_dir "wadi-watch-manifest-reload" (fun workspace ->
            write_manifest workspace
              {|
[watch]
include = ["app/**"]
ignore = ["docs/**"]

[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "demo"|};
            write_source workspace "docs/notes.txt" "notes\n";
            let reload_manifest =
              spawn_delayed_write workspace Manifest.default_filename
                {|
[watch]
include = ["app/**", "docs/**"]

[executable.demo]
dir = "app"
main = "main"
|}
            in
            let relevant_change =
              spawn_delayed_write ~delay_s:3 workspace "docs/notes.txt"
                "updated notes\n"
            in
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--poll-ms";
                  "50";
                  "--debounce-ms";
                  "20";
                  "--max-runs";
                  "3";
                  "run";
                  "demo";
                ]
            in
            ignore (Unix.waitpid [] reload_manifest);
            ignore (Unix.waitpid [] relevant_change);
            assert_int_equal 0 watch.status
              "watch should survive a manifest watch-policy edit and keep running";
            assert_string_contains ~needle:"Watch-config: reloaded include=app/**, docs/**"
              watch.output
              "watch should report the broadened manifest include policy";
            assert_string_contains ~needle:"Watch-run 2: run demo" watch.output
              "manifest edits should still rerun the delegated subtool";
            assert_string_contains ~needle:"Watch-run 3: run demo" watch.output
              "watch should apply the reloaded manifest policy to later changes")) );
    ( "reruns build --locked when wadi.lock changes outside included globs",
      (fun () ->
        with_temp_dir "wadi-watch-build-locked" (fun workspace ->
            write_demo_workspace
              ~watch_block:{|
[watch]
include = ["app/**"]
|}
              workspace;
            let locked = run_wadi ~cwd:workspace [ "lock"; "demo" ] in
            assert_int_equal 0 locked.status
              "lock should succeed before watching a locked build";
            let drift_lock =
              spawn_delayed_write workspace "wadi.lock" "{}\n"
            in
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--poll-ms";
                  "50";
                  "--debounce-ms";
                  "20";
                  "--max-runs";
                  "2";
                  "build";
                  "--locked";
                  "demo";
                ]
            in
            ignore (Unix.waitpid [] drift_lock);
            assert_true (watch.status <> 0)
              "watch should surface the failing rerun when the lock snapshot drifts";
            assert_string_contains
              ~needle:"Watch-run 2: build --locked demo"
              watch.output
              "watch should rerun build when wadi.lock changes outside the include globs";
            assert_string_contains ~needle:"lock validation failed against"
              watch.output
              "locked build reruns should validate the changed lock file")) );
    ( "does not watch wadi.lock for an ordinary build",
      (fun () ->
        with_temp_dir "wadi-watch-build-unlocked" (fun workspace ->
            write_demo_workspace
              ~watch_block:{|
[watch]
include = ["app/**"]
|}
              workspace;
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--poll-ms";
                  "50";
                  "--debounce-ms";
                  "20";
                  "--max-runs";
                  "1";
                  "build";
                  "demo";
                ]
            in
            assert_int_equal 0 watch.status
              "watch should allow a non-locking build to run once successfully";
            assert_string_contains
              ~needle:"Watch-root-files: wadi.toml, .wadiwatchignore"
              watch.output
              "ordinary builds should not add wadi.lock to the watched root-file set";
            assert_string_not_contains
              ~needle:"Watch-root-files: wadi.toml, .wadiwatchignore, wadi.lock"
              watch.output
              "ordinary builds should not report wadi.lock as a watched root file";
            assert_string_contains
              ~needle:"Watch-root-file-roles: wadi.toml=reload+rerun, .wadiwatchignore=reload-only"
              watch.output
              "ordinary builds should report only manifest reload and ignore-file policy roles")) );
    ( "reruns install --warn-locked when wadi.lock changes outside included globs",
      (fun () ->
        with_temp_dir "wadi-watch-install-locked" (fun workspace ->
            write_demo_workspace
              ~watch_block:{|
[watch]
include = ["app/**"]
|}
              workspace;
            let locked = run_wadi ~cwd:workspace [ "lock"; "demo" ] in
            assert_int_equal 0 locked.status
              "lock should succeed before watching a lock-aware install";
            let prefix = Filename.concat workspace "_stage" in
            let drift_lock =
              spawn_delayed_write workspace "wadi.lock" "{}\n"
            in
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--poll-ms";
                  "50";
                  "--debounce-ms";
                  "20";
                  "--max-runs";
                  "2";
                  "install";
                  "--warn-locked";
                  "--prefix";
                  prefix;
                  "demo";
                ]
            in
            ignore (Unix.waitpid [] drift_lock);
            assert_int_equal 0 watch.status
              "watch should keep going when install only warns on lock drift";
            assert_string_contains
              ~needle:"Watch-run 2: install --warn-locked --prefix"
              watch.output
              "watch should rerun install when wadi.lock changes outside the include globs";
            assert_string_contains ~needle:"lock validation failed against"
              watch.output
              "warn-locked install reruns should report the changed lock file")) );
    ( "reports and watches wadi.lock for doctor by default",
      (fun () ->
        with_temp_dir "wadi-watch-doctor-locked" (fun workspace ->
            write_demo_workspace
              ~watch_block:{|
[watch]
include = ["app/**"]
|}
              workspace;
            let locked = run_wadi ~cwd:workspace [ "lock"; "demo" ] in
            assert_int_equal 0 locked.status
              "lock should succeed before watching doctor";
            let drift_lock =
              spawn_delayed_write workspace "wadi.lock" "{}\n"
            in
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--poll-ms";
                  "50";
                  "--debounce-ms";
                  "20";
                  "--max-runs";
                  "2";
                  "doctor";
                  "demo";
                ]
            in
            ignore (Unix.waitpid [] drift_lock);
            assert_int_equal 0 watch.status
              "doctor should keep warning, not failing, when the lock file drifts";
            assert_string_contains
              ~needle:"Watch-root-files: wadi.toml, .wadiwatchignore, wadi.lock"
              watch.output
              "watch should report lock-aware root files for doctor";
            assert_string_contains
              ~needle:"Watch-root-file-roles: wadi.toml=reload+rerun, .wadiwatchignore=reload-only, wadi.lock=rerun-only"
              watch.output
              "watch should explain which root files reload policy versus only trigger reruns";
            assert_string_contains ~needle:"Watch-run 2: doctor demo" watch.output
              "watch should rerun doctor when wadi.lock changes outside the include globs";
            assert_string_contains ~needle:"failed to read"
              watch.output
              "doctor reruns should inspect the changed lock file")) );
    ( "keeps the last watch policy after an ignore-file reload error",
      (fun () ->
        with_temp_dir "wadi-watch-ignore-reload-error" (fun workspace ->
            write_manifest workspace
              {|
[watch]
include = ["app/**", "docs/**"]

[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "first"|};
            write_source workspace "docs/notes.txt" "notes\n";
            write_workspace_file workspace ".wadiwatchignore" {|
docs/**
|};
            let break_ignore_file =
              spawn_delayed_script workspace "break-ignore-file"
                (Printf.sprintf "rm -f %s\nmkdir %s"
                   (Filename.quote
                      (Filename.concat workspace ".wadiwatchignore"))
                   (Filename.quote
                      (Filename.concat workspace ".wadiwatchignore")))
            in
            let relevant_change =
              spawn_delayed_write ~delay_s:3 workspace "app/main.ml"
                {|let () = print_endline "second"|}
            in
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--poll-ms";
                  "50";
                  "--debounce-ms";
                  "20";
                  "--max-runs";
                  "2";
                  "run";
                  "demo";
                ]
            in
            ignore (Unix.waitpid [] break_ignore_file);
            ignore (Unix.waitpid [] relevant_change);
            assert_int_equal 0 watch.status
              "watch should keep running after a broken ignore-file reload";
            assert_string_contains
              ~needle:"Watch-config: keeping previous policy after reload error:"
              watch.output
              "watch should explain that it retained the prior watch policy";
            assert_string_contains ~needle:"Watch-run 2: run demo" watch.output
              "watch should still rerun on later source edits after the reload error";
            assert_string_contains ~needle:"second\n" watch.output
              "watch should continue forwarding delegated subtool output after the warning")) );
    ( "stops on the first failing run without --keep-going",
      (fun () ->
        with_temp_dir "wadi-watch-stop" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml" {|let () = exit 7|};
            let watch =
              run_wadi ~cwd:workspace
                [ "watch"; "--max-runs"; "2"; "run"; "demo" ]
            in
            assert_int_equal 7 watch.status
              "watch should forward the first failing run status by default";
            assert_string_contains ~needle:"Watch-result 1: exit 7" watch.output
              "watch should report the failing child exit status";
            assert_string_not_contains ~needle:"Watch-waiting:" watch.output
              "watch should stop immediately instead of waiting for changes")) );
    ( "continues after a failing run when --keep-going is set",
      (fun () ->
        with_temp_dir "wadi-watch-keep-going" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml" {|let () = exit 7|};
            let mutator =
              spawn_delayed_write workspace "app/main.ml"
                {|let () = print_endline "fixed"|}
            in
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--keep-going";
                  "--poll-ms";
                  "50";
                  "--debounce-ms";
                  "20";
                  "--max-runs";
                  "2";
                  "run";
                  "demo";
                ]
            in
            ignore (Unix.waitpid [] mutator);
            assert_int_equal 0 watch.status
              "watch should keep going until a later successful run";
            assert_string_contains ~needle:"Watch-result 1: exit 7" watch.output
              "watch should report the initial failure before continuing";
            assert_string_contains ~needle:"Watch-change: rerunning" watch.output
              "watch should keep waiting for a source change after a failure";
            assert_string_contains ~needle:"fixed\n" watch.output
              "watch should include the successful rerun output")) );
    ( "rejects watching the watch subtool itself",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let watch = run_wadi ~cwd:workspace [ "watch"; "watch"; "build" ] in
            assert_true (watch.status <> 0)
              "watch should reject recursive watch invocations";
            assert_string_contains
              ~needle:"watch cannot watch itself; choose another subtool"
              watch.output
              "watch should explain the recursive-command rejection")) );
    ( "ignores matching paths before rerunning",
      (fun () ->
        with_temp_dir "wadi-watch-ignore" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "first"|};
            write_source workspace "docs/notes.txt" "notes\n";
            let ignored_change =
              spawn_delayed_write ~delay_s:1 workspace "docs/notes.txt"
                "updated notes\n"
            in
            let relevant_change =
              spawn_delayed_write ~delay_s:3 workspace "app/main.ml"
                {|let () = print_endline "second"|}
            in
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--ignore";
                  "docs/**";
                  "--poll-ms";
                  "50";
                  "--debounce-ms";
                  "20";
                  "--max-runs";
                  "2";
                  "run";
                  "demo";
                ]
            in
            ignore (Unix.waitpid [] ignored_change);
            ignore (Unix.waitpid [] relevant_change);
            assert_int_equal 0 watch.status
              "watch should still complete successfully when ignored files change first";
            assert_string_contains ~needle:"Watch-run 2: run demo" watch.output
              "watch should rerun once a non-ignored file changes";
            assert_string_contains ~needle:"second\n" watch.output
              "watch should wait for the relevant source change before rerunning")) );
    ( "can restrict watch inputs to included globs",
      (fun () ->
        with_temp_dir "wadi-watch-include" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "first"|};
            write_source workspace "README.md" "readme\n";
            let unrelated_change =
              spawn_delayed_write ~delay_s:1 workspace "README.md"
                "updated readme\n"
            in
            let relevant_change =
              spawn_delayed_write ~delay_s:3 workspace "app/main.ml"
                {|let () = print_endline "second"|}
            in
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--include";
                  "app/**";
                  "--poll-ms";
                  "50";
                  "--debounce-ms";
                  "20";
                  "--max-runs";
                  "2";
                  "run";
                  "demo";
                ]
            in
            ignore (Unix.waitpid [] unrelated_change);
            ignore (Unix.waitpid [] relevant_change);
            assert_int_equal 0 watch.status
              "watch should rerun successfully when the included tree changes";
            assert_string_contains ~needle:"Watch-run 2: run demo" watch.output
              "watch should rerun after an included path changes";
            assert_string_contains ~needle:"second\n" watch.output
              "watch should ignore changes outside the included glob set")) );
    ( "uses persisted manifest watch globs",
      (fun () ->
        with_temp_dir "wadi-watch-manifest-globs" (fun workspace ->
            write_manifest workspace
              {|
[watch]
include = ["app/**"]
ignore = ["docs/**"]

[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "first"|};
            write_source workspace "docs/notes.txt" "notes\n";
            let ignored_change =
              spawn_delayed_write ~delay_s:1 workspace "docs/notes.txt"
                "updated notes\n"
            in
            let relevant_change =
              spawn_delayed_write ~delay_s:3 workspace "app/main.ml"
                {|let () = print_endline "second"|}
            in
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--poll-ms";
                  "50";
                  "--debounce-ms";
                  "20";
                  "--max-runs";
                  "2";
                  "run";
                  "demo";
                ]
            in
            ignore (Unix.waitpid [] ignored_change);
            ignore (Unix.waitpid [] relevant_change);
            assert_int_equal 0 watch.status
              "watch should use persisted root-manifest include and ignore globs";
            assert_string_contains ~needle:"Watch-run 2: run demo" watch.output
              "watch should rerun after a manifest-included path changes";
            assert_string_contains ~needle:"second\n" watch.output
              "watch should keep ignoring persisted ignored paths")) );
    ( "loads extra ignore globs from .wadiwatchignore",
      (fun () ->
        with_temp_dir "wadi-watch-ignore-file" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "first"|};
            write_source workspace "docs/notes.txt" "notes\n";
            write_workspace_file workspace ".wadiwatchignore"
              {|
# Ignore generated docs noise.
docs/**
|};
            let ignored_change =
              spawn_delayed_write ~delay_s:1 workspace "docs/notes.txt"
                "updated notes\n"
            in
            let relevant_change =
              spawn_delayed_write ~delay_s:3 workspace "app/main.ml"
                {|let () = print_endline "second"|}
            in
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--poll-ms";
                  "50";
                  "--debounce-ms";
                  "20";
                  "--max-runs";
                  "2";
                  "run";
                  "demo";
                ]
            in
            ignore (Unix.waitpid [] ignored_change);
            ignore (Unix.waitpid [] relevant_change);
            assert_int_equal 0 watch.status
              "watch should merge ignore globs from the workspace ignore file";
            assert_string_contains ~needle:"Watch-run 2: run demo" watch.output
              "watch should rerun after a non-ignored source change";
            assert_string_contains ~needle:"second\n" watch.output
              "watch should keep the ignore-file-filtered docs tree from retriggering")) );
    ( "rejects conflicting inner --workspace flags",
      (fun () ->
        with_temp_dir "wadi-watch-conflict" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "demo"|};
            let other_workspace = Filename.concat workspace "other-workspace" in
            Unix.mkdir other_workspace 0o755;
            write_manifest other_workspace
              {|
[executable.other]
dir = "app"
main = "main"
|};
            write_source other_workspace "app/main.ml"
              {|let () = print_endline "other"|};
            let watch =
              run_wadi ~cwd:workspace
                [
                  "watch";
                  "--max-runs";
                  "1";
                  "run";
                  "--workspace";
                  other_workspace;
                  "demo";
                ]
            in
            assert_true (watch.status <> 0)
              "watch should reject an inner subtool workspace that points elsewhere";
            assert_string_contains ~needle:"conflicts with watched workspace"
              watch.output
              "watch should explain why differing workspaces are unsafe")) );
    ( "allows a redundant inner --workspace for the same tree",
      (fun () ->
        with_temp_dir "wadi-watch-same-workspace" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml"
              {|let () = print_endline "demo"|};
            let watch =
              run_wadi ~cwd:workspace
                [ "watch"; "--max-runs"; "1"; "run"; "--workspace"; "."; "demo" ]
            in
            assert_int_equal 0 watch.status
              "watch should allow a redundant inner workspace that resolves to the same root";
            assert_string_contains ~needle:"Watch-run 1: run --workspace . demo"
              watch.output
              "watch should still execute the selected subtool when the workspace matches";
            assert_string_contains ~needle:"demo\n" watch.output
              "watch should keep forwarding the delegated subtool output")) );
  ]
