open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let cases =
  [
    ( "validates a healthy workspace and current lock snapshot",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let lock = run_oasis ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should succeed before doctor checks a strict snapshot";
            let doctor = run_oasis ~cwd:workspace [ "doctor"; "--locked" ] in
            assert_int_equal 0 doctor.status
              "doctor should pass for a healthy locked workspace";
            assert_string_contains ~needle:"manifest: pass" doctor.output
              "doctor should report manifest validation";
            assert_string_contains ~needle:"graph: pass" doctor.output
              "doctor should report dependency-graph validation";
            assert_string_contains ~needle:"toolchain: pass" doctor.output
              "doctor should report toolchain health";
            assert_string_contains ~needle:"packages: pass" doctor.output
              "doctor should report package resolution health";
            assert_string_contains ~needle:"lock: pass" doctor.output
              "doctor should report lock validation success";
            assert_string_contains ~needle:"Summary: pass=5 warn=0 fail=0"
              doctor.output
              "doctor should summarize all successful checks")) );
    ( "reports missing external packages directly",
      (fun () ->
        with_temp_dir "oasis-doctor-packages" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
packages = ["definitely_missing_oasis_pkg"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "lib/core.ml" {|let value = "core"|};
            write_source workspace "app/main.ml" {|let () = print_endline Core.value|};
            let doctor = run_oasis ~cwd:workspace [ "doctor"; "demo" ] in
            assert_true (doctor.status <> 0)
              "doctor should fail when required packages cannot be resolved";
            assert_string_contains ~needle:"packages: fail" doctor.output
              "doctor should mark package resolution as failed";
            assert_string_contains
              ~needle:"executable 'demo' requires package 'definitely_missing_oasis_pkg' is not available via ocamlfind"
              doctor.output
              "doctor should keep the direct package-resolution error")) );
    ( "warns about stale lock data by default",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let lock = run_oasis ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should succeed before simulating lock drift";
            Fs.write_file (Filename.concat workspace "oasis.lock") "{}\n";
            let doctor = run_oasis ~cwd:workspace [ "doctor" ] in
            assert_int_equal 0 doctor.status
              "doctor should warn about stale lock data by default";
            assert_string_contains ~needle:"lock: warn" doctor.output
              "doctor should downgrade lock drift to a warning by default";
            assert_string_contains
              ~needle:"failed to read"
              doctor.output
              "doctor should surface the lock parsing error in its warning output")) );
    ( "fails on stale lock data when --locked is requested",
      (fun () ->
        with_fixture "hello" (fun workspace ->
            let lock = run_oasis ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should succeed before simulating a strict lock failure";
            Fs.write_file (Filename.concat workspace "oasis.lock") "{}\n";
            let doctor = run_oasis ~cwd:workspace [ "doctor"; "--locked" ] in
            assert_true (doctor.status <> 0)
              "doctor --locked should fail on stale or unreadable lock data";
            assert_string_contains ~needle:"lock: fail" doctor.output
              "doctor should upgrade lock drift to a failure with --locked";
            assert_string_contains
              ~needle:"Refresh the snapshot with `oasis lock`."
              doctor.output
              "doctor should keep the actionable lock refresh guidance")) );
  ]
