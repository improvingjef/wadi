open Test_support

let cases =
  [
    ( "run_capture captures stdout, stderr, and cwd",
      fun () ->
        with_temp_dir "oasis-process-capture" (fun workspace ->
            let subdir = Filename.concat workspace "nested" in
            Fs.ensure_dir subdir;
            let outcome =
              Process.run_capture ~cwd:subdir "/bin/sh"
                [ "-c"; "pwd; printf 'stderr-line\\n' >&2" ]
            in
            assert_int_equal 0 outcome.status
              "run_capture should return zero for successful commands";
            assert_wait_status_exited 0 outcome.unix_status
              "run_capture should preserve a successful raw wait status";
            assert_string_contains ~needle:(subdir ^ "\n") outcome.output
              "run_capture should execute the child in the requested cwd";
            assert_string_contains ~needle:"stderr-line\n" outcome.output
              "run_capture should merge stderr into the captured output"));
    ( "run_capture preserves signal termination details",
      fun () ->
        let outcome = Process.run_capture "/bin/sh" [ "-c"; "kill -TERM $$" ] in
        assert_int_equal (128 + Sys.sigterm) outcome.status
          "signal exits should map to shell-compatible status codes";
        assert_wait_status_signaled Sys.sigterm outcome.unix_status
          "run_capture should retain the raw signaled wait status");
    ( "run_status preserves signal termination details",
      fun () ->
        let outcome = Process.run_status "/bin/sh" [ "-c"; "kill -TERM $$" ] in
        assert_int_equal (128 + Sys.sigterm) outcome.status
          "run_status should map signaled exits to shell-compatible status codes";
        assert_wait_status_signaled Sys.sigterm outcome.unix_status
          "run_status should retain the raw signaled wait status");
    ( "run_capture supports env overrides and stdin",
      fun () ->
        let outcome =
          Process.run_capture ~env:[ ("OASIS_COLOR", "blue") ] ~stdin:"stdin-value"
            "/bin/sh"
            [ "-c"; "printf '%s:' \"$OASIS_COLOR\"; cat" ]
        in
        assert_int_equal 0 outcome.status
          "run_capture should allow stdin text and environment overlays";
        assert_string_equal "blue:stdin-value" outcome.output
          "run_capture should pass stdin and env through to the child");
  ]
