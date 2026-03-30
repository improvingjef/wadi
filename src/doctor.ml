type check_state =
  | Pass
  | Warn
  | Fail

type check = {
  name : string;
  state : check_state;
  details : string list;
}

type summary = {
  passed : int;
  warned : int;
  failed : int;
}

type report = {
  workspace_name : string option;
  workspace_root : string;
  profile : string;
  requested_targets : string list;
  backend_request : Toolchain.backend_request;
  checks : check list;
  summary : summary;
}

type lock_policy =
  | Ignore_lock
  | Warn_locked
  | Require_locked

let ( let* ) = Result.bind

let resolve_profile workspace = function
  | Some profile when String.trim profile <> "" -> profile
  | Some _ | None -> Manifest.default_profile workspace

let check name state details = { name; state; details }

let state_name = function
  | Pass -> "pass"
  | Warn -> "warn"
  | Fail -> "fail"

let summarize checks =
  List.fold_left
    (fun summary check ->
      match check.state with
      | Pass -> { summary with passed = summary.passed + 1 }
      | Warn -> { summary with warned = summary.warned + 1 }
      | Fail -> { summary with failed = summary.failed + 1 })
    { passed = 0; warned = 0; failed = 0 }
    checks

let render_requested_targets requested_targets =
  if requested_targets = [] then "all" else String.concat ", " requested_targets

let render_result render_ok = function
  | Ok value -> render_ok value
  | Error message -> "error: " ^ String.trim message

let manifest_check ~workspace_root ~profile workspace requested_targets =
  let target_names = List.map Manifest.target_name workspace.Manifest.targets in
  check "manifest" Pass
    [
      "manifest: " ^ Filename.concat workspace_root Manifest.default_filename;
      "profile: " ^ profile;
      ("targets: "
      ^
      match target_names with
      | [] -> "none"
      | targets -> String.concat ", " targets);
      "requested-targets: " ^ render_requested_targets requested_targets;
    ]

let graph_check workspace requested_targets =
  match Builder.resolve_build_order workspace requested_targets with
  | Ok order ->
      check "graph" Pass
        [
          ("build-order: "
          ^
          match List.map Manifest.target_display_name order with
          | [] -> "none"
          | names -> String.concat " -> " names);
        ]
  | Error message -> check "graph" Fail [ String.trim message ]

let toolchain_check ~session backend_request =
  let report = Toolchain.inspect ~session () in
  let details =
    [
      Toolchain.render_command_report "ocamlc" report.ocamlc;
      Toolchain.render_command_report "ocamlopt" report.ocamlopt;
      Toolchain.render_command_report "ocamldep" report.ocamldep;
      Toolchain.render_command_report "ocamlfind" report.ocamlfind;
      "backend-request: " ^ Toolchain.backend_request_name backend_request;
      ("selected-backend: "
      ^ render_result Toolchain.backend_name report.selected_backend);
      "compiler-version: " ^ render_result Fun.id report.compiler_version;
      "stdlib: " ^ render_result Fun.id report.stdlib;
      (match report.unix_dir with
      | Ok (Some path) -> "unix-library-dir: " ^ path
      | Ok None -> "unix-library-dir: unavailable"
      | Error message -> "unix-library-dir: error: " ^ String.trim message);
      ("package-roots: "
      ^
      render_result
        (function
          | [] -> "none"
          | roots -> String.concat ", " roots)
        report.package_roots);
    ]
  in
  let state =
    match
      (report.selected_backend, report.compiler_version, report.stdlib)
    with
    | Ok _, Ok _, Ok _ -> (
        match report.package_roots with
        | Ok _ -> Pass
        | Error _ -> Warn)
    | _ -> Fail
  in
  check "toolchain" state details

let deps_check ~session workspace requested_targets =
  match Deps.report_for_targets ~session workspace requested_targets with
  | Error message -> check "packages" Fail [ String.trim message ]
  | Ok report ->
      let target_details =
        List.map
          (fun (target : Deps.target_report) ->
            Printf.sprintf "%s: %s"
              (Manifest.target_display_name target.target)
              (match target.closure_packages with
              | [] -> "no external packages"
              | packages -> String.concat ", " packages))
          report.targets
      in
      let package_roots =
        match report.package_roots with
        | Ok [] -> [ "package-roots: none" ]
        | Ok roots -> [ "package-roots: " ^ String.concat ", " roots ]
        | Error message ->
            [ "package-roots: error: " ^ String.trim message ]
      in
      let state =
        match report.package_roots with
        | Ok _ -> Pass
        | Error _ -> Warn
      in
      check "packages" state (package_roots @ target_details)

