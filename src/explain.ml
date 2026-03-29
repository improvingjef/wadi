type build_status =
  | Rebuilt
  | Regenerated
  | Reused

type target_status = {
  build_status : build_status;
  reasons : string list;
}

let report_path out_dir = Filename.concat out_dir ".oasis-explain"

let json_path out_dir = Filename.concat out_dir ".oasis-explain.json"

let status_name = function
  | Rebuilt -> "rebuilt"
  | Regenerated -> "regenerated"
  | Reused -> "reused"

let needs_rebuild = function
  | Rebuilt -> true
  | Regenerated | Reused -> false

let count_lines lines =
  let counts = Hashtbl.create (List.length lines) in
  List.iter
    (fun line ->
      let count =
        match Hashtbl.find_opt counts line with
        | Some count -> count + 1
        | None -> 1
      in
      Hashtbl.replace counts line count)
    lines;
  counts

let changed_fingerprint_lines previous current =
  let previous_counts = count_lines previous in
  let current_counts = count_lines current in
  let ordered = String_util.dedup_preserve (previous @ current) in
  List.filter
    (fun line ->
      let previous_count =
        match Hashtbl.find_opt previous_counts line with
        | Some count -> count
        | None -> 0
      in
      let current_count =
        match Hashtbl.find_opt current_counts line with
        | Some count -> count
        | None -> 0
      in
      previous_count <> current_count)
    ordered

let reason_of_fingerprint_line line =
  match String_util.split_whitespace line with
  | "compiler" :: _ -> Some "compiler version changed"
  | "backend" :: _ -> Some "selected backend changed"
  | "profile" :: _ -> Some "profile changed"
  | "manifest" :: _ -> Some "workspace manifest changed"
  | "kind" :: _ -> Some "target kind changed"
  | "target" :: _ -> Some "target name changed"
  | "dir" :: _ -> Some "target directory changed"
  | "main" :: _ -> Some "entry module changed"
  | "module" :: _ -> Some "inferred module order changed"
  | "tool" :: tool :: _ -> Some ("toolchain resolution changed: " ^ tool)
  | "package" :: package_name :: _ ->
      Some ("package resolution changed: " ^ package_name)
  | "ml" :: relative_path :: _ -> Some ("source changed: " ^ relative_path)
  | "mli" :: relative_path :: rest ->
      if List.mem "missing" rest then
        Some ("interface availability changed: " ^ relative_path)
      else Some ("interface changed: " ^ relative_path)
  | "dep" :: dependency_name :: _ ->
      Some ("dependency changed: " ^ dependency_name)
  | "compile-flag" :: _ -> Some "compile flags changed"
  | "link-flag" :: _ -> Some "link flags changed"
  | "env" :: binding_parts ->
      Some ("environment changed: " ^ String.concat " " binding_parts)
  | "preprocess" :: tool_name :: _ ->
      Some ("preprocessor pipeline changed: " ^ tool_name)
  | "preprocess-cwd" :: _ -> Some "preprocessor working directory changed"
  | "preprocess-env" :: tool_name :: _ ->
      Some ("preprocessor environment changed: " ^ tool_name)
  | "preprocess-dep" :: tool_name :: relative_path :: _ ->
      Some
        (Printf.sprintf "preprocessor auxiliary input changed: %s (%s)"
           relative_path tool_name)
  | "ppx" :: tool_name :: _ -> Some ("ppx pipeline changed: " ^ tool_name)
  | "ppx-dep" :: tool_name :: relative_path :: _ ->
      Some
        (Printf.sprintf "ppx auxiliary input changed: %s (%s)" relative_path
           tool_name)
  | "action" :: action_name :: _ -> Some ("action changed: " ^ action_name)
  | "sandbox" :: _ -> Some "sandbox mode changed"
  | "argv" :: _ | "arg" :: _ | "prog-digest" :: _ ->
      Some "tool invocation changed"
  | _ -> None

let fingerprint_reasons previous current =
  let changed_lines =
    changed_fingerprint_lines
      (String_util.split_lines previous)
      (String_util.split_lines current)
  in
  let reasons =
    List.filter_map reason_of_fingerprint_line changed_lines
    |> String_util.dedup_preserve
  in
  if reasons = [] && previous <> current then [ "recorded inputs changed" ]
  else reasons

let evaluate_target ~stamp_path ~expected_outputs ~fingerprint =
  let missing_outputs = List.filter (fun path -> not (Fs.exists path)) expected_outputs in
  if Fs.exists stamp_path && missing_outputs = [] && Fs.read_file stamp_path = fingerprint
  then
    {
      build_status = Reused;
      reasons = [ "inputs and outputs matched the recorded fingerprint" ];
    }
  else
    let reasons =
      (if Fs.exists stamp_path then [] else [ "previous build stamp missing" ])
      @ List.map (fun path -> "missing output: " ^ path) missing_outputs
      @
      if Fs.exists stamp_path then
        fingerprint_reasons (Fs.read_file stamp_path) fingerprint
      else []
    in
    {
      build_status = Rebuilt;
      reasons =
        (match String_util.dedup_preserve reasons with
        | [] -> [ "recorded inputs changed" ]
        | reasons -> reasons);
    }

let render_section title items =
  let items = if items = [] then [ "none" ] else items in
  (title ^ ":") :: List.map (fun item -> "- " ^ item) items

let render_report ~kind_name ~target_name ~profile ~status ~out_dir ~artifact
    ~resolution_lines ~include_dirs ~module_order ~command_lines =
  String.concat "\n"
    ([
       "Target: " ^ target_name;
       "Kind: " ^ kind_name;
       "Profile: " ^ profile;
       "State: " ^ status_name status.build_status;
       "Artifact: " ^ artifact;
       "Output-dir: " ^ out_dir;
       "";
     ]
    @ render_section "Reasons" status.reasons
    @ [ "" ]
    @ render_section "Resolution" resolution_lines
    @ [ "" ]
    @ render_section "Include-dirs" include_dirs
    @ [ "" ]
    @ render_section "Module-order" module_order
    @ [ "" ]
    @ render_section "Commands" command_lines)

let json_string text = "\"" ^ String_util.json_escape text ^ "\""

let json_array items = "[" ^ String.concat ", " items ^ "]"

let render_json_report ~kind_name ~target_name ~profile ~status ~out_dir
    ~artifact ~resolution_lines ~include_dirs ~module_order ~command_lines =
  String.concat "\n"
    [
      "{";
      "  \"target\": " ^ json_string target_name ^ ",";
      "  \"kind\": " ^ json_string kind_name ^ ",";
      "  \"profile\": " ^ json_string profile ^ ",";
      "  \"state\": " ^ json_string (status_name status.build_status) ^ ",";
      "  \"artifact\": " ^ json_string artifact ^ ",";
      "  \"output_dir\": " ^ json_string out_dir ^ ",";
      "  \"reasons\": "
      ^ json_array (List.map json_string status.reasons)
      ^ ",";
      "  \"resolution\": "
      ^ json_array (List.map json_string resolution_lines)
      ^ ",";
      "  \"include_dirs\": "
      ^ json_array (List.map json_string include_dirs)
      ^ ",";
      "  \"module_order\": "
      ^ json_array (List.map json_string module_order)
      ^ ",";
      "  \"commands\": "
      ^ json_array (List.map json_string command_lines);
      "}";
      "";
    ]

let load_report path = Fs.read_file path
