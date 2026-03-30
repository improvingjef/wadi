type failure = { name : string; package_path : string option; status : int }

let ( let* ) = Result.bind
let kind_article = function "executable" -> "an" | _ -> "a"
let display_name name package_path = name ^ Manifest.package_suffix package_path

let test_targets workspace =
  List.filter_map
    (function
      | Manifest.Test test -> Some test
      | Manifest.Library _ | Manifest.Executable _ -> None)
    workspace.Manifest.targets

let resolve_requested_targets workspace requested_targets =
  let requested_targets = String_util.dedup_preserve requested_targets in
  if requested_targets = [] then
    match test_targets workspace with
    | [] -> Error "workspace does not define any tests to run"
    | tests -> Ok tests
  else
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | name :: rest -> (
          match
            List.find_opt
              (fun target -> Manifest.target_name target = name)
              workspace.Manifest.targets
          with
          | None -> Error (Printf.sprintf "unknown target '%s'" name)
          | Some (Manifest.Test test) -> loop (test :: acc) rest
          | Some target ->
              let kind = Manifest.target_kind_name target in
              Error
                (Printf.sprintf "target '%s' is %s %s; wadi test only supports tests" name
                   (kind_article kind) kind))
    in
    loop [] requested_targets

let find_built_test name artifacts =
  List.find_map
    (function
      | Builder.Built_test test when test.name = name -> Some test.binary | _ -> None)
    artifacts

let emit_output output = if output <> "" then print_string output

let report_failures failures total =
  let failed_names =
    List.map (fun failure -> display_name failure.name failure.package_path) failures
  in
  prerr_endline (Printf.sprintf "%d/%d tests failed" (List.length failures) total);
  prerr_endline ("Failed tests: " ^ String.concat ", " failed_names)

let cpu_count () =
  try
    let outcome = Process.run_capture "sysctl" [ "-n"; "hw.logicalcpu" ] in
    if outcome.status = 0 then int_of_string (String.trim outcome.output)
    else raise Not_found
  with _ -> (
    try
      let outcome = Process.run_capture "nproc" [] in
      if outcome.status = 0 then int_of_string (String.trim outcome.output) else 4
    with _ -> 4)

let default_jobs () = max 1 (cpu_count ())

type test_slot = {
  pid : int;
  test_name : string;
  name : string;
  package_path : string option;
  read_fd : Unix.file_descr;
}

let launch_test ~verbose binary test_name name package_path =
  let read_fd, write_fd = Unix.pipe () in
  let pid =
    Process.spawn ~stdout_fd:write_fd ~stderr_fd:write_fd ~extra_closes:[ read_fd ] binary
      []
  in
  if verbose then prerr_endline binary;
  Process.close_noerr write_fd;
  { pid; test_name; name; package_path; read_fd }

type test_result = {
  r_test_name : string;
  r_name : string;
  r_package_path : string option;
  r_output : string;
  r_status : int;
  r_no_binary : bool;
}

let run ~workspace_root ~verbose ~backend_request ?profile ?(jobs = 0) ~requested_targets
    workspace =
  let* tests = resolve_requested_targets workspace requested_targets in
  let* build_result =
    Builder.build ~workspace_root ~verbose
      ~requested_targets:(List.map (fun (test : Manifest.test_target) -> test.name) tests)
      ~backend_request ?profile workspace
  in
  let jobs = if jobs <= 0 then default_jobs () else jobs in
  let work_items =
    List.map
      (fun (test : Manifest.test_target) ->
        let test_name = display_name test.name test.package_path in
        let binary = find_built_test test.name build_result.Builder.artifacts in
        (test, test_name, binary))
      tests
  in
  let results = Array.make (List.length work_items) None in
  let pending = Queue.create () in
  List.iteri (fun i item -> Queue.add (i, item) pending) work_items;
  let active = ref [] in
  let launch_next () =
    if not (Queue.is_empty pending) then begin
      let idx, (test, test_name, binary) = Queue.pop pending in
      match binary with
      | None ->
          results.(idx) <-
            Some
              {
                r_test_name = test_name;
                r_name = test.Manifest.name;
                r_package_path = test.Manifest.package_path;
                r_output = "";
                r_status = 1;
                r_no_binary = true;
              }
      | Some bin ->
          let slot =
            launch_test ~verbose bin test_name test.Manifest.name
              test.Manifest.package_path
          in
          active := (idx, slot) :: !active
    end
  in
  for _ = 1 to min jobs (Queue.length pending) do
    launch_next ()
  done;
  while !active <> [] do
    let rec wait () =
      try Unix.waitpid [] (-1) with Unix.Unix_error (Unix.EINTR, _, _) -> wait ()
    in
    let finished_pid, unix_status = wait () in
    match List.find_opt (fun (_, s) -> s.pid = finished_pid) !active with
    | None -> ()
    | Some (idx, slot) ->
        let output = Process.read_all slot.read_fd in
        let status = Process.status_to_code unix_status in
        results.(idx) <-
          Some
            {
              r_test_name = slot.test_name;
              r_name = slot.name;
              r_package_path = slot.package_path;
              r_output = output;
              r_status = status;
              r_no_binary = false;
            };
        active := List.filter (fun (_, s) -> s.pid <> finished_pid) !active;
        launch_next ()
  done;
  let failures = ref [] in
  Array.iter
    (function
      | None -> ()
      | Some r ->
          emit_output r.r_output;
          if r.r_status = 0 then print_endline ("ok - " ^ r.r_test_name)
          else begin
            if r.r_no_binary then
              prerr_endline
                (Printf.sprintf
                   "not ok - %s (build completed without a matching test binary)"
                   r.r_test_name)
            else
              prerr_endline
                (Printf.sprintf "not ok - %s (exit %d)" r.r_test_name r.r_status);
            failures :=
              { name = r.r_name; package_path = r.r_package_path; status = r.r_status }
              :: !failures
          end)
    results;
  let failures = List.rev !failures in
  if failures = [] then (
    print_endline (Printf.sprintf "All %d tests passed" (List.length tests));
    Ok 0)
  else (
    report_failures failures (List.length tests);
    Ok 1)
