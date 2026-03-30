open Test_support

let cases =
  [
    ( "summarizes current target state before the first build",
      fun () ->
        with_fixture "hello" (fun workspace ->
            let status = run_wadi ~cwd:workspace [ "status" ] in
            assert_int_equal 0 status.status
              "status should summarize a workspace without compiling it";
            assert_string_contains ~needle:"Summary: rebuilt=2 regenerated=0 reused=0"
              status.output "status should report both hello targets as pending rebuilds";
            assert_string_contains ~needle:"1. library greeting" status.output
              "status should list library targets";
            assert_string_contains ~needle:"2. executable hello" status.output
              "status should list executable targets";
            assert_string_contains ~needle:"state: rebuilt" status.output
              "status should report rebuild state before the first build") );
    ( "reports reused targets after a successful build",
      fun () ->
        with_fixture "hello" (fun workspace ->
            let build = run_wadi ~cwd:workspace [ "build" ] in
            assert_int_equal 0 build.status
              "build should succeed before status reports cache hits";
            let status = run_wadi ~cwd:workspace [ "status" ] in
            assert_int_equal 0 status.status "status should still succeed after a build";
            assert_string_contains ~needle:"Summary: rebuilt=0 regenerated=0 reused=2"
              status.output
              "status should report reused artifacts after an unchanged build";
            assert_string_contains ~needle:"state: reused" status.output
              "status should surface reused target state") );
    ( "renders machine-readable status output with explicit backend selection",
      fun () ->
        with_fixture "hello" (fun workspace ->
            let status =
              run_wadi ~cwd:workspace
                [ "status"; "--json"; "--backend"; "bytecode"; "hello" ]
            in
            assert_int_equal 0 status.status
              "status --json should support explicit backend selection";
            assert_string_contains ~needle:"\"backend_request\": \"bytecode\""
              status.output "status JSON should record the requested backend";
            assert_string_contains ~needle:"\"target\": \"hello\"" status.output
              "status JSON should include the selected target";
            assert_string_contains ~needle:"\"state\": \"rebuilt\"" status.output
              "status JSON should report the current target state") );
  ]
