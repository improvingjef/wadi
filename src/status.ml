type target_status = {
  target : string;
  kind : string;
  package_path : string;
  profile : string;
  state : string;
  artifact : string;
  output_dir : string;
  reasons : string list;
  resolution : string list;
}

type summary = {
  rebuilt : int;
  regenerated : int;
  reused : int;
}

type report = {
  workspace_name : string option;
  workspace_root : string;
  profile : string;
  requested_targets : string list;
  backend_request : Toolchain.backend_request;
  selected_backend : string option;
  targets : target_status list;
  summary : summary;
}

let ( let* ) = Result.bind

let resolve_profile workspace = function
  | Some profile when String.trim profile <> "" -> profile
  | Some _ | None -> Manifest.default_profile workspace

let resolution_value prefix lines =
  let prefix_length = String.length prefix in
  List.find_map
    (fun line ->
      if String_util.starts_with ~prefix line then
        Some
          (String.sub line prefix_length (String.length line - prefix_length))
      else None)
    lines

let parse_target_status path text =
  let* json = Locker.parse_json path text in
  let* _ = Locker.json_object_fields json in
  let* target = Locker.json_string_field "target" json in
  let* kind = Locker.json_string_field "kind" json in
  let* package_path = Locker.json_string_field "package_path" json in
  let* profile = Locker.json_string_field "profile" json in
  let* state = Locker.json_string_field "state" json in
  let* artifact = Locker.json_string_field "artifact" json in
  let* output_dir = Locker.json_string_field "output_dir" json in
  let* reasons = Locker.json_string_list_field "reasons" json in
  let* resolution = Locker.json_string_list_field "resolution" json in
  Ok
    {
      target;
      kind;
      package_path;
      profile;
      state;
      artifact;
      output_dir;
      reasons;
      resolution;
    }

let count_states targets =
  List.fold_left
    (fun summary target ->
      match target.state with
      | "rebuilt" -> { summary with rebuilt = summary.rebuilt + 1 }
      | "regenerated" ->
          { summary with regenerated = summary.regenerated + 1 }
      | "reused" -> { summary with reused = summary.reused + 1 }
      | _ -> summary)
    { rebuilt = 0; regenerated = 0; reused = 0 }
    targets

let collect_results items f =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
        let* value = f item in
        loop (value :: acc) rest
  in
  loop [] items

let report ~workspace_root ?(requested_targets = [])
    ?(backend_request = Toolchain.Auto) ?profile workspace =
  let workspace_root = Fs.realpath workspace_root in
  let profile = resolve_profile workspace profile in
  let* explain_reports =
    Builder.explain_current ~workspace_root ~requested_targets ~backend_request
      ~profile workspace
  in
  let* targets =
    collect_results explain_reports (fun (report : Builder.explain_report) ->
        parse_target_status
          ("status report for " ^ report.target_name)
          report.json_report)
  in
  let summary = count_states targets in
  Ok
    {
      workspace_name = workspace.Manifest.name;
      workspace_root;
      profile;
      requested_targets;
      backend_request;
      selected_backend =
        List.find_map
          (fun target -> resolution_value "selected-backend: " target.resolution)
          targets;
      targets;
      summary;
    }

let render_requested_targets requested_targets =
  if requested_targets = [] then "all" else String.concat ", " requested_targets

let render_reasons reasons =
  match reasons with
  | [] -> "none"
  | reasons -> String.concat "; " reasons

let render_target index (target : target_status) =
  String.concat "\n"
    [
      Printf.sprintf "%d. %s %s" index target.kind target.target;
      "   package-path: " ^ target.package_path;
      "   state: " ^ target.state;
      "   artifact: " ^ target.artifact;
      "   output-dir: " ^ target.output_dir;
      "   reasons: " ^ render_reasons target.reasons;
    ]

let render_report (report : report) =
  let header =
    [
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
      ("Selected-backend: "
      ^
      match report.selected_backend with
      | Some backend -> backend
      | None -> "unresolved");
      Printf.sprintf "Summary: rebuilt=%d regenerated=%d reused=%d"
        report.summary.rebuilt report.summary.regenerated report.summary.reused;
    ]
  in
  let targets =
    List.concat_map
      (fun (index, target) -> [ ""; render_target index target ])
      (List.mapi (fun index target -> (index + 1, target)) report.targets)
  in
  String.concat "\n" (header @ targets @ [ "" ])

let json_string text = "\"" ^ String_util.json_escape text ^ "\""

let json_array render items =
  "[" ^ String.concat ", " (List.map render items) ^ "]"

let json_option render = function
  | Some value -> render value
  | None -> "null"

let render_json_target (target : target_status) =
  String.concat "\n"
    [
      "    {";
      "      \"target\": " ^ json_string target.target ^ ",";
      "      \"kind\": " ^ json_string target.kind ^ ",";
      "      \"package_path\": " ^ json_string target.package_path ^ ",";
      "      \"profile\": " ^ json_string target.profile ^ ",";
      "      \"state\": " ^ json_string target.state ^ ",";
      "      \"artifact\": " ^ json_string target.artifact ^ ",";
      "      \"output_dir\": " ^ json_string target.output_dir ^ ",";
      "      \"reasons\": "
      ^ json_array json_string target.reasons
      ^ ",";
      "      \"resolution\": "
      ^ json_array json_string target.resolution;
      "    }";
    ]

let render_json_report (report : report) =
  let targets =
    match report.targets with
    | [] -> "[]"
    | targets ->
        "[\n"
        ^ String.concat ",\n" (List.map render_json_target targets)
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
      "  \"selected_backend\": "
      ^ json_option json_string report.selected_backend
      ^ ",";
      "  \"summary\": {";
      "    \"rebuilt\": " ^ string_of_int report.summary.rebuilt ^ ",";
      "    \"regenerated\": " ^ string_of_int report.summary.regenerated ^ ",";
      "    \"reused\": " ^ string_of_int report.summary.reused;
      "  },";
      "  \"targets\": " ^ targets;
      "}";
      "";
    ]
