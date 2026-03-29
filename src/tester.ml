type failure = {
  name : string;
  package_path : string option;
  status : int;
}

let ( let* ) = Result.bind

let kind_article = function
  | "executable" -> "an"
  | _ -> "a"

let display_name name package_path =
  name ^ Manifest.package_suffix package_path

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
                (Printf.sprintf
                   "target '%s' is %s %s; oasis test only supports tests" name
                   (kind_article kind) kind))
    in
    loop [] requested_targets

let find_built_test name artifacts =
  List.find_map
    (function
      | Builder.Built_test test when test.name = name -> Some test.binary
      | _ -> None)
    artifacts

let emit_output output =
  if output <> "" then print_string output

let report_failures failures total =
  let failed_names =
    List.map
      (fun failure -> display_name failure.name failure.package_path)
      failures
  in
  prerr_endline
    (Printf.sprintf "%d/%d tests failed" (List.length failures) total);
  prerr_endline ("Failed tests: " ^ String.concat ", " failed_names)

let run ~workspace_root ~verbose ~backend_request ?profile ~requested_targets
    workspace =
  let* tests = resolve_requested_targets workspace requested_targets in
  let* build_result =
    Builder.build ~workspace_root ~verbose
      ~requested_targets:
        (List.map (fun (test : Manifest.test_target) -> test.name) tests)
      ~backend_request ?profile workspace
  in
  let rec loop (failures : failure list) (tests : Manifest.test_target list) =
    match tests with
    | [] -> List.rev failures
    | test :: rest -> (
        let test_name = display_name test.name test.package_path in
        match find_built_test test.name build_result.Builder.artifacts with
        | None ->
            prerr_endline
              (Printf.sprintf
                 "not ok - %s (build completed without a matching test binary)"
                 test_name);
            loop
              ({ name = test.name; package_path = test.package_path; status = 1 }
              :: failures)
              rest
        | Some binary ->
            let outcome = Process.run_capture ~verbose binary [] in
            emit_output outcome.output;
            if outcome.status = 0 then (
              print_endline ("ok - " ^ test_name);
              loop failures rest)
            else (
              prerr_endline
                (Printf.sprintf "not ok - %s (exit %d)" test_name outcome.status);
              loop
                ({
                   name = test.name;
                   package_path = test.package_path;
                   status = outcome.status;
                 }
                :: failures)
                rest))
  in
  let failures = loop [] tests in
  if failures = [] then (
    print_endline (Printf.sprintf "All %d tests passed" (List.length tests));
    Ok 0)
  else (
    report_failures failures (List.length tests);
    Ok 1)
