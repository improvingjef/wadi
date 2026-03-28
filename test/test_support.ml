type case = string * (unit -> unit)

let fail message = raise (Failure message)

let assert_true condition message =
  if not condition then fail message

let assert_int_equal expected actual message =
  if expected <> actual then
    fail
      (Printf.sprintf "%s\nexpected: %d\nactual: %d" message expected actual)

let assert_string_equal expected actual message =
  if expected <> actual then
    fail
      (Printf.sprintf "%s\nexpected: %S\nactual: %S" message expected actual)

let assert_string_contains ~needle haystack message =
  let needle_length = String.length needle in
  let haystack_length = String.length haystack in
  let rec loop index =
    if index + needle_length > haystack_length then false
    else if String.sub haystack index needle_length = needle then true
    else loop (index + 1)
  in
  if not (loop 0) then
    fail
      (Printf.sprintf "%s\nmissing substring: %S\nhaystack:\n%s" message needle
         haystack)

let assert_string_not_contains ~needle haystack message =
  let needle_length = String.length needle in
  let haystack_length = String.length haystack in
  let rec loop index =
    if index + needle_length > haystack_length then false
    else if String.sub haystack index needle_length = needle then true
    else loop (index + 1)
  in
  if loop 0 then
    fail
      (Printf.sprintf "%s\nunexpected substring: %S\nhaystack:\n%s" message
         needle haystack)

let assert_file_exists path =
  assert_true (Fs.exists path) (Printf.sprintf "expected file to exist: %s" path)

let string_of_wait_status = function
  | Unix.WEXITED code -> Printf.sprintf "exited %d" code
  | Unix.WSIGNALED signal -> Printf.sprintf "signaled %d" signal
  | Unix.WSTOPPED signal -> Printf.sprintf "stopped %d" signal

let assert_wait_status_exited expected status message =
  match status with
  | Unix.WEXITED actual -> assert_int_equal expected actual message
  | _ ->
      fail
        (Printf.sprintf "%s\nexpected: exited %d\nactual: %s" message expected
           (string_of_wait_status status))

let assert_wait_status_signaled expected status message =
  match status with
  | Unix.WSIGNALED actual -> assert_int_equal expected actual message
  | _ ->
      fail
        (Printf.sprintf "%s\nexpected: signaled %d\nactual: %s" message expected
           (string_of_wait_status status))

let expect_ok = function
  | Ok value -> value
  | Error message -> fail ("expected Ok but got Error: " ^ message)

let expect_error = function
  | Ok _ -> fail "expected Error but got Ok"
  | Error message -> message

let with_temp_dir prefix f =
  let path = Filename.temp_file prefix ".tmp" in
  Unix.unlink path;
  Unix.mkdir path 0o755;
  Fun.protect ~finally:(fun () -> Fs.remove_tree path) (fun () -> f path)

let fixture_root name =
  Filename.concat (Filename.concat (Sys.getcwd ()) "test/fixtures") name

let with_fixture name f =
  with_temp_dir ("oasis-" ^ name) (fun path ->
      Fs.copy_tree ~src:(fixture_root name) ~dst:path;
      f path)

let oasis_bin () =
  try Sys.getenv "OASIS_BIN" with
  | Not_found -> fail "OASIS_BIN is not set"

let run_oasis ~cwd args = Process.run_capture ~cwd (oasis_bin ()) args

let run_binary path args = Process.run_capture path args

let manifest_path workspace =
  Filename.concat workspace Manifest.default_filename

let write_workspace_file workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let write_manifest workspace contents =
  Fs.write_file (manifest_path workspace) contents