let lock_check ~lock_policy ~workspace_root workspace requested_targets =
  match lock_policy with
  | Ignore_lock ->
      check "lock" Pass [ "lock validation skipped" ]
  | Warn_locked | Require_locked -> (
      let lock_path = Locker.default_lock_path workspace_root in
      match Locker.validate_current ~workspace_root workspace requested_targets with
      | Ok () -> check "lock" Pass [ "lock file is current: " ^ lock_path ]
      | Error message ->
          let state =
            match lock_policy with
            | Require_locked -> Fail
            | Warn_locked | Ignore_lock -> Warn
          in
          check "lock" state [ String.trim message ])

let report ~workspace_root ?(requested_targets = [])
    ?(backend_request = Toolchain.Auto) ?profile ~lock_policy workspace =
  let workspace_root = Fs.realpath workspace_root in
  let profile = resolve_profile workspace profile in
  let session = Toolchain.create_session () in
  let checks =
    [
      manifest_check ~workspace_root ~profile workspace requested_targets;
      graph_check workspace requested_targets;
      toolchain_check ~session backend_request;
      deps_check ~session workspace requested_targets;
      lock_check ~lock_policy ~workspace_root workspace requested_targets;
    ]
  in
  let summary = summarize checks in
  Ok
    {
      workspace_name = workspace.Manifest.name;
      workspace_root;
      profile;
      requested_targets;
      backend_request;
      checks;
      summary;
    }

let has_failures (report : report) = report.summary.failed > 0

let render_check (check : check) =
  String.concat "\n"
    ((Printf.sprintf "%s: %s" check.name (state_name check.state))
    :: List.map (fun detail -> "- " ^ detail) check.details)

let render_report (report : report) =
  String.concat "\n"
    ([
       ("Workspace: "
       ^
       match report.workspace_name with
       | Some name -> name
       | None -> "unnamed");
       "Workspace-root: " ^ report.workspace_root;
       "Profile: " ^ report.profile;
       "Requested-targets: " ^ render_requested_targets report.requested_targets;
       "Backend-request: "
       ^ Toolchain.backend_request_name report.backend_request;
       Printf.sprintf "Summary: pass=%d warn=%d fail=%d" report.summary.passed
         report.summary.warned report.summary.failed;
     ]
    @ List.concat_map (fun check -> [ ""; render_check check ]) report.checks
    @ [ "" ])

let json_string text = "\"" ^ String_util.json_escape text ^ "\""

let json_array render items =
  "[" ^ String.concat ", " (List.map render items) ^ "]"

let json_option render = function
  | Some value -> render value
  | None -> "null"

let render_json_check (check : check) =
  String.concat "\n"
    [
      "    {";
      "      \"name\": " ^ json_string check.name ^ ",";
      "      \"state\": " ^ json_string (state_name check.state) ^ ",";
      "      \"details\": " ^ json_array json_string check.details;
      "    }";
    ]

let render_json_report (report : report) =
  let checks =
    match report.checks with
    | [] -> "[]"
    | checks ->
        "[\n"
        ^ String.concat ",\n" (List.map render_json_check checks)
        ^ "\n  ]"
  in
  String.concat "\n"
    [
      "{";
      "  \"workspace\": "
      ^
      json_option json_string report.workspace_name
      ^ ",";
      "  \"workspace_root\": " ^ json_string report.workspace_root ^ ",";
      "  \"profile\": " ^ json_string report.profile ^ ",";
      "  \"requested_targets\": "
      ^ json_array json_string report.requested_targets
      ^ ",";
      "  \"backend_request\": "
      ^ json_string (Toolchain.backend_request_name report.backend_request)
      ^ ",";
      "  \"summary\": {";
      "    \"pass\": " ^ string_of_int report.summary.passed ^ ",";
      "    \"warn\": " ^ string_of_int report.summary.warned ^ ",";
      "    \"fail\": " ^ string_of_int report.summary.failed;
      "  },";
      "  \"checks\": " ^ checks;
      "}";
      "";
    ]
