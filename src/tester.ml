type failure = {
  name : string;
  status : int;
}

let ( let* ) = Result.bind

let kind_article = function
  | "executable" -> "an"
  | _ -> "a"

let test_names workspace =
  List.filter_map
    (function
      | Manifest.Test test -> Some test.name
      | Manifest.Library _ | Manifest.Executable _ -> None)
    workspace.Manifest.targets

let resolve_requested_targets workspace requested_targets =
  let requested_targets = String_util.dedup_preserve requested_targets in
  if requested_targets = [] then
    match test_names workspace with
    | [] -> Error "workspace does not define any tests to run"
    | names -> Ok names
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
          | Some (Manifest.Test _) -> loop (name :: acc) rest
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
  let failed_names = List.map (fun failure -> failure.name) failures in
  prerr_endline
    (Printf.sprintf "%d/%d tests failed" (List.length failures) total);
  prerr_endline ("Failed tests: " ^ String.concat ", " failed_names)

let run ~workspace_root ~verbose ~backend_request ~requested_targets workspace =
  let* target_names = resolve_requested_targets workspace requested_targets in
  let* build_result =
    Builder.build ~workspace_root ~verbose ~requested_targets:target_names
      ~backend_request workspace
  in
  let rec loop failures = function
    | [] -> List.rev failures
    | name :: rest -> (
        match find_built_test name build_result.Builder.artifacts with
        | None ->
            prerr_endline
              (Printf.sprintf
                 "not ok - %s (build completed without a matching test binary)"
                 name);
            loop ({ name; status = 1 } :: failures) rest
        | Some binary ->
            let outcome = Process.run_capture ~verbose binary [] in
            emit_output outcome.output;
            if outcome.status = 0 then (
              print_endline ("ok - " ^ name);
              loop failures rest)
            else (
              prerr_endline
                (Printf.sprintf "not ok - %s (exit %d)" name outcome.status);
              loop ({ name; status = outcome.status } :: failures) rest))
  in
  let failures = loop [] target_names in
  if failures = [] then (
    print_endline (Printf.sprintf "All %d tests passed" (List.length target_names));
    Ok 0)
  else (
    report_failures failures (List.length target_names);
    Ok 1)
